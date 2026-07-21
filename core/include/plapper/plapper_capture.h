/* plapper capture — mic input via miniaudio, feeding a plapper_detector.
 * Optional layer: build with PLAPPER_BUILD_CAPTURE. The detector itself
 * stays pure DSP and testable without any audio device. */
#ifndef PLAPPER_CAPTURE_H
#define PLAPPER_CAPTURE_H

#include "plapper.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct plapper_capture plapper_capture;

/* Opens the default capture device (mono f32 at the detector's sample rate)
 * and streams it into the detector from the audio thread.
 * Returns NULL on failure (no device, permission denied, ...).
 * The detector must outlive the capture. */
PLAPPER_API plapper_capture* plapper_capture_start(plapper_detector* d,
                                                      double sample_rate);
PLAPPER_API void plapper_capture_stop(plapper_capture* c);

/* Session audio recording: writes 16-bit mono WAV at the capture rate to
 * `path` until stopped. Returns 1 on success, 0 on failure. Recording
 * always stops (and the file is finalized) when the capture is stopped. */
PLAPPER_API int plapper_capture_record_start(plapper_capture* c,
                                             const char* path);
PLAPPER_API void plapper_capture_record_stop(plapper_capture* c);
PLAPPER_API int plapper_capture_is_recording(const plapper_capture* c);

#ifdef __cplusplus
}
#endif
#endif /* PLAPPER_CAPTURE_H */
