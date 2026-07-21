/* plapper core — clap detection C API.
 * Pure DSP: push mono float samples in, get clap counts out.
 * This header is the FFI surface consumed by the Flutter app (ffigen). */
#ifndef PLAPPER_H
#define PLAPPER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(PLAPPER_SHARED)
  #ifdef PLAPPER_BUILDING
    #define PLAPPER_API __declspec(dllexport)
  #else
    #define PLAPPER_API __declspec(dllimport)
  #endif
#else
  #define PLAPPER_API __attribute__((visibility("default")))
#endif

typedef struct plapper_detector plapper_detector;

typedef struct plapper_config {
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
  float decay_check_ms;    /* claps must decay; sustained noise (fans, ...) must not count */
  float decay_drop_db;     /* required envelope drop at decay_check_ms after confirm */
  float env_attack_ms;     /* detection envelope attack */
  float env_release_ms;    /* detection envelope release ("smoothing"); lower = faster re-arm */
  float rearm_drop_db;     /* envelope must fall this far below the last event to re-arm */
} plapper_config;

PLAPPER_API plapper_config plapper_config_default(double sample_rate);

PLAPPER_API plapper_detector* plapper_create(const plapper_config* cfg);
/* Convenience for FFI callers: default config at the given sample rate. */
PLAPPER_API plapper_detector* plapper_create_default(double sample_rate);
PLAPPER_API void plapper_destroy(plapper_detector* d);

/* Process a block of mono float samples. Returns claps detected in this block.
 * Real-time safe: no allocation, no locks. */
PLAPPER_API int32_t plapper_process(plapper_detector* d, const float* mono, int32_t num_samples);

PLAPPER_API uint64_t plapper_total_count(const plapper_detector* d);
PLAPPER_API void plapper_reset_count(plapper_detector* d);

/* Live tuning + UI meter taps. Safe to call from a different thread than process(). */
/* Diagnostic: when enabled, every threshold crossing logs its gate values
 * (rise, band ratio, ZCR, verdict) to stderr from the audio thread. */
PLAPPER_API void plapper_debug_log(plapper_detector* d, int enable);

PLAPPER_API void plapper_set_sensitivity(plapper_detector* d, float db);
PLAPPER_API float plapper_get_sensitivity(const plapper_detector* d);
PLAPPER_API void plapper_set_env_release(plapper_detector* d, float ms);
PLAPPER_API float plapper_get_env_release(const plapper_detector* d);
PLAPPER_API float plapper_envelope_db(const plapper_detector* d);    /* detection-band envelope, dBFS */
PLAPPER_API float plapper_envelope_full_db(const plapper_detector* d); /* full-band envelope, dBFS */
PLAPPER_API float plapper_noise_floor_db(const plapper_detector* d); /* adaptive floor, dBFS */

#ifdef __cplusplus
}
#endif
#endif /* PLAPPER_H */
