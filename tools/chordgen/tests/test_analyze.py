import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
import analyze  # noqa: E402
import make_chords  # noqa: E402


def pads(name):
    _, ch = make_chords.fetch(name)
    return [ch[i] for i in range(16)]


class ReferenceTest(unittest.TestCase):
    def test_neo_soul_minor(self):
        m = analyze.metrics(pads("neo_soul_minor"))
        self.assertEqual((m["diatonic"], m["shapes"]), (13, 15))
        self.assertEqual((m["bass_lo"], m["bass_hi"], m["top_lo"], m["top_hi"]), (39, 47, 58, 70))
        self.assertEqual((m["top_step"], m["vl_row"], m["mud"]), (2.4, 9.8, 0))
        self.assertEqual(m["key"], "F#")

    def test_detroit(self):
        m = analyze.metrics(pads("detroit_techno"))
        self.assertEqual((m["shapes"], m["bass_lo"], m["bass_hi"]), (8, 30, 42))

    def test_all_metrics_present(self):
        m = analyze.metrics(pads("cinematic"))
        for k in analyze.METRICS + ["key", "fit"]:
            self.assertIn(k, m)


class SpecKeyTest(unittest.TestCase):
    def test_diatonic_uses_the_spec_key(self):
        chords = [[51, 58, 61, 66]] * 16                 # Ebm7: diatonic in Eb minor, not in E major
        self.assertEqual(analyze.metrics(chords, "Ebm")["diatonic"], 16)
        self.assertEqual(analyze.metrics(chords, "E")["diatonic"], 0)


class RangesTest(unittest.TestCase):
    def test_min_median_max(self):
        ms = [dict.fromkeys(analyze.METRICS, v) for v in (1, 2, 10)]
        r = analyze.ranges(ms)
        self.assertEqual(r["span"], [1, 2, 10])


if __name__ == "__main__":
    unittest.main()
