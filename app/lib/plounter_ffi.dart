/// Hand-written dart:ffi bindings for the plounter core C API
/// (core/include/plounter/plounter.h). The API is small enough that
/// ffigen would be more machinery than it saves.
library;

import 'dart:ffi';
import 'dart:io';

final class _Detector extends Opaque {}

final class _Capture extends Opaque {}

DynamicLibrary _openCore() {
  // On Apple platforms the core is compiled into the plounter_native pod
  // (dynamic framework; falls back to process() for static linkage).
  if (Platform.isIOS || Platform.isMacOS) {
    try {
      return DynamicLibrary.open('plounter_native.framework/plounter_native');
    } on ArgumentError {
      return DynamicLibrary.process();
    }
  }
  final name = Platform.isWindows ? 'plounter.dll' : 'libplounter.so';
  // Bundled location first (runner rpath / loader path), then the local
  // core build for tests and development.
  final candidates = [
    name,
    '../core/build/$name',
    '../../core/build/$name',
  ];
  for (final path in candidates) {
    try {
      return DynamicLibrary.open(path);
    } on ArgumentError {
      continue;
    }
  }
  throw StateError(
      'plounter core library not found (tried: ${candidates.join(", ")})');
}

/// Thin OO wrapper over the C API. One instance per mic session is fine;
/// the detector itself is created once and reused across start/stop.
class Plounter {
  Plounter([this._sampleRate = 48000]) {
    _detector = _createDefault(_sampleRate);
    if (_detector == nullptr) {
      throw StateError('plounter_create_default failed');
    }
  }

  static final DynamicLibrary _lib = _openCore();

  static final _createDefault = _lib.lookupFunction<
      Pointer<_Detector> Function(Double),
      Pointer<_Detector> Function(double)>('plounter_create_default');
  static final _destroy = _lib.lookupFunction<
      Void Function(Pointer<_Detector>),
      void Function(Pointer<_Detector>)>('plounter_destroy');
  static final _totalCount = _lib.lookupFunction<
      Uint64 Function(Pointer<_Detector>),
      int Function(Pointer<_Detector>)>('plounter_total_count');
  static final _resetCount = _lib.lookupFunction<
      Void Function(Pointer<_Detector>),
      void Function(Pointer<_Detector>)>('plounter_reset_count');
  static final _setSensitivity = _lib.lookupFunction<
      Void Function(Pointer<_Detector>, Float),
      void Function(Pointer<_Detector>, double)>('plounter_set_sensitivity');
  static final _getSensitivity = _lib.lookupFunction<
      Float Function(Pointer<_Detector>),
      double Function(Pointer<_Detector>)>('plounter_get_sensitivity');
  static final _envelopeDb = _lib.lookupFunction<
      Float Function(Pointer<_Detector>),
      double Function(Pointer<_Detector>)>('plounter_envelope_db');
  static final _noiseFloorDb = _lib.lookupFunction<
      Float Function(Pointer<_Detector>),
      double Function(Pointer<_Detector>)>('plounter_noise_floor_db');
  static final _captureStart = _lib.lookupFunction<
      Pointer<_Capture> Function(Pointer<_Detector>, Double),
      Pointer<_Capture> Function(
          Pointer<_Detector>, double)>('plounter_capture_start');
  static final _captureStop = _lib.lookupFunction<
      Void Function(Pointer<_Capture>),
      void Function(Pointer<_Capture>)>('plounter_capture_stop');

  final double _sampleRate;
  late final Pointer<_Detector> _detector;
  Pointer<_Capture> _capture = nullptr;

  bool get isListening => _capture != nullptr;
  int get count => _totalCount(_detector);
  double get envelopeDb => _envelopeDb(_detector);
  double get noiseFloorDb => _noiseFloorDb(_detector);
  double get sensitivityDb => _getSensitivity(_detector);
  set sensitivityDb(double db) => _setSensitivity(_detector, db);

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

  void dispose() {
    stopListening();
    _destroy(_detector);
  }
}
