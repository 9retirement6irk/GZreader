#!/usr/bin/env python3
"""The setup page (docs/setup) in a real browser: jailbreak steps and GZreader.

  setup_page_test.py <port>

Chromium (Playwright) opens the page in its test mode (?test): a folder in the
browser's private storage (OPFS) stands in for the Kindle's drive. A local
server serves docs/ and, under /raw/, stand-ins for the updates branch's
packages.json and GZreader packages (small zips). The test plants files on the
pretend drive (an old .bin, KUAL, Launchpad's screenshot, kual-dx-fix's log)
where a real Kindle would, and checks what the page puts there at each step.
"""
import hashlib, io, json, os, re, sys, tempfile, threading, zipfile
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
DOCS = os.path.join(REPO, "docs")
FILES = os.path.join(DOCS, "setup", "files")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18563

passed = failed = 0
def check(cond, name):
    global passed, failed
    if cond:
        passed += 1; print("  ok   " + name)
    else:
        failed += 1; print("  FAIL " + name)


def make_zip(files):
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in files.items():
            z.writestr(name, data)
    return b.getvalue()


def package(flavour):
    files = {
        "koreader/gzreader-version": "1.27.0\n",
        "koreader/plugins/gzreader.koplugin/main.lua": "-- GZreader (" + flavour + ")\n",
        "koreader/reader.lua": "-- KOReader\n",
        "extensions/koreader/config.xml": "<extension/>\n",
    }
    if flavour == "kindle-legacy":
        files["launchpad/koreader.ini"] = "[Actions]\nG G = !sh /mnt/us/koreader/koreader.sh\n"
    else:
        files["documents/GZreader.sh"] = "#!/bin/sh\n"
    return make_zip(files)


RAW = tempfile.mkdtemp(prefix="gzsetup-raw-")
meta = {"version": "1.27.0", "packages": {}}
for fl in ("kindle-legacy", "kindle", "kindlepw2", "kindlehf"):
    data = package(fl)
    open(os.path.join(RAW, "gzreader-%s.zip" % fl), "wb").write(data)
    meta["packages"][fl] = {"file": "gzreader-%s.zip" % fl, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
open(os.path.join(RAW, "packages.json"), "w").write(json.dumps(meta))


class Handler(SimpleHTTPRequestHandler):
    def translate_path(self, path):
        p = path.split("?", 1)[0]
        if p.startswith("/raw/"):
            return os.path.join(RAW, p[len("/raw/"):])
        return SimpleHTTPRequestHandler.translate_path(self, path)

    def log_message(self, *a):
        pass


def serve():
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), partial(Handler, directory=DOCS))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


# helpers that run in the page: the pretend drive
JS = r"""
window.T = {
  root: async function () { return (await navigator.storage.getDirectory()).getDirectoryHandle("gzsetup-kindle", { create: true }); },
  at: async function (path, create) {
    var d = await T.root(), parts = path.split("/"), name = parts.pop();
    for (var p of parts) d = await d.getDirectoryHandle(p, { create: !!create });
    return { d: d, name: name };
  },
  put: async function (path, text) {
    var x = await T.at(path, true), w = await (await x.d.getFileHandle(x.name, { create: true })).createWritable();
    await w.write(text); await w.close();
  },
  mkdir: async function (path) { var x = await T.at(path + "/x", true); return true; },
  read: async function (path) {
    try { var x = await T.at(path); return await (await (await x.d.getFileHandle(x.name)).getFile()).text(); } catch (e) { return null; }
  },
  sha: async function (path) {
    try {
      var x = await T.at(path), buf = await (await (await x.d.getFileHandle(x.name)).getFile()).arrayBuffer();
      var d = new Uint8Array(await crypto.subtle.digest("SHA-256", buf));
      return Array.from(d).map(function (b) { return ("0" + b.toString(16)).slice(-2); }).join("");
    } catch (e) { return null; }
  },
  has: async function (path) { return (await T.read(path)) !== null; },
  isDir: async function (path) { try { var x = await T.at(path + "/x"); return true; } catch (e) { return false; } },
  rm: async function (path) { try { var x = await T.at(path); await x.d.removeEntry(x.name, { recursive: true }); } catch (e) {} },
  ls: async function (path) {
    var d = await T.root();
    if (path) for (var p of path.split("/")) d = await d.getDirectoryHandle(p);
    var out = []; for await (var h of d.values()) out.push(h.name); return out.sort();
  },
  wipe: async function () { try { await (await navigator.storage.getDirectory()).removeEntry("gzsetup-kindle", { recursive: true }); } catch (e) {} },
};
"""


