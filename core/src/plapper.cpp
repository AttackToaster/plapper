#include "../include/plapper/plapper.h"

#include <new>

#include "detector.hpp"

extern "C" {

struct plapper_detector {
  plapper::Detector impl;
};

plapper_config plapper_config_default(double sample_rate) {
  plapper_config c;
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

plapper_detector* plapper_create(const plapper_config* cfg) {
  if (!cfg || cfg->sample_rate <= 0.0) return nullptr;
  return new (std::nothrow) plapper_detector{plapper::Detector(*cfg)};
}

plapper_detector* plapper_create_default(double sample_rate) {
  const plapper_config cfg = plapper_config_default(sample_rate);
  return plapper_create(&cfg);
}

void plapper_destroy(plapper_detector* d) { delete d; }

int32_t plapper_process(plapper_detector* d, const float* mono, int32_t n) {
  if (!d || !mono || n <= 0) return 0;
  return d->impl.process(mono, n);
}

uint64_t plapper_total_count(const plapper_detector* d) {
  return d ? d->impl.totalCount() : 0;
}

void plapper_reset_count(plapper_detector* d) {
  if (d) d->impl.resetCount();
}

void plapper_debug_log(plapper_detector* d, int enable) {
  if (d) d->impl.setDebugLog(enable != 0);
}

void plapper_set_sensitivity(plapper_detector* d, float db) {
  if (d) d->impl.setSensitivity(db);
}

float plapper_get_sensitivity(const plapper_detector* d) {
  return d ? d->impl.sensitivity() : 0.0f;
}

void plapper_set_env_release(plapper_detector* d, float ms) {
  if (d) d->impl.setEnvRelease(ms);
}

float plapper_get_env_release(const plapper_detector* d) {
  return d ? d->impl.envRelease() : 0.0f;
}

float plapper_envelope_db(const plapper_detector* d) {
  return d ? d->impl.envelopeDb() : -120.0f;
}

float plapper_envelope_full_db(const plapper_detector* d) {
  return d ? d->impl.envelopeFullDb() : -120.0f;
}

float plapper_noise_floor_db(const plapper_detector* d) {
  return d ? d->impl.noiseFloorDb() : -120.0f;
}

}  // extern "C"
