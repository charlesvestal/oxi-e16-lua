#!/usr/bin/env python3
"""Build an OXI App scene (.oxie16) that runs a script with every control wired.

An existing scene exported by the OXI App is used as a template. Only the title,
the embedded script, and the wiring of pages 1-2 change; pages 3-12 are kept.

Wiring follows the script-ID convention used by the scripts in this repo:
  page 1: encoder e -> turn id e,      push id 16 + e
  page 2: encoder e -> turn id 32 + e, push id 48 + e
--pad-pages N repeats the page-1 wiring on pages 1..N (scripts tell them apart
with enc.page), and --settings-page moves the page-2 block elsewhere.
A control is wired only if the script declares that id with --@assign;
otherwise it is switched off. Labels come from the assign's abbr.

usage: make_scene.py TEMPLATE.oxie16 SCRIPT.lua OUT.oxie16 [LIBRARY.e16script]
                     [--title TITLE] [--pages P1,P2,...] [--pad-pages N] [--settings-page P]
"""
import argparse
import json
import os
import re
import sys


def minify(src):
    """Remove comments and every space that isn't needed. The scene's "code"
    field is exactly what the device receives; smaller code also means less
    memory while loading, which is the E16's real limit. Strings and long brackets are copied verbatim."""
    word = lambda c: c.isalnum() or c == "_"
    out, i, n = [], 0, len(src)
    pending = False                                 # whitespace seen since last token

    def emit(tok):
        nonlocal pending
        if pending and out:
            a, b = out[-1][-1], tok[0]
            if (word(a) and word(b)) or (a == "-" and b == "-") \
                    or (a in "0123456789." and b == ".") or (a == "." and b in "0123456789.") \
                    or (a == "[" and b in "[="):
                out.append(" ")
        out.append(tok)
        pending = False

    while i < n:
        c = src[i]
        m = re.match(r"\[(=*)\[", src[i:i + 20])
        if src.startswith("--", i):
            m2 = re.match(r"--\[(=*)\[", src[i:i + 20])
            if m2:                                  # long comment
                end = src.find("]" + m2.group(1) + "]", i)
                i = n if end < 0 else end + len(m2.group(1)) + 2
            else:
                j = src.find("\n", i)
                i = n if j < 0 else j
            pending = True
        elif m:                                     # long string: copy verbatim
            end = src.find("]" + m.group(1) + "]", i)
            end = n if end < 0 else end + len(m.group(1)) + 2
            emit(src[i:end])
            i = end
        elif c in "\"'":                            # short string
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            emit(src[i:j + 1])
            i = j + 1
        elif c.isspace():
            pending = True
            i += 1
        else:
            j = i + 1
            if word(c):
                while j < n and word(src[j]):
                    j += 1
            emit(src[i:j])
            i = j
    return "".join(out) + "\n"


KEYWORDS = set("""and break do else elseif end false for function goto if in local nil not
or repeat return then true until while""".split())


def _elseif(toks, idx):
    """True if this `then` closes an `elseif` condition (no new block)."""
    for k, t in reversed(toks[:idx]):
        if k == "w" and t in ("if", "elseif"):
            return t == "elseif"
    return False


