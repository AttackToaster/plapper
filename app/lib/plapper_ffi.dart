/// Hand-written dart:ffi bindings for the plapper core C API
/// (core/include/plapper/plapper.h). The API is small enough that
/// ffigen would be more machinery than it saves.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _Detector extends Opaque {}

final class _Capture extends Opaque {}

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

/// Thin OO wrapper over the C API. One instance per mic session is fine;
/// the detector itself is created once and reused across start/stop.
class Plapper {
  Plapper([this._sampleRate = 48000]) {
    _detector = _createDefault(_sampleRate);
    if (_detector == nullptr) {
      throw StateError('plapper_create_default failed');
    }
  }

  static final DynamicLibrary _lib = _openCore();

  static final _createDefault = _lib
      .lookupFunction<
        Pointer<_Detector> Function(Double),
        Pointer<_Detector> Function(double)
      >('plapper_create_default');
  static final _destroy = _lib
      .lookupFunction<
        Void Function(Pointer<_Detector>),
        void Function(Pointer<_Detector>)
      >('plapper_destroy');
  static final _totalCount = _lib
      .lookupFunction<
        Uint64 Function(Pointer<_Detector>),
        int Function(Pointer<_Detector>)
      >('plapper_total_count');
  static final _resetCount = _lib
      .lookupFunction<
        Void Function(Pointer<_Detector>),
        void Function(Pointer<_Detector>)
      >('plapper_reset_count');
  static final _setSensitivity = _lib
      .lookupFunction<
        Void Function(Pointer<_Detector>, Float),
        void Function(Pointer<_Detector>, double)
      >('plapper_set_sensitivity');
  static final _getSensitivity = _lib
      .lookupFunction<
        Float Function(Pointer<_Detector>),
        double Function(Pointer<_Detector>)
      >('plapper_get_sensitivity');
  static final _setEnvRelease = _lib
      .lookupFunction<
        Void Function(Pointer<_Detector>, Float),
        void Function(Pointer<_Detector>, double)
      >('plapper_set_env_release');
  static final _getEnvRelease = _lib
      .lookupFunction<
        Float Function(Pointer<_Detector>),
        double Function(Pointer<_Detector>)
      >('plapper_get_env_release');
  static final _envelopeDb = _lib
      .lookupFunction<
        Float Function(Pointer<_Detector>),
        double Function(Pointer<_Detector>)
      >('plapper_envelope_db');
  static final _noiseFloorDb = _lib
      .lookupFunction<
        Float Function(Pointer<_Detector>),
        double Function(Pointer<_Detector>)
      >('plapper_noise_floor_db');
  static final _captureStart = _lib
      .lookupFunction<
        Pointer<_Capture> Function(Pointer<_Detector>, Double),
        Pointer<_Capture> Function(Pointer<_Detector>, double)
      >('plapper_capture_start');
  static final _captureStop = _lib
      .lookupFunction<
        Void Function(Pointer<_Capture>),
        void Function(Pointer<_Capture>)
      >('plapper_capture_stop');
  static final _recordStart = _lib
      .lookupFunction<
        Int32 Function(Pointer<_Capture>, Pointer<Utf8>),
        int Function(Pointer<_Capture>, Pointer<Utf8>)
      >('plapper_capture_record_start');
  static final _recordStop = _lib
      .lookupFunction<
        Void Function(Pointer<_Capture>),
        void Function(Pointer<_Capture>)
      >('plapper_capture_record_stop');
  static final _isRecording = _lib
      .lookupFunction<
        Int32 Function(Pointer<_Capture>),
        int Function(Pointer<_Capture>)
      >('plapper_capture_is_recording');

  final double _sampleRate;
  late final Pointer<_Detector> _detector;
  Pointer<_Capture> _capture = nullptr;

  bool get isListening => _capture != nullptr;
  int get count => _totalCount(_detector);
  double get envelopeDb => _envelopeDb(_detector);
  double get noiseFloorDb => _noiseFloorDb(_detector);
  double get sensitivityDb => _getSensitivity(_detector);
  set sensitivityDb(double db) => _setSensitivity(_detector, db);
  double get envReleaseMs => _getEnvRelease(_detector);
  set envReleaseMs(double ms) => _setEnvRelease(_detector, ms);

  /// Opens the default mic and starts feeding the detector.
  /// Returns false if the device could not be opened.
  bool startListening() {
    if (isListening) return true;
    _capture = _captureStart(_detector, _sampleRate);
    return isListening;
  }

  void stopListening() {
    if (!isListening) return;
    _captureStop(_capture);
    _capture = nullptr;
  }

  void resetCount() => _resetCount(_detector);

  bool get isRecording => isListening && _isRecording(_capture) != 0;

  /// Starts writing a 16-bit mono WAV to [path]. Requires an active
  /// listening session; recording stops automatically with it.
  bool startRecording(String path) {
    if (!isListening) return false;
    final p = path.toNativeUtf8();
    try {
      return _recordStart(_capture, p) != 0;
    } finally {
      malloc.free(p);
    }
  }

  void stopRecording() {
    if (isListening) _recordStop(_capture);
  }

  void dispose() {
    stopListening();
    _destroy(_detector);
  }
}