def sha_file(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def main():
    from playwright.sync_api import sync_playwright
    srv = serve()
    base = "http://127.0.0.1:%d/setup/?test&raw=http://127.0.0.1:%d/raw/" % (PORT, PORT)

    print("the page's own files")
    html = open(os.path.join(DOCS, "setup", "index.html")).read()
    js = open(os.path.join(DOCS, "setup", "setup.js"), "rb").read()
    m = re.search(r'setup\.js\?v=([0-9a-f]+)', html)
    check(m and m.group(1) == hashlib.sha256(js).hexdigest()[:10],
          "setup.js?v= is the script's SHA-256 (first 10): " + hashlib.sha256(js).hexdigest()[:10])
    bundled = dict(re.findall(r'"([\w.-]+/[\w./-]+)": \[(\d+), ', js.decode()))
    shas = dict(re.findall(r'"([\w.-]+/[\w./-]+)": \[\d+, "([0-9a-f]{64})"\]', js.decode()))
    ok = bool(bundled)
    for path, size in bundled.items():
        f = os.path.join(FILES, path)
        if not os.path.isfile(f) or os.path.getsize(f) != int(size) or (path in shas and sha_file(f) != shas[path]):
            ok = False; print("    (%s: missing, or not the size/SHA-256 in BUNDLED)" % path)
    check(ok and len(bundled) >= 18, "every file in BUNDLED is in docs/setup/files with its size and SHA-256 (%d files)" % len(bundled))
    readme = open(os.path.join(FILES, "README.md")).read()
    check(all(d in readme for d in ("jailbreak-0.13.N/", "hotfix/", "winterbreak/", "kual-dx-fix/"))
          and all(os.path.isfile(os.path.join(FILES, p)) for p in ("jailbreak-0.13.N/LICENSE.txt", "hotfix/LICENSE.txt",
                  "winterbreak/LICENSE-WinterBreak.txt", "winterbreak/LICENSE-Mesquito.txt")),
          "files/README.md lists each bundled folder, and their licences are there")
    check(not re.search(r"https?://(?!(raw\.githubusercontent\.com|github\.com|kindlemodding\.org|www\.mobileread\.com|9retirement6irk\.github\.io|penguins184\.xyz)[/\"])[\w.-]+",
                        js.decode().replace("http://127.0.0.1", "")),
          "setup.js talks only to GitHub, kindlemodding.org, MobileRead (links) and WinterBreak2's page")

    with sync_playwright() as p:
        browser = p.chromium.launch()
        ctx = browser.new_context()
        page = ctx.new_page()
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.add_init_script(JS)

        def fresh(plant=None):
            page.goto(base)
            page.evaluate("async () => { localStorage.removeItem('gzsetup'); await T.wipe(); }")
            page.goto(base)
            page.wait_for_function("window.GZSetup && window.T")
            page.evaluate("async () => { await T.mkdir('documents'); await T.mkdir('system'); }")
            if plant:
                page.evaluate(plant)
            page.click("#pick")
            page.wait_for_selector("#kindle-card:not(.hidden)")

        def ev(expr):
            return page.evaluate(expr)

        def steps():
            return ev("() => Array.from(document.querySelectorAll('#step-list li')).map(li => li.dataset.step)")

        def goto_step(sid):
            page.click('#step-list li[data-step="%s"] button' % sid)
            page.wait_for_selector('#steps[data-step="%s"]' % sid)

        def drop(name, data, which="#steps .act input[type=file]"):
            page.set_input_files(which, files=[{"name": name, "mimeType": "application/octet-stream", "buffer": data}])

        def out_text():
            return ev("() => (document.querySelector('#steps .out') || {}).textContent || ''")

        print("serial numbers, firmware, jailbreaks (the page's own logic)")
        page.goto(base)
        page.wait_for_function("window.GZSetup")
        r = ev("""() => { const G = GZSetup, m = s => { const r = G.modelFromSerial(s); return r.error !== undefined ? 'error' : r.model.id + ':' + (r.sfx || '') + ':' + r.name; };
          return [m('B009 1234'), m('B004'), m('B005ab'), m('B00E'), m('9023'), m('B0080000'), m('B00A'), m('G090G1'), m('G0910L12'),
                  m('B0'), m('ZZZZ'), m('G09'), m('B0ZZ')]; }""")
        check(r[:9] == ["DX:dxg:Kindle DX Graphite", "DX:dx:Kindle DX", "DX:dxi:Kindle DX International", "K4::Kindle 4", "K4::Kindle 4",
                        "K3:k3w:Kindle Keyboard (3)", "K3:k3gb:Kindle Keyboard (3)", "PW3::Kindle Paperwhite 3", "KT4::Kindle (10th generation)"],
              "serials: B009 → DX Graphite, B004 DX, B005 DX International, B00E/9023 Kindle 4, B008/B00A Kindle Keyboard, G090G1 Paperwhite 3, G0910L Kindle 10 (%s)" % r[:9])
        check(r[9:] == ["error"] * 4, "too short or unknown serials are refused (%s)" % r[9:])
        r = ev("""() => { const G = GZSetup; return [G.legacyJailbreak('k3w', '3.2'), G.legacyJailbreak('k3w', '3.2.1'), G.legacyJailbreak('k3g', '3.0.3'),
                   G.legacyJailbreak('k3gb', '3.4.3'), G.legacyJailbreak('dxg', ''), G.legacyJailbreak('k2i', '2.5.8')]; }""")
        check(r == ["Update_jailbreak_k3w_3.0-to-3.2_install.bin", "Update_jailbreak_k3w_install.bin", "Update_jailbreak_k3g_3.0-to-3.2_install.bin",
                    "Update_jailbreak_k3gb_install.bin", "Update_jailbreak_dxg_install.bin", "Update_jailbreak_k2i_install.bin"],
              "Kindle Keyboard 3.2 and older takes the -3.0-to-3.2 file, 3.2.1 and newer the other (as the jailbreak's README says; %s)" % r[:2])
        r = ev("""() => { const G = GZSetup, M = id => ({ id: id, family: 'touch' }), names = (id, fw, reg, ads) => G.methodsFor(id, fw, reg, ads).map(m => m.name);
          return { pw3: G.packageFor(M('PW3'), '5.16.2.1.1'), pw3hf: G.packageFor(M('PW3'), '5.16.3'), pw5: G.packageFor(M('PW5'), '5.18.1'),
                   k4: G.packageFor({ pkg: 'kindle' }, ''), legacy: G.packageFor({ pkg: 'kindle-legacy' }, ''),
                   a: names('PW3', '5.16.2.1.1', true, false), b: names('PW3', '5.16.2.1.1', false, false), c: names('PW5', '5.18.1', true, false),
                   d: names('PW5', '5.18.1', true, true), e: names('PW6', '5.21.0', true, true), f: names('PW4', '5.16.5', null, null),
                   g: G.cmpVer('5.16.10', '5.16.9'), h: G.cmpVer('5.16.2.1.1', '5.16.3') }; }""")
        check(r["pw3"] == "kindlepw2" and r["pw3hf"] == "kindlehf" and r["pw5"] == "kindlehf" and r["k4"] == "kindle" and r["legacy"] == "kindle-legacy",
              "packages: firmware before 5.16.3 kindlepw2, from 5.16.3 kindlehf; Kindle 4/Touch kindle; Kindle 2/3/DX kindle-legacy")
        check(r["a"] == ["WinterBreak2", "WinterBreak"] and r["b"] == ["WinterBreak2"],
              "Paperwhite 3 on 5.16.2.1.1: WinterBreak2 first, WinterBreak only if it can be registered (%s, %s)" % (r["a"], r["b"]))
        check(r["c"][:1] == ["SpiderCat"] and "SpringBreak" in r["c"] and "AdBreak" not in r["c"] and "AdBreak" in r["d"],
              "Paperwhite 5 on 5.18.1: SpiderCat first; AdBreak only with ads (%s / %s)" % (r["c"], r["d"]))
        check(r["e"] == [] and "WinterBreak2" in r["f"] and "Sanctuary" not in r["f"],
              "no jailbreak for a firmware nothing handles; 5.16.5's exceptions (WinterBreak2 yes, Sanctuary no): %s" % r["f"])
        check(r["g"] == 1 and r["h"] == -1, "firmware versions compare as numbers (5.16.10 > 5.16.9)")

        print("a Kindle DX Graphite, from nothing to GZreader")
        fresh("async () => { await T.put('update.bin.tmp.partial', 'x'); await T.put('Update_old_install.bin', 'x');"
              " await T.put('documents/My Book.mobi', 'book'); }")
        check("Kindle drive connected" in ev("() => document.querySelector('#drive-status').textContent"), "the pretend Kindle is taken for a Kindle")
        page.fill("#serial", "B009ABCDEFGH")
        page.wait_for_selector("#steps-card:not(.hidden)")
        check(ev("() => document.querySelector('#jb-no').checked"), "nothing on the drive says jailbroken: \"No, jailbreak it first\"")
        check(steps() == ["wireless", "clean", "jailbreak", "launchpad", "gzreader", "kualfix"],
              "the steps: wireless off, old update files, jailbreak, Launchpad, GZreader, KUAL (optional): %s" % steps())
        goto_step("clean")
        check("update.bin.tmp.partial" in ev("() => document.querySelector('#steps .act').textContent"), "the old update files are listed")
        page.click("#steps #do")
        page.wait_for_function("() => (document.querySelector('#steps .out') || {}).textContent.includes('Looks right')")
        check(not ev("() => T.has('update.bin.tmp.partial')") and not ev("() => T.has('Update_old_install.bin')")
              and ev("() => T.has('documents/My Book.mobi')"), "removed (the books stay)")
        goto_step("jailbreak")
        check("Update_jailbreak_dxg_install.bin" in ev("() => document.querySelector('#steps').textContent")
              and "U006" in ev("() => document.querySelector('#steps').textContent"), "the jailbreak step names the DXG's file and says U006 is normal")
        page.click("#steps #do")
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('On the Kindle')")
        check(ev("() => T.sha('Update_jailbreak_dxg_install.bin')") == sha_file(os.path.join(FILES, "jailbreak-0.13.N/Update_jailbreak_dxg_install.bin")),
              "Update_jailbreak_dxg_install.bin on the drive, the bundled file byte for byte")
        goto_step("launchpad")
        drop("something.zip", make_zip({"readme.txt": "no"}))
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.length > 0")
        check("has no update_launchpad_0.0.1d_dxg_install.bin" in out_text() and not ev("() => T.has('update_launchpad_0.0.1d_dxg_install.bin')"),
              "a zip without the DXG's Launchpad file is refused, nothing written")
        drop("lpad-pkg-001d.zip", make_zip({"lpad/update_launchpad_0.0.1d_dx_install.bin": "FC02dx",
                                            "lpad/update_launchpad_0.0.1d_dxg_install.bin": "FC02dxg"}))
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('On the Kindle')")
        check(ev("() => T.read('update_launchpad_0.0.1d_dxg_install.bin')") == "FC02dxg" and not ev("() => T.has('update_launchpad_0.0.1d_dx_install.bin')"),
              "from lpad-pkg-001d.zip only the DXG's installer goes on the drive")
        page.click("#check")
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('No sign of Launchpad')")
        check(True, "Check: no Launchpad yet (no screenshot.bmp, no launchpad folder)")
        ev("() => T.put('screenshot_0001.bmp', 'BM')")
        page.click("#check")
        page.wait_for_function("() => document.querySelector('#step-list li[data-step=launchpad]').classList.contains('done')")
        check(True, "Check after Shift ×3: Launchpad's screenshot found, step done")
        goto_step("gzreader")
        page.wait_for_function("() => document.querySelector('#steps #do').textContent.includes('1.27.0')")
        page.click("#steps #do")
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('files on the Kindle')", timeout=30000)
        check(ev("() => T.read('koreader/gzreader-version')") == "1.27.0\n" and ev("() => T.has('launchpad/koreader.ini')")
              and ev("() => T.has('extensions/koreader/config.xml')") and not ev("() => T.has('documents/GZreader.sh')"),
              "GZreader's kindle-legacy package from the updates branch: koreader, extensions, launchpad on the drive")
        check(ev("() => document.querySelector('#step-list li[data-step=gzreader]').classList.contains('done')")
              and "Shift, G, G" in ev("() => document.querySelector('#steps .device').textContent"),
              "the package step is done, and says to start with Shift, G, G")
        goto_step("kualfix")
        ev("() => T.put('documents/KUAL-KDK-2.0.azw2', 'old')")
        page.click("#steps #do")
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('On the Kindle')")
        check(ev("() => T.sha('documents/KUAL-KDK-1.0.azw2')") == sha_file(os.path.join(FILES, "kual-dx-fix/documents/KUAL-KDK-1.0.azw2"))
              and ev("() => T.has('kual-dx-fix/install_keystore.sh')") and ev("() => T.has('launchpad/kualfix.ini')")
              and ev("() => T.has('launchpad/koreader.ini')") and not ev("() => T.has('documents/KUAL-KDK-2.0.azw2')"),
              "kual-dx-fix: the re-signed KUAL, the keystore folder, Shift K I's shortcut; the other KUAL book removed, GZreader's shortcut kept")
        page.click("#check")
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('install.log')")
        ev("() => T.put('kual-dx-fix/install.log', '=== x ===\\ninstalled keystore OK\\nlocked (immutable) OK\\n')")
        page.click("#check")
        page.wait_for_function("() => document.querySelector('#step-list li[data-step=kualfix]').classList.contains('done')")
        check(True, "Check after Shift K I: install.log says the keystore is in and locked")
        page.click("#finish")
        check(ev("() => !!document.querySelector('#all-done')") and "sync page" in ev("() => document.querySelector('#steps').textContent"),
              "Done: points a Kindle without Wi-Fi to the sync page")
        page.reload()
        page.wait_for_function("window.GZSetup")
        page.click("#pick")
        page.wait_for_selector("#steps-card:not(.hidden)")
        check(steps() == ["clean", "gzreader", "kualfix"] and ev("() => document.querySelector('#jb-yes').checked")
              and "GZreader 1.27.0 is installed" in ev("() => document.querySelector('#drive-status').textContent"),
              "back on the page later: GZreader seen on the drive, taken as jailbroken: the update files left over, GZreader, KUAL (%s)" % steps())

        print("a Kindle Keyboard that's already jailbroken")
        fresh("async () => { await T.mkdir('launchpad'); await T.mkdir('extensions'); }")
        page.fill("#serial", "B008")
        page.fill("#fw", "3.4.3")
        page.wait_for_selector("#steps-card:not(.hidden)")
        check(ev("() => document.querySelector('#jb-yes').checked") and "Launchpad (launchpad/)" in ev("() => document.querySelector('#jb-hint').textContent"),
              "Launchpad and KUAL's extensions found: taken as jailbroken")
        check(steps() == ["gzreader", "kual"], "only GZreader (and KUAL, optional) left to do: %s" % steps())
        page.click("#jb-no")
        page.wait_for_function("() => document.querySelector('#step-list li[data-step=jailbreak]')")
        goto_step("jailbreak")
        check("Update_jailbreak_k3w_install.bin" in ev("() => document.querySelector('#steps').textContent"), "jailbreak it anyway: 3.4.3 takes k3w_install.bin")
        page.fill("#fw", "3.2")
        page.wait_for_function("() => document.querySelector('#step-list li[data-step=jailbreak]')")
        goto_step("jailbreak")
        check("Update_jailbreak_k3w_3.0-to-3.2_install.bin" in ev("() => document.querySelector('#steps').textContent"), "on 3.2: the -3.0-to-3.2 file")
        page.fill("#fw", "3.9")
        page.wait_for_function("() => document.querySelector('#fw-status').textContent.includes('3.0 – 3.4.3')")
        check(not ev("() => !document.querySelector('#steps-card').classList.contains('hidden')"), "a firmware a Kindle Keyboard never had: no steps")
        page.fill("#fw", "3.4.3")
        page.click("#jb-yes")
        page.wait_for_function("() => document.querySelector('#step-list li[data-step=kual]')")
        goto_step("kual")
        drop("KUAL-KDK-1.0.azw2", make_zip({"META-INF/MANIFEST.MF": "Manifest-Version: 1.0\nImplementation-Title: Something\n"}))
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.length > 0")
        check("That isn't KUAL" in out_text() and not ev("() => T.has('documents/KUAL-KDK-1.0.azw2')"), "an .azw2 that isn't KUAL is refused")
        drop("KUAL-KDK-1.0.azw2", make_zip({"META-INF/MANIFEST.MF": "Manifest-Version: 1.0\nImplementation-Title: KUAL\nImplementation-Version: 2.7\n"}))
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('On the Kindle')")
        check(ev("() => T.has('documents/KUAL-KDK-1.0.azw2')"), "KUAL goes in documents")
        goto_step("gzreader")
        page.evaluate("() => { window.GZSetup.S.raw = location.origin + '/raw-missing/'; window.GZSetup.Pkg.meta = null; }")
        # (the updates branch without packages yet: the page asks for the release's zip)
        ev("() => { document.querySelector('#step-list li[data-step=kual] button').click(); }")
        goto_step("gzreader")
        page.wait_for_selector("#pkg-drop:not(.hidden)")
        drop("gzreader-kindle-1.27.0.zip", package("kindle"), "#pkg-drop input[type=file]")
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.length > 0")
        check("this Kindle takes gzreader-kindle-legacy" in out_text() and not ev("() => T.has('koreader/gzreader-version')"),
              "no packages on the updates branch: the release's zip is asked for, and the wrong one refused")
        drop("gzreader-kindle-legacy-1.27.0.zip", package("kindle-legacy"), "#pkg-drop input[type=file]")
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('files on the Kindle')")
        check(ev("() => T.has('launchpad/koreader.ini')") and ev("() => T.read('koreader/gzreader-version')") == "1.27.0\n",
              "the right one dropped: installed")

        print("a Paperwhite 3 on 5.16.2.1.1, with WinterBreak")
        fresh()
        page.fill("#serial", "G090G1XX")
        page.fill("#fw", "5.16.2.1.1")
        page.wait_for_selector("#touch-q:not(.hidden)")
        check(ev("() => !document.querySelector('#q-reg').classList.contains('hidden')") and ev("() => document.querySelector('#q-ads').classList.contains('hidden')"),
              "asks whether it can be registered (WinterBreak needs it), not about ads (no jailbreak here depends on them)")
        check(steps()[:3] == ["wireless", "clean", "jailbreak"] and "hotfix" in steps() and steps()[-1] == "gzreader",
              "before the answer: WinterBreak2 (recommended), then the hotfix, then GZreader: %s" % steps())
        page.check('input[name=reg][value=yes]')
        page.wait_for_function("() => document.querySelectorAll('#method option').length === 2")
        page.select_option("#method", "WinterBreak")
        page.wait_for_function("() => document.querySelector('#step-list li[data-step=jailbreak] button').textContent.includes('(WinterBreak)')")
        check("hotfix" not in steps(), "WinterBreak installs its own hotfix: no hotfix step (%s)" % steps())
        goto_step("jailbreak")
        page.click("#steps #do")
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('On the Kindle')")
        check(ev("() => T.has('.active_content_sandbox/store/resource/cachedResources/index.html')")
              and ev("() => T.has('apps/tech.hackerdude.winterbreak/manifest.json')") and ev("() => T.has('mesquito/main.js')"),
              "WinterBreak's files on the drive, the hidden .active_content_sandbox folder too (the step people miss on a Mac)")
        goto_step("gzreader")
        page.click("#steps #do")
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('files on the Kindle')")
        check(ev("() => T.read('koreader/plugins/gzreader.koplugin/main.lua')") == "-- GZreader (kindlepw2)\n" and ev("() => T.has('documents/GZreader.sh')"),
              "firmware before 5.16.3: the kindlepw2 package, with the GZreader item (documents/GZreader.sh)")
        page.fill("#fw", "5.16.3")
        page.wait_for_function("() => document.querySelector('#step-list li[data-step=gzreader]')")
        goto_step("gzreader")
        check("kindlehf" in ev("() => document.querySelector('#steps').textContent"), "5.16.3: the kindlehf package")
        page.fill("#fw", "5.22.1")
        page.wait_for_function("() => document.querySelector('#step-list li[data-step=nojb]')")
        check(steps() == ["wireless", "nojb"], "a firmware no jailbreak handles yet: says so and stops (%s)" % steps())

        print("a Kindle 4: the jailbreak's zip, without its uninstaller")
        fresh()
        page.fill("#serial", "B00E")
        page.wait_for_selector("#steps-card:not(.hidden)")
        check(steps() == ["wireless", "clean", "jailbreak", "mkk", "kual", "gzreader"],
              "jailbreak, the 2025 developer keys, KUAL, GZreader: %s" % steps())
        goto_step("jailbreak")
        drop("K4-Jailbreak.zip", make_zip({"data.tar.gz": "TGZ", "ENABLE_DIAGS": "", "diagnostic_logs/device_info.xml": "",
                                           "Update_jailbreak_1.8.N_uninstall.bin": "FC02un"}))
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('On the Kindle')")
        check(ev("() => T.has('ENABLE_DIAGS')") and ev("() => T.read('data.tar.gz')") == "TGZ" and ev("() => T.has('diagnostic_logs/device_info.xml')")
              and not ev("() => T.has('Update_jailbreak_1.8.N_uninstall.bin')"),
              "data.tar.gz, ENABLE_DIAGS, diagnostic_logs on the drive; the uninstaller left out (it would undo the jailbreak at the next update)")
        goto_step("mkk")
        drop("Update_mkk-20250419-k4-ALL_keystore-install.bin", b"not an update")
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.length > 0")
        check("isn't a Kindle update file" in out_text(), "an MKK file that isn't a Kindle update file is refused")
        drop("Update_mkk-20250419-k4-ALL_keystore-install.bin", b"FC02" + b"\0" * 60)
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('On the Kindle')")
        page.click("#check")
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('still on the drive')")
        check(True, "Check before Update Your Kindle: the MKK file is still there, not done")

        print("a Kindle Touch: the K5 jailbreak and the hotfix")
        fresh()
        page.fill("#serial", "B00F")
        page.wait_for_selector("#steps-card:not(.hidden)")
        check(steps() == ["wireless", "clean", "jailbreak", "hotfix", "gzreader"], "jailbreak, hotfix, GZreader: %s" % steps())
        goto_step("jailbreak")
        drop("kindle-5.4-jailbreak.zip", make_zip({"jb.sh": "#!/bin/sh", "Update_jb_$(cd mnt && cd us && sh jb.sh).bin": "FC02",
                                                    "gandalf": "x", "bridge.sh": "x", "developer.keystore": "x"}))
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('On the Kindle')")
        check(ev("() => T.has('Update_jb_$(cd mnt && cd us && sh jb.sh).bin')") and ev("() => T.has('jb.sh')"),
              "the K5 jailbreak's files, its odd update file name included")
        goto_step("hotfix")
        page.click("#steps #do")
        page.wait_for_function("() => document.querySelector('#steps .out').textContent.includes('On the Kindle')")
        check(ev("() => T.sha('Update_hotfix_universal.bin')") == sha_file(os.path.join(FILES, "hotfix/Update_hotfix_universal.bin")),
              "the Universal Hotfix on the drive, the bundled file")

        print("not a Kindle, and other drives")
        fresh()
        page.evaluate("async () => { await T.rm('documents'); await T.rm('system'); await T.put('photo.jpg', 'x'); await GZSetup.rescan(); }")
        check("doesn't look like a Kindle" in ev("() => document.querySelector('#drive-status').textContent"), "a drive without documents/system: said so")
        page.fill("#serial", "QQQQ")
        check("doesn't look like a Kindle serial" in ev("() => document.querySelector('#serial-err').textContent"), "a serial that can't be a Kindle's: said so")
        page.fill("#serial", "B001")
        page.wait_for_function("() => document.querySelector('#serial-status').textContent.includes(\"doesn't run\")")
        check(not ev("() => !document.querySelector('#steps-card').classList.contains('hidden')"), "a Kindle 1: GZreader doesn't run on it, no steps")

        print("narrow screens")
        for w in (390, 1100):
            page.set_viewport_size({"width": w, "height": 900})
            fresh()
            page.fill("#serial", "B009")
            page.wait_for_selector("#steps-card:not(.hidden)")
            check(ev("() => document.documentElement.scrollWidth <= window.innerWidth"), "%d px wide: no sideways scrolling" % w)
        check(not errors, "no script errors on the page " + "; ".join(errors[:3]))
        browser.close()
    srv.shutdown()
    print("%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
