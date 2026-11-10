#!/usr/bin/env python3
"""A stand-in for plex.tv and a Plex Media Server with music, for the tests.

  mock_plex.py <port>

plex.tv:   POST /api/v2/pins, GET /api/v2/pins/<id> (signed in once
           /ctl/claim?id=<id> was called, or after 2 checks with auto=1),
           GET /api/v2/user, GET /api/v2/resources
the server (same port): /identity, /library/sections, …/all, /library/metadata/<k>/children,
           /playlists, /playlists/<k>/items, /hubs/search, part downloads,
           /music/:/transcode/universal/start.m3u8 (HLS, MP3 in MPEG-TS), /photo/:/transcode
Tokens: account "plex-token", server "srv-token" (X-Plex-Token header only:
a token in the address is refused, so it's never in one).
The audio is tests/media (3-second tones).
"""
import json
import time, os, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(sys.argv[1])
MEDIA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "media")
def media(name):
    with open(os.path.join(MEDIA, name), "rb") as f:
        return f.read()
MP3, M4A, TS = media("tone.mp3"), media("tone.m4a"), media("tone.ts")
STATE = {"pins": {}, "next_pin": 1000, "log": [], "auto": False, "claimed": set(), "slow": 0, "progress": {}}

def track(k, title, idx, album_key, album, container, codec, kbps):
    return {"ratingKey": str(k), "type": "track", "title": title, "index": idx, "duration": 3000,
            "parentRatingKey": str(album_key), "parentTitle": album, "grandparentTitle": "The Tones",
            "Media": [{"container": container, "audioCodec": codec, "bitrate": kbps,
                       "Part": [{"key": f"/library/parts/{k}/1/file.{container}", "container": container, "size": 12000}]}]}

ALBUMS = {
    "201": {"ratingKey": "201", "type": "album", "title": "MP3 Album", "parentTitle": "The Tones", "year": 2020, "thumb": "/library/metadata/201/thumb/1",
            "addedAt": 1700000100, "lastViewedAt": 1700500000,
            "tracks": [track(301, "Tone A", 1, 201, "MP3 Album", "mp3", "mp3", 320), track(302, "Tone B", 2, 201, "MP3 Album", "mp3", "mp3", 200)]},
    "202": {"ratingKey": "202", "type": "album", "title": "AAC Album", "parentTitle": "The Tones", "year": 2021, "addedAt": 1700000300,
            "tracks": [track(303, "Tone C", 1, 202, "AAC Album", "mp4", "aac", 160)]},
    "203": {"ratingKey": "203", "type": "album", "title": "FLAC Album", "parentTitle": "The Tones", "year": 2022, "addedAt": 1700000200,
            "lastViewedAt": 1700600000,
            "tracks": [track(304, "Tone D", 1, 203, "FLAC Album", "flac", "flac", 900)]},
}
ARTIST = {"ratingKey": "101", "type": "artist", "title": "The Tones"}
# a second music library (key 4): one album, its own artist
LIVE = {"ratingKey": "205", "type": "album", "title": "Live Album", "parentTitle": "The Band", "year": 2019, "addedAt": 1700000400, "leafCount": 1}
LIVE_ARTIST = {"ratingKey": "105", "type": "artist", "title": "The Band"}
TRACKS = {t["ratingKey"]: t for a in ALBUMS.values() for t in a["tracks"]}

# an audiobook library (key 5, a music library as Plex keeps audiobooks): an
# album per book, its author as the artist
AB_AUTHOR = {"ratingKey": "106", "type": "artist", "title": "Narr Author"}
def abtrack(k, title, idx, album_key, album, container, codec):
    t = track(k, title, idx, album_key, album, container, codec, 128)
    t["grandparentTitle"] = "Narr Author"
    return t
