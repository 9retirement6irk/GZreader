#!/usr/bin/env python3
"""A Grimmory stand-in with a real demo library, for screenshots.

  demo_grimmory.py <mock_grimmory.py> <library dir from make_library.py> <port>

Reuses the test suite's mock Grimmory (login, progress, bookmarks, the app
book lists…) and replaces its fake books with the demo library: real EPUBs
and covers. Login: user "reader", password "demo". Downloads trickle a bit
so the progress dialog can be seen.
"""
import importlib.util, json, os, sys, time
from http.server import ThreadingHTTPServer
from urllib.parse import urlparse

mock_path, LIB, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
sys.argv = [mock_path, str(port)]
spec = importlib.util.spec_from_file_location("mock_grimmory", mock_path)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

lib = json.load(open(os.path.join(LIB, "library.json")))
names = sorted({b["library"] for b in lib})
lib_ids = {n: i + 1 for i, n in enumerate(names)}
m.USERS.clear()
m.USERS["reader"] = "demo"
m.BOOKS[:] = []
for b in lib:
    m.BOOKS.append({
        "id": b["id"], "title": b["title"], "authors": [b["author"]], "primaryFileType": "EPUB",
        "primaryFileName": "%d.epub" % b["id"], "fileSizeKb": max(1, b["size"] // 1024),
        "readProgress": {2: 34.0, 3: 8.5}.get(b["id"]), "primaryFileId": 1000 + b["id"],
        "libraryId": lib_ids[b["library"]], "seriesName": b["series"], "seriesNumber": b["number"],
    })
m.LIBRARIES[:] = [{"id": lib_ids[n], "name": n, "bookCount": sum(1 for b in lib if b["library"] == n)} for n in names]
authors = sorted({b["author"] for b in lib})
m.AUTHORS[:] = [{"id": 100 + i, "name": a, "bookCount": sum(1 for b in lib if b["author"] == a), "hasPhoto": False}
                for i, a in enumerate(authors)]
m.SERIES[:] = [{"seriesName": "Father Brown", "bookCount": 1, "seriesTotal": 5, "authors": ["G. K. Chesterton"]}]
m.SHELVES.clear()
m.SHELVES[1] = [1, 6, 12]
m.SUBTITLES.clear()
m.SUBTITLES[6] = "Father Brown, book 1"

orig_get = m.H.do_GET


def do_GET(self):
    u = urlparse(self.path)
    parts = u.path.split("/")
    if u.path == "/api/v1/app/books/continue-reading":
        if not self._user():
            return self._json(401)
        return self._json(200, [b for b in m.BOOKS if b.get("readProgress")])
    if u.path == "/api/v1/app/books/recently-added":
        if not self._user():
            return self._json(401)
        return self._json(200, list(reversed(m.BOOKS))[:12])
    if u.path.startswith("/api/v1/media/book/") and u.path.endswith("/thumbnail"):
        if not self._user():
            return self._json(401)
        p = os.path.join(LIB, "%s.jpg" % parts[5])
        if os.path.exists(p):
            data = open(p, "rb").read()
            self.send_response(200); self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
            return
    if u.path.startswith("/api/v1/books/") and u.path.endswith("/download"):
        if not self._user():
            return self._json(401)
        p = os.path.join(LIB, "%s.epub" % parts[4])
        if os.path.exists(p):
            data = open(p, "rb").read()
            self.send_response(200); self.send_header("Content-Type", "application/epub+zip")
            self.send_header("Content-Length", str(len(data))); self.end_headers()
            try:
                for i in range(0, len(data), 8192):
                    self.wfile.write(data[i:i + 8192]); self.wfile.flush()
                    time.sleep(float(os.environ.get("DEMO_DL_DELAY", "0.12")))
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
    return orig_get(self)


m.H.do_GET = do_GET
srv = ThreadingHTTPServer(("127.0.0.1", port), m.H)
print("demo Grimmory on", port, flush=True)
srv.serve_forever()
