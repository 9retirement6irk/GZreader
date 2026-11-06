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
port+22 the page.
"""
import base64, json, os, subprocess, sys, tempfile, threading, time, urllib.request
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18500
DUMP = sys.argv[2] if len(sys.argv) > 2 else None
GP, MP, PP, WP = PORT, PORT + 20, PORT + 21, PORT + 22

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

spawn(os.path.join(HERE, "mock_grimmory.py"), str(GP))
spawn(os.path.join(REPO, "tools", "gzreader", "emulator", "demo", "mock_memos.py"), str(MP), "--sample")
spawn(os.path.join(HERE, "mock_plex.py"), str(PP))

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
class Quiet(SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
srv = ThreadingHTTPServer(("127.0.0.1", WP), partial(Quiet, directory=web))
threading.Thread(target=srv.serve_forever, daemon=True).start()
for p in (GP, MP, PP):
    wait_port(p)

OUTBOX = {
    "format": 1, "written_at": int(now), "gzreader": "1.24.0",
    "kindle": {"model": "Kindle2", "name": "Kindle 2 · 3F2A", "id": "3f2a01", "audio": True},
    "grimmory": {"server": "http://127.0.0.1:%d" % GP, "user": "will"},
    "jobs": [
        {"id": "p:1:7", "kind": "progress", "book": 1, "method": "PUT", "path": "/api/v1/app/books/1/progress",
         "body": {"fileProgress": {"bookFileId": 1001, "progressPercent": 42.5, "positionHref": "ch2.xhtml", "positionData": "epubcfi(/6/4!/4/2)"}}},
        {"id": "s:1:2026-11-05T10:00:00Z", "kind": "session", "book": 1, "method": "POST", "path": "/api/v1/reading-sessions",
         "body": {"bookId": 1, "bookType": "EPUB", "startTime": "2026-11-05T10:00:00Z", "endTime": "2026-11-05T10:30:00Z", "durationSeconds": 1800}},
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
    ],
    "disk": {"total": 1500000000, "available": 900000000},
    "queue": [
        {"id": 3, "kind": "book", "title": "Book 03", "authors": ["Author 0"], "format": "EPUB", "file_id": 1003, "name": "book3.epub", "size_kb": 300},
        {"id": 32, "kind": "audiobook", "title": "Book 32", "format": "AUDIOBOOK", "name": "book32.audiobook", "size_kb": 12},
    ],
    # (empty lists as GZreader 1.24 on a Kindle wrote them: {}, KOReader's JSON)
    "have": {"books": {"1": {"file_id": 1001, "format": "EPUB"}}, "audiobooks": {}, "music": ["album-999"]},
    "notes": {"queue": [{"id": "q1", "op": "create", "content": "Written on the Kindle #kindle", "visibility": "PRIVATE"}],
              "keep": 100, "files": {}},
    "calendar": {"days_back": 14, "days_ahead": 90},
}

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
    page.evaluate("""async (outbox) => {
        const root = await navigator.storage.getDirectory();
        for await (const name of root.keys()) await root.removeEntry(name, { recursive: true });
        const gz = await (await root.getDirectoryHandle('documents', { create: true })).getDirectoryHandle('GZreader', { create: true });
        const sync = await gz.getDirectoryHandle('.gzsync', { create: true });
        const w = await (await sync.getFileHandle('outbox.json', { create: true })).createWritable();
        await w.write(JSON.stringify(outbox)); await w.close();
        window.testRoot = root;
    }""", OUTBOX)
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
    check("Kindle 2 · 3F2A" in page.locator("#k-name").inner_text() and "8 reading updates" in page.locator("#k-sub").inner_text()
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
    check(all(t not in keys for t in ("hunter22", "memos-test-token", "plex-token", "family.ics", "127.0.0.1")) and json.loads(keys)["cipher"] == "AES-256-GCM"
          and not page.evaluate("() => Object.keys(localStorage).filter(k => k.startsWith('gzsync.') && k !== 'gzsync.sso').length"),
          "the sign-ins are on the Kindle, encrypted with its PIN (and not in the browser)")

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

    page.click("#sync")
    page.wait_for_selector("#done:not(.hidden)", timeout=120000)
    log = page.locator("#log").inner_text()
    print("    (page log)\n      " + log.replace("\n", "\n      "))

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
ab = next((a for a in inbox.get("audiobooks", []) if a["id"] == 32), None)
check(ab and G + ab["dir"] + "/track-001.mp3" in files and G + ab["dir"] + "/track-002.mp3" in files
      and G + ab["dir"] + "/cover.jpg" in files and ab["info"]["folderBased"] and "folder" in (ab["info"].get("gz_description") or ""),
      "the sync queue: the audiobook's tracks, named as GZreader names them, its cover and description")
mus = {m["key"]: m for m in inbox.get("music", [])}
def col(key):
    m = mus.get(key)
    return m and json.loads(files.get(G + m["dir"] + "/music.json", b"{}"))
c1, c2, c3 = col("201"), col("202"), col("203")
check(c1 and [t["file"] for t in c1["tracks"]] == ["01.mp3", "02.mp3"] and G + mus["201"]["dir"] + "/cover.jpg" in files,
      "music: an MP3 album as it is, with its cover")
check(c2 and c2["tracks"][0]["file"] == "01.m4a", "music: AAC in M4A as it is (the Kindle converts it)")
f3 = c3 and c3["tracks"][0].get("file")
check(f3 and files.get(G + mus["203"]["dir"] + "/" + f3, b"")[:3] in (b"ID3", b"\xff\xfb", b"\xff\xf3", b"\xff\xfa") or (f3 and len(files.get(G + mus["203"]["dir"] + "/" + f3, b"")) > 1000),
      "music: FLAC made into MP3 by Plex, its MPEG-TS taken apart in the browser")
notes = json.loads(files.get(G + "in/notes.json", b"{}"))
memos = json.loads(urllib.request.urlopen("http://127.0.0.1:%d/__state" % MP).read())
check(inbox.get("notes", {}).get("done") == ["q1"] and any("Written on the Kindle" in (m.get("content") or "") for m in memos.get("memos", memos if isinstance(memos, list) else [])),
      "notes: the one written on the Kindle is in Memos")
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