def rename_locals(code):
    """Shorten file-level local names in minified code. Only names declared with
    `local` at the start of a statement are renamed, never after "." or ":",
    and never names that also appear as table keys ({name = ...})."""
    # tokenize: strings/long strings stay opaque
    toks, i, n = [], 0, len(code)
    while i < n:
        c = code[i]
        m = re.match(r"\[(=*)\[", code[i:i + 20])
        if m:
            end = code.find("]" + m.group(1) + "]", i) + len(m.group(1)) + 2
            toks.append(("s", code[i:end])); i = end
        elif c in "\"'":
            j = i + 1
            while code[j] != c:
                j += 2 if code[j] == "\\" else 1
            toks.append(("s", code[i:j + 1])); i = j + 1
        elif c.isalpha() or c == "_":
            j = i
            while j < n and (code[j].isalnum() or code[j] == "_"):
                j += 1
            toks.append(("w", code[i:j])); i = j
        else:
            toks.append(("o", c)); i += 1
    words = {t for k, t in toks if k == "w"}
    full = toks
    toks = [x for x in toks if not x[1].isspace()]   # analyse without whitespace
    # names declared by `local` / `local function` at depth 0 of the chunk
    declared, depth = [], 0
    for idx, (k, t) in enumerate(toks):
        if k == "w" and t in ("function", "do", "repeat") or (k == "w" and t == "then"
                                                               and not _elseif(toks, idx)):
            depth += 1
        elif k == "w" and t in ("end", "until"):
            depth -= 1
        if k == "w" and t == "local" and depth == 0:
            j = idx + 1
            if toks[j][1] == "function":
                j += 1
            while j < len(toks) and toks[j][0] == "w" and toks[j][1] not in KEYWORDS:
                declared.append(toks[j][1])
                if toks[j + 1][1] != ",":
                    break
                j += 2
    keys = set()
    for idx in range(1, len(toks) - 2):
        if toks[idx][0] == "w" and toks[idx - 1][1] in "{," and toks[idx + 1][1] == "=" \
                and toks[idx + 2][1] != "=":
            keys.add(toks[idx][1])
    pool = (a + b for a in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" for b in [""] + list("0123456789"))
    mapping = {}
    for name in sorted(set(declared), key=lambda x: -sum(1 for k, t in toks if t == x)):
        if len(name) < 3 or name in keys:
            continue
        new = next(pool)
        while new in words or new in KEYWORDS:
            new = next(pool)
        mapping[name] = new
    out, prev, prev2 = [], "", ""
    for k, t in full:
        field = prev == ":" or (prev == "." and prev2 != ".")   # a.b / a:b, not a..b
        out.append(mapping.get(t, t) if k == "w" and not field else t)
        if not t.isspace():
            prev, prev2 = t, prev
    return "".join(out)


def assigns(src):
    """Parse --@assign directives into {id: {key: value}}."""
    res = {}
    for m in re.finditer(r"^--@assign\s+(.*)$", src, re.M):
        kv = dict(re.findall(r'(\w+)=("[^"]*"|\S+)', m.group(1)))
        kv = {k: v.strip('"') for k, v in kv.items()}
        res[int(kv["id"])] = kv
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("template")
    ap.add_argument("script")
    ap.add_argument("out")
    ap.add_argument("library", nargs="?")
    ap.add_argument("--title")
    ap.add_argument("--pages", help="comma-separated page titles (default: from a '-- pages:' line)")
    ap.add_argument("--pad-pages", type=int, default=1,
                    help="pages 1..N all get the page-1 wiring (ids 1-32); tell them apart by page")
    ap.add_argument("--settings-page", type=int, default=2, help="page that gets ids 33-64")
    args = ap.parse_args()

    src = open(args.script, encoding="utf-8").read()
    code = rename_locals(minify(src))
    if len(code.encode()) > 7900:     # the app caps scripts at 8000; 7000-byte probes load (fw 1.2)
        sys.exit(f"script is {len(code)} bytes; the OXI App caps scripts at 8000")
    name = os.path.splitext(os.path.basename(args.script))[0]

    scene = json.load(open(args.template, encoding="utf-8"))
    a = assigns(src)
    scene["title"] = args.title or name.capitalize()
    scene["code"] = {"code": code, "fullScript": src.replace("\n", "\r\n"), "scriptName": name}

    wiring = [(pg, 0) for pg in range(args.pad_pages)] + [(args.settings_page - 1, 1)]
    for pg, block in wiring:
        for e in range(1, 17):
            enc = scene["pages"][pg]["encoders"][e - 1]
            tid, pid = 32 * block + e, 32 * block + 16 + e
            t, p = enc["turn_actions"][0], enc["push_action"]
            turn, push = a.get(tid), a.get(pid)
            if turn:
                enc["name"] = enc["abbr"] = turn["abbr"]
                t["type"], t["scriptId"] = 11, tid          # 11 = Script turn
                t["lower"], t["upper"] = int(turn.get("l", 0)), int(turn.get("h", 127))
            else:
                enc["name"] = enc["abbr"] = push["abbr"] if push else ""
                t["type"], t["scriptId"] = 0, 0             # 0 = off
            if push:
                p["type"], p["scriptId"] = 12, pid          # 12 = Script push
            else:
                p["type"], p["scriptId"] = 0, 0
    m = re.search(r"^-- pages:\s*(.+)$", src, re.M)
    pages = args.pages or (m.group(1) if m else "")
    for pg, title in enumerate(t for t in pages.split(",") if t):
        scene["pages"][pg]["title"] = title

    json.dump(scene, open(args.out, "w", encoding="utf-8"), separators=(",", ":"))
    print(f"wrote {args.out}: '{scene['title']}', script {len(code)} bytes uploaded")
    if args.library:
        open(args.library, "w", encoding="utf-8", newline="").write(src.replace("\n", "\r\n"))
        print(f"wrote {args.library}")


if __name__ == "__main__":
    main()
