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


def entry(name, slug, typ, source, ref, symbols, chords, spec_key=None):
    return {"name": name, "slug": slug, "type": typ, "source": source, "reference": ref,
            "pads": [{"symbol": s, "notes": c, "label": label(c)} for s, c in zip(symbols, chords)],
            "metrics": metrics(chords, spec_key)}


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
                          [s for r in spec["rows"] for s in r], chords, spec.get("key")))
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
