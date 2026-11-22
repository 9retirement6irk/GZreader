#!/usr/bin/env python3
"""Ask a real BookOrbit server the questions GZreader's BookOrbit support
depends on, and print what came back in a form that is safe to paste into a
pull request: status codes, field names and counts only. It never prints the
address, the user name, the password, the API key, a book's title or any
other value from the library.

    python3 tools/gzreader/bookorbit-probe.py

It asks for the server's address, the KOReader sync user name and password
(BookOrbit: Settings, KOReader), and optionally an API key (for audiobooks).
Or set BOOKORBIT_URL, BOOKORBIT_KO_USER, BOOKORBIT_KO_PASSWORD and
BOOKORBIT_API_KEY. It only reads books and positions; the one trace it leaves is
a device named "GZreader probe" in BookOrbit's KOReader device list (from the
match check), which can be removed there.
"""
import getpass, hashlib, json, os, socket, ssl, sys, urllib.error, urllib.request

TLS = None

MOCK_SHAPES = {  # what the tests' mock server (tests/mock_bookorbit.py) sends, to compare with
    "list item": {"id", "title", "authors", "seriesId", "seriesName", "seriesIndex", "progressPercentage", "lastReadAt",
                  "readStatus", "formats", "hasCover", "thumbnailUrl", "detailUrl", "addedAt", "updatedAt"},
    "file": {"id", "format", "role", "downloadVariant", "sizeBytes", "sourceSizeBytes", "durationSeconds", "fileHash",
             "downloadUrl", "devicePath"},
    "manifest": {"schema", "schemaVersion", "revision", "book", "assets", "chapters", "totalDurationMs"},
    "asset": {"assetId", "fileId", "sequence", "format", "durationMs", "sizeBytes", "etag"},
}


def ask(env, prompt, secret=False, optional=False):
    v = os.environ.get(env)
    if v:
        return v.strip()
    if not sys.stdin.isatty():
        return "" if optional else sys.exit("Set %s (not a terminal, so I can't ask)." % env)
    v = (getpass.getpass(prompt) if secret else input(prompt)).strip()
    if not v and not optional:
        sys.exit("Needed: " + prompt.strip(": "))
    return v


def tls_context():
    """The system's certificates; where Python has none of its own (python.org's
    Python on a Mac before its "Install Certificates" step), macOS's bundle or certifi's."""
    ctx = ssl.create_default_context()
    if ctx.cert_store_stats().get("x509_ca", 0) == 0:
        for bundle in ("/etc/ssl/cert.pem", "/etc/ssl/certs/ca-certificates.crt"):
            if os.path.exists(bundle):
                try:
                    ctx.load_verify_locations(bundle)
                    break
                except (OSError, ssl.SSLError):
                    pass
        else:
            try:
                import certifi
                ctx.load_verify_locations(certifi.where())
            except Exception:
                pass
    return ctx


def why(e):
    """Why a request got no answer, in words that name no address."""
    r = getattr(e, "reason", e)
    text = str(r)
    if isinstance(r, ssl.SSLCertVerificationError) or "CERTIFICATE_VERIFY_FAILED" in text:
        return "the server's certificate wasn't accepted (%s)" % (getattr(r, "verify_message", "") or "verification failed")
    if isinstance(r, ssl.SSLError):
        return "a TLS error (%s)" % (getattr(r, "reason", None) or type(r).__name__)
    if isinstance(r, socket.gaierror):
        return "the address's name wasn't found (DNS)"
    if isinstance(r, (socket.timeout, TimeoutError)) or "timed out" in text:
        return "timed out"
    if isinstance(r, ConnectionRefusedError):
        return "connection refused"
    if isinstance(r, ConnectionResetError):
        return "connection reset"
    code = getattr(r, "errno", None)
    return type(r).__name__ + (code and " (errno %s)" % code or "")


