# Community posts

One post per scene. Post the `.oxie16` scene: it carries the wiring and the script.
All five need E16 firmware 1.3 (Lua API 1.3.0) or later.

---

## Euclid

**Title:** Euclid – 4-track Euclidean drum sequencer

**Description:**

Four Euclidean rhythm tracks, one per row: turn to set Length (1–32), Pulses, Rotation and Note;
push for Mute, Invert, Play/Stop and Resync.

- Follows external MIDI clock and transport (Start, Continue, Stop). With no clock running,
  Play starts the E16's internal clock at the scene's BPM.
- Page 2: BPM, step size (1/4 to 1/32, with triplets), gate, MIDI channel, output port.
- Defaults to a GM drum kit on channel 10. Settings are saved in the scene.

To send clock to other gear, choose an output on the Internal Clock alt action first.

Source and docs: https://github.com/charlesvestal/oxi-e16-lua (MIT)

---

## LFOx16

**Title:** LFOx16 – 16 LFOs, each on its own channel and CC

**Description:**

A modulation bank for several synths. Four LFOs per page on pages 1–4, one per row: Shape (sine,
triangle, saws, square, S&H), Rate, Depth ±100 % and Center.

- Push Rate to switch between a free rate (20 s to 6.4 Hz) and a tempo-synced one (8 bars to
  1/32, with triplets).
- Synced LFOs lock to the running clock, internal or external, and restart on Start. When the
  transport is stopped, they run at the scene's BPM.
- Push Dest to set each LFO's MIDI channel and CC. Other pushes: on/off, freeze.
- Page 5: output port, BPM, restart all, all off.

Source and docs: https://github.com/charlesvestal/oxi-e16-lua (MIT)

---

## Chords

**Title:** Chords – 176 hand-voiced chord pads in 11 moods

**Description:**

Eleven pages of 16 chord pads each, one mood per page: Cinematic, Chill House, Gospel Soul,
Neo Soul, Lofi R&B, Indie Jazz, Detroit, Lush Pads, Pop Piano, Impressionist and Sad Ballads.
The labels show the chord names.

- Push a pad to play its chord. By default it sounds while you hold the pad.
- Turn any pad to set the length: Held, Ltch (latch until the next pad) or 0.1–4 s.
- Page 12: transpose, octave, velocity, length, strum time and direction, MIDI channel, output
  port. Push encoder 1 for all notes off.

The chord sets are original, voiced to stay in one register and move smoothly from pad to pad.

Source and docs: https://github.com/charlesvestal/oxi-e16-lua (MIT)

---

## Mod Seq

**Title:** Mod Seq – 16-step CC modulation sequencer

**Description:**

One step per encoder. Turn to set the step's CC value; push to glide to the next step.

- Follows external MIDI clock and transport; otherwise Play starts the internal clock.
- Glides move every clock tick (24 per quarter note).
- Page 2: BPM (push = Play/Stop), step size, length 1–16, CC number, MIDI channel, output port.

Source and docs: https://github.com/charlesvestal/oxi-e16-lua (MIT)

---

## TB-3PO

**Title:** TB-3PO – generative 303-style acid sequencer

**Description:**

A port of the TB-3PO applet from Ornament & Crime / Phazerville to the E16.

- The knobs set up the generator, and the pattern only changes when you ask. Generate draws a
  new seed. Regen redraws the same seed at the current density. Mutate re-rolls some steps.
  Undo swaps back.
- Density goes from −7 to +7. Negative values narrow the pitch range, for classic 303 lines.
- Root, scale (8 scales), octave and transpose apply live. Encoders 9–16 show the steps around
  the playhead.
- Slides play legato, optionally with portamento (CC 65).
- Follows external MIDI clock and transport; otherwise Play starts the internal clock.

Original TB3PO © 2020 Logarhythm (MIT), modified by djphazer in Phazerville. This port is
GPL-3.0: https://github.com/charlesvestal/oxi-e16-lua
