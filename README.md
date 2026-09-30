# Lua scripts for the OXI E16

Five scripts that run entirely on the E16 (Lua API ≥ 1.3.0, for the clock and
push/release callbacks), each with a ready-wired scene:

| script | scene | what it is |
|---|---|---|
| `euclid.lua` | Euclid | 4-track Euclidean drum sequencer |
| `lfo.lua` | LFOx16 | 16 LFOs, each on its own MIDI channel and CC, free or tempo-synced |
| `chords.lua` | Chords | 176 chord pads on 11 pages, in 11 moods |
| `modseq.lua` | Mod Seq | 16-step CC modulation sequencer with glide |
| `tb3po.lua` | TB-3PO | generative 303-style acid sequencer (port of the O&C / Phazerville applet, GPL-3.0) |

All five ran on hardware on firmware 1.2.0. The clock and push/release versions are
tested against a mock of the 1.3.0 API and still need a hardware check.

## Loading a script onto the E16

The OXI App keeps its E16 files in the folder chosen under **Scenes → Assign PC/Mac
folder** (it contains `Scenes/` and `Scripts/`).
`tools/make_scene.py` turns a script into a ready-wired scene, using any exported
scene as a template:

    E=/path/to/your/OXI/E16/folder; T="$E/Scenes/Some Scene.oxie16"   # any exported scene as template
    python3 tools/make_scene.py "$T" euclid.lua "$E/Scenes/Euclid.oxie16" "$E/Scripts/euclid.e16script" --title Euclid --pages Pat,Set
    python3 tools/make_scene.py "$T" lfo.lua    "$E/Scenes/LFOx16.oxie16" "$E/Scripts/lfo.e16script"    --title LFOx16 --pad-pages 4 --settings-page 5
    python3 tools/make_scene.py "$T" chords.lua "$E/Scenes/Chords.oxie16" "$E/Scripts/chords.e16script" --title Chords --pad-pages 11 --settings-page 12
    python3 tools/make_scene.py "$T" modseq.lua "$E/Scenes/ModSeq.oxie16" "$E/Scripts/modseq.e16script" --title "Mod Seq"
    python3 tools/make_scene.py "$T" tb3po.lua  "$E/Scenes/TB-3PO.oxie16" "$E/Scripts/tb3po.e16script" --title TB-3PO

The scene's embedded code is exactly what the device receives, so `make_scene.py` minifies
it: it removes comments and unneeded whitespace and shortens file-level local names. The
test suites pass on the minified output.

Then:

1. Connect the E16 over USB and open the OXI App.
2. On the **Scenes** tab, click **Refresh Views**. The scene appears under *On Computer*.
3. Drag it onto a slot under *On Device*. This uploads the scene and its script.
4. On the E16, pick that scene from the home screen.

**Faster loop while editing a script.** Once a scene is on the device, `tools/e16push.py` replaces
just its script over USB-MIDI, without the app (needs `pip install mido python-rtmidi`):

    python3 tools/e16push.py list                # scenes by home-screen encoder, 1-16
    python3 tools/e16push.py push 2 euclid.lua   # minify and send to the scene on encoder 2
    python3 tools/e16push.py scene 2 "$E/Scenes/Euclid.oxie16"   # the whole scene, wiring included

Reopen the scene on the E16 to run the new code. `push` leaves pages, labels and script variables
alone. When the wiring changes, `scene` uploads everything the way the OXI App does.

To switch pages on the E16, tap Shift and then a page (P.1, P.2, …). Every script keeps
running on any page, and its settings are saved in the scene's script variables.

**Wiring convention.** Page 1 uses turn IDs 1–16 and push IDs 17–32; the settings page
uses turn IDs 33–48 and push IDs 49–64. `make_scene.py` wires whatever IDs a script
declares with `--@assign`. `--pad-pages N` repeats the page-1 wiring on pages 1–N
(the script tells them apart by page).

## Euclid

**Page 1: pattern.** One track per row. Turn = edit, push = action. The parameters
follow the OXI ONE's Euclidean generator.

|        | col 1 (Len)  | col 2 (Puls) | col 3 (Rot)          | col 4 (Note)      |
|--------|--------------|--------------|----------------------|-------------------|
| turn   | length 1–32  | pulses 0–Len | rotation ±(Len−1)    | MIDI note 0–127   |
| push   | mute         | invert       | play / stop          | resync all tracks |

Rings: col 1 shows the playhead, col 2 pulse density, col 3 rotation, and col 4 the
note (it flashes while a note sounds). Labels show `L16`, `P4` (`i4` when inverted), `R+2`, and
the note name (`C2`). The header shows `EUC ▶ 120` while playing and `EUC ■ 120` while stopped
(with an external clock, its tempo).

