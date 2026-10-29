import http.server, sys, json, time
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0)); b = self.rfile.read(n)
        try: d = json.loads(b)
        except Exception: d = {"raw": b[:200].decode("utf8", "replace")}
        with open(sys.argv[2], "a") as f:
            f.write("%s %s %s\n%s\n----\n" % (time.strftime("%H:%M:%S"), self.path, d.get("eventName"), d.get("eventContent")))
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(b'{"ok":true}')
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
