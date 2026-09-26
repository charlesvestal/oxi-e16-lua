"""Set metrics: how a 16-pad chord set sits (key, register, top line, voice
leading, mud), and reference ranges across sets."""
import statistics as st

from theory import NAMES, key, label, mud, pc, scale, vl

# numeric metrics, in the order the harness shows them
METRICS = ["diatonic", "shapes", "voices_min", "voices_max", "bass_lo", "bass_hi",
           "top_lo", "top_hi", "span", "top_step", "vl_row", "vl_all", "vl_max",
           "mud", "unnamed"]


def metrics(chords, spec_key=None):
    """chords: 16 note lists in pad order (row by row). With the spec's key
    ("Ebm"), diatonic counts against it instead of the estimated key."""
    fit, k, q = key(chords)
    if spec_key:
        sk, sq = spec_key.rstrip("m"), "m" if spec_key.endswith("m") else ""
        sc = scale(pc(sk), sq)
    else:
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
