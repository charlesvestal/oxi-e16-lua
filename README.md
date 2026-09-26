# Lua scripts for the OXI E16

Five scripts that run entirely on the E16 (firmware ≥ 1.2.0), each with a
ready-wired scene:

| script | scene | what it is |
|---|---|---|
| `euclid.lua` | Euclid | 4-track Euclidean drum sequencer |
| `lfo.lua` | LFO x16 | 16 LFOs, each on its own MIDI channel and CC, free or tempo-synced |
| `chords.lua` | Chords | 176 hand-voiced chord pads on 11 pages |
| `modseq.lua` | Mod Seq | 16-step CC modulation sequencer with glide |
| `tb3po.lua` | TB-3PO | generative 303-style acid sequencer (port of the O&C / Phazerville applet, GPL-3.0) |

All five have run on hardware (firmware 1.2.0).

## Loading a script onto the E16

The OXI App keeps its E16 files in the folder chosen under **Scenes → Assign PC/Mac
folder** (it contains `Scenes/` and `Scripts/`).
`tools/make_scene.py` turns a script into a ready-wired scene, using any exported
scene as a template:

    E=/path/to/your/OXI/E16/folder; T="$E/Scenes/Some Scene.oxie16"   # any exported scene as template
    python3 tools/make_scene.py "$T" euclid.lua "$E/Scenes/Euclid.oxie16" "$E/Scripts/euclid.e16script" --title Euclid --pages Pat,Set
    python3 tools/make_scene.py "$T" lfo.lua    "$E/Scenes/LFO.oxie16"    "$E/Scripts/lfo.e16script"    --title "LFO x16" --pad-pages 4 --settings-page 5
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

Reopen the scene on the E16 to run the new code. Pages, labels and script variables aren't touched,
so use the app when the wiring changes.

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
the note name (`C2`). The header shows `EUC > 120` while playing and `EUC | 120` while stopped.

**Page 2: settings.**

| enc | turn | label |
|---|---|---|
| 1 | tempo 20–300 (fast turns jump); **push = play/stop** | `120` |
| 2 | step size: 1/4, 1/8, 8T, 1/16, 16T, 1/32 | `1/16` |
| 3 | gate 10–990 ms | `G60` |
| 4 | MIDI channel | `Ch10` |
| 5 | output port (0 = all) | `All` / `O2` |
| 6 | tempo trim, ±9.9 % in 0.1 % steps | `T+5` |

Defaults are a GM drum kit on channel 10: kick 36 E(4,16), snare 38 E(2,16) rotated by 4,
closed hat 42 E(8,16), open hat 46 E(3,16) rotated by 2.

## LFO x16

A modulation bank for several synths: 16 LFOs, each with its own MIDI channel and CC number.

**Pages 1–4:** four LFOs per page, one per row (page 1 = LFO 1–4 … page 4 = LFO 13–16).

|      | col 1 | col 2 | col 3 | col 4 |
|------|---|---|---|---|
| turn | Shape (Sin, Tri, SawU, SawD, Sqr, S&H) | Rate | Depth −100…+100 % | Center 0–127 |
| push | on/off | **Sync/Free** | freeze | **Dest** |

- **Rate** is free (20 s … 6.4 Hz) or **synced** to the tempo (8 bars … 1/32, with triplets).
  Pushing Rate toggles between them and keeps about the same speed. Synced LFOs follow one
  beat counter, so they stay locked together.
- **Dest** switches the row's first two encoders to that LFO's **MIDI channel** and **CC
  number** (labels `Ch3`, `CC74`). Push again to go back.
- The Center ring shows the live output. An LFO that is off sends its center value when it's
  switched off or its Center is turned, so it works as a plain CC knob. The header shows the page's
  LFOs and how many are running in total (`LFO 1-4 3on`).

**Page 5, settings:**
1. output port. Push = restart all, which realigns synced LFOs to the downbeat.
2. BPM for synced rates
3. push = all off

By default only LFO 1 runs. Each page starts on its own MIDI channel (page 1 = channel 1 …), with
the rows on CC 74, 71, 1 and 10, so a page is effectively one synth. There's no MIDI clock
input for Lua (firmware 1.2), so synced rates follow the BPM setting; a future clock callback
would only need to drive the beat counter.

## Chords

**Pages 1–11:** each page is one chord set (a mood), with 16 hand-voiced chords. Push a
pad to play it. The header shows the set's name, and labels show chord names (minor chords
use a lowercase root: `f#11` = F#m11; `s` = sus, `a9` = add9, `h7` = half-diminished,
`?` = no simple name). The ring lights on the sounding pad.

**Page 12: settings.**
1. transpose −12…+12 (the root key; labels follow)
2. octave ±2
3. velocity
4. gate: Hold, or 0.1–4 s. In Hold mode a chord sustains until the next pad; push the same pad to stop it.
5. strum 0–200 ms
6. strum direction
7. MIDI channel
8. output port

Push encoder 1 for all notes off.

The default pages are Cinematic, Chill House, Gospel Soul, Neo Soul Minor, Lofi R&B 1, Indie
Jazz, Detroit Techno, Lush Pads, Pop Piano, Impressionist and Sad Ballads, taking the
first 16 chords of each. To choose other sets (about 150 are available), run:

    python3 tools/make_chords.py chords.lua cinematic chill_house lofi_rb_2:16 indie_jazz ...