def call(base, path, headers, method="GET", body=None, want_bytes=0):
    data = json.dumps(body).encode() if body is not None else None
    h = dict(headers)
    h.setdefault("User-Agent", "GZreader-probe/1")
    h.setdefault("Accept", "*/*")
    if data is not None:
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(base + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=30, context=TLS) as r:
            code, raw, hdr = r.status, r.read(want_bytes or 4 << 20), r.headers
    except urllib.error.HTTPError as e:
        code, raw, hdr = e.code, e.read(1 << 16), e.headers
    except (urllib.error.URLError, OSError) as e:
        return None, None, {}, why(e)
    if want_bytes:
        return code, raw, hdr, None
    try:
        return code, json.loads(raw) if raw else None, hdr, None
    except ValueError:
        return code, None, hdr, "not JSON"


def keys(v):
    return sorted(v) if isinstance(v, dict) else type(v).__name__


def line(name, code, note=""):
    print("%-44s %s  %s" % (name, code if code is not None else "no answer", note))


def compare(name, got):
    want = MOCK_SHAPES[name]
    got = set(got)
    if got >= want:
        extra = sorted(got - want)
        print("    %s: has every field GZreader's tests use%s" % (name, extra and "; also " + ", ".join(extra) or ""))
    else:
        print("    %s: MISSING %s" % (name, ", ".join(sorted(want - got))))


