#!/usr/bin/env python3
"""The sync page (docs/sync) in a real browser, against the mock servers.

  sync_page_test.py <port> [<dump dir>]

Chromium (Playwright) opens the page from a local server; a folder in the
browser's private storage (OPFS) stands in for the Kindle's drive, with an
outbox.json as GZreader writes it. The page signs in to the mock Grimmory,
Memos and Plex, syncs, and the test checks what it left (inbox.json, the
library copy, the books, audiobooks, music, notes, calendars) and what the
servers got. With a dump dir, the Kindle's GZreader folder as the page left
it is copied there, for run_tests.lua's import test (GZ_SYNC_DUMP).
Ports: port (Grimmory) port+1 (its control), port+20 Memos, port+21 Plex,
port+22 the page, port+23 Immich (with the CORS headers a proxy adds), port+24
Immich as it is (none).
"""
import base64, datetime, json, os, shutil, struct, subprocess, sys, tempfile, threading, time, urllib.request
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18500
DUMP = sys.argv[2] if len(sys.argv) > 2 else None
GP, MP, PP, WP, IP = PORT, PORT + 20, PORT + 21, PORT + 22, PORT + 23

passed = failed = 0
def check(cond, name):
    global passed, failed
    if cond:
        passed += 1; print("  ok   " + name)
    else:
        failed += 1; print("  FAIL " + name)

procs = []
import atexit
atexit.register(lambda: [p.terminate() for p in procs])  # (also when a step fails)
def lua_chunks(path, seconds=15):
    """gzreader_mp4.lua's conversion (what GZreader does on the Kindle): {name: bytes}, index.json's text."""
    out = tempfile.mkdtemp()
    script = os.path.join(out, "convert.lua")
    with open(script, "w") as f:
        f.write("package.path = %r .. '/?.lua;' .. package.path\n" % os.path.join(REPO, "plugins", "gzreader.koplugin")
                + "local Mp4 = require('gzreader_mp4'); Mp4.CHUNK_SECONDS = %s\n" % seconds
                + "local r = assert(Mp4.convert(arg[1], arg[2])); io.write(Mp4.indexJson(r))\n")
    os.makedirs(os.path.join(out, "c"))
    idx = subprocess.run(["luajit", script, path, os.path.join(out, "c")], capture_output=True, check=True).stdout.decode()
    got = {}
    for n in os.listdir(os.path.join(out, "c")):
        with open(os.path.join(out, "c", n), "rb") as f: got[n] = f.read()
    shutil.rmtree(out)
    return got, idx

def spawn(*args):
    p = subprocess.Popen([sys.executable, "-I", *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=dict(os.environ))
    procs.append(p)
    return p

def wait_port(port):
    for _ in range(50):
        try:
            urllib.request.urlopen("http://127.0.0.1:%d/" % port, timeout=1)
            return
        except urllib.error.HTTPError:
            return
        except Exception:
            time.sleep(0.1)

# (the single-file audiobook Grimmory streams: a real M4A, which the page prepares for the Kindle)
TEST_M4A = os.path.join(REPO, "plugins", "gzreader.koplugin", "audio", "test.m4a")
os.environ.setdefault("GZ_TEST_M4A", TEST_M4A)
spawn(os.path.join(HERE, "mock_grimmory.py"), str(GP))
spawn(os.path.join(REPO, "tools", "gzreader", "emulator", "demo", "mock_memos.py"), str(MP), "--sample", "--spaces")
spawn(os.path.join(HERE, "mock_plex.py"), str(PP))
spawn(os.path.join(REPO, "tools", "gzreader", "emulator", "demo", "mock_immich.py"), str(IP), "--cors")
spawn(os.path.join(REPO, "tools", "gzreader", "emulator", "demo", "mock_immich.py"), str(IP + 1))
def immich_uid(n, kind="a"): return "%08x-0000-4000-8000-%s%011x" % (n, kind, n)

# the page, as GitHub Pages serves it (/GZreader/…), and a calendar link
web = tempfile.mkdtemp()
os.symlink(os.path.join(REPO, "docs"), os.path.join(web, "GZreader"))
def ics_time(t): return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime(t))
now = time.time()
with open(os.path.join(web, "family.ics"), "w") as f:
    f.write("BEGIN:VCALENDAR\r\nX-WR-CALNAME:Family\r\nBEGIN:VEVENT\r\nUID:a\r\nSUMMARY:Dentist\r\nDTSTART:%s\r\nDTEND:%s\r\nEND:VEVENT\r\n"
            "BEGIN:VEVENT\r\nUID:b\r\nSUMMARY:Swim\r\nDTSTART:%s\r\nDTEND:%s\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
            % (ics_time(now + 86400), ics_time(now + 90000), ics_time(now + 2 * 86400), ics_time(now + 2 * 86400 + 3600)))
import hashlib, zipfile
os.makedirs(os.path.join(web, "api")); os.makedirs(os.path.join(web, "updates"))
with open(os.path.join(web, "api", "latest.json"), "w") as f:
    json.dump({"tag_name": "v1.30.0", "assets": []}, f)
