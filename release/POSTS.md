# Community posts

One post per scene: post the `.oxie16` scene, which carries the wiring and the script.
All five need E16 firmware 1.3 or later.

---

## LFOx16

A bank of 16 assignable LFOs.

Each row is an LFO with four knobs. Controls:

Turns:
Knob 1: Shape (Sine, Triangle, Saw Up, Saw Down, Square, S&H)
Knob 2: Rate (20s to 6.4Hz; synced 8 bars to 1/32)
Knob 3: Depth (-100% to +100%)
Knob 4: Center

Pushes:
Knob 1: LFO on/off
Knob 2: Sync/Free
Knob 3: Freeze LFO
Knob 4: Destination (use knobs 1-2 to set this LFO's channel and CC)

Press shift to change pages:
1-4: 4 LFOs each
5: Settings: Output port, BPM, All off, Restart all

---

## Euclid

Four Euclidean rhythm tracks that follow MIDI clock.

Each row is a track with four knobs. Controls:

Turns:
Knob 1: Length (1-32 steps)
Knob 2: Pulses (hits spread evenly across the length)
Knob 3: Rotation
Knob 4: Note

Pushes:
Knob 1: Mute
Knob 2: Invert
Knob 3: Play/Stop
Knob 4: Resync all tracks

Press shift to change pages:
1: Tracks
2: Settings: BPM, Step size (1/4 to 1/32, with triplets), Gate, MIDI channel, Output port, Play/Stop

Follows external clock and transport. With no clock, Play starts the E16's internal clock.

---

## Chords

176 chord pads in 11 moods: Cinematic, Chill House, Gospel Soul, Neo Soul, Lofi R&B,
Indie Jazz, Detroit, Lush Pads, Pop Piano, Impressionist and Sad Ballads.

Each knob is a chord pad. Controls:

Push: play the chord (it sounds while held)
Turn: change the root
Push + turn: change the chord type (34 types)

Edited chords are voiced to fit the set and saved with the scene.

Press shift to change pages:
1-11: one chord set each
12: Settings: Transpose, Octave, Velocity, Length (Held, Latch, 0.1-4s), Strum, Strum direction,
MIDI channel, Output port, Panic, Reset edits (hold 2s)

---

## Mod Seq

A 16-step CC modulation sequencer that follows MIDI clock.

Each knob is a step. Controls:

Turn: step value (0-127)
Push: glide to the next step

Press shift to change pages:
1: Steps
2: Settings: BPM, Step size, Length (1-16), CC number, MIDI channel, Output port, Play/Stop

Follows external clock and transport. With no clock, Play starts the E16's internal clock.

---

## TB-3PO

A generative 303-style acid sequencer that follows MIDI clock, ported from the Ornament & Crime
/ Phazerville applet.

Knobs 1-8 set the generator. Controls:

Turns:
Knob 1: Density (-7 to +7)
Knob 2: Length (1-32)
Knob 3: Root
Knob 4: Scale
Knob 5: Octave
Knob 6: Transpose
Knob 7: Mutate amount
Knob 8: BPM

Pushes:
Knob 1: Generate (new pattern)
Knob 2: Undo
Knob 4: Restart
Knob 5: Regen (same pattern, current density)
Knob 7: Mutate
Knob 8: Play/Stop

Knobs 9-16 show the steps around the playhead.

Press shift to change pages:
1: Pattern
2: Settings: Step size, Gate, Slide mode, MIDI channel, Output port, Play/Stop

Original TB3PO © 2020 Logarhythm (MIT), modified by djphazer. This port is GPL-3.0.
