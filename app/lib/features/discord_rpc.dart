import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Dependency-free Discord Rich Presence client over Discord's local IPC
/// socket. Desktop only (Linux + macOS); pure `dart:io`, no packages.
///
/// ## Setup
///
/// 1. Create an application at <https://discord.com/developers/applications>
///    (suggested name: `plapper` — the app name is what Discord shows as
///    "Playing ...").
/// 2. Copy its **Application ID** and pass it as [clientId].
///
/// ## Usage
///
/// ```dart
/// final rpc = DiscordRpc('YOUR_APPLICATION_ID');
/// await rpc.connect(); // false if Discord isn't running — never throws
/// await rpc.setActivity(
///   details: 'listening for claps',
///   state: '42 plaps this session',
///   start: DateTime.now(),
/// );
/// await rpc.clearActivity();
/// await rpc.dispose();
/// ```
///
/// Every socket error is swallowed: the app must never care whether Discord
/// is installed, running, or died mid-session. If the socket dies,
/// [connected] flips to `false` and later calls become no-ops; call
/// [connect] again at any time to retry.
///
/// Windows uses named pipes for Discord IPC, which `dart:io` sockets cannot
/// open — on Windows this class no-ops gracefully ([connect] returns
/// `false`).
class DiscordRpc {
  DiscordRpc(this.clientId);

  /// Application ID from the Discord developer portal.
  final String clientId;

  static const _opHandshake = 0;
  static const _opFrame = 1;
  static const _handshakeTimeout = Duration(seconds: 2);
  static const _connectTimeout = Duration(milliseconds: 500);

  Socket? _socket;
  bool _connected = false;
  int _nonce = 0;
  final BytesBuilder _inbox = BytesBuilder();
  Completer<bool>? _handshake;

  /// Whether a handshaken IPC connection is currently alive.
  bool get connected => _connected;

  /// Tries every known Discord IPC socket path and handshakes on the first
  /// one that answers. Returns `false` if Discord is absent. Never throws,
  /// and is safe to call repeatedly (each call starts from a clean slate).
  Future<bool> connect() async {
    _dropSocket();
    if (!Platform.isLinux && !Platform.isMacOS) return false;
    for (final path in _candidateSocketPaths()) {
      Socket socket;
      try {
        socket = await Socket.connect(
          InternetAddress(path, type: InternetAddressType.unix),
          0,
          timeout: _connectTimeout,
        );
      } catch (_) {
        continue; // Socket file absent/stale — try the next candidate.
      }
      if (await _handshakeOn(socket)) {
        _connected = true;
        return true;
      }
      _dropSocket();
    }
    return false;
  }

  /// Publishes an activity. Null fields are omitted from the payload.
  /// No-op when not [connected].
  Future<void> setActivity({
    String? details,
    String? state,
    DateTime? start,
  }) async {
    if (!_connected) return;
    _sendActivity(<String, Object?>{
      'details': ?details,
      'state': ?state,
      if (start != null)
        'timestamps': <String, Object?>{
          'start': start.toUtc().millisecondsSinceEpoch ~/ 1000,
        },
    });
  }

  /// Clears the presence (SET_ACTIVITY with a null activity).
  /// No-op when not [connected].
  Future<void> clearActivity() async {
    if (!_connected) return;
    _sendActivity(null);
  }

  /// Closes the socket and forgets it. Safe to call at any time; [connect]
  /// may be called again afterwards.
  Future<void> dispose() async {
    _dropSocket();
  }

  // ---------------------------------------------------------------- wire --

