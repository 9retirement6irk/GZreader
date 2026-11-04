# GZreader on an emulated Kindle 3

Runs the real KOReader + ZenOS + GZreader Lua, with the Kindle 3's own ARM
binaries (LuaJIT, crengine, SQLite…) under `qemu-arm`, headless:

- the Kindle 3 device class itself (`/proc/usid` answers a K3 serial), so
  every `Device:hasKeyboard()` / non-touch branch is the real one;
- a fake framebuffer that also keeps **what the e-ink panel would show**
  (only refreshed regions are copied), saved as PNGs;
- scripted key presses (Kindle 3 key codes);
- networking reported as connected; Grimmory = `mock_grimmory.py` from the
  test suite on 127.0.0.1:18080; remote debugging can post to `feed.py`;
- GZreader's watchdog and background processes really run (through qemu);
- optionally a CPU quota (cgroup) so it runs about as slowly as a Kindle 3
  (20 % ≈ a Kindle 3 here).

`GZ_EMU_MODEL` picks the Kindle (default `k3`): `k2` (Kindle 2), `dx` (the
DX: KOReader's Kindle 2 class at 824 × 1200), `dxg` (DX Graphite), `k4`
(Kindle 4: 5-way, no keyboard, an 8-bit framebuffer with inverted levels),
`kt` (Kindle Touch: touch at 600 × 800, its panel's 0–4095 coordinates) or
`pw3`, each with its serial, framebuffer and key codes (the model's own
event map, so a key it doesn't have fails the step).

`GZ_EMU_MODEL=pw3` runs it as a **Kindle Paperwhite 3**: its serial
(so the real `KindlePaperWhite3` device class, touch, no keys, 300 dpi), an
8-bit 1072 × 1448 framebuffer, and scripted touches sent as the panel's
multitouch frames through KOReader's own gesture detection:
`{ tap = { x, y } }`, `{ tap = "Save" }` (the innermost tappable widget
showing that text), `{ hold = … }`, `{ swipe = { x1, y1, x2, y2 } }`. Text
painted straight onto the screen (ZenOS's setup guide) isn't found by text:
tap its coordinates. Same tree and binaries as the Kindle 3 (the Lua is what
differs).

It caught what the Lua tests can't: the setup's touch tours opening the
Menu, KOReader's "Styles have changed…" box over picture books (which only
Press/Back answer), and the order things happen in on a first start.

## Setup

1. A tree: the official kindle-legacy release's `koreader/` folder, with this
   branch's `frontend/`, `reader.lua`, `platform/kindle/koreader.sh` (as
   `koreader.sh`), `GZREADER_VERSION` (as `gzreader-version`) and the five
   kept plugins copied over (what `package-kindle.sh` does). Point
   `GZ_EMU_TREE` at it.
2. `qemu-arm-static` and the ARM loader in `/usr/arm-linux-gnueabi`.
3. The mock Grimmory: `python3 mock_grimmory.py 18080` (test suite).
4. Optional remote debugging: `python3 feed.py 18091 feed.log` and
   `echo http://127.0.0.1:18091/open/feed/test > /mnt/us/gzreader-remote.txt`.

## Scripts

- `setup_qr.lua` — first start: setup guide, the phone page connects
  Grimmory (the phone's GET and POST are sent straight to the Kindle's page
  server), Back, the rest of the guide, keys on Home.
- `pw3_tour.lua` (with `GZ_EMU_MODEL=pw3` or `kt` and `phone_drive.js`, servers as
  for `phone_shots.lua`) — a Paperwhite's first start by touch: the phone
  page, the setup guide, ZenOS's touch tips, every tab, the launcher
  (GZreader menu, Send books), a note ticked by tapping, the note editor,
  the calendar's buttons and an event, a book read by tapping.
- `picture_book.lua` — open `GZ_EMU_BOOK` (e.g. Diary of a Wimpy Kid), turn
  pages, close.
- `audio_keys.lua` — the audiobook player: pause / play again, the volume
  rocker (VPlus / VMinus) in the player and on Home, D (the description), the
  Home key from the player and Settings, sleep and closing GZreader. Needs a
  stand-in `gst-launch-0.10` (see the script).
- `note_toolbar.lua` — the note editor's Menu key: to the toolbar and back,
  the cursor kept in place.
- `screen_check.lua` — what the panel shows (the emulator's framebuffer is
  4-bit and inverted like the Kindle 3's; `GZ_EMU_FB8=1` for a plain 8-bit
  one) on Home, Settings, a book page, rotated and in night mode.
- `setup_books.lua`, then `run_keep.sh startup.lua <out>` (keeps the
  install) a few times — start-up time to Home, CPU, Lua memory, modules.
- `shadow_test.lua`, `bytecode_test.lua` — run with the tree's own luajit
  (`qemu-arm-static -L /usr/arm-linux-gnueabi ./luajit <test>` in the tree):
  the shadow screen gives the same framebuffer bytes as drawing in Lua; the
  bytecode cache.
- `speed.lua` — CPU time, screen refreshes (mode, share of the screen),
  forks and files opened for everyday keys on Home, the tabs, the Home menu
  and Settings, twice; a sampling profiler shows where the CPU went. Needs
  the demo library server on 18080.
- `grimmory_memory.lua` (best with `GZ_EMU_MODEL=pw3`, and
  `demo/big_grimmory.py <tests/mock_grimmory.py> 18080 6000`: thousands of
  books with real covers) — Lua memory and RSS while paging through All
  books with Load more (`GZ_MEM_LOADS`, default 16), the tiles, the title's
  back arrow, Authors and Series (the library index) and a search; writes
  `memory.txt`.
- `copy_send.lua` + `copy_receive.lua` — copying connections between two
  emulators at once (e.g. `GZ_EMU_MODEL=pw3` sending, `k3` receiving, each
  with its own `GZ_EMU_TREE`, the same `GZ_COPY_PIN` file; servers: the mock
  Grimmory on 18080, `demo/mock_memos.py 18082 --sample`,
  `demo/demo_caldav.py 18083 <dir>`): found by mDNS, the PIN, what's copied,
  Grimmory's sign-in filled in. The receiver writes `copy.txt`.

```
tools/gzreader/emulator/run.sh tools/gzreader/emulator/setup_qr.lua /tmp/emu/setup 20
GZ_EMU_BOOK=/path/wimpy.epub EMU_TIMEOUT=900 tools/gzreader/emulator/run.sh tools/gzreader/emulator/picture_book.lua /tmp/emu/pb 20
```

Each step logs the window stack and the panel's refresh count; a key that
leaves the refresh count unchanged changed nothing on screen.

## README screenshots

`readme_shots.lua` walks through setup (QR sign-in), the Grimmory tab, a
download, reading, the Reading menu, read aloud, Home and its Menu. It needs the
demo library server instead of the test mock:

```
python3 tools/gzreader/emulator/demo/make_library.py <nltk gutenberg dir> <koreader>/fonts/noto /tmp/demo-lib
DEMO_DL_DELAY=0.7 python3 tools/gzreader/emulator/demo/demo_grimmory.py <test>/mock_grimmory.py /tmp/demo-lib 18080 &
tools/gzreader/emulator/run.sh tools/gzreader/emulator/readme_shots.lua /tmp/emu/readme
```

`phone_shots.lua` with `phone_drive.js` is the phone page, driven by a real
browser (Playwright's Chromium at a phone's size) talking to the emulated
Kindle: Grimmory, Notes, a CalDAV account, two calendar links, editing a
calendar, sending two books, then Back (the summary), Downloads, Calendar and
Notes. It also checks the log never has the token, passwords or the links'
keys. Servers: the demo library (18080), `demo/mock_memos.py 18097 --sample
--prefix /api --memos26`, `demo/demo_caldav.py 18095 <dir>` and `demo/` served
on 18096 (`python3 -m http.server 18096 --bind 127.0.0.1`). Start both:

```
tools/gzreader/emulator/run.sh tools/gzreader/emulator/phone_shots.lua /tmp/emu/phone &
node tools/gzreader/emulator/phone_drive.js /tmp/emu/phone book1.epub book2.epub
```

A step `{ wait_for = function(E) ... end, timeout = s }` waits (the Kindle's
UI keeps running) until the function returns true; here, files the browser
writes as it goes.

The books are Project Gutenberg texts (NLTK's `gutenberg` corpus) with plain
generated covers. Read aloud is stubbed (no speech daemon in the emulator), so
the highlight stays on the first sentence.
