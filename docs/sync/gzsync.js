/*
GZreader: sync with computer (https://9retirement6irk.github.io/GZreader/sync/).

For Kindles without Wi-Fi. GZreader leaves .gzsync/outbox.json in its folder
on the Kindle (what to send to Grimmory, the sync queue, what's on the
Kindle); this page, with the Kindle plugged in:
  1. sends the outbox's jobs to Grimmory (positions, reading time, ratings,
     bookmarks and highlights, books put on or taken off your shelves);
  2. leaves a copy of the library (library.json, small covers, book pages);
  3. brings what's in the sync queue (books, audiobooks) and the auto-download
     shelf's new books;
  4. Memos: sends the notes written on the Kindle, brings the notes;
  5. calendars: links, CalDAV calendars, .ics files;
  6. Plex: the albums and playlists chosen here;
and writes .gzsync/inbox.json (after each step: what's there so far). The
next time GZreader starts it takes all that in (gzreader_usbsync.lua).

Nothing leaves this browser except to your own servers (and plex.tv for a
Plex sign-in). Sign-ins are kept in this browser's storage; the Kindle never
gets a password or token.
*/
(function () {
  "use strict";

  var FORMAT = 1;
  var PAGE = 100;
  var BOOK_FIELDS = ["id", "title", "authors", "primaryFileType", "primaryFileName", "primaryFileId", "fileSizeKb",
    "readProgress", "readStatus", "seriesName", "seriesNumber", "coverUpdatedOn", "audiobookCoverUpdatedOn", "libraryId",
    "isPhysical", "personalRating", "addedOn", "lastReadTime", "publishedDate", "pageCount", "goodreadsRating"];
  var READABLE = ["EPUB", "PDF", "FB2", "MOBI", "AZW3", "CBX"];
  var COVER_W = 160, COVER_H = 240;

  function $(s) { return document.querySelector(s); }
  function el(tag, attrs, text) {
    var e = document.createElement(tag);
    for (var k in attrs || {}) { if (k === "class") e.className = attrs[k]; else e.setAttribute(k, attrs[k]); }
    if (text != null) e.textContent = text;
    return e;
  }

  // ------------------------------------------------------------ storage in this browser

  var LS = {
    get: function (k, d) {
      try { var v = localStorage.getItem("gzsync." + k); return v == null ? d : JSON.parse(v); } catch (e) { return d; }
    },
    set: function (k, v) { try { localStorage.setItem("gzsync." + k, JSON.stringify(v)); } catch (e) {} },
    del: function (k) { try { localStorage.removeItem("gzsync." + k); } catch (e) {} },
  };

  // file and folder handles (the Kindle, .ics files) live in IndexedDB
  var idb = {
    db: null,
    open: function () {
      if (this.db) return Promise.resolve(this.db);
      var self = this;
      return new Promise(function (ok, bad) {
        var r = indexedDB.open("gzsync", 1);
        r.onupgradeneeded = function () { r.result.createObjectStore("kv"); };
        r.onsuccess = function () { self.db = r.result; ok(r.result); };
        r.onerror = function () { bad(r.error); };
      });
    },
    get: function (k) {
      return this.open().then(function (db) {
        return new Promise(function (ok) {
          var t = db.transaction("kv").objectStore("kv").get(k);
          t.onsuccess = function () { ok(t.result); };
          t.onerror = function () { ok(undefined); };
        });
      }).catch(function () { return undefined; });
    },
    set: function (k, v) {
      return this.open().then(function (db) {
        return new Promise(function (ok) {
          var t = db.transaction("kv", "readwrite");
          t.objectStore("kv").put(v, k);
          t.oncomplete = function () { ok(); };
          t.onerror = function () { ok(); };
        });
      }).catch(function () {});
    },
    del: function (k) {
      return this.open().then(function (db) {
        return new Promise(function (ok) {
          var t = db.transaction("kv", "readwrite");
          t.objectStore("kv").delete(k);
          t.oncomplete = function () { ok(); };
          t.onerror = function () { ok(); };
        });
      }).catch(function () {});
    },
  };

  // ------------------------------------------------------------ the activity list

  function log(text, kind) {
    var li = el("li", kind ? { class: kind } : null, text);
    $("#log").appendChild(li);
    li.scrollIntoView({ block: "nearest" });
  }
  function phase(text) { $("#phase").textContent = text || ""; }
  var bar = {
    set: function (done, total) {
      var b = $("#bar");
      b.classList.remove("hidden");
      if (total) { b.max = total; b.value = Math.min(done, total); } else { b.removeAttribute("value"); }
    },
    hide: function () { $("#bar").classList.add("hidden"); },
  };
  // (calendar links carry secret keys: only their host in what's shown)
  function hostOf(u) { try { return new URL(u.replace(/^webcal:/i, "https:")).host; } catch (e) { return "link"; } }
  function mb(bytes) { return (bytes / 1048576).toFixed(bytes > 104857600 ? 0 : 1) + " MB"; }

  function HttpError(status, what) { this.status = status; this.message = (what || "the server") + " answered " + status; }
  HttpError.prototype = Object.create(Error.prototype);

  function rand(n) {
    var b = new Uint8Array(n);
    crypto.getRandomValues(b);
    return Array.prototype.map.call(b, function (x) { return ("0" + x.toString(16)).slice(-2); }).join("");
  }
  function b64url(buf) {
    var s = String.fromCharCode.apply(null, new Uint8Array(buf));
    return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  function qs(params) {
    var parts = [];
    Object.keys(params).forEach(function (k) {
      var v = params[k];
      if (v == null || v === "") return;
      (Array.isArray(v) ? v : [v]).forEach(function (x) { parts.push(encodeURIComponent(k) + "=" + encodeURIComponent(x)); });
    });
    return parts.length ? "?" + parts.join("&") : "";
  }
  function normalizeServer(s) {
    s = String(s || "").trim().replace(/\/+$/, "");
    if (!s) return null;
    if (!/^https?:\/\//i.test(s)) s = "https://" + s;
    try { var u = new URL(s); return u.origin + u.pathname.replace(/\/+$/, ""); } catch (e) { return null; }
  }
  function mixedContent(server) {
    return location.protocol === "https:" && /^http:/i.test(server) && !/^http:\/\/(localhost|127\.0\.0\.1)(:|\/|$)/i.test(server);
  }

  // a few at a time
  function pool(items, n, fn) {
    var i = 0;
    function worker() {
      if (i >= items.length) return Promise.resolve();
      var k = i++;
      return Promise.resolve(fn(items[k], k)).then(worker);
    }
    var ws = [];
    for (var w = 0; w < Math.min(n, items.length); w++) ws.push(worker());
    return Promise.all(ws);
  }

  // ------------------------------------------------------------ the Kindle's drive

  var Drive = {
    root: null, gz: null, sync: null,
    dir: async function (parent, path, create) {
      var d = parent;
      var parts = String(path || "").split("/").filter(Boolean);
      for (var i = 0; i < parts.length; i++) d = await d.getDirectoryHandle(parts[i], { create: !!create });
      return d;
    },
    tryDir: async function (parent, path) { try { return await Drive.dir(parent, path); } catch (e) { return null; } },
    file: async function (parent, path, create) {
      var parts = String(path).split("/");
      var name = parts.pop();
      var d = await Drive.dir(parent, parts.join("/"), create);
      return d.getFileHandle(name, { create: !!create });
    },
    readText: async function (parent, path) {
      try { return await (await (await Drive.file(parent, path)).getFile()).text(); } catch (e) { return null; }
    },
    readJSON: async function (parent, path) {
      var t = await Drive.readText(parent, path);
      if (t == null) return null;
      try { return JSON.parse(t); } catch (e) { return null; }
    },
    has: async function (parent, path) { try { await Drive.file(parent, path); return true; } catch (e) { return false; } },
    write: async function (parent, path, data) {
      var fh = await Drive.file(parent, path, true);
      var w = await fh.createWritable();
      await w.write(data);
      await w.close(); // (Chrome writes a copy and swaps it in on close: never half a file)
    },
    writeStream: async function (parent, path, body, onBytes) {
      var fh = await Drive.file(parent, path, true);
      var w = await fh.createWritable();
      var reader = body.getReader();
      try {
        for (;;) {
          var r = await reader.read();
          if (r.done) break;
          await w.write(r.value);
          if (onBytes) onBytes(r.value.length);
        }
        await w.close();
      } catch (e) {
        try { await w.abort(); } catch (e2) {}
        throw e;
      }
    },
    remove: async function (parent, path) {
      var parts = String(path).split("/");
      var name = parts.pop();
      try { var d = await Drive.dir(parent, parts.join("/")); await d.removeEntry(name, { recursive: true }); } catch (e) {}
    },
    list: async function (dir) {
      var out = [];
      try { for await (var entry of dir.values()) out.push(entry.name); } catch (e) {}
      return out;
    },
    // the GZreader folder: the drive picked, its documents folder, or the folder itself
    locate: async function (root) {
      var tries = ["documents/GZreader", "GZreader", ""];
      for (var i = 0; i < tries.length; i++) {
        var gz = tries[i] ? await Drive.tryDir(root, tries[i]) : root;
        if (!gz) continue;
        var sync = await Drive.tryDir(gz, ".gzsync");
        if (sync) return { gz: gz, sync: sync };
        if (tries[i] || root.name === "GZreader") return { gz: gz, sync: await Drive.dir(gz, ".gzsync", true) };
      }
      return null;
    },
  };

  async function permitted(handle, mode) {
    if (!handle || !handle.queryPermission) return true;
    var opts = { mode: mode || "readwrite" };
    if ((await handle.queryPermission(opts)) === "granted") return true;
    try { return (await handle.requestPermission(opts)) === "granted"; } catch (e) { return false; }
  }

  // ------------------------------------------------------------ Grimmory

  var G = {
    st: null, // { server, user, access, refresh, exp } (in the Vault)
    save: function () { Vault.save(); },
    connected: function () { return !!(G.st && G.st.server && G.st.refresh); },
    keep: function (d) {
      G.st.access = d.accessToken;
      G.st.refresh = d.refreshToken || G.st.refresh;
      G.st.exp = Date.now() + (Number(d.expires) || 7200) * 1000;
      G.save();
    },
    token: async function () {
      if (G.st.access && Date.now() < (G.st.exp || 0) - 120000) return G.st.access;
      var r = await fetch(G.st.server + "/api/v1/auth/refresh", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ refreshToken: G.st.refresh }),
      });
      if (r.status === 400 || r.status === 401 || r.status === 403) {
        G.st.refresh = null; G.st.access = null; G.save(); renderConnections();
        throw new Error("Grimmory signed this browser out: sign in again.");
      }
      if (!r.ok) throw new HttpError(r.status, "Grimmory");
      G.keep(await r.json());
      return G.st.access;
    },
    fetch: async function (path, opts) {
      opts = opts || {};
      for (var attempt = 0; attempt < 2; attempt++) {
        var t = await G.token();
        var h = Object.assign({ Authorization: "Bearer " + t }, opts.headers || {});
        var body = opts.body;
        if (body !== undefined && typeof body !== "string") { body = JSON.stringify(body); h["Content-Type"] = "application/json"; }
        var r = await fetch(G.st.server + path, { method: opts.method || "GET", headers: h, body: body });
        if (r.status === 401 && attempt === 0) { G.st.access = null; continue; }
        return r;
      }
    },
    json: async function (path) {
      var r = await G.fetch(path);
      if (!r.ok) throw new HttpError(r.status, "Grimmory");
      return r.json();
    },
    me: async function () {
      try { var me = await G.json("/api/v1/users/me"); return me.username || me.name || null; } catch (e) { return null; }
    },
    login: async function (server, user, pass) {
      var base = normalizeServer(server);
      if (!base) throw new Error("Enter your Grimmory address.");
      if (mixedContent(base)) throw new Error("A web page can only reach Grimmory over https://.");
      var r = await fetch(base + "/api/v1/auth/login", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ username: user, password: pass }),
      });
      if (r.status === 401 || r.status === 403 || r.status === 400) throw new Error("Wrong username or password.");
      if (r.status === 429) throw new Error("Too many attempts. Wait a minute and try again.");
      if (!r.ok) throw new HttpError(r.status, "Grimmory");
      G.st = { server: base, user: user };
      G.keep(await r.json());
    },
    // single sign-on: the provider sends the browser to the hand-off page
    // (../oauth2-callback), which sends it back here with ?code&state
    redirectUri: function () { return new URL("../oauth2-callback", location.href).href.replace(/\?.*$/, ""); },
    startSso: async function (server) {
      var base = normalizeServer(server);
      if (!base) throw new Error("Enter your Grimmory address first.");
      if (mixedContent(base)) throw new Error("A web page can only reach Grimmory over https://.");
      var ps = await (await fetch(base + "/api/v1/public-settings")).json();
      var pd = ps.oidcProviderDetails || {};
      if (ps.oidcEnabled !== true || !pd.clientId || !pd.issuerUri) throw new Error("Single sign-on isn't turned on for this Grimmory server.");
      var doc = await (await fetch(pd.issuerUri.replace(/\/+$/, "") + "/.well-known/openid-configuration")).json();
      if (!doc.authorization_endpoint) throw new Error("Couldn't reach your identity provider.");
      var st = await (await fetch(base + "/api/v1/auth/oidc/state")).json();
      if (!st.state) throw new Error("Grimmory didn't start single sign-on. Try again.");
      var verifier = rand(32), nonce = rand(16);
      var challenge = b64url(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)));
      var redirect = G.redirectUri();
      LS.set("sso", { base: base, state: st.state, verifier: verifier, nonce: nonce, redirect: redirect, at: Date.now() });
      var ep = doc.authorization_endpoint;
      var auth = ep + (ep.indexOf("?") >= 0 ? "&" : "?") + qs({
        response_type: "code", client_id: pd.clientId, redirect_uri: redirect, scope: pd.scopes || "openid profile email offline_access",
        code_challenge: challenge, code_challenge_method: "S256", state: st.state, nonce: nonce,
      }).slice(1);
      var back = location.origin + location.pathname.replace(/index\.html$/, "");
      location.assign(redirect + "#back=" + encodeURIComponent(back) + "&go=" + encodeURIComponent(auth));
    },
    // (the provider's answer was kept when the page loaded: the Kindle had to be unlocked first)
    finishSso: async function () {
      var back = null;
      try { back = sessionStorage.getItem("gzsync.sso-return"); sessionStorage.removeItem("gzsync.sso-return"); } catch (e) {}
      $("#sso-wait").classList.add("hidden");
      var q = new URLSearchParams(back || "");
      if (!q.get("state") || !(q.get("code") || q.get("error"))) return false;
      var s = LS.get("sso", null);
      LS.del("sso");
      if (!s || s.state !== q.get("state") || Date.now() - s.at > 30 * 60 * 1000) throw new Error("That sign-in has expired. Try single sign-on again.");
      if (q.get("error")) throw new Error("Sign-in didn't complete: " + (q.get("error_description") || q.get("error")));
      var form = new URLSearchParams({ code: q.get("code"), code_verifier: s.verifier, redirect_uri: s.redirect, nonce: s.nonce, state: s.state });
      var r = await fetch(s.base + "/api/v1/auth/oidc/mobile/callback", { method: "POST", body: form });
      if (!r.ok) throw new Error("Grimmory rejected the sign-in (" + r.status + ").");
      G.st = { server: s.base };
      G.keep(await r.json());
      G.st.user = await G.me();
      G.save();
      return true;
    },
  };

  // ------------------------------------------------------------ Memos

  var M = {
    st: null, // { server, token, prefix, user, userName } (in the Vault)
    save: function () { Vault.save(); },
    connected: function () { return !!(M.st && M.st.server && M.st.token); },
    req: async function (method, path, body, params) {
      var prefixes = [M.st.prefix, "/api/v1", "/api"].filter(function (p, i, a) { return p && a.indexOf(p) === i; });
      var last;
      for (var i = 0; i < prefixes.length; i++) {
        var h = { Authorization: "Bearer " + M.st.token };
        if (body !== undefined) h["Content-Type"] = "application/json";
        var r = await fetch(M.st.server + prefixes[i] + path + qs(params || {}), {
          method: method, headers: h, body: body === undefined ? undefined : JSON.stringify(body),
        });
        if (r.status !== 404 && r.status !== 410) {
          if (r.ok && prefixes[i] !== M.st.prefix) { M.st.prefix = prefixes[i]; M.save(); }
          return r;
        }
        last = last && last.status === 404 ? last : r;
      }
      return last;
    },
    me: async function () {
      var r = await M.req("GET", "/auth/me");
      if (r.status === 401 || r.status === 403) throw new Error("Memos didn't accept the access token.");
      if (!r.ok) throw new HttpError(r.status, "Memos");
      var d = await r.json();
      var u = d.user || d;
      return { name: u.name, username: u.username || u.displayName };
    },
    connect: async function (server, token) {
      var base = normalizeServer(server);
      if (!base || !token) throw new Error("Enter the Memos address and an access token.");
      if (mixedContent(base)) throw new Error("A web page can only reach Memos over https://.");
      M.st = { server: base, token: token.trim() };
      try {
        var u = await M.me();
        M.st.user = u.username; M.st.userName = u.name;
        M.save();
      } catch (e) { M.st = null; throw e; }
    },
  };

  // what the Notes tab keeps of a note (gzreader_memos.lua Memos.slim)
  function slimMemo(m) {
    var loc = m.location && typeof m.location === "object" ? m.location : null;
    return {
      name: m.name, content: m.content || "", pinned: m.pinned === true, visibility: m.visibility,
      tags: Array.isArray(m.tags) ? m.tags : [], created: m.createTime, updated: m.updateTime,
      place: loc && loc.placeholder ? loc.placeholder : undefined,
      attachments: (m.attachments || []).map(function (a) {
        return { name: a.name, filename: a.filename, type: a.type, size: Number(a.size) || undefined, link: a.externalLink || undefined };
      }),
    };
  }
  // where the Kindle keeps an attachment (Memos.filePath)
  function memoFileName(att) {
    var uid = (String(att.name || "").match(/attachments\/(.+)$/) || [, "x"])[1];
    var fname = String(att.filename || "file").replace(/[\/\\:*?"<>|\x00-\x1f]/g, "_");
    return uid.replace(/[^A-Za-z0-9\-_]/g, "_") + "-" + fname;
  }

  // ------------------------------------------------------------ Plex

  var P = {
    st: null, // { token, user, server: { name, uri, token } } (in the Vault)
    clientId: function () {
      var id = Vault.plexClient;
      if (!id) { id = Vault.plexClient = "gzreader-sync-" + rand(8); Vault.save(); }
      return id;
    },
    save: function () { Vault.save(); },
    connected: function () { return !!(P.st && P.st.token && P.st.server && P.st.server.uri); },
    headers: function (token) {
      var h = { "X-Plex-Product": "GZreader", "X-Plex-Version": "sync", "X-Plex-Client-Identifier": P.clientId(),
        "X-Plex-Platform": "Chrome", "X-Plex-Device": "Browser", "X-Plex-Device-Name": "GZreader sync page", Accept: "application/json" };
      if (token) h["X-Plex-Token"] = token;
      return h;
    },
    tv: async function (method, path, token) {
      var r = await fetch("https://plex.tv" + path, { method: method, headers: P.headers(token) });
      if (!r.ok) throw new HttpError(r.status, "plex.tv");
      return r.json();
    },
    signIn: async function (onWaiting) {
      var pin = await P.tv("POST", "/api/v2/pins?strong=true");
      var url = "https://app.plex.tv/auth#?" + "clientID=" + encodeURIComponent(P.clientId()) + "&code=" + encodeURIComponent(pin.code)
        + "&context%5Bdevice%5D%5Bproduct%5D=GZreader";
      var win = window.open(url, "plexauth", "width=520,height=720");
      if (onWaiting) onWaiting(!win);
      var token = null;
      for (var i = 0; i < 150 && !token; i++) {
        await new Promise(function (ok) { setTimeout(ok, 2000); });
        var d = await P.tv("GET", "/api/v2/pins/" + pin.id + qs({ code: pin.code }));
        token = d.authToken || null;
      }
      try { if (win) win.close(); } catch (e) {}
      if (!token) throw new Error("The Plex sign-in wasn't finished.");
      var user = await P.tv("GET", "/api/v2/user", token);
      var res = await P.tv("GET", "/api/v2/resources" + qs({ includeHttps: 1, includeRelay: 1 }), token);
      var servers = (res || []).filter(function (r) { return String(r.provides || "").indexOf("server") >= 0; });
      servers.sort(function (a, b) { return (a.owned ? 0 : 1) - (b.owned ? 0 : 1); });
      for (var s = 0; s < servers.length; s++) {
        var conns = (servers[s].connections || []).filter(function (c) { return c.uri && (c.protocol === "https" || location.protocol === "http:"); });
        conns.sort(function (a, b) { return (a.local ? 0 : 2) + (a.relay ? 4 : 0) - ((b.local ? 0 : 2) + (b.relay ? 4 : 0)); });
        for (var c = 0; c < conns.length; c++) {
          var stoken = servers[s].accessToken || token;
          try {
            var ctl = new AbortController();
            var timer = setTimeout(function () { ctl.abort(); }, 5000);
            var r = await fetch(conns[c].uri + "/identity", { headers: P.headers(stoken), signal: ctl.signal });
            clearTimeout(timer);
            if (r.ok) {
              P.st = { token: token, user: user.username || user.title, server: { name: servers[s].name, uri: conns[c].uri, token: stoken } };
              P.save();
              return;
            }
          } catch (e) {}
        }
      }
      throw new Error("None of your Plex servers answered this browser.");
    },
    get: async function (path, params, extra) {
      var r = await fetch(P.st.server.uri + path + qs(params || {}), { headers: Object.assign(P.headers(P.st.server.token), extra || {}) });
      if (!r.ok) throw new HttpError(r.status, "Plex");
      return r;
    },
    items: async function (path, params, extra) {
      var d = await (await P.get(path, params, extra)).json();
      var mc = d.MediaContainer || {};
      return (mc.Metadata || mc.Directory || []).map(P.item).filter(function (x) { return x && x.key; });
    },
    // (gzreader_plex.lua Plex.item)
    item: function (m) {
      if (!m) return null;
      var t = { key: m.ratingKey && String(m.ratingKey), type: m.type, title: m.title || "?",
        artist: m.grandparentTitle || m.parentTitle, album: m.parentTitle, year: m.year, index: m.index,
        duration: m.duration, thumb: m.thumb || m.composite || m.parentThumb, count: m.leafCount || m.childCount };
      if (t.type === "album") t.artist = m.parentTitle;
      if (t.type === "artist") t.artist = undefined;
      var media = m.Media && m.Media[0], part = media && media.Part && media.Part[0];
      if (part) t.part = { key: part.key, container: part.container || media.container, size: part.size, codec: media.audioCodec, bitrate: media.bitrate };
      return t;
    },
    // (gzreader_plex.lua Plex.how: bigger MP3/AAC made into MP3 at the quality too, if asked)
    how: function (t) {
      var p = t.part || {}, c = String(p.container || "").toLowerCase(), codec = String(p.codec || "").toLowerCase(), r;
      if (c === "mp3" || (codec === "mp3" && c === "")) r = ["file", "mp3"];
      else if ((c === "mp4" || c === "m4a") && (codec === "aac" || codec === "")) r = ["file", "m4a"];
      else if (c === "aac" || c === "adts") r = ["file", "aac"];
      else return ["transcode", "mp3"];
      var q = P.quality(), kbps = Number(p.bitrate);
      if (q.shrink && kbps > q.bitrate * P.SHRINK_MARGIN) return ["transcode", "mp3"];
      return r;
    },
    BITRATES: [128, 192, 320],
    SHRINK_MARGIN: 1.15,
    q: null, // chosen on the page (null: as on the Kindle)
    quality: function () {
      if (P.q) return P.q;
      var k = (K.out || {}).music_quality || {};
      return { bitrate: P.BITRATES.indexOf(Number(k.bitrate)) >= 0 ? Number(k.bitrate) : 192, shrink: k.shrink === true };
    },
    renderQuality: function () {
      var q = P.quality();
      if ($("#p-bitrate")) $("#p-bitrate").value = String(q.bitrate);
      if ($("#p-shrink")) $("#p-shrink").checked = q.shrink;
    },
  };

  // MPEG-TS → its audio (MP3 or ADTS frames), as gzreader_plex.lua Plex.demuxTs
  function demuxTs(data, state, out) {
    var n = data.length, i = 0;
    while (i < n && data[i] !== 0x47) i++;
    while (i + 187 < n) {
      if (data[i] !== 0x47) break;
      var b1 = data[i + 1], b2 = data[i + 2], b3 = data[i + 3];
      var pusi = (b1 & 0x40) !== 0, pid = ((b1 & 0x1f) << 8) | b2, afc = (b3 >> 4) & 3;
      var p = i + 4;
      if (afc === 2 || afc === 3) p = p + 1 + data[p];
      var payload = (afc === 1 || afc === 3) && p <= i + 187 ? data.subarray(p, i + 188) : new Uint8Array(0);
      if (pid === 0 && pusi && payload.length > 12) {
        var sec = payload.subarray(1 + payload[0]);
        state.pmt = ((sec[10] & 0x1f) << 8) | sec[11];
      } else if (state.pmt != null && pid === state.pmt && pusi && payload.length > 16) {
        var s = payload.subarray(1 + payload[0]);
        var B = function (k) { return s[k - 1] || 0; }; // (1-based, like the Lua)
        var slen = ((B(2) & 0x0f) << 8) | B(3);
        var pinfo = ((B(11) & 0x0f) << 8) | B(12);
        var j = 13 + pinfo, stop = 3 + slen - 4;
        while (j + 4 <= stop) {
          var st = B(j), epid = ((B(j + 1) & 0x1f) << 8) | B(j + 2), eslen = ((B(j + 3) & 0x0f) << 8) | B(j + 4);
          if ((st === 0x03 || st === 0x04 || st === 0x0f) && state.audio == null) { state.audio = epid; state.type = st; }
          j = j + 5 + eslen;
        }
      } else if (state.audio != null && pid === state.audio && payload.length > 0) {
        if (pusi && payload[0] === 0 && payload[1] === 0 && payload[2] === 1) payload = payload.subarray(9 + (payload[8] || 0));
        out.push(payload.slice());
        state.bytes = (state.bytes || 0) + payload.length;
      }
      i += 188;
    }
  }

  // ------------------------------------------------------------ calendars

  var Cal = {
    list: [], // { id, type = link | caldav | file, name, url, user, pass } (in the Vault; a file's handle: this browser)
    save: function () { Vault.save(); },
    range: function (out) {
      var c = (out && out.calendar) || {};
      var day = new Date(); day.setHours(0, 0, 0, 0);
      return { from: new Date(day.getTime() - (c.days_back || 14) * 86400000), to: new Date(day.getTime() + ((c.days_ahead || 90) + 1) * 86400000) };
    },
    text: async function (src, range) {
      if (src.type === "file") {
        var h = await idb.get("calfile:" + src.id);
        if (!h) throw new Error("the file isn't remembered any more: add it again");
        if (!(await permitted(h, "read"))) throw new Error("this browser wasn't allowed to read it");
        return (await h.getFile()).text();
      }
      var url = src.url.replace(/^webcal:/i, "https:");
      var headers = {};
      if (src.user) headers.Authorization = "Basic " + btoa(unescape(encodeURIComponent(src.user + ":" + (src.pass || ""))));
      if (src.type === "caldav") return Cal.caldav(url, headers, range);
      var r;
      try { r = await fetch(url, { headers: headers }); } catch (e) { throw new Error("its server doesn't let web pages read it (add the .ics file instead)"); }
      if (r.status === 401 || r.status === 403) throw new Error("not allowed (" + r.status + ")");
      if (r.status === 404 || r.status === 410) throw new Error("the link no longer works");
      if (!r.ok) throw new HttpError(r.status, "the calendar server");
      var t = await r.text();
      if (t.indexOf("BEGIN:VCALENDAR") < 0) {
        // not a calendar file: maybe a CalDAV address
        src.type = "caldav"; Cal.save();
        return Cal.caldav(url, headers, range);
      }
      return t;
    },
    utc: function (d) { return d.toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z"); },
    caldav: async function (url, headers, range) {
      var dav = "urn:ietf:params:xml:ns:caldav";
      var body = '<?xml version="1.0" encoding="utf-8"?><c:calendar-query xmlns:d="DAV:" xmlns:c="' + dav + '"><d:prop><c:calendar-data/></d:prop>'
        + '<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT"><c:time-range start="' + Cal.utc(range.from)
        + '" end="' + Cal.utc(range.to) + '"/></c:comp-filter></c:comp-filter></c:filter></c:calendar-query>';
      var r;
      try {
        r = await fetch(url, { method: "REPORT", headers: Object.assign({ Depth: "1", "Content-Type": "application/xml; charset=utf-8" }, headers), body: body });
      } catch (e) { throw new Error("the CalDAV server doesn't let web pages read it (export an .ics file instead)"); }
      if (r.status === 401 || r.status === 403) throw new Error("the user name or app password wasn't accepted");
      if (!r.ok && r.status !== 207) throw new HttpError(r.status, "the CalDAV server");
      var xml = new DOMParser().parseFromString(await r.text(), "application/xml");
      var parts = Array.prototype.map.call(xml.getElementsByTagNameNS(dav, "calendar-data"), function (n) { return n.textContent; });
      return parts.join("\r\n");
    },
  };

  // ------------------------------------------------------------ GZreader updates

  // One file out of a zip (a GZreader update: its koreader/gzreader-version).
  async function zipEntryText(blob, name) {
    var tailLen = Math.min(blob.size, 65557);
    var tail = new Uint8Array(await blob.slice(blob.size - tailLen).arrayBuffer());
    var dv = new DataView(tail.buffer), eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) { if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; } }
    if (eocd < 0) return null;
    var cdSize = dv.getUint32(eocd + 12, true), cdOff = dv.getUint32(eocd + 16, true);
    var cd = new Uint8Array(await blob.slice(cdOff, cdOff + cdSize).arrayBuffer());
    var c = new DataView(cd.buffer), dec = new TextDecoder();
    for (var p = 0; p + 46 <= cd.length && c.getUint32(p, true) === 0x02014b50;) {
      var method = c.getUint16(p + 10, true), csize = c.getUint32(p + 20, true);
      var nlen = c.getUint16(p + 28, true), elen = c.getUint16(p + 30, true), clen = c.getUint16(p + 32, true);
      var lho = c.getUint32(p + 42, true);
      if (dec.decode(cd.subarray(p + 46, p + 46 + nlen)) === name) {
        var lh = new DataView(await blob.slice(lho, lho + 30).arrayBuffer());
        var start = lho + 30 + lh.getUint16(26, true) + lh.getUint16(28, true);
        var data = blob.slice(start, start + csize);
        if (method === 0) return data.text();
        if (method === 8) return new Response(data.stream().pipeThrough(new DecompressionStream("deflate-raw"))).text();
        return null;
      }
      p += 46 + nlen + elen + clen;
    }
    return null;
  }

  var Update = {
    API: "https://api.github.com/repos/9retirement6irk/GZreader/releases/latest",
    // (GitHub's release downloads can't be read by a web page; the release
    // workflow also puts the update on this branch, which can)
    RAW: "https://raw.githubusercontent.com/9retirement6irk/GZreader/updates/",
    // test builds (the Kindle's Settings → Updates → Test builds, or the
    // checkbox here): every push to the beta branch, any other than the
    // Kindle's is offered (gzreader-beta.yml)
    // (next to the release's: gzreader-beta-update.zip, latest-beta.json)
    RAW_BETA: "https://raw.githubusercontent.com/9retirement6irk/GZreader/updates/",
    beta: false, betaTouched: false,
    raw: function () { return Update.beta ? Update.RAW_BETA : Update.RAW; },
    meta: function (base) { return (base || Update.raw()) + (Update.beta ? "latest-beta.json" : "latest.json"); },
    // the updates branch at its commit now: GitHub's file server keeps each
    // file of a branch for minutes, each on its own, so right after a new
    // build latest.json and the zip could be from different builds ("the
    // update came incomplete"); a commit's files never change
    base: async function () {
      var raw = Update.raw(), m = raw.match(/^(https:\/\/raw\.githubusercontent\.com\/[^/]+\/[^/]+\/)updates\/$/);
      if (!m) return raw;
      try {
        var r = await fetch("https://api.github.com/repos/9retirement6irk/GZreader/commits/updates",
          { headers: { Accept: "application/vnd.github.sha" }, cache: "no-store" });
        var sha = r.ok ? (await r.text()).trim() : "";
        if (/^[0-9a-f]{40}$/.test(sha)) return m[1] + sha + "/";
      } catch (e) {}
      return raw;
    },
    // whether `v` should go to a Kindle that has `have`
    offered: function (v, have) { return !!v && (Update.beta ? v !== have : Update.compare(v, have) > 0); },
    RELEASES: "https://github.com/9retirement6irk/GZreader/releases/latest",
    latest: null, chosen: true, file: null,
    // -1, 0, 1, as GZreader's own (gzreader_update.lua): a release is newer
    // than a test build of the same number (1.27.0 > 1.27.0-beta.5995ce3),
    // so turning test builds off offers the release. (It compared the numbers
    // only: a Kindle on a test build of the release's number was offered nothing.)
    compare: function (a, b) {
      function parts(v) {
        var m = String(v).replace(/^v\.?/, "").match(/^([\d.]*)(.*)$/);
        return { n: (m[1] || "0").split("."), pre: m[2] || "" };
      }
      var pa = parts(a), pb = parts(b);
      for (var i = 0; i < Math.max(3, pa.n.length, pb.n.length); i++) {
        var x = parseInt(pa.n[i], 10) || 0, y = parseInt(pb.n[i], 10) || 0;
        if (x !== y) return x < y ? -1 : 1;
      }
      if (pa.pre === pb.pre) return 0;
      if (pa.pre === "") return 1;
      if (pb.pre === "") return -1;
      return pa.pre < pb.pre ? -1 : 1;
    },
    check: async function () {
      Update.latest = null;
      $("#o-update-row").classList.add("hidden");
      var old = $("#update-note");
      if (old) old.remove();
      var have = (K.out || {}).gzreader;
      if (!have) return;
      $("#o-beta-row").classList.remove("hidden");
      if (!Update.betaTouched) $("#o-beta").checked = (K.out || {}).test_builds === true;
      Update.beta = $("#o-beta").checked;
      try {
        var v;
        if (Update.beta) {
          var meta = await (await fetch(Update.meta(), { cache: "no-store" })).json();
          v = String(meta.version || "");
        } else {
          var rel = await (await fetch(Update.API, { headers: { Accept: "application/vnd.github+json" } })).json();
          v = String(rel.tag_name || "").replace(/^v\.?/, "");
        }
        if (!Update.offered(v, have)) return;
        Update.latest = v;
        $("#o-update-text").textContent = "Update GZreader on the Kindle to " + (Update.beta ? "test build " : "") + v + " (it has " + have + ")";
        $("#o-update-row").classList.remove("hidden");
        Update.chosen = $("#o-update").checked;
        var box = $("#kindle");
        var note = el("div", { class: "update small", id: "update-note" }, (Update.beta ? "Test build " + v + " is waiting" : "GZreader " + v + " is out")
          + " (this Kindle has " + have + "). The sync brings it; GZreader installs it when it starts. ");
        var b = el("button", { class: "link" }, "Use a downloaded update file…");
        b.onclick = busy(b, Update.pick);
        note.appendChild(b);
        box.appendChild(note);
      } catch (e) {}
    },
    // the update downloaded by hand (gzreader-update.zip from the release)
    pick: async function () {
      var file;
      if (window.showOpenFilePicker) {
        try { file = await (await window.showOpenFilePicker({ types: [{ description: "GZreader update", accept: { "application/zip": [".zip"] } }] }))[0].getFile(); }
        catch (e) { if (e.name === "AbortError") return; throw e; }
      }
      if (!file) return;
      var v = await Update.versionOf(file);
      if (!v) throw new Error("That isn't a GZreader update (gzreader-update.zip).");
      Update.file = file; Update.chosen = true; $("#o-update").checked = true;
      $("#o-update-text").textContent = "Update GZreader on the Kindle to " + v + " (from " + file.name + ")";
      $("#o-update-row").classList.remove("hidden");
      if (!Update.latest) Update.latest = v;
    },
    versionOf: async function (blob) {
      try {
        var t = await zipEntryText(blob, "koreader/gzreader-version");
        var v = t && t.trim().replace(/^v\.?/, "");
        return v && /^\d+(\.\d+)*/.test(v) ? v : null;
      } catch (e) { return null; }
    },
    bring: async function (out, inbox) {
      phase("GZreader update…");
      var blob = Update.file;
      if (!blob) {
        try {
          var base = await Update.base();
          var meta = await (await fetch(Update.meta(base), { cache: "no-store" })).json();
          if (Update.offered(meta.version, out.gzreader || "0") && /^[\w.-]+$/.test(meta.file || "gzreader-update.zip")) {
            var r = await fetch(base + (meta.file || "gzreader-update.zip"), { cache: "no-store" });
            if (r.ok) {
              var b = await r.blob();
              if (meta.size && b.size !== meta.size) throw new Error("the update came incomplete");
              if (meta.sha256) {
                var h = Array.prototype.map.call(new Uint8Array(await crypto.subtle.digest("SHA-256", await b.arrayBuffer())),
                  function (x) { return ("0" + x.toString(16)).slice(-2); }).join("");
                if (h !== meta.sha256) throw new Error("the update didn't come through intact");
              }
              blob = b;
            }
          }
        } catch (e) { if (/incomplete|intact/.test(e.message)) throw e; }
      }
      if (!blob) {
        log("GZreader " + Update.latest + " can't be fetched by this page yet: download gzreader-update.zip from " + Update.RELEASES.replace(/^https:\/\//, "")
          + ", add it with “Use a downloaded update file…” above and sync again.", "bad");
        return;
      }
      var v = await Update.versionOf(blob);
      if (!v) throw new Error("that isn't a GZreader update");
      if (!Update.offered(v, out.gzreader || "0")) { log("GZreader " + (out.gzreader || "") + " is already up to date."); return; }
      await Drive.write(Drive.sync, "in/gzreader-update.zip", blob);
      inbox.update = { version: v, file: "in/gzreader-update.zip", size: blob.size, beta: Update.beta };
      log("GZreader " + v + " is on its way: it installs when GZreader starts.", "ok");
    },
  };

  // ------------------------------------------------------------ sign-ins, kept on the Kindle with a PIN

  // .gzsync/keys.json: the connections (Grimmory's sign-in token, the Memos
  // token, Plex, calendar links and CalDAV app passwords), encrypted with a
  // key made from the PIN (PBKDF2-SHA-256, 600 000 rounds, AES-256-GCM).
  // Only this page reads it; GZreader on the Kindle never does. Without the
  // PIN it's unreadable, but a short PIN can be guessed by someone who has
  // the file and time: a longer one is safer.
  var Vault = {
    FILE: "keys.json", ROUNDS: 600000,
    key: null, salt: null, mode: null, // "kindle" | "session"
    plexClient: null,
    exists: async function () { return !!(Drive.sync && await Drive.has(Drive.sync, Vault.FILE)); },
    derive: async function (pin, salt) {
      var base = await crypto.subtle.importKey("raw", new TextEncoder().encode(pin), "PBKDF2", false, ["deriveKey"]);
      return crypto.subtle.deriveKey({ name: "PBKDF2", hash: "SHA-256", salt: salt, iterations: Vault.ROUNDS }, base,
        { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
    },
    b64: function (buf) { return btoa(String.fromCharCode.apply(null, new Uint8Array(buf))); },
    unb64: function (s) { return Uint8Array.from(atob(s), function (c) { return c.charCodeAt(0); }); },
    data: function () { return { grimmory: G.st, memos: M.st, plex: P.st, plexClient: Vault.plexClient, calendars: Cal.list }; },
    use: function (d) {
      d = d || {};
      G.st = d.grimmory || null; M.st = d.memos || null; P.st = d.plex || null;
      Vault.plexClient = d.plexClient || null; Cal.list = Array.isArray(d.calendars) ? d.calendars : [];
    },
    // a new PIN (or the first one)
    create: async function (pin) {
      Vault.salt = crypto.getRandomValues(new Uint8Array(16));
      Vault.key = await Vault.derive(pin, Vault.salt);
      Vault.mode = "kindle";
      await Vault.write();
    },
    unlock: async function (pin) {
      var f = await Drive.readJSON(Drive.sync, Vault.FILE);
      if (!f || !f.salt || !f.iv || !f.data) throw new Error("The Kindle's sign-ins file is damaged: start over.");
      var salt = Vault.unb64(f.salt), key = await Vault.derive(pin, salt);
      var plain;
      try { plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: Vault.unb64(f.iv) }, key, Vault.unb64(f.data)); }
      catch (e) { throw new Error("That isn't this Kindle's PIN."); }
      Vault.salt = salt; Vault.key = key; Vault.mode = "kindle";
      Vault.use(JSON.parse(new TextDecoder().decode(plain)));
    },
    // (no PIN: the sign-ins last as long as this tab)
    session: function () {
      Vault.mode = "session"; Vault.key = null;
      try { Vault.use(JSON.parse(sessionStorage.getItem("gzsync.session") || "null")); } catch (e) { Vault.use(null); }
    },
    lock: function () { Vault.key = null; Vault.mode = null; Vault.use(null); },
    chain: Promise.resolve(),
    // every change written at once (Grimmory changes its sign-in token at each refresh), one write at a time
    save: function () {
      Vault.chain = Vault.chain.then(Vault.write).catch(function (e) { log("Couldn't keep the sign-ins on the Kindle: " + e.message, "bad"); });
      return Vault.chain;
    },
    write: async function () {
      if (Vault.mode === "session") { try { sessionStorage.setItem("gzsync.session", JSON.stringify(Vault.data())); } catch (e) {} return; }
      if (Vault.mode !== "kindle" || !Vault.key || !Drive.sync) return;
      var iv = crypto.getRandomValues(new Uint8Array(12));
      var data = await crypto.subtle.encrypt({ name: "AES-GCM", iv: iv }, Vault.key, new TextEncoder().encode(JSON.stringify(Vault.data())));
      await Drive.write(Drive.sync, Vault.FILE, JSON.stringify({ format: 1, kdf: "PBKDF2-SHA256", rounds: Vault.ROUNDS,
        cipher: "AES-256-GCM", salt: Vault.b64(Vault.salt), iv: Vault.b64(iv), data: Vault.b64(data), written_at: Math.floor(Date.now() / 1000) }));
    },
    forget: async function () { await Drive.remove(Drive.sync, Vault.FILE); Vault.lock(); },
  };

  // What's chosen on the page for the next sync, kept on the Kindle (.gzsync/picks.json: no secrets)
  var Picks = {
    d: { books: [], music: [] },
    load: async function () {
      var d = Drive.sync && await Drive.readJSON(Drive.sync, "picks.json");
      Picks.d = { books: asList(d && d.books), music: asList(d && d.music) };
    },
    save: function () { if (Drive.sync) Drive.write(Drive.sync, "picks.json", JSON.stringify(Picks.d)).catch(function () {}); },
    // Off the list: what the Kindle already has (it came another way: a sync
    // from another computer, a download over Wi-Fi). Left there, it was listed
    // as coming, and came again once deleted from the Kindle.
    prune: function (out) {
      var have = (out && out.have) || {};
      var books = have.books || {}, audio = asList(have.audiobooks).map(String), music = asList(have.music);
      var b = Picks.d.books.filter(function (p) { var id = String(p.id); return !books[id] && audio.indexOf(id) < 0; });
      var m = Picks.d.music.filter(function (p) {
        if (p.kind === "audiobook") return audio.indexOf("plex-" + p.key) < 0; // (a Plex audiobook: on the Kindle as plex-<key>)
        return music.indexOf(p.kind + "-" + p.key) < 0 && music.indexOf(safe(p.kind) + "-" + safe(p.key)) < 0;
      });
      var n = Picks.d.books.length - b.length + Picks.d.music.length - m.length;
      if (n) { Picks.d = { books: b, music: m }; Picks.save(); }
      return n;
    },
  };

  // ------------------------------------------------------------ the Kindle and its outbox

  var K = { out: null, handle: null, test: false };

  function show(id, on) { $(id).classList.toggle("hidden", !on); }

  // The outbox as GZreader wrote it: an empty list can come as {} (KOReader's
  // JSON writes an empty Lua table as an object; GZreader 1.24): lists here.
  function asList(x) { return Array.isArray(x) ? x : (x && typeof x === "object" ? Object.keys(x).map(function (k) { return x[k]; }) : []); }
  function fixOutbox(o) {
    if (!o || typeof o !== "object") return o;
    o.jobs = asList(o.jobs);
    o.queue = asList(o.queue);
    o.have = o.have && typeof o.have === "object" ? o.have : {};
    o.have.books = o.have.books && typeof o.have.books === "object" && !Array.isArray(o.have.books) ? o.have.books : {};
    o.have.audiobooks = asList(o.have.audiobooks);
    o.have.music = asList(o.have.music);
    o.notes = o.notes && typeof o.notes === "object" ? o.notes : {};
    o.notes.queue = asList(o.notes.queue);
    o.notes.files = asList(o.notes.files);
    if (o.notes.sync_tags != null) o.notes.sync_tags = asList(o.notes.sync_tags);
    o.jobs.forEach(function (j) { if (j && j.queue) j.queue = asList(j.queue); });
    o.queue.forEach(function (q) { if (q && q.authors != null) q.authors = asList(q.authors); });
    return o;
  }

  // 1. the drive: its GZreader folder, the Kindle's outbox
  async function openDrive(handle, quiet) {
    if (!(await permitted(handle, "readwrite"))) { if (!quiet) problem("The browser wasn't allowed to use the Kindle's drive."); return false; }
    var where = await Drive.locate(handle);
    if (!where) {
      problem("No GZreader folder there. Choose the Kindle's drive itself (it has a documents folder), with GZreader installed and started once.");
      return false;
    }
    Drive.root = handle; Drive.gz = where.gz; Drive.sync = where.sync;
    K.handle = handle;
    if (!K.test && !window.GZSYNC_TEST) await idb.set("drive", handle); // (test mode: a folder in the browser's own storage)
    K.out = fixOutbox(await Drive.readJSON(Drive.sync, "outbox.json"));
    K.pending = await Drive.readJSON(Drive.sync, "inbox.json");
    await Picks.load();
    Picks.prune(K.out);
    show("#kindle-problem", false);
    await askPin();
    return true;
  }

  function problem(text) {
    var box = $("#kindle-problem");
    box.textContent = "";
    box.appendChild(el("p", { class: "bad" }, text));
    show("#kindle-problem", true);
  }

  // 2. its PIN: unlock the sign-ins kept on it, or set one
  async function askPin() {
    var has = await Vault.exists();
    $("#unlock-title").textContent = has ? "Unlock the Kindle's connections" : "Choose a PIN for this Kindle";
    $("#unlock-text").textContent = has
      ? "Enter the PIN you chose for this Kindle: its sign-ins (Grimmory, Memos, Plex, calendars) are kept on it, locked with it."
      : "Your sign-ins are kept on the Kindle, locked with this PIN, so any computer can sync it with the PIN. 4 characters at least; a longer one is safer (someone with the Kindle could try to guess a short one).";
    show("#pin2", !has);
    $("#unlock-go").textContent = has ? "Unlock" : "Keep sign-ins on the Kindle";
    show("#unlock-reset-wrap", has);
    show("#unlock-err", false);
    $("#pin").value = ""; $("#pin2").value = "";
    show("#gate", false);
    show("#unlock", true);
    $("#pin").focus();
  }

  async function unlocked() {
    show("#unlock", false);
    show("#app", true);
    $("#keep-note").textContent = Vault.mode === "kindle"
      ? "Kept on the Kindle, locked with its PIN (any computer can sync it with the PIN). Grimmory's password isn't kept: it stays signed in with a sign-in token."
      : "Not kept on the Kindle: these sign-ins last until this tab is closed. Grimmory's password isn't kept.";
    showKindle(K.out);
    renderConnections();
    renderPicks();
    Sleep.render();
    setPanel(G.connected() || M.connected() || P.connected() || Cal.list.length ? "content" : "connections");
    Update.check();
    measure();
    try {
      if (await G.finishSso()) { renderConnections(); setPanel("connections"); alertIn($("#g-out"), "Signed in to Grimmory."); }
    } catch (e) { setPanel("connections"); alertIn($("#g-sso"), e.message); }
  }

  function setPanel(name) {
    document.querySelectorAll("nav.main button").forEach(function (b) { b.classList.toggle("on", b.dataset.panel === name); });
    document.querySelectorAll("section.panel").forEach(function (p) { p.classList.toggle("hidden", p.dataset.panel !== name); });
    if (name === "content" && !$("#b-results").children.length) Browse.show();
    if (name === "sync") { measure(); Report.render(); }
  }

  function showKindle(out) {
    var k = (out && out.kindle) || {};
    $("#k-name").textContent = K.test ? "Pretend Kindle" : (k.name || "Kindle");
    var sub = [];
    if (out && out.gzreader) sub.push("GZreader " + out.gzreader);
    var jobs = ((out && out.jobs) || []).length, notes = (((out && out.notes) || {}).queue || []).length;
    if (jobs) sub.push(jobs + " reading update" + (jobs === 1 ? "" : "s") + " to send");
    if (notes) sub.push(notes + " note change" + (notes === 1 ? "" : "s"));
    if (K.pending) sub.push("a sync not taken in yet (this one adds to it)");
    $("#k-sub").textContent = sub.length ? "· " + sub.join(" · ") : "";
    var box = $("#kindle");
    box.textContent = "";
    if (!out) {
      box.appendChild(el("p", { class: "warn small" }, "GZreader hasn't left its sync file on this Kindle yet: update it to 1.24 or newer, start it once, then exit it and plug the Kindle in again. You can still sync: the next start takes in what's brought."));
    } else if (out.grimmory && G.st && G.st.server && normalizeServer(out.grimmory.server) !== G.st.server) {
      box.appendChild(el("p", { class: "warn small" }, "This Kindle was last synced with " + hostOf(out.grimmory.server) + "; the connections here use " + hostOf(G.st.server) + "."));
    }
    $("#c-plex").classList.toggle("hidden", k.audio === false);
    updateSyncButton();
  }

  // what's on the Kindle, and how much room is left (the Sync tab)
  async function dirSize(dir, skip) {
    var total = 0;
    try {
      for await (var entry of dir.values()) {
        if (skip && skip(entry.name)) continue;
        if (entry.kind === "file") { try { total += (await entry.getFile()).size; } catch (e) {} }
        else total += await dirSize(entry);
      }
    } catch (e) {}
    return total;
  }
  var COLORS = { books: "#3b6ea5", audiobooks: "#a5673b", music: "#6a3ba5", copy: "#3ba57a", notes: "#a53b6a" };
  async function measure() {
    var box = $("#storage");
    if (!Drive.gz || !box) return;
    var gz = Drive.gz;
    // (as GZreader's Settings → Storage counts them: the Audiobooks and Music folders hold stand-ins)
    var ab = await Drive.tryDir(gz, ".audiobooks"), mu = await Drive.tryDir(gz, ".music"), cp = Drive.sync;
    var parts = [
      { key: "books", label: "Books", bytes: await dirSize(gz, function (n) { return n[0] === "." || n === "Audiobooks" || n === "Music"; }) },
      { key: "audiobooks", label: "Audiobooks", bytes: ab ? await dirSize(ab) : 0 },
      { key: "music", label: "Music", bytes: mu ? await dirSize(mu) : 0 },
    ];
    parts.push({ key: "copy", label: "Library copy, covers and sync files", bytes: await dirSize(cp, function (n) { return n === "in" || n === Vault.FILE; }) });
    var notes = Drive.root && await Drive.tryDir(Drive.root, "koreader/cache/gzreader-notes");
    if (notes) parts.push({ key: "notes", label: "Notes' pictures", bytes: await dirSize(notes) });
    var disk = (K.out || {}).disk;
    var coming = Picks.d.books.concat((K.out || {}).queue || []).reduce(function (a, q) { return a + (Number(q.size_kb) || 0) * 1024; }, 0);
    box.textContent = "";
    if (disk && disk.total) {
      var head = el("div", null, mb(disk.available) + " free of " + mb(disk.total) + " (as GZreader last saw it)");
      box.appendChild(head);
      var meter = el("div", { class: "meter", role: "img", "aria-label": "Space used on the Kindle" });
      parts.forEach(function (p) {
        if (!p.bytes) return;
        var span = el("span"); span.style.width = Math.max(0.5, p.bytes / disk.total * 100) + "%"; span.style.background = COLORS[p.key]; span.title = p.label;
        meter.appendChild(span);
      });
      box.appendChild(meter);
    }
    var legend = el("div", { class: "legend" });
    parts.forEach(function (p) {
      var d = el("div"); var i = el("i"); i.style.background = COLORS[p.key];
      d.appendChild(i); d.appendChild(document.createTextNode(p.label + ": " + mb(p.bytes))); legend.appendChild(d);
    });
    box.appendChild(legend);
    if (coming) {
      var warn = disk && disk.available && coming > disk.available * 0.9;
      box.appendChild(el("p", { class: warn ? "bad" : "" }, "The next sync brings about " + mb(coming) + (warn ? ": more than there's room for." : ".")));
    }
  }

  // test mode (?test): a pretend Kindle in this browser's own storage
  var TEST_OUTBOX = {
    format: 1, gzreader: "1.24.0", written_at: 0,
    kindle: { model: "Kindle2", name: "Pretend Kindle 2", id: "test00", audio: true },
    jobs: [], queue: [], have: { books: {}, audiobooks: [], music: [] },
    notes: { queue: [], keep: 100, files: [] }, calendar: { days_back: 14, days_ahead: 90 },
    disk: { total: 1.4 * 1073741824, available: 1.1 * 1073741824 },
    screensavers: { names: [], mode: "auto" },
  };
  async function testKindle(reset) {
    var root = await navigator.storage.getDirectory();
    if (reset) { for await (var n of root.keys()) await root.removeEntry(n, { recursive: true }); }
    var sync = await Drive.dir(root, "documents/GZreader/.gzsync", true);
    if (!(await Drive.has(sync, "outbox.json"))) {
      var o = JSON.parse(JSON.stringify(TEST_OUTBOX)); o.written_at = Math.floor(Date.now() / 1000);
      await Drive.write(sync, "outbox.json", JSON.stringify(o));
    }
    return root;
  }

  // ------------------------------------------------------------ the sync

  var Opt = { covers: true, details: true, slim: true };

  function newInbox(prev) {
    var inbox = prev && prev.format === FORMAT ? prev : { format: FORMAT, done: [], books: [], audiobooks: [], music: [] };
    inbox.done = inbox.done || []; inbox.books = inbox.books || []; inbox.audiobooks = inbox.audiobooks || []; inbox.music = inbox.music || [];
    inbox.failed = [];
    return inbox;
  }

  async function saveInbox(inbox) {
    inbox.written_at = Math.floor(Date.now() / 1000);
    inbox.page = "gzsync 1";
    await Drive.write(Drive.sync, "inbox.json", JSON.stringify(inbox));
  }

  function slimBook(b) {
    var o = {};
    BOOK_FIELDS.forEach(function (k) { if (b[k] !== undefined && b[k] !== null) o[k] = b[k]; });
    return o;
  }

  async function allPages(path, params, onPage, max) {
    var out = [], page = 0, pages = 1;
    while (page < pages && page < (max || 1000)) {
      var d = await G.json(path + qs(Object.assign({ page: page, size: PAGE }, params)));
      pages = Number(d.totalPages || (d.page && d.page.totalPages)) || 1;
      (d.content || []).forEach(function (b) { out.push(b); });
      page++;
      if (onPage) onPage(page, pages);
    }
    return out;
  }

  // 1. what the Kindle has to send
  async function sendJobs(out, inbox) {
    var done = new Set(inbox.done);
    var jobs = (out.jobs || []).filter(function (j) { return !done.has(j.id); });
    if (!jobs.length) return;
    phase("Sending reading updates to Grimmory…");
    var sent = 0, marks = 0, badClock = 0;
    inbox.created = inbox.created || {};
    for (var i = 0; i < jobs.length; i++) {
      var j = jobs[i];
      var r, path = j.path, body = j.body;
      if (j.kind === "session" && body && Date.parse(body.startTime) < Date.UTC(2020, 0, 1)) {
        // read while the Kindle's clock was wrong (a Kindle DX starts at 1970 when its clock is lost):
        // not sent, so Grimmory's stats don't get 1970 dates
        inbox.done.push(j.id); badClock++; continue;
      }
      if (j.kind === "mark") {
        // a bookmark or highlight: ids made on the Kindle ("usb-…") are Grimmory's once created
        var ref = j.ref != null ? String(j.ref) : null;
        if (ref && inbox.created[ref]) ref = String(inbox.created[ref]);
        if (ref && /^usb-/.test(ref)) { inbox.done.push(j.id); continue; } // (its creation never went through)
        path = path.replace("{id}", encodeURIComponent(ref || ""));
      }
      try { r = await G.fetch(path, { method: j.method, body: body }); } catch (e) {
        inbox.failed.push({ id: j.id, error: "unreachable" });
        log("Couldn't reach Grimmory to send the rest: " + e.message, "bad");
        break;
      }
      if (r.ok) {
        inbox.done.push(j.id);
        if (j.kind === "mark") {
          marks++;
          if (j.temp) { try { var made = await r.json(); if (made && made.id != null) inbox.created[j.temp] = made.id; } catch (e) {} }
        } else sent++;
      } else if (j.kind === "mark" && (r.status === 404 || r.status === 409 || r.status === 400)) {
        inbox.done.push(j.id); // (already gone, or already there: the next sync's lists show it)
      } else if (r.status >= 400 && r.status < 500 && r.status !== 401 && r.status !== 408 && r.status !== 429) {
        // refused for good (a book gone from Grimmory): not sent again
        if (j.kind === "progress") inbox.failed.push({ id: j.id, error: "http_" + r.status });
        else inbox.done.push(j.id);
      } else inbox.failed.push({ id: j.id, error: "http_" + r.status });
      bar.set(i + 1, jobs.length);
    }
    await saveInbox(inbox);
    if (badClock) log(badClock + " reading time" + (badClock === 1 ? "" : "s") + " left out: recorded while the Kindle's clock was wrong (it's set from this computer's now).");
    log("Sent " + sent + " reading update" + (sent === 1 ? "" : "s") + (marks ? " and " + marks + " bookmark and highlight change" + (marks === 1 ? "" : "s") : "") + " to Grimmory.", "ok");
  }

  // 2. the library copy
  async function libraryCopy(out, inbox) {
    phase("Reading your Grimmory library…");
    var books = (await allPages("/api/v1/app/books", { sort: "title", dir: "asc" }, function (p, n) { bar.set(p, n); })).map(slimBook);
    var libraries;
    try { libraries = await G.json("/api/v1/app/libraries"); } catch (e) { try { libraries = await G.json("/api/v1/libraries"); } catch (e2) { libraries = []; } }
    var shelves = [];
    try { shelves = (await G.json("/api/v1/app/shelves")) || []; } catch (e) {}
    try { (await G.json("/api/v1/app/shelves/magic") || []).forEach(function (s) { s.magic = true; shelves.push(s); }); } catch (e) {}
    // which regular shelves are yours (own): the Kindle puts books only on those
    // (Grimmory refuses someone else's public shelf; /app/shelves has no owner)
    try {
      var me = await G.json("/api/v1/users/me"), owner = {};
      ((await G.json("/api/v1/shelves")) || []).forEach(function (s) { owner[String(s.id)] = s.userId; });
      shelves.forEach(function (s) {
        if (!s.magic && me && me.id != null && owner[String(s.id)] != null) s.own = String(owner[String(s.id)]) === String(me.id);
      });
    } catch (e) {}
    var lists = { shelf: {}, magic: {}, continue: [], recent: [] };
    phase("Reading your shelves…");
    for (var i = 0; i < shelves.length; i++) {
      var s = shelves[i];
      try {
        var on = await allPages("/api/v1/app/books", s.magic ? { magicShelfId: s.id, sort: "title", dir: "asc" } : { shelfId: s.id, sort: "title", dir: "asc" }, null, 20);
        lists[s.magic ? "magic" : "shelf"][String(s.id)] = on.map(function (b) { return b.id; });
      } catch (e) {}
    }
    // Continue reading, as the Kindle asks for it (gzreader_api.lua continueReading)
    try {
      var cr = await G.json("/api/v1/app/books/continue-reading?limit=30");
      var more = [];
      try {
        more = (await G.json("/api/v1/app/books" + qs({ page: 0, size: 30, status: ["READING", "RE_READING", "PAUSED"], sort: "lastReadTime", dir: "desc", fileType: READABLE }))).content || [];
      } catch (e) {}
      var seen = {}, merged = [];
      cr.concat(more).forEach(function (b, n) { if (b && b.id != null && !seen[b.id]) { seen[b.id] = true; merged.push({ b: b, n: n }); } });
      merged.sort(function (x, y) {
        var a = x.b.lastReadTime || "", c = y.b.lastReadTime || "";
        if (a && c && a !== c) return a > c ? -1 : 1;
        if (!!a !== !!c) return a ? -1 : 1;
        return x.n - y.n;
      });
      lists.continue = merged.slice(0, 30).map(function (x) { return x.b.id; });
    } catch (e) {}
    try { lists.recent = (await G.json("/api/v1/app/books/recently-added?limit=30")).map(function (b) { return b.id; }); } catch (e) {}
    // the books on the Kindle: their places elsewhere
    var have = out.have || {};
    var ids = Object.keys(have.books || {}).concat((have.audiobooks || []).map(String));
    var full = {};
    phase("Reading where you are in the books on the Kindle…");
    await pool(ids, 4, async function (id) {
      try {
        var b = await G.json("/api/v1/books/" + id);
        var keep = { id: b.id, personalRating: b.personalRating };
        Object.keys(b).forEach(function (k) { if (/Progress$/.test(k)) keep[k] = b[k]; });
        full[id] = keep;
      } catch (e) {}
    });
    // their bookmarks and highlights (GZreader compares and merges them when the book opens)
    var marks = {};
    phase("Reading bookmarks and highlights…");
    await pool(Object.keys(have.books || {}), 4, async function (id) {
      try {
        var bms = await G.json("/api/v1/bookmarks/book/" + id);
        var ans = await G.json("/api/v1/annotations/book/" + id);
        marks[id] = { bookmarks: Array.isArray(bms) ? bms : [], annotations: Array.isArray(ans) ? ans : [] };
      } catch (e) {}
    });
    // subtitles (only the web app's list has them)
    var subtitles = {};
    phase("Reading subtitles…");
    try {
      var wp = 0, wps = 1;
      while (wp < wps && wp < 500) {
        var d = await G.json("/api/v1/books/page" + qs({ page: wp, size: 100 }));
        var meta = d.page && typeof d.page === "object" ? d.page : d;
        wps = Number(meta.totalPages) || 1;
        (d.content || []).forEach(function (b) { var m = b && b.metadata; if (m && m.subtitle) subtitles[String(b.id)] = m.subtitle; });
        wp++;
      }
    } catch (e) {}
    var copy = { format: FORMAT, written_at: Math.floor(Date.now() / 1000), server: G.st.server, user: G.st.user,
      books: books, libraries: libraries, shelves: shelves, lists: lists, full: full, subtitles: subtitles, marks: marks };
    await Drive.write(Drive.sync, "library.json", JSON.stringify(copy));
    inbox.grimmory = { server: G.st.server, user: G.st.user };
    log("Library copy: " + books.length + " books and audiobooks, " + shelves.length + " shelves.", "ok");
    K.subtitles = subtitles;
    K.books = books;
    if (Opt.covers) await covers(books);
    if (Opt.details) await details(books);
  }

  async function shrink(blob, w, h) {
    var img = await createImageBitmap(blob);
    var scale = Math.min(w / img.width, h / img.height, 1);
    var cw = Math.max(1, Math.round(img.width * scale)), ch = Math.max(1, Math.round(img.height * scale));
    var canvas = typeof OffscreenCanvas !== "undefined" ? new OffscreenCanvas(cw, ch) : Object.assign(document.createElement("canvas"), { width: cw, height: ch });
    var ctx = canvas.getContext("2d");
    ctx.filter = "grayscale(1)"; // (e-ink: smaller files, the same picture)
    ctx.drawImage(img, 0, 0, cw, ch);
    if (img.close) img.close();
    if (canvas.convertToBlob) return canvas.convertToBlob({ type: "image/jpeg", quality: 0.8 });
    return new Promise(function (ok) { canvas.toBlob(ok, "image/jpeg", 0.8); });
  }

  // A book's cover, as a page can read it. Grimmory's covers (/api/v1/media)
  // don't let other web pages read them (no CORS: an <img> can show them,
  // a script can't save them); the EPUB's own cover image (/api/v1/epub) and
  // an audiobook's cover (/api/v1/audiobooks/…/cover) can be read.
  var mediaReadable = null; // (tried once a sync)
  async function coverOf(id, audio) {
    if (mediaReadable !== false) {
      try {
        var r = await G.fetch("/api/v1/media/book/" + id + (audio ? "/audiobook-thumbnail" : "/thumbnail"));
        mediaReadable = true;
        return r;
      } catch (e) { if (mediaReadable === true) return null; mediaReadable = false; }
    }
    if (audio) return G.fetch("/api/v1/audiobooks/" + id + "/cover");
    var info = await G.fetch("/api/v1/epub/" + id + "/info");
    if (!info.ok) return null; // (not an EPUB: no cover a page can read)
    var cp = (await info.json()).coverPath;
    if (!cp) return null;
    return G.fetch("/api/v1/epub/" + id + "/file/" + cp.split("/").map(encodeURIComponent).join("/"));
  }

  async function covers(books) {
    mediaReadable = null;
    var index = (await Drive.readJSON(Drive.sync, "covers/index.json")) || {};
    var todo = [];
    books.forEach(function (b) {
      var audio = String(b.primaryFileType || "").toUpperCase() === "AUDIOBOOK";
      var stamp = String((audio ? b.audiobookCoverUpdatedOn || b.coverUpdatedOn : b.coverUpdatedOn) || "0");
      var name = b.id + (audio ? "-a" : "");
      if (index[name] !== stamp && index[name] !== stamp + ":none") todo.push({ id: b.id, name: name, stamp: stamp, audio: audio });
    });
    if (!todo.length) return;
    phase("Small covers for the Catalog tab…");
    var n = 0, got = 0;
    await pool(todo, 6, async function (t) {
      try {
        var r = await coverOf(t.id, t.audio);
        if (!r || r.status === 404) index[t.name] = t.stamp + ":none";
        else if (r.ok) {
          var small = await shrink(await r.blob(), COVER_W, t.audio ? COVER_W : COVER_H);
          await Drive.write(Drive.sync, "covers/" + t.name + ".jpg", small);
          index[t.name] = t.stamp;
          got++;
        }
      } catch (e) {}
      n++;
      bar.set(n, todo.length);
      if (n % 50 === 0) await Drive.write(Drive.sync, "covers/index.json", JSON.stringify(index));
    });
    await Drive.write(Drive.sync, "covers/index.json", JSON.stringify(index));
    log(got + " cover" + (got === 1 ? "" : "s") + " updated.", "ok");
  }

  async function details(books) {
    var dir = await Drive.dir(Drive.sync, "details", true);
    var here = new Set(await Drive.list(dir));
    var todo = books.filter(function (b) { return !here.has(b.id + ".json"); });
    if (!todo.length) return;
    phase("Book descriptions…");
    var n = 0;
    await pool(todo, 4, async function (b) {
      try {
        var d = await G.json("/api/v1/app/books/" + b.id);
        var keep = {};
        ["id", "title", "subtitle", "description", "categories", "goodreadsRating", "goodreadsReviewCount", "pageCount",
          "publisher", "publishedDate", "seriesName", "seriesNumber", "authors", "narrator", "language"].forEach(function (k) {
          if (d[k] !== undefined && d[k] !== null) keep[k] = d[k];
        });
        await Drive.write(dir, b.id + ".json", JSON.stringify(keep));
      } catch (e) {}
      n++;
      bar.set(n, todo.length);
    });
    log("Descriptions for " + n + " book" + (n === 1 ? "" : "s") + ".", "ok");
  }

  function extOf(name, fallback) { var m = /\.([A-Za-z0-9]+)$/.exec(name || ""); return m ? m[1].toLowerCase() : fallback; }
  function inInbox(inbox, id) {
    return inbox.books.some(function (b) { return String(b.id) === String(id); })
      || inbox.audiobooks.some(function (a) { return String(a.id) === String(id); });
  }

  // 3. the sync queue (and the auto-download shelf)
  async function bringQueue(out, inbox) {
    var have = (out.have || {}).books || {};
    var queue = (out.queue || []).slice();
    // (and what was chosen on this page)
    bookPicks().forEach(function (p) {
      if (!queue.some(function (q) { return String(q.id) === String(p.id); }) && !have[String(p.id)]
          && !((out.have || {}).audiobooks || []).some(function (a) { return String(a) === String(p.id); })) queue.push(p);
    });
    var shelf = out.auto_shelf;
    if (shelf && shelf.id != null) {
      try {
        var on = await allPages("/api/v1/app/books", shelf.magic ? { magicShelfId: shelf.id, sort: "addedOn", dir: "desc", fileType: READABLE }
          : { shelfId: shelf.id, sort: "addedOn", dir: "desc", fileType: READABLE }, null, 4);
        var added = 0;
        on.forEach(function (b) {
          if (added >= 20 || b.isPhysical || have[String(b.id)] || inInbox(inbox, b.id)) return;
          if (queue.some(function (q) { return String(q.id) === String(b.id); })) return;
          queue.push({ id: b.id, kind: "book", title: b.title, authors: b.authors, format: b.primaryFileType, file_id: b.primaryFileId,
            name: (b.primaryFileName || "").split(/[\/\\]/).pop(), size_kb: b.fileSizeKb, shelf: true });
          added++;
        });
        if (added) log(added + " new book" + (added === 1 ? "" : "s") + " on “" + (shelf.name || "your shelf") + "”.");
      } catch (e) { log("Couldn't read the auto-download shelf: " + e.message, "bad"); }
    }
    queue = queue.filter(function (q) { return !inInbox(inbox, q.id); });
    if (!queue.length) return;
    var total = queue.reduce(function (a, q) { return a + (Number(q.size_kb) || 0) * 1024; }, 0), got = 0;
    for (var i = 0; i < queue.length; i++) {
      var q = queue[i];
      phase("Bringing “" + (q.title || "?") + "” (" + (i + 1) + " of " + queue.length + ")…");
      try {
        if (q.kind === "audiobook") await bringAudiobook(q, inbox, function (n) { got += n; bar.set(got, total); });
        else await bringBook(q, inbox, function (n) { got += n; bar.set(got, total); });
        await saveInbox(inbox);
        log("“" + (q.title || "?") + "” is on its way to the Kindle.", "ok");
      } catch (e) {
        log("“" + (q.title || "?") + "” couldn't be brought: " + e.message, "bad");
        if (/quota|space|NoModificationAllowed|InvalidState/i.test(String(e.name) + e.message)) { log("The Kindle may be full.", "bad"); break; }
      }
    }
  }

  async function bringBook(q, inbox, onBytes) {
    var r = await G.fetch("/api/v1/books/" + q.id + "/download");
    if (!r.ok) throw new HttpError(r.status, "Grimmory");
    var ext = extOf(q.name, String(q.format || "epub").toLowerCase());
    if (ext === "cbx") ext = "cbz";
    var file = "in/book-" + q.id + "." + ext;
    var slim = null;
    if (ext === "epub" && Opt.slim) {
      // (the whole book here first: its big pictures made the Kindle's size, see Slim)
      var blob = await new Response(r.body.pipeThrough(new TransformStream({ transform: function (chunk, c) { onBytes(chunk.byteLength); c.enqueue(chunk); } }))).blob();
      var res = null;
      try { res = await Slim.epub(blob, Sleep.screen()); } catch (e) { log("“" + q.title + "”: pictures left as they were (" + e.message + ").", "warn"); }
      if (res && res.changed) {
        slim = { before: blob.size, after: res.blob.size, pictures: res.changed };
        log("“" + q.title + "”: " + res.changed + " picture" + (res.changed === 1 ? "" : "s") + " made the Kindle's size, " +
          Math.round(blob.size / 1024) + " → " + Math.round(res.blob.size / 1024) + " KB.", "ok");
        blob = res.blob;
      }
      await Drive.write(Drive.sync, file, blob);
    } else {
      await Drive.writeStream(Drive.sync, file, r.body, onBytes);
    }
    var progress = null;
    try { progress = progressOf(await G.json("/api/v1/books/" + q.id)); } catch (e) {}
    inbox.books.push({ id: q.id, file: file, name: q.name, title: q.title, authors: q.authors, format: q.format, file_id: q.file_id,
      subtitle: (K.subtitles || {})[String(q.id)], progress: progress || undefined, slim: slim || undefined });
  }

  // ------------------------------------------------------------ slim EPUB copies
  // An EPUB's big pictures (scanned pages, full-size covers, photos) made the
  // Kindle's screen size and grey, before the book goes to the Kindle: the book
  // engine decodes and scales every picture when it lays a book out, which on
  // a Kindle 3 or DX is much of a picture-heavy book's open time and memory.
  // Each picture keeps its name and format (a JPEG stays a JPEG, a PNG a PNG),
  // so nothing else in the book changes (pages, positions, highlights); one is
  // replaced only if it gets smaller. Everything else in the zip is copied byte
  // for byte. Grimmory keeps the original.
  var Slim = {
    MIN_BYTES: 64 * 1024, // smaller pictures: left as they are
    CRC: null,
    crc32: function (u8) {
      if (!Slim.CRC) {
        Slim.CRC = new Uint32Array(256);
        for (var n = 0; n < 256; n++) { var c = n; for (var k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; Slim.CRC[n] = c >>> 0; }
      }
      var crc = 0xFFFFFFFF;
      for (var i = 0; i < u8.length; i++) crc = Slim.CRC[(crc ^ u8[i]) & 0xFF] ^ (crc >>> 8);
      return (crc ^ 0xFFFFFFFF) >>> 0;
    },
    // the zip's entries from its central directory (null: not a zip we can rewrite)
    entries: async function (blob) {
      var tailLen = Math.min(blob.size, 65557);
      var tail = new Uint8Array(await blob.slice(blob.size - tailLen).arrayBuffer());
      var dv = new DataView(tail.buffer), eocd = -1;
      for (var i = tail.length - 22; i >= 0; i--) { if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; } }
      if (eocd < 0) return null;
      var count = dv.getUint16(eocd + 10, true), cdSize = dv.getUint32(eocd + 12, true), cdOff = dv.getUint32(eocd + 16, true);
      if (count === 0xFFFF || cdSize === 0xFFFFFFFF || cdOff === 0xFFFFFFFF) return null; // (zip64)
      var cd = new Uint8Array(await blob.slice(cdOff, cdOff + cdSize).arrayBuffer());
      var c = new DataView(cd.buffer), dec = new TextDecoder(), out = [];
      for (var p = 0; p + 46 <= cd.length && c.getUint32(p, true) === 0x02014b50;) {
        var nlen = c.getUint16(p + 28, true), elen = c.getUint16(p + 30, true), clen = c.getUint16(p + 32, true);
        out.push({ cdir: cd.slice(p, p + 46 + nlen + elen + clen), name: dec.decode(cd.subarray(p + 46, p + 46 + nlen)),
          method: c.getUint16(p + 10, true), csize: c.getUint32(p + 20, true), size: c.getUint32(p + 24, true),
          nameBytes: cd.slice(p + 46, p + 46 + nlen), lho: c.getUint32(p + 42, true) });
        p += 46 + nlen + elen + clen;
      }
      if (out.length !== count) return null;
      out.cdOff = cdOff;
      return out;
    },
    data: async function (blob, e) {
      var lh = new DataView(await blob.slice(e.lho, e.lho + 30).arrayBuffer());
      if (lh.getUint32(0, true) !== 0x04034b50) throw new Error("a damaged zip");
      var start = e.lho + 30 + lh.getUint16(26, true) + lh.getUint16(28, true);
      var raw = blob.slice(start, start + e.csize);
      if (e.method === 0) return raw;
      if (e.method === 8) return new Response(raw.stream().pipeThrough(new DecompressionStream("deflate-raw"))).blob();
      return null;
    },
    // a picture at most the screen's size, grey, in its own format; null: leave it
    picture: async function (data, type, screen) {
      var img;
      try { img = await createImageBitmap(data); } catch (e) { return null; }
      var scale = Math.min(screen.w / img.width, screen.h / img.height, 1);
      var w = Math.max(1, Math.round(img.width * scale)), h = Math.max(1, Math.round(img.height * scale));
      var canvas = typeof OffscreenCanvas !== "undefined" ? new OffscreenCanvas(w, h) : Object.assign(document.createElement("canvas"), { width: w, height: h });
      var ctx = canvas.getContext("2d");
      ctx.filter = "grayscale(1)";
      ctx.drawImage(img, 0, 0, w, h);
      if (img.close) img.close();
      var out = canvas.convertToBlob ? await canvas.convertToBlob({ type: type, quality: 0.8 })
        : await new Promise(function (ok) { canvas.toBlob(ok, type, 0.8); });
      return out && out.type === type && out.size < data.size ? out : null;
    },
    epub: async function (blob, screen) {
      var list = await Slim.entries(blob);
      if (!list) return null;
      var TYPES = { jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png" };
      var parts = [], central = [], offset = 0, changed = 0;
      // (the local entries in the order they're in the file: each copied up to the next one)
      var byPos = list.slice().sort(function (a, b) { return a.lho - b.lho; });
      for (var i = 0; i < byPos.length; i++) byPos[i].end = i + 1 < byPos.length ? byPos[i + 1].lho : list.cdOff;
      // (written in the file's order: the mimetype stays first; the directory in its own order)
      for (var j = 0; j < byPos.length; j++) {
        var e = byPos[j], ext = (e.name.match(/\.([a-z0-9]+)$/i) || [])[1], type = ext && TYPES[ext.toLowerCase()];
        var repl = null;
        if (type && e.size >= Slim.MIN_BYTES) {
          var data = await Slim.data(blob, e);
          if (data) repl = await Slim.picture(data, type, screen);
        }
        var cdir = e.cdir.slice(), cv = new DataView(cdir.buffer);
        if (repl) {
          var bytes = new Uint8Array(await repl.arrayBuffer()), crc = Slim.crc32(bytes);
          var flags = cv.getUint16(8, true) & ~8; // (no data descriptor; a UTF-8 name stays marked)
          var lh = new Uint8Array(30 + e.nameBytes.length), lv = new DataView(lh.buffer);
          lv.setUint32(0, 0x04034b50, true); lv.setUint16(4, 20, true); lv.setUint16(6, flags, true); lv.setUint16(8, 0, true);
          lv.setUint16(10, cv.getUint16(12, true), true); lv.setUint16(12, cv.getUint16(14, true), true); lv.setUint32(14, crc, true);
          lv.setUint32(18, bytes.length, true); lv.setUint32(22, bytes.length, true);
          lv.setUint16(26, e.nameBytes.length, true); lv.setUint16(28, 0, true); lh.set(e.nameBytes, 30);
          cv.setUint16(8, flags, true); cv.setUint16(10, 0, true);
          cv.setUint32(16, crc, true); cv.setUint32(20, bytes.length, true); cv.setUint32(24, bytes.length, true);
          cv.setUint32(42, offset, true);
          parts.push(lh, bytes);
          offset += lh.length + bytes.length;
          changed++;
        } else {
          var raw = blob.slice(e.lho, e.end);
          cv.setUint32(42, offset, true);
          parts.push(raw);
          offset += raw.size;
        }
        e.newDir = cdir;
      }
      for (var k = 0; k < list.length; k++) central.push(list[k].newDir);
      if (!changed) return { changed: 0, blob: blob };
      var cdSize = central.reduce(function (n, c) { return n + c.length; }, 0);
      var end = new Uint8Array(22), ev = new DataView(end.buffer);
      ev.setUint32(0, 0x06054b50, true); ev.setUint16(8, list.length, true); ev.setUint16(10, list.length, true);
      ev.setUint32(12, cdSize, true); ev.setUint32(16, offset, true);
      return { changed: changed, blob: new Blob(parts.concat(central, [end]), { type: "application/epub+zip" }) };
    },
  };

  // Grimmory's reading progress of a book: the Kindle opens it there the first time
  var PROGRESS_KEYS = ["epubProgress", "pdfProgress", "cbxProgress", "audiobookProgress"];
  function progressOf(book) {
    if (!book || typeof book !== "object") return null;
    var p = {}, any = false;
    PROGRESS_KEYS.forEach(function (k) {
      var v = book[k];
      if (v && typeof v === "object" && Object.keys(v).length) { p[k] = v; any = true; }
    });
    return any ? p : null;
  }

  async function bringAudiobook(q, inbox, onBytes) {
    var info = await G.json("/api/v1/audiobooks/" + q.id + "/info");
    var progress = null;
    try {
      var full = await G.json("/api/v1/books/" + q.id);
      if (full.metadata && full.metadata.description) info.gz_description = full.metadata.description;
      progress = progressOf(full);
    } catch (e) {}
    var dir = "in/audio-" + q.id;
    var files = [];
    if (info.folderBased && Array.isArray(info.tracks) && info.tracks.length) {
      info.tracks.forEach(function (t, i) {
        files.push({ name: "track-" + ("00" + (i + 1)).slice(-3) + "." + extOf(t.fileName, "mp3"),
          url: "/api/v1/audiobooks/" + q.id + "/track/" + (t.index != null ? t.index : i) + "/stream" });
      });
    } else {
      files.push({ name: "audiobook." + extOf(q.name, /mp3/i.test(info.codec || "") ? "mp3" : "m4b"), url: "/api/v1/audiobooks/" + q.id + "/stream" });
    }
    for (var i = 0; i < files.length; i++) {
      var r = await G.fetch(files[i].url);
      if (!r.ok) throw new HttpError(r.status, "Grimmory");
      if (Mp4.needs(files[i].name)) await Mp4.bring(dir, files[i].name, r.body, onBytes, q.title + (files.length > 1 ? " (" + (i + 1) + "/" + files.length + ")" : ""));
      else await Drive.writeStream(Drive.sync, dir + "/" + files[i].name, r.body, onBytes);
    }
    try {
      var c = await G.fetch("/api/v1/audiobooks/" + q.id + "/cover");
      if (c.ok) await Drive.write(Drive.sync, dir + "/cover.jpg", await c.blob());
    } catch (e) {}
    inbox.audiobooks.push({ id: q.id, dir: dir, info: info, primaryFileName: q.name, title: q.title, progress: progress || undefined });
  }

  // ------------------------------------------------------------ M4B/M4A → ADTS AAC chunks

  // The Kindle can decode AAC but can't open MP4 files, so GZreader repacks
  // M4B/M4A audio once into ~15-second ADTS AAC files (gzreader_mp4.lua): on
  // a Kindle DX that takes 8 minutes and more for a long book. Done here
  // instead, with the same files (byte for byte: sync_page_test.py compares
  // them with gzreader_mp4.lua's): <file>.chunks/c0.aac, c1.aac… and
  // index.json, written last. GZreader then finds them ready and has nothing
  // to do (Audiobook.prepare skips a track with an index; Music.trackReady).
  // The download waits in the browser's own storage (not on the Kindle) while
  // it's converted; if anything fails, the file goes to the Kindle as it is,
  // and GZreader converts it as before.
  var Mp4 = {
    CHUNK_SECONDS: 15,
    WINDOW: 4 << 20, // bytes read from the file at a time
    CONTAINERS: { moov: true, trak: true, mdia: true, minf: true, stbl: true },
    needs: function (name) { return /\.(m4a|m4b|mp4)$/i.test(name || ""); },
    // reads of a Blob (a File) at any place, through a window
    reader: function (blob) {
      var w = null, wAt = 0;
      return async function (pos, n) {
        pos = Math.max(0, pos); n = Math.max(0, Math.min(n, blob.size - pos));
        if (n <= 0) return new Uint8Array(0);
        if (!w || pos < wAt || pos + n > wAt + w.length) {
          if (n > Mp4.WINDOW) return new Uint8Array(await blob.slice(pos, pos + n).arrayBuffer());
          wAt = pos;
          w = new Uint8Array(await blob.slice(pos, Math.min(blob.size, pos + Mp4.WINDOW)).arrayBuffer());
        }
        return w.subarray(pos - wAt, pos - wAt + n);
      };
    },
    u32: function (d, i) { return i + 4 <= d.length ? ((d[i] << 24) >>> 0) + (d[i + 1] << 16) + (d[i + 2] << 8) + d[i + 3] : 0; },
    u64: function (d, i) { return Mp4.u32(d, i) * 4294967296 + Mp4.u32(d, i + 4); },
    str: function (d, i, n) { return String.fromCharCode.apply(null, Array.prototype.slice.call(d.subarray(i, i + n))); },
    // a table of 4- or 8-byte entries, whole (a long book's sample sizes: a few MB)
    table: async function (read, at, n, width) {
      var d = await read(at, n * width), out = new Float64Array(n);
      for (var k = 0; k < n; k++) out[k] = (k + 1) * width <= d.length ? (width === 8 ? Mp4.u64(d, k * 8) : Mp4.u32(d, k * 4)) : 0;
      return out;
    },
    // the first sound track's timescale, sample tables and AAC config (esds)
    parse: async function (blob) {
      var read = Mp4.reader(blob), size = blob.size, tracks = [], cur = null;
      var walk = async function (start, stop) {
        var pos = start;
        while (pos + 8 <= stop) {
          var hdr = (await read(pos, 16)).slice();
          if (hdr.length < 8) break;
          var bsize = Mp4.u32(hdr, 0), btype = Mp4.str(hdr, 4, 4), hlen = 8;
          if (bsize === 1) { bsize = Mp4.u64(hdr, 8); hlen = 16; } else if (bsize === 0) bsize = stop - pos;
          if (bsize < hlen) break;
          var body = pos + hlen, end = pos + bsize, d;
          if (btype === "trak") { cur = {}; tracks.push(cur); await walk(body, end); }
          else if (Mp4.CONTAINERS[btype]) await walk(body, end);
          else if (cur) {
            if (btype === "hdlr") cur.handler = Mp4.str(await read(body + 8, 4), 0, 4);
            else if (btype === "mdhd") {
              d = await read(body, 32);
              if (d[0] === 1) { cur.timescale = Mp4.u32(d, 20); cur.duration = Mp4.u64(d, 24); }
              else { cur.timescale = Mp4.u32(d, 12); cur.duration = Mp4.u32(d, 16); }
            } else if (btype === "stsd") {
              d = (await read(body, Math.min(bsize - hlen, 4096))).slice();
              cur.codec = Mp4.str(d, 12, 4);
              var e = -1;
              for (var j = 0; j + 4 <= d.length; j++) if (d[j] === 101 && d[j + 1] === 115 && d[j + 2] === 100 && d[j + 3] === 115) { e = j; break; }
              if (e >= 0) {
                var i = e + 8; // after "esds" and its version/flags: the descriptors
                while (i < d.length) {
                  var tag = d[i++], len = 0;
                  for (var q = 0; q < 4; q++) {
                    var b = d[i++];
                    if (b === undefined) break;
                    len = len * 128 + (b & 0x7f);
                    if (b < 0x80) break;
                  }
                  if (tag === 0x03) i += 3;       // ES_ID, flags
                  else if (tag === 0x04) i += 13; // DecoderConfig's fixed part
                  else if (tag === 0x05) { cur.asc = d.slice(i, i + len); break; } // DecoderSpecificInfo
                  else i += len;
                }
              }
            } else if (btype === "stts" || btype === "stsc") {
              d = await read(body, 8);
              var words = btype === "stts" ? 2 : 3, n = Mp4.u32(d, 4);
              cur[btype] = await Mp4.table(read, body + 8, n * words, 4);
              cur[btype + "_n"] = n;
            } else if (btype === "stsz") {
              d = await read(body, 12);
              var fixed = Mp4.u32(d, 4);
              cur.count = Mp4.u32(d, 8); cur.fixed_size = fixed > 0 ? fixed : null; cur.stsz_at = body + 12;
            } else if (btype === "stco" || btype === "co64") {
              d = await read(body, 8);
              cur.chunk_count = Mp4.u32(d, 4); cur.stco_at = body + 8; cur.stco_w = btype === "stco" ? 4 : 8;
            }
          }
          pos = end;
        }
      };
      await walk(0, size);
      for (var k = 0; k < tracks.length; k++) {
        var t = tracks[k];
        if (t.handler === "soun" && t.codec === "mp4a" && t.asc && t.count != null && t.stco_at != null && t.stsc && t.stts) {
          t.file_size = size; t.read = read;
          return t;
        }
      }
      throw new Error("no AAC audio track found");
    },
    // AudioSpecificConfig → object type, sampling frequency index, channels
    config: function (asc) {
      var b0 = asc[0], b1 = asc[1] || 0;
      var ot = b0 >> 3, sfi = ((b0 & 7) << 1) | (b1 >> 7), ch = (b1 >> 3) & 0xf;
      if (ot === 5 || ot === 29) ot = 2; // HE-AAC: the core is AAC-LC
      return [ot, sfi, ch];
    },
    adts: function (ot, sfi, ch, n) {
      var len = n + 7;
      return new Uint8Array([0xff, 0xf1, (((ot - 1) & 3) << 6) | ((sfi & 0xf) << 2) | ((ch >> 2) & 1),
        ((ch & 3) << 6) | ((len >> 11) & 3), (len >> 3) & 0xff, ((len & 7) << 5) | 0x1f, 0xfc]);
    },
    // the chunk files, through write(name, blob) (a few at once); progress(done, total)
    convert: async function (blob, write, progress) {
      var t = await Mp4.parse(blob), read = t.read;
      var cfg = Mp4.config(t.asc), ot = cfg[0], sfi = cfg[1], ch = cfg[2];
      var sizes = t.fixed_size ? null : await Mp4.table(read, t.stsz_at, t.count, 4);
      var offsets = await Mp4.table(read, t.stco_at, t.chunk_count, t.stco_w);
      var chunkLen = Mp4.CHUNK_SECONDS * t.timescale;
      var sttsI = 0, sttsLeft = t.stts_n > 0 ? t.stts[0] : 0;
      var nextDuration = function () {
        while (sttsI < t.stts_n && sttsLeft === 0) { sttsI++; sttsLeft = sttsI < t.stts_n ? t.stts[sttsI * 2] : 0; }
        if (sttsI >= t.stts_n) return 1024;
        sttsLeft--;
        return t.stts[sttsI * 2 + 1];
      };
      var starts = [], outN = -1, pieces = [], time = 0, sample = 0, done = 0, nextReport = 0, writing = [];
      var flush = async function () {
        var name = "c" + outN + ".aac", data = new Blob(pieces);
        pieces = [];
        writing.push(write(name, data));
        if (writing.length >= 4) await writing.shift();
      };
      var openChunk = async function () {
        if (outN >= 0) await flush();
        outN++;
        starts.push(Math.floor(time * 1000 / t.timescale));
      };
      await openChunk();
      var stscI = 0;
      for (var c = 0; c < t.chunk_count; c++) {
        while (stscI + 1 < t.stsc_n && t.stsc[(stscI + 1) * 3] <= c + 1) stscI++;
        var n = t.stsc[stscI * 3 + 1], chunkSizes = [], total = 0;
        for (var k = 0; k < n; k++) {
          if (sample + k >= t.count) break;
          var sz = t.fixed_size || (sizes && sizes[sample + k]) || 0;
          chunkSizes.push(sz); total += sz;
        }
        if (c >= offsets.length) break;
        var data = (await read(offsets[c], total)).slice(), pos = 0;
        for (k = 0; k < chunkSizes.length; k++) {
          sz = chunkSizes[k];
          if (time >= (outN + 1) * chunkLen) await openChunk();
          pieces.push(Mp4.adts(ot, sfi, ch, sz), data.subarray(pos, pos + sz));
          pos += sz;
          time += nextDuration();
          sample++;
        }
        done += total;
        if (progress && done >= nextReport) {
          progress(done, t.file_size);
          nextReport = done + Math.max(256 * 1024, Math.floor(t.file_size / 200));
        }
      }
      await flush();
      await Promise.all(writing);
      if (progress) progress(t.file_size, t.file_size);
      return { starts: starts, durationMs: Math.floor(time * 1000 / t.timescale), count: outN + 1 };
    },
    indexJson: function (res) {
      return '{"starts":[' + res.starts.map(function (v) { return String(Math.floor(v)); }).join(",") + '],"durationMs":' + res.durationMs + ',"count":' + res.count + "}";
    },
    // The browser's own storage, for the download while it's converted (null: none here).
    scratch: async function () {
      try { return await (await navigator.storage.getDirectory()).getDirectoryHandle("gzsync-prepare", { create: true }); }
      catch (e) { return null; }
    },
    // Download an M4B/M4A (a fetch response's body) to path on the Kindle:
    // as chunks when it can, else the file as it is. Returns true if converted.
    bring: async function (dir, name, body, onBytes, what) {
      var tmp = Mp4.scratch && await Mp4.scratch(), tmpName = rand(8) + ".m4a";
      if (!tmp) { await Drive.writeStream(Drive.sync, dir + "/" + name, body, onBytes); return false; }
      try {
        await Drive.writeStream(tmp, tmpName, body, onBytes);
        var file = await (await tmp.getFileHandle(tmpName)).getFile();
        var cdir = dir + "/" + name + ".chunks", started = Date.now();
        try {
          var res = await Mp4.convert(file, function (n, data) { return Drive.write(Drive.sync, cdir + "/" + n, data); }, function (d, total) {
            phase("Preparing “" + (what || name) + "” for the Kindle… " + Math.floor(d * 100 / Math.max(1, total)) + "%");
          });
          await Drive.write(Drive.sync, cdir + "/index.json", Mp4.indexJson(res));
          log("“" + (what || name) + "”: prepared for the Kindle here (" + res.count + " parts, " + Math.round((Date.now() - started) / 1000) + " s).");
          return true;
        } catch (e) {
          await Drive.remove(Drive.sync, cdir);
          log("“" + (what || name) + "” couldn't be prepared here (" + e.message + "): the Kindle prepares it.");
          await Drive.write(Drive.sync, dir + "/" + name, file);
          return false;
        }
      } finally {
        try { await tmp.removeEntry(tmpName); } catch (e) {}
      }
    },
  };

  // 4. notes
  async function syncNotes(out, inbox) {
    var n = out.notes || {};
    var prev = inbox.notes || {};
    var done = (prev.done || []).slice();
    var sentNow = 0;
    phase("Notes: sending what was written on the Kindle…");
    for (var i = 0; i < (n.queue || []).length; i++) {
      var q = n.queue[i];
      if (done.indexOf(q.id) >= 0) continue;
      var r;
      if (q.op === "create") r = await M.req("POST", "/memos", { content: q.content, visibility: q.visibility || "PRIVATE" });
      else if (q.op === "update") r = await M.req("PATCH", "/" + q.name, { name: q.name, content: q.content, visibility: q.visibility },
        { updateMask: q.visibility ? "content,visibility" : "content" });
      else if (q.op === "pin") r = await M.req("PATCH", "/" + q.name, { name: q.name, pinned: q.pinned === true }, { updateMask: "pinned" });
      else { done.push(q.id); continue; }
      if (r.ok) { done.push(q.id); sentNow++; }
      else if (r.status === 401 || r.status === 403) throw new Error("Memos didn't accept the access token.");
      else if (r.status >= 400 && r.status < 500) done.push(q.id); // refused for good: dropped
      else break;
    }
    phase("Notes: bringing your notes…");
    var keep = Number(n.keep) || 100;
    var filter = null;
    if (Array.isArray(n.sync_tags) && n.sync_tags.length) filter = "tag in [" + n.sync_tags.map(function (t) { return JSON.stringify(String(t)); }).join(", ") + "]";
    var notes = [], token = null;
    do {
      var r2 = await M.req("GET", "/memos", undefined, { pageSize: Math.min(200, keep - notes.length), pageToken: token, filter: filter, orderBy: "pinned desc, create_time desc" });
      if (r2.status === 401 || r2.status === 403) throw new Error("Memos didn't accept the access token.");
      if (!r2.ok) throw new HttpError(r2.status, "Memos");
      var d = await r2.json();
      (d.memos || []).forEach(function (m) { notes.push(slimMemo(m)); });
      token = d.nextPageToken || null;
    } while (token && notes.length < keep);
    var tags = null;
    try {
      if (!M.st.userName) { var u = await M.me(); M.st.userName = u.name; M.save(); }
      var rs = await M.req("GET", "/" + M.st.userName + ":getStats");
      if (rs.ok) { var sd = await rs.json(); tags = sd.tagCounts || sd.tagCount || null; }
    } catch (e) {}
    await Drive.write(Drive.sync, "in/notes.json", JSON.stringify({ notes: notes, at: Math.floor(Date.now() / 1000), tags: tags }));
    // their pictures (not already on the Kindle)
    var have = new Set(n.files || []);
    var budget = (Number(n.files_mb) || 50) * 1048576 * 0.8, pics = [];
    notes.forEach(function (m) {
      m.attachments.forEach(function (a) {
        var fname = memoFileName(a);
        if (/^image\//.test(a.type || "") && !a.link && (a.size || 0) <= 3145728 && !have.has(fname) && budget - (a.size || 0) > 0) {
          budget -= a.size || 0;
          pics.push({ a: a, fname: fname });
        }
      });
    });
    await pool(pics, 3, async function (p) {
      var uid = (String(p.a.name || "").match(/attachments\/(.+)$/) || [])[1];
      if (!uid) return;
      try {
        var r3 = await fetch(M.st.server + "/file/attachments/" + uid + "/" + encodeURIComponent(p.a.filename || "file"), { headers: { Authorization: "Bearer " + M.st.token } });
        if (r3.ok) await Drive.write(Drive.sync, "in/notes-files/" + p.fname, await r3.blob());
      } catch (e) {}
    });
    inbox.notes = { file: "in/notes.json", files: "in/notes-files", done: done, server: M.st.server, user: M.st.user };
    await saveInbox(inbox);
    log("Notes: " + notes.length + " brought" + (sentNow ? ", " + sentNow + " change" + (sentNow === 1 ? "" : "s") + " sent to Memos" : "") + (pics.length ? ", " + pics.length + " picture" + (pics.length === 1 ? "" : "s") : "") + ".", "ok");
  }

  // 5. calendars
  async function syncCalendars(out, inbox) {
    phase("Calendars…");
    var range = Cal.range(out);
    var list = [], events = 0;
    for (var i = 0; i < Cal.list.length; i++) {
      var src = Cal.list[i];
      var label = src.name || (src.type === "file" ? "calendar file" : hostOf(src.url));
      try {
        var text = await Cal.text(src, range);
        if (!text || text.indexOf("BEGIN:VCALENDAR") < 0) throw new Error("it isn't a calendar");
        var named = (text.match(/\nX-WR-CALNAME[^:\r\n]*:([^\r\n]*)/) || [])[1];
        var file = "in/calendar/" + (list.length + 1) + ".ics";
        await Drive.write(Drive.sync, file, text);
        list.push({ name: src.name || named || label, file: file });
        events += (text.match(/BEGIN:VEVENT/g) || []).length;
      } catch (e) {
        log("Calendar “" + label + "”: " + e.message, "bad");
        list.push({ name: src.name || label, file: null });
      }
    }
    inbox.calendars = list;
    await saveInbox(inbox);
    log("Calendars: " + list.filter(function (c) { return c.file; }).length + " of " + list.length + " brought (" + events + " events).", "ok");
  }

  // 6. music
  function picks() { return Picks.d.music; }
  function setPicks(l) { Picks.d.music = l; Picks.save(); }
  function safe(s) { return String(s == null ? "" : s).replace(/[^A-Za-z0-9\-]/g, "_"); }

  async function syncMusic(out, inbox) {
    var have = new Set(((out.have || {}).music) || []);
    var abHave = new Set((((out.have || {}).audiobooks) || []).map(String));
    var todo = picks().filter(function (p) {
      if (p.kind === "audiobook") return !abHave.has("plex-" + p.key) && !inbox.audiobooks.some(function (a) { return String(a.id) === "plex-" + p.key; });
      var k = safe(p.kind) + "-" + safe(p.key);
      return !have.has(p.kind + "-" + p.key) && !have.has(k) && !inbox.music.some(function (m) { return m.kind === p.kind && String(m.key) === String(p.key); });
    });
    for (var i = 0; i < todo.length; i++) {
      var p = todo[i];
      if (p.kind === "audiobook") {
        phase("Audiobook: “" + p.title + "”…");
        try {
          await bringPlexAudiobook(p, inbox);
          await saveInbox(inbox);
          log("“" + p.title + "” (audiobook, Plex) is on its way to the Kindle.", "ok");
        } catch (e) { log("Audiobook: “" + p.title + "” couldn't be brought: " + e.message, "bad"); }
        continue;
      }
      phase("Music: “" + p.title + "”…");
      try {
        var tracks = p.kind === "playlist" ? await playlistTracks(p.key) : await P.items("/library/metadata/" + encodeURIComponent(p.key) + "/children");
        tracks = tracks.filter(function (t) { return t.type === "track" || t.part; });
        var dir = "in/music-" + safe(p.kind) + "-" + safe(p.key);
        var col = { kind: p.kind, key: String(p.key), title: p.title, artist: p.artist, year: p.year, added: Math.floor(Date.now() / 1000), tracks: [] };
        for (var j = 0; j < tracks.length; j++) {
          var t = tracks[j], base = ("0" + (j + 1)).slice(-2);
          bar.set(j, tracks.length);
          var entry = { key: t.key, title: t.title, artist: t.artist, album: t.album, duration: t.duration, base: base, part: t.part };
          try { entry.file = await bringTrack(t, dir, base); } catch (e) { log("“" + t.title + "”: " + e.message, "bad"); }
          col.tracks.push(entry);
        }
        if (p.thumb) {
          try {
            var c = await P.get("/photo/:/transcode", { url: p.thumb, width: 300, height: 300, minSize: 1, upscale: 1, format: "jpeg" });
            await Drive.write(Drive.sync, dir + "/cover.jpg", await c.blob());
          } catch (e) {}
        }
        await Drive.write(Drive.sync, dir + "/music.json", JSON.stringify(col));
        inbox.music.push({ kind: p.kind, key: String(p.key), dir: dir });
        await saveInbox(inbox);
        var nt = col.tracks.filter(function (x) { return x.file; }).length;
        log("Music: “" + p.title + "”, " + nt + " track" + (nt === 1 ? "" : "s") + ".", "ok");
      } catch (e) { log("Music: “" + p.title + "” couldn't be brought: " + e.message, "bad"); }
    }
  }

  // A Plex audiobook (an album of the library the Kindle takes audiobooks
  // from): its tracks as the book's files, laid out as gzreader_plex.lua's
  // Plex:audiobookInfo describes it, so the Kindle takes it like Grimmory's
  // (Usb.takeAudiobook), as plex-<key>.
  async function bringPlexAudiobook(p, inbox) {
    var meta = await (await P.get("/library/metadata/" + encodeURIComponent(p.key))).json();
    var album = ((meta.MediaContainer || {}).Metadata || [])[0] || {};
    var tracks = (await P.items("/library/metadata/" + encodeURIComponent(p.key) + "/children")).filter(function (t) { return t.type === "track" || t.part; });
    if (!tracks.length) throw new Error("it has no tracks on Plex");
    var dir = "in/audio-plex-" + safe(p.key);
    var info = { title: album.title || p.title, author: album.parentTitle || p.artist, folderBased: true, tracks: [], chapters: [],
      gz_description: album.summary || undefined, plexKey: String(p.key), plexThumb: album.thumb || p.thumb || undefined };
    var start = 0;
    for (var j = 0; j < tracks.length; j++) {
      var t = tracks[j];
      bar.set(j, tracks.length);
      var file = await bringTrack(t, dir, "track-" + ("00" + (j + 1)).slice(-3));
      info.tracks.push({ index: j, fileName: "track." + extOf(file, "mp3"), durationMs: Number(t.duration) || 0, cumulativeStartMs: start,
        title: t.title, plexKey: String(t.key) });
      start += Number(t.duration) || 0;
    }
    info.durationMs = start;
    if (tracks.length === 1) {
      try { // (one file: its chapters, when Plex has them)
        var cm = await (await P.get("/library/metadata/" + encodeURIComponent(tracks[0].key), { includeChapters: 1 })).json();
        var ch = (((cm.MediaContainer || {}).Metadata || [])[0] || {}).Chapter || [];
        ch.forEach(function (c, i) {
          if (c.startTimeOffset == null) return;
          info.chapters.push({ title: c.tag || ("Chapter " + (i + 1)), startTimeMs: Number(c.startTimeOffset),
            durationMs: c.endTimeOffset != null ? Number(c.endTimeOffset) - Number(c.startTimeOffset) : undefined });
        });
      } catch (e) {}
    }
    if (info.plexThumb) {
      try {
        var c = await P.get("/photo/:/transcode", { url: info.plexThumb, width: 600, height: 600, minSize: 1, upscale: 1, format: "jpeg" });
        await Drive.write(Drive.sync, dir + "/cover.jpg", await c.blob());
      } catch (e) {}
    }
    inbox.audiobooks.push({ id: "plex-" + p.key, dir: dir, info: info, title: info.title });
  }

  async function playlistTracks(key) {
    var out = [];
    for (var start = 0; start < 5000; start += 100) {
      var page = await P.items("/playlists/" + encodeURIComponent(key) + "/items", null,
        { "X-Plex-Container-Start": String(start), "X-Plex-Container-Size": "100" });
      out = out.concat(page);
      if (page.length < 100) break;
    }
    return out;
  }

  async function bringTrack(t, dir, base) {
    var how = P.how(t);
    if (how[0] === "file") {
      if (!t.part || !t.part.key) throw new Error("no file");
      var r = await P.get(t.part.key, { download: 1 });
      if (how[1] === "m4a") await Mp4.bring(dir, base + ".m4a", r.body, null, t.title);
      else await Drive.writeStream(Drive.sync, dir + "/" + base + "." + how[1], r.body);
      return base + "." + how[1];
    }
    // the server's MP3 (FLAC, ALAC, Ogg…): its transcoder, HLS with MP3 in MPEG-TS
    var session = rand(8);
    var params = { path: "/library/metadata/" + t.key, protocol: "hls", mediaIndex: 0, partIndex: 0, directPlay: 0, directStream: 0,
      directStreamAudio: 0, musicBitrate: P.quality().bitrate, fastSeek: 1, hasMDE: 1, "X-Plex-Session-Identifier": session, session: session,
      location: "lan", "X-Plex-Platform": "Chrome", "X-Plex-Client-Identifier": P.clientId(), "X-Plex-Product": "GZreader",
      "X-Plex-Client-Profile-Extra": "add-transcode-target(type=musicProfile&context=streaming&protocol=hls&container=mpegts&audioCodec=mp3)" };
    var start = P.st.server.uri + "/music/:/transcode/universal/start.m3u8";
    var lines = function (txt) { return String(txt).split(/\r?\n/).filter(function (l) { return l && l[0] !== "#"; }); };
    var text = await (await P.get("/music/:/transcode/universal/start.m3u8", params)).text();
    var media = start, list = lines(text);
    if (list[0] && /\.m3u8/.test(list[0])) {
      media = new URL(list[0], start).href;
      text = await (await fetch(media, { headers: P.headers(P.st.server.token) })).text();
      list = lines(text);
    }
    if (!list.length) throw new Error("the transcoder sent nothing");
    var state = {}, chunks = [];
    for (var i = 0; i < list.length; i++) {
      var data = null;
      for (var tries = 0; tries < 20 && !data; tries++) {
        var r2 = await fetch(new URL(list[i], media).href, { headers: P.headers(P.st.server.token) });
        if (r2.ok) { var buf = new Uint8Array(await r2.arrayBuffer()); if (buf.length) data = buf; }
        if (!data) await new Promise(function (ok) { setTimeout(ok, 1000); });
      }
      if (!data) throw new Error("a part of the track never came");
      demuxTs(data, state, chunks);
    }
    try { await fetch(P.st.server.uri + "/music/:/transcode/universal/stop" + qs({ session: session }), { headers: P.headers(P.st.server.token) }); } catch (e) {}
    if (!state.bytes) throw new Error("no audio");
    var ext = state.type === 0x0f ? "aac" : "mp3";
    await Drive.write(Drive.sync, dir + "/" + base + "." + ext, new Blob(chunks));
    return base + "." + ext;
  }

  // Usage statistics GZreader up to 1.28.1 left in usage/: deleted, not sent
  // (GZreader sends no usage statistics since).
  async function dropUsage() {
    var dir = await Drive.tryDir(Drive.sync, "usage");
    if (!dir) return;
    var names = [];
    for await (var entry of dir.values()) if (entry.kind === "file") names.push(entry.name);
    for (var i = 0; i < names.length; i++) await dir.removeEntry(names[i]);
  }

  // Send to the developer for a Kindle without Wi-Fi: what the Kindle saved in
  // reports/ (Diagnostics → Send to the developer, gzreader_usbreport.lua) goes
  // at the sync; the Diagnostics box on the Sync tab sends the Kindle's logs
  // as they are now, with what's typed there. Both go to the developer's
  // report feed in the same parts, names and tags as a Wi-Fi Kindle's
  // (gzreader_remote.lua R.sendLogs).
  var Report = {
    FEED: "https://in.wxcyber.com/open/feed/cmw7f51fm0e318o2f94o54020", // (R.REPORT_FEED: older GZreader didn't say)
    PART: 60 * 1024, MAX_PARTS: 8,
    SECRET_KEYS: ["password", "accessToken", "refreshToken", "access_token", "refresh_token", "code", "code_verifier",
      "state", "nonce", "token", "id_token", "passwordMD5"],
    feed: function (out) {
      var f = out && out.report && out.report.feed;
      if (typeof f === "string" && (/^https:\/\/[^\s]+$/.test(f) || /^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?\//.test(f))) return f.replace(/\/+$/, "");
      return Report.FEED;
    },
    // (Log.redact: passwords and tokens out of what's typed and crash.log)
    redact: function (s) {
      s = String(s == null ? "" : s);
      s = s.replace(/([Bb]earer\s+)[\w\-.~+\/=]+/g, "$1<redacted>").replace(/(\/pair\/)[0-9a-fA-F]+/g, "$1<token>");
      if (s.indexOf("=") < 0 && s.indexOf('"') < 0) return s;
      Report.SECRET_KEYS.forEach(function (k) {
        s = s.replace(new RegExp("([?&]" + k + "=)[^&\\s\"]*", "g"), "$1<redacted>")
          .replace(new RegExp("^(" + k + "=)[^&\\s\"]*", "gm"), "$1<redacted>")
          .replace(new RegExp("(\"" + k + "\"\\s*:\\s*\")[^\"]*", "g"), "$1<redacted>");
      });
      return s;
    },
    // the newest MAX_PARTS × PART bytes, in PART-byte pieces (never inside a character)
    parts: function (text) {
      var bytes = new TextEncoder().encode(text), total = bytes.length;
      function lead(i) { while (i < total && (bytes[i] & 0xC0) === 0x80) i++; return i; }
      var first = lead(Math.max(0, total - Report.PART * Report.MAX_PARTS)), out = [], dec = new TextDecoder();
      for (var i = first; i < total;) {
        var j = lead(Math.min(total, i + Report.PART));
        out.push(dec.decode(bytes.subarray(i, j)));
        i = j;
      }
      return { parts: out, first: first, total: total };
    },
    stamp: function (t) {
      var d = new Date(t), p = function (n) { return (n < 10 ? "0" : "") + n; };
      return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) + " " + p(d.getHours()) + ":" + p(d.getMinutes());
    },
    // r: { text, note, device, version, test_build, when, how }; throws when the feed can't be reached
    send: async function (out, r) {
      var cut = Report.parts(r.text || "");
      if (!cut.parts.length) throw new Error("the log is empty");
      var note = Report.redact(r.note || "").trim();
      var head = "GZreader " + (r.version || "?") + " on " + r.device + ", " + r.when + ". " + r.how + " "
        + (cut.first > 0 ? "The last " + Math.floor((cut.total - cut.first) / 1024) + " KB of " + Math.floor(cut.total / 1024) + " KB of the log." : "")
        + "\n\nWhat happened: " + (note || "(nothing typed)");
      var summary = note.replace(/\s+/g, " ");
      if (summary.length > 80) summary = (summary.slice(0, 79).match(/^(.*) /) || [null, summary.slice(0, 79)])[1] + "…";
      var url = Report.feed(out) + "/send";
      for (var k = 0; k < cut.parts.length; k++) {
        var tags = ["gzreader", r.device, "debug-log", r.test_build ? "test-build" : "release", "sync-page"];
        if (note) tags.push("with-comment");
        var res;
        try {
          res = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({
            eventName: "Debug report from " + r.device + " (" + (k + 1) + "/" + cut.parts.length + ")" + (k === 0 && summary ? ": " + summary : ""),
            eventContent: (k === 0 ? head + "\n\n" : "") + cut.parts[k],
            tags: tags, source: "gzreader", important: false,
          }) });
        } catch (e) { throw new Error("the developer's feed couldn't be reached"); }
        if (res.status >= 400) throw new Error("the developer's feed answered " + res.status);
      }
      return cut.parts.length;
    },
    info: function (out) {
      var o = out || {}, rep = o.report || {};
      return { device: rep.device || ((o.kindle || {}).model || "Kindle").replace(/\s/g, ""), version: o.gzreader,
        test_build: rep.test_build === true || /^\d[\d.]*\d.+$/.test(o.gzreader || "") };
    },
    // the reports the Kindle saved, oldest first: [{ stamp, meta }]
    saved: async function () {
      var dir = Drive.sync && await Drive.tryDir(Drive.sync, "reports"), out = [];
      if (!dir) return out;
      for await (var entry of dir.values()) {
        var m = entry.kind === "file" && /^report-([\d-]+)\.json$/.exec(entry.name);
        if (m) out.push({ stamp: m[1], meta: await Drive.readJSON(dir, entry.name) || {} });
      }
      out.sort(function (a, b) { return a.stamp < b.stamp ? -1 : a.stamp > b.stamp ? 1 : 0; });
      return out;
    },
    // at the sync: each saved report sent, then deleted (kept for the next sync when it can't be sent)
    sendSaved: async function (out) {
      var list = await Report.saved(), sent = 0;
      if (!list.length) return 0;
      var dir = await Drive.dir(Drive.sync, "reports"), base = Report.info(out);
      for (var i = 0; i < list.length; i++) {
        var meta = list[i].meta, name = "report-" + list[i].stamp;
        var text = await Drive.readText(dir, name + ".txt");
        if (text == null) { await Drive.remove(dir, name + ".json"); continue; } // (half a report: nothing to send)
        try {
          await Report.send(out, { text: text, note: meta.note, device: meta.device || base.device, version: meta.version || base.version,
            test_build: meta.test_build != null ? meta.test_build === true : base.test_build,
            when: meta.at ? Report.stamp(meta.at * 1000) + " (the Kindle's clock)" : "?",
            how: "Saved on the Kindle, sent from the sync page " + Report.stamp(Date.now()) + "." });
        } catch (e) {
          log("The Kindle's report for the developer couldn't be sent (" + e.message + "): it waits for the next sync.");
          return sent;
        }
        await Drive.remove(dir, name + ".json");
        await Drive.remove(dir, name + ".txt");
        sent++;
      }
      if (sent) log("Sent to the developer: " + sent + " report" + (sent === 1 ? "" : "s") + " from the Kindle's Diagnostics. Thank you!", "ok");
      return sent;
    },
    // the Diagnostics box: the log GZreader exported when Sync was pressed
    // (reports/latest.txt: diagnostic logging on), else the Kindle's log files
    // as they are on its drive (put together as Log.exportTo does)
    readLogs: async function () {
      var fresh = Drive.sync && await Drive.readText(Drive.sync, "reports/latest.txt");
      if (fresh != null && fresh !== "") return { text: fresh, exported: true };
      var ko = Drive.root && await Drive.tryDir(Drive.root, "koreader");
      if (!ko) return null;
      var a = await Drive.readText(ko, "gzreader.log.1"), b = await Drive.readText(ko, "gzreader.log");
      var crash = await Drive.readText(ko, "crash.log");
      if (a == null && b == null && crash == null) return null;
      var text = "Grimmory plugin log, read from the Kindle's drive by the sync page " + Report.stamp(Date.now()) + "\n\n" + (a || "") + (b || "");
      if (crash != null) text += "\n\n===== tail of KOReader crash.log =====\n" + Report.redact(crash.slice(-64 * 1024));
      return { text: text, exported: false };
    },
    sendNow: async function (out, note) {
      var sent = await Report.sendSaved(out);
      var logs = await Report.readLogs();
      if (logs == null) throw new Error("No GZreader logs on this drive (koreader/gzreader.log)");
      var info = Report.info(out);
      var n = await Report.send(out, { text: logs.text, note: note, device: info.device, version: info.version, test_build: info.test_build,
        when: (logs.exported ? "log exported when Sync was pressed, sent " : "log files read ") + Report.stamp(Date.now()),
        how: "Sent from the sync page (the Kindle has no Wi-Fi)." });
      if (logs.exported) await Drive.remove(Drive.sync, "reports/latest.txt"); // (sent: not sent twice)
      return { parts: n, saved: sent, exported: logs.exported };
    },
    render: async function () {
      var list = Drive.sync ? await Report.saved() : [];
      $("#rep-status").textContent = list.length
        ? list.length + " report" + (list.length === 1 ? "" : "s") + " saved on the Kindle (Diagnostics → Send to the developer): sent with the next sync, or with the button below."
        : "On the Kindle: Diagnostics → Send to the developer saves a report, sent at the next sync. Or describe the problem here and send the Kindle's logs now.";
    },
  };

  // Grimmory's reading stats for the Kindle's Home widget (as GZreader asks
  // for them: gzreader_grimstats.lua), after this sync's reading sessions
  function isoWeekOfYear(d) {
    // (Grimmory's WeekFields.ISO.weekOfYear(): Monday first, week 1 has at least 4 days; before it: 0)
    var jan1 = new Date(d.getFullYear(), 0, 1, 12);
    var jan1Wday = (jan1.getDay() + 6) % 7 + 1;
    var yday = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate(), 12) - jan1) / 86400000) + 1;
    var days = (yday - 1) + (jan1Wday - 1);
    return Math.floor(days / 7) + (jan1Wday <= 4 ? 1 : 0);
  }
  async function readingStats(inbox, now) {
    now = now || new Date();
    function sum(list, key) {
      return (Array.isArray(list) ? list : []).reduce(function (a, r) { return a + (Number(r && r[key]) || 0); }, 0);
    }
    var base = "/api/v1/user-stats/reading/";
    var at = Math.floor(now.getTime() / 1000);
    var r = await G.fetch(base + "streak");
    if (!r.ok) {
      inbox.grimmory_stats = { at: at, error: r.status === 403 ? "permission" : "http_" + r.status };
      if (r.status === 403) log("Reading stats: this Grimmory user may not see reading statistics (Grimmory: user settings → permissions).");
      return;
    }
    var streak = await r.json();
    var v = { streak: streak.currentStreak, longest_streak: streak.longestStreak, reading_days: streak.totalReadingDays };
    async function get(path) { try { var x = await G.fetch(base + path); return x.ok ? await x.json() : null; } catch (e) { return null; } }
    var y = now.getFullYear();
    var tl = await get("timeline?year=" + y + "&week=" + isoWeekOfYear(now));
    if (Array.isArray(tl)) { v.week_time = sum(tl, "totalDurationSeconds"); v.week_books = tl.length; }
    var heat = await get("heatmap/monthly?year=" + y + "&month=" + (now.getMonth() + 1));
    if (Array.isArray(heat)) v.month_sessions = sum(heat, "count");
    var done = await get("completion-timeline?year=" + y);
    if (Array.isArray(done)) v.year_finished = sum(done, "finishedBooks");
    inbox.grimmory_stats = { at: at, values: v };
    log("Reading stats for the Kindle's Home: " + (v.streak || 0) + "-day streak.", "ok");
  }

  async function runSync() {
    $("#sync").disabled = true;
    $("#done").classList.add("hidden");
    $("#log").textContent = "";
    Opt.covers = $("#o-covers").checked; Opt.details = $("#o-details").checked;
    Opt.slim = !$("#o-slim") || $("#o-slim").checked;
    var t0 = Date.now();
    try {
      // (asked first, while the button press still counts: the .ics files)
      for (var i = 0; i < Cal.list.length; i++) {
        if (Cal.list[i].type === "file") { var h = await idb.get("calfile:" + Cal.list[i].id); if (h) await permitted(h, "read"); }
      }
      if (!(await permitted(K.handle, "readwrite"))) throw new Error("The browser wasn't allowed to write to the Kindle.");
      K.out = fixOutbox(await Drive.readJSON(Drive.sync, "outbox.json") || {});
      var inbox = newInbox(await Drive.readJSON(Drive.sync, "inbox.json"));
      var out = K.out;
      if (G.connected()) {
        try {
          if (!G.st.user) { G.st.user = await G.me(); G.save(); }
          await sendJobs(out, inbox);
          try { await readingStats(inbox); } catch (e) { log("Reading stats: " + e.message, "bad"); }
          await libraryCopy(out, inbox);
          await saveInbox(inbox);
          await bringQueue(out, inbox);
        } catch (e) { log("Grimmory: " + e.message, "bad"); }
        setBookPicks(bookPicks().filter(function (p) { return !inInbox(inbox, p.id); }));
      } else if ((out.jobs || []).length || (out.queue || []).length) {
        log("Not signed in to Grimmory: reading updates and the sync queue wait for the next sync.", "bad");
      }
      if (M.connected()) { try { await syncNotes(out, inbox); } catch (e) { log("Notes: " + e.message, "bad"); } }
      if (Cal.list.length) { try { await syncCalendars(out, inbox); } catch (e) { log("Calendars: " + e.message, "bad"); } }
      if (P.connected() && ((out.kindle || {}).audio !== false) && picks().length) {
        try { await syncMusic(out, inbox); } catch (e) { log("Music: " + e.message, "bad"); }
      }
      setPicks(picks().filter(function (p) {
        return !inbox.music.some(function (m) { return m.kind === p.kind && String(m.key) === String(p.key); });
      }));
      Picks.prune(out);
      try { await dropUsage(); } catch (e) {}
      try { await Report.sendSaved(out); } catch (e) { log("Reports for the developer: " + e.message); }
      if (Sleep.count()) { try { await Sleep.bring(inbox); } catch (e) { log("Sleep screen pictures: " + e.message, "bad"); } }
      // (test builds on or off: the Kindle remembers it, Settings → Updates)
      if (out.gzreader && Update.betaTouched) inbox.test_builds = Update.beta;
      if (P.q) inbox.music_quality = { bitrate: P.q.bitrate, shrink: P.q.shrink }; // (the Kindle's Plex settings follow)
      if (Update.chosen && Update.latest) { try { await Update.bring(out, inbox); } catch (e) { log("Update: " + e.message, "bad"); } }
      await saveInbox(inbox);
      await Vault.chain; // (a renewed sign-in token: on the Kindle before it's unplugged)
      phase("");
      bar.hide();
      var secs = Math.round((Date.now() - t0) / 1000);
      var dn = $("#done");
      dn.textContent = "Done in " + (secs >= 90 ? Math.round(secs / 60) + " min" : secs + " s") + ". Eject the Kindle, unplug it and start GZreader: it takes in what was brought.";
      dn.classList.remove("hidden");
      K.pending = inbox;
      showKindle(K.out);
      renderPicks();
      Sleep.render();
      $("#b-results").textContent = "";
      measure();
      Report.render();
    } catch (e) {
      phase("");
      bar.hide();
      log(e.message || String(e), "bad");
    }
    updateSyncButton();
  }

  // ------------------------------------------------------------ the page

  function updateSyncButton() {
    $("#sync").disabled = !Drive.sync || !(G.connected() || M.connected() || Cal.list.length || P.connected() || Sleep.count());
  }

  function renderConnections() {
    var g = G.connected();
    $("#c-grimmory").classList.toggle("on", g);
    $("#g-status").textContent = g ? "Signed in to " + hostOf(G.st.server) + (G.st.user ? " as " + G.st.user : "") : "Not connected";
    $("#g-form").classList.toggle("hidden", g);
    $("#g-on").classList.toggle("hidden", !g);
    if (!g && G.st && G.st.server) $("#g-server").value = G.st.server;
    var m = M.connected();
    $("#c-memos").classList.toggle("on", m);
    $("#m-status").textContent = m ? "Connected to " + hostOf(M.st.server) + (M.st.user ? " as " + M.st.user : "") : "Not connected";
    $("#m-form").classList.toggle("hidden", m);
    $("#m-on").classList.toggle("hidden", !m);
    var c = Cal.list.length;
    $("#c-cal").classList.toggle("on", c > 0);
    $("#cal-status").textContent = c ? c + " calendar" + (c === 1 ? "" : "s") : "None yet";
    var ul = $("#cal-list");
    ul.textContent = "";
    Cal.list.forEach(function (src) {
      var li = el("li");
      li.appendChild(el("span", null, (src.name || (src.type === "file" ? "calendar file" : hostOf(src.url))) + "  "));
      li.lastChild.appendChild(el("span", { class: "small muted" }, src.type === "file" ? ".ics file" : src.type === "caldav" ? "CalDAV" : "link"));
      var b = el("button", null, "Remove");
      b.onclick = function () {
        Cal.list = Cal.list.filter(function (x) { return x !== src; });
        Cal.save(); idb.del("calfile:" + src.id); renderConnections();
      };
      li.appendChild(b);
      ul.appendChild(li);
    });
    var p = P.connected();
    $("#c-plex").classList.toggle("on", p);
    $("#p-status").textContent = p ? "Signed in" + (P.st.user ? " as " + P.st.user : "") + " · " + (P.st.server.name || "Plex") : "Not connected";
    $("#p-form").classList.toggle("hidden", p);
    $("#p-on").classList.toggle("hidden", !p);
    P.renderQuality();
    renderPicks();
    $("#b-results").textContent = ""; // (the Content tab loads again with the new connections)
    updateSyncButton();
  }

  // ------------------------------------------------------------ choosing what to bring

  function bookPicks() { return Picks.d.books; }
  function setBookPicks(l) { Picks.d.books = l; Picks.save(); }

  // where a book or album stands: on the Kindle, queued there, brought, chosen here
  function standing(kind, id) {
    var out = K.out || {}, have = out.have || {}, inbox = K.pending || {};
    id = String(id);
    if (kind === "audiobook") { // (a Plex audiobook, its album's key: plex-<key> on the Kindle)
      if ((have.audiobooks || []).some(function (a) { return String(a) === "plex-" + id; })) return "here";
      if ((inbox.audiobooks || []).some(function (b) { return String(b.id) === "plex-" + id; })) return "brought";
      return picks().some(function (y) { return y.kind === "audiobook" && String(y.key) === id; }) ? "chosen" : "";
    }
    if (kind === "album" || kind === "playlist") {
      if ((have.music || []).some(function (m) { return m === kind + "-" + id || m === safe(kind) + "-" + safe(id); })) return "here";
      if ((inbox.music || []).some(function (m) { return m.kind === kind && String(m.key) === id; })) return "brought";
      return picks().some(function (y) { return y.kind === kind && String(y.key) === id; }) ? "chosen" : "";
    }
    if ((have.books || {})[id] || (have.audiobooks || []).some(function (a) { return String(a) === id; })) return "here";
    if ((inbox.books || []).concat(inbox.audiobooks || []).some(function (b) { return String(b.id) === id; })) return "brought";
    if ((out.queue || []).some(function (q) { return String(q.id) === id; })) return "queued";
    return bookPicks().some(function (b) { return String(b.id) === id; }) ? "chosen" : "";
  }
  var STANDING = { here: "On the Kindle", brought: "Brought", queued: "In its queue", chosen: "Added ✓" };

  // The Content tab, as the Grimmory tab on the Kindle: Recently added, A–Z,
  // Libraries, Shelves, Authors, Series, a search; Plex's albums, playlists.
  // Each list is a view; opening one from another (a library's books) can go back.
  var Browse = {
    tab: "books", cat: null, stack: [], more: null,
    clear: function () { $("#b-results").textContent = ""; show("#b-more", false); Browse.more = null; },
    note: function (text) { Browse.clear(); $("#b-results").appendChild(el("li", { class: "small muted" }, text)); },
    CATS: {
      books: [["recent", "Recently added"], ["az", "A–Z"], ["libraries", "Libraries"], ["shelves", "Shelves"], ["authors", "Authors"], ["series", "Series"]],
      audio: [["recent", "Recently added"], ["az", "A–Z"], ["libraries", "Libraries"], ["authors", "Authors"], ["series", "Series"]],
      music: [["albums", "Albums A–Z"], ["playlists", "Playlists"]],
    },
    setTab: function (tab) {
      Browse.tab = tab;
      document.querySelectorAll(".tabs button").forEach(function (b) { b.classList.toggle("on", b.dataset.tab === tab); });
      $("#b-search").value = "";
      $("#b-search").placeholder = tab === "music" ? "Search albums and playlists" : tab === "audio" ? "Search audiobooks" : "Search books";
      var cats = $("#b-cats");
      cats.textContent = "";
      Browse.cats(tab).forEach(function (c) {
        var b = el("button", { "data-cat": c[0] }, c[1]);
        b.onclick = function () { Browse.open(c[0]); };
        cats.appendChild(b);
      });
      Browse.open(Browse.cats(tab)[0][0]);
    },
    // Audiobooks from a Plex library: the one the Kindle takes them from
    // (Settings → Connections → Plex → Audiobooks), or one picked here
    // ("Audiobooks from…"); audioSrc "grimmory": Grimmory's.
    audioSrc: null,
    plexAudio: function () {
      if (!P.connected() || Browse.audioSrc === "grimmory") return null;
      if (Browse.audioSrc) return Browse.audioSrc;
      var a = (K.out || {}).audiobook_library;
      return a && a.key != null ? a : null;
    },
    PLEX_AUDIO_CATS: [["precent", "Recently added"], ["paz", "A–Z"], ["pauthors", "Authors"]],
    cats: function (tab) {
      if (tab !== "audio") return Browse.CATS[tab];
      var list = (Browse.plexAudio() ? Browse.PLEX_AUDIO_CATS : Browse.CATS.audio).slice();
      if (P.connected()) list.push(["source", "Audiobooks from…"]);
      return list;
    },
    ready: function () {
      if (Browse.tab !== "books" && (((K.out || {}).kindle) || {}).audio === false) { Browse.note("This Kindle has no speaker or headphone jack."); return false; }
      if (Browse.tab === "audio" && (Browse.cat === "source" || Browse.plexAudio())) return true;
      if (Browse.tab === "music" && !P.connected()) { Browse.note("Sign in with Plex (Connections) to choose music."); return false; }
      if (Browse.tab !== "music" && !G.connected()) { Browse.note("Sign in to Grimmory (Connections) to choose books."); return false; }
      return true;
    },
    show: function () { Browse.setTab(Browse.tab); },
    // a category: the start of a new trail
    open: function (cat) {
      Browse.cat = cat;
      document.querySelectorAll("#b-cats button").forEach(function (b) { b.classList.toggle("on", b.dataset.cat === cat); });
      Browse.stack = [];
      if (!Browse.ready()) return;
      var label = (Browse.cats(Browse.tab).filter(function (c) { return c[0] === cat; })[0] || [, ""])[1];
      Browse.push(label, Browse.loader(cat));
    },
    loader: function (cat) {
      var audio = Browse.tab === "audio";
      if (cat === "recent") return function (p) { return Browse.books({ sort: "addedOn", dir: "desc" }, p); };
      if (cat === "az") return function (p) { return Browse.books({ sort: "title", dir: "asc" }, p); };
      if (cat === "libraries") return Browse.libraries;
      if (cat === "shelves") return Browse.shelves;
      if (cat === "authors") return function (p) { return Browse.named("/api/v1/app/authors", "authors", p); };
      if (cat === "series") return function (p) { return Browse.named("/api/v1/app/series", "series", p); };
      if (cat === "precent") return function (p) { return Browse.plexAudiobooks({ type: 9, sort: "addedAt:desc" }, p); };
      if (cat === "paz") return function (p) { return Browse.plexAudiobooks({ type: 9, sort: "titleSort:asc" }, p); };
      if (cat === "pauthors") return Browse.plexAuthors;
      if (cat === "source") return Browse.audioSources;
      if (cat === "albums") return Browse.albums;
      if (cat === "playlists") return Browse.playlists;
      return function () { Browse.note(audio ? "" : ""); };
    },
    push: function (title, load) {
      Browse.stack.push({ title: title, load: load });
      Browse.run();
    },
    back: function () { Browse.stack.pop(); Browse.run(); },
    run: function () {
      var view = Browse.stack[Browse.stack.length - 1];
      var crumbs = $("#b-crumbs");
      crumbs.textContent = "";
      if (!view) return;
      if (Browse.stack.length > 1) {
        var b = el("button", null, "← " + Browse.stack[Browse.stack.length - 2].title);
        b.onclick = Browse.back;
        crumbs.appendChild(b);
      }
      crumbs.appendChild(el("strong", null, view.title));
      Browse.note("Loading…");
      Promise.resolve(view.load(0)).catch(function (e) { Browse.note(e.message || String(e)); });
    },
    pageMore: function (fn) { Browse.more = fn; show("#b-more", !!fn); },
    // books (and audiobooks): a page of Grimmory's list with these filters
    books: async function (params, page) {
      var audio = Browse.tab === "audio";
      var d = await G.json("/api/v1/app/books" + qs(Object.assign({ page: page, size: 30, fileType: audio ? ["AUDIOBOOK"] : READABLE }, params)));
      if (page === 0) Browse.clear();
      var list = (d.content || []).filter(function (b) {
        var t = String(b.primaryFileType || "").toUpperCase();
        return !b.isPhysical && (audio ? t === "AUDIOBOOK" : t && t !== "AUDIOBOOK");
      });
      if (params.search) {
        // (older Grimmory ignores search=: only what matches)
        var ql = String(params.search).toLowerCase();
        list = list.filter(function (b) {
          return [b.title, (b.authors || []).join(" "), b.seriesName].join(" ").toLowerCase().indexOf(ql) >= 0;
        });
      }
      if (page === 0 && !list.length) Browse.note("Nothing here.");
      var token = await G.token().catch(function () { return null; });
      list.forEach(function (b) { Browse.bookItem(b, token); });
      var pages = Number(d.totalPages) || 1;
      Browse.pageMore(page + 1 < pages ? function () { return Browse.books(params, page + 1); } : null);
    },
    navItem: function (title, meta, count, onOpen) {
      var li = el("li", { class: "nav", tabindex: "0", role: "button" });
      var txt = el("span", { class: "txt" }, title);
      if (meta) txt.appendChild(el("span", { class: "meta" }, meta));
      li.appendChild(txt);
      if (count != null) li.appendChild(el("span", { class: "count" }, String(count)));
      li.onclick = onOpen;
      li.onkeydown = function (e) { if (e.key === "Enter") onOpen(); };
      $("#b-results").appendChild(li);
    },
    libraries: async function () {
      var libs;
      try { libs = await G.json("/api/v1/app/libraries"); } catch (e) { libs = await G.json("/api/v1/libraries"); }
      Browse.clear();
      (libs || []).forEach(function (l) {
        Browse.navItem(l.name || "Library", null, l.bookCount, function () {
          Browse.push(l.name || "Library", function (p) { return Browse.books({ libraryId: l.id, sort: "title", dir: "asc" }, p); });
        });
      });
      if (!(libs || []).length) Browse.note("No libraries.");
    },
    shelves: async function () {
      var list = (await G.json("/api/v1/app/shelves")) || [];
      try { (await G.json("/api/v1/app/shelves/magic") || []).forEach(function (s) { s.magic = true; list.push(s); }); } catch (e) {}
      Browse.clear();
      list.forEach(function (sh) {
        Browse.navItem(sh.name || "Shelf", sh.magic ? "magic shelf" : null, sh.bookCount, function () {
          Browse.push(sh.name || "Shelf", function (p) {
            return Browse.books(sh.magic ? { magicShelfId: sh.id, sort: "title", dir: "asc" } : { shelfId: sh.id, sort: "title", dir: "asc" }, p);
          });
        });
      });
      if (!list.length) Browse.note("No shelves.");
    },
    // authors and series: a page of names, each opening its books
    named: async function (path, kind, page) {
      var d = await G.json(path + qs({ page: page, size: 50, sort: "name", dir: "asc" }));
      if (page === 0) Browse.clear();
      var items = d.content || (Array.isArray(d) ? d : []);
      items.forEach(function (x) {
        var name = kind === "series" ? (x.seriesName || x.name) : x.name;
        if (!name) return;
        var meta = kind === "series" && Array.isArray(x.authors) && x.authors.length ? x.authors.join(", ") : null;
        Browse.navItem(name, meta, x.bookCount, function () {
          Browse.push(name, function (p) {
            return Browse.books(kind === "series" ? { series: name, sort: "seriesNumber", dir: "asc" } : { authors: name, sort: "title", dir: "asc" }, p);
          });
        });
      });
      if (page === 0 && !items.length) Browse.note("Nothing here.");
      var pages = Number(d.totalPages) || 1;
      Browse.pageMore(page + 1 < pages ? function () { return Browse.named(path, kind, page + 1); } : null);
    },
    bookItem: function (b, token) {
      var audio = String(b.primaryFileType || "").toUpperCase() === "AUDIOBOOK";
      var li = el("li", audio ? { class: "square" } : null);
      if (token) {
        // (Grimmory's covers can be shown, not read, by a web page: an <img> with the sign-in in its address)
        var img = el("img", { alt: "", loading: "lazy", referrerpolicy: "no-referrer",
          src: G.st.server + "/api/v1/media/book/" + b.id + (audio ? "/audiobook-thumbnail" : "/thumbnail") + "?token=" + encodeURIComponent(token) });
        img.onerror = function () { img.replaceWith(el("span", { class: "ph" })); };
        li.appendChild(img);
      } else li.appendChild(el("span", { class: "ph" }));
      var txt = el("span", { class: "txt" }, b.title || "?");
      var meta = [(b.authors || []).join(", "), audio ? "audiobook" : b.primaryFileType,
        b.fileSizeKb ? mb(b.fileSizeKb * 1024) : null, b.seriesName ? b.seriesName + (b.seriesNumber ? " #" + b.seriesNumber : "") : null];
      txt.appendChild(el("span", { class: "meta" }, meta.filter(Boolean).join(" · ")));
      li.appendChild(txt);
      li.appendChild(Browse.button("book", b.id, function (on) {
        var l = bookPicks().filter(function (x) { return String(x.id) !== String(b.id); });
        if (on) l.push({ id: b.id, kind: audio ? "audiobook" : "book", title: b.title, authors: b.authors, format: b.primaryFileType,
          file_id: b.primaryFileId, name: String(b.primaryFileName || "").split(/[\/\\]/).pop() || undefined, size_kb: b.fileSizeKb });
        setBookPicks(l);
      }));
      $("#b-results").appendChild(li);
    },
    button: function (kind, id, onToggle) {
      var st = standing(kind, id);
      var b = el("button", null, STANDING[st] || "Add");
      b.disabled = st === "here" || st === "brought" || st === "queued";
      b.onclick = function () {
        var on = standing(kind, id) !== "chosen";
        onToggle(on);
        b.textContent = on ? STANDING.chosen : "Add";
        renderPicks();
      };
      return b;
    },
    search: async function () {
      var q = $("#b-search").value.trim();
      if (!q) return Browse.open(Browse.cats(Browse.tab)[0][0]);
      document.querySelectorAll("#b-cats button").forEach(function (b) { b.classList.remove("on"); });
      Browse.stack = [];
      Browse.cat = null;
      if (!Browse.ready()) return;
      var lib = Browse.tab === "audio" && Browse.plexAudio();
      if (lib) {
        return Browse.push("“" + q + "”", async function () {
          var d = await (await P.get("/hubs/search", { query: q, sectionId: lib.key, limit: 30 })).json();
          var found = [];
          ((d.MediaContainer || {}).Hub || []).forEach(function (hub) {
            if (hub.type === "album") (hub.Metadata || []).forEach(function (m) { var it = P.item(m); if (it && it.key) found.push(it); });
          });
          Browse.clear();
          if (!found.length) Browse.note("Nothing found.");
          Browse.plexAudioItems(found);
        });
      }
      if (Browse.tab === "music") {
        return Browse.push("“" + q + "”", async function () {
          var d = await (await P.get("/hubs/search", { query: q, limit: 30 })).json();
          var found = [];
          ((d.MediaContainer || {}).Hub || []).forEach(function (hub) {
            if (hub.type === "album" || hub.type === "playlist") (hub.Metadata || []).forEach(function (m) { var it = P.item(m); if (it && it.key) found.push(it); });
          });
          Browse.clear();
          if (!found.length) Browse.note("Nothing found.");
          Browse.musicItems(found);
        });
      }
      Browse.push("“" + q + "”", function (p) { return Browse.books({ search: q, sort: "title", dir: "asc" }, p); });
    },
    albums: async function (start) {
      start = start || 0;
      var music = [];
      var d = await (await P.get("/library/sections")).json();
      ((d.MediaContainer || {}).Directory || []).forEach(function (x) { if (x.type === "artist") music.push(x); });
      if (!music.length) return Browse.note("No music library on this Plex server.");
      // (the music library chosen on the Kindle, if this server has it: same key and name; else the first)
      var want = (K.out || {}).music_library, lib = music[0];
      if (want) music.forEach(function (x) { if (String(x.key) === String(want.key) && x.title === want.title) lib = x; });
      var items = await P.items("/library/sections/" + encodeURIComponent(lib.key) + "/all", { type: 9, sort: "titleSort:asc" },
        { "X-Plex-Container-Start": String(start), "X-Plex-Container-Size": "50" });
      if (start === 0) Browse.clear();
      items.forEach(function (x) { x.type = "album"; });
      Browse.musicItems(items);
      Browse.pageMore(items.length === 50 ? function () { return Browse.albums(start + 50); } : null);
    },
    playlists: async function () {
      var items = await P.items("/playlists", { playlistType: "audio" });
      Browse.clear();
      items.forEach(function (x) { x.type = "playlist"; });
      if (!items.length) return Browse.note("No playlists.");
      Browse.musicItems(items);
    },
    // a page of the Plex audiobook library's albums
    plexAudiobooks: async function (params, start) {
      start = start || 0;
      var lib = Browse.plexAudio();
      var items = await P.items("/library/sections/" + encodeURIComponent(lib.key) + "/all", params,
        { "X-Plex-Container-Start": String(start), "X-Plex-Container-Size": "50" });
      if (start === 0) Browse.clear();
      if (start === 0 && !items.length) Browse.note("No audiobooks in “" + (lib.title || "this library") + "”.");
      Browse.plexAudioItems(items);
      Browse.pageMore(items.length === 50 ? function () { return Browse.plexAudiobooks(params, start + 50); } : null);
    },
    plexAuthors: async function (start) {
      start = start || 0;
      var lib = Browse.plexAudio();
      var items = await P.items("/library/sections/" + encodeURIComponent(lib.key) + "/all", { type: 8, sort: "titleSort:asc" },
        { "X-Plex-Container-Start": String(start), "X-Plex-Container-Size": "50" });
      if (start === 0) Browse.clear();
      items.forEach(function (a) {
        Browse.navItem(a.title, null, null, function () {
          Browse.push(a.title, async function () {
            var books = await P.items("/library/metadata/" + encodeURIComponent(a.key) + "/children");
            Browse.clear();
            Browse.plexAudioItems(books);
          });
        });
      });
      if (start === 0 && !items.length) Browse.note("Nothing here.");
      Browse.pageMore(items.length === 50 ? function () { return Browse.plexAuthors(start + 50); } : null);
    },
    // where audiobooks come from on this page: Grimmory or a Plex library
    audioSources: async function () {
      var cur = Browse.plexAudio();
      Browse.clear();
      var pick = function (src) { Browse.audioSrc = src; Browse.setTab("audio"); };
      if (G.connected()) Browse.navItem("Grimmory", cur ? null : "in use", null, function () { pick("grimmory"); });
      var d = await (await P.get("/library/sections")).json();
      ((d.MediaContainer || {}).Directory || []).forEach(function (x) {
        if (x.type !== "artist") return;
        var on = cur && String(cur.key) === String(x.key);
        Browse.navItem("Plex: " + x.title, on ? "in use" : null, null, function () { pick({ key: String(x.key), title: x.title }); });
      });
      $("#b-results").appendChild(el("li", { class: "small muted" },
        "On the Kindle: Settings → Connections → Plex → Audiobooks. Plex audiobooks come to the Kindle with the next sync, and play there like Grimmory's."));
    },
    plexAudioItems: function (items) {
      items.forEach(function (it) {
        if (it.type && it.type !== "album") return;
        var li = el("li", { class: "square" }), ph = el("span", { class: "ph" });
        li.appendChild(ph);
        var txt = el("span", { class: "txt" }, it.title);
        txt.appendChild(el("span", { class: "meta" }, [it.artist, "audiobook", it.year].filter(Boolean).join(" · ")));
        li.appendChild(txt);
        li.appendChild(Browse.button("audiobook", it.key, function (on) {
          var l = picks().filter(function (y) { return !(y.kind === "audiobook" && String(y.key) === String(it.key)); });
          if (on) l.push({ kind: "audiobook", key: it.key, title: it.title, artist: it.artist, year: it.year, thumb: it.thumb });
          setPicks(l);
        }));
        $("#b-results").appendChild(li);
        if (it.thumb) {
          P.get("/photo/:/transcode", { url: it.thumb, width: 96, height: 96, minSize: 1, format: "jpeg" }).then(function (r) { return r.blob(); })
            .then(function (blob) { if (ph.isConnected) ph.replaceWith(el("img", { src: URL.createObjectURL(blob), alt: "" })); })
            .catch(function () {});
        }
      });
    },
    musicItems: function (items) {
      items.forEach(function (it) {
        var kind = it.type === "playlist" ? "playlist" : "album";
        var li = el("li", { class: "square" });
        var ph = el("span", { class: "ph" });
        li.appendChild(ph);
        var txt = el("span", { class: "txt" }, it.title);
        txt.appendChild(el("span", { class: "meta" }, [it.artist, kind === "playlist" ? "playlist" : it.year, it.count ? it.count + " tracks" : null].filter(Boolean).join(" · ")));
        li.appendChild(txt);
        li.appendChild(Browse.button(kind, it.key, function (on) {
          var l = picks().filter(function (y) { return !(y.kind === kind && String(y.key) === String(it.key)); });
          if (on) l.push({ kind: kind, key: it.key, title: it.title, artist: it.artist, year: it.year, thumb: it.thumb });
          setPicks(l);
        }));
        $("#b-results").appendChild(li);
        if (it.thumb) {
          P.get("/photo/:/transcode", { url: it.thumb, width: 96, height: 96, minSize: 1, format: "jpeg" }).then(function (r) { return r.blob(); })
            .then(function (blob) { if (ph.isConnected) ph.replaceWith(el("img", { src: URL.createObjectURL(blob), alt: "" })); })
            .catch(function () {});
        }
      });
    },
  };

  // what comes with the next sync: the Kindle's queue, then what was chosen here
  function renderPicks() {
    var ul = $("#picks");
    if (!ul) return;
    ul.textContent = "";
    var rows = 0, bytes = 0;
    ((K.out || {}).queue || []).forEach(function (q) {
      if (standing("book", q.id) === "brought") return;
      var li = el("li");
      li.appendChild(el("span", null, (q.title || "?") + (q.authors && q.authors.length ? " — " + q.authors.join(", ") : "")));
      li.appendChild(el("span", { class: "small muted" }, "the Kindle's queue"));
      ul.appendChild(li); rows++; bytes += (Number(q.size_kb) || 0) * 1024;
    });
    var refresh = function () { renderPicks(); if (!$("#app").classList.contains("hidden")) Browse.run(); };
    var remove = function (fn) { var b = el("button", null, "Remove"); b.onclick = function () { fn(); refresh(); }; return b; };
    bookPicks().forEach(function (x) {
      if (standing("book", x.id) === "here") return; // (Picks.prune takes it off)
      var li = el("li");
      li.appendChild(el("span", null, (x.title || "?") + (x.authors && x.authors.length ? " — " + x.authors.join(", ") : "") + (x.kind === "audiobook" ? " (audiobook)" : "")));
      li.appendChild(remove(function () { setBookPicks(bookPicks().filter(function (y) { return String(y.id) !== String(x.id); })); }));
      ul.appendChild(li); rows++; bytes += (Number(x.size_kb) || 0) * 1024;
    });
    picks().forEach(function (x) {
      if (standing(x.kind, x.key) === "here") return;
      var li = el("li");
      li.appendChild(el("span", null, x.title + (x.artist ? " — " + x.artist : "") + " (" + x.kind + ")"));
      li.appendChild(remove(function () { setPicks(picks().filter(function (y) { return !(y.kind === x.kind && String(y.key) === String(x.key)); })); }));
      ul.appendChild(li); rows++;
    });
    $("#picks-size").textContent = bytes ? "· about " + mb(bytes) : "";
    if (!rows) ul.appendChild(el("li", { class: "small muted" }, "Nothing yet: choose above, or with Download in the Kindle's Catalog tab."));
  }

  // ------------------------------------------------------------ HEIC pictures

  // HEIC/HEIF (iPhone photos): only Safari opens them. Elsewhere libheif
  // (vendor/, LGPL 3.0, see vendor/README.md) decodes them, in a worker (it
  // compiles its WebAssembly at once, which a page may not do with a big one,
  // and a 12-megapixel photo takes a moment). Loaded only when one is added;
  // the picture never leaves the browser.
  var Heic = {
    LIB: "vendor/libheif-1.23.5.js",
    BRANDS: ["heic", "heix", "heim", "heis", "hevc", "hevx", "hevm", "hevs", "mif1", "msf1"],
    worker: null, n: 0, waits: {},
    // by its name, its type, or its first bytes ("ftyp" and a HEIF brand)
    is: async function (file) {
      if (/\.(heic|heif|hif)$/i.test(file.name || "") || /^image\/hei[cf]/i.test(file.type || "")) return true;
      try {
        var b = new Uint8Array(await file.slice(0, 12).arrayBuffer());
        var s = String.fromCharCode.apply(null, b);
        return s.slice(4, 8) === "ftyp" && Heic.BRANDS.indexOf(s.slice(8, 12)) >= 0;
      } catch (e) { return false; }
    },
    // the worker's code: libheif, then one picture at a time
    code: function () {
      var lib = null;
      onmessage = async function (e) {
        var id = e.data.id;
        try {
          if (!lib) {
            importScripts(e.data.lib);
            lib = libheif();
            if (lib && typeof lib.then === "function") lib = await lib;
          }
          var imgs = new lib.HeifDecoder().decode(new Uint8Array(e.data.buf));
          if (!imgs || !imgs.length) throw new Error("not a picture libheif can read");
          var im = imgs[0], w = im.get_width(), h = im.get_height();
          im.display({ data: new Uint8ClampedArray(w * h * 4), width: w, height: h }, function (d) {
            imgs.forEach(function (x) { try { x.free(); } catch (er) {} });
            if (!d) postMessage({ id: id, error: "libheif couldn't decode it" });
            else postMessage({ id: id, w: w, h: h, data: d.data.buffer }, [d.data.buffer]);
          });
        } catch (err) { postMessage({ id: id, error: String((err && err.message) || err) }); }
      };
    },
    start: function () {
      if (Heic.worker) return Heic.worker;
      var url = URL.createObjectURL(new Blob(["(" + Heic.code.toString() + ")();"], { type: "text/javascript" }));
      Heic.worker = new Worker(url);
      URL.revokeObjectURL(url);
      var fail = function (msg) {
        Object.keys(Heic.waits).forEach(function (k) { Heic.waits[k].bad(new Error(msg)); });
        Heic.waits = {};
        Heic.worker.terminate(); Heic.worker = null;
      };
      Heic.worker.onmessage = function (e) {
        var w = Heic.waits[e.data.id];
        if (!w) return;
        delete Heic.waits[e.data.id];
        if (e.data.error) w.bad(new Error(e.data.error)); else w.ok(e.data);
      };
      Heic.worker.onerror = function (e) { e.preventDefault(); fail("the HEIC converter didn't load (" + (e.message || "no connection?") + ")"); };
      return Heic.worker;
    },
    // a HEIC file → an ImageBitmap, like createImageBitmap(file)
    bitmap: async function (file) {
      var buf = await file.arrayBuffer();
      var worker = Heic.start(), id = ++Heic.n;
      var lib = new URL(Heic.LIB, location.href).href;
      var r = await new Promise(function (ok, bad) {
        Heic.waits[id] = { ok: ok, bad: bad };
        worker.postMessage({ id: id, lib: lib, buf: buf }, [buf]);
      });
      return await createImageBitmap(new ImageData(new Uint8ClampedArray(r.data), r.w, r.h));
    },
  };

  // ------------------------------------------------------------ sleep screen pictures

  // Pictures for the Kindle's sleep screen: made here for its screen (grey,
  // its size, filling it or whole), brought with the sync; GZreader moves
  // them into the drive's screensavers folder (gzreader_usbsync.lua).
  var Sleep = {
    pending: [], // { name, blob, url } (in this tab only)
    remove: {},  // names of the Kindle's pictures to take off
    mode: null,  // "auto" | "always" (null: as it is on the Kindle)
    screen: function () {
      var sc = ((K.out || {}).kindle || {}).screen;
      return sc && sc.w > 0 && sc.h > 0 ? { w: Math.round(sc.w), h: Math.round(sc.h) } : { w: 600, h: 800 };
    },
    onKindle: function () { return asList(((K.out || {}).screensavers || {}).names); },
    count: function () { return Sleep.pending.length + Object.keys(Sleep.remove).length + (Sleep.mode ? 1 : 0); },
    nameFor: function (file) {
      var base = String(file.name || "picture").replace(/\.[^.]*$/, "").replace(/[^A-Za-z0-9 _-]+/g, "-").replace(/^[-\s.]+|[-\s]+$/g, "").slice(0, 40) || "picture";
      var name = base + ".png", k = 2;
      var taken = function (n) { return Sleep.pending.some(function (p) { return p.name === n; }); };
      while (taken(name)) name = base + " (" + (k++) + ").png";
      return name;
    },
    // the picture as the Kindle's screen shows it: its size, in grey
    make: async function (file, fit) {
      var img;
      try { img = await createImageBitmap(file); }
      catch (e) {
        if (!(await Heic.is(file))) throw e;
        img = await Heic.bitmap(file); // (an iPhone photo, in a browser that can't open it)
      }
      var sc = Sleep.screen();
      var c = document.createElement("canvas");
      c.width = sc.w; c.height = sc.h;
      var g = c.getContext("2d");
      g.fillStyle = "#fff";
      g.fillRect(0, 0, sc.w, sc.h);
      var k = fit === "contain" ? Math.min(sc.w / img.width, sc.h / img.height) : Math.max(sc.w / img.width, sc.h / img.height);
      var w = img.width * k, h = img.height * k;
      g.imageSmoothingQuality = "high";
      g.drawImage(img, (sc.w - w) / 2, (sc.h - h) / 2, w, h);
      if (img.close) img.close();
      var d = g.getImageData(0, 0, sc.w, sc.h), px = d.data;
      for (var i = 0; i < px.length; i += 4) {
        var y = Math.round(0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2]);
        px[i] = px[i + 1] = px[i + 2] = y; px[i + 3] = 255;
      }
      g.putImageData(d, 0, 0);
      return await new Promise(function (ok, bad) { c.toBlob(function (b) { b ? ok(b) : bad(new Error("couldn't make the picture")); }, "image/png"); });
    },
    add: async function (files) {
      var fit = ($("#ss-fit") || {}).value || "cover", bad = 0, heicBad = [];
      var btn = $("#ss-add"), label = btn.textContent;
      btn.disabled = true;
      try {
        for (var i = 0; i < files.length; i++) {
          btn.textContent = files.length > 1 ? "Making " + (i + 1) + " of " + files.length + "…" : "Making the picture…";
          try {
            var blob = await Sleep.make(files[i], fit);
            Sleep.pending.push({ name: Sleep.nameFor(files[i]), blob: blob, url: URL.createObjectURL(blob) });
          } catch (e) {
            if (await Heic.is(files[i])) heicBad.push(e.message || String(e)); else bad++;
          }
        }
      } finally { btn.disabled = false; btn.textContent = label; }
      Sleep.render();
      var msg = [];
      if (bad) msg.push(bad + " picture" + (bad === 1 ? "" : "s") + " couldn't be read (this browser can't open that kind of file).");
      if (heicBad.length) msg.push(heicBad.length + " HEIC picture" + (heicBad.length === 1 ? "" : "s") + " couldn't be converted: " + heicBad[0] + ".");
      if (msg.length) alertIn(btn, msg.join(" "));
    },
    render: function () {
      var ul = $("#ss-list");
      if (!ul) return;
      ul.textContent = "";
      var sc = Sleep.screen();
      $("#ss-size").textContent = "· made " + sc.w + " × " + sc.h + " for this Kindle";
      var mode = Sleep.mode || ((K.out || {}).screensavers || {}).mode;
      document.querySelectorAll('input[name="ss-mode"]').forEach(function (r) { r.checked = r.value === mode; });
      Sleep.pending.forEach(function (p) {
        var li = el("li");
        var left = el("span", { class: "ss-row" });
        var im = el("img", { class: "ss-thumb", alt: "", src: p.url });
        left.appendChild(im);
        left.appendChild(el("span", null, p.name));
        li.appendChild(left);
        var b = el("button", null, "Remove");
        b.onclick = function () { URL.revokeObjectURL(p.url); Sleep.pending = Sleep.pending.filter(function (x) { return x !== p; }); Sleep.render(); };
        li.appendChild(b);
        ul.appendChild(li);
      });
      Sleep.onKindle().forEach(function (name) {
        var li = el("li");
        var off = !!Sleep.remove[name];
        li.appendChild(el("span", { class: off ? "muted ss-off" : "" }, name));
        var right = el("span", { class: "small muted" }, off ? "taken off with the sync " : "on the Kindle ");
        var b = el("button", null, off ? "Keep" : "Take off");
        b.onclick = function () { if (off) delete Sleep.remove[name]; else Sleep.remove[name] = true; Sleep.render(); };
        right.appendChild(b);
        li.appendChild(right);
        ul.appendChild(li);
      });
      if (!ul.children.length) ul.appendChild(el("li", { class: "small muted" }, "No pictures yet: add some, or the Kindle shows its own."));
      updateSyncButton();
    },
    // with the sync: the new pictures under in/, what to do with them in the inbox
    bring: async function (inbox) {
      var st = inbox.screensavers && typeof inbox.screensavers === "object" ? inbox.screensavers : {};
      st.add = asList(st.add); st.remove = asList(st.remove);
      var n = 0;
      for (var i = 0; i < Sleep.pending.length; i++) {
        var p = Sleep.pending[i];
        var file = "in/screensavers/" + Date.now() + "-" + i + ".png";
        await Drive.write(Drive.sync, file, p.blob);
        st.add.push({ file: file, name: p.name });
        n++;
      }
      Object.keys(Sleep.remove).forEach(function (name) { if (st.remove.indexOf(name) < 0) st.remove.push(name); });
      if (Sleep.mode) st.mode = Sleep.mode;
      inbox.screensavers = st;
      var off = Object.keys(Sleep.remove).length;
      Sleep.pending.forEach(function (p) { URL.revokeObjectURL(p.url); });
      Sleep.pending = []; Sleep.remove = {}; Sleep.mode = null;
      if (n || off) log("Sleep screen: " + (n ? n + " picture" + (n === 1 ? "" : "s") + " on the way" : "") + (n && off ? ", " : "") + (off ? off + " taken off" : "") + ".", "ok");
    },
  };

  function busy(btn, fn) {
    return async function () {
      btn.disabled = true;
      try { await fn(); } catch (e) { alertIn(btn, e.message || String(e)); }
      btn.disabled = false;
    };
  }
  function alertIn(btn, text) {
    var box = btn.closest(".conn") || btn.closest("section");
    var old = box.querySelector(".err");
    if (old) old.remove();
    var p = el("p", { class: "err small " + (/^Signed in/.test(text) ? "ok" : "bad") }, text);
    box.appendChild(p);
    setTimeout(function () { p.remove(); }, 12000);
  }

  // ------------------------------------------------------------ start

  async function start() {
    var params = new URLSearchParams(location.search);
    K.test = params.has("test");
    if (!window.showDirectoryPicker && !K.test && !window.GZSYNC_TEST) {
      show("#unsupported", true);
      $("#pick").disabled = true;
    }
    // back from single sign-on: finished once the Kindle is unlocked
    if (params.get("state") && (params.get("code") || params.get("error"))) {
      try { sessionStorage.setItem("gzsync.sso-return", location.search); } catch (e) {}
      history.replaceState(null, "", location.pathname + (K.test ? "?test" : ""));
      show("#sso-wait", true);
    }
    // sleep screen pictures
    $("#ss-add").onclick = function () { $("#ss-files").click(); };
    $("#ss-files").onchange = async function () { var f = Array.prototype.slice.call(this.files || []); this.value = ""; await Sleep.add(f); };
    document.querySelectorAll('input[name="ss-mode"]').forEach(function (r) {
      r.onchange = function () { if (r.checked) { Sleep.mode = r.value === ((K.out || {}).screensavers || {}).mode ? null : r.value; Sleep.render(); } };
    });
    // the gate: a Kindle
    $("#pick").onclick = async function () {
      try { await openDrive(await window.showDirectoryPicker({ id: "gzkindle", mode: "readwrite" })); }
      catch (e) { if (e.name !== "AbortError") problem(e.message); }
    };
    var last = !K.test && await idb.get("drive");
    if (last) {
      show("#reopen", true);
      $("#reopen").textContent = "Use “" + last.name + "” again";
      $("#reopen").onclick = async function () { await openDrive(last); };
    }
    // the PIN
    $("#unlock-form").onsubmit = async function (e) {
      e.preventDefault();
      var pin = $("#pin").value, err = $("#unlock-err");
      show("#unlock-err", false);
      $("#unlock-go").disabled = true;
      try {
        if (await Vault.exists()) await Vault.unlock(pin);
        else {
          if (pin.length < 4) throw new Error("At least 4 characters.");
          if (pin !== $("#pin2").value) throw new Error("The two PINs aren't the same.");
          // (sign-ins made in this tab without a PIN come along)
          if (Vault.mode !== "session") Vault.use(null);
          await Vault.create(pin);
        }
        await unlocked();
      } catch (x) { err.textContent = x.message; show("#unlock-err", true); }
      $("#unlock-go").disabled = false;
    };
    $("#unlock-skip").onclick = function () { Vault.session(); unlocked(); };
    $("#unlock-reset").onclick = async function () {
      if (!confirm("Start over? The connections kept on this Kindle are deleted; you connect again and choose a new PIN.")) return;
      await Vault.forget();
      await askPin();
    };
    $("#k-lock").onclick = function () { Vault.lock(); show("#app", false); askPin(); };
    $("#k-other").onclick = function () { Vault.lock(); Drive.sync = null; show("#app", false); show("#unlock", false); show("#gate", true); };
    document.querySelectorAll("nav.main button").forEach(function (b) { b.onclick = function () { setPanel(b.dataset.panel); }; });
    // connections
    $("#g-login").onclick = busy($("#g-login"), async function () {
      await G.login($("#g-server").value, $("#g-user").value.trim(), $("#g-pass").value);
      $("#g-pass").value = "";
      renderConnections();
    });
    $("#g-sso").onclick = busy($("#g-sso"), function () { return G.startSso($("#g-server").value); });
    $("#g-out").onclick = function () {
      if (G.st && G.st.refresh) fetch(G.st.server + "/api/v1/auth/logout", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ refreshToken: G.st.refresh }) }).catch(function () {});
      G.st = { server: G.st && G.st.server }; G.save(); renderConnections();
    };
    $("#m-connect").onclick = busy($("#m-connect"), async function () {
      await M.connect($("#m-server").value, $("#m-token").value);
      $("#m-token").value = "";
      renderConnections();
    });
    $("#m-out").onclick = function () { M.st = null; M.save(); renderConnections(); };
    $("#cal-add").onclick = busy($("#cal-add"), async function () {
      var url = $("#cal-url").value.trim();
      if (!/^(webcal|https?):\/\//i.test(url)) throw new Error("Enter a calendar link (webcal:// or https://).");
      if (mixedContent(url.replace(/^webcal:/i, "https:"))) throw new Error("A web page can only read calendars over https://.");
      var user = $("#cal-user").value.trim();
      Cal.list.push({ id: rand(4), type: user ? "caldav" : "link", name: $("#cal-name").value.trim() || null, url: url, user: user || null, pass: $("#cal-pass").value || null });
      Cal.save();
      $("#cal-url").value = ""; $("#cal-name").value = ""; $("#cal-user").value = ""; $("#cal-pass").value = "";
      renderConnections();
    });
    $("#cal-file").onclick = busy($("#cal-file"), async function () {
      if (!window.showOpenFilePicker) throw new Error("This browser can't remember files: use Chrome or Edge.");
      var hs;
      try { hs = await window.showOpenFilePicker({ multiple: true, types: [{ description: "Calendars", accept: { "text/calendar": [".ics"] } }] }); }
      catch (e) { if (e.name === "AbortError") return; throw e; }
      for (var i = 0; i < hs.length; i++) {
        var id = rand(4);
        await idb.set("calfile:" + id, hs[i]);
        Cal.list.push({ id: id, type: "file", name: $("#cal-name").value.trim() || hs[i].name.replace(/\.ics$/i, "") });
      }
      Cal.save();
      $("#cal-name").value = "";
      renderConnections();
    });
    $("#p-login").onclick = busy($("#p-login"), async function () {
      $("#p-status").textContent = "Waiting for the Plex sign-in…";
      await P.signIn(function (blocked) { if (blocked) alertIn($("#p-login"), "Allow pop-ups for this page, then try again."); });
      renderConnections();
    });
    $("#p-out").onclick = function () { P.st = null; P.save(); renderConnections(); };
    // content
    document.querySelectorAll(".tabs button").forEach(function (b) { b.onclick = function () { Browse.setTab(b.dataset.tab); }; });
    var search = busy($("#b-go"), Browse.search);
    $("#b-go").onclick = search;
    $("#b-search").onkeydown = function (e) { if (e.key === "Enter") search(); };
    $("#b-more").onclick = busy($("#b-more"), function () { return Browse.more && Browse.more(); });
    // sync
    $("#o-update").onchange = function () { Update.chosen = $("#o-update").checked; };
    var qChanged = function () { P.q = { bitrate: Number($("#p-bitrate").value) || 192, shrink: $("#p-shrink").checked }; };
    $("#p-bitrate").onchange = qChanged;
    $("#p-shrink").onchange = qChanged;
    $("#o-beta").onchange = function () { Update.betaTouched = true; Update.file = null; Update.check(); };
    $("#sync").onclick = runSync;
    $("#rep-send").onclick = busy($("#rep-send"), async function () {
      var res = $("#rep-result");
      res.textContent = ""; res.className = "small";
      try {
        if (!Drive.sync) throw new Error("Choose the Kindle's drive first.");
        var r = await Report.sendNow(K.out, $("#rep-note").value);
        $("#rep-note").value = "";
        res.textContent = "Sent to the developer" + (r.saved ? " (with " + r.saved + " saved on the Kindle)" : "") + ". Thank you!";
        res.classList.add("ok");
      } catch (e) {
        res.textContent = "Not sent: " + e.message + ".";
        res.classList.add("bad");
      }
      await Report.render();
    });
    // test mode: the pretend Kindle at once
    if (K.test) {
      show("#testbar", true);
      $("#test-reset").onclick = async function () {
        if (!confirm("Start the pretend Kindle over? Everything on it, its PIN and connections included, is deleted.")) return;
        Vault.lock(); show("#app", false);
        await openDrive(await testKindle(true), true);
      };
      $("#test-leave").onclick = function () { location.href = location.pathname; };
      await openDrive(await testKindle(false), true);
    }
  }

  // (tests: a folder standing in for the Kindle, without the folder picker)
  window.GZSync = {
    open: openDrive, sync: runSync, demuxTs: demuxTs, memoFileName: memoFileName, slimMemo: slimMemo,
    G: G, M: M, P: P, K: K, Cal: Cal, Vault: Vault, Picks: Picks, Update: Update, zipEntryText: zipEntryText, Browse: Browse,
    testKindle: testKindle, setPanel: setPanel, isoWeekOfYear: isoWeekOfYear, Sleep: Sleep, Heic: Heic, Mp4: Mp4, Report: Report,
    Slim: Slim,
  };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start); else start();
})();
