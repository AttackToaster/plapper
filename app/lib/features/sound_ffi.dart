/// Hand-written dart:ffi bindings for the plapper sound C API
/// (core/include/plapper/plapper_sound.h): one-shot playback of the
/// bundled celebration chimes. Self-contained on purpose — mirrors the
/// library-loading pattern in plapper_ffi.dart without importing it.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

DynamicLibrary _openCore() {
  // On Apple platforms the core is compiled into the plapper_native pod
  // (dynamic framework; falls back to process() for static linkage).
  if (Platform.isIOS || Platform.isMacOS) {
    try {
      return DynamicLibrary.open('plapper_native.framework/plapper_native');
    } on ArgumentError {
      return DynamicLibrary.process();
    }
  }
  final name = Platform.isWindows ? 'plapper.dll' : 'libplapper.so';
  // Bundled location first (runner rpath / loader path), then the local
  // core build for tests and development.
  final candidates = [name, '../core/build/$name', '../../core/build/$name'];
  for (final path in candidates) {
    try {
      return DynamicLibrary.open(path);
    } on ArgumentError {
      continue;
    }
  }
  throw StateError(
    'plapper core library not found (tried: ${candidates.join(", ")})',
  );
}

/// Fire-and-forget playback of short sound files through the plapper core
/// (miniaudio engine on the C side). All failures are swallowed: a missing
/// audio device must never break a celebration.
class PlapperSound {
  PlapperSound._();

  static final DynamicLibrary _lib = _openCore();

  static final _play = _lib
      .lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
        'plapper_sound_play',
      );
  static final _shutdown = _lib
      .lookupFunction<Void Function(), void Function()>(
        'plapper_sound_shutdown',
      );

  /// Plays the file at [path] (a real filesystem path — see
  /// [materializeAsset]). Returns false on any failure.
  static bool play(String path) {
    try {
      final p = path.toNativeUtf8();
      try {
        return _play(p) != 0;
      } finally {
        malloc.free(p);
      }
    } catch (_) {
      return false;
    }
  }

  /// Tears down the native playback engine. Optional; playback lazily
  /// re-initializes afterwards.
  static void shutdown() {
    try {
      _shutdown();
    } catch (_) {
      // ignore: best-effort cleanup
    }
  }
}

/// Copies a bundled asset (e.g. 'assets/sounds/goal.wav') to the app support
/// directory once and returns its filesystem path — the C side can only play
/// real files, not Flutter bundle keys. Subsequent calls reuse the file.
Future<String> materializeAsset(String assetKey) async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/${assetKey.split('/').last}');
  if (!await file.exists()) {
    final data = await rootBundle.load(assetKey);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
  return file.path;
}
