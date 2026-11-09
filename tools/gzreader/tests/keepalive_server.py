"""An HTTP/1.1 server for the keep-alive test (run_tests.lua): counts its
connections. GET /n: {"conn": <this connection's number>}; /close: answers
with Connection: close; /drop: answers, then closes without saying so (as a
server whose idle timeout passed). python3 -I keepalive_server.py <port>"""
import json, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

lock = threading.Lock()
count = {"conn": 0}


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def setup(self):
        super().setup()
        with lock:
            count["conn"] += 1
            self.conn_no = count["conn"]

    def log_message(self, *a):
        pass

    def reply(self, close=False):
        body = json.dumps({"conn": self.conn_no, "path": self.path}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        if close:
            self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/close"):
            self.reply(close=True)
            self.close_connection = True
        elif self.path.startswith("/drop"):
            self.reply()
            self.close_connection = True
        else:
            self.reply()

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        self.rfile.read(n)
        self.reply()


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
