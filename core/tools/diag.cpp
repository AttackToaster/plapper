// Live diagnostic: capture from the default mic for N seconds, log every
// threshold crossing's gate values (via plapper_debug_log) plus a 1 s
// status line of envelope / floor / count.
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <thread>

#include "../include/plapper/plapper.h"
#include "../include/plapper/plapper_capture.h"

int main(int argc, char** argv) {
  const int seconds = argc > 1 ? std::atoi(argv[1]) : 15;

  plapper_detector* d = plapper_create_default(48000.0);
  if (!d) { std::fprintf(stderr, "detector create failed\n"); return 1; }
  plapper_debug_log(d, 1);

  plapper_capture* c = plapper_capture_start(d, 48000.0);
  if (!c) { std::fprintf(stderr, "capture start failed\n"); return 1; }

  std::fprintf(stderr, "listening %d s... clap!\n", seconds);
  for (int t = 0; t < seconds; ++t) {
    std::this_thread::sleep_for(std::chrono::seconds(1));
    std::fprintf(stderr,
                 "t=%2ds hp=%6.1f dB  full=%6.1f dB  floor=%6.1f dB  count=%llu\n",
                 t + 1, plapper_envelope_db(d), plapper_envelope_full_db(d),
                 plapper_noise_floor_db(d),
                 (unsigned long long)plapper_total_count(d));
  }

  plapper_capture_stop(c);
  const unsigned long long n = plapper_total_count(d);
  plapper_destroy(d);
  std::fprintf(stderr, "total claps: %llu\n", n);
  return 0;
}
