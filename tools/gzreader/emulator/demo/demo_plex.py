#!/usr/bin/env python3
"""A Plex stand-in with a demo music library, for screenshots.

  demo_plex.py <mock_plex.py> <library dir from make_library.py> <port>

Reuses the test suite's mock (plex.tv's PINs, the server's tokens, the
transcoder) and replaces its music with the made-up albums in the library's
audio.json: their covers (plex-<key>.jpg) through /photo/:/transcode, each
track the test suite's tone. Sign in as the tests do: start the sign-in on
the Kindle, then /ctl/claim?id=<newest PIN from /ctl/log>, or /ctl/auto.
"""
import json, os, sys
from urllib.parse import urlparse, parse_qs

mock_path, LIB, port = sys.argv[1], sys.argv[2], sys.argv[3]
sys.argv = [mock_path, port]
src = open(mock_path).read()
# (everything but the last line, which starts serving)
body, last = src.rstrip().rsplit("\n", 1)
assert last.startswith("ThreadingHTTPServer("), last
g = {"__name__": "mock_plex", "__file__": mock_path}
exec(compile(body, mock_path, "exec"), g)

audio = json.load(open(os.path.join(LIB, "audio.json")))
ARTISTS, ALBUMS, TRACKS = {}, {}, {}
for n, a in enumerate(audio["albums"]):
    art = ARTISTS.setdefault(a["artist"], {"ratingKey": str(600 + len(ARTISTS)), "type": "artist", "title": a["artist"],
                                           "thumb": "/library/metadata/%s/thumb/1" % a["key"]})
    tracks = []
    for i, t in enumerate(a["tracks"], 1):
        k = "%s%02d" % (a["key"], i)
        tracks.append({"ratingKey": k, "type": "track", "title": t, "index": i, "duration": 180000 + 17000 * i,
                       "parentRatingKey": a["key"], "parentTitle": a["title"], "grandparentTitle": a["artist"],
                       "parentThumb": "/library/metadata/%s/thumb/1" % a["key"],
                       "Media": [{"container": "mp3", "audioCodec": "mp3", "bitrate": 192,
                                  "Part": [{"key": "/library/parts/%s/1/file.mp3" % k, "container": "mp3", "size": 12000}]}]})
        TRACKS[k] = tracks[-1]
    ALBUMS[a["key"]] = {"ratingKey": a["key"], "type": "album", "title": a["title"], "parentTitle": a["artist"],
                        "parentRatingKey": art["ratingKey"], "year": a["year"],
                        "thumb": "/library/metadata/%s/thumb/1" % a["key"], "leafCount": len(tracks),
                        # (newest first for Recently added; the first four played lately)
                        "addedAt": 1760000000 + 1000 * (len(audio["albums"]) - n),
                        "lastViewedAt": 1761000000 - 1000 * n if n < 4 else None, "tracks": tracks}
PLAYLISTS = {"701": ("Reading music", ["50301", "50601", "50202", "50701"]),
             "702": ("Evening", ["50101", "50403", "50801", "50502"])}
TONE = g["MP3"]
H = g["H"]
orig_route = H.route


def meta(a):
    return {k: v for k, v in a.items() if k != "tracks" and v is not None}


def route(self, method):
    u = urlparse(self.path)
    q = parse_qs(u.query)
    p = u.path
    if p == "/api/v2/user" and self.token() == "plex-token":
        return self.send(200, {"username": "reader", "title": "Reader", "email": "reader@example.com"})
    if not p.startswith("/library/") and p not in ("/playlists", "/hubs/search", "/photo/:/transcode") and not p.startswith("/playlists/"):
        return orig_route(self, method)
    g["STATE"]["log"].append([method, p, bool(self.token())])
    if self.token() != "srv-token":
        return self.send(401, {})
    if p == "/library/sections":
        return self.send(200, {"MediaContainer": {"Directory": [{"key": "1", "type": "artist", "title": "Music"}]}})
    if p == "/library/sections/1/all":
        start = int(self.headers.get("X-Plex-Container-Start", "0"))
        size = int(self.headers.get("X-Plex-Container-Size", "50"))
        if q.get("type") == ["9"]:
            items = sorted((meta(a) for a in ALBUMS.values()), key=lambda m: m["title"])
            for field in ("addedAt", "lastViewedAt"):
                if q.get("sort") == [field + ":desc"]:
                    items.sort(key=lambda m: -(m.get(field) or 0))
        else:
            items = sorted(ARTISTS.values(), key=lambda m: m["title"])
        return self.mc(items[start:start + size], len(items))
    if p.startswith("/library/metadata/") and p.endswith("/children"):
        k = p.split("/")[3]
        if k in ALBUMS:
            return self.mc(ALBUMS[k]["tracks"])
        for art in ARTISTS.values():
            if art["ratingKey"] == k:
                return self.mc([meta(a) for a in ALBUMS.values() if a["parentTitle"] == art["title"]])
        return self.send(404, {})
    if p.startswith("/library/metadata/") and p.count("/") == 3:
        k = p.split("/")[3]
        if k in ALBUMS: return self.mc([meta(ALBUMS[k])])
        if k in TRACKS: return self.mc([TRACKS[k]])
        return self.send(404, {})
    if p == "/playlists":
        return self.mc([{"ratingKey": k, "type": "playlist", "title": t, "leafCount": len(ks),
                         "composite": "/playlists/%s/composite/1" % k} for k, (t, ks) in PLAYLISTS.items()])
    if p.startswith("/playlists/") and p.endswith("/items"):
        pl = PLAYLISTS.get(p.split("/")[2])
        return self.mc([TRACKS[k] for k in pl[1]]) if pl else self.send(404, {})
    if p == "/hubs/search":
        ql = q.get("query", [""])[0].lower()
        return self.send(200, {"MediaContainer": {"Hub": [
            {"type": "artist", "Metadata": [a for a in ARTISTS.values() if ql in a["title"].lower()]},
            {"type": "album", "Metadata": [meta(a) for a in ALBUMS.values() if ql in a["title"].lower()]},
            {"type": "track", "Metadata": [t for t in TRACKS.values() if ql in t["title"].lower()]}]}})
    if p.startswith("/library/parts/"):
        return self.send(200, TONE, "audio/mpeg")
    if p == "/photo/:/transcode":
        thumb = q.get("url", [""])[0]
        key = thumb.split("/")[3] if thumb.count("/") >= 3 else ""
        if thumb.startswith("/playlists/"):
            key = ALBUMS[TRACKS[PLAYLISTS[key][1][0]]["parentRatingKey"]]["ratingKey"] if key in PLAYLISTS else ""
        f = os.path.join(LIB, "plex-%s.jpg" % key)
        if os.path.exists(f):
            return self.send(200, open(f, "rb").read(), "image/jpeg")
        return self.send(404, {})
    return orig_route(self, method)


H.route = route
print("demo Plex on", port, flush=True)
g["ThreadingHTTPServer"](("127.0.0.1", int(port)), H).serve_forever()
