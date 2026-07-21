/// FFI plugin shell for the plapper DSP core.
///
/// This package contains no Dart code on purpose: it exists so the Flutter
/// tooling builds and bundles the native `plapper` library on every
/// platform (see `src/CMakeLists.txt`, the podspecs, and `android/`).
/// The actual bindings live in the app (`app/lib/plapper_ffi.dart`).
library;
