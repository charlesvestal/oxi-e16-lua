# Chord Sets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tools to write our own chord sets for `chords.lua` (hand-written set specs, a voicer, an analyzer) and a local web harness to hear and measure sets against the current ones.

**Architecture:** Python standard-library tools in `tools/chordgen/`: `theory.py` (symbols, keys, voice leading), `analyze.py` (set metrics), `voicer.py` (specs → notes by dynamic programming over the 4×4 grid), `build.py` (specs → `.chords` files + `data.json`), `serve.py` (serves the harness, saves feedback). `harness/index.html` is a single page with a Web Audio synth. `tools/make_chords.py` gains `--dir` so generated sets pack into `chords.lua` unchanged.

**Tech Stack:** Python 3 (stdlib only, `unittest`), plain HTML/CSS/JS with Web Audio, Lua 5.4 (LUA_32BITS) for the existing `chords.lua` tests.

**User decisions (already made):**
- "Browser synth only" (no Web MIDI output).
- Feedback: "Rate + notes, saved to a file" (keep / fix / drop + notes, JSON I read).
- Reference sets: "Yes, local reference" (current sets playable in the harness, never published).
- "what's important is the SETS not just the chords": sets are judged and generated as a whole.
- Approach 1: hand-curated chord symbols + a voicing engine; first iteration Neo Soul, Detroit, Impressionist.

Design spec: `docs/superpowers/specs/2026-09-26-chord-sets-design.md`.

**Environment notes for the implementer:**
- Run everything from the repo root `/Volumes/ExtFS/charlesvestal/github/e16-euc`.
- There is no system Lua. A 32-bit Lua is built at
  `/private/tmp/claude-501/-Volumes-ExtFS-charlesvestal-github-e16-euc/0827e003-02cc-4ee7-b831-0047b26ad30f/scratchpad/lua-5.4.7/src/lua`;
  below it is called `$LUA`. Set it with
  `LUA=/private/tmp/claude-501/-Volumes-ExtFS-charlesvestal-github-e16-euc/0827e003-02cc-4ee7-b831-0047b26ad30f/scratchpad/lua-5.4.7/src/lua`.
- Reference sets are cached in `build/chordsets/*.chords` (gitignored). `make_chords.fetch(name)` downloads a missing one.
- `build/` is gitignored; never commit anything under it.

---

## File structure

| file | responsibility |
|---|---|
| `tools/make_chords.py` (modify) | add `read(path)` and `--dir DIR` |
| `test/chords_test.lua` (modify) | optional args: script, set directory, set names |
| `tools/chordgen/theory.py` | note/chord parsing, labels as on the device, key, scale, voice leading, mud |
| `tools/chordgen/analyze.py` | set metrics, reference ranges |
| `tools/chordgen/voicer.py` | spec loading/validation, candidates, costs, grid DP |
| `tools/chordgen/specs/neo_soul.json`, `detroit.json`, `impressionist.json` | the three set specs |
| `tools/chordgen/build.py` | specs → `build/chordgen/sets/*.chords`, `build/chordgen/data.json` |
| `tools/chordgen/serve.py` | HTTP server for the harness, `POST /feedback` |
| `tools/chordgen/harness/index.html` | the web harness |
| `tools/chordgen/tests/test_*.py` | unit tests |
| `README.md` (modify) | a short "Writing chord sets" section |

Tests run with: `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen`

Each test file starts with this path setup (the modules import each other by plain name):

```python
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
```

---

### Task 1: `make_chords.py --dir` and a configurable `chords_test.lua`

**Goal:** Generated `.chords` files can be packed into a copy of `chords.lua` and tested with the existing suite.

**Files:**
- Modify: `tools/make_chords.py` (`fetch`, `main`)
- Modify: `test/chords_test.lua` (header, `SETS`, `source`, `E.load`, title check)
- Create: `tools/chordgen/tests/test_make_chords.py`

**Acceptance Criteria:**
- [ ] `make_chords.read(path)` returns `(title, {index: sorted notes})` for a `.chords` file
- [ ] `python3 tools/make_chords.py --dir DIR TARGET NAME...` reads `DIR/NAME.chords` and never downloads
- [ ] `$LUA test/chords_test.lua` (no args) still prints `ALL PASSED`
- [ ] `$LUA test/chords_test.lua SCRIPT DIR NAME...` tests SCRIPT against DIR's sets, with titles from their `Name:` lines

**Verify:** `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_make_chords.py' -v` → OK; `$LUA test/chords_test.lua | tail -1` → `ALL PASSED`

**Steps:**

- [ ] **Step 1: Write the failing test** — `tools/chordgen/tests/test_make_chords.py`

```python
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
import make_chords  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


class ReadTest(unittest.TestCase):
    def test_read_parses_name_and_sorted_notes(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "x.chords")
            open(p, "w").write("Name: Test Set\n0: 64,48,60\n1: 50,62\n")
            title, chords = make_chords.read(p)
        self.assertEqual(title, "Test Set")
        self.assertEqual(chords, {0: [48, 60, 64], 1: [50, 62]})

    def test_dir_option_packs_local_sets(self):
        with tempfile.TemporaryDirectory() as d:
            lines = ["Name: Local One"] + [f"{i}: {48 + i},{55 + i},{64 + i}" for i in range(16)]
            open(os.path.join(d, "local_one.chords"), "w").write("\n".join(lines) + "\n")
            target = os.path.join(d, "chords.lua")
            open(target, "w").write(open(os.path.join(ROOT, "chords.lua")).read())
            r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "make_chords.py"),
                                "--dir", d, target, "local_one"], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            src = open(target).read()
        self.assertIn("local T = [=[Local One]=]", src)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_make_chords.py' -v`
Expected: FAIL / ERROR with `module 'make_chords' has no attribute 'read'`.

- [ ] **Step 3: Implement in `tools/make_chords.py`**

Replace the body of `fetch` and add `read` above it:

```python
def read(path):
    """Parse a .chords file: (title, {index: sorted notes})."""
    title, chords = os.path.splitext(os.path.basename(path))[0], {}
    for line in open(path, encoding="utf-8"):
        m = re.match(r"\s*Name:\s*(.+)", line)
        if m:
            title = m.group(1).strip()
        m = re.match(r"\s*(\d+):\s*([\d,\s]+)", line)
        if m:
            chords[int(m.group(1))] = sorted({int(x) for x in m.group(2).split(",") if x.strip()})
    return title, chords


def fetch(name, directory=None):
    """A set by name: from DIRECTORY if given, else the Impressive Chords cache (downloading it once)."""
    if directory:
        return read(os.path.join(directory, name + ".chords"))
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name + ".chords")
    if not os.path.exists(path):
        with urllib.request.urlopen(RAW.format(name)) as r:
            open(path, "wb").write(r.read())
    return read(path)
```

In `main`, replace the first two lines with:

```python
    args, directory = sys.argv[1:], None
    if "--dir" in args:
        i = args.index("--dir")
        directory = args[i + 1]
        del args[i:i + 2]
    target, specs = args[0], args[1:]
```

and change `title, chords = fetch(name)` to `title, chords = fetch(name, directory)`.
Update the docstring's usage line to `usage: make_chords.py [--dir DIR] chords.lua SET[:START] ... (up to 11 sets)`
and add a sentence: `With --dir, sets are read from DIR/SET.chords instead of Impressive Chords.`

- [ ] **Step 4: Make `test/chords_test.lua` configurable**

Replace the header comment and `SETS` (lines 1–8) with:

```lua
-- Tests for chords.lua. Run from the repo root with a LUA_32BITS Lua, after
-- tools/make_chords.py has filled the data (it caches sets in build/chordsets):
--   lua test/chords_test.lua [SCRIPT DIR SET...]
-- With arguments, SCRIPT is tested against the sets DIR/SET.chords, one per page.
local E = dofile("test/e16mock.lua")
local check = E.check

local SCRIPT, DIR = arg[1] or "chords.lua", arg[2] or "build/chordsets"
local SETS = {"cinematic", "chill_house", "gospel_soul", "neo_soul_minor", "lofi_rb_1",
  "indie_jazz", "detroit_techno", "lush_pads", "pop_piano", "impressionist", "sad_ballads"}
if arg[3] then SETS = {table.unpack(arg, 3)} end
```

In `source`, change `io.lines("build/chordsets/" .. set .. ".chords")` to `io.lines(DIR .. "/" .. set .. ".chords")`.
Add below `source`:

```lua
-- a set's title as chords.lua shows it (Name: line, 15 characters)
local function title(set)
  for line in io.lines(DIR .. "/" .. set .. ".chords") do
    local t = line:match("^%s*Name:%s*(.-)%s*$")
    if t then return t:sub(1, 15) end
  end
  return set:sub(1, 15)
end
```

Change both `E.load("chords.lua")` (lines 49 and 160) to `E.load(SCRIPT)`.
Change every `for pg = 1, 11 do` to `for pg = 1, #SETS do`.
Replace the title check (line 75) with:

```lua
local want = {}
for pg = 1, #SETS do want[pg] = title(SETS[pg]) end
check(table.concat(titles, ",") == table.concat(want, ","), "titles per page: " .. table.concat(titles, ", "))
```

- [ ] **Step 5: Run both checks**

Run: `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_make_chords.py' -v`
Expected: 2 tests OK.
Run: `$LUA test/chords_test.lua | tail -1`
Expected: `ALL PASSED`

- [ ] **Step 6: Commit**

```bash
git add tools/make_chords.py test/chords_test.lua tools/chordgen/tests/test_make_chords.py
git commit -m "make_chords --dir reads local sets; chords_test takes a script and set directory"
```

---

### Task 2: `theory.py`

**Goal:** Chord symbols, device labels, keys, scales, voice leading and the mud rule in one module.

**Files:**
- Create: `tools/chordgen/theory.py`
- Create: `tools/chordgen/tests/test_theory.py`

**Acceptance Criteria:**
- [ ] `parse("Ebm9") == (3, (0, 3, 7, 10, 14), None, "m9")`; `parse("F/A") == (5, (0, 4, 7), 9, "")`; aliases (`M7`, `sus`, `h7` …) resolve
- [ ] unknown roots or qualities raise `ValueError` naming the symbol
- [ ] `label(notes)` matches `chords.lua`'s label (minor → lowercase root, 4 characters, unnamed → bass name + `?`)
- [ ] `vl`, `mud`, `key`, `scale` behave as in the tests

**Verify:** `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_theory.py' -v` → OK

**Steps:**

- [ ] **Step 1: Write the failing tests** — `tools/chordgen/tests/test_theory.py`

```python
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import theory  # noqa: E402


class ParseTest(unittest.TestCase):
    def test_minor_ninth(self):
        self.assertEqual(theory.parse("Ebm9"), (3, (0, 3, 7, 10, 14), None, "m9"))

    def test_slash(self):
        self.assertEqual(theory.parse("F/A"), (5, (0, 4, 7), 9, ""))

    def test_flat_root_and_long_quality(self):
        self.assertEqual(theory.parse("Bbmaj7#11")[0], 10)
        self.assertEqual(theory.parse("Bbmaj7#11")[3], "maj7#11")

    def test_aliases(self):
        self.assertEqual(theory.parse("CM7")[3], "maj7")
        self.assertEqual(theory.parse("Csus")[3], "sus4")
        self.assertEqual(theory.parse("Bh7")[3], "m7b5")

    def test_errors_name_the_symbol(self):
        with self.assertRaisesRegex(ValueError, "Hm7"):
            theory.parse("Hm7")
        with self.assertRaisesRegex(ValueError, "Cxyz"):
            theory.parse("Cxyz")

    def test_pcs_include_slash_bass(self):
        self.assertEqual(theory.pcs("C/Bb"), {0, 4, 7, 10})


class LabelTest(unittest.TestCase):
    def test_minor_is_lowercase(self):
        self.assertEqual(theory.label([39, 58, 61, 66]), "d#7")     # D#m7

    def test_major_seventh(self):
        self.assertEqual(theory.label([48, 64, 67, 71]), "CM7")

    def test_unnamed_is_bass_and_question_mark(self):
        self.assertEqual(theory.label([48, 49, 50, 51]), "C?")

    def test_four_characters(self):
        self.assertLessEqual(len(theory.label([48, 64, 67, 71, 78])), 4)


class ToolsTest(unittest.TestCase):
    def test_vl_pairs_voices(self):
        self.assertEqual(theory.vl([60, 64, 67], [60, 65, 69]), 3)

    def test_vl_extra_voice_goes_to_nearest(self):
        self.assertEqual(theory.vl([60, 64, 67], [60, 64, 67, 70]), 3)

    def test_mud(self):
        self.assertEqual(theory.mud([40, 43, 47]), 2)      # 40-43 and 43-47 under a 4th below A2
        self.assertEqual(theory.mud([40, 52, 55, 59]), 0)
        self.assertEqual(theory.mud([48, 50, 55]), 1)      # a 2nd below E3

    def test_key_of_c_major_triads(self):
        chords = [[48, 52, 55], [53, 57, 60], [55, 59, 62], [48, 52, 55]]
        fit, k, q = theory.key(chords)
        self.assertEqual((k, q), (0, ""))

    def test_scale(self):
        self.assertEqual(theory.scale(9, "m"), {9, 11, 0, 2, 4, 5, 7})


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_theory.py' -v`
Expected: ERROR `No module named 'theory'`.

- [ ] **Step 3: Implement `tools/chordgen/theory.py`**

```python
"""Music theory for the chord-set tools: chord symbols, device labels, keys,
scales, voice leading and the low-interval ("mud") rule."""
import itertools
import os
import statistics as st
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import make_chords  # noqa: E402  (chords.lua's namer: labels must match the device)

NAMES = "C C# D D# E F F# G G# A A# B".split()
LETTER = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

# Intervals above the root. Tensions keep their octave (9th = 14) so voicings can use it.
QUALITY = {
    "": (0, 4, 7), "m": (0, 3, 7), "dim": (0, 3, 6), "aug": (0, 4, 8), "5": (0, 7),
    "sus2": (0, 2, 7), "sus4": (0, 5, 7), "add9": (0, 4, 7, 14), "madd9": (0, 3, 7, 14),
    "6": (0, 4, 7, 9), "m6": (0, 3, 7, 9), "69": (0, 4, 7, 9, 14), "m69": (0, 3, 7, 9, 14),
    "7": (0, 4, 7, 10), "maj7": (0, 4, 7, 11), "m7": (0, 3, 7, 10), "mmaj7": (0, 3, 7, 11),
    "m7b5": (0, 3, 6, 10), "dim7": (0, 3, 6, 9), "7sus4": (0, 5, 7, 10),
    "9": (0, 4, 7, 10, 14), "maj9": (0, 4, 7, 11, 14), "m9": (0, 3, 7, 10, 14),
    "9sus4": (0, 5, 7, 10, 14), "mmaj9": (0, 3, 7, 11, 14),
    "11": (0, 7, 10, 14, 17), "m11": (0, 3, 7, 10, 14, 17),
    "maj7#11": (0, 4, 7, 11, 18), "maj9#11": (0, 4, 7, 11, 14, 18),
    "13": (0, 4, 7, 10, 14, 21), "m13": (0, 3, 7, 10, 14, 21), "maj13": (0, 4, 7, 11, 14, 21),
    "13sus4": (0, 5, 7, 10, 14, 21),
    "7b9": (0, 4, 7, 10, 13), "7#9": (0, 4, 7, 10, 15), "7#11": (0, 4, 7, 10, 18),
    "7b13": (0, 4, 7, 10, 20), "m7b9": (0, 3, 7, 10, 13),
}
ALIAS = {"M7": "maj7", "M9": "maj9", "M13": "maj13", "M7#11": "maj7#11", "M9#11": "maj9#11",
         "min": "m", "-": "m", "sus": "sus4", "7sus": "7sus4", "9sus": "9sus4",
         "o": "dim", "o7": "dim7", "h7": "m7b5", "+": "aug", "mM7": "mmaj7", "mM9": "mmaj9"}

# Krumhansl-Kessler key profiles (C major, C minor)
MAJOR = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
MINOR = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]


def pc(name):
    """Pitch class of a note name: C, F#, Bb."""
    if not name or name[0] not in LETTER:
        raise ValueError(f"bad note name {name!r}")
    p = LETTER[name[0]]
    for a in name[1:]:
        if a == "#":
            p += 1
        elif a == "b":
            p -= 1
        else:
            raise ValueError(f"bad note name {name!r}")
    return p % 12


def parse(symbol):
    """'Ebm9' -> (root pc, intervals, slash bass pc or None, quality name)."""
    body, _, bass = symbol.partition("/")
    i = 1
    while i < len(body) and body[i] in "#b":
        i += 1
    try:
        root = pc(body[:i])
        slash = pc(bass) if bass else None
    except ValueError:
        raise ValueError(f"bad chord symbol {symbol!r}") from None
    q = ALIAS.get(body[i:], body[i:])
    if q not in QUALITY:
        raise ValueError(f"unknown chord quality {body[i:]!r} in {symbol!r}")
    return root, QUALITY[q], slash, q


def pcs(symbol):
    """Pitch classes of a symbol, slash bass included."""
    root, ivs, slash, _ = parse(symbol)
    s = {(root + i) % 12 for i in ivs}
    return s | {slash} if slash is not None else s


def label(notes):
    """The pad label chords.lua shows for these notes (untransposed)."""
    nm = make_chords.name_chord(notes)
    if nm is None:
        return NAMES[min(notes) % 12] + "?"
    n, x = NAMES[nm[0]], make_chords.SUF[nm[1]]
    if x.startswith("m"):
        n, x = n.lower(), x[1:]
    return (n + x)[:4]


def vl(a, b):
    """Voice-leading distance: total semitones moved, pairing voices in order;
    voices without a partner move to the nearest note of the other chord."""
    a, b = sorted(a), sorted(b)
    if len(a) > len(b):
        a, b = b, a
    best = None
    for combo in itertools.combinations(range(len(b)), len(a)):
        cost = sum(abs(a[i] - b[j]) for i, j in enumerate(combo))
        cost += sum(min(abs(b[j] - x) for x in a) for j in range(len(b)) if j not in combo)
        best = cost if best is None else min(best, cost)
    return best


def mud(notes):
    """Adjacent intervals below the low-interval limits: under a minor 3rd below
    E3 (52), under a 4th below A2 (45)."""
    s = sorted(notes)
    return sum(1 for x, y in zip(s, s[1:]) if (x < 52 and y - x < 3) or (x < 45 and y - x < 5))


def _corr(a, b):
    ma, mb = st.mean(a), st.mean(b)
    num = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    den = (sum((x - ma) ** 2 for x in a) * sum((y - mb) ** 2 for y in b)) ** 0.5
    return num / den if den else 0.0


def key(chords):
    """Best-fitting key: (correlation, tonic pc, "" major / "m" minor)."""
    h = [0] * 12
    for c in chords:
        for n in c:
            h[n % 12] += 1
    return max((_corr(h, p[-k:] + p[:-k]), k, q)
               for k in range(12) for q, p in (("", MAJOR), ("m", MINOR)))


def scale(k, q):
    """Pitch classes of the major or natural minor scale on k."""
    steps = [0, 2, 4, 5, 7, 9, 11] if q == "" else [0, 2, 3, 5, 7, 8, 10]
    return {(k + s) % 12 for s in steps}
```