AUDIOBOOKS = {
    "206": {"ratingKey": "206", "type": "album", "title": "Two Part Book", "parentTitle": "Narr Author", "year": 2018,
            "summary": "<p>A book in two parts.</p>", "thumb": "/library/metadata/206/thumb/1", "addedAt": 1700000500,
            "tracks": [abtrack(306, "Part 1", 1, 206, "Two Part Book", "mp3", "mp3"), abtrack(307, "Part 2", 2, 206, "Two Part Book", "mp3", "mp3")]},
    "207": {"ratingKey": "207", "type": "album", "title": "One File Book", "parentTitle": "Narr Author", "year": 2017, "addedAt": 1700000450,
            "tracks": [abtrack(308, "One File Book", 1, 207, "One File Book", "mp4", "aac")]},
}
TRACKS.update({t["ratingKey"]: t for a in AUDIOBOOKS.values() for t in a["tracks"]})
CHAPTERS = {"308": [{"tag": "Opening", "startTimeOffset": 0, "endTimeOffset": 1500}, {"tag": "Closing", "startTimeOffset": 1500, "endTimeOffset": 3000}]}

def with_progress(t):
    pr = STATE["progress"].get(t["ratingKey"])
    if not pr: return t
    t = dict(t, lastViewedAt=pr["at"])
    if pr.get("done"): t["viewCount"] = 1
    else: t["viewOffset"] = pr["offset"]
    return t

def album_meta(a):
    return {k: v for k, v in a.items() if k != "tracks"} | {"leafCount": len(a["tracks"])}

ALLOW_HEADERS = None


