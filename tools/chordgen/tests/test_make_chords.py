import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
import make_chords  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


class ReadTest(unittest.TestCase):
    def test_read_parses_name_and_sorted_notes(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "x.chords")
            open(p, "w").write("Name: Test Set\n0: 64,48,60\n1: 50,62\n")
            title, chords = make_chords.read(p)
        self.assertEqual(title, "Test Set")
        self.assertEqual(chords, {0: [48, 60, 64], 1: [50, 62]})

    def test_dir_option_packs_local_sets(self):
        with tempfile.TemporaryDirectory() as d:
            lines = ["Name: Local One"] + [f"{i}: {48 + i},{55 + i},{64 + i}" for i in range(16)]
            open(os.path.join(d, "local_one.chords"), "w").write("\n".join(lines) + "\n")
            target = os.path.join(d, "chords.lua")
            open(target, "w").write(open(os.path.join(ROOT, "chords.lua")).read())
            r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "make_chords.py"),
                                "--dir", d, target, "local_one"], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            src = open(target).read()
        self.assertIn("local T = [=[Local One]=]", src)


if __name__ == "__main__":
    unittest.main()