**Page 2: settings.**

| enc | turn | label |
|---|---|---|
| 1 | tempo 20–300 (fast turns jump) | `120` |
| 2 | step size: 1/4, 1/8, 8T, 1/16, 16T, 1/32 | `1/16` |
| 3 | gate 10–990 ms | `G60` |
| 4 | MIDI channel | `Ch10` |
| 5 | output port (0 = all) | `All` / `O2` |
| 6 | push = **play / stop** | `Play` / `Stop` |

Defaults are a GM drum kit on channel 10: kick 36 E(4,16), snare 38 E(2,16) rotated by 4,
closed hat 42 E(8,16), open hat 46 E(3,16) rotated by 2.

Steps follow the E16's clock; see [Clock and transport](#clock-and-transport).

## LFOx16

A modulation bank for several synths: 16 LFOs, each with its own MIDI channel and CC number.

**Pages 1–4:** four LFOs per page, one per row (page 1 = LFO 1–4 … page 4 = LFO 13–16).

|      | col 1 | col 2 | col 3 | col 4 |
|------|---|---|---|---|
| turn | Shape (Sin, Tri, SawU, SawD, Sqr, S&H) | Rate | Depth −100…+100 % | Center 0–127 |
| push | on/off | **Sync/Free** | freeze | **Dest** |

- **Rate** is free (20 s … 6.4 Hz) or **synced** to the tempo (8 bars … 1/32, with triplets).
  Free rates below 1 Hz show their period (`2.5s`), faster ones their frequency (`1.0H` = 1 Hz).
  Pushing Rate toggles between them and keeps about the same speed. Synced LFOs follow one
  beat counter, so they stay locked together. While the E16's clock runs (its internal clock or
  external MIDI transport), the counter follows the clock's position, and a Start restarts every
  LFO on the downbeat. While transport is stopped, the counter runs at BPM.
- **Dest** switches the row's first two encoders to that LFO's **MIDI channel** and **CC
  number** (labels `Ch3`, `CC74`). Push again to go back. The CC it leaves behind is sent the
  center value, and so is the old port when the output changes.
- A row is **blue** while its LFO plays, **white** when it's off and **pink** when frozen.
- The Center ring shows the live output. An LFO that is off sends its center value when it's
  switched off or its Center is turned, so it works as a plain CC knob. The header shows the page's
  LFOs and how many are running in total (`LFO 1-4 3on`).

**Page 5, settings:**
1. output port
2. BPM: the E16's internal tempo, used for synced rates while transport is stopped
3. push = all off
4. push = restart all, which realigns synced LFOs to the downbeat

By default only LFO 1 runs. Each page starts on its own MIDI channel (page 1 = channel 1 …), with
the rows on CC 74, 71, 1 and 10, so a page is effectively one synth.

## Chords

**Pages 1–11:** each page is one chord set (a mood), with 16 chords. Push a
pad to play it. The header shows the set's name, and labels show chord names (minor chords
use a lowercase root: `f#11` = F#m11; `s` = sus, `a9` = add9, `h7` = half-diminished,
`?` = no simple name). The ring lights on the sounding pad.

**Make your own layout.** Turn a pad to change its root. Hold the pad and turn to change its
chord type (34 types: triads, sus, 6ths, 7ths, 9ths, 11ths, 13ths, altered). Turning doesn't play
anything, and a chord that's ringing keeps ringing; the next push plays the new chord. An edited chord is voiced on the device: the root
in the bass near the original bass note, the rest around the original chord's register, so it
sits with the rest of the set. Turn back to the original root and type and the hand voicing
returns. Edits are saved in the scene (the store holds all 176 pads with room to spare), and
**Reset** on the settings page clears them.

**Page 12: settings.**
1. transpose −12…+12 (the root key; labels follow)
2. octave ±2
3. velocity
4. length: Held, Ltch, or 0.1–4 s. Held (the default) plays from push to release. Ltch sustains
   a chord until the next pad; push the same pad to stop it.
5. strum 0–200 ms
6. strum direction
7. MIDI channel
8. output port
9. **Panic**: push for all notes off
10. **Reset**: push and hold. The label says `Hold` and the ring fills; after 2 s your edits on
    every page are cleared and it says `Done`. Letting go early cancels.

The pages are Cinematic, Chill House, Gospel Soul, Neo Soul, Lofi R&B, Indie Jazz, Detroit,
Lush Pads, Pop Piano, Impressionist and Sad Ballads. They are written for this project (see
below).

### Writing chord sets

New sets are written as specs in `tools/chordgen/specs/` (a key, a set type, 16 chord
symbols in 4 rows, a voicing style) and voiced by `tools/chordgen/voicer.py`, which keeps
the set in one register, avoids muddy low intervals and moves smoothly from pad to pad.

    python3 tools/chordgen/build.py      # voice the specs, measure them
    python3 tools/chordgen/serve.py      # then open http://localhost:8016/

