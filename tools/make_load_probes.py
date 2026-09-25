#!/usr/bin/env python3
"""Build "load probe" scripts: dummy code (N small functions plus a table of
10*N numbers), so compiling them takes a known amount of memory. Each shows "Load N OK" in the header and
Lua's heap (KB) on encoder 1 if the device loads it. Measure each with
test/e16host.c to map N to a modeled load peak.

usage: make_load_probes.py OUTDIR N [N ...]        (writes load<N>.lua)
"""
import os
import sys

FN = "F[{k}]=function(x)return x*{k}+x//3-x%7 end\n"

HEAD = """-- load probe: {n} dummy functions
local F = {{}}
"""

TAIL = """function page.onInit()
  collectgarbage()
  page.setTitle("Load {n} OK")
  slots.update(1, "" .. math.floor(collectgarbage("count")))
  slots.update(2, "" .. F[{n}](1, 2) % 1000)
end
"""


def main():
    out = sys.argv[1]
    for n in map(int, sys.argv[2:]):
        nums = ",".join(str(i % 97) for i in range(10 * n))
        src = (HEAD.format(n=n) + "".join(FN.format(k=k) for k in range(1, n + 1))
               + "local T={" + nums + "}\n" + TAIL.format(n=n).replace("F[{n}](1, 2)".format(n=n), "F[{n}](T[{n}])".format(n=n)))
        open(os.path.join(out, f"load{n}.lua"), "w").write(src)


if __name__ == "__main__":
    main()
