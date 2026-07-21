/// FFI plugin shell for the plounter DSP core.
///
/// This package contains no Dart code on purpose: it exists so the Flutter
/// tooling builds and bundles the native `plounter` library on every
/// platform (see `src/CMakeLists.txt`, the podspecs, and `android/`).
/// The actual bindings live in the app (`app/lib/plounter_ffi.dart`).
library;