The harness plays the sets in the browser (pads, rows, the whole grid, a random walk), shows
each set's measurements next to the range of the current sets, and saves Keep / Fix / Drop
verdicts and notes to `build/chordgen/feedback.json`. To put generated sets on the E16:

    python3 tools/make_chords.py --dir build/chordgen/sets chords.lua cinematic chill_house \
        gospel_soul neo_soul lofi_rb indie_jazz detroit lush_pads pop_piano impressionist sad_ballads

Pop Piano, Gospel Soul and Sad Ballads take their rows from progressions that are common in
the [McGill Billboard](https://ddmal.ca/research/The_McGill_Billboard_Project_(Chord_Analysis_Dataset)/)
chord annotations (Hot 100 songs, 1958–1991; CC0). `tools/chordgen/billboard.py` downloads them
into `build/` and lists the most common progressions (`--decade 1970`, `--minor`). The data is
from John Ashley Burgoyne, Jonathan Wild and Ichiro Fujinaga, "An Expert Ground Truth Set for
Audio Chord Recognition and Music Analysis", ISMIR 2011.

## Mod Seq

**Page 1:** one step per encoder. Turn sets the step's CC value; push toggles **glide**
(a ramp to the next step's value within the step). The ring shows each value, the playhead
lights up, glide steps have their own color, and steps past the length go dark. Labels show
values (`~64` = glide).

**Page 2:**
1. BPM
2. step size
3. length 1–16
4. CC number
5. MIDI channel
6. output port
7. push = **play / stop**

Steps follow the E16's clock, and a glide moves once per clock tick (24 per quarter note).

## TB-3PO

A 303-style pattern generator after the O&C / Phazerville applet, with Generate, Mutate and Undo
as in schwung-tb3po. The knobs set the generator, and the pattern only changes when you ask:

- **Generate**: a new seed, so a new pattern
- **Regen**: the same seed with the current density
- **Mutate**: re-rolls some steps; half get a new gate/accent/slide, half a new pitch
- **Undo**: swaps back to the previous pattern (press again to redo)

**Density** runs from −7 to +7. The further from 0, the more steps play; negative values also
narrow the pitch range and repeat notes, which gives classic 303 lines. Root, scale, octave and
transpose apply live. The pattern is stored, so mutations survive reloads.

**Page 1:**

| enc | turn | push |
|---|---|---|
| 1 | density | Generate |
| 2 | length 1–32 | Undo |
| 3 | root | |
| 4 | scale (8 scales) | restart |
| 5 | octave | Regen |
| 6 | transpose | |
| 7 | mutate amount | Mutate |
| 8 | BPM | **play/stop** |

Encoders 9–16 show the 8 steps around the playhead. They're a display, not controls: the ring
shows pitch, colors mark accent, slide and the playhead, and labels show the note. Velocity is
100, or 127 on accents.

**Page 2:**
1. step size
2. gate %
3. slide: Off, Leg (legato), or CC65 (legato plus portamento CC 65)
4. MIDI channel
5. output port
6. push = **play / stop** (the same as encoder 8's push on page 1)

Steps follow the E16's clock. If anything goes wrong, TB-3PO keeps running: an error in its
timer is caught, the header flashes `ERR`, and the message goes to the OXI App's console.

The original `TB3PO.h` is Copyright (c) 2020 Logarhythm under the MIT license (the notice is kept
in the file), and was modified by djphazer in Phazerville. This port is GPL-3.0.

## Clock and transport

Euclid, Mod Seq and TB-3PO step on the E16's clock (`clock.onPulse` at 24 ticks per quarter
note), so steps land on the clock exactly, and triplet step sizes are whole ticks.

- **Play** starts the E16's internal clock at the script's BPM, and **Stop** stops it. BPM is
  the E16's internal tempo, so it also sets the Internal Clock alt action's tempo.
- **External MIDI transport:** Start restarts the sequence from step 1, Continue resumes it, and
  Stop stops it. While external transport runs, Play/Stop only silences the sequence or lets it
  rejoin; the header shows the external tempo.
- **Clock output:** Lua can't choose where the E16 sends MIDI clock. The internal clock uses the
  output last chosen on the **Internal Clock alt action** (off until you set one). To send clock
  to other gear, pick the output there, start and stop the clock once with the alt action, then
  use the script's Play.
- Loading a scene stops an internal clock that a script started.
- Gates and strums are timed by `system.update()` every 10 ms. The LFOs update every 20 ms.
- **Errors in `update` stop it silently.** If `system.update` raises an error, the firmware
  disables updates, so the scripts clamp every value they read. An error in a clock callback
  only ends that call.

## Memory

Measured on firmware 1.2.0 with probe scenes (the tools are in `tools/`):

- **Loading is the limit.** A script's *modeled load peak* (`test/e16host.c`: its "script peak
  (load)" plus the 11.9 KB base) must stay **≤ 42.5 KB**. Load probes load at 42.6 KB and fail at 43.5 KB.
- **While running,** the ceiling is higher: `probe.lua` runs out at a Lua count of 42.3 KB, which is
  about **46.6 KB** modeled.
- **Size** is not the constraint: 7,000-byte scripts load, and API 1.3.0 allows 8,192 bytes after
  the app minifies them.

| script | uploaded | load peak | margin |
|---|---|---|---|
| modseq | 3.2 KB | ~30.0 KB | ~12.5 KB |
| euclid | 4.5 KB | ~36.8 KB | ~5.7 KB |
| chords | 5.3 KB | ~37.6 KB | ~4.9 KB |
| lfo | 5.7 KB | ~41.8 KB | ~0.7 KB |
| tb3po | 6.0 KB | 42.5 KB | 0.1 KB |
| example step sequencer | 6.2 KB | 43.6 KB | −1.1 KB (fails to load) |

On firmware 1.3.0 the limit measured a little lower (TB-3PO stopped loading about 0.1 KB
above its old peak), so TB-3PO and LFO were trimmed by about 1 KB each; see the notes.
The peaks marked ~ are for the clock versions. They're estimated from each script's growth in a
64-bit build of `e16host`, because the 32-bit build needs Docker. TB-3PO was trimmed back to its
old peak. Firmware 1.3 may also give Lua a different budget, so check the tight ones on hardware
first. Scene variables are also limited: 32 per scene, and they outlive script changes, so
`lfo.lua` and `tb3po.lua` stamp a layout version and clear old variables when it changes.

If a scene shows its default title and labels and doesn't respond, the script didn't fit. With
API 1.3.0, the OXI App's console (Scripts tab) shows load errors and `print` output.
`tools/make_diag.py` is the firmware 1.2 alternative: a copy of a scene that prints any Lua error
across the labels.

## E16 Lua notes

Everything learned about the E16's Lua environment is collected in
[`docs/e16-lua-notes.md`](docs/e16-lua-notes.md), tagged by source (hardware, firmware, guide,
example, model). That includes limits, undocumented APIs, quirks, and the OXI App file
formats.

## Tests

Build Lua 5.4 with `#define LUA_32BITS 1` in `luaconf.h` so its numbers match the device,
then run the suites from the repo root:

    lua test/euclid_test.lua
    lua test/lfo_test.lua
    lua test/chords_test.lua     # after python3 tools/chordgen/build.py (it builds the sets into build/)
    lua test/modseq_test.lua
    lua test/tb3po_test.lua
    lua test/fuzz.lua tb3po.lua 2 600    # random input for 10 simulated minutes (pages: 12 for chords)
    python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen   # chord-set tools

`test/fuzz.lua` matters on the E16: an error in `update()` silently stops a script's updates, so
the fuzzer throws random presses and releases, turns, page changes, variable edits and external
transport at a script. It fails if `update()` or a clock callback ever raises, or a label is too long.

`test/e16mock.lua` is a reusable mock of the E16 API 1.3.0. It includes the clock (internal
and external transport, 24 ticks per quarter note, callbacks delivered on the next clock pass)
and push release. The suites check the following:
- Euclid: every E(k, n) against a reference Bjorklund
- Chords: all 176 pads against their source voicings, and Held / Ltch / timed gates
- sequencers: steps on the clock, internal and external transport, Continue
- all scripts: timing, label lengths, page switching, persistence, ignoring non-physical events, and no per-tick garbage

`test/e16host.c` models the device heap: a 32-bit build, the heap_4 overhead, the firmware's
library set, and generational GC. While "playing" it calls `system.update` every 10 ms and
`clock.onPulse` at 120 BPM. For example, with Docker:

    docker run --rm --platform linux/386 -v "$PWD":/w -w /w i386/alpine:3.20 sh -c '
      apk add -q build-base && cd lua-5.4.7/src && make -s liblua.a &&
      cd /w && gcc -Os -o e16host test/e16host.c -Ilua-5.4.7/src lua-5.4.7/src/liblua.a -lm &&
      ./e16host euclid.lua'

## License

MIT (see `LICENSE`), except `tb3po.lua`, which is GPL-3.0 (see `LICENSES/GPL-3.0.txt`): it
ports the TB-3PO applet as modified in the GPL-3.0 Phazerville firmware. The original `TB3PO.h`
is Copyright (c) 2020 Logarhythm under the MIT license, and its notice is kept in the file.

