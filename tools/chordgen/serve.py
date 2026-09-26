#!/usr/bin/env python3
"""Serve the chord-set harness: the page, build/chordgen/data.json, and
POST /feedback, which saves build/chordgen/feedback.json.

usage: serve.py [PORT]   (default 8016), then open http://localhost:PORT/"""
import functools
import http.server
import json
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.abspath(os.path.join(HERE, "..", "..", "build", "chordgen"))
FILES = {"/data.json", "/feedback.json"}


class Handler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        p = path.split("?", 1)[0]
        if p in FILES:
            return os.path.join(self.server.build, p[1:])
        return super().translate_path(path)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        if self.path != "/feedback":
            return self.send_error(404)
        n = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(n))
        except ValueError:
            return self.send_error(400, "feedback must be JSON")
        if not isinstance(body, dict):
            return self.send_error(400, "feedback must be a JSON object")
        body["saved"] = time.strftime("%Y-%m-%dT%H:%M:%S")
        os.makedirs(self.server.build, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=self.server.build, suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(body, f, indent=1)
        os.replace(tmp, os.path.join(self.server.build, "feedback.json"))
        self.send_response(204)
        self.end_headers()

    def log_message(self, fmt, *args):
        pass


def make_server(port=8016, build=BUILD):
    handler = functools.partial(Handler, directory=os.path.join(HERE, "harness"))
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    httpd.build = build
    return httpd


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8016
    if not os.path.exists(os.path.join(BUILD, "data.json")):
        print("no build/chordgen/data.json yet: run python3 tools/chordgen/build.py first")
    httpd = make_server(port)
    print(f"chord sets harness: http://localhost:{port}/  (Ctrl-C to stop)")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
