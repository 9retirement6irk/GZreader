"""A small Mealie for the Recipes tab's tests and the emulator.

Mirrors the parts of Mealie's REST API GZreader uses (checked against
Mealie's source, mealie/routes):
  GET    /api/app/about                    version, enableOidc, … (no sign-in)
  GET    /api/users/self                   who the token is
  GET    /api/recipes                      page, perPage, orderBy, orderDirection,
                                           search, categories (an id or a slug)
  GET    /api/recipes/<slug>               one recipe: ingredients, steps, notes
  GET    /api/organizers/categories        every category
  POST   /api/users/api-tokens             {name}: 201 with the new token
  DELETE /api/users/api-tokens/<id>
Single sign-on for apps (not with --old; enableOidc false with --no-oidc):
  GET    /api/auth/oauth/native/config     authorization_endpoint, client_id, scope
  POST   /api/auth/oauth/native/token      {code, code_verifier, redirect_uri,
                                           nonce}: a session token, if the
                                           verifier fits the challenge
The identity provider is played here too: GET /idp/authorize takes the
request an app sends a browser with and answers {"code", "state"} as JSON
(a real one redirects the browser to redirect_uri with them).

Sign-in: "Authorization: Bearer <token>": TOKEN below (an API token made in
Mealie), a session token from single sign-on, or a token made here.

  python3 -I mock_mealie.py PORT [--no-oidc] [--old]

Test helpers: GET /__state (the request log, the tokens made, sign-ons
started), POST /__reset, POST /__offline?on=1,
POST /__rename?slug=<slug>&name=<name>.
"""
import base64, hashlib, json, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote

TOKEN = "mealie-test-token"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 0
NO_OIDC = "--no-oidc" in sys.argv
OLD = "--old" in sys.argv
LOCK = threading.Lock()

CATEGORIES = [
    {"id": "c0000000-0000-4000-8000-000000000001", "name": "Dinner", "slug": "dinner"},
    {"id": "c0000000-0000-4000-8000-000000000002", "name": "Baking", "slug": "baking"},
    {"id": "c0000000-0000-4000-8000-000000000003", "name": "Breakfast", "slug": "breakfast"},
]
CAT = {c["slug"]: c for c in CATEGORIES}


def unit(name, plural=None, abbr="", use=False):
    return {"id": None, "name": name, "pluralName": plural, "abbreviation": abbr, "useAbbreviation": use}


def food(name, plural=None):
    return {"id": None, "name": name, "pluralName": plural}


def recipe(n, slug, name, cats=(), **more):
    r = {
        "id": "a0000000-0000-4000-8000-%012d" % n, "slug": slug, "name": name, "description": "",
        "recipeServings": 0, "recipeYieldQuantity": 0, "recipeYield": None,
        "totalTime": None, "prepTime": None, "performTime": None, "rating": None, "orgURL": None,
        "recipeCategory": [CAT[c] for c in cats], "tags": [], "tools": [],
        "createdAt": "2026-01-%02dT10:00:00" % (1 + n % 28), "order": n,
        "recipeIngredient": [], "recipeInstructions": [], "notes": [],
    }
    r.update(more)
    return r


def initial():
    recipes = [
        recipe(101, "apple-pie", "Apple pie", ["baking"], description="A **classic** pie with a butter crust.",
               recipeServings=8, totalTime="1 hour 20 minutes", prepTime="30 minutes", performTime="50 minutes", rating=5,
               orgURL="https://recipes.example.com/apple-pie",
               recipeIngredient=[
                   {"title": "Crust", "quantity": 2.5, "unit": unit("cup", "cups"), "food": food("flour"), "note": "sifted",
                    "display": "2 ½ cups flour, sifted"},
                   {"quantity": 1, "unit": unit("cup", "cups"), "food": food("butter"), "note": "cold", "display": "1 cup butter, cold"},
                   {"title": "Filling", "quantity": 6, "unit": None, "food": food("apple", "apples"), "note": "peeled and sliced", "display": ""},
                   {"quantity": 0.75, "unit": unit("cup", "cups"), "food": food("sugar"), "note": "",
                    "display": "<sup>3</sup>⁄<sub>4</sub> cup sugar"},
                   {"quantity": 2, "unit": unit("teaspoon", "teaspoons", "tsp", True), "food": food("cinnamon"), "note": "", "display": ""},
                   {"quantity": 0, "unit": None, "food": None, "note": "a pinch of salt", "display": ""},
               ],
               recipeInstructions=[
                   {"title": "Crust", "text": "Rub the butter into the flour, add **cold water** and rest the dough for 30 minutes."},
                   {"title": "", "text": "Roll out half and line the dish."},
                   {"title": "Filling", "text": "Toss the apples with the sugar and cinnamon."},
                   {"title": "", "text": "Fill, cover with the rest of the dough and bake at 190 °C for 50 minutes.\n\nSee [the notes](https://recipes.example.com/notes)."},
               ],
               notes=[{"title": "Apples", "text": "Tart ones keep their shape."}, {"title": "", "text": "Good cold the next day."}]),
        recipe(102, "banana-bread", "Banana bread", ["baking", "breakfast"], description="Uses up brown bananas.",
               recipeYieldQuantity=1, recipeYield="loaf", totalTime="PT1H5M",
               recipeIngredient=[{"quantity": 3, "unit": None, "food": food("banana", "bananas"), "note": "ripe", "display": "3 bananas, ripe"}],
               recipeInstructions=[{"title": "", "text": "Mash, mix, bake for an hour."}]),
        recipe(103, "chili", "Chili", ["dinner"], description="", recipeServings=6, totalTime="2 hours",
               recipeIngredient=[{"quantity": 2, "unit": unit("can", "cans"), "food": food("bean", "beans"), "note": "", "display": "2 cans beans"}],
               recipeInstructions=[{"title": "", "text": "Simmer for two hours."}]),
        recipe(104, "empty-idea", "Empty idea"),
    ]
    for i in range(1, 57):
        recipes.append(recipe(i, "weeknight-%02d" % i, "Weeknight dinner %02d" % i, ["dinner"], totalTime="30 minutes"))
    return recipes


