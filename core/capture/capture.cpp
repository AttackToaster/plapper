#include "../include/plapper/plapper_capture.h"

#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_DECODING
#define MA_NO_GENERATION
#include "miniaudio.h"

#include <atomic>
#include <chrono>
#include <new>
#include <thread>

extern "C" {

struct plapper_capture {
  ma_device device;
  plapper_detector* detector;
  ma_encoder encoder;
  std::atomic<bool> recording{false};
};

static void data_callback(ma_device* device, void* /*out*/, const void* in,
                          ma_uint32 frames) {
  auto* cap = static_cast<plapper_capture*>(device->pUserData);
  const float* mono = static_cast<const float*>(in);
  plapper_process(cap->detector, mono, static_cast<int32_t>(frames));

  if (cap->recording.load(std::memory_order_acquire)) {
    /* encode as 16-bit; block-sized conversion on the stack */
    ma_int16 buf[4096];
    ma_uint32 done = 0;
    while (done < frames) {
      const ma_uint32 n = frames - done > 4096 ? 4096 : frames - done;
      ma_pcm_f32_to_s16(buf, mono + done, n, ma_dither_mode_triangle);
      ma_uint64 written = 0;
      ma_encoder_write_pcm_frames(&cap->encoder, buf, n, &written);
      done += n;
    }
  }
}

plapper_capture* plapper_capture_start(plapper_detector* d,
                                         double sample_rate) {
  if (!d) return nullptr;
  auto* cap = new (std::nothrow) plapper_capture();
  if (!cap) return nullptr;
  cap->detector = d;

  ma_device_config cfg = ma_device_config_init(ma_device_type_capture);
  cfg.capture.format = ma_format_f32;
  cfg.capture.channels = 1;
  cfg.sampleRate = static_cast<ma_uint32>(sample_rate);
  cfg.dataCallback = data_callback;
  cfg.pUserData = cap;

  if (ma_device_init(nullptr, &cfg, &cap->device) != MA_SUCCESS) {
    delete cap;
    return nullptr;
  }
  if (ma_device_start(&cap->device) != MA_SUCCESS) {
    ma_device_uninit(&cap->device);
    delete cap;
    return nullptr;
  }
  fprintf(stderr, "[plapper] capture: backend=%s device=\"%s\" rate=%u\n",
          ma_get_backend_name(cap->device.pContext->backend),
          cap->device.capture.name, cap->device.sampleRate);
  return cap;
}

int plapper_capture_record_start(plapper_capture* c, const char* path) {
  if (!c || !path || c->recording.load(std::memory_order_acquire)) return 0;

  ma_encoder_config ecfg = ma_encoder_config_init(
      ma_encoding_format_wav, ma_format_s16, 1, c->device.sampleRate);
  if (ma_encoder_init_file(path, &ecfg, &c->encoder) != MA_SUCCESS) return 0;
  c->recording.store(true, std::memory_order_release);
  return 1;
}

void plapper_capture_record_stop(plapper_capture* c) {
  if (!c || !c->recording.load(std::memory_order_acquire)) return;
  c->recording.store(false, std::memory_order_release);
  /* the audio callback finishes any in-flight write within its period
   * (<10 ms); wait it out before finalizing the file */
  std::this_thread::sleep_for(std::chrono::milliseconds(40));
  ma_encoder_uninit(&c->encoder);
}

int plapper_capture_is_recording(const plapper_capture* c) {
  return c && c->recording.load(std::memory_order_acquire) ? 1 : 0;
}

void plapper_capture_stop(plapper_capture* c) {
  if (!c) return;
  plapper_capture_record_stop(c);
  ma_device_uninit(&c->device);
  delete c;
}

}  // extern "C"
