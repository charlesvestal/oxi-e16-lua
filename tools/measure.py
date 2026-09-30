#!/usr/bin/env python3
"""Memory of scripts on the E16, from the 32-bit heap model (test/e16host.c).

  python3 tools/measure.py WASI_SDK_DIR LUA_SRC_DIR script.lua ...

Builds test/e16host.c for wasm32 once (build/e16host32.wasm), minifies each
script like make_scene.py, and runs it under node's WASI. Prints the compile
peak (the device fails with "compile: not enough memory" above ~28.7-29.3 KB)
and the load and playing peaks. LUA_SRC_DIR is a Lua 5.4 src/ with
LUA_32BITS 1 in luaconf.h; WASI_SDK_DIR is an unpacked wasi-sdk release.
"""
import glob
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
from make_scene import minify, rename_locals  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WASM = os.path.join(ROOT, "build", "e16host32.wasm")
SKIP = ("lua.c", "luac.c", "liolib.c", "loslib.c", "loadlib.c", "linit.c")


def build(sdk, lua):
    srcs = [f for f in glob.glob(os.path.join(lua, "*.c")) if os.path.basename(f) not in SKIP]
    os.makedirs(os.path.dirname(WASM), exist_ok=True)
    subprocess.run([os.path.join(sdk, "bin", "clang"), "--target=wasm32-wasip1",
                    "--sysroot=" + os.path.join(sdk, "share", "wasi-sysroot"), "-Os",
                    "-mllvm", "-wasm-enable-sjlj", "-lsetjmp",
                    "-D_WASI_EMULATED_PROCESS_CLOCKS", "-lwasi-emulated-process-clocks",
                    "-D_WASI_EMULATED_SIGNAL", "-lwasi-emulated-signal",
                    "-I" + lua, "-o", WASM, os.path.join(ROOT, "test", "e16host.c")] + srcs, check=True)


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    sdk, lua, scripts = sys.argv[1], sys.argv[2], sys.argv[3:]
    if not os.path.exists(WASM):
        build(sdk, lua)
    tmp = os.path.join(ROOT, "build", "measure.lua")
    print("%-14s %7s %8s %8s %8s" % ("script", "bytes", "compile", "load", "playing"))
    for path in scripts:
        code = rename_locals(minify(open(path, encoding="utf-8").read()))
        open(tmp, "w", encoding="utf-8").write(code)
        out = subprocess.run(["node", "--no-warnings", os.path.join(ROOT, "test", "run32.mjs"), WASM, tmp, "5"],
                             capture_output=True, text=True).stdout
        get = lambda k: (re.search(k + r"\s+(\d+)", out) or [None, "?"])[1]
        print("%-14s %7d %8s %8s %8s" % (os.path.basename(path), len(code), get(r"compile peak"),
                                           get(r"peak \(load\)"), get(r"peak \(playing\)")))


if __name__ == "__main__":
    main()
