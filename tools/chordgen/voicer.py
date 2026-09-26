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
    with open(path, encoding="utf-8") as f:
        return validate(json.load(f))


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
