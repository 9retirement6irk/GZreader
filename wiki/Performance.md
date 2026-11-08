What GZreader does to be quick on the Kindle 3 and other old Kindles.

- **Drawing with the C blitter** (`frontend/device/kindle/shadowfb.lua`).
  KOReader's fast C blitter doesn't handle the Kindle 2 / DX / 3's 4-bit
  framebuffer, so every glyph, icon and cover was drawn pixel by pixel in
  Lua: most of the CPU time of each key press. KOReader now draws into an
  8-bit shadow screen with the C blitter, and just before each e-ink refresh
  the refreshed rectangle is packed into the framebuffer (two pixels per
  byte, the panel's inverted levels, physical coordinates so rotation works).
  The result is byte-for-byte what drawing into the framebuffer gave
  (`tools/gzreader/emulator/shadow_test.lua`); in the emulator everyday keys
  take about a third less CPU and start-up is faster. Off: a file named
  `gz-no-shadow-screen` in the `koreader` folder.
- **Night mode works again**, at no cost: it's done while packing (the device
  reports hardware inversion), so drawing is the same as by day.
- **Bytecode cache for source installs** (`frontend/gzbytecode.lua`): when
  the Lua files are source (an update from GitHub's source archive, a
  development copy), each module's bytecode is kept in
  `cache/gz-bytecode/<LuaJIT, version>/` the first time it loads (about 4x
  faster to load after that). Release packages are precompiled already, and
  then it does nothing. Off: a file named `gz-no-bytecode` in the `koreader`
  folder.
- **Opening books**: each open logs a timing line (`gzreader_opentiming.lua`:
  closing the file manager, opening and laying out the document, each
  module's ReaderReady, screen refreshes, free memory). The crengine layout
  cache is 256 MB instead of 64 (a dropped layout means a full re-layout on
  the next open), and `LuaSettings:flush` skips writing a file whose content
  hasn't changed (opening a book wrote `settings.reader.lua` twice).
- **5-way focus on Home** refreshes only the old and the new focus boxes
  (quick mode), and the Home key from Settings or the audiobook player makes
  one refresh.
- Lua is shipped as precompiled bytecode (see [Building](Building)): no parsing
  at start (~4x faster loading overall, up to 15x for big files).

- Covers are pre-sized (Settings → Interface → Pre-size covers). ZenOS scales
  every cover to the exact size of where it's shown; on the Kindle 3 that took
  ~4 s of CPU per Home screen (the cover strip), and its memory cache starts
  empty after every restart. GZreader keeps each final-size cover as a raw
  bitmap in `koreader/cache/gz-covers/` (used only while the book file is
  unchanged), learns the sizes ZenOS uses, and a low-priority background
  process (`gzreader_coverwarm.lua`) makes them for every downloaded book a
  minute after start, after downloads and when a new size shows up. Books
  whose cover hasn't been read yet go through KOReader's cover extraction
  first.
- **Background processes below the screen's priority** (`gzreader_async.lua`):
  syncing, downloads, the library index, update checks and usage statistics
  run at nice 5 (longer jobs such as matching highlights at 10, cover sizing
  and other local work at 19), so a TLS handshake (seconds of CPU on a Kindle 3) doesn't hold up
  page turns.

- Night mode on the Kindle 2, DX and Keyboard is done while packing the
  shadow screen (above). On the Kindle 4 (no shadow screen) it stays off and
  can't be switched on: it has no hardware screen inversion, and KOReader's
  software inversion is too slow there.

- The removed CJK font was still listed as a fallback, so every missing
  glyph made KOReader try to load it again (dozens of errors per screen in
  the log). Missing fallbacks are now dropped at start.
- ZenOS's Home "quotes" row (about 0.5 s per Home rebuild) is off by default.
- ZenOS's icon font is no longer registered with the book renderer (it
  failed every time).
- **One background process for a book's sync** (`Async.together`,
  `Grimmory:openSync`): a moment after a book opens, its place, queued
  updates, bookmarks and highlights go in one process instead of four at
  1, 2, 4 and 6 s; requests queued together for the same login share a
  process anyway (up to 6, long ones last), each result coming back as soon
  as it's ready.
- **Kept connections in background processes** (`gzreader_api.lua`, the pool):
  a background process's requests to the same server share one connection
  (HTTP keep-alive) instead of a new TCP and TLS connection each; the
  handshake was most of a request's time on a Kindle 3. A connection idle
  more than 4 s isn't used again; one the server closed meanwhile is opened
  again and the request sent once more (never a POST, which always starts
  on a new connection). Grimmory's book lists come in pages of 50 at most,
  so a 2,000-book index is 40 requests: now on one connection. Off: a file
  named `gz-no-keepalive` in the `koreader` folder.
- **Request helper (experimental, opt-in)** (`gzreader_reqhelper.lua`): with
  a file named `gz-request-helper` in the `koreader` folder, a small
  separate LuaJIT process runs while Wi‑Fi is on and keeps the connections
  to your servers open *between* background processes: they send their
  requests to it on 127.0.0.1 (with a random token, as to an HTTP proxy)
  and it sends them on over its kept connections, replies unchanged. If it
  isn't there or doesn't answer, requests go directly. It ends when Wi‑Fi
  goes off, GZreader is gone, or after 5 idle minutes.
- The first open of a big EPUB is slow (crengine renders and caches it; 28 s
  seen for a large book). Later opens use the cache.
