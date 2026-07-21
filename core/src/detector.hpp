#pragma once
#include <atomic>
#include <array>
#include <cmath>
#include <cstdint>

/* Relative include keeps this buildable without include-path setup —
 * the iOS/macOS pods compile core via forwarder files where xcconfig
 * header search paths proved unreliable. */
#include "../include/plapper/plapper.h"

namespace plapper {

inline constexpr double kPi = 3.14159265358979323846;

inline float db_from_lin(float lin) { return 20.0f * std::log10(lin + 1e-12f); }

/* RBJ high-pass biquad, Q = 0.707. Two in cascade -> 4th order. */
class BiquadHP {
public:
  void prepare(double sampleRate, float cutoffHz) {
    const double w0 = 2.0 * kPi * cutoffHz / sampleRate;
    const double cw = std::cos(w0), sw = std::sin(w0);
    const double alpha = sw / (2.0 * 0.70710678);
    const double a0 = 1.0 + alpha;
    b0_ = float(((1.0 + cw) / 2.0) / a0);
    b1_ = float((-(1.0 + cw)) / a0);
    b2_ = b0_;
    a1_ = float((-2.0 * cw) / a0);
    a2_ = float((1.0 - alpha) / a0);
    z1_ = z2_ = 0.0f;
  }
  float process(float x) {
    const float y = b0_ * x + z1_;
    z1_ = b1_ * x - a1_ * y + z2_;
    z2_ = b2_ * x - a2_ * y;
    return y;
  }
private:
  float b0_ = 0, b1_ = 0, b2_ = 0, a1_ = 0, a2_ = 0, z1_ = 0, z2_ = 0;
};

/* One-pole peak envelope follower (attack/release in linear domain). */
class EnvFollower {
public:
  void prepare(double sr, float attackMs, float releaseMs) {
    sr_ = sr;
    atk_ = coef(sr, attackMs);
    rel_ = coef(sr, releaseMs);
    env_ = 0.0f;
  }
  void setRelease(float ms) { rel_ = coef(sr_, ms); }
  float process(float x) {
    const float a = std::fabs(x);
    const float c = a > env_ ? atk_ : rel_;
    env_ = c * env_ + (1.0f - c) * a;
    return env_;
  }
  float value() const { return env_; }
private:
  static float coef(double sr, float ms) {
    return std::exp(-1.0f / (float(sr) * ms * 0.001f));
  }
  double sr_ = 48000.0;
  float atk_ = 0, rel_ = 0, env_ = 0;
};

/* Onset flow: threshold crossing on the high-passed envelope arms a pending
 * confirm; kConfirmMs later the gates (attack speed, RMS band ratio, ZCR)
 * decide clap vs. not. The delay lets a tone-onset click flush out of the
 * short RMS window, so beeps with hard attacks don't count. */
class Detector {
public:
  explicit Detector(const plapper_config& cfg) : cfg_(cfg) { prepare(); }

  int32_t process(const float* mono, int32_t n);

  uint64_t totalCount() const { return count_.load(std::memory_order_relaxed); }
  void resetCount() { count_.store(0, std::memory_order_relaxed); }

  void setDebugLog(bool on) { debugLog_.store(on, std::memory_order_relaxed); }
  void setSensitivity(float db) { sensitivityDb_.store(db, std::memory_order_relaxed); }
  void setEnvRelease(float ms) { releaseMs_.store(ms, std::memory_order_relaxed); }
  float envRelease() const { return releaseMs_.load(std::memory_order_relaxed); }
  float sensitivity() const { return sensitivityDb_.load(std::memory_order_relaxed); }
  float envelopeDb() const { return envHpDbShared_.load(std::memory_order_relaxed); }
  float envelopeFullDb() const { return envFullDbShared_.load(std::memory_order_relaxed); }
  float noiseFloorDb() const { return floorDbShared_.load(std::memory_order_relaxed); }

private:
  static constexpr float kConfirmMs = 10.0f;

  void prepare();
  bool riseOk() const;

  plapper_config cfg_{};

  BiquadHP hp1_, hp2_;
  EnvFollower envHp_, envFull_;

  float floor_ = 1e-4f;            /* linear noise floor on detection band */
  float floorUp_ = 0, floorDown_ = 0;

  /* envelope history at 1 ms grid, for the attack-speed gate */
  static constexpr int kHist = 64;
  std::array<float, kHist> hist_{};
  int histPos_ = 0, histDecim_ = 0, histFilled_ = 0;
  int samplesPerMs_ = 48, lookbackSlots_ = 20;

  /* short raw-input window: zero-crossing rate + per-band RMS */
  static constexpr int kWin = 256;
  std::array<int8_t, kWin> signs_{};
  std::array<float, kWin> hpSq_{}, fullSq_{};
  double sumHpSq_ = 0.0, sumFullSq_ = 0.0;
  int winPos_ = 0, winFilled_ = 0, zcrCount_ = 0;

  int pending_ = 0, confirmSamples_ = 0;
  int decayPending_ = 0, decaySamples_ = 0;
  float envConfirmDb_ = 0.0f;
  int refractory_ = 0, refractorySamples_ = 0;
  int warmup_ = 0;
  /* Schmitt-style arming: a new candidate needs the envelope to have fallen
   * rearm_drop_db below the last event (or below threshold) first, so rapid
   * successive claps retrigger without a full threshold re-crossing. */
  bool armed_ = true;
  float rearmBelowDb_ = -200.0f;
  float appliedReleaseMs_ = 0.0f;

  std::atomic<bool> debugLog_{false};
  std::atomic<uint64_t> count_{0};
  std::atomic<float> sensitivityDb_{12.0f};
  std::atomic<float> releaseMs_{20.0f};
  std::atomic<float> envHpDbShared_{-120.0f};
  std::atomic<float> envFullDbShared_{-120.0f};
  std::atomic<float> floorDbShared_{-120.0f};
};

}  // namespace plapper
