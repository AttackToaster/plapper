// replay.dart — shareable session replays (".plap files") 💌
//
// A PlapSession captures one clapping session as a list of clap offsets.
// It round-trips through a compact shareable string:
//
//   PLAP1.<base64url(gzip(json))>
//
// so besties can paste each other's sessions and watch the plaps roll in.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../palette.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// One recorded clapping session, ready to share.
class PlapSession {
  const PlapSession({
    required this.version,
    required this.startedAt,
    required this.durationMs,
    required this.clapOffsetsMs,
  });

  /// Format version — bump when the schema changes.
  final int version;

  /// When the session started (stored as UTC ISO-8601).
  final DateTime startedAt;

  /// Total session length in milliseconds.
  final int durationMs;

  /// Milliseconds from [startedAt] at which each plap landed.
  final List<int> clapOffsetsMs;

  int get plapCount => clapOffsetsMs.length;

  Map<String, dynamic> toJson() => {
    'version': version,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'durationMs': durationMs,
    'clapOffsetsMs': clapOffsetsMs,
  };

  factory PlapSession.fromJson(Map<String, dynamic> json) => PlapSession(
    version: json['version'] as int,
    startedAt: DateTime.parse(json['startedAt'] as String),
    durationMs: json['durationMs'] as int,
    clapOffsetsMs: (json['clapOffsetsMs'] as List<dynamic>)
        .map((e) => e as int)
        .toList(),
  );
}

// ---------------------------------------------------------------------------
// Codec
// ---------------------------------------------------------------------------

const String _plapPrefix = 'PLAP1.';

/// Encodes a session as a shareable `PLAP1.` string (gzip + base64url).
String encodePlap(PlapSession s) {
  final jsonBytes = utf8.encode(jsonEncode(s.toJson()));
  final gzipped = GZipCodec(level: 9).encode(jsonBytes);
  return '$_plapPrefix${base64UrlEncode(gzipped)}';
}