class H(BaseHTTPRequestHandler):

    # (the sync page, docs/sync, asks from a browser: cross-origin, like the real server)
    def end_headers(self):
        o = self.headers.get("Origin")
        if o:
            self.send_header("Access-Control-Allow-Origin", o)
            self.send_header("Access-Control-Allow-Credentials", "true")
            self.send_header("Access-Control-Expose-Headers", "Content-Disposition, Accept-Ranges, Content-Range, Content-Length")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Methods", "GET, HEAD, POST, PUT, DELETE, OPTIONS, PATCH, REPORT, PROPFIND")
        self.send_header("Access-Control-Allow-Headers", ALLOW_HEADERS or (self.headers.get("Access-Control-Request-Headers") or ""))
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *a): pass

    def send(self, code, body=b"", ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def mc(self, items, total=None):
        return self.send(200, {"MediaContainer": {"size": len(items), "totalSize": total if total is not None else len(items), "Metadata": items}})

    def token(self):
        return self.headers.get("X-Plex-Token")

    def route(self, method):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        p = u.path
        STATE["log"].append([method, p, bool(self.token())])
        if "X-Plex-Token" in q or "token" in u.query.lower():
            return self.send(400, {"error": "token in the address"})
        if p == "/ctl/claim":
            STATE["claimed"].add(q["id"][0]); return self.send(200, {})
        if p == "/ctl/auto":
            STATE["auto"] = True; return self.send(200, {})
        if p == "/ctl/slow":   # seconds each track file takes (a download to stop)
            STATE["slow"] = float(q["s"][0]); return self.send(200, {})
        if p == "/ctl/transcodes":
            return self.send(200, STATE.get("transcodes", []))
        if p == "/ctl/log":
            return self.send(200, STATE["log"])
        if p == "/ctl/progress":   # what /:/progress was told; ?key=&offset=&at=[&done=1]: another player's
            if "key" in q:
                STATE["progress"][q["key"][0]] = {"offset": int(q.get("offset", ["0"])[0]), "at": int(q["at"][0]), "done": "done" in q}
            return self.send(200, STATE["progress"])
        # plex.tv
        if p == "/api/v2/pins" and method == "POST":
            STATE["next_pin"] += 1
            pid = str(STATE["next_pin"])
            strong = q.get("strong") == ["true"]
            code = ("strongcode" + pid) if strong else "AB" + pid[-2:]
            STATE["pins"][pid] = {"code": code, "checks": 0}
            return self.send(201, {"id": int(pid), "code": code, "expiresIn": 900, "authToken": None})
        if p.startswith("/api/v2/pins/"):
            pid = p.rsplit("/", 1)[1]
            pin = STATE["pins"].get(pid)
            if not pin or q.get("code") != [pin["code"]]:
                return self.send(404, {"error": "no pin"})
            pin["checks"] += 1
            done = pid in STATE["claimed"] or (STATE["auto"] and pin["checks"] >= 2)
            return self.send(200, {"id": int(pid), "code": pin["code"], "authToken": "plex-token" if done else None})
        if p == "/api/v2/user":
            if self.token() != "plex-token": return self.send(401, {})
            return self.send(200, {"username": "will", "title": "Will", "email": "secret@example.com"})
        if p == "/api/v2/resources":
            if self.token() != "plex-token": return self.send(401, {})
            return self.send(200, [
                {"name": "Somebody's", "provides": "server", "clientIdentifier": "srv2", "accessToken": "srv-token", "owned": False,
                 "connections": [{"protocol": "https", "address": "10.255.255.1", "port": 32400, "uri": "https://10-255-255-1.x.plex.direct:9", "local": False}]},
                {"name": "Home Server", "provides": "server,client", "clientIdentifier": "srv1", "accessToken": "srv-token", "owned": True,
                 "connections": [{"protocol": "https", "address": "127.0.0.1", "port": 9, "uri": "https://127-0-0-1.x.plex.direct:9", "local": True},
                                 {"protocol": "http", "address": "127.0.0.1", "port": PORT, "uri": f"http://127.0.0.1:{PORT}", "local": True}]},
                {"name": "A player", "provides": "player", "clientIdentifier": "p1", "connections": []},
            ])
        # the server
        if self.token() != "srv-token":
            return self.send(401, {})
        if p == "/identity":
            return self.send(200, {"MediaContainer": {"machineIdentifier": "srv1"}})
        if p == "/library/sections":
            return self.send(200, {"MediaContainer": {"Directory": [{"key": "1", "type": "artist", "title": "Music"}, {"key": "2", "type": "movie", "title": "Films"},
                                                                 {"key": "4", "type": "artist", "title": "Concerts"},
                                                                 {"key": "5", "type": "artist", "title": "Audiobooks"}]}})
        if p == "/library/sections/5/all":
            start = int(self.headers.get("X-Plex-Container-Start", "0"))
            size = int(self.headers.get("X-Plex-Container-Size", "50"))
            items = [album_meta(a) for a in AUDIOBOOKS.values()] if q.get("type") == ["9"] else [AB_AUTHOR]
            items.sort(key=lambda m: m["title"])
            if q.get("sort") == ["addedAt:desc"]: items.sort(key=lambda m: -(m.get("addedAt") or 0))
            return self.mc(items[start:start + size], len(items))
        if p == "/library/sections/4/all":
            return self.mc([LIVE] if q.get("type") == ["9"] else [LIVE_ARTIST])
        if p == "/library/sections/1/all":
            start = int(self.headers.get("X-Plex-Container-Start", "0"))
            size = int(self.headers.get("X-Plex-Container-Size", "50"))
            items = [album_meta(a) for a in ALBUMS.values()] if q.get("type") == ["9"] else [ARTIST]
            # (Plex's sort: addedAt:desc for Recently added, lastViewedAt:desc for Recently played, never played last)
            for field in ("addedAt", "lastViewedAt"):
                if q.get("sort") == [field + ":desc"]:
                    items.sort(key=lambda m: -(m.get(field) or 0))
            return self.mc(items[start:start + size], len(items))
        if p.startswith("/library/metadata/") and p.endswith("/children"):
            k = p.split("/")[3]
            if k == "101": return self.mc([album_meta(a) for a in ALBUMS.values()])
            if k in ALBUMS: return self.mc(ALBUMS[k]["tracks"])
            if k == "106": return self.mc([album_meta(a) for a in AUDIOBOOKS.values()])
            if k in AUDIOBOOKS: return self.mc([with_progress(t) for t in AUDIOBOOKS[k]["tracks"]])
            return self.send(404, {})
        if p.startswith("/library/metadata/") and p.count("/") == 3:
            k = p.split("/")[3]
            if k in AUDIOBOOKS: return self.mc([album_meta(AUDIOBOOKS[k])])
            if k in TRACKS:
                t = dict(TRACKS[k])
                if q.get("includeChapters") == ["1"] and k in CHAPTERS: t["Chapter"] = CHAPTERS[k]
                return self.mc([t])
            return self.send(404, {})
        if p == "/:/progress":
            if q.get("identifier") != ["com.plexapp.plugins.library"] or "key" not in q: return self.send(400, {})
            STATE["progress"][q["key"][0]] = {"offset": int(q["time"][0]), "at": int(time.time()), "state": q.get("state", [""])[0]}
            return self.send(200, b"", "text/plain")
        if p == "/playlists":
            # (sectionID: the playlists with that library's music; Mix is library 1's)
            if q.get("sectionID", ["1"]) != ["1"]: return self.mc([])
            return self.mc([{"ratingKey": "401", "type": "playlist", "title": "Mix", "leafCount": 2}])
        if p == "/playlists/401/items":
            return self.mc([TRACKS["302"], TRACKS["303"]])
        if p == "/hubs/search":
            ql = q.get("query", [""])[0].lower()
            if q.get("sectionId", ["1"]) == ["5"]:
                return self.send(200, {"MediaContainer": {"Hub": [{"type": "album", "Metadata": [album_meta(a) for a in AUDIOBOOKS.values() if ql in a["title"].lower()]}]}})
            if q.get("sectionId", ["1"]) == ["4"]:
                return self.send(200, {"MediaContainer": {"Hub": [{"type": "album", "Metadata": [LIVE] if ql in LIVE["title"].lower() else []}]}})
            hubs = [{"type": "artist", "Metadata": [ARTIST] if ql in "the tones" else []},
                    {"type": "album", "Metadata": [album_meta(a) for a in ALBUMS.values() if ql in a["title"].lower()]},
                    {"type": "track", "Metadata": [t for t in TRACKS.values() if ql in t["title"].lower()]}]
            return self.send(200, {"MediaContainer": {"Hub": hubs}})
        if p.startswith("/library/parts/"):
            k = p.split("/")[3]
            t = TRACKS.get(k)
            if not t: return self.send(404, {})
            c = t["Media"][0]["container"]
            if c == "flac": return self.send(200, b"fLaC-not-for-the-kindle", "audio/flac")
            if STATE["slow"]: time.sleep(STATE["slow"])
            return self.send(200, MP3 if c == "mp3" else M4A, "audio/mpeg" if c == "mp3" else "audio/mp4")
        if p == "/music/:/transcode/universal/start.m3u8":
            path = q.get("path", [""])[0]
            if q.get("protocol") != ["hls"] or not path.startswith("/library/metadata/"):
                return self.send(400, {})
            # as a real server: no client profile for a platform it doesn't know -> 400
            platform = q.get("X-Plex-Platform", [self.headers.get("X-Plex-Platform", "")])[0]
            STATE["platforms"] = STATE.get("platforms", []) + [platform]
            if platform not in ("Chrome", "Safari", "Firefox"):
                return self.send(400, "<html><head><title>Bad Request</title></head></html>", "text/html")
            STATE["transcoded"] = path
            STATE["transcodes"] = STATE.get("transcodes", []) + [[path, q.get("musicBitrate", [""])[0]]]
            return self.send(200, "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=192000\nsession/abc/base/index.m3u8\n", "application/vnd.apple.mpegurl")
        if p == "/music/:/transcode/universal/session/abc/base/index.m3u8":
            return self.send(200, "#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:1.5,\n00000.ts\n#EXTINF:1.5,\n00001.ts\n#EXT-X-ENDLIST\n", "application/vnd.apple.mpegurl")
        if p.startswith("/music/:/transcode/universal/session/abc/base/0000"):
            n = int(p[-4])
            half = (len(TS) // 188 // 2) * 188
            return self.send(200, TS[:half] if n == 0 else TS[half:], "video/mp2t")
        if p == "/music/:/transcode/universal/stop":
            return self.send(200, {})
        if p == "/photo/:/transcode":
            return self.send(200, b"\xff\xd8\xff\xe0fakejpeg\xff\xd9", "image/jpeg")
        return self.send(404, {"error": p})

    def do_GET(self): self.route("GET")
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n: self.rfile.read(n)
        self.route("POST")

ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
