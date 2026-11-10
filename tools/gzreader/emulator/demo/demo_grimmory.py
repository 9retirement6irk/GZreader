#!/usr/bin/env python3
"""A Grimmory stand-in with a real demo library, for screenshots.

  demo_grimmory.py <mock_grimmory.py> <library dir from make_library.py> <port>

Reuses the test suite's mock Grimmory (login, progress, bookmarks, the app
book lists…) and replaces its fake books with the demo library: real EPUBs
and covers. Login: user "reader", password "demo". Downloads trickle a bit
so the progress dialog can be seen. With the library's audio.json, the
made-up audiobooks too (folder-based, the test suite's tone as each chapter),
for the Catalog's Audiobooks page.
"""
import importlib.util, json, os, sys, time
from http.server import ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

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
        "primaryFileName": "%s.epub" % b["title"].replace("'", ""), "fileSizeKb": max(1, b["size"] // 1024),
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

AUDIO = {}
audio_json = os.path.join(LIB, "audio.json")
if os.path.exists(audio_json):
    TONE = open(os.path.join(os.path.dirname(os.path.abspath(mock_path)), "media", "tone.mp3"), "rb").read()
    m.LIBRARIES.append({"id": 9, "name": "Audiobooks", "bookCount": 0})
    for a in json.load(open(audio_json))["audiobooks"]:
        AUDIO[a["id"]] = a
        m.BOOKS.append({
            "id": a["id"], "title": a["title"], "authors": [a["author"]], "primaryFileType": "AUDIOBOOK",
            "primaryFileName": a["title"], "fileSizeKb": 28000 * a["chapters"],   # (as a real one would be)
            "readProgress": a["progress"], "primaryFileId": 1000 + a["id"], "libraryId": 9,
            "seriesName": None, "seriesNumber": None,
        })
        m.DESCRIPTIONS[a["id"]] = "<p><i>%s</i> by %s, read by %s.</p>" % (a["title"], a["author"], a["narrator"])
    m.LIBRARIES[-1]["bookCount"] = len(AUDIO)
    for au in m.AUTHORS:
        au["bookCount"] = sum(1 for b in m.BOOKS if au["name"] in b["authors"])
    for name in sorted({a["author"] for a in AUDIO.values()} - {au["name"] for au in m.AUTHORS}):
        m.AUTHORS.append({"id": 100 + len(m.AUTHORS), "name": name, "bookCount": sum(1 for a in AUDIO.values() if a["author"] == name), "hasPhoto": False})
    m.SHELVES[6] = [101, 103]


def readable():
    return [b for b in m.BOOKS if b["primaryFileType"] != "AUDIOBOOK"]


def send_file(self, path, ctype):
    data = open(path, "rb").read()
    self.send_response(200); self.send_header("Content-Type", ctype)
    self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)

orig_get = m.H.do_GET


def do_GET(self):
    u = urlparse(self.path)
    parts = u.path.split("/")
    if u.path == "/api/v1/app/books/continue-reading":
        if not self._user():
            return self._json(401)
        return self._json(200, [b for b in readable() if b.get("readProgress")])
    if u.path == "/api/v1/app/books/recently-added":
        if not self._user():
            return self._json(401)
        return self._json(200, list(reversed(readable()))[:12])
    q = parse_qs(u.query)
    if u.path == "/api/v1/app/books" and (q.get("status") or q.get("sort") == ["addedOn"]):
        # (the Catalog's Audiobooks page: in progress, and newest first)
        if not self._user():
            return self._json(401)
        types = q.get("fileType", [])
        books = [b for b in m.BOOKS if not types or b["primaryFileType"] in types]
        if q.get("status"):
            books = [b for b in books if b.get("readProgress")]
        else:
            books = list(reversed(books))
        return self._json(200, m.page_of(books, q, 20))
    if len(parts) == 6 and parts[4] == "books" and parts[5].isdigit() and parts[3] == "app":
        # (a book's page: what a real library would say about it)
        b = next((x for x in m.BOOKS if x["id"] == int(parts[5])), None)
        if b and b["primaryFileType"] == "EPUB":
            lib_name = next((n for n, i in lib_ids.items() if i == b["libraryId"]), "Classics")
            out = dict(b, subtitle=m.SUBTITLES.get(b["id"]), categories=[lib_name.rstrip("s"), "Public domain"],
                       description="<p>%s by %s, from Project Gutenberg's public-domain collection.</p>" % (b["title"], b["authors"][0]),
                       pageCount=max(40, b["fileSizeKb"] * 2), publisher="Project Gutenberg", publishedDate=None,
                       goodreadsRating=None, goodreadsReviewCount=None)
            return self._json(200, out)
    a = None
    if len(parts) > 4 and parts[3] in ("audiobooks", "media") and parts[4].isdigit():
        a = AUDIO.get(int(parts[4]))
    elif len(parts) > 5 and parts[4] == "book" and parts[5].isdigit():
        a = AUDIO.get(int(parts[5]))
    if a and (u.path.endswith("/cover") or u.path.endswith("thumbnail")):
        if not self._user():
            return self._json(401)
        return send_file(self, os.path.join(LIB, "a%d.jpg" % a["id"]), "image/jpeg")
    if a and u.path.endswith("/info"):
        if not self._user():
            return self._json(401)
        n, ms = a["chapters"], 25 * 60000
        return self._json(200, {"bookId": a["id"], "bookFileId": 1000 + a["id"], "title": a["title"], "author": a["author"],
            "narrator": a["narrator"], "durationMs": n * ms, "codec": "mp3", "folderBased": True, "totalSizeBytes": n * len(TONE),
            "tracks": [{"index": i, "fileName": "%02d Chapter %d.mp3" % (i + 1, i + 1), "title": "Chapter %d" % (i + 1), "durationMs": ms,
                        "fileSizeBytes": len(TONE), "cumulativeStartMs": i * ms} for i in range(n)],
            "chapters": []})
    if a and u.path.endswith("/stream"):
        if not self._user():
            return self._json(401)
        self.send_response(200); self.send_header("Content-Type", "audio/mpeg")
        self.send_header("Content-Length", str(len(TONE))); self.end_headers()
        time.sleep(float(os.environ.get("DEMO_DL_DELAY", "0.12")) * 4)
        self.wfile.write(TONE)
        return
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
