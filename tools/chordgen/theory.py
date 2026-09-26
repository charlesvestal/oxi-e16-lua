"""Music theory for the chord-set tools: chord symbols, device labels, keys,
scales, voice leading and the low-interval ("mud") rule."""
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
    "9sus4": (0, 5, 7, 10, 14),
    "11": (0, 7, 10, 14, 17), "m11": (0, 3, 7, 10, 14, 17),
    "maj7#11": (0, 4, 7, 11, 18),
    "13": (0, 4, 7, 10, 14, 21), "m13": (0, 3, 7, 10, 14, 21), "maj13": (0, 4, 7, 11, 14, 21),
    "7b9": (0, 4, 7, 10, 13), "7#9": (0, 4, 7, 10, 15),
    "m7b9": (0, 3, 7, 10, 13),
}
ALIAS = {"M7": "maj7", "M9": "maj9", "M13": "maj13", "M7#11": "maj7#11",
         "min": "m", "-": "m", "sus": "sus4", "7sus": "7sus4", "9sus": "9sus4",
         "o": "dim", "o7": "dim7", "h7": "m7b5", "+": "aug", "mM7": "mmaj7"}

# Krumhansl-Kessler key profiles (C major, C minor)
MAJOR = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
MINOR = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]


def pc(name):
    """Pitch class of a note name: C, F#, Bb."""
    if not name or name[0] not in LETTER:
        raise ValueError(f"bad note name {name!r}")
    accs = name[1:]
    if "#" in accs and "b" in accs:
        raise ValueError(f"bad note name {name!r}")
    p = LETTER[name[0]]
    for a in accs:
        if a == "#":
            p += 1
        elif a == "b":
            p -= 1
        else:
            raise ValueError(f"bad note name {name!r}")
    return p % 12


def parse(symbol):
    """'Ebm9' -> (root pc, intervals, slash bass pc or None, quality name)."""
    body, sep, bass = symbol.partition("/")
    if sep and not bass:
        raise ValueError(f"bad chord symbol {symbol!r}")
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
    """The pad label chords.lua shows for these notes (untransposed).
    chords.lua drops notes outside 22..115 before naming."""
    notes = [n for n in notes if 22 <= n <= 115]
    if not notes:
        return ""
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
    if len(a) == len(b):
        return sum(abs(x - y) for x, y in zip(a, b))
    if len(a) > len(b):
        a, b = b, a
    n, m = len(a), len(b)
    nearest = [min(abs(b[j] - x) for x in a) for j in range(m)]
    inf = float("inf")
    dp = [[inf] * (m + 1) for _ in range(n + 1)]
    dp[0][0] = 0
    for j in range(1, m + 1):
        dp[0][j] = dp[0][j - 1] + nearest[j - 1]
    for i in range(1, n + 1):
        for j in range(i, m + 1):
            best = dp[i - 1][j - 1] + abs(a[i - 1] - b[j - 1])
            if j > i:
                best = min(best, dp[i][j - 1] + nearest[j - 1])
            dp[i][j] = best
    return dp[n][m]


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
