#!/usr/bin/env python3
"""Build the community-release scenes and scripts into release/.

  python3 tools/make_release.py

Each scene is wired by make_scene.py from release/template.oxie16 (a blank scene)
and gets its icon from release/icons.txt. The .e16script files are the full
sources for the OXI App's script library.
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REL = os.path.join(ROOT, "release")

# script, scene file, title, make_scene options
SCENES = [
    ("euclid", "Euclid", "Euclid", ["--pages", "Pat,Set"]),
    ("lfo", "LFOx16", "LFOx16", ["--pad-pages", "4", "--settings-page", "5"]),
    ("chords", "Chords", "Chords", ["--pad-pages", "11", "--settings-page", "12"]),
    ("modseq", "ModSeq", "Mod Seq", []),
    ("tb3po", "TB-3PO", "TB-3PO", []),
]


def icons():
    res, name, rows = {}, None, []
    for line in open(os.path.join(REL, "icons.txt")):
        line = line.rstrip("\n")
        if not line or line.startswith("# "):   # comments; icon rows can start with "#"
            continue
        if set(line) <= {".", "#"} and len(line) == 16:
            rows.append(line)
            if len(rows) == 16:
                bits = [int(r.replace("#", "1").replace(".", "0"), 2) for r in rows]
                res[name] = [b for v in bits for b in (v >> 8, v & 0xFF)]
                rows = []
        else:
            name = line.strip()
    return res


def main():
    ic = icons()
    for script, scene, title, opts in SCENES:
        out = os.path.join(REL, scene + ".oxie16")
        lib = os.path.join(REL, script + ".e16script")
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "make_scene.py"),
                        os.path.join(REL, "template.oxie16"), os.path.join(ROOT, script + ".lua"),
                        out, lib, "--title", title] + opts, check=True)
        s = json.load(open(out, encoding="utf-8"))
        s["icon"] = ic[script]
        json.dump(s, open(out, "w", encoding="utf-8"), separators=(",", ":"))


if __name__ == "__main__":
    main()
