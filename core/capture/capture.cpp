#include "../include/plapper/plapper_capture.h"

#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_ENCODING
#define MA_NO_DECODING
#define MA_NO_GENERATION
#include "miniaudio.h"

#include <new>

extern "C" {

struct plapper_capture {
  ma_device device;
  plapper_detector* detector;
};

static void data_callback(ma_device* device, void* /*out*/, const void* in,
                          ma_uint32 frames) {
  auto* cap = static_cast<plapper_capture*>(device->pUserData);
  plapper_process(cap->detector, static_cast<const float*>(in),
                   static_cast<int32_t>(frames));
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

void plapper_capture_stop(plapper_capture* c) {
  if (!c) return;
  ma_device_uninit(&c->device);
  delete c;
}

}  // extern "C"
