/* plounter core — clap detection C API.
 * Pure DSP: push mono float samples in, get clap counts out.
 * This header is the FFI surface consumed by the Flutter app (ffigen). */
#ifndef PLOUNTER_H
#define PLOUNTER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(PLOUNTER_SHARED)
  #ifdef PLOUNTER_BUILDING
    #define PLOUNTER_API __declspec(dllexport)
  #else
    #define PLOUNTER_API __declspec(dllimport)
  #endif
#else
  #define PLOUNTER_API __attribute__((visibility("default")))
#endif

typedef struct plounter_detector plounter_detector;

typedef struct plounter_config {
  double sample_rate;      /* Hz, e.g. 48000 */
  float sensitivity_db;    /* trigger threshold above noise floor, dB. lower = more sensitive */
  float hpf_hz;            /* high-pass cutoff for the detection band */
  float refractory_ms;     /* lockout after a count; suppresses double-counts */
  float min_level_db;      /* absolute gate: never trigger below this dBFS */
  float rise_db;           /* required envelope rise vs. rise_lookback_ms ago */
  float rise_lookback_ms;
  float band_ratio_min;    /* high-band / full-band envelope ratio gate (broadbandness) */
  float zcr_min;           /* zero-crossing-rate gate on raw input (0..0.5) */
  float warmup_ms;         /* no triggers until the noise floor has settled */
} plounter_config;

PLOUNTER_API plounter_config plounter_config_default(double sample_rate);

PLOUNTER_API plounter_detector* plounter_create(const plounter_config* cfg);
/* Convenience for FFI callers: default config at the given sample rate. */
PLOUNTER_API plounter_detector* plounter_create_default(double sample_rate);
PLOUNTER_API void plounter_destroy(plounter_detector* d);

/* Process a block of mono float samples. Returns claps detected in this block.
 * Real-time safe: no allocation, no locks. */
PLOUNTER_API int32_t plounter_process(plounter_detector* d, const float* mono, int32_t num_samples);

PLOUNTER_API uint64_t plounter_total_count(const plounter_detector* d);
PLOUNTER_API void plounter_reset_count(plounter_detector* d);

/* Live tuning + UI meter taps. Safe to call from a different thread than process(). */
PLOUNTER_API void plounter_set_sensitivity(plounter_detector* d, float db);
PLOUNTER_API float plounter_get_sensitivity(const plounter_detector* d);
PLOUNTER_API float plounter_envelope_db(const plounter_detector* d);    /* detection-band envelope, dBFS */
PLOUNTER_API float plounter_noise_floor_db(const plounter_detector* d); /* adaptive floor, dBFS */

#ifdef __cplusplus
}
#endif
#endif /* PLOUNTER_H */
