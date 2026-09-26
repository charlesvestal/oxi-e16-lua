import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
import build  # noqa: E402
import make_chords  # noqa: E402

SPECS = sorted(f[:-5] for f in os.listdir(os.path.join(HERE, "..", "specs")) if f.endswith(".json"))


class BuildTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        build.build(cls.tmp.name)
        cls.data = json.load(open(os.path.join(cls.tmp.name, "data.json")))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_chords_files(self):
        for slug in SPECS:
            title, chords = make_chords.read(os.path.join(self.tmp.name, "sets", slug + ".chords"))
            self.assertEqual(sorted(chords), list(range(16)), slug)

    def test_data_sets(self):
        src = [s["source"] for s in self.data["sets"]]
        self.assertEqual((src.count("generated"), src.count("reference")), (len(SPECS), 11))
        s = next(s for s in self.data["sets"] if s["slug"] == "neo_soul")
        self.assertEqual(s["reference"], "neo_soul_minor")
        self.assertIn("ref_neo_soul_minor", [x["slug"] for x in self.data["sets"]])
        self.assertEqual(len(s["pads"]), 16)
        self.assertEqual(set(s["pads"][0]), {"symbol", "notes", "label"})
        self.assertIn("vl_row", s["metrics"])

    def test_ranges_per_type(self):
        self.assertEqual(set(self.data["ranges"]), {"functional", "shape", "pedal"})
        self.assertEqual(len(self.data["ranges"]["functional"]["span"]), 3)

    def test_bad_spec_exits_with_pad(self):
        with tempfile.TemporaryDirectory() as d:
            specs = os.path.join(d, "specs")
            os.makedirs(specs)
            rows = [["C", "F", "G", "Qm7"]] + [["C", "F", "G", "C"]] * 3
            json.dump({"name": "Bad", "type": "functional", "style": "close", "rows": rows},
                      open(os.path.join(specs, "bad.json"), "w"))
            r = subprocess.run([sys.executable, os.path.join(HERE, "..", "build.py"),
                                "--specs", specs, "--out", d, "--no-reference"],
                               capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("Bad: pad 4", r.stderr)


if __name__ == "__main__":
    unittest.main()
