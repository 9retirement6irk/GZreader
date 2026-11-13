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
                                   the states it changed
Sign-in: "Authorization: Bearer <token>" (TOKEN below).

  python3 -I mock_homeassistant.py PORT [--no-admin]

The house is the mockup's: a living room, a kitchen, outside, a switch in no
room and three scenes. Test helpers: GET /__state (states and the request
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
                                    "sensor.living_room_temperature", "sensor.living_room_power"]),
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
           hvac_action="heating", min_temp=7, max_temp=35, target_temp_step=0.5),
        st("sensor.living_room_temperature", "20.5", friendly_name="Living room Temperature",
           device_class="temperature", unit_of_measurement="°C"),
        st("sensor.living_room_power", "120", friendly_name="Living room Power", device_class="power",
           unit_of_measurement="W"),
        st("light.under_cabinet", "off", friendly_name="Kitchen Under-cabinet lights",
           supported_color_modes=["brightness"]),
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

C = {"light", "switch", "fan", "input_boolean", "climate", "lock", "cover", "script"}
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
    modes = [m for m in (a.get("supported_color_modes") or []) if m not in ("onoff", "unknown")]
    return {"i": s["entity_id"], "s": s["state"], "n": a.get("friendly_name", s["entity_id"]),
            "b": a.get("brightness"), "d": len(modes) > 0, "u": a.get("unit_of_measurement"),
            "c": a.get("device_class"), "t": a.get("current_temperature"), "g": a.get("temperature"),
            "a": a.get("hvac_action"), "lo": a.get("min_temp"), "hi": a.get("max_temp"),
            "st": a.get("target_temp_step"), "p": a.get("current_position")}


def render_house():
    rooms = []
    for aid, name, ids in AREAS:
        rooms.append({"id": aid, "name": name, "e": [obj(by_id(i)) for i in ids if by_id(i) and shown(by_id(i))]})
    other = [obj(s) for s in STATE["states"]
             if s["entity_id"].split(".")[0] in C - {"script"} and not area_of(s["entity_id"])]
    scenes = [obj(s) for s in STATE["states"] if s["entity_id"].startswith("scene.")]
    return json.dumps({"v": 1, "rooms": rooms, "other": other, "scenes": scenes}, ensure_ascii=False)


def call(domain, service, data):
    """Run a service; the states it changed, or None (unknown service)."""
    ids = data.get("entity_id")
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
        elif domain == "climate" and service == "set_temperature":
            a["temperature"] = data.get("temperature")
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
