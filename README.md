# Plounter

Counts your claps. Tunable sensitivity, adaptive noise floor, cross-platform
(Windows / macOS / Linux / Android / iOS).

## Layout

```
core/                       pure C++20 clap-detection DSP + miniaudio mic capture (CMake)
packages/plounter_native/   FFI plugin shell: builds + bundles core on every platform
app/                        Flutter UI, talks to core over dart:ffi
fixtures/                   recorded test audio (see fixtures/README.md)
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

## Platform wiring

All five platforms build the core through the `plounter_native` FFI plugin:

| Platform | Mechanism | Mic permission |
|----------|-----------|----------------|
| Linux    | plugin `linux/CMakeLists.txt` → `core/`, bundles `libplounter.so` | none needed |
| Windows  | plugin `windows/CMakeLists.txt` → `core/`, bundles `plounter.dll` | none needed |
| macOS    | pod compiles core via forwarder includes (`macos/Classes/`) | entitlement + usage string; system prompts |
| Android  | Gradle `externalNativeBuild` → `src/CMakeLists.txt` → `core/` | `RECORD_AUDIO` + runtime request (`permission_handler`) |
| iOS      | pod compiles core via forwarder includes (`ios/Classes/`) | usage string + runtime request (`permission_handler`) |

CI (`.github/workflows/`): `core.yml` runs the DSP unit tests on
Linux/macOS/Windows; `app.yml` analyzes, tests, and builds the app for all
five targets (iOS unsigned).
