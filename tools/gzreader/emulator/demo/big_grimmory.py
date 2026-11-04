#!/usr/bin/env python3
"""A Grimmory stand-in with a big library, for memory tests.

  big_grimmory.py <mock_grimmory.py> <port> [books, default 6000]

Reuses the test suite's mock Grimmory and fills it with N books (EPUB, PDF
and some audiobooks), about one author per 4 books and one series per 6,
with every field Grimmory's app book list sends, and real JPEG covers
(250 x 350, made on the fly). Login: user "reader", password "demo".
"""
import importlib.util, io, os, random, sys
from http.server import ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

mock_path, port = sys.argv[1], int(sys.argv[2])
N = int(sys.argv[3]) if len(sys.argv) > 3 else 6000
sys.argv = [mock_path, str(port)]
spec = importlib.util.spec_from_file_location("mock_grimmory", mock_path)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

rnd = random.Random(7)
WORDS = ("night river glass winter crown shadow garden letter storm silver house city sea "
         "lantern orchard iron paper mountain bridge echo hollow ember quiet thread").split()
m.USERS.clear()
m.USERS["reader"] = "demo"
m.BOOKS[:] = []
n_auth, n_series = max(1, N // 4), max(1, N // 6)
for i in range(1, N + 1):
    t = "AUDIOBOOK" if i % 23 == 0 else ("PDF" if i % 7 == 0 else "EPUB")
    title = " ".join(w.capitalize() for w in rnd.sample(WORDS, 3)) + f" {i}"
    b = {"id": i, "title": title, "authors": [f"Author {rnd.randrange(n_auth):04d}"],
         "primaryFileType": t, "primaryFileName": f"{i}.{t.lower()}", "fileSizeKb": 400 + i % 900,
         "primaryFileId": 100000 + i, "libraryId": 1 + i % 3, "readProgress": None,
         "thumbnailUrl": f"/api/v1/media/book/{i}/thumbnail", "readStatus": "UNREAD",
         "addedOn": "2026-01-01T10:00:00Z", "coverUpdatedOn": "2026-01-01T10:00:00Z",
         "publisher": "Big House Publishing", "categories": ["Fiction", "Mystery", "Classics"],
         "tags": ["imported", "calibre"], "language": "en", "isbn13": "978%010d" % i,
         "publishedDate": "1999-05-01", "pageCount": 320, "metadataMatchScore": 87.5,
         "goodreadsRating": 3.9, "goodreadsReviewCount": 12000, "amazonRating": 4.2,
         "amazonReviewCount": 3000, "isPhysical": False}
    if i % 3 == 0:
        b["seriesName"], b["seriesNumber"] = f"Series {rnd.randrange(n_series):04d}", float(i % 9 + 1)
    m.BOOKS.append(b)
m.BOOKS.sort(key=lambda b: b["title"].lower())
m.LIBRARIES[:] = [{"id": k, "name": f"Library {k}", "bookCount": sum(1 for b in m.BOOKS if b["libraryId"] == k)}
                  for k in (1, 2, 3)]
m.SUBTITLES.clear()

_covers = {}


def cover(i):
    k = i % 40
    if k not in _covers:
        from PIL import Image, ImageDraw
        img = Image.new("RGB", (250, 350), (40 + k * 5, 90, 160 - k * 3))
        d = ImageDraw.Draw(img)
        for y in range(0, 350, 14):
            d.line([(0, y), (250, (y * 7 + k * 13) % 350)], fill=(200, 180 - k, 90 + k), width=3)
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=80)
        _covers[k] = buf.getvalue()
    return _covers[k]


orig_get = m.H.do_GET


def do_GET(self):
    u = urlparse(self.path)
    parts = u.path.split("/")
    q = parse_qs(u.query)
    if u.path.startswith("/api/v1/media/book/") and u.path.endswith("/thumbnail"):
        if not self._user():
            return self._json(401)
        data = cover(int(parts[5]))
        self.send_response(200); self.send_header("Content-Type", "image/jpeg")
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
        return
    if u.path == "/api/v1/app/books" and q.get("search"):
        # (Grimmory: title, series or an author containing the words, any case)
        ql = q["search"][0].lower().strip()
        types = q.get("fileType", [])
        books = [b for b in m.BOOKS if (not types or b["primaryFileType"] in types)
                 and (ql in b["title"].lower() or ql in b.get("seriesName", "").lower()
                      or any(ql in a.lower() for a in b["authors"]))]
        if q.get("libraryId"):
            books = [b for b in books if b["libraryId"] == int(q["libraryId"][0])]
        if q.get("authors"):
            want = {a.lower() for a in q["authors"]}
            books = [b for b in books if any(a.lower() in want for a in b["authors"])]
        if q.get("series"):
            books = [b for b in books if b.get("seriesName", "").lower() == q["series"][0].lower()]
        page, size = int(q.get("page", ["0"])[0]), min(50, int(q.get("size", ["20"])[0]))
        chunk = books[page * size:(page + 1) * size]
        total_pages = -(-len(books) // size)
        return self._json(200, {"content": chunk, "page": page, "size": size, "totalElements": len(books),
                                "totalPages": total_pages, "hasNext": page + 1 < total_pages, "hasPrevious": page > 0})
    if u.path in ("/api/v1/app/books/continue-reading", "/api/v1/app/books/recently-added"):
        if not self._user():
            return self._json(401)
        return self._json(200, m.BOOKS[:20])
    return orig_get(self)


m.H.do_GET = do_GET
srv = ThreadingHTTPServer(("127.0.0.1", port), m.H)
print("big Grimmory on", port, "with", N, "books", flush=True)
srv.serve_forever()