upd = os.path.join(web, "updates", "gzreader-update.zip")
with zipfile.ZipFile(upd, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("koreader/gzreader-version", "1.30.0\n")
    z.writestr("koreader/frontend/x.lua", "-- x\n" * 200)
UPD = open(upd, "rb").read()
with open(os.path.join(web, "updates", "latest.json"), "w") as f:
    json.dump({"version": "1.30.0", "file": "gzreader-update.zip", "size": len(UPD), "sha256": hashlib.sha256(UPD).hexdigest()}, f)
# test builds (next to the release's on the updates branch)
with open(os.path.join(web, "updates", "latest-beta.json"), "w") as f:
    json.dump({"version": "1.29.0-beta.abc1234", "file": "gzreader-beta-update.zip", "size": 1, "sha256": "00"}, f)
class Quiet(SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
srv = ThreadingHTTPServer(("127.0.0.1", WP), partial(Quiet, directory=web))
threading.Thread(target=srv.serve_forever, daemon=True).start()
for p in (GP, MP, PP, IP, IP + 1):
    wait_port(p)

OUTBOX = {
    "format": 1, "written_at": int(now), "gzreader": "1.24.0",
    "kindle": {"model": "Kindle2", "name": "Kindle 2 · 3F2A", "id": "3f2a01", "audio": True, "screen": {"w": 824, "h": 1200}},
    "screensavers": {"names": ["old.png"], "mode": "auto"},
    "music_quality": {"bitrate": 128, "shrink": False},
    "grimmory": {"server": "http://127.0.0.1:%d" % GP, "user": "will"},
    "jobs": [
        {"id": "p:1:7", "kind": "progress", "book": 1, "method": "PUT", "path": "/api/v1/app/books/1/progress",
         "body": {"fileProgress": {"bookFileId": 1001, "progressPercent": 42.5, "positionHref": "ch2.xhtml", "positionData": "epubcfi(/6/4!/4/2)"}}},
        {"id": "s:1:2026-11-05T10:00:00Z", "kind": "session", "book": 1, "method": "POST", "path": "/api/v1/reading-sessions",
         "body": {"bookId": 1, "bookType": "EPUB", "startTime": "2026-11-05T10:00:00Z", "endTime": "2026-11-05T10:30:00Z", "durationSeconds": 1800}},
        {"id": "s:1:1970-01-01T02:11:00Z", "kind": "session", "book": 1, "method": "POST", "path": "/api/v1/reading-sessions",
         "body": {"bookId": 1, "bookType": "EPUB", "startTime": "1970-01-01T02:11:00Z", "endTime": "1970-01-01T02:41:00Z", "durationSeconds": 1799}},
        {"id": "r:2:4", "kind": "rating", "book": 2, "method": "PUT", "path": "/api/v1/books/personal-rating", "body": {"ids": [2], "rating": 8}},
        {"id": "p:999:3", "kind": "progress", "book": 999, "method": "PUT", "path": "/api/v1/app/books/999/progress",
         "body": {"fileProgress": {"bookFileId": 1, "progressPercent": 1}}},
        # bookmarks and highlights made on the Kindle (its journal), in order
        {"id": "m:1", "kind": "mark", "op": "bookmark+", "book": 1, "method": "POST", "path": "/api/v1/bookmarks",
         "body": {"bookId": 1, "cfi": "epubcfi(/6/4!/4/8)", "title": "Kindle"}, "temp": "usb-1"},
        {"id": "m:2", "kind": "mark", "op": "highlight+", "book": 1, "method": "POST", "path": "/api/v1/annotations",
         "body": {"bookId": 1, "cfi": "epubcfi(/6/4!/4/2,/1:0,/1:5)", "text": "Hello", "color": "#FFC107", "style": "highlight"}, "temp": "usb-2"},
        {"id": "m:3", "kind": "mark", "op": "highlight~", "method": "PUT", "path": "/api/v1/annotations/{id}", "ref": "usb-2",
         "body": {"color": "#F87171", "style": "highlight", "note": "from the Kindle"}},
        {"id": "m:4", "kind": "mark", "op": "bookmark-", "method": "DELETE", "path": "/api/v1/bookmarks/{id}", "ref": "9999"},
        # a book put on a shelf on the Kindle; one put on someone else's shelf (Grimmory refuses it)
        {"id": "sh:3:5", "kind": "shelf", "book": 3, "method": "POST", "path": "/api/v1/books/shelves",
         "body": {"bookIds": [3], "shelvesToAssign": [6], "shelvesToUnassign": []}},
        {"id": "sh:5:6", "kind": "shelf", "book": 5, "method": "POST", "path": "/api/v1/books/shelves",
         "body": {"bookIds": [5], "shelvesToAssign": [7], "shelvesToUnassign": []}},
    ],
    "disk": {"total": 1500000000, "available": 900000000},
    "queue": [
        {"id": 3, "kind": "book", "title": "Book 03", "authors": ["Author 0"], "format": "EPUB", "file_id": 1003, "name": "book3.epub", "size_kb": 300},
        {"id": 32, "kind": "audiobook", "title": "Book 32", "format": "AUDIOBOOK", "name": "book32.audiobook", "size_kb": 12},
    ],
    # (empty lists as GZreader 1.24 on a Kindle wrote them: {}, KOReader's JSON)
    "have": {"books": {"1": {"file_id": 1001, "format": "EPUB"}}, "audiobooks": {}, "music": ["album-999"]},
    "notes": {"queue": [{"id": "q1", "op": "create", "content": "Written on the Kindle #kindle", "visibility": "PRIVATE"},
                        # (Memos v0.31's spaces: a new note in one, a note moved into one)
                        {"id": "q2", "op": "create", "content": "For the family #kindle", "visibility": "SPACE", "space": "spaces/family"},
                        {"id": "q3", "op": "update", "name": "memos/m003", "content": "A quote for the book club #quotes",
                         "visibility": "PRIVATE", "space": "spaces/book-club"}],
              "keep": 100, "files": {}},
    "calendar": {"days_back": 14, "days_ahead": 90},
    # (GZreader up to 1.28.1 also wrote usage statistics' server here; the page ignores it)
    "usage": {"level": "basic", "server": "http://127.0.0.1:%d" % GP, "app": "test-app"},
    # Send to the developer: the reports in reports/ go to this feed (gzreader_usbreport.lua)
    "report": {"feed": "http://127.0.0.1:%d/open/feed/testfeed" % GP, "device": "Kindle2-ab12cd", "test_build": False},
}
USAGE_LINES = "\n".join(json.dumps(x) for x in [
    {"type": "identify", "payload": {"application": "test-app", "os": "Kindle2", "language": "en", "data": {"id": "k", "version": "1.25.2"}}},
    {"type": "event", "payload": {"application": "test-app", "name": "start", "os": "Kindle2", "language": "en", "data": {"install": "k"}}},
]) + "\n"

from playwright.sync_api import sync_playwright

print("The sync page (docs/sync), in a browser")
# (browsers keep GitHub Pages' files 10 minutes: a new page with an old script breaks, so the
# page asks for the script by its content: update ?v= in index.html when gzsync.js changes)
_js = open(os.path.join(REPO, "docs", "sync", "gzsync.js"), "rb").read()
_v = hashlib.sha256(_js).hexdigest()[:10]
check(('gzsync.js?v=%s"' % _v) in open(os.path.join(REPO, "docs", "sync", "index.html")).read(),
      "index.html asks for this gzsync.js (?v=%s: its SHA-256)" % _v)
with sync_playwright() as pw:
    browser = pw.chromium.launch()
    page = browser.new_page()
    # (a folder in the browser's own storage stands in for the drive: not
    # remembered between visits; headless Chromium stops on reading one back)
    page.add_init_script("window.GZSYNC_TEST = true")
    errors = []
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.on("crash", lambda: errors.append("the page crashed"))
    page.goto("http://127.0.0.1:%d/GZreader/sync/" % WP)
    page.wait_for_function("window.GZSync")
    check(page.locator("h1").inner_text() == "Sync with computer" and page.locator("#sync").is_disabled(),
          "the page opens; Sync waits for a Kindle and a connection")
    page.evaluate("""async ({ outbox, usage }) => {
        const root = await navigator.storage.getDirectory();
        for await (const name of root.keys()) await root.removeEntry(name, { recursive: true });
        const gz = await (await root.getDirectoryHandle('documents', { create: true })).getDirectoryHandle('GZreader', { create: true });
        const sync = await gz.getDirectoryHandle('.gzsync', { create: true });
        const w = await (await sync.getFileHandle('outbox.json', { create: true })).createWritable();
        await w.write(JSON.stringify(outbox)); await w.close();
        const u = await (await (await sync.getDirectoryHandle('usage', { create: true })).getFileHandle('sending-1.jsonl', { create: true })).createWritable();
        await u.write(usage); await u.close();
        window.testRoot = root;
    }""", {"outbox": OUTBOX, "usage": USAGE_LINES})
    # a report saved on the Kindle (Diagnostics → Send to the developer), the log exported when
    # Sync was pressed, and the log files themselves (gzreader_usbreport.lua)
    page.evaluate("""async () => {
        const root = window.testRoot;
        const sync = await (await (await root.getDirectoryHandle('documents')).getDirectoryHandle('GZreader')).getDirectoryHandle('.gzsync');
        const reports = await sync.getDirectoryHandle('reports', { create: true });
        async function put(dir, name, text) { const w = await (await dir.getFileHandle(name, { create: true })).createWritable(); await w.write(text); await w.close(); }
        await put(reports, 'report-20261108-101500.txt', 'Grimmory plugin log, exported 2026-11-08 10:15:00\\n\\nthe saved report\u2019s log line\\n');
        await put(reports, 'report-20261108-101500.json', JSON.stringify({ note: 'Sign-in froze at https://books.example.com/login?password=hunter2', at: 1794150900, version: '1.26.9', device: 'Kindle2-ab12cd', test_build: false }));
        await put(reports, 'report-20261108-101700.txt', 'a report whose .json never got written');
        await put(reports, 'latest.txt', 'Grimmory plugin log, exported when Sync was pressed\\n\\n===== staying awake =====\\nfresh export line\\n');
        const ko = await root.getDirectoryHandle('koreader', { create: true });
        await put(ko, 'gzreader.log.1', 'older log line\\n');
        await put(ko, 'gzreader.log', 'newer log line\\n');
        await put(ko, 'crash.log', 'crash line GET /x?access_token=abc123&y=1\\n');
    }""")
    check(page.locator("#gate").is_visible() and not page.locator("#app").is_visible(), "a Kindle first: nothing to set up before one is chosen")
    page.evaluate("() => GZSync.open(window.testRoot, true)")
    page.wait_for_selector("#unlock:not(.hidden)")
    check("Choose a PIN" in page.locator("#unlock-title").inner_text() and page.locator("#pin2").is_visible(),
          "a new Kindle: a PIN is chosen for it")
    page.fill("#pin", "24"); page.fill("#pin2", "24"); page.click("#unlock-go")
    page.wait_for_selector("#unlock-err:not(.hidden)")
    check("At least 4" in page.locator("#unlock-err").inner_text(), "…at least 4 characters")
    page.fill("#pin", "2468"); page.fill("#pin2", "2468"); page.click("#unlock-go")
    page.wait_for_selector("#app:not(.hidden)")
    check("Kindle 2 · 3F2A" in page.locator("#k-name").inner_text() and "11 reading updates" in page.locator("#k-sub").inner_text()
          and page.locator("nav.main button.on").inner_text() == "Connections",
          "unlocked: the Kindle, what's waiting; Connections first while there are none")

    # connections, as a person would make them
    page.fill("#g-server", "http://127.0.0.1:%d" % GP)
    page.fill("#g-user", "will")
    page.fill("#g-pass", "wrong")
    page.click("#g-login")
    page.wait_for_selector("#c-grimmory .err")
    check("Wrong username or password" in page.locator("#c-grimmory .err").inner_text(), "Grimmory: a wrong password says so")
    page.fill("#g-pass", "hunter22")
    page.click("#g-login")
    page.wait_for_selector("#c-grimmory.on")
    check(page.locator("#g-pass").input_value() == "", "Grimmory: signed in")
    page.fill("#m-server", "http://127.0.0.1:%d" % MP)
    page.fill("#m-token", "memos-test-token")
    page.click("#m-connect")
    page.wait_for_selector("#c-memos.on")
    check("Connected to" in page.locator("#m-status").inner_text(), "Memos: connected with an access token")
    # Immich: as it is (no CORS headers) the page can't reach it, and says what to do; through a proxy that adds them, it can
    page.fill("#i-server", "http://127.0.0.1:%d" % (IP + 1))
    page.fill("#i-key", "immich-test-key")
    page.click("#i-connect")
    page.wait_for_selector("#c-immich .err")
    check("Couldn't reach Immich from this page" in page.locator("#c-immich .err").inner_text(), "Immich without CORS headers: the page says what's needed")
    page.evaluate("() => document.querySelector('#c-immich .err').remove()")
    page.fill("#i-server", "http://127.0.0.1:%d" % IP)
    page.fill("#i-key", "wrong")
    page.click("#i-connect")
    page.wait_for_selector("#c-immich .err")
    check("didn't accept the API key" in page.locator("#c-immich .err").inner_text(), "Immich: a wrong API key says so")
    page.fill("#i-server", "http://127.0.0.1:%d/albums/%s?x=1" % (IP, immich_uid(1, "b")))
    page.fill("#i-key", "immich-test-key")
    page.click("#i-connect")
    page.wait_for_selector("#c-immich.on")
    opts = page.eval_on_selector_all("#i-album option", "os => os.map(o => o.textContent)")
    check("as Will" in page.locator("#i-status").inner_text() and "Kindle" in page.locator("#i-status").inner_text()
          and page.locator("#i-album").input_value() == immich_uid(1, "b") and opts == ["Family (2)", "Kindle (30)", "Trip (4)"],
          "Immich: connected with an album's address: that album chosen, the others (shared ones too) to choose from %r" % opts)
    page.select_option("#i-count", "10")
    page.check("#i-wall")
    page.click("#c-cal summary")
    page.fill("#cal-url", "http://127.0.0.1:%d/family.ics" % WP)
    page.click("#cal-add")
    page.fill("#cal-url", "http://127.0.0.1:%d/missing.ics" % WP)
    page.fill("#cal-name", "Old")
    page.click("#cal-add")
    check(page.locator("#cal-list li").count() == 2, "calendars: two links added")
    page.evaluate("""(pp) => {
        GZSync.P.st = { token: 'plex-token', user: 'tones', server: { name: 'Tones', uri: 'http://127.0.0.1:' + pp, token: 'srv-token' } };
        return GZSync.P.save();
    }""", PP)
    keys = page.evaluate("""async () => {
        for (let i = 0; i < 20; i++) {
            await GZSync.Vault.chain;
            try {
                const s = await (await (await navigator.storage.getDirectory()).getDirectoryHandle('documents')).getDirectoryHandle('GZreader');
                return await (await (await (await s.getDirectoryHandle('.gzsync')).getFileHandle('keys.json')).getFile()).text();
            } catch (e) { await new Promise(r => setTimeout(r, 200)); }   // (being written)
        }
    }""")
    check(all(t not in keys for t in ("hunter22", "memos-test-token", "plex-token", "family.ics", "127.0.0.1", "immich-test-key")) and json.loads(keys)["cipher"] == "AES-256-GCM"
          and not page.evaluate("() => Object.keys(localStorage).filter(k => k.startsWith('gzsync.') && k !== 'gzsync.sso').length"),
          "the sign-ins are on the Kindle, encrypted with its PIN (and not in the browser)")

    # picks the Kindle has meanwhile (from another computer's sync, say): Book 01 and album 999 are on it
    page.evaluate("""async () => {
        const s = await (await (await navigator.storage.getDirectory()).getDirectoryHandle('documents')).getDirectoryHandle('GZreader');
        const d = await s.getDirectoryHandle('.gzsync');
        let p = { books: [], music: [] };
        try { p = JSON.parse(await (await (await d.getFileHandle('picks.json')).getFile()).text()); } catch (e) {}
        p.books = (p.books || []).concat([{ id: 1, kind: 'book', title: 'Book 01', size_kb: 100 }]);
        p.music = (p.music || []).concat([{ kind: 'album', key: '999', title: 'Old Album' }]);
        const w = await (await d.getFileHandle('picks.json', { create: true })).createWritable();
        await w.write(JSON.stringify(p)); await w.close();
    }""")
    page.goto("about:blank")   # (a fresh visit, as on another computer)
    page.goto("http://127.0.0.1:%d/GZreader/sync/" % WP)
    page.wait_for_function("window.GZSync")
    page.evaluate("""async () => { window.testRoot = await navigator.storage.getDirectory(); await GZSync.open(window.testRoot, true); }""")
    page.wait_for_selector("#unlock:not(.hidden)")
    page.fill("#pin", "1357"); page.click("#unlock-go")
    page.wait_for_selector("#unlock-err:not(.hidden)")
    check("isn't this Kindle's PIN" in page.locator("#unlock-err").inner_text(), "unlock: a wrong PIN says so")
    page.fill("#pin", "2468"); page.click("#unlock-go")
    page.wait_for_selector("#app:not(.hidden)")
    seen = (page.locator("#c-plex.on").count(), page.locator("#c-grimmory.on").count(), page.locator("#c-memos.on").count(),
            page.locator("#cal-list li").count(), page.locator("nav.main button.on").inner_text())
    check(seen == (1, 1, 1, 2, "Content"), "unlocked again (another visit): every connection back; Content first %r" % (seen,))
    stale = page.evaluate("""async () => {
        const s = await (await (await navigator.storage.getDirectory()).getDirectoryHandle('documents')).getDirectoryHandle('GZreader');
        for (let i = 0; i < 50; i++) {
            const p = JSON.parse(await (await (await (await s.getDirectoryHandle('.gzsync')).getFileHandle('picks.json')).getFile()).text());
            if (!p.books.some(b => b.id === 1) && !p.music.some(m => m.key === '999')) return [GZSync.Picks.d.books.length, GZSync.Picks.d.music.length, document.querySelector('#picks').innerText];
            await new Promise(r => setTimeout(r, 100));
        }
        return null;
    }""")
    check(stale is not None and stale[:2] == [0, 0] and "Book 01" not in stale[2] and "Old Album" not in stale[2],
          "picks the Kindle already has: off the list (on the Kindle too), not shown as coming %r" % (stale,))
    # music quality: as on the Kindle (128, MP3/AAC as they are), then chosen here: 192, bigger ones made smaller
    page.evaluate("() => GZSync.setPanel('connections')")
    check(page.locator("#p-bitrate").input_value() == "128" and not page.locator("#p-shrink").is_checked(),
          "music quality: the Kindle's, shown with the Plex connection")
    page.select_option("#p-bitrate", "192")
    page.check("#p-shrink")
    page.evaluate("() => GZSync.setPanel('content')")

    # choosing on the page: books, audiobooks, music, as in the Kindle's Grimmory tab
    page.wait_for_selector("#b-results li button")
    text = page.locator("#b-results").inner_text()
    check("Book 25" in text and "Book 33" not in text and page.locator("#b-results li", has_text="Book 01").locator("button").inner_text() == "On the Kindle"
          and page.locator("#b-results li", has_text="Book 03").locator("button").inner_text() == "In its queue" and page.locator("#b-more").is_visible(),
          "Books: Recently added, a page at a time (no audiobooks); what's on the Kindle or in its queue says so")
    page.wait_for_function("[...document.querySelectorAll('#b-results img')].some(i => i.complete && i.naturalWidth > 0)")
    check(True, "covers shown (Grimmory's, in <img>: a web page can't read them, it can show them)")
    page.click("#b-cats button:has-text('Libraries')")
    page.wait_for_selector("#b-results li.nav:has-text('fiction')")
    page.click("#b-results li.nav:has-text('fiction')")
    page.wait_for_selector("#b-crumbs button:has-text('Libraries')")
    page.wait_for_function("document.querySelector('#b-results').innerText.includes('Book 02')")
    check("Book 02" in page.locator("#b-results").inner_text() and "Book 01" not in page.locator("#b-results").inner_text(),
          "Libraries: a library's books, with the way back")
    page.click("#b-crumbs button")
    page.wait_for_selector("#b-results li.nav:has-text('Comics')")
    page.click("#b-cats button:has-text('Shelves')")
    page.wait_for_selector("#b-results li.nav")
    page.locator("#b-results li.nav").first.click()
    page.wait_for_function("document.querySelector('#b-results').innerText.includes('Book 10')")
    page.click("#b-cats button:has-text('Authors')")
    page.wait_for_selector("#b-results li.nav:has-text('Author 2')")
    page.click("#b-cats button:has-text('Series')")
    page.wait_for_selector("#b-results li.nav:has-text('Saga / Part One')")
    page.click("#b-results li.nav:has-text('Saga / Part One')")
    page.wait_for_function("document.querySelector('#b-results').innerText.includes('Book 06')")
    order = page.locator("#b-results li .txt").all_inner_texts()
    check(order[0].startswith("Book 06") and order[1].startswith("Book 05"), "Shelves, Authors, Series: a series in its order")
    page.fill("#b-search", "Book 05")
    page.click("#b-go")
    page.wait_for_function("document.querySelectorAll('#b-results li').length === 1")
    page.locator("#b-results li", has_text="Book 05").locator("button").click()
    page.click(".tabs button[data-tab=audio]")
    page.wait_for_selector("#b-results li:has-text('Book 33') button")
    check(page.locator("#b-results li", has_text="Book 32").locator("button").inner_text() == "In its queue",
          "Audiobooks: only audiobooks; one the Kindle queued says so")
    page.locator("#b-results li", has_text="Book 33").locator("button").click()
    page.click(".tabs button[data-tab=music]")
    page.wait_for_selector("#b-results li:has-text('FLAC Album') button")
    for title in ("MP3 Album", "AAC Album", "FLAC Album"):
        page.locator("#b-results li", has_text=title).locator("button").click()
    page.click("#b-cats button:has-text('Playlists')")
    page.wait_for_selector("#b-results li button")
    picks = page.locator("#picks").inner_text()
    check(page.locator("#picks li").count() == 7 and "the Kindle's queue" in picks and "Book 05" in picks and "Book 33 — Audio Author (audiobook)" in picks
          and "FLAC Album" in picks, "coming with the next sync: the Kindle's queue, then the books, audiobook and albums chosen here")
    # the music library chosen on the Kindle (Settings → Connections → Plex): its albums
    page.evaluate("() => { GZSync.K.out.music_library = { key: '4', title: 'Concerts' }; }")
    page.click("#b-cats button:has-text('Albums')")
    page.wait_for_selector("#b-results li:has-text('Live Album')")
    check(page.locator("#b-results li").count() == 1, "Music: Albums from the music library chosen on the Kindle")
    page.evaluate("() => { delete GZSync.K.out.music_library; }")
    # audiobooks from a Plex library (the Kindle's Settings → Connections → Plex → Audiobooks): its albums, chosen like music
    page.evaluate("() => { GZSync.K.out.audiobook_library = { key: '5', title: 'Audiobooks' }; }")
    page.click(".tabs button[data-tab=audio]")
    page.wait_for_selector("#b-results li:has-text('Two Part Book') button")
    cats = page.locator("#b-cats button").all_inner_texts()
    titles = page.locator("#b-results li .txt").all_inner_texts()
    check(cats == ["Recently added", "A–Z", "Authors", "Audiobooks from…"] and len(titles) == 2 and titles[0].startswith("Two Part Book")
          and "Narr Author" in titles[0], "Audiobooks from the Kindle's Plex library: its albums, newest first %r" % (cats,))
    page.locator("#b-results li", has_text="Two Part Book").locator("button").click()
    page.fill("#b-search", "one file")
    page.click("#b-go")
    page.wait_for_function("document.querySelectorAll('#b-results li').length === 1 && document.querySelector('#b-results li').innerText.includes('One File Book')")
    page.click("#b-cats button:has-text('Audiobooks from')")
    page.wait_for_selector("#b-results li.nav:has-text('Plex: Concerts')")
    srcs = page.locator("#b-results li.nav").all_inner_texts()
    check(srcs[0].startswith("Grimmory") and any(x.startswith("Plex: Audiobooks") and "in use" in x for x in srcs) and len(srcs) == 4,
          "Audiobooks from…: Grimmory or the Plex server's music libraries, the one in use marked %r" % (srcs,))
    page.locator("#b-results li.nav", has_text="Grimmory").click()
    page.wait_for_selector("#b-results li:has-text('Book 33')")
    check(page.evaluate("() => GZSync.Browse.plexAudio() === null"), "Audiobooks from Grimmory again, on this page")
    page.evaluate("() => { GZSync.Browse.audioSrc = null; delete GZSync.K.out.audiobook_library; }")
    check("Two Part Book — Narr Author (audiobook)" in page.locator("#picks").inner_text(), "a Plex audiobook in what comes with the next sync")
    page.click("nav.main button[data-panel=sync]")
    page.wait_for_function("document.querySelector('#storage').innerText.includes('free of')")
    st = page.locator("#storage").inner_text()
    check("858 MB free of 1431 MB" in st and "Books:" in st and "next sync brings about" in st, "Sync: room on the Kindle, what's on it, what's coming")

    # a GZreader update (the release, and the file the page can read, served here)
    page.evaluate("""(wp) => {
        GZSync.Update.API = 'http://127.0.0.1:' + wp + '/api/latest.json';
        GZSync.Update.RAW = 'http://127.0.0.1:' + wp + '/updates/';
        return GZSync.Update.check();
    }""", WP)
    page.wait_for_selector("#o-update-row:not(.hidden)")
    check("to 1.30.0 (it has 1.24.0)" in page.locator("#o-update-row").inner_text(),
          "update: a newer GZreader is offered for the Kindle")
    check(page.locator("#o-beta-row:not(.hidden)").count() == 1 and not page.locator("#o-beta").is_checked(),
          "test builds: a choice on the page, off (as on the Kindle)")
    # the files at the updates branch's commit (GitHub's file server keeps each file of a branch on its own)
    sha = "ab12" * 10
    page.route("https://api.github.com/repos/9retirement6irk/GZreader/commits/updates",
               lambda route: route.fulfill(status=200, body=sha if route.request.headers.get("accept") == "application/vnd.github.sha" else "{}"))
    bases = page.evaluate("""async () => {
        var keep = GZSync.Update.RAW, out = [];
        GZSync.Update.RAW = 'https://raw.githubusercontent.com/9retirement6irk/GZreader/updates/';
        out.push(await GZSync.Update.base());
        GZSync.Update.RAW = keep;
        out.push(await GZSync.Update.base());
        return out;
    }""")
    check(bases[0] == "https://raw.githubusercontent.com/9retirement6irk/GZreader/%s/" % sha and bases[1].startswith("http://127.0.0.1:"),
          "update files read at the updates branch's commit (the data and the zip from the same build)")
    page.unroute("https://api.github.com/repos/9retirement6irk/GZreader/commits/updates")
    page.evaluate("(wp) => { GZSync.Update.RAW_BETA = 'http://127.0.0.1:' + wp + '/updates/'; }", WP)
    page.click("#o-beta")
    page.wait_for_function("document.querySelector('#o-update-text').innerText.includes('test build')")
    check("to test build 1.29.0-beta.abc1234 (it has 1.24.0)" in page.locator("#o-update-row").inner_text()
          and page.locator("#update-note").count() == 1,
          "test builds on: the latest test build offered (even with a lower number than the release), one note")
    page.click("#o-beta")
    page.wait_for_function("document.querySelector('#o-update-text').innerText.includes('to 1.30.0')")
    check(page.locator("#update-note").count() == 1, "test builds off again: the release offered")
    cmp = page.evaluate("""() => [GZSync.Update.compare('1.27.0', '1.27.0-beta.5995ce3'), GZSync.Update.compare('1.27.0-beta.5995ce3', '1.27.0'),
        GZSync.Update.offered('1.27.0', '1.27.0-beta.5995ce3'), GZSync.Update.compare('1.27.0', '1.27.0'),
        GZSync.Update.compare('1.10.0', '1.9.2'), GZSync.Update.compare('v1.26.10', '1.27.0-beta.1')]""")
    check(cmp == [1, -1, True, 0, 1, -1],
          "test builds off on a Kindle with a test build of the release's number: the release offered (it was offered nothing) %r" % (cmp,))

    # sleep screen pictures: one added (a wide colour picture), one of the Kindle's taken off, always pictures
    import struct, zlib
    def png(w, h):
        raw = b"".join(b"\x00" + bytes([200, 30, 30]) * w for _ in range(h))
        def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
        return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    pic = os.path.join(web, "My Dog!.png")
    with open(pic, "wb") as f: f.write(png(60, 30))
    page.evaluate("() => GZSync.setPanel('content')")
    page.set_input_files("#ss-files", pic)
    page.wait_for_function("GZSync.Sleep.pending.length === 1")
    ss = page.locator("#ss-list").inner_text()
    check("My Dog.png" in ss and "old.png" in ss and "824 × 1200" in page.locator("#ss-size").inner_text()
          and page.locator('input[name="ss-mode"][value="auto"]').is_checked(),
          "sleep screen pictures: a picture added (made for this Kindle's screen), the Kindle's own listed, its mode shown")
    # an iPhone photo (HEIC, which Chromium can't open): converted by the vendored libheif, in a worker
    # (media/picture.heic: 120 × 60, its left half dark blue, its right half red)
    heic = os.path.join(web, "Beach.HEIC")
    shutil.copy(os.path.join(HERE, "media", "picture.heic"), heic)
    page.set_input_files("#ss-files", heic)
    page.wait_for_function("GZSync.Sleep.pending.length === 2 && !document.querySelector('#ss-add').disabled", timeout=60000)
    got = page.evaluate("""async () => {
      const p = GZSync.Sleep.pending[1], img = await createImageBitmap(p.blob);
      const c = new OffscreenCanvas(img.width, img.height), g = c.getContext('2d'); g.drawImage(img, 0, 0);
      const px = (x, y) => Array.from(g.getImageData(x, y, 1, 1).data);
      return { name: p.name, w: img.width, h: img.height, left: px(200, 600), right: px(620, 600), worker: !!GZSync.Heic.worker };
    }""")
    L, R = got["left"], got["right"]
    check(got["name"] == "Beach.png" and (got["w"], got["h"]) == (824, 1200) and got["worker"]
          and L[0] == L[1] == L[2] and R[0] == R[1] == R[2] and L[0] < 60 and 60 < R[0] < 110,
          "sleep screen pictures: a HEIC photo converted (grey, the screen's size, the blue half darker than the red) %r" % got)
    sniff = page.evaluate("""async (b) => {
      const bytes = Uint8Array.from(atob(b), (c) => c.charCodeAt(0));
      return [await GZSync.Heic.is(new File([bytes], 'IMG_0001', { type: '' })),
              await GZSync.Heic.is(new File([new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13])], 'a.png'))];
    }""", base64.b64encode(open(heic, "rb").read()[:12]).decode())
    check(sniff == [True, False], "HEIC told by its first bytes too (a photo without its .heic name), a PNG isn't")
    broken = os.path.join(web, "broken.heic")
    with open(broken, "wb") as f: f.write(b"\x00\x00\x00\x18ftypheic" + b"\x00" * 64)
    page.set_input_files("#ss-files", broken)
    page.wait_for_function("(document.querySelector('#ss-add').closest('section').querySelector('.err') || {}).innerText", timeout=60000)
    err = page.locator("#ss-add").locator("xpath=ancestor::section").locator(".err").inner_text()
    check("1 HEIC picture couldn't be converted" in err and page.evaluate("GZSync.Sleep.pending.length") == 2,
          "a HEIC that can't be decoded: said so, nothing added (%s)" % err)
    page.locator("#ss-list li", has_text="old.png").locator("button").click()
    page.check('input[name="ss-mode"][value="always"]')
    check("taken off with the sync" in page.locator("#ss-list").inner_text(), "…one of the Kindle's to take off")
    check(page.locator("#ss-immich").is_visible() and page.locator('input[name="ss-mode"][value="immich_auto"]').count() == 1,
          "sleep screen: with an Immich album, its two choices (the cover and Immich, Immich always) are offered too")
    page.evaluate("() => GZSync.setPanel('sync')")
    # Grimmory has places for the books the sync brings (they open there on the Kindle)
    urllib.request.urlopen("http://127.0.0.1:%d/webprogress?book=3&pct=30&cfi=epubcfi(/6/6!/4/2)&href=Text/ch1.xhtml" % (GP + 1)).read()
    urllib.request.urlopen("http://127.0.0.1:%d/webprogress?book=32&pct=60&cfi=50000&href=1" % (GP + 1)).read()
    page.click("#sync")
    page.wait_for_selector("#done:not(.hidden)", timeout=120000)
    log = page.locator("#log").inner_text()
    _days = ["2026-01-01", "2027-01-01", "2027-01-04", "2025-12-29", "2024-12-31", "2026-11-06", "2028-01-02", "2028-06-15"]
    page_weeks = page.evaluate("(ds) => ds.map((s) => { const p = s.split('-').map(Number); return GZSync.isoWeekOfYear(new Date(p[0], p[1] - 1, p[2], 9)); })", _days)
    week_of = []
    for _s in _days:
        _d = datetime.date(*map(int, _s.split("-")))
        _j = datetime.date(_d.year, 1, 1).isoweekday()
        week_of.append(((_d.timetuple().tm_yday - 1) + (_j - 1)) // 7 + (1 if _j <= 4 else 0))
    check(page_weeks == week_of, "reading stats: the page's week numbers match GZreader's around New Year (%s)" % page_weeks)
    print("    (page log)\n      " + log.replace("\n", "\n      "))

    # Send to the developer for a Kindle without Wi-Fi
    def feed():
        return json.loads(urllib.request.urlopen("http://127.0.0.1:%d/feed" % (GP + 1)).read())
    def report_files():
        return page.evaluate("""async () => {
            const sync = await (await (await window.testRoot.getDirectoryHandle('documents')).getDirectoryHandle('GZreader')).getDirectoryHandle('.gzsync');
            const d = await sync.getDirectoryHandle('reports'); const out = []; for await (const n of d.keys()) out.push(n); return out.sort();
        }""")
    sent = feed()
    first = sent[0] if sent else {}
    check(len(sent) == 1 and first.get("_channel") == "testfeed"
          and first.get("eventName") == "Debug report from Kindle2-ab12cd (1/1): Sign-in froze at https://books.example.com/login?password=<redacted>"
          and "What happened: Sign-in froze at https://books.example.com/login?password=<redacted>" in first.get("eventContent", "")
          and "the saved report\u2019s log line" in first.get("eventContent", "") and "hunter2" not in json.dumps(first)
          and first.get("tags") == ["gzreader", "Kindle2-ab12cd", "debug-log", "release", "sync-page", "with-comment"],
          "a report saved on the Kindle: sent at the sync, as a Wi-Fi Kindle sends it (name, comment, tags; a password typed in is redacted)… %r" % ([e.get("eventName") for e in sent],))
    check("Sent to the developer: 1 report" in log and report_files() == ["latest.txt", "report-20261108-101700.txt"],
          "…then deleted from the Kindle (half a report, without its .json, isn't sent) %r" % (report_files(),))
    page.fill("#rep-note", "Sync froze at 40%")
    page.click("#rep-send")
    page.wait_for_function("document.querySelector('#rep-result').innerText !== ''", timeout=30000)
    sent = feed()
    last = sent[-1] if sent else {}
    check(page.locator("#rep-result").inner_text().startswith("Sent to the developer") and len(sent) == 2
          and last.get("eventName") == "Debug report from Kindle2-ab12cd (1/1): Sync froze at 40%"
          and "fresh export line" in last.get("eventContent", "") and "newer log line" not in last.get("eventContent", "")
          and "sync-page" in last.get("tags", []) and report_files() == ["report-20261108-101700.txt"],
          "the page's Send to the developer: the log GZreader exported when Sync was pressed, with what's typed; then deleted")
    page.click("#rep-send")
    page.wait_for_function("!document.querySelector('#rep-send').disabled", timeout=30000)
    sent = feed()
    last = sent[-1] if sent else {}
    content = last.get("eventContent", "")
    check(len(sent) == 3 and "What happened: (nothing typed)" in content and content.index("older log line") < content.index("newer log line")
          and "access_token=<redacted>" in content and "abc123" not in content and "with-comment" not in last.get("tags", []),
          "…without that export: the log files on the drive (crash.log's tail redacted), nothing typed")
    cut = page.evaluate("""() => {
        const text = 'é'.repeat(300000) + 'tail';   // (600 KB of two-byte characters)
        const r = GZSync.Report.parts(text);
        const enc = new TextEncoder();
        return { n: r.parts.length, max: Math.max(...r.parts.map((p) => enc.encode(p).length)), ok: r.parts.join('') === text.slice(text.length - r.parts.join('').length),
                 tail: r.parts[r.parts.length - 1].endsWith('tail'), bytes: enc.encode(r.parts.join('')).length };
    }""")
    check(cut["n"] == 8 and cut["max"] <= 60 * 1024 and cut["ok"] and cut["tail"] and cut["bytes"] <= 480 * 1024,
          "a long log: its newest 480 KB in 60 KB parts, never inside a character (as gzreader_remote.lua) %r" % (cut,))

    # M4B/M4A prepared for the Kindle here: the same files as gzreader_mp4.lua's (short chunks: many of them)
    for src in (os.path.join(HERE, "media", "tone.m4a"), TEST_M4A):
        for secs in (15, 0.25):
            want, want_idx = lua_chunks(src, secs)
            got = page.evaluate("""async ([b64, secs]) => {
                const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)), files = {};
                const keep = GZSync.Mp4.CHUNK_SECONDS; GZSync.Mp4.CHUNK_SECONDS = secs;
                try {
                    const r = await GZSync.Mp4.convert(new Blob([bytes]), async (n, d) => {
                        const b = new Uint8Array(await d.arrayBuffer()); let s = '';
                        for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
                        files[n] = btoa(s);
                    });
                    return { index: GZSync.Mp4.indexJson(r), files };
                } finally { GZSync.Mp4.CHUNK_SECONDS = keep; }
            }""", [base64.b64encode(open(src, "rb").read()).decode(), secs])
            gotf = {k: base64.b64decode(v) for k, v in got["files"].items()}
            check(got["index"] == want_idx and gotf == want and len(want) >= (1 if secs == 15 else 3),
                  "audio prepared in the browser = on the Kindle, byte for byte (%s, %s s chunks: %d files)" % (os.path.basename(src), secs, len(want)))
    fb = page.evaluate("""async () => {
        const junk = new TextEncoder().encode('not an mp4 at all, just bytes');
        const ok = await GZSync.Mp4.bring('in/prep-test', 'x.m4b', new Response(junk).body, null, 'Junk');
        const s = await (await (await window.testRoot.getDirectoryHandle('documents')).getDirectoryHandle('GZreader')).getDirectoryHandle('.gzsync');
        const d = await (await s.getDirectoryHandle('in')).getDirectoryHandle('prep-test');
        const names = []; for await (const n of d.keys()) names.push(n);
        const text = await (await (await d.getFileHandle('x.m4b')).getFile()).text();
        await (await s.getDirectoryHandle('in')).removeEntry('prep-test', { recursive: true });
        return [ok, names, text];
    }""")
    check(fb == [False, ["x.m4b"], "not an mp4 at all, just bytes"],
          "a file that can't be prepared here goes to the Kindle as it is (GZreader prepares it) %r" % (fb,))
    res = page.evaluate("""async () => {
        const root = window.testRoot;
        const files = {};
        async function walk(dir, path) {
            for await (const [name, h] of dir.entries()) {
                const p = path ? path + '/' + name : name;
                if (h.kind === 'directory') await walk(h, p);
                else {
                    const f = await h.getFile();
                    const b = new Uint8Array(await f.arrayBuffer());
                    let s = ''; for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
                    files[p] = btoa(s);
                }
            }
        }
        await walk(root, '');
        return files;
    }""")
    # slim EPUB copies: big pictures made the Kindle's size, everything else byte for byte
    slim_pics = page.evaluate("""async () => {
        async function noise(w, h, type) {
            const c = new OffscreenCanvas(w, h), x = c.getContext('2d'), d = x.createImageData(w, h);
            for (let i = 0; i < d.data.length; i++) d.data[i] = (i % 4 === 3) ? 255 : (Math.random() * 256) | 0;
            x.putImageData(d, 0, 0);
            const b = new Uint8Array(await (await c.convertToBlob({ type, quality: 0.95 })).arrayBuffer());
            let s = ''; for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
            return btoa(s);
        }
        return { big: await noise(1600, 2400, 'image/jpeg'), png: await noise(900, 1400, 'image/png'), small: await noise(60, 60, 'image/jpeg') };
    }""")
    import io as _io
    slim_zb = _io.BytesIO()
    slim_xhtml = ("<html><body>" + "words " * 3000 + "</body></html>").encode()
    with zipfile.ZipFile(slim_zb, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", "<container/>", compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/chapter1.xhtml", slim_xhtml, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/images/scan.jpg", base64.b64decode(slim_pics["big"]), compress_type=zipfile.ZIP_STORED)
        z.writestr("OEBPS/images/plate.png", base64.b64decode(slim_pics["png"]), compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/images/icon.jpg", base64.b64decode(slim_pics["small"]), compress_type=zipfile.ZIP_STORED)
    slim_epub = slim_zb.getvalue()
    slim_res = page.evaluate("""async (b64) => {
        const bin = atob(b64), u = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
        const r = await GZSync.Slim.epub(new Blob([u]), { w: 600, h: 800 });
        const dims = {};
        for (const e of await GZSync.Slim.entries(r.blob)) {
            if (/\.(jpg|png)$/.test(e.name)) { const im = await createImageBitmap(await GZSync.Slim.data(r.blob, e)); dims[e.name] = [im.width, im.height]; }
        }
        const b = new Uint8Array(await r.blob.arrayBuffer());
        let s = ''; for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
        const notZip = await GZSync.Slim.epub(new Blob(['not a zip']), { w: 600, h: 800 });
        return { changed: r.changed, data: btoa(s), dims, notZip: notZip === null };
    }""", base64.b64encode(slim_epub).decode())
    slim_out = base64.b64decode(slim_res["data"])
    with zipfile.ZipFile(_io.BytesIO(slim_out)) as z2, zipfile.ZipFile(_io.BytesIO(slim_epub)) as z1:
        infos = z2.infolist()
        check(z2.testzip() is None and [i.filename for i in infos] == [i.filename for i in z1.infolist()]
              and infos[0].filename == "mimetype" and infos[0].compress_type == zipfile.ZIP_STORED
              and z2.read("mimetype") == b"application/epub+zip", "slim EPUB: a valid zip, same files in the same order, mimetype first and stored")
        check(slim_res["changed"] == 2 and len(slim_out) < len(slim_epub) and z2.read("OEBPS/chapter1.xhtml") == slim_xhtml
              and z2.read("OEBPS/images/icon.jpg") == z1.read("OEBPS/images/icon.jpg"),
              "slim EPUB: the two big pictures replaced; the text and a small picture byte for byte (%d → %d KB)" % (len(slim_epub) // 1024, len(slim_out) // 1024))
        sd = slim_res["dims"]
        check(sd["OEBPS/images/scan.jpg"][0] <= 600 and sd["OEBPS/images/scan.jpg"][1] <= 800 and sd["OEBPS/images/scan.jpg"][1] >= 790
              and sd["OEBPS/images/plate.png"][1] <= 800 and z2.read("OEBPS/images/scan.jpg")[:3] == b"\xff\xd8\xff"
              and z2.read("OEBPS/images/plate.png")[:4] == b"\x89PNG", "slim EPUB: at most the screen's size, a JPEG still a JPEG, a PNG a PNG (%s)" % sd)
        check(slim_res["notZip"], "not a zip: left as it is")
    # test mode (?test): a pretend Kindle in the browser, no drive to choose
    page.goto("about:blank")
    page.evaluate("() => 0")
    page2 = browser.new_page()
    page2.on("pageerror", lambda e: errors.append(str(e)))
    page2.goto("http://127.0.0.1:%d/GZreader/sync/?test" % WP)
    page2.wait_for_selector("#unlock:not(.hidden)")
    page2.click("#test-reset")  # (confirm() is answered by Playwright: dismissed)
    check(page2.locator("#testbar").is_visible() and not page2.locator("#gate").is_visible(),
          "test mode (?test): straight to the pretend Kindle's PIN, the banner says so")
    page2.on("dialog", lambda d: d.accept())
    page2.click("#test-reset")
    page2.wait_for_function("document.querySelector('#unlock-title').innerText.includes('Choose a PIN') && document.activeElement.id === 'pin'")
    page2.wait_for_timeout(300)
    page2.fill("#pin", "0000"); page2.fill("#pin2", "0000"); page2.click("#unlock-go")
    page2.wait_for_selector("#app:not(.hidden)")
    check(page2.locator("#k-name").inner_text() == "Pretend Kindle" and page2.locator("#c-grimmory.on").count() == 0,
          "test mode: started over, a fresh pretend Kindle to set up")
    browser.close()

files = {k: base64.b64decode(v) for k, v in res.items()}
G = "documents/GZreader/.gzsync/"
inbox = json.loads(files.get(G + "inbox.json", b"{}"))
lib = json.loads(files.get(G + "library.json", b"{}"))
state = json.loads(urllib.request.urlopen("http://127.0.0.1:%d/" % (GP + 1)).read())

check(inbox.get("update", {}).get("version") == "1.30.0" and files.get(G + inbox["update"]["file"]) == UPD
      and inbox["update"]["size"] == len(UPD), "update: brought (checked against its size and SHA-256), for GZreader to install")
check(inbox.get("test_builds") is False and inbox["update"].get("beta") is False,
      "test builds switched off on the page: the Kindle is told (it remembers it in its update settings)")
check(any(b["id"] == 5 for b in inbox.get("books", [])) and any(a["id"] == 33 for a in inbox.get("audiobooks", [])),
      "what was chosen on the page came too (a book and an audiobook)")
marks = lib.get("marks", {}).get("1", {})
hl = [a for a in state["annotations"] if a["text"] == "Hello"]
check(set(inbox.get("created", {})) == {"usb-1", "usb-2"} and hl and hl[0]["note"] == "from the Kindle" and hl[0]["color"] == "#F87171"
      and any(b.get("title") == "Kindle" for b in state["bookmarks"]) and {"m:1", "m:2", "m:3", "m:4"} <= set(inbox["done"]),
      "bookmarks and highlights: made, changed (by their new ids) and deleted on Grimmory; the new ids for the Kindle")
check(any(a.get("note") == "from the Kindle" for a in marks.get("annotations", [])) and any(b.get("title") == "Kindle" for b in marks.get("bookmarks", [])),
      "…and the books' bookmarks and highlights in the copy, for GZreader to merge")
check(not errors, "no script errors" + ("" if not errors else ": " + "; ".join(errors)))
check(set(inbox.get("done", [])) >= {"p:1:7", "s:1:2026-11-05T10:00:00Z", "r:2:4"},
      "jobs: positions, reading time and ratings reported done")
check(state["progress"].get("1", {}).get("progressPercent") == 42.5 and state["progress"]["1"]["positionData"] == "epubcfi(/6/4!/4/2)"
      and any(s["durationSeconds"] == 1800 for s in state["sessions"]) and state["ratings"].get("2") == 8,
      "Grimmory got the position (with its CFI), the reading time and the rating")
own = {str(x["id"]): x.get("own") for x in lib.get("shelves", []) if not x.get("magic")}
check({"sh:3:5", "sh:5:6"} <= set(inbox.get("done", [])) and 3 in state["shelves"]["6"] and 5 not in state["shelves"]["7"]
      and 3 in lib["lists"]["shelf"].get("6", []),
      "shelves: the book put on a shelf on the Kindle is on it in Grimmory and in the copy; someone else's shelf: refused, done")
check(own == {"4": True, "6": True, "7": False}, "library copy: your own shelves marked (someone else's public one not) " + str(own))
check(any(f["id"] == "p:999:3" and f["error"].startswith("http_4") for f in inbox.get("failed", [])),
      "a position for a book Grimmory doesn't have: refused, reported (the Kindle drops it)")
check(len(lib.get("books", [])) == 35 and lib["server"] == "http://127.0.0.1:%d" % GP and "1" in lib.get("full", {})
      and lib["full"]["1"].get("epubProgress", {}).get("percentage") == 42.5 and lib["lists"]["shelf"].get("4") == [10, 11, 12]
      and lib.get("subtitles", {}).get("3") == "Old School" and len(lib["libraries"]) == 3,
      "library copy: every book, shelves, the books on the Kindle with their places, subtitles")
covers = [k for k in files if k.startswith(G + "covers/") and k.endswith(".jpg")]
small = files.get(G + "covers/1.jpg", b"")
check(len(covers) == 33 and small[:2] == b"\xff\xd8" and len(small) < 5664 and G + "covers/34.jpg" not in files,
      "small covers: the EPUBs' own and the audiobooks' (Grimmory's can't be read by a web page; PDFs have none), shrunk JPEGs")
details = [k for k in files if k.startswith(G + "details/")]
check(len(details) == 35, "book pages: one per book")
book = next((b for b in inbox.get("books", []) if b["id"] == 3), None)
check(book and files.get(G + book["file"], b"").startswith(b"PK\x03\x04") and book["name"] == "book3.epub" and book["subtitle"] == "Old School",
      "the sync queue: the book, under in/")
check(book and (book.get("progress") or {}).get("epubProgress", {}).get("percentage") == 30.0,
      "the sync queue: the book's place on Grimmory goes with it (it opens there)")
ab = next((a for a in inbox.get("audiobooks", []) if a["id"] == 32), None)
check(ab and G + ab["dir"] + "/track-001.mp3" in files and G + ab["dir"] + "/track-002.mp3" in files
      and G + ab["dir"] + "/cover.jpg" in files and ab["info"]["folderBased"] and "folder" in (ab["info"].get("gz_description") or ""),
      "the sync queue: the audiobook's tracks, named as GZreader names them, its cover and description")
check(ab and (ab.get("progress") or {}).get("audiobookProgress", {}).get("positionMs") == 50000,
      "the sync queue: the audiobook's place on Grimmory too")
gs = inbox.get("grimmory_stats") or {}
gv = gs.get("values") or {}
check(gv.get("reading_days", 0) >= 1 and gv.get("week_time", 0) >= 1800 and gv.get("year_finished") == 3 and "streak" in gv
      and abs(gs.get("at", 0) - time.time()) < 600,
      "reading stats for the Kindle's Home widget, with this sync's session in")
import datetime
def iso_week(d):  # (Grimmory's WeekFields.ISO.weekOfYear(), as gzreader_grimstats.lua counts it)
    jan1 = datetime.date(d.year, 1, 1).isoweekday()
    days = (d.timetuple().tm_yday - 1) + (jan1 - 1)
    return days // 7 + (1 if jan1 <= 4 else 0)
_today = datetime.date.today()
check(state.get("last_timeline_query") == "year=%d&week=%d" % (_today.year, iso_week(_today)),
      "reading stats: this week as Grimmory counts weeks (%s)" % state.get("last_timeline_query"))
check("s:1:1970-01-01T02:11:00Z" in inbox.get("done", []) and not any(x["durationSeconds"] == 1799 for x in state["sessions"]),
      "reading time recorded while the Kindle's clock said 1970: not sent to Grimmory (dropped on the Kindle)")
sst = inbox.get("screensavers") or {}
added = (sst.get("add") or [{}])[0]
pdata = files.get(G + added.get("file", "-"), b"")
pw, ph = struct.unpack(">II", pdata[16:24]) if pdata[:8] == b"\x89PNG\r\n\x1a\n" else (0, 0)
check(added.get("name") == "My Dog.png" and added.get("file", "").startswith("in/screensavers/") and (pw, ph) == (824, 1200)
      and sst.get("remove") == ["old.png"] and sst.get("mode") == "always",
      "sleep screen pictures: brought as a PNG the screen's size, with what to take off and when they show")
added2 = (sst.get("add") or [{}, {}])[1:2] or [{}]
pdata2 = files.get(G + added2[0].get("file", "-"), b"")
check(added2[0].get("name") == "Beach.png" and len(sst.get("add") or []) == 2 and pdata2[:8] == b"\x89PNG\r\n\x1a\n"
      and struct.unpack(">II", pdata2[16:24]) == (824, 1200),
      "sleep screen pictures: the HEIC photo brought as a PNG too")
im = inbox.get("immich") or {}
iadd = im.get("add") or []
idata = [files.get(G + a.get("file", "-"), b"") for a in iadd]
isizes = [struct.unpack(">II", d[16:24]) if d[:8] == b"\x89PNG\r\n\x1a\n" else (0, 0) for d in idata]
check(len(iadd) == 10 and all(a["file"] == "in/immich/%s.png" % a["id"] for a in iadd) and all(320 <= w <= 326 and 200 <= h <= 204 for w, h in isizes)
      and (im.get("album") or {}).get("id") == immich_uid(1, "b") and im["album"].get("count") == 30 and im.get("keep") == [] and im.get("count") == 10
      and im.get("wallpaper") is True and "immich-test-key" not in json.dumps(inbox),
      "Immich: 10 of the album's photos made for this screen (fitted inside it, never bigger), the album, the wallpaper; not the key %r" % (isizes[:2],))
istate = json.loads(urllib.request.urlopen("http://127.0.0.1:%d/__state" % IP).read())
isearch = [r for r in istate["log"] if r["path"] == "/api/search/metadata" and r["key"] == "ok"]
check(isearch and isearch[-1]["body"]["albumIds"] == [immich_uid(1, "b")] and isearch[-1]["body"]["type"] == "IMAGE"
      and len([r for r in istate["log"] if "/thumbnail?size=preview" in r["path"] and r["key"] == "ok"]) == 10,
      "Immich: the album's photos found with its search, 10 previews asked for, all with the API key")
check("Immich: 10 new pictures" in log, "the sync's log says what came from Immich")
usage = state.get("usage", [])
check(len(usage) == 0 and not [k for k in files if k.startswith(G + "usage/")],
      "usage statistics an older GZreader left: deleted, not sent (GZreader sends none since 1.28.1)")
mus = {m["key"]: m for m in inbox.get("music", [])}
def col(key):
    m = mus.get(key)
    return m and json.loads(files.get(G + m["dir"] + "/music.json", b"{}"))
c1, c2, c3 = col("201"), col("202"), col("203")
check(c1 and [t["file"] for t in c1["tracks"]] == ["01.mp3", "02.mp3"] and G + mus["201"]["dir"] + "/cover.jpg" in files,
      "music: an MP3 album, with its cover (one track made smaller: see the music quality check)")
want, want_idx = lua_chunks(os.path.join(HERE, "media", "tone.m4a"))
d2 = c2 and G + mus["202"]["dir"] + "/01.m4a.chunks/"
check(c2 and c2["tracks"][0]["file"] == "01.m4a" and G + mus["202"]["dir"] + "/01.m4a" not in files
      and files.get(d2 + "index.json", b"").decode() == want_idx and all(files.get(d2 + n) == b for n, b in want.items()),
      "music: AAC in M4A prepared for the Kindle here (its chunks, not the M4A)")
ab33 = next((a for a in inbox.get("audiobooks", []) if a["id"] == 33), None)
want, want_idx = lua_chunks(TEST_M4A)
d33 = ab33 and G + ab33["dir"] + "/audiobook.m4b.chunks/"
check(ab33 and G + ab33["dir"] + "/audiobook.m4b" not in files and files.get(d33 + "index.json", b"").decode() == want_idx
      and all(files.get(d33 + n) == b for n, b in want.items()),
      "audiobook: the M4B prepared for the Kindle here (its chunks, not the M4B)")
check(not [k for k in files if k.startswith("gzsync-prepare/")], "…and nothing left in the browser's own storage")
abp = next((a for a in inbox.get("audiobooks", []) if a["id"] == "plex-206"), None)
abi = (abp or {}).get("info") or {}
check(abp and [t["fileName"] for t in abi.get("tracks", [])] == ["track.mp3", "track.mp3"] and abi.get("plexKey") == "206"
      and abi["tracks"][1]["cumulativeStartMs"] == 3000 and abi["tracks"][1]["plexKey"] == "307" and abi.get("folderBased")
      and files.get(G + abp["dir"] + "/track-002.mp3") == open(os.path.join(HERE, "media", "tone.mp3"), "rb").read()
      and G + abp["dir"] + "/cover.jpg" in files and abi.get("gz_description") == "<p>A book in two parts.</p>",
      "a Plex audiobook: its tracks as the book's files, laid out as the Kindle's own Plex download")
f3 = c3 and c3["tracks"][0].get("file")
check(f3 and files.get(G + mus["203"]["dir"] + "/" + f3, b"")[:3] in (b"ID3", b"\xff\xfb", b"\xff\xf3", b"\xff\xfa") or (f3 and len(files.get(G + mus["203"]["dir"] + "/" + f3, b"")) > 1000),
      "music: FLAC made into MP3 by Plex, its MPEG-TS taken apart in the browser")
tc = {p: b for p, b in json.loads(urllib.request.urlopen("http://127.0.0.1:%d/ctl/transcodes" % PP).read())}
check(tc == {"/library/metadata/301": "192", "/library/metadata/304": "192"} and inbox.get("music_quality") == {"bitrate": 192, "shrink": True},
      "music quality chosen on the page: FLAC and the 320 kbps MP3 converted at 192 kbps; the 200 kbps MP3 as it is; the Kindle told %r" % (tc,))
notes = json.loads(files.get(G + "in/notes.json", b"{}"))
memos = json.loads(urllib.request.urlopen("http://127.0.0.1:%d/__state" % MP).read())
check(inbox.get("notes", {}).get("done") == ["q1", "q2", "q3"] and any("Written on the Kindle" in (m.get("content") or "") for m in memos.get("memos", memos if isinstance(memos, list) else [])),
      "notes: the one written on the Kindle is in Memos")
by_content = {m.get("content"): m for m in memos.get("memos", [])}
check("space" not in by_content.get("Written on the Kindle #kindle", {"space": 1})
      and by_content.get("For the family #kindle", {}).get("space") == "spaces/family"
      and by_content.get("For the family #kindle", {}).get("visibility") == "SPACE"
      and by_content.get("A quote for the book club #quotes", {}).get("space") == "spaces/book-club",
      "notes: a note's space from the Kindle (a new note in Family, one moved to Book club; none sent for a note in no space)")
check([sp.get("title") for sp in notes.get("spaces") or []] == ["Family", "Book club"]
      and any(n.get("space") == "spaces/family" for n in notes.get("notes", [])),
      "notes: your spaces and each note's space, for the Kindle")
check(len(notes.get("notes", [])) >= 3 and any(f.startswith(G + "in/notes-files/") for f in files),
      "notes: the notes and their pictures, for the Kindle")
cals = inbox.get("calendars", [])
check(len(cals) == 2 and cals[0]["name"] == "Family" and b"Dentist" in files.get(G + cals[0]["file"], b"") and cals[1]["file"] is None,
      "calendars: a link brought; one that fails is listed without events")
check("http://127.0.0.1:%d/family.ics" % WP not in log and "missing.ics" not in log, "calendar links (secret keys) never shown in full")
check(not any(t in json.dumps(inbox) + json.dumps(lib) for t in ("hunter22", "memos-test-token", "srv-token", "plex-token")),
      "nothing secret written to the Kindle")

if DUMP:
    for k, v in files.items():
        if not k.startswith("documents/GZreader/"):
            continue
        p = os.path.join(DUMP, k[len("documents/GZreader/"):])
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(v)

for p in procs:
    p.terminate()
srv.shutdown()
print("\n%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