- [ ] **Step 4: Run tests**

Run: `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_theory.py' -v`
Expected: all OK. If `test_major_seventh` fails because the namer returns a different suffix, print `theory.label([48, 64, 67, 71])` and fix the test's expectation only if it matches what `chords.lua` would show (the namer is authoritative).

- [ ] **Step 5: Commit**

```bash
git add tools/chordgen/theory.py tools/chordgen/tests/test_theory.py
git commit -m "chordgen: theory module (symbols, labels, keys, voice leading, mud)"
```

---

### Task 3: `analyze.py`

**Goal:** Measure a set the way the design's yardstick does, and derive reference ranges.

**Files:**
- Create: `tools/chordgen/analyze.py`
- Create: `tools/chordgen/tests/test_analyze.py`

**Acceptance Criteria:**
- [ ] `metrics(chords)` returns every name in `METRICS` plus `key` and `fit`
- [ ] On Neo Soul Minor pads 1–16 it reproduces: diatonic 13, shapes 15, bass 39–47, top 58–70, top_step 2.4, vl_row 9.8, mud 0, key `F#`
- [ ] On Detroit Techno: shapes 8, bass 30–42
- [ ] `ranges(list)` gives `[min, median, max]` per metric

**Verify:** `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_analyze.py' -v` → OK

**Steps:**

- [ ] **Step 1: Write the failing tests** — `tools/chordgen/tests/test_analyze.py`

```python
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
import analyze  # noqa: E402
import make_chords  # noqa: E402


def pads(name):
    _, ch = make_chords.fetch(name)
    return [ch[i] for i in range(16)]


class ReferenceTest(unittest.TestCase):
    def test_neo_soul_minor(self):
        m = analyze.metrics(pads("neo_soul_minor"))
        self.assertEqual((m["diatonic"], m["shapes"]), (13, 15))
        self.assertEqual((m["bass_lo"], m["bass_hi"], m["top_lo"], m["top_hi"]), (39, 47, 58, 70))
        self.assertEqual((m["top_step"], m["vl_row"], m["mud"]), (2.4, 9.8, 0))
        self.assertEqual(m["key"], "F#")

    def test_detroit(self):
        m = analyze.metrics(pads("detroit_techno"))
        self.assertEqual((m["shapes"], m["bass_lo"], m["bass_hi"]), (8, 30, 42))

    def test_all_metrics_present(self):
        m = analyze.metrics(pads("cinematic"))
        for k in analyze.METRICS + ["key", "fit"]:
            self.assertIn(k, m)


class RangesTest(unittest.TestCase):
    def test_min_median_max(self):
        ms = [dict.fromkeys(analyze.METRICS, v) for v in (1, 2, 10)]
        r = analyze.ranges(ms)
        self.assertEqual(r["span"], [1, 2, 10])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_analyze.py' -v`
Expected: ERROR `No module named 'analyze'`.

- [ ] **Step 3: Implement `tools/chordgen/analyze.py`**

```python
"""Set metrics: how a 16-pad chord set sits (key, register, top line, voice
leading, mud), and reference ranges across sets."""
import statistics as st

from theory import NAMES, key, label, mud, scale, vl

# numeric metrics, in the order the harness shows them
METRICS = ["diatonic", "shapes", "voices_min", "voices_max", "bass_lo", "bass_hi",
           "top_lo", "top_hi", "span", "top_step", "vl_row", "vl_all", "vl_max",
           "mud", "unnamed"]


def metrics(chords):
    """chords: 16 note lists in pad order (row by row)."""
    fit, k, q = key(chords)
    sc = scale(k, q)
    bass = [min(c) for c in chords]
    top = [max(c) for c in chords]
    moves = [vl(a, b) for a, b in zip(chords, chords[1:])]
    in_rows = [v for i, v in enumerate(moves) if i % 4 != 3]
    return {
        "key": NAMES[k] + q, "fit": round(fit, 2),
        "diatonic": sum(1 for c in chords if {n % 12 for n in c} <= sc),
        "shapes": len({tuple(n - min(c) for n in sorted(c)) for c in chords}),
        "voices_min": min(map(len, chords)), "voices_max": max(map(len, chords)),
        "bass_lo": min(bass), "bass_hi": max(bass), "top_lo": min(top), "top_hi": max(top),
        "span": round(st.mean(t - b for t, b in zip(top, bass)), 1),
        "top_step": round(st.mean(abs(b - a) for a, b in zip(top, top[1:])), 1),
        "vl_row": round(st.mean(in_rows), 1), "vl_all": round(st.mean(moves), 1),
        "vl_max": max(moves),
        "mud": sum(mud(c) for c in chords),
        "unnamed": sum(1 for c in chords if label(c).endswith("?")),
    }


def ranges(all_metrics):
    """{metric: [min, median, max]} over a list of metrics dicts."""
    out = {}
    for m in METRICS:
        v = [x[m] for x in all_metrics]
        out[m] = [min(v), round(st.median(v), 1), max(v)]
    return out
```

- [ ] **Step 4: Run tests**

Run: `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_analyze.py' -v`
Expected: all OK (needs network once if `build/chordsets/` is empty; `make_chords.fetch` caches).

- [ ] **Step 5: Commit**

```bash
git add tools/chordgen/analyze.py tools/chordgen/tests/test_analyze.py
git commit -m "chordgen: set metrics and reference ranges"
```

---

### Task 4: `voicer.py`

**Goal:** Turn a set spec into 16 voicings that obey the hard rules and move smoothly across the grid.

**Files:**
- Create: `tools/chordgen/voicer.py`
- Create: `tools/chordgen/tests/test_voicer.py`

**Acceptance Criteria:**
- [ ] `load_spec(path)` validates: 4 rows × 4 symbols, `type` in functional/shape/pedal, `style` in rootless/quartal/open/close/shape, every symbol parses; errors name the set and pad
- [ ] Every voicing: bass pc = root (or slash) pc, bass and top inside the register, `mud == 0`, 3–7 notes, all notes in the chord's pitch classes
- [ ] Same spec → same notes
- [ ] A `pedal` set's top note moves ≤ 1 semitone per pad on average
- [ ] A spec that cannot fit raises `VoicingError` naming the pad

**Verify:** `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_voicer.py' -v` → OK

**Steps:**

- [ ] **Step 1: Write the failing tests** — `tools/chordgen/tests/test_voicer.py`

