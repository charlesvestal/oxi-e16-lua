#!/usr/bin/env python3
"""Mine the McGill Billboard chord annotations for common progressions.

The annotations (CC0; Burgoyne, Wild & Fujinaga, ISMIR 2011) cover songs from
the Billboard Hot 100, 1958-1991. Each song becomes a chord sequence relative to
its tonic ("I", "vi7", "bVII", "IV/5"); consecutive repeats are merged and the
4-chord windows are counted, overall and by decade. The data is downloaded into
build/billboard/ (gitignored) and never committed.

usage: billboard.py [--top N] [--decade 1960] [--minor]"""
import argparse
import collections
import csv
import glob
import os
import re
import tarfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.abspath(os.path.join(HERE, "..", "..", "build", "billboard"))
SALAMI = "https://www.dropbox.com/s/2lvny9ves8kns4o/billboard-2.0-salami_chords.tar.gz?dl=1"
INDEX = "https://www.dropbox.com/s/o0olz0uwl9z9stb/billboard-2.0-index.csv?dl=1"

PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
DEGREE = ["I", "bII", "II", "bIII", "III", "IV", "#IV", "V", "bVI", "VI", "bVII", "VII"]
# Harte qualities -> (minor?, suffix in our symbol style)
QUALITY = {
    "maj": (False, ""), "min": (True, ""), "7": (False, "7"), "maj7": (False, "maj7"),
    "min7": (True, "7"), "maj6": (False, "6"), "min6": (True, "6"), "9": (False, "9"),
    "maj9": (False, "maj9"), "min9": (True, "9"), "11": (False, "11"), "min11": (True, "11"),
    "13": (False, "13"), "min13": (True, "13"), "sus4": (False, "sus4"), "sus2": (False, "sus2"),
    "sus4(b7)": (False, "7sus4"), "sus4(b7,9)": (False, "9sus4"), "dim": (True, "dim"),
    "dim7": (True, "dim7"), "hdim7": (True, "m7b5"), "aug": (False, "aug"),
    "5": (False, "5"), "1": (False, "5"), "minmaj7": (True, "maj7"), "maj(9)": (False, "add9"),
    "min(9)": (True, "add9"),
}


def fetch():
    """Download and unpack the annotations once."""
    os.makedirs(DATA, exist_ok=True)
    if not glob.glob(os.path.join(DATA, "McGill-Billboard", "*", "salami_chords.txt")):
        path = os.path.join(DATA, "salami.tar.gz")
        urllib.request.urlretrieve(SALAMI, path)
        with tarfile.open(path) as t:
            t.extractall(DATA, filter="data")
    index = os.path.join(DATA, "index.csv")
    if not os.path.exists(index):
        urllib.request.urlretrieve(INDEX, index)


def pc(name):
    p = PC[name[0]]
    for a in name[1:]:
        p += 1 if a == "#" else -1
    return p % 12


def roman(chord, tonic):
    """'A:min7' in C -> 'vi7'; None for N/X or unknown qualities."""
    m = re.match(r"([A-G][#b]*):([^/]+)(?:/(.+))?$", chord)
    if not m:
        return None
    root, qual, inv = m.groups()
    if qual not in QUALITY:
        return None
    minor, suf = QUALITY[qual]
    deg = DEGREE[(pc(root) - tonic) % 12]
    if minor:
        deg = deg.lower()
    return deg + suf + (f"/{inv}" if inv in ("3", "b3", "5", "b7", "7") else "")


def songs():
    """(year, tonic pc, [roman chords with repeats merged]) per annotation."""
    years = {}
    with open(os.path.join(DATA, "index.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["chart_date"]:
                years[int(row["id"])] = int(row["chart_date"][:4])
    for path in sorted(glob.glob(os.path.join(DATA, "McGill-Billboard", "*", "salami_chords.txt"))):
        sid = int(os.path.basename(os.path.dirname(path)))
        tonic, seq = None, []
        with open(path, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"# tonic: (\S+)", line)
                if m:
                    tonic = pc(m.group(1))
                    continue
                if line.startswith("#") or tonic is None:
                    continue
                for bar in re.findall(r"\|([^|]*)(?=\|)", line):
                    for tok in bar.split():
                        if tok == ".":
                            continue
                        r = roman(tok, tonic)
                        if r and (not seq or seq[-1] != r):
                            seq.append(r)
        if seq:
            yield years.get(sid), tonic, seq


def minor_song(seq):
    """A song in a minor key uses its minor tonic more than the major one."""
    minor = sum(1 for s in seq if re.match(r"i(?![iv])", s))
    major = sum(1 for s in seq if re.match(r"I(?![IV])", s))
    return minor > major


def progressions(n=4, decade=None, minor=None):
    """Counter of n-chord windows (as tuples), each counted once per song."""
    count = collections.Counter()
    for year, _, seq in songs():
        if decade and not (year and decade <= year < decade + 10):
            continue
        if minor is not None and minor_song(seq) != minor:
            continue
        count.update({tuple(seq[i:i + n]) for i in range(len(seq) - n + 1)})
    return count


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--decade", type=int)
    ap.add_argument("--minor", action="store_true", help="only songs in minor keys")
    ap.add_argument("--major", action="store_true", help="only songs in major keys")
    a = ap.parse_args()
    fetch()
    minor = True if a.minor else False if a.major else None
    for prog, k in progressions(decade=a.decade, minor=minor).most_common(a.top):
        print(f"{k:4} songs  {' - '.join(prog)}")


if __name__ == "__main__":
    main()