/// Decodes a pasted `PLAP1.` string. Tolerant of surrounding whitespace and
/// missing base64 padding; returns null on anything that isn't a plap.
PlapSession? decodePlap(String data) {
  try {
    var text = data.trim();
    if (!text.startsWith(_plapPrefix)) return null;
    text = text.substring(_plapPrefix.length).trim();
    if (text.isEmpty) return null;
    final compressed = base64Url.decode(base64Url.normalize(text));
    final jsonBytes = GZipCodec().decode(compressed);
    final decoded = jsonDecode(utf8.decode(jsonBytes));
    if (decoded is! Map<String, dynamic>) return null;
    return PlapSession.fromJson(decoded);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// File helpers
// ---------------------------------------------------------------------------

String _two(int v) => v.toString().padLeft(2, '0');

/// Writes the session into [dir] as `plap-<yyyyMMdd-HHmmss>.plap`
/// (timestamped from [PlapSession.startedAt], local time).
Future<File> savePlapFile(PlapSession s, Directory dir) async {
  final t = s.startedAt.toLocal();
  final name =
      'plap-${t.year}${_two(t.month)}${_two(t.day)}'
      '-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}.plap';
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  return file.writeAsString(encodePlap(s));
}

/// Reads a `.plap` file; returns null if it's unreadable or not a plap.
PlapSession? loadPlapFile(File f) {
  try {
    return decodePlap(f.readAsStringSync());
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Replay sheet
// ---------------------------------------------------------------------------

/// Opens the animated replay sheet for [session].
/// [fromName] is shown when the session came from someone else.
void showReplaySheet(
  BuildContext context,
  Palette pal,
  PlapSession session, {
  String? fromName,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) =>
        _ReplaySheet(pal: pal, session: session, fromName: fromName),
  );
}

class _ReplaySheet extends StatefulWidget {
  const _ReplaySheet({required this.pal, required this.session, this.fromName});

  final Palette pal;
  final PlapSession session;
  final String? fromName;

  @override
  State<_ReplaySheet> createState() => _ReplaySheetState();
}

class _ReplaySheetState extends State<_ReplaySheet>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final List<int> _offsets;

  /// Session-milliseconds that pass per real-time millisecond, so long
  /// sessions replay in at most ~30 seconds.
  late final double _timeScale;

  double _playheadMs = 0;
  int _count = 0;
  bool _playing = true;
  bool _doubleSpeed = false;
  Duration _lastTick = Duration.zero;

  int get _durationMs => widget.session.durationMs;
  bool get _spedUp => _timeScale > 1.0;
  bool get _atEnd => _playheadMs >= _durationMs;

  @override
  void initState() {
    super.initState();
    _offsets = [...widget.session.clapOffsetsMs]..sort();
    _timeScale = _durationMs > 60000 ? _durationMs / 30000 : 1.0;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final deltaMs = (elapsed - _lastTick).inMicroseconds / 1000.0;
    _lastTick = elapsed;
    if (!_playing) return;
    setState(() {
      _playheadMs = (_playheadMs +
              deltaMs * _timeScale * (_doubleSpeed ? 2.0 : 1.0))
          .clamp(0.0, _durationMs.toDouble());
      while (_count < _offsets.length && _offsets[_count] <= _playheadMs) {
        _count++;
      }
      if (_atEnd) {
        _playing = false;
        _ticker.stop();
      }
    });
  }

  void _togglePlay() {
    setState(() {
      if (_playing) {
        _playing = false;
        _ticker.stop();
      } else {
        if (_atEnd) {
          _playheadMs = 0;
          _count = 0;
        }
        _playing = true;
        if (!_ticker.isActive) {
          _lastTick = Duration.zero;
          _ticker.start();
        }
      }
    });
  }

  void _restart() {
    setState(() {
      _playheadMs = 0;
      _count = 0;
      _playing = true;
      if (!_ticker.isActive) {
        _lastTick = Duration.zero;
        _ticker.start();
      }
    });
  }

  String _fmt(double ms) {
    final totalSec = (ms / 1000).floor();
    return '${_two(totalSec ~/ 60)}:${_two(totalSec % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final progress = _durationMs == 0
        ? 1.0
        : (_playheadMs / _durationMs).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pal.bgTop, pal.bgBottom],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'replay',
            style: TextStyle(fontFamily: 'Pacifico', fontSize: 22, color: pal.text),
          ),
          if (widget.fromName != null) ...[
            const SizedBox(height: 2),
            Text(
              'from ${widget.fromName} 💌',
              style: TextStyle(
                color: pal.textSoft,
                fontSize: 13,
                fontVariations: const [wghtSemi],
              ),
            ),
          ],
          if (_spedUp) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: pal.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'sped up ✨',
                style: TextStyle(
                  color: pal.accentDeep,
                  fontSize: 12,
                  fontVariations: const [wghtSemi],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            decoration: BoxDecoration(
              color: pal.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: pal.accent.withValues(alpha: 0.25)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (rect) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [pal.accentDeep, pal.secondary],
                  ).createShader(rect),
                  child: Text(
                    '$_count',
                    style: const TextStyle(
                      fontFamily: 'Quicksand',
                      fontSize: 96,
                      height: 1.05,
                      color: Colors.white,
                      fontVariations: [wghtBold],
                    ),
                  ),
                ),
                Text(
                  'plaps',
                  style: TextStyle(
                    color: pal.cardTextSoft,
                    fontSize: 14,
                    fontVariations: const [wghtSemi],
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: pal.accent,
                    backgroundColor: pal.accent.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _fmt(_playheadMs),
                      style: TextStyle(color: pal.cardTextSoft, fontSize: 12),
                    ),
                    Text(
                      _fmt(_durationMs.toDouble()),
                      style: TextStyle(color: pal.cardTextSoft, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _restart,
                      tooltip: 'from the top',
                      icon: Icon(
                        Icons.replay_rounded,
                        color: pal.accentDeep,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _togglePlay,
                      tooltip: _playing ? 'pause' : 'play',
                      icon: Icon(
                        _playing
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        color: pal.accent,
                        size: 52,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () =>
                          setState(() => _doubleSpeed = !_doubleSpeed),
                      style: TextButton.styleFrom(
                        foregroundColor: _doubleSpeed
                            ? pal.accentDeep
                            : pal.cardTextSoft,
                        backgroundColor: _doubleSpeed
                            ? pal.accent.withValues(alpha: 0.15)
                            : Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: const Text(
                        '2x',
                        style: TextStyle(
                          fontFamily: 'Quicksand',
                          fontSize: 15,
                          fontVariations: [wghtBold],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Import sheet
// ---------------------------------------------------------------------------

/// Opens the paste-a-code sheet; a valid code closes it and plays the replay.
void showPlapImportSheet(BuildContext context, Palette pal) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => _ImportSheet(
      pal: pal,
      onDecoded: (session) {
        Navigator.of(sheetContext).pop();
        showReplaySheet(context, pal, session);
      },
    ),
  );
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({required this.pal, required this.onDecoded});

  final Palette pal;
  final ValueChanged<PlapSession> onDecoded;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  final TextEditingController _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _tryDecode() {
    final session = decodePlap(_ctrl.text);
    if (session == null) {
      setState(() => _error = "hmm, that code doesn't look like plaps 🥺");
      return;
    }
    widget.onDecoded(session);
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pal.bgTop, pal.bgBottom],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'watch a replay',
            style: TextStyle(fontFamily: 'Pacifico', fontSize: 22, color: pal.text),
          ),
          const SizedBox(height: 4),
          Text(
            'paste a plap code from a bestie 💗',
            style: TextStyle(
              color: pal.textSoft,
              fontSize: 13,
              fontVariations: const [wghtSemi],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: pal.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: pal.accent.withValues(alpha: 0.25)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _ctrl,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  style: TextStyle(color: pal.cardText, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'PLAP1.…',
                    hintStyle: TextStyle(color: pal.cardTextSoft),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: pal.accent.withValues(alpha: 0.25),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: pal.accent, width: 2),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: pal.accentDeep,
                      fontSize: 12,
                      fontVariations: const [wghtSemi],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _tryDecode,
                  style: FilledButton.styleFrom(
                    backgroundColor: pal.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text(
                    'watch it 💖',
                    style: TextStyle(
                      fontFamily: 'Quicksand',
                      fontSize: 15,
                      fontVariations: [wghtBold],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
