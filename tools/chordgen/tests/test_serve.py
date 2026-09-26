import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import serve  # noqa: E402


class ServeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        open(os.path.join(self.tmp.name, "data.json"), "w").write('{"sets": []}')
        self.httpd = serve.make_server(0, self.tmp.name)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.httpd.server_address[1]}"

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.tmp.cleanup()

    def post(self, path, body):
        req = urllib.request.Request(self.base + path, data=body, method="POST",
                                     headers={"Content-Type": "application/json"})
        return urllib.request.urlopen(req)

    def test_serves_page_and_data(self):
        self.assertIn(b"<html", urllib.request.urlopen(self.base + "/").read().lower())
        self.assertEqual(json.load(urllib.request.urlopen(self.base + "/data.json")), {"sets": []})

    def test_feedback_roundtrip(self):
        r = self.post("/feedback", json.dumps({"sets": {"neo_soul": {"verdict": "keep"}}}).encode())
        self.assertEqual(r.status, 204)
        fb = json.load(open(os.path.join(self.tmp.name, "feedback.json")))
        self.assertEqual(fb["sets"]["neo_soul"]["verdict"], "keep")
        self.assertIn("saved", fb)
        self.assertEqual(json.load(urllib.request.urlopen(self.base + "/feedback.json"))["sets"],
                         fb["sets"])

    def test_rejects_non_json(self):
        with self.assertRaises(urllib.error.HTTPError) as e:
            self.post("/feedback", b"not json")
        self.assertEqual(e.exception.code, 400)

    def test_missing_feedback_is_404(self):
        with self.assertRaises(urllib.error.HTTPError) as e:
            urllib.request.urlopen(self.base + "/feedback.json")
        self.assertEqual(e.exception.code, 404)


if __name__ == "__main__":
    unittest.main()
