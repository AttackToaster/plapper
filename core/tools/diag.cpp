// Live diagnostic: capture from the default mic for N seconds, log every
// threshold crossing's gate values (via plounter_debug_log) plus a 1 s
// status line of envelope / floor / count.
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <thread>

#include "../include/plounter/plounter.h"
#include "../include/plounter/plounter_capture.h"

int main(int argc, char** argv) {
  const int seconds = argc > 1 ? std::atoi(argv[1]) : 15;

  plounter_detector* d = plounter_create_default(48000.0);
  if (!d) { std::fprintf(stderr, "detector create failed\n"); return 1; }
  plounter_debug_log(d, 1);

  plounter_capture* c = plounter_capture_start(d, 48000.0);
  if (!c) { std::fprintf(stderr, "capture start failed\n"); return 1; }

  std::fprintf(stderr, "listening %d s... clap!\n", seconds);
  for (int t = 0; t < seconds; ++t) {
    std::this_thread::sleep_for(std::chrono::seconds(1));
    std::fprintf(stderr,
                 "t=%2ds hp=%6.1f dB  full=%6.1f dB  floor=%6.1f dB  count=%llu\n",
                 t + 1, plounter_envelope_db(d), plounter_envelope_full_db(d),
                 plounter_noise_floor_db(d),
                 (unsigned long long)plounter_total_count(d));
  }

  plounter_capture_stop(c);
  const unsigned long long n = plounter_total_count(d);
  plounter_destroy(d);
  std::fprintf(stderr, "total claps: %llu\n", n);
  return 0;
}
