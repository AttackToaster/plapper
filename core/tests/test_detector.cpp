#include <catch2/catch_test_macros.hpp>

#include <cmath>
#include <random>
#include <vector>

#include "plapper/plapper.h"

namespace {

constexpr double kSr = 48000.0;
constexpr float kPi = 3.14159265f;

/* Deterministic white noise source. */
struct Noise {
  std::mt19937 rng{1234};
  std::uniform_real_distribution<float> dist{-1.0f, 1.0f};
  float operator()() { return dist(rng); }
};

std::vector<float> silence(double seconds, float noiseAmp = 0.0f) {
  std::vector<float> v(size_t(seconds * kSr), 0.0f);
  if (noiseAmp > 0.0f) {
    Noise n;
    for (auto& s : v) s = n() * noiseAmp;
  }
  return v;
}

/* Synthetic clap: instantaneous broadband noise burst, exponential decay. */
void add_clap(std::vector<float>& buf, double atSeconds, float amp = 0.5f) {
  Noise n;
  const size_t start = size_t(atSeconds * kSr);
  const size_t len = size_t(0.080 * kSr);
  const float tau = float(0.015 * kSr);
  for (size_t i = 0; i < len && start + i < buf.size(); ++i) {
    buf[start + i] += amp * n() * std::exp(-float(i) / tau);
  }
}

void add_sine(std::vector<float>& buf, double atSeconds, double lenSeconds,
              float freq, float amp) {
  const size_t start = size_t(atSeconds * kSr);
  const size_t len = size_t(lenSeconds * kSr);
  for (size_t i = 0; i < len && start + i < buf.size(); ++i) {
    buf[start + i] += amp * std::sin(2.0f * kPi * freq * float(i) / float(kSr));
  }
}

/* Feed in 512-sample blocks like a real audio callback. */
int run(plapper_detector* d, const std::vector<float>& buf) {
  int total = 0;
  for (size_t i = 0; i < buf.size(); i += 512) {
    const int32_t n = int32_t(std::min<size_t>(512, buf.size() - i));
    total += plapper_process(d, buf.data() + i, n);
  }
  return total;
}

struct Fixture {
  plapper_config cfg = plapper_config_default(kSr);
  plapper_detector* d = nullptr;
  explicit Fixture(float sensitivity = 12.0f) {
    cfg.sensitivity_db = sensitivity;
    d = plapper_create(&cfg);
    REQUIRE(d != nullptr);
  }
  ~Fixture() { plapper_destroy(d); }
};

}  // namespace

TEST_CASE("single clap in quiet room counts once") {
  Fixture f;
  auto buf = silence(2.0, 3e-4f); /* ~-70 dBFS room tone */
  add_clap(buf, 1.0);
  CHECK(run(f.d, buf) == 1);
  CHECK(plapper_total_count(f.d) == 1);
}

TEST_CASE("five claps spaced 400 ms count as five") {
  Fixture f;
  auto buf = silence(4.0, 3e-4f);
  for (int i = 0; i < 5; ++i) add_clap(buf, 1.0 + 0.4 * i);
  CHECK(run(f.d, buf) == 5);
}

TEST_CASE("two claps 60 ms apart do not double-count") {
  /* 60 ms double hits are echo/flam territory, not two intentional claps. */
  Fixture f;
  auto buf = silence(2.0, 3e-4f);
  add_clap(buf, 1.0);
  add_clap(buf, 1.06);
  CHECK(run(f.d, buf) <= 1);
}

TEST_CASE("rapid clapping at ~7.7 Hz counts every clap") {
  Fixture f;
  auto buf = silence(3.0, 3e-4f);
  for (int i = 0; i < 5; ++i) add_clap(buf, 1.0 + 0.13 * i);
  CHECK(run(f.d, buf) == 5);
}

TEST_CASE("rapid LOUD clapping still retriggers (no threshold re-crossing)") {
  Fixture f;
  auto buf = silence(3.0, 3e-4f);
  for (int i = 0; i < 5; ++i) add_clap(buf, 1.0 + 0.15 * i, 0.9f);
  CHECK(run(f.d, buf) == 5);
}

TEST_CASE("claps 300 ms apart both count") {
  Fixture f;
  auto buf = silence(2.5, 3e-4f);
  add_clap(buf, 1.0);
  add_clap(buf, 1.3);
  CHECK(run(f.d, buf) == 2);
}

TEST_CASE("loud low tone never triggers") {
  Fixture f;
  auto buf = silence(3.0, 3e-4f);
  add_sine(buf, 1.0, 1.5, 440.0f, 0.7f);
  CHECK(run(f.d, buf) == 0);
}

TEST_CASE("slowly ramped broadband noise never triggers") {
  Fixture f;
  auto buf = silence(5.0, 0.0f);
  Noise n;
  const size_t rampStart = size_t(1.0 * kSr);
  const size_t rampLen = size_t(2.0 * kSr);
  for (size_t i = rampStart; i < buf.size(); ++i) {
    const float g = std::min(1.0f, float(i - rampStart) / float(rampLen));
    buf[i] = n() * 0.2f * g;
  }
  CHECK(run(f.d, buf) == 0);
}

TEST_CASE("clap over moderate background noise still counts") {
  Fixture f;
  auto buf = silence(3.0, 0.01f); /* ~-40 dBFS noise floor */
  add_clap(buf, 2.0, 0.6f);
  CHECK(run(f.d, buf) == 1);
}

TEST_CASE("sensitivity: high threshold rejects a soft clap, low accepts") {
  auto buf = silence(2.0, 3e-4f);
  add_clap(buf, 1.0, 0.02f); /* soft clap, ~36 dB over the room tone floor */
  {
    Fixture strict(40.0f);
    CHECK(run(strict.d, buf) == 0);
  }
  {
    Fixture lax(6.0f);
    CHECK(run(lax.d, buf) == 1);
  }
}

TEST_CASE("clap after long low-frequency room tone still counts") {
  /* Regression: the sliding ZCR counter once drifted negative on
   * LF-dominated input (wrong pair removed from the window), which
   * silently rejected every real clap. White-noise room tone masks it;
   * a mains-hum-style tone does not. */
  Fixture f;
  auto buf = silence(5.0, 0.0f);
  add_sine(buf, 0.0, 5.0, 60.0f, 3e-3f); /* ~-50 dBFS hum */
  add_clap(buf, 4.0, 0.4f);
  CHECK(run(f.d, buf) == 1);
}

TEST_CASE("counter reset and meter taps behave") {
  Fixture f;
  auto buf = silence(2.0, 3e-4f);
  add_clap(buf, 1.0);
  run(f.d, buf);
  CHECK(plapper_total_count(f.d) == 1);
  plapper_reset_count(f.d);
  CHECK(plapper_total_count(f.d) == 0);
  CHECK(plapper_envelope_db(f.d) < 0.0f);
  CHECK(plapper_noise_floor_db(f.d) < plapper_envelope_db(f.d) + 120.0f);
  plapper_set_sensitivity(f.d, 20.0f);
  CHECK(plapper_get_sensitivity(f.d) == 20.0f);
}
