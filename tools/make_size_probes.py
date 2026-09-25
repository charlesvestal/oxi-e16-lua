#!/usr/bin/env python3
"""Build "size probe" scenes: a tiny script padded so its uploaded code is exactly
N bytes. Each shows "Size N OK" in the header if the device loads it; a
rejected script leaves the scene's default header.

usage: make_size_probes.py TEMPLATE.oxie16 OUTDIR N [N ...]
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import make_scene  # noqa: E402

BODY = '''-- size probe: uploaded code is exactly {n} bytes
local PAD = [=[{pad}]=]
function page.onInit()
  page.setTitle("Size {n} OK")
  slots.update(1, "" .. #PAD // 1000)
end
'''


def build(n):
    pad = ""
    for _ in range(3):                      # converge on the exact size
        src = BODY.format(n=n, pad=pad)
        code = make_scene.rename_locals(make_scene.minify(src))
        pad += "x" * (n - len(code.encode()))
    assert len(code.encode()) == n, (n, len(code))
    return src, code


def main():
    template, outdir, sizes = sys.argv[1], sys.argv[2], [int(x) for x in sys.argv[3:]]
    for n in sizes:
        src, code = build(n)
        scene = json.load(open(template, encoding="utf-8"))
        scene["title"] = f"Size {n}"
        scene["code"] = {"code": code, "fullScript": src.replace("\n", "\r\n"), "scriptName": f"size{n}"}
        path = os.path.join(outdir, f"Size {n}.oxie16")
        json.dump(scene, open(path, "w", encoding="utf-8"), separators=(",", ":"))
        print(f"wrote {path}: {len(code.encode())} bytes")


if __name__ == "__main__":
    main()
