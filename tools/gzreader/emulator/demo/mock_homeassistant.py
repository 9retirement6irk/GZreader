"""A small Home Assistant for the House tab's tests and the emulator.

Mirrors the parts of Home Assistant's REST API GZreader uses:
  GET   /api/                      {"message": "API running."}
  GET   /api/config                location_name, version, unit_system
  GET   /api/states                every state
  POST  /api/template              {template}: GZreader's House template only
                                   (marked gzreader-house-v1), answered from
                                   the states below as Home Assistant would
                                   render it; 401 with --no-admin (a token
                                   that isn't an administrator's)
  POST  /api/services/<d>/<s>      {entity_id, brightness_pct, temperature}:
                                   the states it changed; a media player's
                                   answer has none (as Home Assistant's: the
                                   player changes afterwards)
  POST  /api/services/music_assistant/get_library?return_response
  POST  /api/services/music_assistant/search?return_response
                                   {"changed_states": [], "service_response":
                                   {…}} from LIBRARY below
Sign-in: "Authorization: Bearer <token>" (TOKEN below).

  python3 -I mock_homeassistant.py PORT [--no-admin]

The house is the mockup's: a living room (with a Music Assistant speaker and
a TV), a kitchen, outside, a switch in no room and three scenes. Test helpers: GET /__state (states and the request
log), POST /__reset, POST /__offline?on=1, POST /__set?id=<entity>&state=<s>.
"""
import copy, json, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

TOKEN = "ha-test-token"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 0
NO_ADMIN = "--no-admin" in sys.argv
LOCK = threading.Lock()

AREAS = [
    ("living_room", "Living room", ["light.living_room_ceiling", "light.floor_lamp", "climate.thermostat",
                                    "sensor.living_room_temperature", "sensor.living_room_power",
                                    "media_player.living_room_speaker", "media_player.living_room_tv"]),
    ("kitchen", "Kitchen", ["light.under_cabinet", "switch.kettle"]),
    ("outside", "Outside", ["light.porch", "lock.front_door", "cover.garage_door", "binary_sensor.back_door"]),
    ("attic", "Attic", []),
]


def initial():
    def st(eid, state, **attrs):
        return {"entity_id": eid, "state": state, "attributes": attrs,
                "last_changed": "2026-11-12T10:00:00+00:00", "last_updated": "2026-11-12T10:00:00+00:00"}
    return [
        st("light.living_room_ceiling", "on", friendly_name="Living room Ceiling light", brightness=204,
           supported_color_modes=["brightness"]),
        st("light.floor_lamp", "off", friendly_name="Floor lamp", supported_color_modes=["onoff"]),
        st("climate.thermostat", "heat", friendly_name="Thermostat", current_temperature=20.5, temperature=21,
           hvac_action="heating", min_temp=7, max_temp=35, target_temp_step=0.5, hvac_modes=["off", "heat", "cool", "dry"]),
        st("sensor.living_room_temperature", "20.5", friendly_name="Living room Temperature",
           device_class="temperature", unit_of_measurement="°C"),
        st("sensor.living_room_power", "120", friendly_name="Living room Power", device_class="power",
           unit_of_measurement="W"),
        st("media_player.living_room_speaker", "paused", friendly_name="Living room Speaker", device_class="speaker",
           volume_level=0.3, is_volume_muted=False, shuffle=False, repeat="off", media_title="Blue in Green",
           media_artist="Example Quartet", app_id="music_assistant", supported_features=8322623),
        st("media_player.living_room_tv", "off", friendly_name="TV", device_class="tv", supported_features=384),
        st("light.under_cabinet", "off", friendly_name="Kitchen Under-cabinet lights",
           supported_color_modes=["hs", "color_temp"]),
        st("switch.kettle", "off", friendly_name="Kettle"),
        st("light.porch", "on", friendly_name="Porch light", supported_color_modes=["onoff"]),
        st("lock.front_door", "locked", friendly_name="Front door"),
        st("cover.garage_door", "closed", friendly_name="Garage door", device_class="garage", current_position=0),
        st("binary_sensor.back_door", "off", friendly_name="Back door", device_class="door"),
        st("switch.coffee_maker", "off", friendly_name="Coffee maker"),
        st("automation.morning", "on", friendly_name="Morning"),
        st("scene.goodnight", "2026-11-11T22:00:00+00:00", friendly_name="Goodnight"),
        st("scene.leaving", "unknown", friendly_name="Leaving"),
        st("scene.movie", "unknown", friendly_name="Movie"),
    ]


