#!/usr/bin/env python3
"""Generate the celebration chime WAVs bundled with the Flutter app.

Stdlib only. Writes 48 kHz mono 16-bit WAVs to app/assets/sounds/:
  milestone.wav  ~0.7 s soft two-note bell (E6 -> B6)
  goal.wav       ~1.4 s ascending sparkly arpeggio (C6 E6 G6 C7)

Run from anywhere:  python3 core/tools/gen_chimes.py
"""

import math
import struct
import wave
from pathlib import Path

RATE = 48000
PEAK = 0.38  # headroom target; spec caps peak amplitude at 0.4

# note frequencies (Hz)
C6, E6, G6, B6, C7 = 1046.50, 1318.51, 1567.98, 1975.53, 2093.00


def bell(freq, start, dur, amp, shimmer=False):
    """One struck-bell partial stack as a (start_time, samples) pair."""
    n = int(dur * RATE)
    out = [0.0] * n
    attack = int(0.005 * RATE)  # 5 ms attack ramp: no click at onset
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * 5.0 / dur)
        # fundamental + gentle 2nd harmonic that decays faster
        s = math.sin(2 * math.pi * freq * t) * env
        s += 0.30 * math.sin(2 * math.pi * 2 * freq * t) * math.exp(-t * 8.0 / dur)
        if shimmer:
            # detuned partner (slow beating) + airy 3rd partial with tremolo
            s += 0.22 * math.sin(2 * math.pi * (freq * 1.003) * t) * env
            trem = 0.5 * (1 + math.sin(2 * math.pi * 6.0 * t))
            s += 0.10 * trem * math.sin(2 * math.pi * 3 * freq * t) * math.exp(-t * 10.0 / dur)
        if i < attack:
            s *= i / attack
        out[i] = amp * s
    return start, out


def render(notes, total_dur, path):
    total = int(total_dur * RATE)
    mix = [0.0] * total
    for start, samples in notes:
        offset = int(start * RATE)
        for i, s in enumerate(samples):
            j = offset + i
            if j < total:
                mix[j] += s

    # normalize to PEAK
    peak = max(abs(s) for s in mix) or 1.0
    gain = PEAK / peak
    mix = [s * gain for s in mix]

    # global edge fades: 5 ms in, 30 ms out — guarantees click-free ends
    fade_in = int(0.005 * RATE)
    fade_out = int(0.030 * RATE)
    for i in range(fade_in):
        mix[i] *= i / fade_in
    for i in range(fade_out):
        mix[total - 1 - i] *= i / fade_out

    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in mix
        )
        w.writeframes(frames)
    print(f"wrote {path}  ({total_dur:.2f}s, peak {PEAK})")


def main():
    sounds = Path(__file__).resolve().parents[2] / "app" / "assets" / "sounds"

    # milestone: soft two-note bell, E6 then B6, ~0.7 s
    render(
        [
            bell(E6, 0.00, 0.55, 1.0),
            bell(B6, 0.16, 0.54, 0.85),
        ],
        0.70,
        sounds / "milestone.wav",
    )

    # goal: ascending sparkly 4-note arpeggio C6-E6-G6-C7, ~1.4 s
    render(
        [
            bell(C6, 0.00, 0.70, 0.90, shimmer=True),
            bell(E6, 0.16, 0.70, 0.90, shimmer=True),
            bell(G6, 0.32, 0.75, 0.95, shimmer=True),
            bell(C7, 0.48, 0.90, 1.00, shimmer=True),
        ],
        1.40,
        sounds / "goal.wav",
    )


if __name__ == "__main__":
    main()
