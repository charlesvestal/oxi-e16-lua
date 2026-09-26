import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import theory  # noqa: E402


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


class LabelTest(unittest.TestCase):
    def test_minor_is_lowercase(self):
        self.assertEqual(theory.label([39, 58, 61, 66]), "d#7")     # D#m7

    def test_major_seventh(self):
        self.assertEqual(theory.label([48, 64, 67, 71]), "CM7")

    def test_unnamed_is_bass_and_question_mark(self):
        self.assertEqual(theory.label([48, 49, 50, 51]), "C?")

    def test_four_characters(self):
        self.assertLessEqual(len(theory.label([48, 64, 67, 71, 78])), 4)


class ToolsTest(unittest.TestCase):
    def test_vl_pairs_voices(self):
        self.assertEqual(theory.vl([60, 64, 67], [60, 65, 69]), 3)

    def test_vl_extra_voice_goes_to_nearest(self):
        self.assertEqual(theory.vl([60, 64, 67], [60, 64, 67, 70]), 3)

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
