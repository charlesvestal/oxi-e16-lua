# Chord sets: generator, analyzer and web harness

Date: 2026-09-26. Status: approved design, not yet implemented.

## Goal

Replace the chord sets in `chords.lua` (taken from the Impressive Chords sets, which were
extracted from an Ableton plugin) with sets we write ourselves, released under MIT. What
matters is the **set**: 16 chords that work together on a 4×4 grid, not 16 good chords.
A local web harness lets us hear and measure sets in a tight loop instead of on the E16.

## What makes a set good (the yardstick)

Measured on the 11 current sets (16 pads each):

1. **One center, a few colors.** Functional sets are 10–14 of 16 diatonic; the rest are
   deliberate borrowed chords. Two sets are non-diatonic by design. That gives three
   **set types**:
   - `functional`: one key, rows are progressions (Pop Piano, Gospel, Neo Soul, Indie Jazz …)
   - `shape`: one or a few voicing shapes moved across many roots, often by 3rds (Detroit)
   - `pedal`: parallel chords under a nearly fixed top note (Impressionist; top moves 0.6 semitones per step)
2. **Rows read as progressions**, and any pad can follow any other.
3. **Tight register.** Bass about notes 39–52, top voice about 64–74 (Detroit: bass 30–42, wider spread).
4. **Smooth top line.** Top note moves 2–3 semitones on average between neighboring pads.
5. **Spread voicings, no mud.** A lone bass, a gap, then 3–6 upper notes. No interval under a
   minor 3rd below E3 (52), none under a 4th below A2 (45).
6. **Rich chords.** 4–7 notes, 9ths/11ths/13ths/sus, except deliberately plain sets (Pop Piano).

Weak spots to avoid: total voice movement of 29–33 semitones between some neighbors
(Chill House, Cinematic, Sad Ballads), and chords our namer can't label (12 of 176, mostly slash chords).

## Components

All under `tools/chordgen/`, Python 3 standard library only.

| unit | does | depends on |
|---|---|---|
| `theory.py` | pitch classes, chord-symbol parsing (`Dm9`, `Bbmaj7#11`, `F/A`, `C7sus4`), scales, key estimation (Krumhansl–Kessler), chord naming for 4-character labels | — |
| `voicer.py` | voices a whole set: candidate voicings per chord by style, then one path through the grid minimizing a cost | `theory` |
| `analyze.py` | set metrics (below) and reference ranges from a list of sets | `theory` |
| `specs/*.json` | one hand-written set spec per mood | — |
| `build.py` | specs → `build/chordgen/sets/<name>.chords` + `build/chordgen/data.json` (sets, reference sets, metrics, ranges) | all above |
| `serve.py` | serves the harness and `data.json`; `POST /feedback` writes `build/chordgen/feedback.json` | `build` |
| `harness/index.html` | the web harness (single file, inline JS/CSS, Web Audio) | `data.json` |

`tools/make_chords.py` gains `--dir DIR`: read `NAME.chords` from DIR instead of fetching,
so generated sets pack into `chords.lua` unchanged. The `.chords` format stays
(`Name: …` then `index: note,note,…`).

### Set spec

```json
{
  "name": "Neo Soul",
  "type": "functional",
  "key": "Ebm",
  "style": "rootless",
  "rows": [["Ebm9", "Abm11", "Bmaj7", "Bb7#9"],
           ["...", "...", "...", "..."],
           ["...", "...", "...", "..."],
           ["...", "...", "...", "..."]],
  "register": {"bass": [39, 52], "top": [64, 74]}
}
```

Optional fields: `reference` (slug of the current set to compare against in the harness) and
`shapes` (for `style: "shape"`: offsets above the bass per chord quality, e.g.
`{"m9": [0, 19, 22, 26, 27]}`; a quality without a shape uses its plain intervals).

`style` is one of `rootless` (3rd/7th-based upper structure plus extensions), `quartal`,
`open` (5ths and 9ths, wide), `close` (close triads/7ths), `shape` (one fixed interval
shape above the bass; the spec gives it as `"shape": [0, 7, 10, 14, 15]` or similar).
`register` is optional; defaults come from the yardstick.

### Voicer

- Bass: the root, or the slash note, placed in the bass range.
- Upper structure: candidates from the style, in every inversion that fits the top range.
- Hard rules: no mud (rule 5), 3–7 notes, bass within range, top within range.
- Choice: dynamic programming over the grid in pad order (rows left to right, then the
  next row), minimizing `a·voice movement + b·top-line step + c·distance from register
  centre`, with row-internal transitions weighted above row boundaries. `pedal` sets add a
  heavy cost on top-note movement; `shape` sets keep the shape fixed and choose only the
  octave of the root.
- Deterministic: the same spec always gives the same notes.

### Analyzer metrics

Per set: key and fit, diatonic count, distinct shapes, voice count range, bass and top
ranges, average span, average top-line step, voice movement (within rows, all neighbors,
maximum), root motion by interval class, mud count, unnamed chords. Reference ranges are
the min–max (and median) of each metric across the reference sets of the same type, or
all reference sets when a type has only one.

### Harness

- Set picker (generated sets, plus reference sets marked "reference, local only").
- A 4×4 grid laid out like the E16, labels as on the device.
- Play: click a pad; play a row; play the grid in order; random walk (random pad hops at a tempo).
- Controls like the E16 settings: transpose, octave, velocity, gate (Hold or seconds), strum ms, strum direction.
- Browser synth: two tones, electric piano (FM or additive with decay) and pad (detuned saws, low-pass, slow attack).
- Metrics panel: each metric with the reference range; out-of-range values flagged.
- Reference toggle: switch to the current set for the same mood (by name mapping) to compare.
- Feedback: per set keep / fix / drop and a note; per chord an optional note (click a pad's note field).
  Saved with `POST /feedback` to `build/chordgen/feedback.json`, keyed by set name and pad, with a timestamp.
- Works offline once served (`python3 tools/chordgen/serve.py`, then open the printed URL).

## Error handling

- Spec errors (unknown symbol, wrong row count, no voicing satisfies the hard rules) fail
  `build.py` with the set name, pad and reason.
- `serve.py` rejects feedback that isn't JSON; it writes via a temporary file and rename.
- The harness shows a message if `data.json` is missing (run `build.py`).

## Testing

`python3 -m unittest discover tools/chordgen/tests`:
- symbol parsing and naming round trips; labels fit 4 characters
- voicer hard rules hold for every chord of every spec
- analyzer reproduces the reference numbers above for Neo Soul Minor and Detroit Techno (from cached `.chords`)
- `build.py` output parses with `make_chords.py --dir`, and `lua test/chords_test.lua` passes on the generated `chords.lua`
  (the test reads source sets from `build/chordsets/`; it gains an optional directory argument,
  `lua test/chords_test.lua build/chordgen/sets`)

## Licensing

Specs, generated sets and tools: MIT. Reference sets are fetched into `build/` (gitignored)
and never committed or published. When generated sets replace the current ones,
`chords.lua` and the README drop the Impressive Chords attribution.

## First iteration

Three specs, one per type: **Neo Soul** (`functional`), **Detroit** (`shape`),
**Impressionist** (`pedal`). The other 8 moods follow once these sound right.

## Out of scope

Web MIDI output, A/B voicing variants, mining progressions from datasets, changes to `chords.lua` itself.