STATE = {"states": initial(), "log": [], "offline": False}

C = {"light", "switch", "fan", "input_boolean", "climate", "lock", "cover", "script", "media_player"}
MA_ENTRY = "ma-entry-1"
LIBRARY = {
    "playlist": [{"name": "Evening", "uri": "library://playlist/1", "media_type": "playlist", "owner": "Home"},
                 {"name": "Morning", "uri": "library://playlist/2", "media_type": "playlist", "owner": "Home"}],
    "album": [{"name": "Kind of Example", "uri": "library://album/7", "media_type": "album", "version": "Remastered",
               "artists": [{"name": "Example Quartet"}]}],
    "artist": [{"name": "Example Quartet", "uri": "library://artist/3", "media_type": "artist"}],
    "radio": [],
    "track": [{"name": "Blue in Green", "uri": "library://track/9", "media_type": "track",
               "artists": [{"name": "Example Quartet"}]}],
}
NAMES = {i["uri"]: i for items in LIBRARY.values() for i in items}
SC = {"temperature", "humidity"}
BC = {"door", "window", "garage_door", "opening", "lock"}


def by_id(eid):
    for s in STATE["states"]:
        if s["entity_id"] == eid:
            return s
    return None


def area_of(eid):
    for aid, _name, ids in AREAS:
        if eid in ids:
            return aid
    return None


def shown(s):
    d = s["entity_id"].split(".")[0]
    dc = s["attributes"].get("device_class")
    return d in C or (d == "sensor" and dc in SC) or (d == "binary_sensor" and dc in BC)


def obj(s):
    """One device as the House template renders it."""
    a = s["attributes"]
    if s["entity_id"].startswith("media_player."):
        return {"i": s["entity_id"], "s": s["state"], "n": a.get("friendly_name", s["entity_id"]),
                "c": a.get("device_class"), "v": a.get("volume_level"), "mu": a.get("is_volume_muted"),
                "sh": a.get("shuffle"), "rp": a.get("repeat"), "mt": a.get("media_title"),
                "ar": a.get("media_artist"), "sf": a.get("supported_features"), "ap": a.get("app_id"),
                "ce": MA_ENTRY if a.get("app_id") == "music_assistant" else None}
    modes = [m for m in (a.get("supported_color_modes") or []) if m not in ("onoff", "unknown")]
    return {"i": s["entity_id"], "s": s["state"], "n": a.get("friendly_name", s["entity_id"]),
            "b": a.get("brightness"), "d": len(modes) > 0, "u": a.get("unit_of_measurement"),
            "c": a.get("device_class"), "t": a.get("current_temperature"), "g": a.get("temperature"),
            "a": a.get("hvac_action"), "lo": a.get("min_temp"), "hi": a.get("max_temp"),
            "st": a.get("target_temp_step"), "p": a.get("current_position"),
            "rgb": a.get("rgb_color"), "hm": a.get("hvac_modes"),
            "cm": any(m in ("hs", "rgb", "rgbw", "rgbww", "xy") for m in (a.get("supported_color_modes") or []))}


def render_house():
    rooms = []
    for aid, name, ids in AREAS:
        rooms.append({"id": aid, "name": name, "e": [obj(by_id(i)) for i in ids if by_id(i) and shown(by_id(i))]})
    other = [obj(s) for s in STATE["states"]
             if s["entity_id"].split(".")[0] in C - {"script"} and not area_of(s["entity_id"])]
    scenes = [obj(s) for s in STATE["states"] if s["entity_id"].startswith("scene.")]
    return json.dumps({"v": 1, "rooms": rooms, "other": other, "scenes": scenes}, ensure_ascii=False)


