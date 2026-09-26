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

    def test_deterministic(self):
        self.assertEqual(voicer.voice_set(FUNCTIONAL), voicer.voice_set(FUNCTIONAL))


class ErrorsTest(unittest.TestCase):
    def test_impossible_register_names_the_pad(self):
        spec = dict(FUNCTIONAL, register={"bass": [39, 52], "top": [60, 61]})
        with self.assertRaisesRegex(voicer.VoicingError, "pad 1 .Cmaj9."):
            voicer.voice_set(spec)

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
