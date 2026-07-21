/* plapper sound — one-shot file playback for celebration chimes.
 * Optional layer: built with PLAPPER_BUILD_CAPTURE (shares the miniaudio
 * implementation compiled in capture/capture.cpp). */
#ifndef PLAPPER_SOUND_H
#define PLAPPER_SOUND_H

#include "plapper.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Lazily creates the global playback engine (default output device).
 * Returns 1 on success, 0 on failure. Thread-safe; called on demand by
 * plapper_sound_play, so explicit init is optional. */
PLAPPER_API int plapper_sound_init(void);

/* Fire-and-forget playback of an audio file (e.g. WAV). Initializes the
 * engine on demand. Returns 1 if playback started, 0 on failure. */
PLAPPER_API int plapper_sound_play(const char* path);

/* Tears down the playback engine. Safe to call without prior init;
 * a later plapper_sound_play re-initializes. */
PLAPPER_API void plapper_sound_shutdown(void);

#ifdef __cplusplus
}
#endif
#endif /* PLAPPER_SOUND_H */