def media(s, service, data):
    """A media player's service; False when it isn't one."""
    a = s["attributes"]
    if service == "media_play":
        s["state"] = "playing"
    elif service == "media_pause":
        s["state"] = "paused"
    elif service == "volume_set":
        a["volume_level"] = float(data["volume_level"])
    elif service == "volume_mute":
        a["is_volume_muted"] = bool(data["is_volume_muted"])
    elif service == "shuffle_set":
        a["shuffle"] = bool(data["shuffle"])
    elif service == "repeat_set" and data.get("repeat") in ("off", "all", "one"):
        a["repeat"] = data["repeat"]
    elif service in ("media_next_track", "media_previous_track"):
        a["media_title"] = "Next song" if service == "media_next_track" else "Song before"
    elif service == "turn_on":
        s["state"] = "on"
    elif service == "turn_off":
        s["state"] = "off"
    else:
        return False
    return True


def call(domain, service, data):
    """Run a service; the states it changed, or None (unknown service)."""
    ids = data.get("entity_id")
    if domain == "music_assistant" and service == "play_media":
        s = by_id(ids)
        item = NAMES.get(data.get("media_id"))
        if not s or not item or s["attributes"].get("app_id") != "music_assistant" or data.get("enqueue") != "replace":
            return None
        s["state"] = "playing"
        s["attributes"]["media_title"] = item["name"]
        s["attributes"]["media_content_id"] = item["uri"]
        return []
    if domain == "media_player":
        s = by_id(ids)
        return [] if s and ids.startswith("media_player.") and media(s, service, data) else None
    ids = ids if isinstance(ids, list) else [ids]
    changed = []
    for eid in ids:
        s = by_id(eid)
        if not s or not eid.startswith(domain + "."):
            return None
        a = s["attributes"]
        if service == "turn_on" and domain == "scene":
            # Goodnight: every light off
            if eid == "scene.goodnight":
                for l in STATE["states"]:
                    if l["entity_id"].startswith("light.") and l["state"] == "on":
                        l["state"] = "off"
                        l["attributes"].pop("brightness", None)
                        changed.append(l)
            s["state"] = "2026-11-12T22:00:00+00:00"
            changed.append(s)
            continue
        if service == "turn_on" and domain == "script":
            changed.append(s)
            continue
        if service in ("turn_on", "turn_off", "toggle") and domain in ("light", "switch", "fan", "input_boolean"):
            on = {"turn_on": True, "turn_off": False, "toggle": s["state"] != "on"}[service]
            s["state"] = "on" if on else "off"
            if domain == "light":
                if on and "brightness_pct" in data and "onoff" not in a.get("supported_color_modes", []):
                    a["brightness"] = round(int(data["brightness_pct"]) * 255 / 100)
                elif on and "onoff" not in a.get("supported_color_modes", []):
                    a.setdefault("brightness", 255)
                elif not on:
                    a.pop("brightness", None)
                if on and "rgb_color" in data:
                    a["rgb_color"] = [int(x) for x in data["rgb_color"]]
                elif on and any(m in ("hs", "rgb", "xy") for m in a.get("supported_color_modes", [])):
                    a.setdefault("rgb_color", [255, 180, 107])
                elif not on:
                    a.pop("rgb_color", None)
        elif domain == "climate" and service == "set_temperature":
            a["temperature"] = data.get("temperature")
        elif domain == "climate" and service == "set_hvac_mode" and data.get("hvac_mode") in a.get("hvac_modes", []):
            s["state"] = data["hvac_mode"]
            a["hvac_action"] = {"heat": "heating", "cool": "cooling", "off": "off"}.get(data["hvac_mode"], "idle")
        elif domain == "lock" and service in ("lock", "unlock"):
            s["state"] = "locked" if service == "lock" else "unlocked"
        elif domain == "cover" and service in ("open_cover", "close_cover"):
            s["state"] = "open" if service == "open_cover" else "closed"
            a["current_position"] = 100 if service == "open_cover" else 0
        else:
            return None
        changed.append(s)
    return changed


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="application/json"):
        data = body.encode() if isinstance(body, str) else json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw) if raw else {}
        except ValueError:
            return None

    def handle_all(self, method):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        with LOCK:
            if u.path == "/__state":
                return self.send(200, {"states": STATE["states"], "log": STATE["log"]})
            if u.path == "/__reset":
                STATE.update({"states": initial(), "log": [], "offline": False})
                return self.send(200, {"ok": True})
            if u.path == "/__offline":
                STATE["offline"] = q.get("on", ["0"])[0] == "1"
                return self.send(200, {"ok": True})
            if u.path == "/__set":
                s = by_id(q.get("id", [""])[0])
                if s:
                    s["state"] = q.get("state", [s["state"]])[0]
                return self.send(200, {"ok": s is not None})
            if STATE["offline"]:
                self.close_connection = True
                return
            STATE["log"].append(method + " " + self.path)
            if self.headers.get("Authorization") != "Bearer " + TOKEN:
                return self.send(401, "401: Unauthorized", "text/plain")
            if method == "GET" and u.path == "/api/":
                return self.send(200, {"message": "API running."})
            if method == "GET" and u.path == "/api/config":
                return self.send(200, {"location_name": "Home", "version": "2026.11.1",
                                       "unit_system": {"temperature": "°C", "length": "km"}})
            if method == "GET" and u.path == "/api/states":
                return self.send(200, STATE["states"])
            if method == "POST" and u.path == "/api/template":
                data = self.body()
                if NO_ADMIN:
                    return self.send(401, "401: Unauthorized", "text/plain")
                if not isinstance(data, dict) or "gzreader-house-v1" not in str(data.get("template")):
                    return self.send(400, {"message": "Error rendering template: not GZreader's"})
                return self.send(200, render_house(), "text/plain; charset=utf-8")
            if method == "POST" and u.path.startswith("/api/services/"):
                parts = u.path.split("/")
                data = self.body()
                if len(parts) != 5 or not isinstance(data, dict):
                    return self.send(400, {"message": "Data should be valid JSON."})
                if parts[3] == "music_assistant" and parts[4] in ("get_library", "search"):
                    if "return_response" not in q and "return_response" not in u.query:
                        return self.send(400, {"message": "Service call requires responses but caller did not ask for responses."})
                    if data.get("config_entry_id") != MA_ENTRY:
                        return self.send(400, {"message": "Config entry not found."})
                    if parts[4] == "get_library":
                        items = LIBRARY.get(data.get("media_type"))
                        if items is None or data.get("order_by") != "sort_name":
                            return self.send(400, {"message": "Invalid media type."})
                        off, lim = int(data.get("offset", 0)), int(data.get("limit", 25))
                        res = {"items": items[off:off + lim], "limit": lim, "offset": off, "media_type": data["media_type"]}
                    else:
                        want = str(data.get("name", "")).lower()
                        res = {k + "s" if k != "radio" else k: [i for i in v if want in i["name"].lower()][:int(data.get("limit", 5))]
                               for k, v in LIBRARY.items()}
                    return self.send(200, {"changed_states": [], "service_response": res})
                changed = call(parts[3], parts[4], data)
                if changed is None:
                    return self.send(400, {"message": "Service not found."})
                return self.send(200, copy.deepcopy(changed))
            return self.send(404, {"message": "Not found"})

    def do_GET(self):
        self.handle_all("GET")

    def do_POST(self):
        self.handle_all("POST")


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    print("mock Home Assistant on", srv.server_address[1], flush=True)
    srv.serve_forever()