STATE = {"recipes": initial(), "log": [], "offline": False, "tokens": {}, "sessions": {}, "pending": {}, "next_id": 1, "sso": []}

USER = {"id": "b0000000-0000-4000-8000-000000000001", "username": "sam", "fullName": "Sam Example",
        "email": "sam@example.com", "group": "Home", "household": "Family", "admin": False}


def b64url(raw):
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def summary(r):
    keep = ("id", "slug", "name", "description", "recipeServings", "recipeYieldQuantity", "recipeYield", "totalTime",
            "prepTime", "performTime", "rating", "orgURL", "recipeCategory", "tags", "tools")
    return {k: r[k] for k in keep}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="application/json"):
        raw = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def who(self):
        """What the request's token is: "api" (TOKEN or one made here), "session", or None."""
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return None
        t = auth[7:]
        if t == TOKEN or t in [v["token"] for v in STATE["tokens"].values()]:
            return "api"
        if t in STATE["sessions"]:
            return "session"
        return None

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw.decode() or "{}")
        except ValueError:
            return {}

    def handle_all(self, method):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        with LOCK:
            # test helpers
            if u.path == "/__state":
                return self.send(200, {"log": STATE["log"], "sso": STATE["sso"], "sessions": len(STATE["sessions"]),
                                       "tokens": [{"id": k, "name": v["name"]} for k, v in sorted(STATE["tokens"].items())],
                                       "recipes": len(STATE["recipes"])})
            if u.path == "/__reset":
                STATE.update({"recipes": initial(), "log": [], "offline": False, "tokens": {}, "sessions": {}, "pending": {},
                              "next_id": 1, "sso": []})
                return self.send(200, {})
            if u.path == "/__offline":
                STATE["offline"] = q.get("on", ["1"])[0] == "1"
                return self.send(200, {})
            if u.path == "/__rename":
                for r in STATE["recipes"]:
                    if r["slug"] == q.get("slug", [""])[0]:
                        r["name"] = q.get("name", [""])[0]
                return self.send(200, {})
            if STATE["offline"]:
                return self.send(503, {"detail": "offline"})
            STATE["log"].append(method + " " + self.path.split("?")[0] + (" auth" if self.headers.get("Authorization") else ""))

            # the identity provider (an app sends the browser here)
            if u.path == "/idp/authorize" and method == "GET":
                need = ("response_type", "client_id", "redirect_uri", "scope", "code_challenge", "code_challenge_method", "state", "nonce")
                if any(k not in q for k in need) or q["code_challenge_method"][0] != "S256" or q["client_id"][0] != "mealie-web":
                    return self.send(400, {"error": "invalid_request"})
                code = "code-%d" % (len(STATE["pending"]) + 1)
                STATE["pending"][code] = {"challenge": q["code_challenge"][0], "redirect_uri": q["redirect_uri"][0], "nonce": q["nonce"][0]}
                STATE["sso"].append({"redirect_uri": q["redirect_uri"][0], "scope": q["scope"][0]})
                return self.send(200, {"code": code, "state": q["state"][0]})

            if u.path == "/api/app/about" and method == "GET":
                return self.send(200, {"production": True, "version": "v3.9.2", "demoStatus": False, "allowSignup": False,
                                       "allowPasswordLogin": True, "enableOidc": not NO_OIDC, "oidcRedirect": False,
                                       "oidcProviderName": "Example ID", "tokenTime": 48})
            if u.path == "/api/auth/oauth/native/config" and method == "GET":
                if OLD or NO_OIDC:
                    return self.send(404, {"detail": "Not Found" if OLD else "OIDC is not configured"})
                return self.send(200, {"authorization_endpoint": "http://127.0.0.1:%d/idp/authorize" % self.server.server_address[1],
                                       "client_id": "mealie-web", "scope": "openid email profile"})
            if u.path == "/api/auth/oauth/native/token" and method == "POST":
                if OLD or NO_OIDC:
                    return self.send(404, {"detail": "Not Found"})
                b = self.body()
                p = STATE["pending"].pop(b.get("code") or "", None)
                ok = (p is not None and b.get("redirect_uri") == p["redirect_uri"] and b.get("nonce") == p["nonce"]
                      and b64url(hashlib.sha256(str(b.get("code_verifier") or "").encode()).digest()) == p["challenge"])
                if not ok:
                    return self.send(401, {"detail": "Unauthorized"})
                t = "session-%d" % (len(STATE["sessions"]) + 1)
                STATE["sessions"][t] = True
                return self.send(200, {"access_token": t, "token_type": "bearer", "expires_in": 172800})

            # everything below needs a token
            kind = self.who()
            if not kind:
                return self.send(401, {"detail": "Could not validate credentials"})
            if u.path == "/api/users/self" and method == "GET":
                return self.send(200, USER)
            if u.path == "/api/users/api-tokens" and method == "POST":
                b = self.body()
                if not b.get("name"):
                    return self.send(422, {"detail": "name"})
                i = STATE["next_id"]
                STATE["next_id"] += 1
                STATE["tokens"][i] = {"name": b["name"], "token": "made-token-%d" % i}
                return self.send(201, {"name": b["name"], "id": i, "createdAt": "2026-11-24T12:00:00", "token": "made-token-%d" % i})
            if u.path.startswith("/api/users/api-tokens/") and method == "DELETE":
                try:
                    i = int(u.path.rsplit("/", 1)[1])
                except ValueError:
                    return self.send(422, {"detail": "id"})
                if i not in STATE["tokens"]:
                    return self.send(404, {"detail": "no such token"})
                gone = STATE["tokens"].pop(i)
                return self.send(200, {"tokenDelete": gone["name"]})
            if u.path == "/api/organizers/categories" and method == "GET":
                return self.send(200, {"page": 1, "per_page": -1, "total": len(CATEGORIES), "total_pages": 1,
                                       "items": CATEGORIES, "next": None, "previous": None})
            if u.path == "/api/recipes" and method == "GET":
                items = list(STATE["recipes"])
                search = (q.get("search", [""])[0] or "").lower()
                if search:
                    def hit(r):
                        text = r["name"] + " " + (r["description"] or "") + " " + " ".join(
                            ((i.get("food") or {}).get("name") or "") + " " + (i.get("note") or "") for i in r["recipeIngredient"])
                        return search in text.lower()
                    items = [r for r in items if hit(r)]
                for c in q.get("categories", []):
                    items = [r for r in items if any(c in (k["id"], k["slug"]) for k in r["recipeCategory"])]
                order, direction = q.get("orderBy", ["created_at"])[0], q.get("orderDirection", ["desc"])[0]
                if order == "name":
                    items.sort(key=lambda r: r["name"].lower(), reverse=direction == "desc")
                else:
                    items.sort(key=lambda r: r["order"], reverse=direction == "desc")
                page, per = int(q.get("page", ["1"])[0]), int(q.get("perPage", ["50"])[0])
                total = len(items)
                pages = max(1, -(-total // per)) if per > 0 else 1
                part = items if per <= 0 else items[(page - 1) * per:page * per]
                return self.send(200, {"page": page, "per_page": per, "total": total, "total_pages": pages,
                                       "items": [summary(r) for r in part], "next": None, "previous": None})
            if u.path.startswith("/api/recipes/") and method == "GET":
                slug = unquote(u.path[len("/api/recipes/"):])
                for r in STATE["recipes"]:
                    if r["slug"] == slug:
                        return self.send(200, r)
                return self.send(404, {"detail": "no such recipe"})
            return self.send(404, {"detail": "Not Found"})

    def do_GET(self):
        self.handle_all("GET")

    def do_POST(self):
        self.handle_all("POST")

    def do_DELETE(self):
        self.handle_all("DELETE")


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    print("mock Mealie on", srv.server_address[1], flush=True)
    srv.serve_forever()
