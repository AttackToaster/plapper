#include "../include/plounter/plounter.h"

#include <new>

#include "detector.hpp"

extern "C" {

struct plounter_detector {
  plounter::Detector impl;
};

plounter_config plounter_config_default(double sample_rate) {
  plounter_config c;
  c.sample_rate = sample_rate;
  c.sensitivity_db = 12.0f;
  c.hpf_hz = 1500.0f;
  c.refractory_ms = 30.0f;
  c.min_level_db = -60.0f;
  c.rise_db = 9.0f;
  c.rise_lookback_ms = 20.0f;
  c.band_ratio_min = 0.30f;
  c.zcr_min = 0.12f;
  c.warmup_ms = 300.0f;
  c.decay_check_ms = 50.0f;
  c.decay_drop_db = 4.0f;
  c.env_attack_ms = 1.0f;
  c.env_release_ms = 20.0f;
  c.rearm_drop_db = 6.0f;
  return c;
}

plounter_detector* plounter_create(const plounter_config* cfg) {
  if (!cfg || cfg->sample_rate <= 0.0) return nullptr;
  return new (std::nothrow) plounter_detector{plounter::Detector(*cfg)};
}

plounter_detector* plounter_create_default(double sample_rate) {
  const plounter_config cfg = plounter_config_default(sample_rate);
  return plounter_create(&cfg);
}

void plounter_destroy(plounter_detector* d) { delete d; }

int32_t plounter_process(plounter_detector* d, const float* mono, int32_t n) {
  if (!d || !mono || n <= 0) return 0;
  return d->impl.process(mono, n);
}

uint64_t plounter_total_count(const plounter_detector* d) {
  return d ? d->impl.totalCount() : 0;
}

void plounter_reset_count(plounter_detector* d) {
  if (d) d->impl.resetCount();
}

void plounter_debug_log(plounter_detector* d, int enable) {
  if (d) d->impl.setDebugLog(enable != 0);
}

void plounter_set_sensitivity(plounter_detector* d, float db) {
  if (d) d->impl.setSensitivity(db);
}

float plounter_get_sensitivity(const plounter_detector* d) {
  return d ? d->impl.sensitivity() : 0.0f;
}

void plounter_set_env_release(plounter_detector* d, float ms) {
  if (d) d->impl.setEnvRelease(ms);
}

float plounter_get_env_release(const plounter_detector* d) {
  return d ? d->impl.envRelease() : 0.0f;
}

float plounter_envelope_db(const plounter_detector* d) {
  return d ? d->impl.envelopeDb() : -120.0f;
}

float plounter_envelope_full_db(const plounter_detector* d) {
  return d ? d->impl.envelopeFullDb() : -120.0f;
}

float plounter_noise_floor_db(const plounter_detector* d) {
  return d ? d->impl.noiseFloorDb() : -120.0f;
}

}  // extern "C"