```python
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import theory  # noqa: E402
import voicer  # noqa: E402

FUNCTIONAL = {
    "name": "Test Functional", "type": "functional", "key": "C", "style": "rootless",
    "rows": [["Cmaj9", "Am9", "Dm11", "G13"], ["Em7", "A7b9", "Dm9", "G7sus4"],
             ["Fmaj7#11", "Em11", "Am9", "D9"], ["Dm9", "G13", "Cmaj9", "C6"]],
}
PEDAL = {
    "name": "Test Pedal", "type": "pedal", "key": "E", "style": "open",
    "rows": [["Emaj9", "Cmaj7#11", "Amaj9", "Fmaj7#11"], ["Gmaj7", "D69", "Bm11", "C#m11"],
             ["G#m7", "Db9sus4", "Fm7b5", "E6"], ["A69", "G6", "Cmaj7#11", "Esus2"]],
}


class HardRulesTest(unittest.TestCase):
    def check(self, spec):
        reg = voicer.register(spec)
        out = voicer.voice_set(spec)
        syms = [s for r in spec["rows"] for s in r]
        self.assertEqual(len(out), 16)
        for sym, notes in zip(syms, out):
            root, _, slash, _ = theory.parse(sym)
            self.assertEqual(notes[0] % 12, root if slash is None else slash, sym)
            self.assertTrue(reg["bass"][0] <= notes[0] <= reg["bass"][1], (sym, notes))
            self.assertTrue(reg["top"][0] <= notes[-1] <= reg["top"][1], (sym, notes))
            self.assertEqual(theory.mud(notes), 0, (sym, notes))
            self.assertTrue(3 <= len(notes) <= 7, (sym, notes))
            self.assertLessEqual({n % 12 for n in notes}, theory.pcs(sym), (sym, notes))
        return out

    def test_functional(self):
        self.check(FUNCTIONAL)

    def test_pedal_holds_the_top(self):
        out = self.check(PEDAL)
        tops = [c[-1] for c in out]
        self.assertLessEqual(sum(abs(b - a) for a, b in zip(tops, tops[1:])) / 15, 1.0, tops)

    def test_shape(self):
        spec = {"name": "Test Shape", "type": "shape", "key": "Am", "style": "shape",
                "register": {"bass": [30, 42], "top": [56, 72]},
                "shapes": {"m9": [0, 19, 22, 26, 27]},
                "rows": [["Am9", "Cm9", "Ebm9", "F#m9"]] * 4}
        out = self.check(spec)
        self.assertEqual([n - out[0][0] for n in out[0]], [0, 19, 22, 26, 27])

    def test_deterministic(self):
        self.assertEqual(voicer.voice_set(FUNCTIONAL), voicer.voice_set(FUNCTIONAL))


class ErrorsTest(unittest.TestCase):
    def test_impossible_register_names_the_pad(self):
        spec = dict(FUNCTIONAL, register={"bass": [39, 52], "top": [60, 61]})
        with self.assertRaisesRegex(voicer.VoicingError, "pad 1 .Cmaj9."):
            voicer.voice_set(spec)

    def test_bad_rows(self):
        with self.assertRaisesRegex(ValueError, "4 rows of 4"):
            voicer.validate(dict(FUNCTIONAL, rows=[["C"]]))

    def test_bad_symbol_names_pad(self):
        rows = [r[:] for r in FUNCTIONAL["rows"]]
        rows[1][2] = "Qm7"
        with self.assertRaisesRegex(ValueError, "pad 7"):
            voicer.validate(dict(FUNCTIONAL, rows=rows))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_voicer.py' -v`
Expected: ERROR `No module named 'voicer'`.

- [ ] **Step 3: Implement `tools/chordgen/voicer.py`**

```python
"""Voice a chord set: pick notes for 16 chord symbols so the set sits in one
register, never gets muddy, and moves smoothly from pad to pad.

Candidates come from the spec's style; one path through the grid (row by row)
is chosen by dynamic programming over voice movement, top-line steps,
register and style costs."""
import itertools
import json

from theory import mud, parse, vl

TYPES = ("functional", "shape", "pedal")
STYLES = ("rootless", "quartal", "open", "close", "shape")
DEFAULT_REGISTER = {"bass": [39, 52], "top": [64, 74]}
MAX_CANDIDATES = 40      # per pad, cheapest first
ROW_WEIGHT, EDGE_WEIGHT = 1.0, 0.5   # transitions inside a row count more than row to row


class VoicingError(ValueError):
    pass


def validate(spec):
    name = spec.get("name", "?")
    rows = spec.get("rows")
    if not (isinstance(rows, list) and len(rows) == 4 and all(isinstance(r, list) and len(r) == 4 for r in rows)):
        raise ValueError(f"{name}: rows must be 4 rows of 4 chord symbols")
    if spec.get("type") not in TYPES:
        raise ValueError(f"{name}: type must be one of {', '.join(TYPES)}")
    if spec.get("style") not in STYLES:
        raise ValueError(f"{name}: style must be one of {', '.join(STYLES)}")
    for i, sym in enumerate(s for r in rows for s in r):
        try:
            parse(sym)
        except ValueError as e:
            raise ValueError(f"{name}: pad {i + 1}: {e}") from None
    return spec


def load_spec(path):
    return validate(json.load(open(path, encoding="utf-8")))


def register(spec):
    return {**DEFAULT_REGISTER, **spec.get("register", {})}


def upper_pcs(root, ivs, style):
    """Pitch classes above the bass. Rootless drops the root; every style drops
    the 5th when there are enough other colors."""
    tones = [i for i in ivs if i != 0] if style == "rootless" else list(ivs)
    if len(tones) > (3 if style == "rootless" else 5) and 7 in tones:
        tones.remove(7)
    seen, out = set(), []
    for i in tones:
        p = (root + i) % 12
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def candidates(symbol, spec, reg):
    root, ivs, slash, quality = parse(symbol)
    b = root if slash is None else slash
    basses = [n for n in range(reg["bass"][0], reg["bass"][1] + 1) if n % 12 == b]
    lo, hi = reg["top"]
    out = []
    for bass in basses:
        if spec["style"] == "shape":
            shape = spec.get("shapes", {}).get(quality, list(ivs))
            uppers = [tuple(bass + s for s in shape if s > 0)]
        else:
            choices = [[n for n in range(bass + 1, hi + 1) if n % 12 == p]
                       for p in upper_pcs(root, ivs, spec["style"])]
            uppers = itertools.product(*choices)
        for up in uppers:
            notes = tuple(sorted((bass,) + tuple(up)))
            if len(set(notes)) != len(notes) or notes[0] != bass:
                continue
            if not (lo <= notes[-1] <= hi and 3 <= len(notes) <= 7) or mud(notes):
                continue
            out.append(notes)
    return out


def node_cost(notes, style, reg):
    """Register distance plus how well the spacing fits the style."""
    bass, up = notes[0], notes[1:]
    gaps = [b - a for a, b in zip(up, up[1:])]
    c = 0.3 * abs(bass - sum(reg["bass"]) / 2) + 0.5 * abs(up[-1] - sum(reg["top"]) / 2)
    c += 0.5 * max(0, 7 - (up[0] - bass))          # a lone bass, then a gap
    if style == "close":
        c += sum(max(0, g - 4) for g in gaps)
    elif style == "open":
        c += sum(max(0, 5 - g) for g in gaps)
    elif style == "quartal":
        c += sum(0 if g in (5, 6) else 2 for g in gaps)
    elif style == "rootless":
        c += sum(max(0, g - 5) for g in gaps) + 3 * (up[-1] - up[0] > 12)
    return c


def move_cost(a, b, pedal):
    return vl(a, b) + (6 if pedal else 1) * abs(a[-1] - b[-1])


def voice_set(spec):
    """16 voicings (lists of MIDI notes, low to high) in pad order."""
    validate(spec)
    reg, style, pedal = register(spec), spec["style"], spec["type"] == "pedal"
    syms = [s for r in spec["rows"] for s in r]
    cands, costs = [], []
    for i, sym in enumerate(syms):
        cs = candidates(sym, spec, reg)
        if not cs:
            raise VoicingError(f"{spec['name']}: pad {i + 1} ({sym}): no voicing fits "
                               f"bass {reg['bass']} / top {reg['top']} without mud")
        cs.sort(key=lambda n: (node_cost(n, style, reg), n))
        cs = cs[:MAX_CANDIDATES]
        cands.append(cs)
        costs.append([node_cost(n, style, reg) for n in cs])
    total, back = costs[0][:], []
    for i in range(1, len(syms)):
        w = EDGE_WEIGHT if i % 4 == 0 else ROW_WEIGHT
        new, bk = [], []
        for k, n in enumerate(cands[i]):
            j = min(range(len(cands[i - 1])),
                    key=lambda j: (total[j] + w * move_cost(cands[i - 1][j], n, pedal), j))
            new.append(total[j] + w * move_cost(cands[i - 1][j], n, pedal) + costs[i][k])
            bk.append(j)
        total = new
        back.append(bk)
    j = min(range(len(total)), key=lambda j: (total[j], j))
    path = [j]
    for bk in reversed(back):
        j = bk[j]
        path.append(j)
    path.reverse()
    return [list(cands[i][p]) for i, p in enumerate(path)]
```

- [ ] **Step 4: Run tests**

Run: `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_voicer.py' -v`
Expected: all OK within a few seconds. If `test_pedal_holds_the_top` fails, raise the pedal weight in `move_cost` (6 → 10) and rerun; do not loosen the test.

- [ ] **Step 5: Commit**