`NAME:16` starts at chord 16. The chord sets come from
[Impressive Chords](https://github.com/mestela/schwung-impressive-chords) by mestela, a
module in the Schwung catalog.

## Mod Seq

**Page 1:** one step per encoder. Turn sets the step's CC value; push toggles **glide**
(a ramp to the next step's value within the step). The ring shows each value, the playhead
lights up, glide steps have their own color, and steps past the length go dark. Labels show
values (`~64` = glide).

**Page 2:**
1. BPM (**push = play/stop**)
2. step size
3. length 1–16
4. CC number
5. MIDI channel
6. output port
7. tempo trim

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
| 2 | length 1–32 | Mutate |
| 3 | root | |
| 4 | scale (8 scales) | restart |
| 5 | octave | Regen |
| 6 | transpose | Undo |
| 7 | mutate amount | |
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

If anything goes wrong, TB-3PO keeps running: an error in its timer is caught, the header shows
`ERR`, and the bottom 8 labels spell out the message for a few seconds.

The original `TB3PO.h` is Copyright (c) 2020 Logarhythm under the MIT license (the notice is kept
in the file), and was modified by djphazer in Phazerville. This port is GPL-3.0.

## Timing and limitations

- **No external sync.** Lua gets no MIDI clock, start/stop or time source. The only
  timebase is `system.update()`, which the firmware calls once more than *rate* ms
  have passed (`system.setUpdateRate(rate)`, 20–1000).
- **Even steps, approximate tempo.** The sequencers pick a 20–40 ms rate so that a step is
  exactly *K* ticks (at 120 BPM, 16ths are 5 × 25 ms). Steps are evenly spaced, and the
  tempo is within about 1% (0.4% slow at 120 BPM). Main-loop latency makes it run a
  little slower still; nudge it with `trim`.
- Gates, strums, glides and LFOs move in ticks of 20–40 ms.
- **Errors in `update` stop it silently.** If `system.update` raises an error, the firmware
  disables updates, so the scripts clamp every value they read.

## Memory

Measured on firmware 1.2.0 with probe scenes (the tools are in `tools/`):

- **Loading is the limit.** A script's *modeled load peak* (`test/e16host.c`: its "script peak
  (load)" plus the 11.9 KB base) must stay **≤ 42.5 KB**. Load probes load at 42.6 KB and fail at 43.5 KB.
- **While running,** the ceiling is higher: `probe.lua` runs out at a Lua count of 42.3 KB, which is
  about **46.6 KB** modeled.
- **Size** is not the constraint: 7,000-byte scripts load, and the app caps them at 8,000.

| script | uploaded | load peak | margin |
|---|---|---|---|
| modseq | 3.1 KB | 29.6 KB | 12.9 KB |
| euclid | 4.4 KB | 35.5 KB | 7.0 KB |
| chords | 5.1 KB | 36.9 KB | 5.6 KB |
| lfo | 5.4 KB | 40.9 KB | 1.6 KB |
| tb3po | 6.1 KB | 42.5 KB | 0.1 KB |
| example step sequencer | 6.2 KB | 43.6 KB | −1.1 KB (fails to load) |

All five scripts run on hardware. Scene variables are also limited: 32 per scene, and they outlive
script changes, so `lfo.lua` and `tb3po.lua` stamp a layout version and clear old variables
when it changes.

If a scene shows its default title and labels and doesn't respond, the script didn't fit. To
see errors on the device (there's no Lua Debug view), `tools/make_diag.py` makes a copy of a scene
that prints any Lua error across the labels.

## E16 Lua notes

Everything learned about the E16's Lua environment is collected in
[`docs/e16-lua-notes.md`](docs/e16-lua-notes.md), tagged by source (hardware, firmware, guide,
example, model). That includes limits, undocumented APIs, quirks, and the OXI App file
formats.

## Tests

Build Lua 5.4 with `#define LUA_32BITS 1` in `luaconf.h` so its numbers match the device,
then run the suites from the repo root:

    lua test/harness.lua euclid.lua
    lua test/lfo_test.lua
    lua test/chords_test.lua     # after tools/make_chords.py (it caches the sets in build/)
    lua test/modseq_test.lua
    lua test/tb3po_test.lua
    lua test/fuzz.lua tb3po.lua 2 600    # random input for 10 simulated minutes (pages: 12 for chords)

`test/fuzz.lua` matters on the E16: an error in `update()` silently stops a script's updates, so
the fuzzer throws random presses, turns, page changes and variable edits at a script and fails if
`update()` ever raises or a label is too long.

`test/e16mock.lua` is a reusable mock of the E16 API. The suites check the following:
- Euclid: every E(k, n) against a reference Bjorklund
- Chords: all 176 pads against their source voicings
- all scripts: timing, label lengths, page switching, persistence, ignoring non-physical events, and no per-tick garbage

`test/e16host.c` models the device heap: a 32-bit build, the heap_4 overhead, the firmware's
library set, and generational GC. For example, with Docker:

    docker run --rm --platform linux/386 -v "$PWD":/w -w /w i386/alpine:3.20 sh -c '
      apk add -q build-base && cd lua-5.4.7/src && make -s liblua.a &&
      cd /w && gcc -Os -o e16host test/e16host.c -Ilua-5.4.7/src lua-5.4.7/src/liblua.a -lm &&
      ./e16host euclid.lua'

## License

MIT (see `LICENSE`), except `tb3po.lua`, which is GPL-3.0 (see `LICENSES/GPL-3.0.txt`): it
ports the TB-3PO applet as modified in the GPL-3.0 Phazerville firmware. The original `TB3PO.h`
is Copyright (c) 2020 Logarhythm under the MIT license, and its notice is kept in the file.

The chord voicings in `chords.lua` come from the
[Impressive Chords](https://github.com/mestela/schwung-impressive-chords) sets by mestela.
