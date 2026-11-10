What GZreader does to be quick on the Kindle 3 and other old Kindles.

- **While a book opens, background work waits** (`Async.pause`/`resume`):
  a sync already running (the calendar, Notes, Grimmory) is paused until
  the first page is up, and new requests start after it (at most 30 s). On a
  Kindle 3 a calendar sync running beside an open made it take 23.5 s
  instead of 6. The log says `async: paused … while a book opens` and
  `async: resumed after … s`.
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
  The packing reads four pixels at a time where the rows are aligned (one
  32-bit read and one 16-bit write per four pixels): about a third less
  time than two at a time, byte for byte the same.
- **Fewer wake-ups while reading:** GZreader's own timers (usage
  statistics, the remote-debugging heartbeat, the Wi‑Fi idle check) fire on
  the clock's quarter minutes, together, instead of each at its own offset
  (`gzreader_ticks.lua`). On the Kindles without REAGL (2, DX, 3, 4) the
  clock and battery at the top of a book are updated with the page instead
  of by a partial refresh of their own every minute (the clock shows the time
  of the last page turn; `gzreader_reader_clock_minute = true` in
  `settings.reader.lua` brings back the minute updates).
- **Night mode works again**, at no cost: it's done while packing (the device
  reports hardware inversion), so drawing is the same as by day.
- **New books laid out while charging** (`gzreader_layout.lua`; Settings →
  Reader → *Lay out new books while charging*): while the Kindle charges and
  Home is on screen, downloaded books not opened yet are laid out in a
  background process at the lowest priority, the way the reader would open
  them, so the layout cache is there for their first open. Not while books
  download or wait to, or another background job runs (on a Kindle 3 with
  many downloads, memory went down to 2–3 MB), and a new book only after its
  picture-book check: a picture book is laid out with the margins and style
  the check fits it with (laid out before, fitting it made that layout
  useless), and the check waits while a layout runs (side by side, it failed
  for lack of memory). A picture book recognized but not fitted yet (the
  first one on a Kindle) isn't laid out: its first open fits it. It stops
  when the charger is unplugged, a book is opened or a download starts; the
  books don't show as opened (no history, no book settings). Not on Kindles
  with 128 MB or less. After each layout the book engine reads its layout
  cache index again: it reads the index once, at the first book opened, and
  before 2026-11-09's fix didn't see the books laid out after that (laid out
  again when opened). The log says when such a book opens whether the
  reader used that layout, from the time its own layout took
  (`layout: book … opened after its background layout: its layout used:
  laid out in 0.1 s (in the background: 88 s)`, or `laid out again, …`).
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
- **Starting**: each start logs a timing line too (`gzreader_opentiming.lua`):
  how long until Home (or a book) is on screen, the CPU time, when
  GZreader's own part started and how long it took, modules loaded, Lua
  memory, free memory and GZreader's size.
- **5-way focus on Home** refreshes only the old and the new focus boxes
  (quick mode), and the Home key from Settings or the audiobook player makes
  one refresh.
- **Less of ZenOS loaded at start**: ZenOS's own updater (about 1,900
  lines, unused: GZreader's updater replaces it) isn't loaded at all; a
  small `gz_updater.lua` answers ZenOS instead, and GZreader's updater is
  loaded the first time it's needed (the check 20 s after start). The
  integration for Rakuyomi, a manga plugin GZreader doesn't ship, is loaded
  only if that plugin is installed (or a finished `.cbz` is counted).
- Lua is shipped as precompiled bytecode (see [Building](Building)): no parsing
  at start (~4x faster loading overall, up to 15x for big files).
- **CPU budgets in CI** (`tools/gzreader/emulator/perf.lua`): every pull
  request that reaches the emulator times a Kindle 3's start, opening a
  book, 20 page turns, the quick panel and moves on Home, against
  `perf_baseline.json` (more than 50% more CPU fails the check).

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
- **JSON through KOReader's C library** (`gzreader_json.lua`): rapidjson
  (`common/rapidjson.so`) instead of LuaJSON, 5–10× faster on a library's
  worth of books; JSON null still decodes to nil, and lists that must stay
  lists when empty are marked with `Json.list()`. LuaJSON is used if
  rapidjson doesn't load or refuses something.

- The removed CJK font was still listed as a fallback, so every missing
  glyph made KOReader try to load it again (dozens of errors per screen in
  the log). Missing fallbacks are now dropped at start.
- **Statistics after the first page** (GZreader's copy of the statistics
  plugin): the book's database row and its reading totals are looked up
  just after the first page is drawn; the totals kept with the book
  (`gz_read_pages`, `gz_read_time` in its `stats`) give the time-left
  estimate until then.
- ZenOS's Home "quotes" row (about 0.5 s per Home rebuild) is off by default.
- **Saving** (`Grimmory:save`): a save whose download list, audiobooks,
  music, shelves and sign-in are unchanged writes only the rest of GZreader's
  state, to `settings/gzreader_recent.lua` (a few KB), instead of the whole
  of `settings/gzreader.lua` (250 KB with 500 books). The whole file is
  written when those change, when the Kindle sleeps, on exit and at least
  hourly; at start the recent part is laid over it. Without rapidjson (to
  tell "unchanged" quickly) every save is a whole one, as before.
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
- **Request helper (experimental, off by default)** (`gzreader_reqhelper.lua`):
  with Settings → Connections → Grimmory → Keep connections open
  (experimental) ticked (or a file named `gz-request-helper` in the
  `koreader` folder; not offered on Kindles without Wi‑Fi), a small
  separate LuaJIT process runs while Wi‑Fi is on and keeps the connections
  to your servers open *between* background processes: they send their
  requests to it on 127.0.0.1 (with a random token, as to an HTTP proxy)
  and it sends them on over its kept connections, replies unchanged. If it
  isn't there or doesn't answer, requests go directly. It ends when Wi‑Fi
  goes off, GZreader is gone, or after 5 idle minutes.
- The first open of a big EPUB is slow (crengine renders and caches it; 28 s
  seen for a large book). Later opens use the cache.