```bash
git add tools/chordgen/voicer.py tools/chordgen/tests/test_voicer.py
git commit -m "chordgen: voicer (style candidates, hard rules, grid DP)"
```

---

### Task 5: The three set specs and `build.py`

**Goal:** `python3 tools/chordgen/build.py` writes the three generated sets as `.chords` files and a `data.json` with generated and reference sets, metrics and ranges; the sets pack into a copy of `chords.lua` that passes its tests.

**Files:**
- Create: `tools/chordgen/specs/neo_soul.json`, `tools/chordgen/specs/detroit.json`, `tools/chordgen/specs/impressionist.json`
- Create: `tools/chordgen/build.py`
- Create: `tools/chordgen/tests/test_build.py`
- Modify: `docs/superpowers/specs/2026-09-26-chord-sets-design.md` (spec format: optional `reference`, `shapes`)

**Acceptance Criteria:**
- [ ] `build.py` writes `build/chordgen/sets/{neo_soul,detroit,impressionist}.chords` (16 chords each) and `build/chordgen/data.json`
- [ ] `data.json`: `sets` has 3 `generated` + 11 `reference` entries (reference slugs prefixed `ref_`), each with `name, slug, type, source, reference, pads[{symbol, notes, label}], metrics`; `ranges` has `functional`, `shape`, `pedal`
- [ ] a spec error exits non-zero with the set and pad in the message
- [ ] `make_chords.py --dir build/chordgen/sets` packs the three sets into a copy of `chords.lua`; `$LUA test/chords_test.lua build/chordgen/chords.lua build/chordgen/sets neo_soul detroit impressionist` → `ALL PASSED`; `$LUA test/fuzz.lua build/chordgen/chords.lua 12 600` → `ok`

**Verify:** `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -v` → OK, then the two Lua commands above.

**Steps:**

- [ ] **Step 1: Write the specs**

`tools/chordgen/specs/neo_soul.json` (E♭ minor; rows are progressions; row 4 ends on D♭9sus4, which leads back to pad 1):

```json
{
  "name": "Neo Soul",
  "type": "functional",
  "key": "Ebm",
  "style": "rootless",
  "reference": "neo_soul_minor",
  "rows": [
    ["Ebm9", "Abm11", "Bmaj9", "Bb7#9"],
    ["Gbmaj9", "Fm7b5", "Bb7b9", "Ebm11"],
    ["Bmaj7#11", "Bbm7", "Abm9", "Db13"],
    ["Gbmaj7", "Fm7", "Ebm9", "Db9sus4"]
  ]
}
```

`tools/chordgen/specs/detroit.json` (one minor-9 and one major-9 shape, roots moving by minor 3rds; low root, cluster an octave and more above):

```json
{
  "name": "Detroit",
  "type": "shape",
  "key": "Am",
  "style": "shape",
  "reference": "detroit_techno",
  "register": {"bass": [30, 42], "top": [56, 72]},
  "shapes": {"m9": [0, 19, 22, 26, 27], "maj9": [0, 19, 23, 26, 28]},
  "rows": [
    ["Am9", "Cm9", "Ebm9", "F#m9"],
    ["Fm9", "Abm9", "Bm9", "Dm9"],
    ["Emaj9", "Gmaj9", "Bbmaj9", "Dbmaj9"],
    ["Dm9", "Fmaj9", "Am9", "Cmaj9"]
  ]
}
```

`tools/chordgen/specs/impressionist.json` (every chord contains B, held on top as a pedal):

```json
{
  "name": "Impressionist",
  "type": "pedal",
  "key": "E",
  "style": "open",
  "reference": "impressionist",
  "register": {"bass": [36, 52], "top": [71, 71]},
  "rows": [
    ["Emaj9", "Cmaj7#11", "Amaj9", "Fmaj7#11"],
    ["Gmaj7", "D69", "Bm11", "C#m11"],
    ["G#m7", "Db9sus4", "Fm7b5", "E6"],
    ["A69", "G6", "Cmaj7#11", "Esus2"]
  ]
}
```

(`top: [71, 71]` pins the top voice to B4. If the voicer reports a pad with no voicing, widen to `[64, 74]` and rely on the pedal cost.)

- [ ] **Step 2: Write the failing test** — `tools/chordgen/tests/test_build.py`

```python
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
import build  # noqa: E402
import make_chords  # noqa: E402


class BuildTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        build.build(cls.tmp.name)
        cls.data = json.load(open(os.path.join(cls.tmp.name, "data.json")))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_chords_files(self):
        for slug in ("neo_soul", "detroit", "impressionist"):
            title, chords = make_chords.read(os.path.join(self.tmp.name, "sets", slug + ".chords"))
            self.assertEqual(sorted(chords), list(range(16)), slug)

    def test_data_sets(self):
        src = [s["source"] for s in self.data["sets"]]
        self.assertEqual((src.count("generated"), src.count("reference")), (3, 11))
        s = next(s for s in self.data["sets"] if s["slug"] == "neo_soul")
        self.assertEqual(s["reference"], "neo_soul_minor")
        self.assertIn("ref_neo_soul_minor", [x["slug"] for x in self.data["sets"]])
        self.assertEqual(len(s["pads"]), 16)
        self.assertEqual(set(s["pads"][0]), {"symbol", "notes", "label"})
        self.assertIn("vl_row", s["metrics"])

    def test_ranges_per_type(self):
        self.assertEqual(set(self.data["ranges"]), {"functional", "shape", "pedal"})
        self.assertEqual(len(self.data["ranges"]["functional"]["span"]), 3)

    def test_bad_spec_exits_with_pad(self):
        with tempfile.TemporaryDirectory() as d:
            specs = os.path.join(d, "specs")
            os.makedirs(specs)
            rows = [["C", "F", "G", "Qm7"]] + [["C", "F", "G", "C"]] * 3
            json.dump({"name": "Bad", "type": "functional", "style": "close", "rows": rows},
                      open(os.path.join(specs, "bad.json"), "w"))
            r = subprocess.run([sys.executable, os.path.join(HERE, "..", "build.py"),
                                "--specs", specs, "--out", d, "--no-reference"],
                               capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("Bad: pad 4", r.stderr)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run to verify it fails**

Run: `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_build.py' -v`
Expected: ERROR `No module named 'build'`.

- [ ] **Step 4: Implement `tools/chordgen/build.py`**

