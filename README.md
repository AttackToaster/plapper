# Plounter

Counts your claps. Tunable sensitivity, adaptive noise floor, cross-platform
(Windows / macOS / Linux / Android / iOS).

## Layout

```
core/       pure C++20 clap-detection DSP + miniaudio mic capture (CMake)
app/        Flutter UI, talks to core over dart:ffi
fixtures/   recorded test audio (see fixtures/README.md)
```

## How detection works

1. 4th-order high-pass at 1.5 kHz isolates the clap band.
2. Fast peak envelope on that band; a slow asymmetric EMA tracks the room
   noise floor (rises with tau ~2.5 s, falls with tau ~80 ms).
3. A threshold crossing (floor + sensitivity dB) arms a *pending confirm*.
4. 10 ms later three gates decide clap vs. not:
   - **attack speed** — envelope must have risen >= 9 dB vs. 20 ms ago
     (rejects slowly swelling noise);
   - **band ratio** — short-window RMS of high band / full band >= 0.30
     (rejects tonal onsets; the 10 ms delay lets the onset click flush out
     of the RMS window);
   - **zero-crossing rate** — raw-input ZCR >= 0.12 (claps are broadband).
5. A 180 ms refractory suppresses double counts from one physical clap.

Sensitivity is the dB offset over the noise floor (3 = hair trigger,
40 = only loud claps), adjustable live from the UI.

## Build

Core + tests:

```sh
cmake -S core -B core/build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build core/build && ./core/build/plounter_tests
```

App (bundles the core automatically on Linux):

```sh
cd app && flutter run -d linux
```

## Platform wiring status

| Platform | Core build wired | Notes |
|----------|-----------------|-------|
| Linux    | yes             | `app/linux/CMakeLists.txt` adds `core/` and bundles `libplounter.so` |
| Windows  | not yet         | mirror the Linux approach in `app/windows/CMakeLists.txt` |
| macOS    | not yet         | add core as an Xcode dependency or prebuilt dylib |
| Android  | not yet         | Gradle `externalNativeBuild` + mic permission in the manifest |
| iOS      | not yet         | static lib + `DynamicLibrary.process()` (already handled in Dart) |

Mobile also needs runtime mic-permission requests (e.g. `permission_handler`)
before `startListening()`.
