# fixtures

Recorded audio for detector regression tests: real claps (near/far, single,
flams), false-positive bait (speech, music, door slams, keyboard, beeps).

Unit tests currently use synthesized signals (see core/tests). Drop WAVs here
as they get recorded; keep them mono, 48 kHz, and name them
`<what>_<distance>_<room>.wav`.
