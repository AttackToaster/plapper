#include "../include/plapper/plapper_sound.h"

/* The miniaudio implementation is compiled in capture/capture.cpp; the
 * MA_NO_* configuration here must match the one there so declarations
 * agree across translation units. */
#define MA_NO_GENERATION
#include "miniaudio.h"

#include <mutex>

namespace {

std::mutex g_engine_mutex;
ma_engine g_engine;
bool g_engine_ready = false;

}  // namespace

extern "C" {

int plapper_sound_init(void) {
  std::lock_guard<std::mutex> lock(g_engine_mutex);
  if (g_engine_ready) return 1;
  if (ma_engine_init(nullptr, &g_engine) != MA_SUCCESS) return 0;
  g_engine_ready = true;
  return 1;
}

int plapper_sound_play(const char* path) {
  if (!path) return 0;
  if (!plapper_sound_init()) return 0;
  /* fire-and-forget: the engine owns the sound and frees it when done */
  return ma_engine_play_sound(&g_engine, path, nullptr) == MA_SUCCESS ? 1 : 0;
}

void plapper_sound_shutdown(void) {
  std::lock_guard<std::mutex> lock(g_engine_mutex);
  if (!g_engine_ready) return;
  ma_engine_uninit(&g_engine);
  g_engine_ready = false;
}

}  // extern "C"
