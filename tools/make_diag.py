#!/usr/bin/env python3
"""Make a diagnostic copy of a scene: its uploaded code gets a marker in front
(header "diag: ran" as soon as the script's top level runs) and
tools/diag_wrap.lua after it (errors in callbacks are shown on the labels).

If the header never shows "diag: ran", the script failed before running
(compile error or out of memory while loading).

usage: make_diag.py SCENE.oxie16 OUT.oxie16 [TITLE]
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import make_scene  # noqa: E402

src, out = sys.argv[1], sys.argv[2]
scene = json.load(open(src, encoding="utf-8"))
wrap = open(os.path.join(os.path.dirname(__file__), "diag_wrap.lua"), encoding="utf-8").read()
code = 'page.setTitle("diag: ran");' + scene["code"]["code"].rstrip() + "\n" + make_scene.minify(wrap)
scene["code"]["code"] = code
scene["title"] = sys.argv[3] if len(sys.argv) > 3 else scene["title"] + " diag"
json.dump(scene, open(out, "w", encoding="utf-8"), separators=(",", ":"))
print(f"wrote {out}: {len(code.encode())} bytes uploaded")
