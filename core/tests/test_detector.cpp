#include <catch2/catch_test_macros.hpp>

#include <cmath>
#include <random>
#include <vector>

#include "plounter/plounter.h"

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
int run(plounter_detector* d, const std::vector<float>& buf) {
  int total = 0;
  for (size_t i = 0; i < buf.size(); i += 512) {
    const int32_t n = int32_t(std::min<size_t>(512, buf.size() - i));
    total += plounter_process(d, buf.data() + i, n);
  }
  return total;
}

struct Fixture {
  plounter_config cfg = plounter_config_default(kSr);
  plounter_detector* d = nullptr;
  explicit Fixture(float sensitivity = 12.0f) {
    cfg.sensitivity_db = sensitivity;
    d = plounter_create(&cfg);
    REQUIRE(d != nullptr);
  }
  ~Fixture() { plounter_destroy(d); }
};

}  // namespace

TEST_CASE("single clap in quiet room counts once") {
  Fixture f;
  auto buf = silence(2.0, 3e-4f); /* ~-70 dBFS room tone */
  add_clap(buf, 1.0);
  CHECK(run(f.d, buf) == 1);
  CHECK(plounter_total_count(f.d) == 1);
}

TEST_CASE("five claps spaced 400 ms count as five") {
  Fixture f;
  auto buf = silence(4.0, 3e-4f);
  for (int i = 0; i < 5; ++i) add_clap(buf, 1.0 + 0.4 * i);
  CHECK(run(f.d, buf) == 5);
}

TEST_CASE("two claps 60 ms apart merge into one (refractory)") {
  Fixture f;
  auto buf = silence(2.0, 3e-4f);
  add_clap(buf, 1.0);
  add_clap(buf, 1.06);
  CHECK(run(f.d, buf) == 1);
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

TEST_CASE("counter reset and meter taps behave") {
  Fixture f;
  auto buf = silence(2.0, 3e-4f);
  add_clap(buf, 1.0);
  run(f.d, buf);
  CHECK(plounter_total_count(f.d) == 1);
  plounter_reset_count(f.d);
  CHECK(plounter_total_count(f.d) == 0);
  CHECK(plounter_envelope_db(f.d) < 0.0f);
  CHECK(plounter_noise_floor_db(f.d) < plounter_envelope_db(f.d) + 120.0f);
  plounter_set_sensitivity(f.d, 20.0f);
  CHECK(plounter_get_sensitivity(f.d) == 20.0f);
}
