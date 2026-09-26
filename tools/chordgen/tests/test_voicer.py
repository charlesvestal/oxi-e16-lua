import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import theory  # noqa: E402
import voicer  # noqa: E402

FUNCTIONAL = {
    "name": "Test Functional", "type": "functional", "key": "C", "style": "rootless",
    "rows": [["Cmaj9", "Am9", "Dm11", "G13"], ["Em7", "A7b9", "Dm9", "G7sus4"],
             ["Fmaj7#11", "Em11", "Am9", "D9"], ["Dm9", "G13", "Cmaj9", "C6"]],
}
PEDAL = {
    "name": "Test Pedal", "type": "pedal", "key": "E", "style": "open",
    "rows": [["Emaj9", "Cmaj7#11", "Amaj9", "Fmaj7#11"], ["Gmaj7", "D69", "Bm11", "C#m11"],
             ["G#m7", "Db9sus4", "Fm7b5", "E6"], ["A69", "G6", "Cmaj7#11", "Esus2"]],
}


class HardRulesTest(unittest.TestCase):
    def check(self, spec):
        reg = voicer.register(spec)
        out = voicer.voice_set(spec)
        syms = [s for r in spec["rows"] for s in r]
        self.assertEqual(len(out), 16)
        for sym, notes in zip(syms, out):
            root, _, slash, _ = theory.parse(sym)
            self.assertEqual(notes[0] % 12, root if slash is None else slash, sym)
            self.assertTrue(reg["bass"][0] <= notes[0] <= reg["bass"][1], (sym, notes))
            self.assertTrue(reg["top"][0] <= notes[-1] <= reg["top"][1], (sym, notes))
            self.assertEqual(theory.mud(notes), 0, (sym, notes))
            self.assertTrue(3 <= len(notes) <= 7, (sym, notes))
            self.assertLessEqual({n % 12 for n in notes}, theory.pcs(sym), (sym, notes))
        return out

    def test_functional(self):
        self.check(FUNCTIONAL)

    def test_pedal_holds_the_top(self):
        out = self.check(PEDAL)
        tops = [c[-1] for c in out]
        self.assertLessEqual(sum(abs(b - a) for a, b in zip(tops, tops[1:])) / 15, 1.0, tops)

    def test_shape(self):
        spec = {"name": "Test Shape", "type": "shape", "key": "Am", "style": "shape",
                "register": {"bass": [30, 42], "top": [56, 72]},
                "shapes": {"m9": [0, 19, 22, 26, 27]},
                "rows": [["Am9", "Cm9", "Ebm9", "F#m9"]] * 4}
        out = self.check(spec)
        self.assertEqual([n - out[0][0] for n in out[0]], [0, 19, 22, 26, 27])

    def test_shape_slash_keeps_slash_bass_and_root_shape(self):
        spec = {"name": "Test Shape Slash", "type": "shape", "key": "Am", "style": "shape",
                "register": {"bass": [30, 42], "top": [56, 72]},
                "shapes": {"m9": [0, 19, 22, 26, 27]},
                "rows": [["Am9/C", "Cm9", "Ebm9", "F#m9"]] + [["Am9", "Cm9", "Ebm9", "F#m9"]] * 3}
        out = self.check(spec)
        self.assertEqual(out[0][0] % 12, 0)
        self.assertEqual({n % 12 for n in out[0]}, theory.pcs("Am9/C"))

    def test_rootless_slash_keeps_the_root(self):
        rows = [r[:] for r in FUNCTIONAL["rows"]]
        rows[0][0] = "C/E"
        out = self.check(dict(FUNCTIONAL, rows=rows))
        self.assertEqual(out[0][0] % 12, 4)
        self.assertIn(0, {n % 12 for n in out[0]}, out[0])

    def test_deterministic(self):
        self.assertEqual(voicer.voice_set(FUNCTIONAL), voicer.voice_set(FUNCTIONAL))


class ErrorsTest(unittest.TestCase):
    def test_impossible_register_names_the_pad(self):
        spec = dict(FUNCTIONAL, register={"bass": [39, 52], "top": [60, 61]})
        with self.assertRaisesRegex(voicer.VoicingError, "pad 1 .Cmaj9.: no voicing satisfies the hard rules"):
            voicer.voice_set(spec)

    def test_voicing_error_without_name(self):
        spec = dict(FUNCTIONAL, register={"bass": [39, 52], "top": [60, 61]})
        del spec["name"]
        with self.assertRaisesRegex(voicer.VoicingError, r"^\?: pad 1"):
            voicer.voice_set(spec)

    def test_non_string_symbol_names_pad(self):
        rows = [r[:] for r in FUNCTIONAL["rows"]]
        rows[2][1] = 7
        with self.assertRaisesRegex(ValueError, "Test Functional: pad 10"):
            voicer.validate(dict(FUNCTIONAL, rows=rows))

    def test_bad_shapes(self):
        for shapes in ([0, 7], {"m9": [0]}, {"m9": [0, 7, 10, 14, 15, 17, 19]},
                       {"m9": [0, -5, 7]}, {"m9": [0, "7"]}, {"m9": "0 7"}, {"m9": [0, True]}):
            with self.assertRaisesRegex(ValueError, "Test Functional: shapes", msg=shapes):
                voicer.validate(dict(FUNCTIONAL, shapes=shapes))

    def test_bad_register(self):
        for reg in ([39, 52], {"bass": [52, 39]}, {"top": [64]}, {"bass": [39.5, 52]},
                    {"top": "64-74"}, {"middle": [50, 60]}):
            with self.assertRaisesRegex(ValueError, "Test Functional: register", msg=reg):
                voicer.validate(dict(FUNCTIONAL, register=reg))

    def test_good_register_and_shapes_pass(self):
        voicer.validate(dict(FUNCTIONAL, register={"bass": [30, 42]}, shapes={"m9": [0, 19, 22]}))

    def test_bad_rows(self):
        with self.assertRaisesRegex(ValueError, "4 rows of 4"):
            voicer.validate(dict(FUNCTIONAL, rows=[["C"]]))

    def test_bad_symbol_names_pad(self):
        rows = [r[:] for r in FUNCTIONAL["rows"]]
        rows[1][2] = "Qm7"
        with self.assertRaisesRegex(ValueError, "pad 7"):
            voicer.validate(dict(FUNCTIONAL, rows=rows))


if __name__ == "__main__":
    unittest.main()
