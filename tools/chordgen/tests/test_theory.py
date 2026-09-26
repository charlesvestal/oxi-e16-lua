import itertools
import os
import random
import re
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import theory  # noqa: E402


def _vl_brute_force(a, b):
    """Old brute-force reference: total semitones moved, pairing voices in
    order; voices without a partner move to the nearest note of the other
    chord."""
    a, b = sorted(a), sorted(b)
    if len(a) > len(b):
        a, b = b, a
    best = None
    for combo in itertools.combinations(range(len(b)), len(a)):
        cost = sum(abs(a[i] - b[j]) for i, j in enumerate(combo))
        cost += sum(min(abs(b[j] - x) for x in a) for j in range(len(b)) if j not in combo)
        best = cost if best is None else min(best, cost)
    return best


class ParseTest(unittest.TestCase):
    def test_minor_ninth(self):
        self.assertEqual(theory.parse("Ebm9"), (3, (0, 3, 7, 10, 14), None, "m9"))

    def test_slash(self):
        self.assertEqual(theory.parse("F/A"), (5, (0, 4, 7), 9, ""))

    def test_flat_root_and_long_quality(self):
        self.assertEqual(theory.parse("Bbmaj7#11")[0], 10)
        self.assertEqual(theory.parse("Bbmaj7#11")[3], "maj7#11")

    def test_aliases(self):
        self.assertEqual(theory.parse("CM7")[3], "maj7")
        self.assertEqual(theory.parse("Csus")[3], "sus4")
        self.assertEqual(theory.parse("Bh7")[3], "m7b5")

    def test_errors_name_the_symbol(self):
        with self.assertRaisesRegex(ValueError, "Hm7"):
            theory.parse("Hm7")
        with self.assertRaisesRegex(ValueError, "Cxyz"):
            theory.parse("Cxyz")

    def test_pcs_include_slash_bass(self):
        self.assertEqual(theory.pcs("C/Bb"), {0, 4, 7, 10})

    def test_empty_slash_bass_is_an_error(self):
        with self.assertRaisesRegex(ValueError, re.escape("C/")):
            theory.parse("C/")

    def test_mixed_accidentals_are_an_error(self):
        with self.assertRaisesRegex(ValueError, re.escape("C#b")):
            theory.parse("C#b")


class LabelTest(unittest.TestCase):
    def test_minor_is_lowercase(self):
        self.assertEqual(theory.label([39, 58, 61, 66]), "d#7")     # D#m7

    def test_major_seventh(self):
        self.assertEqual(theory.label([48, 64, 67, 71]), "CM7")

    def test_unnamed_is_bass_and_question_mark(self):
        self.assertEqual(theory.label([48, 49, 50, 51]), "C?")

    def test_four_characters(self):
        self.assertLessEqual(len(theory.label([48, 64, 67, 71, 78])), 4)

    def test_drops_notes_outside_22_115(self):
        self.assertEqual(theory.label([10, 48, 64, 67, 71, 200]), "CM7")

    def test_empty_when_nothing_in_range(self):
        self.assertEqual(theory.label([10, 200]), "")

    def test_all_qualities_are_nameable(self):
        for name, ivs in theory.QUALITY.items():
            notes = [48 + i for i in ivs]
            lbl = theory.label(notes)
            self.assertFalse(lbl.endswith("?"), f"quality {name!r} -> {lbl!r}")


class ToolsTest(unittest.TestCase):
    def test_vl_pairs_voices(self):
        self.assertEqual(theory.vl([60, 64, 67], [60, 65, 69]), 3)

    def test_vl_extra_voice_goes_to_nearest(self):
        self.assertEqual(theory.vl([60, 64, 67], [60, 64, 67, 70]), 3)

    def test_vl_matches_brute_force(self):
        rng = random.Random(20260926)
        for _ in range(300):
            na, nb = rng.randint(1, 7), rng.randint(1, 7)
            a = [rng.randint(30, 90) for _ in range(na)]
            b = [rng.randint(30, 90) for _ in range(nb)]
            self.assertEqual(theory.vl(a, b), _vl_brute_force(a, b), (a, b))

    def test_mud(self):
        self.assertEqual(theory.mud([40, 43, 47]), 2)      # 40-43 and 43-47 under a 4th below A2
        self.assertEqual(theory.mud([40, 52, 55, 59]), 0)
        self.assertEqual(theory.mud([48, 50, 55]), 1)      # a 2nd below E3

    def test_key_of_c_major_triads(self):
        chords = [[48, 52, 55], [53, 57, 60], [55, 59, 62], [48, 52, 55]]
        fit, k, q = theory.key(chords)
        self.assertEqual((k, q), (0, ""))

    def test_scale(self):
        self.assertEqual(theory.scale(9, "m"), {9, 11, 0, 2, 4, 5, 7})


if __name__ == "__main__":
    unittest.main()
