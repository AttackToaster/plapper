/* plounter capture — mic input via miniaudio, feeding a plounter_detector.
 * Optional layer: build with PLOUNTER_BUILD_CAPTURE. The detector itself
 * stays pure DSP and testable without any audio device. */
#ifndef PLOUNTER_CAPTURE_H
#define PLOUNTER_CAPTURE_H

#include "plounter.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct plounter_capture plounter_capture;

/* Opens the default capture device (mono f32 at the detector's sample rate)
 * and streams it into the detector from the audio thread.
 * Returns NULL on failure (no device, permission denied, ...).
 * The detector must outlive the capture. */
PLOUNTER_API plounter_capture* plounter_capture_start(plounter_detector* d,
                                                      double sample_rate);
PLOUNTER_API void plounter_capture_stop(plounter_capture* c);

#ifdef __cplusplus
}
#endif
#endif /* PLOUNTER_CAPTURE_H */
