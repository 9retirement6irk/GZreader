#!/usr/bin/env python3
"""A stand-in for Claude's Messages API (handwriting to text in the emulator).

POST /v1/messages answers {"content": [{"type": "text", "text": ANSWER}]}
and keeps what it was sent: whether the key and version headers came, the
model, and the picture (its media type and size). GET /__state returns that
as JSON. Only on 127.0.0.1.

  python3 -I mock_claude.py <port> [answer]
"""
import base64
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1])
ANSWER = sys.argv[2] if len(sys.argv) > 2 else "Speaking of work"
STATE = {"requests": []}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/__state":
            return self._json(200, STATE)
        self._json(404, {})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n)
        try:
            req = json.loads(raw)
        except ValueError:
            return self._json(400, {"error": {"message": "not json"}})
        image = None
        for m in req.get("messages", []):
            for c in m.get("content", []):
                if c.get("type") == "image":
                    data = base64.b64decode(c["source"]["data"])
                    image = {"media_type": c["source"]["media_type"], "bytes": len(data), "png": data[:8] == b"\x89PNG\r\n\x1a\n"}
        STATE["requests"].append({
            "path": self.path,
            "key": self.headers.get("x-api-key"),
            "version": self.headers.get("anthropic-version"),
            "agent": self.headers.get("User-Agent"),
            "model": req.get("model"),
            "image": image,
        })
        if self.headers.get("x-api-key") != "sk-ant-test-key":
            return self._json(401, {"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}})
        self._json(200, {"type": "message", "role": "assistant", "content": [{"type": "text", "text": ANSWER}]})


HTTPServer(("127.0.0.1", PORT), H).serve_forever()
