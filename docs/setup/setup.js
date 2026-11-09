/* GZreader setup page: jailbreak a Kindle and install GZreader, step by step.
 *
 * The page writes to the Kindle's USB drive (File System Access API, Chrome or
 * Edge on a computer), like the sync page. It works out the steps from the
 * Kindle's serial number and firmware, puts the files each step needs on the
 * drive (the ones in files/, or ones the user downloads and drops here, which
 * it checks first), and checks the drive afterwards where a step leaves
 * something to see. A Kindle that's already jailbroken goes straight to
 * installing GZreader.
 *
 * Which jailbreak for which model and firmware: kindlemodding.org's tables
 * (CC BY-NC 4.0; facts only, our own wording), checked against the packages'
 * own READMEs (e.g. NiLuJe's: the -3.0-to-3.2 files are for Kindle Keyboard
 * firmware 3.2 and older only, 3.2.1 takes the other one).
 */
(function () {
  "use strict";

  var RAW = "https://raw.githubusercontent.com/9retirement6irk/GZreader/updates/";
  var RELEASES = "https://github.com/9retirement6irk/GZreader/releases/latest";
  var WIKI = "https://github.com/9retirement6irk/GZreader/wiki/";
  var KM = "https://kindlemodding.org/";

  function $(s, root) { return (root || document).querySelector(s); }
  function el(tag, attrs) {
    var e = document.createElement(tag);
    for (var k in attrs || {}) {
      if (k === "class") e.className = attrs[k];
      else if (k === "html") e.innerHTML = attrs[k];
      else if (k.slice(0, 2) === "on") e[k] = attrs[k];
      else e.setAttribute(k, attrs[k]);
    }
    for (var i = 2; i < arguments.length; i++) {
      var c = arguments[i];
      if (c == null || c === false) continue;
      e.appendChild(typeof c === "string" ? document.createTextNode(c) : c);
    }
    return e;
  }
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function mb(n) { return (n / 1048576).toFixed(n < 10485760 ? 1 : 0) + " MB"; }

  // ------------------------------------------------------------ Kindles

  // serial: the first characters decide the model (kindlemodding.org's model
  // table). Old serials (B0xx…) carry a 2-character code at 3–4, newer ones
  // (G0xxxx…) a 3-character code at 4–6.
  var MODELS = [
    { id: "K1", name: "Kindle (1st generation)", codes: ["01"], family: "none" },
    { id: "K2", name: "Kindle 2", codes: ["02", "03"], sfx: { "02": "k2", "03": "k2i" }, family: "k2dx", pkg: "kindle-legacy", keys: true },
    { id: "DX", name: "Kindle DX", codes: ["04", "05", "09"], sfx: { "04": "dx", "05": "dxi", "09": "dxg" },
      names: { "05": "Kindle DX International", "09": "Kindle DX Graphite" }, family: "k2dx", pkg: "kindle-legacy", keys: true },
    { id: "K3", name: "Kindle Keyboard (3)", codes: ["06", "08", "0A"], sfx: { "06": "k3g", "08": "k3w", "0A": "k3gb" },
      family: "k3", pkg: "kindle-legacy", keys: true, needsFw: true },
    { id: "K4", name: "Kindle 4", codes: ["0E", "23"], family: "k4", pkg: "kindle" },
    { id: "KT", name: "Kindle Touch", codes: ["0F", "10", "11", "12"], family: "kt", pkg: "kindle" },
    { id: "PW", name: "Kindle Paperwhite (1st generation)", codes: ["1B", "1C", "1D", "1F", "20", "24"], family: "touch", pkg: "kindle", needsFw: true },
    { id: "PW2", name: "Kindle Paperwhite 2", codes: ["17", "5A", "5F", "60", "61", "62", "D4", "D5", "D6", "D7", "D8", "F2", "F4", "F9"], family: "touch", needsFw: true },
    { id: "KV", name: "Kindle Voyage", codes: ["13", "2A", "4F", "52", "53", "54"], family: "touch", needsFw: true },
    { id: "KT2", name: "Kindle (7th generation)", codes: ["C6", "DD"], family: "touch", needsFw: true },
    { id: "PW3", name: "Kindle Paperwhite 3", codes: ["0G1", "0G2", "0G4", "0G5", "0G6", "0G7", "0KB", "0KC", "0KD", "0KE", "0KF", "0KG", "0LK", "0LL", "TTT"], family: "touch", needsFw: true },
    { id: "KOA", name: "Kindle Oasis (8th generation)", codes: ["0GC", "0GD", "0GR", "0GS", "0GT", "0GU"], family: "touch", needsFw: true },
    { id: "KT3", name: "Kindle (8th generation)", codes: ["0DU", "0K9", "0KA"], family: "touch", needsFw: true },
    { id: "KM", name: "Kindle x Migu", codes: ["0NG"], family: "none" },
    { id: "KOA2", name: "Kindle Oasis 2", codes: ["0LM", "0LN", "0LP", "0LQ", "0P1", "0P2", "0P6", "0P7", "0P8", "0S1", "0S2", "0S3", "0S4", "0S7", "0SA"], family: "touch", needsFw: true },
    { id: "PW4", name: "Kindle Paperwhite 4", codes: ["0PL", "0PP", "0T1", "0T2", "0T3", "0T4", "0T5", "0T6", "0T7", "0TJ", "0TK", "0TL", "0TM", "0TN", "102", "103", "16Q", "16R", "16S", "16T", "16U", "16V"], family: "touch", needsFw: true },
    { id: "KT4", name: "Kindle (10th generation)", codes: ["0VB", "0WF", "0WG", "0WH", "0WJ", "10L"], family: "touch", needsFw: true },
    { id: "KOA3", name: "Kindle Oasis 3", codes: ["0WL", "0WM", "0WN", "0WP", "0WQ", "11L"], family: "touch", needsFw: true },
    { id: "PW5", name: "Kindle Paperwhite 5", codes: ["1LG", "1PX", "1Q0", "1VD", "219", "21A", "2BH", "2BJ", "2DK"], family: "touch", needsFw: true },
    { id: "KT5", name: "Kindle (11th generation, 2022)", codes: ["1XH", "22C", "22D", "23A", "25T", "2AP", "2AQ"], family: "touch", needsFw: true },
    { id: "KS", name: "Kindle Scribe (2022)", codes: ["227", "23L", "23M", "263", "270", "27J", "2BL", "2BM"], family: "touch", needsFw: true },
    { id: "KT6", name: "Kindle (11th generation, 2024)", codes: ["3KM", "3L2", "3L3", "3L4", "3L5", "3L6", "A89"], family: "touch", needsFw: true },
    { id: "PW6", name: "Kindle Paperwhite 6 (2024)", codes: ["33W", "33X", "346", "349", "3H3", "3H5", "3H8", "3HA", "3J5", "3JS"], family: "touch", needsFw: true },
    { id: "KS2", name: "Kindle Scribe (2024)", codes: ["3UV", "3V0", "3V1", "3X3", "3X4", "3X5", "41D", "41E"], family: "touch", needsFw: true },
    { id: "CS", name: "Kindle Colorsoft", codes: ["34X", "3H2", "3H4", "3H6", "3H7", "3H9", "3HB", "3J6", "3JT", "455", "456", "4EP"], family: "touch", needsFw: true },
    { id: "KS3", name: "Kindle Scribe (3rd generation)", codes: ["454", "4F8", "4FA", "4PE", "4PG", "4PL"], family: "touch", needsFw: true },
    { id: "KSC", name: "Kindle Scribe Colorsoft", codes: ["46P", "4F9", "4FB", "4PF", "4PH", "4VX"], family: "touch", needsFw: true },
    { id: "KT7", name: "Kindle (2026)", codes: ["56S", "56T", "56U", "56V", "5W5", "5W6", "6HN", "6HP", "6HQ", "6HR"], family: "touch", needsFw: true },
  ];

  /** { model, code, sfx, name } or { error } from a serial number (or its start). */
  function modelFromSerial(serial) {
    var s = String(serial || "").toUpperCase().replace(/[\s-]/g, "");
    if (!s) return { error: "" };
    var code;
    if (s[0] === "G") {
      if (s.length < 6) return { error: "Type at least the first 6 characters." };
      code = s.slice(3, 6);
    } else if (/^[0-9A-F]/.test(s)) {
      if (s.length < 4) return { error: "Type at least the first 4 characters." };
      code = s.slice(2, 4);
    } else {
      return { error: "That doesn't look like a Kindle serial number (it starts with B0, 90 or G0…)." };
    }
    for (var i = 0; i < MODELS.length; i++) {
      var m = MODELS[i];
      if (m.codes.indexOf(code) >= 0 && (code.length === 3) === (m.codes[0].length === 3)) {
        return { model: m, code: code, sfx: m.sfx && m.sfx[code], name: (m.names && m.names[code]) || m.name };
      }
    }
    return { error: "No Kindle model has that serial number (code " + code + "). Check the first characters." };
  }

  /** -1, 0, 1 comparing dotted firmware versions ("5.16.10" > "5.16.9"). */
  function cmpVer(a, b) {
    var x = String(a).split(".").map(Number), y = String(b).split(".").map(Number);
    for (var i = 0; i < Math.max(x.length, y.length); i++) {
      var p = x[i] || 0, q = y[i] || 0;
      if (p > q) return 1;
      if (p < q) return -1;
    }
    return 0;
  }
  function validFw(fw) { return /^\d{1,2}(\.\d{1,3}){1,5}$/.test(String(fw || "")); }

  /** Which GZreader package a Kindle takes. */
  function packageFor(model, fw) {
    if (model.pkg) return model.pkg;
    if (model.family !== "touch") return null;
    if (fw && cmpVer(fw, "5.16.3") >= 0) return "kindlehf";
    return "kindlepw2";
  }

  // jailbreaks for touch Kindles (Paperwhite 1 and newer), in kindlemodding.org's
  // order of preference: models, firmware ranges (both ends included),
  // whether it needs the Kindle registered to Amazon, or one with ads
  var METHODS = [
    { name: "WinterBreak2", page: "jailbreaking/WinterBreak2/", reg: false, ads: false, kind: "wb2",
      models: ["PW", "PW2", "KV", "KT2", "PW3", "KOA", "KT3", "KOA2", "PW4", "KT4", "KOA3", "PW5", "KT5", "KS"],
      fw: [{ models: "all", min: "5.6.1.1", max: "5.16.3", also: ["5.16.5"] }] },
    { name: "SpiderCat", page: "jailbreaking/SpiderCat/", reg: false, ads: false,
      models: ["PW4", "KT4", "KOA3", "PW5", "KT5", "KT6", "PW6", "CS", "KS", "KS2"],
      fw: [{ models: "all", min: "5.16.3", max: "5.19.5" }] },
    { name: "Véra", page: "jailbreaking/Vera/", reg: false, ads: false,
      models: ["PW5", "KT5", "KT6", "PW6", "CS", "KS", "KS2"], fw: [{ models: "all", min: "5.17.1", max: "5.20.2" }] },
    { name: "Nosebleed", page: "jailbreaking/Nosebleed/", reg: false, ads: false,
      models: ["KT5", "PW5", "KOA3", "PW6", "KT6"],
      fw: [{ models: ["KT5", "PW5", "KOA3"], min: "5.16.4", max: "5.18.6" }, { models: ["PW6", "KT6"], min: "5.16.4", max: "5.17.1.0.4" }] },
    { name: "Sanctuary", page: "jailbreaking/Sanctuary/", reg: false, ads: false, hotfix: true,
      models: ["PW4", "KT4", "KOA3", "PW5", "KT5", "KS", "KT6", "PW6", "KS2", "CS"],
      fw: [{ models: "all", min: "5.16.4", max: "5.18.3", not: ["5.16.5"] }] },
    { name: "WinterBreak", page: "jailbreaking/WinterBreak/", reg: true, ads: false, hotfix: true, kind: "wb",
      models: ["PW", "PW2", "KV", "KT2", "PW3", "KOA", "KT3", "KOA2", "PW4", "KT4", "KOA3", "PW5", "KT5", "KS", "KT6", "PW6", "KS2", "CS"],
      fw: [{ models: "all", min: "5.6.1.1", max: "5.18.0.2" }] },
    { name: "SpringBreak", page: "jailbreaking/SpringBreak/", reg: true, ads: false, hotfix: true,
      models: ["KT5", "PW5", "KT4", "PW4"],
      fw: [{ models: ["KT5", "PW5"], min: "5.18.1", max: "5.19.2.0.1" }, { models: ["KT4", "PW4"], min: "5.18.1", max: "5.18.1.1.1" }] },
    { name: "Shadow", page: "jailbreaking/Shadow/", reg: false, ads: false,
      models: ["KS", "KS2", "CS", "PW6", "KT6"], fw: [{ models: "all", min: "5.19.4", max: "5.19.6" }] },
    { name: "AdBreak", page: "jailbreaking/AdBreak/", reg: true, ads: true,
      models: ["PW4", "KT4", "KOA3", "PW5", "KT5", "KS", "KT6", "PW6"],
      fw: [{ models: ["KOA3", "PW5", "KT5", "KS", "KT6", "PW6"], min: "5.18.1", max: "5.18.5.0.1" }, { models: ["PW4", "KT4"], min: "5.18.1", max: "5.18.1" }] },
  ];

  /** The touch-Kindle jailbreaks for this model and firmware, best first.
   * registered / ads: true, false, or null (not asked yet: not filtered). */
  function methodsFor(modelId, fw, registered, ads) {
    return METHODS.filter(function (m) {
      if (m.models.indexOf(modelId) < 0) return false;
      if (m.reg && registered === false) return false;
      if (m.ads && ads === false) return false;
      return m.fw.some(function (r) {
        if (r.models !== "all" && r.models.indexOf(modelId) < 0) return false;
        if ((r.not || []).indexOf(fw) >= 0) return false;
        if ((r.also || []).indexOf(fw) >= 0) return true;
        return cmpVer(fw, r.min) >= 0 && cmpVer(fw, r.max) <= 0;
      });
    });
  }

  /** NiLuJe's K2/DX/K3 jailbreak file for a model code (and K3 firmware). */
  function legacyJailbreak(sfx, fw) {
    if (/^k3/.test(sfx) && fw && cmpVer(fw, "3.2") <= 0) return "Update_jailbreak_" + sfx + "_3.0-to-3.2_install.bin";
    return "Update_jailbreak_" + sfx + "_install.bin";
  }

  // files kept in files/ (see files/README.md): size and SHA-256, checked
  // after download and by setup_page_test.py
  var BUNDLED = {
    "jailbreak-0.13.N/Update_jailbreak_dx_install.bin": [37146, "d48d88633b07c5feb7ae7826c90fcd9cf2e5cfa6569af28ad266379e5753937c"],
    "jailbreak-0.13.N/Update_jailbreak_dxg_install.bin": [37146, "c3ab36b08ddbaf8a9147f8fdd5036a7cf547dc916bc222b63c87dff37939ccf6"],
    "jailbreak-0.13.N/Update_jailbreak_dxi_install.bin": [37146, "07faa1ecc21252293ad16bbd3e876c0ddf43198dbfbb3887b33d683279e8253f"],
    "jailbreak-0.13.N/Update_jailbreak_k2_install.bin": [37146, "9d1409f5d6156c2c116834a8714a888877cfb893abc90aa6367cfb0a79ff5519"],
    "jailbreak-0.13.N/Update_jailbreak_k2i_install.bin": [37146, "01fdaca053bb03141a87296ef2200014604d3ba0804438554c1fe26f327f6de5"],
    "jailbreak-0.13.N/Update_jailbreak_k3g_3.0-to-3.2_install.bin": [299407, "09343d7a173c50ef6d215508c46882a5b7d2a968bb37b3a0e8cd92dd4e3fae5e"],
    "jailbreak-0.13.N/Update_jailbreak_k3g_install.bin": [299552, "88b03e9e444248dca8e468c05a59ab82273dee6e185300d08368ead09a8ef590"],
    "jailbreak-0.13.N/Update_jailbreak_k3gb_3.0-to-3.2_install.bin": [299409, "a9423f3c3c0f105cd1b5f2f58b9d8f6b3057192c5a05c315dde65a2cf1ad18b1"],
    "jailbreak-0.13.N/Update_jailbreak_k3gb_install.bin": [299552, "6613274e5050720f076617b9814cc6eb94e5a1173a1a235bafd903f4573db5b5"],
    "jailbreak-0.13.N/Update_jailbreak_k3w_3.0-to-3.2_install.bin": [299407, "0f32bc4e13f29664f1a978eec36d2068360e8c60d9ca93356e5414678e781a08"],
    "jailbreak-0.13.N/Update_jailbreak_k3w_install.bin": [299552, "cc00acde0f50538a5886e8afce36775b7dd9b0ff11ed0954426b3a0c3c55e11c"],
    "hotfix/Update_hotfix_universal.bin": [3743762, "94d5c05254b70c4905392515411f620168ac238db62c7dcbc48a1e31d5de6c59"],
    "winterbreak/WinterBreak.tar.gz": [288883, "dc04fff5fcb685834cba9f9e95d4818b473d4100b2d40b8bb7c598ad09eb850d"],
    "kual-dx-fix/documents/KUAL-KDK-1.0.azw2": [126948, null],
    "kual-dx-fix/kual-dx-fix/developer.keystore": [3734, null],
    "kual-dx-fix/kual-dx-fix/install_keystore.sh": [875, null],
    "kual-dx-fix/kual-dx-fix/restore_keystore.sh": [519, null],
    "kual-dx-fix/launchpad/kualfix.ini": [259, null],
  };

  async function sha256(buf) {
    var d = await crypto.subtle.digest("SHA-256", buf);
    return Array.prototype.map.call(new Uint8Array(d), function (b) { return ("0" + b.toString(16)).slice(-2); }).join("");
  }

  async function bundled(path) {
    var r = await fetch("files/" + path, { cache: "no-cache" });
    if (!r.ok) throw new Error("Couldn't load " + path + " from this page (" + r.status + ").");
    var buf = await r.arrayBuffer();
    var want = BUNDLED[path];
    if (want && (buf.byteLength !== want[0] || (want[1] && (await sha256(buf)) !== want[1]))) {
      throw new Error(path + " didn't arrive whole: reload the page and try again.");
    }
    return new Blob([buf]);
  }

  // ------------------------------------------------------------ the drive

  var Drive = {
    dir: async function (parent, path, create) {
      var d = parent, parts = String(path || "").split("/").filter(Boolean);
      for (var i = 0; i < parts.length; i++) d = await d.getDirectoryHandle(parts[i], { create: !!create });
      return d;
    },
    tryDir: async function (parent, path) { try { return await Drive.dir(parent, path); } catch (e) { return null; } },
    file: async function (parent, path, create) {
      var parts = String(path).split("/"), name = parts.pop();
      var d = await Drive.dir(parent, parts.join("/"), create);
      return d.getFileHandle(name, { create: !!create });
    },
    has: async function (parent, path) { try { await Drive.file(parent, path); return true; } catch (e) { return false; } },
    readText: async function (parent, path) {
      try { return await (await (await Drive.file(parent, path)).getFile()).text(); } catch (e) { return null; }
    },
    write: async function (parent, path, data) {
      var w = await (await Drive.file(parent, path, true)).createWritable();
      try {
        if (data && data.stream && data.size > 4194304) await data.stream().pipeTo(w);
        else { await w.write(data); await w.close(); }
      } catch (e) { try { await w.abort(); } catch (e2) {} throw e; }
    },
    remove: async function (parent, path) {
      var parts = String(path).split("/"), name = parts.pop();
      try { var d = await Drive.dir(parent, parts.join("/")); await d.removeEntry(name, { recursive: true }); return true; } catch (e) { return false; }
    },
    list: async function (dir) {
      var out = [];
      try { for await (var h of dir.values()) out.push({ name: h.name, kind: h.kind }); } catch (e) { if (e && e.name === "NotFoundError") throw e; }
      return out;
    },
  };

  // the handle, kept between visits (IndexedDB: handles can't go in localStorage)
  var idb = {
    open: function () {
      return new Promise(function (ok, fail) {
        var r = indexedDB.open("gzsetup", 1);
        r.onupgradeneeded = function () { r.result.createObjectStore("kv"); };
        r.onsuccess = function () { ok(r.result); };
        r.onerror = function () { fail(r.error); };
      });
    },
    get: async function (k) {
      try {
        var db = await idb.open();
        return await new Promise(function (ok) { var q = db.transaction("kv").objectStore("kv").get(k); q.onsuccess = function () { ok(q.result); }; q.onerror = function () { ok(null); }; });
      } catch (e) { return null; }
    },
    set: async function (k, v) {
      try {
        var db = await idb.open();
        await new Promise(function (ok) { var t = db.transaction("kv", "readwrite"); t.objectStore("kv").put(v, k); t.oncomplete = ok; t.onerror = ok; });
      } catch (e) {}
    },
  };

  // ------------------------------------------------------------ zip and tar

  /** The entries of a zip: [{ name, dir, size, open() → Promise<Blob> }]. */
  async function zipEntries(blob) {
    var tailLen = Math.min(blob.size, 65557);
    var tail = new Uint8Array(await blob.slice(blob.size - tailLen).arrayBuffer());
    var dv = new DataView(tail.buffer), eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) { if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; } }
    if (eocd < 0) throw new Error("not a zip file");
    var count = dv.getUint16(eocd + 10, true), cdSize = dv.getUint32(eocd + 12, true), cdOff = dv.getUint32(eocd + 16, true);
    var cd = new Uint8Array(await blob.slice(cdOff, cdOff + cdSize).arrayBuffer());
    var c = new DataView(cd.buffer), dec = new TextDecoder(), out = [];
    for (var p = 0, n = 0; n < count && p + 46 <= cd.length && c.getUint32(p, true) === 0x02014b50; n++) {
      var method = c.getUint16(p + 10, true), csize = c.getUint32(p + 20, true), usize = c.getUint32(p + 24, true);
      var nlen = c.getUint16(p + 28, true), elen = c.getUint16(p + 30, true), clen = c.getUint16(p + 32, true);
      var lho = c.getUint32(p + 42, true);
      var name = dec.decode(cd.subarray(p + 46, p + 46 + nlen));
      out.push(zipEntry(blob, name, method, csize, usize, lho));
      p += 46 + nlen + elen + clen;
    }
    return out;
  }
  function zipEntry(blob, name, method, csize, usize, lho) {
    return {
      name: name.replace(/^\.\//, ""), dir: /\/$/.test(name), size: usize,
      open: async function () {
        var lh = new DataView(await blob.slice(lho, lho + 30).arrayBuffer());
        var start = lho + 30 + lh.getUint16(26, true) + lh.getUint16(28, true);
        var data = blob.slice(start, start + csize);
        if (method === 0) return data;
        if (method === 8) return new Response(data.stream().pipeThrough(new DecompressionStream("deflate-raw"))).blob();
        throw new Error(name + ": compression " + method + " isn't supported");
      },
    };
  }

  /** The entries of a .tar.gz (or .tar): same shape as zipEntries. */
  async function tarEntries(blob) {
    var head = new Uint8Array(await blob.slice(0, 2).arrayBuffer());
    var data = head[0] === 0x1f && head[1] === 0x8b
      ? new Uint8Array(await new Response(blob.stream().pipeThrough(new DecompressionStream("gzip"))).arrayBuffer())
      : new Uint8Array(await blob.arrayBuffer());
    var dec = new TextDecoder(), out = [], longName = null, pax = null;
    function str(a, b) { var s = dec.decode(data.subarray(a, b)); var z = s.indexOf("\0"); return z >= 0 ? s.slice(0, z) : s; }
    for (var p = 0; p + 512 <= data.length;) {
      if (data[p] === 0 && str(p, p + 100) === "") break;
      var name = str(p, p + 100), size = parseInt(str(p + 124, p + 136).trim() || "0", 8), type = String.fromCharCode(data[p + 156] || 48);
      var prefix = str(p + 345, p + 500);
      if (prefix && dec.decode(data.subarray(p + 257, p + 262)) === "ustar") name = prefix + "/" + name;
      var body = p + 512;
      if (type === "L") { longName = str(body, body + size); }
      else if (type === "x") {
        var t = dec.decode(data.subarray(body, body + size)), m = t.match(/\d+ path=([^\n]*)\n/);
        pax = m ? m[1] : null;
      } else if (type === "0" || type === "\0" || type === "5") {
        var full = (pax || longName || name).replace(/^\.\//, "");
        pax = longName = null;
        if (full && full !== ".") {
          (function (bytes) {
            out.push({ name: full + (type === "5" && !/\/$/.test(full) ? "/" : ""), dir: type === "5", size: bytes.length,
              open: async function () { return new Blob([bytes]); } });
          })(data.slice(body, body + size));
        }
      } else { pax = longName = null; }
      p = body + Math.ceil(size / 512) * 512;
    }
    return out;
  }

  async function archiveEntries(blob, name) {
    if (/\.(tar\.gz|tgz|tar)$/i.test(name || "")) return tarEntries(blob);
    return zipEntries(blob);
  }

  /** Write archive entries to the drive under their names (filter(name) → dest
   * path or null to leave it out). onProgress(done, total). */
  async function writeEntries(root, entries, filter, onProgress) {
    var files = [];
    entries.forEach(function (e) {
      if (e.dir || /(^|\/)(__MACOSX|\.DS_Store)(\/|$)/.test(e.name)) return;
      var dest = filter ? filter(e.name) : e.name;
      if (dest) files.push({ e: e, dest: dest });
    });
    var done = 0, next = 0;
    async function worker() {
      while (next < files.length) {
        var f = files[next++];
        await Drive.write(root, f.dest, await f.e.open());
        done++;
        if (onProgress) onProgress(done, files.length);
      }
    }
    var ws = [];
    for (var i = 0; i < Math.min(4, files.length); i++) ws.push(worker());
    await Promise.all(ws);
    return files.map(function (f) { return f.dest; });
  }

  // ------------------------------------------------------------ what the drive shows

  var S = {
    root: null, test: false, raw: RAW,
    serial: null,          // modelFromSerial's answer (the serial itself isn't kept)
    fw: "", registered: null, ads: null,
    jailbroken: null,      // the user's answer (null: not asked; the scan suggests one)
    method: null,          // touch Kindles: the chosen METHODS entry's name
    scan: null, steps: [], at: 0, done: {},
  };

  /** What's on the Kindle's drive that matters here. */
  async function scanDrive(root) {
    var top = await Drive.list(root);
    var names = top.map(function (t) { return t.name; });
    var lower = names.map(function (n) { return n.toLowerCase(); });
    var has = function (n) { return lower.indexOf(n.toLowerCase()) >= 0; };
    var docs = await Drive.tryDir(root, "documents");
    var docNames = docs ? (await Drive.list(docs)).map(function (t) { return t.name; }) : [];
    var r = {
      isKindle: !!docs && (has("system") || has("audible") || has("music") || has("fonts") || has("koreader") || has("extensions")),
      pickedDocuments: root.name === "documents" || (!docs && has("GZreader")),
      markers: [], strays: [],
      gzreader: null, outboxModel: null,
      launchpad: has("launchpad"),
      screenshot: names.some(function (n) { return /^screenshot.*\.bmp$/i.test(n); }),
      kual: docNames.filter(function (n) { return /^KUAL.*\.azw2$|^KUAL\.(sh|jar)$/i.test(n); }),
      scriptlets: docNames.filter(function (n) { return /\.sh$/i.test(n); }),
      kualDxLog: null,
    };
    names.forEach(function (n) {
      if (/\.bin$/i.test(n) || /^update\.bin\.tmp\.partial$/i.test(n)) r.strays.push(n);
    });
    [["extensions", "KUAL extensions (extensions/)"], ["launchpad", "Launchpad (launchpad/)"], ["mrpackages", "MRPI (mrpackages/)"],
      ["koreader", "KOReader or GZreader (koreader/)"], ["kual-dx-fix", "the KUAL DX fix"], ["mesquito", "WinterBreak's files"],
      ["winterbreak2", "WinterBreak2's files"]].forEach(function (m) { if (has(m[0])) r.markers.push(m[1]); });
    if (r.kual.length) r.markers.push("KUAL (" + r.kual.join(", ") + ")");
    var others = r.scriptlets.filter(function (n) { return !/^GZreader\.sh$/i.test(n) && !/^KUAL\.sh$/i.test(n); });
    if (others.length) r.markers.push("scriptlets (" + others.slice(0, 3).join(", ") + (others.length > 3 ? "…" : "") + ")");
    var v = await Drive.readText(root, "koreader/gzreader-version");
    if (v) r.gzreader = v.trim();
    var out = null;
    try { out = JSON.parse(await Drive.readText(root, "documents/GZreader/.gzsync/outbox.json") || "null"); } catch (e) {}
    if (out && out.kindle && out.kindle.model) r.outboxModel = out.kindle.model;
    r.kualDxLog = await Drive.readText(root, "kual-dx-fix/install.log");
    return r;
  }

  // GZreader's own name for the model (the sync outbox: Kindles without Wi-Fi)
  var OUTBOX_MODELS = { Kindle2: ["K2", "02"], KindleDX: ["DX", "04"], KindleDXG: ["DX", "09"] };

  // ------------------------------------------------------------ steps

  // A step: { id, title, why, kind, ... }. Kinds:
  //   info     text and the Kindle-side instructions only
  //   clean    old .bin / update.bin.tmp.partial files on the drive removed
  //   bundled  files from files/ put on the drive ({ files: [[src, dest]], extract })
  //   drop     a file the user downloads ({ link, expect, accept(file) → [{ dest, blob }] })
  //   package  GZreader's package for this Kindle
  //   guide    a jailbreak done by following another site's guide
  // device: what to do on the Kindle afterwards (HTML); check(scan) → true,
  // or a message; optional: can be skipped.

  var OFF_LEGACY = "<li>On the Kindle: <b>Home → Menu → Turn Wireless Off</b>, and leave it off throughout. (A Kindle 2 or DX has " +
    "3G instead of Wi‑Fi: the same menu item.)</li>";
  var OFF_TOUCH = "<li>On the Kindle: turn on <b>Airplane mode</b> (swipe down from the top, or Settings), so it can't update itself " +
    "to a firmware the jailbreak doesn't handle.</li>";
  var UPDATE = "<b>Home → Menu → Settings → Menu → Update Your Kindle</b>";
  var EJECT = "<li><b>Eject</b> the Kindle on the computer, then unplug it.</li>";
  var BACK = "<li>Plug it in again when it's done, and press <b>Check</b>.</li>";

  function cleanStep() {
    return { id: "clean", kind: "clean", title: "Remove old update files",
      why: "A Kindle installs the first update file it finds. Leftover <code>.bin</code> or <code>update.bin.tmp.partial</code> files " +
        "on the drive would be installed instead of the one this page puts there.",
      check: function (scan) { return scan.strays.length ? "Still there: " + scan.strays.join(", ") : true; } };
  }

  function lpadName(sfx) { return "update_launchpad_0.0.1d_" + sfx + "_install.bin"; }

  function launchpadStep(sfx, optional) {
    return { id: "launchpad", kind: "drop", optional: !!optional, title: "Install Launchpad",
      why: "Launchpad runs programs from keyboard shortcuts. GZreader starts with <b>Shift, G, G</b> (one key after the other), " +
        "so on this Kindle it doesn't need KUAL.",
      link: "https://www.mobileread.com/forums/showthread.php?p=1155117", linkText: "lpad-pkg-001d.zip (MobileRead, needs a free account)",
      expect: "<code>lpad-pkg-001d.zip</code>, or the <code>" + lpadName(sfx) + "</code> file from it",
      accept: async function (file) {
        var want = lpadName(sfx);
        if (new RegExp("^" + want.replace(/\./g, "\\.") + "$", "i").test(file.name)) return [{ dest: want, blob: file }];
        if (!/\.zip$/i.test(file.name)) throw new Error("Drop lpad-pkg-001d.zip or " + want + ".");
        var hit = (await zipEntries(file)).filter(function (e) { return e.name.split("/").pop().toLowerCase() === want.toLowerCase(); })[0];
        if (!hit) throw new Error("That zip has no " + want + " (is it Launchpad 0.0.1d?).");
        return [{ dest: want, blob: await hit.open() }];
      },
      device: "<ol>" + EJECT + "<li>" + UPDATE + ". The Kindle installs it and restarts.</li>" +
        "<li>Press <b>Shift</b> three times, one press after the other. That takes a screenshot if Launchpad is running.</li>" + BACK + "</ol>",
      check: function (scan) {
        return scan.screenshot || scan.launchpad ? true : "No sign of Launchpad yet: no launchpad folder or screenshot.bmp on the drive.";
      } };
  }

  function hotfixStep(optional) {
    return { id: "hotfix", kind: "bundled", optional: !!optional, title: "Install the Universal Hotfix",
      why: "The hotfix keeps the jailbreak through firmware updates, and shows <code>.sh</code> files (scriptlets) as books: " +
        "GZreader's package brings one, <b>GZreader</b>, that starts it.",
      files: [["hotfix/Update_hotfix_universal.bin", "Update_hotfix_universal.bin"]],
      device: "<ol>" + EJECT + "<li>" + UPDATE + ", and choose <b>Update</b> if it asks.</li>" +
        "<li>When it has restarted, open the <b>Run Hotfix</b> book in the library once (and again after any firmware update).</li></ol>" };
  }

  function packageStep(flavour, start) {
    return { id: "gzreader", kind: "package", flavour: flavour, title: "Put GZreader on the Kindle",
      why: "GZreader's <code>" + flavour + "</code> package: the folders <code>koreader</code>, <code>extensions</code> and " +
        (flavour === "kindle-legacy" ? "<code>launchpad</code>" : "<code>documents/GZreader.sh</code>") +
        ", merged into the drive. Your books and an older KOReader's settings stay.",
      device: start,
      check: function (scan) { return scan.gzreader ? true : "No koreader/gzreader-version on the drive yet."; } };
  }

  var START_LEGACY = "<ol>" + EJECT + "<li>Restart the Kindle (<b>Home → Menu → Settings → Menu → Restart</b>) so Launchpad reads " +
    "GZreader's shortcuts.</li><li>Press <b>Shift, G, G</b> (one after the other) to start GZreader. Shift, G, L opens the library; " +
    "Shift, G, N starts it without the Kindle's own software (more free memory).</li><li>The setup guide runs on the first start.</li></ol>";
  var START_KUAL = "<ol>" + EJECT + "<li>Open the <b>KUAL</b> book, then <b>GZreader → Start GZreader</b>.</li>" +
    "<li>The setup guide runs on the first start.</li></ol>";
  var START_TOUCH = "<ol>" + EJECT + "<li>Open <b>GZreader</b> in the library (it shows with GZreader's logo). If it isn't there, " +
    "open the <b>Run Hotfix</b> book once, or start GZreader from KUAL if you have it.</li><li>The setup guide runs on the first start.</li></ol>";

  /** The steps for the Kindle chosen (S.serial, S.fw, S.jailbroken, S.method). */
  function plan() {
    var info = S.serial, m = info && info.model, scan = S.scan || { strays: [], kual: [] };
    if (!m) return [];
    var steps = [], jb = S.jailbroken === true, flavour = packageFor(m, S.fw);
    if (m.family === "none") return [];

    if (m.family === "k2dx" || m.family === "k3") {
      if (!jb) {
        steps.push({ id: "wireless", kind: "info", title: "Turn wireless off", device: "<ol>" + OFF_LEGACY + "</ol>" });
        steps.push(cleanStep());
        var jf = legacyJailbreak(info.sfx, S.fw);
        steps.push({ id: "jailbreak", kind: "bundled", title: "Jailbreak",
          why: "NiLuJe's jailbreak 0.13.N: <code>" + jf + "</code>, the file for a " + esc(info.name) + (m.family === "k3" ? " on firmware " + esc(S.fw) : "") + ".",
          files: [["jailbreak-0.13.N/" + jf, jf]],
          device: "<ol>" + EJECT + "<li>" + UPDATE + ". It's quick.</li>" +
            (m.family === "k2dx" ? "<li>On these Kindles it ends with <b>error U006</b> (bottom left): that's normal and means it worked. " +
              "Don't run it again.</li>" : "<li>The Kindle restarts by itself.</li>") + BACK + "</ol>",
          check: function (s) { return s.strays.indexOf(jf) < 0 || m.family === "k2dx" ? true : jf + " is still on the drive: the update didn't run."; } });
      } else if (scan.strays.length) {
        steps.push(cleanStep());
      }
      if (!jb || !scan.launchpad) steps.push(launchpadStep(info.sfx, jb && scan.kual.length > 0));
      steps.push(packageStep("kindle-legacy", START_LEGACY));
      if (m.family === "k2dx") {
        steps.push({ id: "kualfix", kind: "bundled", optional: true, title: "KUAL that opens on this Kindle (optional)",
          why: "GZreader doesn't need KUAL here. If you want it: since April 2025 the usual KUAL won't open on the Kindle 2/DX " +
            "(\"not signed by a registered developer\"). This is KUAL re-signed for these Kindles with developer keys that don't expire " +
            "(<a href=\"https://github.com/9retirement6irk/kual-dx-fix\" target=\"_blank\" rel=\"noopener\">kual-dx-fix</a>; tested on a " +
            "DX Graphite). Other KUAL books in <code>documents</code> are removed.",
          files: [["kual-dx-fix/documents/KUAL-KDK-1.0.azw2", "documents/KUAL-KDK-1.0.azw2"],
            ["kual-dx-fix/kual-dx-fix/developer.keystore", "kual-dx-fix/developer.keystore"],
            ["kual-dx-fix/kual-dx-fix/install_keystore.sh", "kual-dx-fix/install_keystore.sh"],
            ["kual-dx-fix/kual-dx-fix/restore_keystore.sh", "kual-dx-fix/restore_keystore.sh"],
            ["kual-dx-fix/launchpad/kualfix.ini", "launchpad/kualfix.ini"]],
          removeKual: true,
          device: "<ol>" + EJECT + "<li>Restart the Kindle (<b>Home → Menu → Settings → Menu → Restart</b>).</li>" +
            "<li>Press <b>Shift, K, I</b> (one after the other): it installs the keys.</li>" + BACK + "</ol>",
          check: function (s) {
            var log = s.kualDxLog || "";
            if (/installed keystore OK/.test(log) && /locked \(immutable\) OK/.test(log)) return true;
            return log ? "kual-dx-fix/install.log doesn't say \"installed keystore OK\" and \"locked (immutable) OK\" yet." :
              "No kual-dx-fix/install.log yet: press Shift, K, I on the Kindle.";
          } });
      } else {
        steps.push(kualDropStep(true, "GZreader doesn't need KUAL on a Kindle Keyboard: it starts with Shift, G, G. Since April 2025 " +
          "KUAL may not open on a Kindle Keyboard (\"not signed by a registered developer\"); it does on a Kindle 4."));
      }
      return steps;
    }

    if (m.family === "k4") {
      if (!jb) {
        steps.push({ id: "wireless", kind: "info", title: "Turn wireless off", device: "<ol>" + OFF_LEGACY.replace(" (A Kindle 2 or DX has 3G instead of Wi‑Fi: the same menu item.)", "") + "</ol>" });
        steps.push(cleanStep());
        steps.push({ id: "jailbreak", kind: "drop", title: "Jailbreak",
          why: "NiLuJe's Kindle 4 jailbreak, through the Kindle 4's diagnostics mode. Only its three jailbreak files go on the drive (not the uninstaller in the same zip).",
          link: "https://github.com/KindleModding/K4-Jailbreak/releases/latest/download/K4-Jailbreak.zip", linkText: "K4-Jailbreak.zip",
          expect: "<code>K4-Jailbreak.zip</code>",
          accept: async function (file) {
            var es = await zipEntries(file), names = es.map(function (e) { return e.name; });
            if (names.indexOf("ENABLE_DIAGS") < 0 || names.indexOf("data.tar.gz") < 0) throw new Error("That isn't K4-Jailbreak.zip (no ENABLE_DIAGS and data.tar.gz).");
            var out = [];
            for (var i = 0; i < es.length; i++) {
              var e = es[i];
              if (e.dir) continue;
              if (e.name === "ENABLE_DIAGS" || e.name === "data.tar.gz" || /^diagnostic_logs\//.test(e.name)) out.push({ dest: e.name, blob: await e.open() });
            }
            return out;
          },
          device: "<ol>" + EJECT + "<li>Restart: <b>Menu → Settings → Menu → Restart</b>. It starts in diagnostics mode.</li>" +
            "<li>With the 5-way: <b>D) Exit, Reboot or Disable Diags</b> → <b>R) Reboot System</b> → <b>Q) To continue</b> " +
            "(\"FW Left\" means left on the 5-way).</li><li>After about 20 seconds it restarts normally, with a book called " +
            "<b>You are Jailbroken</b>.</li>" + BACK + "</ol>" });
      } else if (scan.strays.length) {
        steps.push(cleanStep());
      }
      if (!scan.kual.length || !jb) {
        steps.push({ id: "mkk", kind: "drop", title: "New developer keys (since April 2025)",
          why: "The developer keys the jailbreak installs expired in April 2025, and KUAL won't open with them. NiLuJe's 2025 keys fix that on a Kindle 4.",
          link: "https://www.mobileread.com/forums/showthread.php?t=225030", linkText: "NiLuJe's snapshots on MobileRead (the MKK package, 2025-04-19 or newer)",
          expect: "the <code>Update_mkk-…-install.bin</code> file for the Kindle 4 from that package",
          accept: async function (file) {
            if (!/^Update_mkk-.*install\.bin$/i.test(file.name)) throw new Error("Drop the Update_mkk-…-install.bin file (from the MKK package).");
            if (!(await isUpdateFile(file))) throw new Error(file.name + " isn't a Kindle update file.");
            return [{ dest: file.name, blob: file }];
          },
          device: "<ol>" + EJECT + "<li>" + UPDATE + ".</li>" + BACK + "</ol>",
          check: function (s) { return s.strays.some(function (n) { return /^Update_mkk-/i.test(n); }) ? "The Update_mkk file is still on the drive: the update didn't run." : true; } });
        steps.push(kualDropStep(false, "GZreader starts from KUAL on a Kindle 4."));
      }
      steps.push(packageStep("kindle", START_KUAL));
      return steps;
    }

    if (m.family === "kt") {
      if (!jb) {
        steps.push({ id: "wireless", kind: "info", title: "Turn wireless off", device: "<ol><li>On the Kindle: <b>Menu → Turn Wireless Off</b>.</li></ol>" });
        steps.push(cleanStep());
        steps.push({ id: "jailbreak", kind: "drop", title: "Jailbreak",
          why: "NiLuJe's K5 jailbreak, for the Kindle Touch, any firmware up to 5.4.4.2.",
          link: KM + "jailbreaking/Legacy/K5-Jailbreak/kindle-5.4-jailbreak.zip", linkText: "kindle-5.4-jailbreak.zip (kindlemodding.org)",
          expect: "<code>kindle-5.4-jailbreak.zip</code>",
          accept: async function (file) {
            var es = await zipEntries(file), names = es.map(function (e) { return e.name; });
            if (names.indexOf("jb.sh") < 0 || !names.some(function (n) { return /^Update_jb_.*\.bin$/.test(n); })) {
              throw new Error("That isn't kindle-5.4-jailbreak.zip (no jb.sh and Update_jb_….bin).");
            }
            var out = [];
            for (var i = 0; i < es.length; i++) if (!es[i].dir) out.push({ dest: es[i].name, blob: await es[i].open() });
            return out;
          },
          device: "<ol>" + EJECT + "<li>" + UPDATE + ". After a few seconds <b>**** JAILBREAK ****</b> shows at the bottom of the screen.</li>" +
            "<li>Restart the Kindle: <b>Menu → Settings → Menu → Restart</b>.</li>" + BACK + "</ol>",
          check: function (s) { return s.strays.some(function (n) { return /^Update_jb_/i.test(n); }) ? "The jailbreak file is still on the drive: run Update Your Kindle." : true; } });
      } else if (scan.strays.length) {
        steps.push(cleanStep());
      }
      if (!jb || !scan.scriptlets.length) steps.push(hotfixStep(jb));
      steps.push(packageStep("kindle", START_TOUCH));
      return steps;
    }

    // touch Kindles (Paperwhite and newer)
    if (!jb) {
      steps.push({ id: "wireless", kind: "info", title: "Airplane mode", device: "<ol>" + OFF_TOUCH + "</ol>" });
      var ms = methodsFor(m.id, S.fw, S.registered, S.ads);
      var chosen = ms.filter(function (x) { return x.name === S.method; })[0] || ms[0];
      if (chosen) steps.push(cleanStep());
      if (!chosen) {
        steps.push({ id: "nojb", kind: "info", title: "No jailbreak for this firmware yet",
          why: "No known jailbreak works on a " + esc(info.name) + " with firmware " + esc(S.fw) + ". Keep it in airplane mode, so it " +
            "doesn't update further, and check <a href=\"" + KM + "jailbreak-wizard.html\" target=\"_blank\" rel=\"noopener\">kindlemodding.org</a> " +
            "from time to time.", stop: true });
        return steps;
      }
      if (chosen.kind === "wb") {
        steps.push({ id: "jailbreak", kind: "bundled", title: "Jailbreak (WinterBreak)",
          why: "Through the Kindle Store, so the Kindle must be registered to an Amazon account. WinterBreak's files, hidden folder " +
            "<code>.active_content_sandbox</code> included, go on the drive.",
          files: [["winterbreak/WinterBreak.tar.gz", null]], extract: true,
          device: "<ol>" + EJECT + "<li>Restart the Kindle.</li><li>Open the <b>Kindle Store</b> (the cart on the home screen); when it asks, " +
            "choose <b>Yes</b> to turn off airplane mode.</li><li>When Mesquito has loaded, tap the <b>WinterBreak</b> icon.</li>" +
            "<li>Wait about 30 seconds: text runs over the screen and the Kindle restarts its home screen. If nothing happens, " +
            "do this step again. Updates are blocked for you afterwards.</li></ol>" +
            "<p class=\"small muted\">Store shows only its home page, or \"Unexpected error\": " +
            "<a href=\"" + KM + "jailbreaking/WinterBreak/#troubleshooting\" target=\"_blank\" rel=\"noopener\">WinterBreak's troubleshooting</a>.</p>" });
      } else if (chosen.kind === "wb2") {
        steps.push({ id: "jailbreak", kind: "drop", title: "Jailbreak (WinterBreak2)",
          why: "Through the Kindle's web browser, no Amazon registration needed (it needs Wi‑Fi for a moment).",
          link: "https://github.com/KindleModding/Winterbreak2/releases/latest/download/wb2.zip", linkText: "wb2.zip",
          expect: "<code>wb2.zip</code>",
          accept: async function (file) {
            var es = await zipEntries(file);
            if (!es.some(function (e) { return /^winterbreak2\//.test(e.name); })) throw new Error("That isn't wb2.zip (no winterbreak2 folder).");
            var out = [];
            for (var i = 0; i < es.length; i++) if (!es[i].dir) out.push({ dest: es[i].name, blob: await es[i].open() });
            return out;
          },
          device: "<ol>" + EJECT + "<li>Connect the Kindle to Wi‑Fi.</li><li>Open the <b>Experimental Browser</b> (Menu, or Settings → " +
            "Device Options → Advanced) and go to <b>https://penguins184.xyz/wb2</b>.</li><li>Press <b>Jailbreak</b> and wait until it's done. " +
            "Then turn airplane mode on again.</li></ol>" });
      } else {
        steps.push({ id: "jailbreak", kind: "guide", title: "Jailbreak (" + chosen.name + ")",
          why: "This jailbreak isn't automated here: follow kindlemodding.org's guide for it, then come back.",
          link: KM + chosen.page, linkText: chosen.name + " on kindlemodding.org" });
      }
      if (!chosen.hotfix) steps.push(hotfixStep(true));
    } else if (scan.strays.length) {
      steps.push(cleanStep());
    }
    steps.push(packageStep(flavour, START_TOUCH));
    return steps;
  }

  function kualDropStep(optional, why) {
    return { id: "kual", kind: "drop", optional: optional, title: optional ? "KUAL (optional)" : "KUAL",
      why: why + " KUAL is a book that lists programs to start.",
      link: KM + "jailbreaking/Legacy/post-jailbreak/installing-kual-mrpi/KUAL-KDK-1.0.azw2", linkText: "KUAL-KDK-1.0.azw2 (kindlemodding.org)",
      expect: "<code>KUAL-KDK-1.0.azw2</code> (KUAL 2.7.37 or newer)",
      accept: async function (file) {
        if (!/\.azw2$/i.test(file.name)) throw new Error("Drop KUAL-KDK-1.0.azw2.");
        var es = await zipEntries(file), mf = es.filter(function (e) { return e.name === "META-INF/MANIFEST.MF"; })[0];
        var text = mf ? await (await mf.open()).text() : "";
        if (!/Implementation-Title:\s*KUAL/.test(text)) throw new Error("That isn't KUAL.");
        return [{ dest: "documents/KUAL-KDK-1.0.azw2", blob: file }];
      },
      removeKual: true,
      device: "<ol>" + EJECT + "<li>A <b>KUAL</b> book appears in the library.</li></ol>" };
  }

  /** A Kindle update file starts with FC02, FD04, SP01… */
  async function isUpdateFile(file) {
    var h = await file.slice(0, 4).text();
    return /^(FC0[2-4]|FD0[34]|FB0[1-3]|SP01|CB01|FB02)$/.test(h);
  }

  // ------------------------------------------------------------ GZreader's package

  var Pkg = {
    meta: null,
    /** packages.json from the updates branch (the release workflow writes it). */
    latest: async function () {
      if (Pkg.meta) return Pkg.meta;
      try {
        var r = await fetch(S.raw + "packages.json", { cache: "no-store" });
        if (r.ok) Pkg.meta = await r.json();
      } catch (e) {}
      return Pkg.meta;
    },
    fetch: async function (flavour, onProgress) {
      var meta = await Pkg.latest(), p = meta && meta.packages && meta.packages[flavour];
      if (!p) return null;
      var r = await fetch(S.raw + p.file, { cache: "no-store" });
      if (!r.ok) throw new Error("Couldn't download GZreader (" + r.status + ").");
      var total = p.size || +r.headers.get("content-length") || 0, got = 0, chunks = [], reader = r.body.getReader();
      for (;;) {
        var x = await reader.read();
        if (x.done) break;
        chunks.push(x.value); got += x.value.length;
        if (onProgress) onProgress(got, total);
      }
      var blob = new Blob(chunks);
      if (p.sha256 && (await sha256(await blob.arrayBuffer())) !== p.sha256) throw new Error("GZreader didn't download whole: try again.");
      return { blob: blob, version: meta.version };
    },
    /** A package zip dropped by the user: checked to be this flavour. */
    check: async function (file, flavour) {
      var m = /^gzreader-(kindle-legacy|kindle|kindlepw2|kindlehf)-([\d.]+)(?: \(\d+\))?\.zip$/i.exec(file.name);
      if (m && m[1].toLowerCase() !== flavour) throw new Error("That's the " + m[1] + " package: this Kindle takes gzreader-" + flavour + "-….zip.");
      var es = await zipEntries(file), names = es.map(function (e) { return e.name; });
      if (!names.some(function (n) { return /^koreader\/plugins\/gzreader\.koplugin\//.test(n); })) throw new Error("That isn't a GZreader package.");
      if (flavour === "kindle-legacy" && !names.some(function (n) { return /^launchpad\//.test(n); })) throw new Error("That isn't the kindle-legacy package (no launchpad folder).");
      if (flavour !== "kindle-legacy" && names.some(function (n) { return /^launchpad\//.test(n); })) throw new Error("That's the kindle-legacy package: this Kindle takes gzreader-" + flavour + "-….zip.");
      return es;
    },
  };

  // ------------------------------------------------------------ rendering

  function save() {
    try {
      localStorage.setItem("gzsetup", JSON.stringify({ model: S.serial && S.serial.model.id, code: S.serial && S.serial.code,
        fw: S.fw, registered: S.registered, ads: S.ads, jailbroken: S.jailbroken, method: S.method, at: S.at, done: S.done }));
    } catch (e) {}
  }
  function restore() {
    var s = null;
    try { s = JSON.parse(localStorage.getItem("gzsetup") || "null"); } catch (e) {}
    if (!s || !s.model) return;
    var m = MODELS.filter(function (x) { return x.id === s.model; })[0];
    if (!m) return;
    S.serial = { model: m, code: s.code, sfx: m.sfx && m.sfx[s.code], name: (m.names && m.names[s.code]) || m.name };
    S.fw = s.fw || ""; S.registered = s.registered; S.ads = s.ads; S.jailbroken = s.jailbroken; S.method = s.method;
    S.at = s.at || 0; S.done = s.done || {};
  }

  function show(sel, on) { var e = $(sel); if (e) e.classList.toggle("hidden", !on); }
  function note(box, text, cls) { box.appendChild(el("p", { class: "small " + (cls || "") }, text)); }

  async function connect(handle) {
    S.root = handle;
    if (handle.requestPermission && !S.test) {
      var ok = (await handle.queryPermission({ mode: "readwrite" })) === "granted" ||
        (await handle.requestPermission({ mode: "readwrite" })) === "granted";
      if (!ok) throw new Error("The page needs permission to write to the Kindle.");
    }
    if (!S.test) await idb.set("drive", handle);
    await rescan(true);
  }

  async function rescan(connected) {
    try {
      S.scan = await scanDrive(S.root);
    } catch (e) {
      S.scan = null; S.root = null;
      renderAll();
      problem("The Kindle isn't there any more (unplugged or ejected). Plug it in and choose it again.");
      return;
    }
    // the model from GZreader's sync outbox (Kindle 2/DX), if not typed yet
    if (!S.serial && S.scan.outboxModel && OUTBOX_MODELS[S.scan.outboxModel]) {
      var om = OUTBOX_MODELS[S.scan.outboxModel], mm = MODELS.filter(function (x) { return x.id === om[0]; })[0];
      S.serial = { model: mm, code: om[1], sfx: mm.sfx[om[1]], name: (mm.names && mm.names[om[1]]) || mm.name, fromOutbox: true };
    }
    if (S.jailbroken === null) S.jailbroken = !!(S.scan.markers.length || S.scan.gzreader);
    // a Kindle with GZreader on it is jailbroken, whatever was answered last time
    else if (connected && S.scan.gzreader && S.jailbroken === false) { S.jailbroken = true; S.at = 0; save(); }
    renderAll();
  }

  function problem(text) {
    var box = $("#problem");
    box.textContent = text;
    show("#problem", !!text);
  }

  function renderAll() {
    problem("");
    renderDrive();
    renderKindle();
    renderSteps();
  }

  function renderDrive() {
    var box = $("#drive-status");
    box.innerHTML = "";
    show("#pick-again", !!S.root);
    if (!S.root) { show("#drive-ok", false); return; }
    var sc = S.scan;
    if (!sc) return;
    show("#drive-ok", true);
    if (sc.pickedDocuments) note(box, "That looks like the Kindle's documents folder: choose the drive itself (the folder above it).", "bad");
    else if (!sc.isKindle) note(box, "This doesn't look like a Kindle's drive (no documents and system folders). Check you chose the Kindle.", "bad");
    else note(box, "Kindle drive connected" + (S.test ? " (pretend Kindle)" : "") + ".", "ok");
    if (sc.gzreader) note(box, "GZreader " + sc.gzreader + " is installed: this puts the newest version on.");
    if (sc.markers.length) note(box, "Found: " + sc.markers.join(", ") + ".");
  }

  function renderKindle() {
    var s = S.serial, m = s && s.model;
    show("#kindle-card", !!S.root);
    if (!S.root) return;
    var st = $("#serial-status"), fwRow = $("#fw-row"), q = $("#touch-q"), jbq = $("#jb-q");
    st.innerHTML = "";
    if (s) {
      st.appendChild(el("span", { class: "ok" }, s.name + (s.fromOutbox ? " (from GZreader on it)" : "")));
      if (m.family === "none") st.appendChild(el("span", { class: "bad" }, ": GZreader doesn't run on this Kindle."));
    }
    show("#fw-row", !!(m && m.needsFw));
    if (m && m.needsFw) {
      var fs = $("#fw-status");
      fs.textContent = !S.fw ? "" : !validFw(S.fw) ? "That isn't a firmware version (like 5.16.2.1.1)." :
        m.family === "k3" && (cmpVer(S.fw, "3.0") < 0 || cmpVer(S.fw, "3.4.3") > 0) ? "A Kindle Keyboard has firmware 3.0 – 3.4.3." :
        m.family === "touch" && cmpVer(S.fw, "5.0") < 0 ? "Touch Kindles have firmware 5.x." : "";
      fs.className = "small " + (fs.textContent ? "bad" : "");
    }
    // touch Kindles: questions that pick between jailbreaks
    var ready = m && m.family !== "none" && (!m.needsFw || (validFw(S.fw) && !$("#fw-status").textContent));
    var touchQ = ready && m.family === "touch" && S.jailbroken === false;
    show("#touch-q", !!touchQ);
    if (touchQ) {
      var all = methodsFor(m.id, S.fw, null, null);
      show("#q-reg", all.some(function (x) { return x.reg; }));
      show("#q-ads", all.some(function (x) { return x.ads; }));
      var ms = methodsFor(m.id, S.fw, S.registered, S.ads), sel = $("#method");
      sel.innerHTML = "";
      ms.forEach(function (x, i) {
        sel.appendChild(el("option", { value: x.name }, x.name + (i === 0 ? " (recommended)" : "") + (x.kind === "wb" ? ", files included here" : "")));
      });
      if (S.method && ms.some(function (x) { return x.name === S.method; })) sel.value = S.method;
      show("#method-row", ms.length > 1);
    }
    show("#jb-q", !!ready);
    if (ready) {
      $("#jb-yes").checked = S.jailbroken === true;
      $("#jb-no").checked = S.jailbroken === false;
      $("#jb-hint").textContent = S.scan && S.scan.markers.length ? "Found on the drive: " + S.scan.markers.join(", ") + "." :
        "Nothing on the drive says it's jailbroken.";
    }
  }

  function currentSteps() {
    var m = S.serial && S.serial.model;
    if (!m || !S.root || m.family === "none" || S.jailbroken === null) return [];
    if (m.needsFw && (!validFw(S.fw) || $("#fw-status").textContent)) return [];
    return plan();
  }

  function renderSteps() {
    var steps = currentSteps(), box = $("#steps"), list = $("#step-list");
    S.steps = steps;
    show("#steps-card", steps.length > 0);
    if (!steps.length) return;
    if (S.at >= steps.length) S.at = steps.length - 1;
    list.innerHTML = "";
    steps.forEach(function (st, i) {
      var li = el("li", { class: (i === S.at ? "on " : "") + (S.done[st.id] ? "done" : ""), "data-step": st.id },
        el("button", { class: "link", onclick: function () { S.at = i; save(); renderSteps(); } }, st.title + (st.optional ? "" : "")));
      list.appendChild(li);
    });
    var st = steps[S.at];
    box.innerHTML = "";
    box.setAttribute("data-step", st.id);
    box.appendChild(el("h3", {}, (S.at + 1) + ". " + st.title));
    if (st.why) box.appendChild(el("p", { class: "small", html: st.why }));
    var act = el("div", { class: "act" }), out = el("div", { class: "out" });
    box.appendChild(act);
    renderAction(st, act, out);
    box.appendChild(out);
    if (st.device) box.appendChild(el("div", { class: "device", html: "<h4>Then, on the Kindle</h4>" + st.device }));
    var nav = el("div", { class: "row navrow" });
    if (st.check) nav.appendChild(el("button", { id: "check", onclick: function () { doCheck(st, out); } }, "Check"));
    if (!S.test && S.root && st.device && /Eject/.test(st.device)) nav.appendChild(el("button", { onclick: ejectHint }, "How to eject"));
    if (S.at > 0) nav.appendChild(el("button", { onclick: function () { S.at--; save(); renderSteps(); } }, "Back"));
    if (!st.stop && S.at < steps.length - 1) {
      nav.appendChild(el("button", { class: "primary", id: "next", onclick: function () { S.done[st.id] = true; S.at++; save(); renderSteps(); } },
        st.optional && !S.done[st.id] ? "Skip" : "Next step"));
    } else if (!st.stop) {
      nav.appendChild(el("button", { class: "primary", id: "finish", onclick: function () { S.done[st.id] = true; save(); renderSteps(); finished(); } }, "Done"));
    }
    box.appendChild(nav);
  }

  function ejectHint() {
    alertBox("Windows: the USB icon by the clock → Eject Kindle. Mac: drag the Kindle to the Trash, or the eject arrow in Finder. " +
      "Linux: Eject in the file manager. The Kindle shows its normal screen again when it's safe to unplug.");
  }
  function alertBox(text) {
    var p = el("p", { class: "warn small" }, text);
    $("#steps").appendChild(p);
    setTimeout(function () { p.remove(); }, 15000);
  }

  function finished() {
    var box = $("#steps");
    box.appendChild(el("p", { class: "done ok", id: "all-done" }, "All done. Enjoy GZreader!"));
    box.appendChild(el("p", { class: "small", html: "Next: <a href=\"" + WIKI + "Installing#after-installing\" target=\"_blank\" rel=\"noopener\">the first start</a>" +
      (S.serial && S.serial.model.family === "k2dx" ? ", and <a href=\"../sync/\">the sync page</a> for this Kindle without Wi‑Fi." : ".") }));
  }

  async function doCheck(st, out) {
    out.innerHTML = "";
    await rescan();
    var o = $("#steps .out") || out;
    if (!S.scan) return;
    var r = st.check(S.scan);
    if (r === true) { S.done[st.id] = true; save(); renderSteps(); note($("#steps .out"), "Looks right.", "ok"); }
    else note(o, r, "bad");
  }

  function progressBar(out) {
    var bar = el("progress", { max: "1", value: "0" }), txt = el("span", { class: "small muted" });
    out.appendChild(el("div", {}, bar, txt));
    return function (done, total, label) { bar.max = total || 1; bar.value = done; txt.textContent = label || (total ? done + " of " + total : ""); };
  }

  async function removeOtherKual() {
    var docs = await Drive.tryDir(S.root, "documents");
    if (!docs) return [];
    var gone = [];
    for (var e of await Drive.list(docs)) {
      if (/^KUAL.*\.azw2$/i.test(e.name) && e.name !== "KUAL-KDK-1.0.azw2") { await Drive.remove(docs, e.name); gone.push(e.name); }
    }
    return gone;
  }

  function renderAction(st, act, out) {
    if (st.kind === "clean") {
      var sc = S.scan || { strays: [] };
      if (!sc.strays.length) { note(act, "None on the drive.", "ok"); S.done[st.id] = true; return; }
      note(act, "On the drive: " + sc.strays.join(", "));
      act.appendChild(el("button", { class: "primary", id: "do", onclick: async function () {
        for (var i = 0; i < sc.strays.length; i++) await Drive.remove(S.root, sc.strays[i]);
        await doCheck(st, out);
      } }, "Remove them"));
      return;
    }
    if (st.kind === "bundled") {
      act.appendChild(el("button", { class: "primary", id: "do", onclick: async function () {
        out.innerHTML = "";
        var bar = progressBar(out);
        try {
          if (st.removeKual) { var gone = await removeOtherKual(); if (gone.length) note(out, "Removed: " + gone.join(", ")); }
          for (var i = 0; i < st.files.length; i++) {
            var f = st.files[i], blob = await bundled(f[0]);
            if (st.extract) {
              var es = await archiveEntries(blob, f[0]);
              await writeEntries(S.root, es, null, function (d, t) { bar(d, t, d + " of " + t + " files"); });
            } else {
              await Drive.write(S.root, f[1], blob);
              bar(i + 1, st.files.length);
            }
          }
          note(out, "On the Kindle." + (st.files.length === 1 && !st.extract ? " (" + st.files[0][1] + ")" : ""), "ok");
          S.done[st.id + ":files"] = true; save();
        } catch (e) { note(out, e.message, "bad"); }
      } }, "Put " + (st.files.length > 1 || st.extract ? "the files" : "it") + " on the Kindle"));
      return;
    }
    if (st.kind === "drop") {
      act.appendChild(el("p", { class: "small", html: "1. Download " + st.expect + ": <a href=\"" + st.link + "\" target=\"_blank\" rel=\"noopener\">" + esc(st.linkText) + "</a>." }));
      act.appendChild(el("p", { class: "small" }, "2. Drop it here, or choose it. The page checks it, then puts it on the Kindle."));
      act.appendChild(dropZone(async function (file) {
        out.innerHTML = "";
        try {
          var files = await st.accept(file);
          if (st.removeKual) { var gone = await removeOtherKual(); if (gone.length) note(out, "Removed: " + gone.join(", ")); }
          for (var i = 0; i < files.length; i++) await Drive.write(S.root, files[i].dest, files[i].blob);
          note(out, "On the Kindle: " + files.map(function (f) { return f.dest; }).join(", "), "ok");
          S.done[st.id + ":files"] = true; save();
        } catch (e) { note(out, e.message, "bad"); }
      }));
      return;
    }
    if (st.kind === "guide") {
      act.appendChild(el("p", { html: "<a class=\"button\" href=\"" + st.link + "\" target=\"_blank\" rel=\"noopener\">" + esc(st.linkText) + "</a>" }));
      note(act, "When it says the Kindle is jailbroken, come back here for the next step.", "muted");
      return;
    }
    if (st.kind === "package") {
      var go = el("button", { class: "primary", id: "do" }, "Download GZreader and put it on the Kindle");
      act.appendChild(go);
      var alt = el("div", { class: "hidden", id: "pkg-drop" });
      alt.appendChild(el("p", { class: "small", html: "Or download <b>gzreader-" + st.flavour + "-&lt;version&gt;.zip</b> from the " +
        "<a href=\"" + RELEASES + "\" target=\"_blank\" rel=\"noopener\">latest release</a> and drop it here:" }));
      alt.appendChild(dropZone(async function (file) {
        out.innerHTML = "";
        try { await installPackage(await Pkg.check(file, st.flavour), out, file.name); }
        catch (e) { note(out, e.message, "bad"); }
      }));
      act.appendChild(alt);
      go.onclick = async function () {
        out.innerHTML = "";
        go.disabled = true;
        try {
          var bar = progressBar(out);
          var got = await Pkg.fetch(st.flavour, function (d, t) { bar(d, t, mb(d) + (t ? " of " + mb(t) : "")); });
          if (!got) {
            note(out, "This page can't download GZreader by itself yet: use the release's zip below.", "bad");
            show("#pkg-drop", true);
            return;
          }
          await installPackage(await zipEntries(got.blob), out, "GZreader " + got.version);
        } catch (e) { note(out, e.message, "bad"); show("#pkg-drop", true); }
        finally { go.disabled = false; }
      };
      Pkg.latest().then(function (meta) {
        if (meta && meta.version) go.textContent = "Download GZreader " + meta.version + " and put it on the Kindle";
        else show("#pkg-drop", true);
      });
    }
  }

  async function installPackage(entries, out, what) {
    var bar = progressBar(out);
    var t0 = Date.now();
    var written = await writeEntries(S.root, entries, function (n) {
      return /^(koreader|extensions|launchpad|documents)\//.test(n) ? n : null;
    }, function (d, t) { bar(d, t, d + " of " + t + " files"); });
    S.done["gzreader:files"] = true; S.done.gzreader = true; save();
    await rescan();
    note($("#steps .out") || out, what + ": " + written.length + " files on the Kindle (" + Math.round((Date.now() - t0) / 1000) + " s).", "ok");
  }

  function dropZone(onFile) {
    var input = el("input", { type: "file", class: "hidden" });
    var zone = el("div", { class: "drop", tabindex: "0", role: "button" }, "Drop the file here, or click to choose it");
    zone.onclick = function () { input.click(); };
    zone.onkeydown = function (e) { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); input.click(); } };
    input.onchange = function () { var f = input.files && input.files[0]; input.value = ""; if (f) onFile(f); };
    zone.ondragover = function (e) { e.preventDefault(); zone.classList.add("over"); };
    zone.ondragleave = function () { zone.classList.remove("over"); };
    zone.ondrop = function (e) { e.preventDefault(); zone.classList.remove("over"); var f = e.dataTransfer.files && e.dataTransfer.files[0]; if (f) onFile(f); };
    var wrap = el("div", {}, zone, input);
    wrap.input = input;
    return wrap;
  }

  // ------------------------------------------------------------ start

  async function testDrive(reset) {
    var opfs = await navigator.storage.getDirectory();
    if (reset) { try { await opfs.removeEntry("gzsetup-kindle", { recursive: true }); } catch (e) {} }
    var root = await opfs.getDirectoryHandle("gzsetup-kindle", { create: true });
    if (reset || !(await Drive.tryDir(root, "documents"))) {
      await Drive.dir(root, "documents", true);
      await Drive.dir(root, "system", true);
      await Drive.dir(root, "audible", true);
    }
    return root;
  }

  async function start() {
    var params = new URLSearchParams(location.search);
    S.test = params.has("test");
    if (S.test && params.get("raw")) S.raw = params.get("raw").replace(/\/?$/, "/");
    restore();
    if (S.test) {
      show("#testbar", true);
      $("#test-reset").onclick = async function () {
        try { localStorage.removeItem("gzsetup"); } catch (e) {}
        location.reload();
      };
      $("#test-leave").onclick = function () { location.href = location.pathname; };
    } else if (!window.showDirectoryPicker) {
      show("#unsupported", true);
      $("#pick").disabled = true;
    }
    $("#pick").onclick = $("#pick-again").onclick = async function () {
      try {
        if (S.test) await connect(await testDrive(false));
        else await connect(await window.showDirectoryPicker({ id: "gzkindle", mode: "readwrite" }));
      } catch (e) { if (e.name !== "AbortError") problem(e.message); }
    };
    var last = !S.test && await idb.get("drive");
    if (last) {
      show("#reopen", true);
      $("#reopen").textContent = "Use “" + last.name + "” again";
      $("#reopen").onclick = async function () { try { await connect(last); } catch (e) { problem(e.message); } };
    }
    $("#serial").oninput = function () {
      var r = modelFromSerial(this.value);
      $("#serial-err").textContent = r.error || "";
      if (r.model) {
        var changed = !S.serial || S.serial.model.id !== r.model.id || S.serial.code !== r.code;
        S.serial = r;
        if (changed) { S.at = 0; S.done = {}; S.method = null; }
        save();
      }
      renderKindle(); renderSteps();
    };
    $("#fw").oninput = function () { S.fw = this.value.trim(); S.at = 0; save(); renderKindle(); renderSteps(); };
    if (S.fw) $("#fw").value = S.fw;
    document.querySelectorAll('input[name="reg"]').forEach(function (r) {
      r.onchange = function () { S.registered = r.value === "yes"; S.method = null; save(); renderKindle(); renderSteps(); };
    });
    document.querySelectorAll('input[name="ads"]').forEach(function (r) {
      r.onchange = function () { S.ads = r.value === "yes"; S.method = null; save(); renderKindle(); renderSteps(); };
    });
    $("#method").onchange = function () { S.method = this.value; S.at = 0; save(); renderSteps(); };
    $("#jb-yes").onchange = function () { S.jailbroken = true; S.at = 0; save(); renderKindle(); renderSteps(); };
    $("#jb-no").onchange = function () { S.jailbroken = false; S.at = 0; save(); renderKindle(); renderSteps(); };
    $("#start-over").onclick = function () {
      try { localStorage.removeItem("gzsetup"); } catch (e) {}
      S.serial = null; S.fw = ""; S.registered = S.ads = S.jailbroken = S.method = null; S.at = 0; S.done = {};
      $("#serial").value = ""; $("#fw").value = "";
      if (S.scan) S.jailbroken = !!(S.scan.markers.length || S.scan.gzreader);
      renderAll();
    };
    renderAll();
  }

  window.GZSetup = { modelFromSerial: modelFromSerial, methodsFor: methodsFor, legacyJailbreak: legacyJailbreak, packageFor: packageFor,
    cmpVer: cmpVer, plan: plan, scanDrive: scanDrive, zipEntries: zipEntries, tarEntries: tarEntries, BUNDLED: BUNDLED, S: S, Pkg: Pkg,
    rescan: rescan };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start); else start();
})();