  /// Candidate unix socket paths, most likely first. Linux checks
  /// `$XDG_RUNTIME_DIR`, `/tmp`, then the flatpak and snap sandboxes;
  /// macOS checks `$TMPDIR`.
  Iterable<String> _candidateSocketPaths() sync* {
    String strip(String dir) =>
        dir.endsWith('/') ? dir.substring(0, dir.length - 1) : dir;
    final dirs = <String>[];
    if (Platform.isMacOS) {
      final tmp = Platform.environment['TMPDIR'];
      if (tmp != null && tmp.isNotEmpty) dirs.add(strip(tmp));
    } else {
      final runtime = Platform.environment['XDG_RUNTIME_DIR'];
      final run = (runtime == null || runtime.isEmpty) ? null : strip(runtime);
      dirs.addAll(<String>[
        ?run,
        '/tmp',
        if (run != null) '$run/app/com.discordapp.Discord',
        if (run != null) '$run/snap.discord',
      ]);
    }
    for (final dir in dirs) {
      for (var n = 0; n < 10; n++) {
        yield '$dir/discord-ipc-$n';
      }
    }
  }

  /// Sends the op-0 handshake on [socket] and waits (2 s) for any complete
  /// frame back — Discord answers a good handshake with a DISPATCH/READY
  /// frame, and any well-formed reply proves the client is alive.
  Future<bool> _handshakeOn(Socket socket) async {
    _socket = socket;
    _inbox.clear();
    final handshake = _handshake = Completer<bool>();
    // Write errors (e.g. broken pipe when Discord quits) surface on
    // `socket.done`, not on the write call itself — drain them here so they
    // can never become unhandled async exceptions, and drop the socket.
    unawaited(socket.done.then<void>(
      (_) => _dropSocket(),
      onError: (Object _) => _dropSocket(),
    ));
    socket.listen(
      _onData,
      onError: (Object _) => _dropSocket(),
      onDone: _dropSocket,
      cancelOnError: true,
    );
    if (!_send(_opHandshake, <String, Object?>{'v': 1, 'client_id': clientId})) {
      return false;
    }
    return handshake.future.timeout(_handshakeTimeout, onTimeout: () => false);
  }

  void _sendActivity(Map<String, Object?>? activity) {
    _send(_opFrame, <String, Object?>{
      'cmd': 'SET_ACTIVITY',
      'args': <String, Object?>{'pid': pid, 'activity': activity},
      'nonce': '${DateTime.now().microsecondsSinceEpoch}-${_nonce++}',
    });
  }

  /// Writes one frame: little-endian int32 opcode, little-endian int32
  /// payload length, UTF-8 JSON payload. Any failure drops the socket.
  bool _send(int opcode, Map<String, Object?> payload) {
    final socket = _socket;
    if (socket == null) return false;
    try {
      final body = utf8.encode(jsonEncode(payload));
      final header = ByteData(8)
        ..setUint32(0, opcode, Endian.little)
        ..setUint32(4, body.length, Endian.little);
      socket.add(header.buffer.asUint8List());
      socket.add(body);
      return true;
    } catch (_) {
      _dropSocket();
      return false;
    }
  }

  /// Minimal frame parser: buffers incoming bytes, pops complete frames and
  /// discards their payloads. The only thing anyone waits on is "a full
  /// frame arrived", which completes the pending handshake.
  void _onData(Uint8List chunk) {
    _inbox.add(chunk);
    final bytes = _inbox.takeBytes();
    var offset = 0;
    while (bytes.length - offset >= 8) {
      final header = ByteData.sublistView(bytes, offset, offset + 8);
      final length = header.getUint32(4, Endian.little);
      if (bytes.length - offset - 8 < length) break; // partial frame
      offset += 8 + length;
      final handshake = _handshake;
      if (handshake != null && !handshake.isCompleted) {
        handshake.complete(true);
      }
    }
    if (offset < bytes.length) {
      _inbox.add(Uint8List.sublistView(bytes, offset));
    }
  }

  /// Tears down the socket and flips [connected] to false. Also fails any
  /// handshake still in flight so [connect] can move on to the next path.
  void _dropSocket() {
    _connected = false;
    final handshake = _handshake;
    _handshake = null;
    if (handshake != null && !handshake.isCompleted) {
      handshake.complete(false);
    }
    try {
      _socket?.destroy();
    } catch (_) {
      // Nothing to do — the socket is gone either way.
    }
    _socket = null;
    _inbox.clear();
  }
}