```python
#!/usr/bin/env python3
"""Build chord sets: voice every spec in tools/chordgen/specs/ into
build/chordgen/sets/<slug>.chords, and write build/chordgen/data.json for the
harness (generated and reference sets, their metrics and reference ranges).

usage: build.py [--specs DIR] [--out DIR] [--no-reference]"""
import argparse
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import make_chords  # noqa: E402
from analyze import metrics, ranges  # noqa: E402
from theory import label  # noqa: E402
from voicer import load_spec, voice_set  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
REFERENCE = ["cinematic", "chill_house", "gospel_soul", "neo_soul_minor", "lofi_rb_1",
             "indie_jazz", "detroit_techno", "lush_pads", "pop_piano", "impressionist",
             "sad_ballads"]
REFERENCE_TYPE = {"detroit_techno": "shape", "impressionist": "pedal"}   # the rest: functional


def entry(name, slug, typ, source, ref, symbols, chords):
    return {"name": name, "slug": slug, "type": typ, "source": source, "reference": ref,
            "pads": [{"symbol": s, "notes": c, "label": label(c)} for s, c in zip(symbols, chords)],
            "metrics": metrics(chords)}


def build(out, specs_dir=os.path.join(HERE, "specs"), reference=True):
    os.makedirs(os.path.join(out, "sets"), exist_ok=True)
    sets = []
    for path in sorted(glob.glob(os.path.join(specs_dir, "*.json"))):
        spec = load_spec(path)
        slug = os.path.splitext(os.path.basename(path))[0]
        chords = voice_set(spec)
        with open(os.path.join(out, "sets", slug + ".chords"), "w", encoding="utf-8") as f:
            f.write(f"Name: {spec['name']}\n")
            for i, c in enumerate(chords):
                f.write(f"{i}: {','.join(map(str, c))}\n")
        sets.append(entry(spec["name"], slug, spec["type"], "generated", spec.get("reference"),
                          [s for r in spec["rows"] for s in r], chords))
    refs = []
    if reference:
        for slug in REFERENCE:
            title, ch = make_chords.fetch(slug)
            chords = [ch[i] for i in range(16)]
            # "ref_" keeps reference slugs apart from generated ones (impressionist / impressionist)
            refs.append(entry(title, "ref_" + slug, REFERENCE_TYPE.get(slug, "functional"),
                              "reference", None, [label(c) for c in chords], chords))
    rng = {}
    for typ in ("functional", "shape", "pedal"):
        same = [r["metrics"] for r in refs if r["type"] == typ]
        pool = same if len(same) >= 2 else [r["metrics"] for r in refs]
        if pool:
            rng[typ] = ranges(pool)
    with open(os.path.join(out, "data.json"), "w", encoding="utf-8") as f:
        json.dump({"sets": sets + refs, "ranges": rng}, f, indent=1)
    return sets


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--specs", default=os.path.join(HERE, "specs"))
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "chordgen"))
    ap.add_argument("--no-reference", action="store_true")
    a = ap.parse_args()
    try:
        sets = build(a.out, a.specs, not a.no_reference)
    except ValueError as e:
        sys.exit(f"build.py: {e}")
    for s in sets:
        m = s["metrics"]
        print(f"{s['name']:15} key {m['key']:3} diatonic {m['diatonic']:2}/16  "
              f"bass {m['bass_lo']}-{m['bass_hi']} top {m['top_lo']}-{m['top_hi']}  "
              f"top step {m['top_step']}  vl row {m['vl_row']} max {m['vl_max']}  mud {m['mud']}")
    print("wrote", os.path.join(a.out, "data.json"))


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Run the unit tests**

Run: `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -v`
Expected: all tests (Tasks 1–5) OK.

- [ ] **Step 6: Build and run the device-side checks**

```bash
python3 tools/chordgen/build.py
cp chords.lua build/chordgen/chords.lua
python3 tools/make_chords.py --dir build/chordgen/sets build/chordgen/chords.lua neo_soul detroit impressionist
$LUA test/chords_test.lua build/chordgen/chords.lua build/chordgen/sets neo_soul detroit impressionist | tail -1
$LUA test/fuzz.lua build/chordgen/chords.lua 12 600
```

Expected: build prints three lines with `mud 0`; make_chords prints `3 pages, 48 pads`; `ALL PASSED`; fuzz prints `ok, … update still running: true`.
If the fuzz or chords test fails on pages 4–11 (no data), stop and report it — `chords.lua` itself is out of scope for this plan.

- [ ] **Step 7: Note the spec format additions**

In `docs/superpowers/specs/2026-09-26-chord-sets-design.md`, under "Set spec", add after the JSON block:

```markdown
Optional fields: `reference` (slug of the current set to compare against in the harness) and
`shapes` (for `style: "shape"`: offsets above the bass per chord quality, e.g.
`{"m9": [0, 19, 22, 26, 27]}`; a quality without a shape uses its plain intervals).
```

- [ ] **Step 8: Commit**

```bash
git add tools/chordgen/specs tools/chordgen/build.py tools/chordgen/tests/test_build.py docs/superpowers/specs/2026-09-26-chord-sets-design.md
git commit -m "chordgen: Neo Soul, Detroit and Impressionist specs; build.py"
```

---

### Task 6: `serve.py`

**Goal:** A local server for the harness that serves `data.json` and saves feedback atomically.

**Files:**
- Create: `tools/chordgen/serve.py`
- Create: `tools/chordgen/tests/test_serve.py`

**Acceptance Criteria:**
- [ ] `GET /` serves `harness/index.html`; `GET /data.json` and `GET /feedback.json` serve files from the build directory (404 when missing)
- [ ] `POST /feedback` with a JSON object writes `feedback.json` (with a `saved` timestamp) via temp file + rename, answers 204
- [ ] non-JSON or non-object bodies get 400; other POST paths 404

**Verify:** `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_serve.py' -v` → OK

**Steps:**

- [ ] **Step 1: Write the failing tests** — `tools/chordgen/tests/test_serve.py`

```python
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import serve  # noqa: E402


class ServeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        open(os.path.join(self.tmp.name, "data.json"), "w").write('{"sets": []}')
        self.httpd = serve.make_server(0, self.tmp.name)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.httpd.server_address[1]}"

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.tmp.cleanup()

    def post(self, path, body):
        req = urllib.request.Request(self.base + path, data=body, method="POST",
                                     headers={"Content-Type": "application/json"})
        return urllib.request.urlopen(req)

    def test_serves_page_and_data(self):
        self.assertIn(b"<html", urllib.request.urlopen(self.base + "/").read().lower())
        self.assertEqual(json.load(urllib.request.urlopen(self.base + "/data.json")), {"sets": []})

    def test_feedback_roundtrip(self):
        r = self.post("/feedback", json.dumps({"sets": {"neo_soul": {"verdict": "keep"}}}).encode())
        self.assertEqual(r.status, 204)
        fb = json.load(open(os.path.join(self.tmp.name, "feedback.json")))
        self.assertEqual(fb["sets"]["neo_soul"]["verdict"], "keep")
        self.assertIn("saved", fb)
        self.assertEqual(json.load(urllib.request.urlopen(self.base + "/feedback.json"))["sets"],
                         fb["sets"])

    def test_rejects_non_json(self):
        with self.assertRaises(urllib.error.HTTPError) as e:
            self.post("/feedback", b"not json")
        self.assertEqual(e.exception.code, 400)

    def test_missing_feedback_is_404(self):
        with self.assertRaises(urllib.error.HTTPError) as e:
            urllib.request.urlopen(self.base + "/feedback.json")
        self.assertEqual(e.exception.code, 404)


if __name__ == "__main__":
    unittest.main()
```

(`GET /` needs `harness/index.html` to exist. Until Task 7, create it as a stub: `<!doctype html><html><body>chord sets</body></html>`.)

- [ ] **Step 2: Run to verify it fails**

Run: `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_serve.py' -v`
Expected: ERROR `No module named 'serve'`.

- [ ] **Step 3: Implement `tools/chordgen/serve.py`**

```python
#!/usr/bin/env python3
"""Serve the chord-set harness: the page, build/chordgen/data.json, and
POST /feedback, which saves build/chordgen/feedback.json.

usage: serve.py [PORT]   (default 8016), then open http://localhost:PORT/"""
import functools
import http.server
import json
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.abspath(os.path.join(HERE, "..", "..", "build", "chordgen"))
FILES = {"/data.json", "/feedback.json"}


class Handler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        p = path.split("?", 1)[0]
        if p in FILES:
            return os.path.join(self.server.build, p[1:])
        return super().translate_path(path)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        if self.path != "/feedback":
            return self.send_error(404)
        n = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(n))
        except ValueError:
            return self.send_error(400, "feedback must be JSON")
        if not isinstance(body, dict):
            return self.send_error(400, "feedback must be a JSON object")
        body["saved"] = time.strftime("%Y-%m-%dT%H:%M:%S")
        os.makedirs(self.server.build, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=self.server.build, suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(body, f, indent=1)
        os.replace(tmp, os.path.join(self.server.build, "feedback.json"))
        self.send_response(204)
        self.end_headers()

    def log_message(self, fmt, *args):
        pass


def make_server(port=8016, build=BUILD):
    handler = functools.partial(Handler, directory=os.path.join(HERE, "harness"))
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    httpd.build = build
    return httpd


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8016
    if not os.path.exists(os.path.join(BUILD, "data.json")):
        print("no build/chordgen/data.json yet: run python3 tools/chordgen/build.py first")
    httpd = make_server(port)
    print(f"chord sets harness: http://localhost:{port}/  (Ctrl-C to stop)")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run tests**

Run: `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen -p 'test_serve.py' -v`
Expected: 4 tests OK.

- [ ] **Step 5: Commit**

```bash
git add tools/chordgen/serve.py tools/chordgen/tests/test_serve.py tools/chordgen/harness/index.html
git commit -m "chordgen: harness server with feedback saving"
```

---

### Task 7: The web harness

**Goal:** A page to hear, measure and rate sets: 4×4 grid, row/grid/random-walk playback, E16-like controls, a browser synth, metrics against reference ranges, a reference toggle, and feedback saved through `serve.py`.

**Files:**
- Create (replace stub): `tools/chordgen/harness/index.html`

**Acceptance Criteria:**
- [ ] The set picker lists generated sets first, then reference sets marked "reference (local)"
- [ ] Clicking a pad plays it with the current strum, direction, gate, velocity, transpose and octave; the pad lights while it sounds
- [ ] Row 1–4, Grid and Random walk (tempo in BPM, one chord every 2 beats) play; Stop silences everything
- [ ] Tone switch: E-piano / Pad
- [ ] Metrics table shows value and the reference `min · median · max` for the set's type; out-of-range values are highlighted
- [ ] "Hear reference" switches to the spec's reference set and back
- [ ] Keep / Fix / Drop + note per set, and a note for the last-played pad, are saved to `feedback.json` within a second of a change and restored on reload
- [ ] The page's script passes `node --check`, and loading it in Chrome shows no console errors

**Verify:**
```bash
python3 - <<'EOF'
import re
html = open("tools/chordgen/harness/index.html").read()
open("/private/tmp/claude-501/-Volumes-ExtFS-charlesvestal-github-e16-euc/0827e003-02cc-4ee7-b831-0047b26ad30f/scratchpad/harness.js", "w").write(re.search(r"<script>(.*)</script>", html, re.S).group(1))
EOF
node --check /private/tmp/claude-501/-Volumes-ExtFS-charlesvestal-github-e16-euc/0827e003-02cc-4ee7-b831-0047b26ad30f/scratchpad/harness.js && echo syntax ok
```
Then `python3 tools/chordgen/serve.py` and open `http://localhost:8016/` in Chrome (claude-in-chrome): no console errors, the grid shows Neo Soul's labels, pressing a pad logs no errors, a verdict change creates `build/chordgen/feedback.json`.