def main():
    base = ask("BOOKORBIT_URL", "BookOrbit address (https://...): ").rstrip("/")
    if not base.startswith(("http://", "https://")):
        sys.exit("The address must start with http:// or https://")
    user = ask("BOOKORBIT_KO_USER", "KOReader sync user name: ")
    password = ask("BOOKORBIT_KO_PASSWORD", "KOReader sync password (not shown): ", secret=True)
    key = ask("BOOKORBIT_API_KEY", "API key for audiobooks (not shown; Enter to skip): ", secret=True, optional=True)
    ko = {"x-auth-user": user, "x-auth-key": hashlib.md5(password.encode()).hexdigest()}
    A = base + "/api/v1"
    global TLS
    TLS = tls_context()
    print("\nBookOrbit probe (status codes and field names only)\n")
    print("Python %s on %s; %d certificate authorities loaded\n" % (sys.version.split()[0], sys.platform, TLS.cert_store_stats().get("x509_ca", 0)))

    code, j, _, err = call(A, "/koreader/users/auth", ko)
    line("sign-in (koreader/users/auth)", code, err or keys(j))
    if code is None:
        print("\nNo answer from the server (%s), so the rest is skipped. The sign-in wasn't tried." % err)
        return 1
    if code != 200:
        ctype = "a web page" if j is None else "JSON"
        print("\nThe sign-in didn't work (the answer was %s), so the rest is skipped. 401: wrong user name or password; 403 with JSON:"
              " sync is switched off for these credentials in BookOrbit; 403 or 302 with a web page: something in front of"
              " BookOrbit (an access proxy or a bot check) answered instead of it." % ctype)
        return 1
    code, j, _, err = call(A, "/koreader/plugin/version", ko)
    line("version", code, err or (isinstance(j, dict) and "server %s; capabilities: %s" % (
        j.get("serverVersion"), ", ".join(j.get("capabilities") or [])) or ""))

    code, j, _, err = call(A, "/koreader/plugin/catalog/root", ko)
    line("catalog root", code, err or (isinstance(j, dict) and "sections: " + ", ".join(
        str(s.get("section")) for s in j.get("sections") or []) or keys(j)))
    for s in ("libraries", "collections", "authors", "series"):
        code, j, _, err = call(A, "/koreader/plugin/catalog/sections/" + s, ko)
        items = isinstance(j, dict) and j.get("items") or []
        line("section " + s, code, err or "%d entries; entry fields: %s" % (len(items), items and keys(items[0]) or "-"))

    code, j, _, err = call(A, "/koreader/plugin/catalog/books?size=5&sort=recently_added", ko)
    items = isinstance(j, dict) and j.get("items") or []
    line("books (first 5)", code, err or "total %s; page fields: %s" % (isinstance(j, dict) and j.get("total"), keys(j)))
    file_hash = None
    if items:
        compare("list item", items[0])
        code, d, _, err = call(A, "/koreader/plugin/catalog/books/%d" % items[0]["id"], ko)
        line("book detail", code, err or "")
        files = isinstance(d, dict) and d.get("files") or []
        if files:
            compare("file", files[0])
            f = files[0]
            file_hash = f.get("fileHash")
            print("    file: format %s, role %s, variant %s, hash %s" % (
                f.get("format"), f.get("role"), f.get("downloadVariant"),
                "32 hex (KOReader's kind)" if isinstance(file_hash, str) and len(file_hash) == 32 else "absent or another kind"))
            code, raw, hdr, err = call(base, f["downloadUrl"], ko, want_bytes=4096)
            line("download (first 4 KB only)", code, err or "type %s; length header %s" % (
                hdr.get("Content-Type"), "present" if hdr.get("Content-Length") else "absent"))
        if items[0].get("thumbnailUrl"):
            code, raw, hdr, err = call(base, items[0]["thumbnailUrl"], ko, want_bytes=64)
            line("cover", code, err or "type %s; ETag %s" % (hdr.get("Content-Type"), "present" if hdr.get("ETag") else "absent"))
    if file_hash:
        dev = {"deviceId": "gzreader-probe", "deviceModel": "GZreader probe", "pluginVersion": "0.0.0"}
        code, j, _, err = call(A, "/koreader/plugin/match-check", ko, "POST", dict(dev, hashes=[file_hash]))
        line("match-check (that book's hash)", code, err or "%s; matched %d" % (keys(j), len(isinstance(j, dict) and j.get("matches") or [])))
        code, j, _, err = call(A, "/koreader/syncs/progress/" + file_hash, ko)
        line("reading position (KOSync)", code, err or (j and keys(j) or "none stored ({})"))

    if not key:
        print("\nNo API key given: audiobooks not checked.")
        return 0
    api = {"Authorization": "Bearer " + key}
    code, j, _, err = call(A, "/auth/me", api)
    line("API key (auth/me)", code, err or (isinstance(j, dict) and "method %s" % j.get("authenticationMethod") or ""))
    if code != 200:
        return 1
    audio = ["m4b", "mp3", "m4a", "flac", "ogg", "opus"]
    query = {"sort": [{"field": "title", "dir": "asc"}], "pagination": {"page": 1, "size": 1},
             "filter": {"type": "group", "join": "AND", "rules": [
                 {"type": "rule", "field": "format", "operator": "includesAny", "value": audio + [f.upper() for f in audio]}]}}
    code, j, _, err = call(A, "/books/query", api, "POST", query)
    items = isinstance(j, dict) and j.get("items") or []
    line("books/query (audiobooks)", code, err or "total %s; page fields: %s; card fields: %s" % (
        isinstance(j, dict) and j.get("total"), keys(j), items and keys(items[0]) or "-"))
    if not items:
        print("    no audiobook found (none in the library, or the format filter doesn't match): send this line back")
        return 0
    bid = items[0].get("id")
    code, m, _, err = call(A, "/audiobooks/%s/manifest" % bid, api)
    line("audiobook manifest", code, err or "")
    if isinstance(m, dict) and m.get("assets"):
        compare("manifest", m)
        compare("asset", m["assets"][0])
        print("    %d file(s), %d chapter(s), formats: %s" % (len(m["assets"]), len(m.get("chapters") or []),
                                                             ", ".join(sorted({str(a.get("format")) for a in m["assets"]}))))
        code, raw, hdr, err = call(A, "/audiobooks/%s/assets/%s/content" % (bid, m["assets"][0]["assetId"]),
                                   dict(api, Range="bytes=0-1023"), want_bytes=1024)
        line("audio file (first 1 KB, resumable?)", code, err or "Content-Range %s" % ("present" if hdr.get("Content-Range") else "absent"))
        code, j, _, err = call(A, "/audiobooks/%s/playback-state" % bid, api)
        line("listening position", code, err or (j and keys(j) or "none stored"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