**Steps:**

- [ ] **Step 1: Write `tools/chordgen/harness/index.html`**

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Chord Sets</title>
<style>
:root { --bg: #f6f5f2; --fg: #1d1d1f; --muted: #6b6b70; --line: #d9d7d2; --pad: #ffffff;
  --accent: #2f6fde; --hot: #ffcf4a; --warn: #c2410c; }
@media (prefers-color-scheme: dark) { :root { --bg: #141416; --fg: #ececef; --muted: #9a9aa2;
  --line: #2c2c31; --pad: #1f1f23; --accent: #6ea0ff; --hot: #d9a21b; --warn: #fb923c; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 14px/1.4 system-ui, sans-serif; }
main { max-width: 1100px; margin: 0 auto; padding: 16px; display: grid; gap: 16px;
  grid-template-columns: minmax(0, 1fr) 320px; }
@media (max-width: 800px) { main { grid-template-columns: 1fr; } }
header { grid-column: 1 / -1; display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
h1 { font-size: 18px; margin: 0 12px 0 0; }
select, button, input, textarea { font: inherit; color: inherit; background: var(--pad);
  border: 1px solid var(--line); border-radius: 6px; padding: 4px 8px; }
button { cursor: pointer; }
button.on { background: var(--accent); color: #fff; border-color: var(--accent); }
.grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; }
.pad { aspect-ratio: 1.4; display: flex; flex-direction: column; justify-content: center;
  align-items: center; border: 1px solid var(--line); border-radius: 10px; background: var(--pad);
  cursor: pointer; user-select: none; }
.pad .lab { font: 600 20px ui-monospace, monospace; }
.pad .sym { color: var(--muted); font-size: 12px; }
.pad.lit { background: var(--hot); color: #111; }
.pad.sel { outline: 2px solid var(--accent); }
.bar { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; margin: 8px 0; }
label.ctl { display: flex; gap: 4px; align-items: center; color: var(--muted); }
label.ctl input[type=number] { width: 64px; }
aside section { border: 1px solid var(--line); border-radius: 10px; padding: 10px; margin-bottom: 12px; }
aside h2 { font-size: 13px; margin: 0 0 6px; color: var(--muted); text-transform: uppercase; letter-spacing: .04em; }
table { width: 100%; border-collapse: collapse; font-variant-numeric: tabular-nums; }
td { padding: 2px 4px; border-bottom: 1px solid var(--line); }
td.v { text-align: right; font-weight: 600; }
td.r { text-align: right; color: var(--muted); }
tr.out td.v { color: var(--warn); }
textarea { width: 100%; min-height: 56px; }
#status { color: var(--muted); font-size: 12px; }
#msg { grid-column: 1 / -1; color: var(--warn); }
</style>
</head>
<body>
<main>
  <header>
    <h1>Chord Sets</h1>
    <select id="set" aria-label="Set"></select>
    <button id="ref">Hear reference</button>
    <button id="tone">E-piano</button>
    <span id="key"></span>
  </header>
  <div id="msg" hidden></div>
  <div>
    <div class="grid" id="grid"></div>
    <div class="bar">
      <button data-row="0">Row 1</button><button data-row="1">Row 2</button>
      <button data-row="2">Row 3</button><button data-row="3">Row 4</button>
      <button id="all">Grid</button><button id="walk">Random walk</button>
      <button id="stop">Stop</button>
    </div>
    <div class="bar">
      <label class="ctl">BPM <input id="bpm" type="number" min="40" max="200" value="84"></label>
      <label class="ctl">Transpose <input id="tr" type="number" min="-12" max="12" value="0"></label>
      <label class="ctl">Octave <input id="oct" type="number" min="-2" max="2" value="0"></label>
      <label class="ctl">Velocity <input id="vel" type="number" min="1" max="127" value="100"></label>
      <label class="ctl">Gate s (0 = hold) <input id="gate" type="number" min="0" max="4" step="0.1" value="0"></label>
      <label class="ctl">Strum ms <input id="strum" type="number" min="0" max="200" value="20"></label>
      <label class="ctl">Down <input id="down" type="checkbox"></label>
    </div>
  </div>
  <aside>
    <section>
      <h2>Verdict</h2>
      <div class="bar" id="verdict">
        <button data-v="keep">Keep</button><button data-v="fix">Fix</button><button data-v="drop">Drop</button>
      </div>
      <textarea id="note" placeholder="Notes on the whole set"></textarea>
      <h2 id="padh">Pad note</h2>
      <textarea id="padnote" placeholder="Play a pad, then note it here"></textarea>
      <div id="status"></div>
    </section>
    <section>
      <h2>Metrics <span id="rtype"></span></h2>
      <table id="metrics"></table>
    </section>
  </aside>
</main>
<script>
"use strict";
const $ = (id) => document.getElementById(id);
const LABELS = {diatonic: "diatonic /16", shapes: "distinct shapes", voices_min: "voices min",
  voices_max: "voices max", bass_lo: "bass low", bass_hi: "bass high", top_lo: "top low",
  top_hi: "top high", span: "span avg", top_step: "top-line step", vl_row: "voice move (rows)",
  vl_all: "voice move (all)", vl_max: "voice move max", mud: "mud", unnamed: "unnamed"};
let data = null, cur = null, back = null, sel = -1;
let feedback = {sets: {}};
let tone = "ep", timers = [], sounding = [];

// ---------- audio ----------
let ctx = null, master = null;
function audio() {
  if (!ctx) {
    ctx = new AudioContext();
    const comp = ctx.createDynamicsCompressor();
    master = ctx.createGain();
    master.gain.value = 0.5;
    master.connect(comp).connect(ctx.destination);
  }
  if (ctx.state === "suspended") ctx.resume();
  return ctx;
}
const hz = (n) => 440 * Math.pow(2, (n - 69) / 12);

function voiceEP(n, t, amp) {
  const car = ctx.createOscillator(), mod = ctx.createOscillator();
  const mg = ctx.createGain(), g = ctx.createGain();
  car.frequency.value = hz(n); mod.frequency.value = hz(n) * 1.0;
  mg.gain.setValueAtTime(hz(n) * 2.2, t);
  mg.gain.exponentialRampToValueAtTime(hz(n) * 0.15, t + 1.2);
  mod.connect(mg).connect(car.frequency);
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(amp, t + 0.005);
  g.gain.exponentialRampToValueAtTime(amp * 0.25, t + 2.5);
  car.connect(g).connect(master);
  car.start(t); mod.start(t);
  return {g, oscs: [car, mod], rel: 0.35};
}
function voicePad(n, t, amp) {
  const f = ctx.createBiquadFilter(), g = ctx.createGain();
  f.type = "lowpass"; f.frequency.value = 1800; f.Q.value = 0.3;
  const oscs = [-7, 7].map((c) => {
    const o = ctx.createOscillator();
    o.type = "sawtooth"; o.frequency.value = hz(n); o.detune.value = c;
    o.connect(f); o.start(t);
    return o;
  });
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(amp * 0.6, t + 0.4);
  f.connect(g).connect(master);
  return {g, oscs, rel: 1.2};
}
function release(v, t) {
  v.g.gain.cancelScheduledValues(t);
  v.g.gain.setValueAtTime(Math.max(v.g.gain.value, 0.0001), t);
  v.g.gain.exponentialRampToValueAtTime(0.0001, t + v.rel);
  v.oscs.forEach((o) => o.stop(t + v.rel + 0.05));
}
function releaseAll() {
  if (!ctx) return;
  const t = ctx.currentTime;
  sounding.forEach((s) => s.voices.forEach((v) => release(v, t)));
  sounding = [];
  document.querySelectorAll(".pad.lit").forEach((p) => p.classList.remove("lit"));
}

function playPad(i) {
  if (!cur) return;
  audio();
  releaseAll();
  const shift = +$("tr").value + 12 * +$("oct").value;
  const notes = cur.pads[i].notes.map((n) => n + shift);
  if ($("down").checked) notes.reverse();
  const amp = 0.12 * (+$("vel").value / 127) / Math.sqrt(notes.length / 4);
  const t0 = ctx.currentTime + 0.01, strum = +$("strum").value / 1000;
  const make = tone === "ep" ? voiceEP : voicePad;
  const s = {voices: notes.map((n, k) => make(n, t0 + k * strum, amp))};
  sounding.push(s);
  const pad = $("grid").children[i];
  pad.classList.add("lit");
  select(i);
  const gate = +$("gate").value;
  if (gate > 0) {
    setTimeout(() => {
      if (sounding.includes(s)) {
        s.voices.forEach((v) => release(v, ctx.currentTime));
        sounding = sounding.filter((x) => x !== s);
        pad.classList.remove("lit");
      }
    }, gate * 1000);
  }
}

// ---------- sequencing ----------
function stop() { timers.forEach(clearTimeout); timers = []; $("walk").classList.remove("on"); releaseAll(); }
function step() { return 2 * 60000 / Math.max(40, +$("bpm").value || 84); }
function sequence(order) {
  stop();
  order.forEach((i, k) => timers.push(setTimeout(() => playPad(i), k * step())));
  timers.push(setTimeout(releaseAll, order.length * step()));
}
function walk() {
  if ($("walk").classList.contains("on")) return stop();
  stop();
  $("walk").classList.add("on");
  let i = Math.floor(Math.random() * 16);
  const tick = () => {
    playPad(i);
    let j = i;
    while (j === i) j = Math.floor(Math.random() * 16);
    i = j;
    timers.push(setTimeout(tick, step()));
  };
  tick();
}

// ---------- view ----------
function select(i) {
  sel = i;
  [...$("grid").children].forEach((p, k) => p.classList.toggle("sel", k === i));
  $("padh").textContent = i < 0 ? "Pad note" : `Pad ${i + 1} note (${cur.pads[i].symbol})`;
  $("padnote").value = i < 0 ? "" : (fb(cur).pads[i] || "");
}
function fb(set) {
  return feedback.sets[set.slug] || (feedback.sets[set.slug] = {verdict: "", note: "", pads: {}});
}
function show(set) {
  stop();
  cur = set;
  $("grid").innerHTML = "";
  set.pads.forEach((p, i) => {
    const d = document.createElement("div");
    d.className = "pad";
    d.innerHTML = `<div class="lab"></div><div class="sym"></div>`;
    d.querySelector(".lab").textContent = p.label;
    d.querySelector(".sym").textContent = set.source === "generated" ? p.symbol : p.notes.join(" ");
    d.title = p.notes.join(" ");
    d.onclick = () => playPad(i);
    $("grid").appendChild(d);
  });
  const m = set.metrics;
  $("key").textContent = `key ${m.key} (fit ${m.fit}) · ${set.type} · ${set.source}`;
  const r = data.ranges[set.type] || {};
  $("rtype").textContent = `vs ${set.type} reference min · median · max`;
  $("metrics").innerHTML = "";
  Object.keys(LABELS).forEach((k) => {
    const tr = document.createElement("tr"), rg = r[k];
    if (rg && (m[k] < rg[0] || m[k] > rg[2])) tr.className = "out";
    tr.innerHTML = `<td></td><td class="v"></td><td class="r"></td>`;
    tr.children[0].textContent = LABELS[k];
    tr.children[1].textContent = m[k];
    tr.children[2].textContent = rg ? rg.join(" · ") : "";
    $("metrics").appendChild(tr);
  });
  const f = fb(set);
  document.querySelectorAll("#verdict button").forEach((b) => b.classList.toggle("on", b.dataset.v === f.verdict));
  $("note").value = f.note;
  $("ref").disabled = !(set.reference || back);
  $("ref").textContent = back ? "Back to " + back.name : "Hear reference";
  $("set").value = (back || set).slug;
  select(-1);
}

// ---------- feedback ----------
let saveTimer = null;
function save() {
  clearTimeout(saveTimer);
  $("status").textContent = "saving…";
  saveTimer = setTimeout(async () => {
    try {
      const r = await fetch("/feedback", {method: "POST", headers: {"Content-Type": "application/json"},
        body: JSON.stringify(feedback)});
      $("status").textContent = r.ok ? "saved " + new Date().toLocaleTimeString() : "save failed: " + r.status;
    } catch (e) { $("status").textContent = "save failed: " + e.message; }
  }, 500);
}

// ---------- wiring ----------
document.querySelectorAll("[data-row]").forEach((b) => b.onclick = () => {
  const r = +b.dataset.row; sequence([0, 1, 2, 3].map((k) => r * 4 + k));
});
$("all").onclick = () => sequence([...Array(16).keys()]);
$("walk").onclick = walk;
$("stop").onclick = stop;
$("tone").onclick = () => { tone = tone === "ep" ? "pad" : "ep"; $("tone").textContent = tone === "ep" ? "E-piano" : "Pad"; };
$("set").onchange = () => { back = null; show(data.sets.find((s) => s.slug === $("set").value)); };
$("ref").onclick = () => {
  if (back) { const b = back; back = null; show(b); return; }
  const r = data.sets.find((s) => s.slug === "ref_" + cur.reference);
  if (r) { const from = cur; show(r); back = from; $("ref").textContent = "Back to " + from.name; $("ref").disabled = false; }
};
document.querySelectorAll("#verdict button").forEach((b) => b.onclick = () => {
  const f = fb(cur); f.verdict = f.verdict === b.dataset.v ? "" : b.dataset.v;
  document.querySelectorAll("#verdict button").forEach((x) => x.classList.toggle("on", x.dataset.v === f.verdict));
  save();
});
$("note").oninput = () => { fb(cur).note = $("note").value; save(); };
$("padnote").oninput = () => {
  if (sel < 0) return;
  const f = fb(cur);
  if ($("padnote").value) f.pads[sel] = $("padnote").value; else delete f.pads[sel];
  save();
};
document.addEventListener("keydown", (e) => {
  if (e.target.matches("input, textarea")) return;
  const k = "1234qwerasdfzxcv".indexOf(e.key.toLowerCase());
  if (k >= 0) playPad(k);
  if (e.key === " ") { e.preventDefault(); stop(); }
});

(async function init() {
  try {
    const r = await fetch("/data.json");
    if (!r.ok) throw new Error("no data.json: run python3 tools/chordgen/build.py");
    data = await r.json();
  } catch (e) {
    $("msg").hidden = false; $("msg").textContent = e.message; return;
  }
  try {
    const r = await fetch("/feedback.json");
    if (r.ok) feedback = await r.json();
    feedback.sets = feedback.sets || {};
  } catch (e) { /* first run */ }
  data.sets.forEach((s) => {
    const o = document.createElement("option");
    o.value = s.slug;
    o.textContent = s.source === "reference" ? s.name + " — reference (local)" : s.name;
    $("set").appendChild(o);
  });
  show(data.sets[0]);
})();
</script>
</body>
</html>
```

- [ ] **Step 2: Syntax check**

Run the Verify block's first command.
Expected: `syntax ok`.

- [ ] **Step 3: Serve and smoke-test in Chrome**

```bash
python3 tools/chordgen/build.py
python3 tools/chordgen/serve.py
```
(run the server in the background). Open `http://localhost:8016/` with claude-in-chrome. Check: the header shows "Neo Soul", 16 pads with labels, the metrics table filled, `read_console_messages` shows no errors. Click a pad, then Keep; confirm `build/chordgen/feedback.json` contains `"verdict": "keep"` for `neo_soul`. Click "Hear reference": the grid switches to Neo Soul Minor. Stop the server.

- [ ] **Step 4: Commit**

```bash
git add tools/chordgen/harness/index.html
git commit -m "chordgen: web harness (grid, playback, synth, metrics, feedback)"
```

---

### Task 8: Docs

**Goal:** The README explains how to write, hear and pack chord sets.

**Files:**
- Modify: `README.md` (Chords section, Tests section)

**Acceptance Criteria:**
- [ ] A "Writing chord sets" subsection under Chords: specs, build, harness, feedback file, packing with `--dir`
- [ ] The Tests section lists `python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen`

**Verify:** `grep -n "tools/chordgen" README.md` → the new lines

**Steps:**

- [ ] **Step 1: Add after the Chords section's `make_chords.py` paragraph**

```markdown
### Writing chord sets

New sets are written as specs in `tools/chordgen/specs/` (a key, a set type, 16 chord
symbols in 4 rows, a voicing style) and voiced by `tools/chordgen/voicer.py`, which keeps
the set in one register, avoids muddy low intervals and moves smoothly from pad to pad.

    python3 tools/chordgen/build.py      # voice the specs, measure them
    python3 tools/chordgen/serve.py      # then open http://localhost:8016/

The harness plays the sets in the browser (pads, rows, the whole grid, a random walk), shows
each set's measurements next to the range of the current sets, and saves Keep / Fix / Drop
verdicts and notes to `build/chordgen/feedback.json`. To put generated sets on the E16:

    python3 tools/make_chords.py --dir build/chordgen/sets chords.lua neo_soul detroit impressionist
```

- [ ] **Step 2: Add to the Tests section's command list**

```
    python3 -m unittest discover -s tools/chordgen/tests -t tools/chordgen   # chord-set tools
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "README: writing chord sets"
```
