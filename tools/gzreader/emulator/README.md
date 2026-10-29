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

It caught what the Lua tests can't: the setup's touch tours opening the
Menu, KOReader's "Styles have changed…" box over picture books (which only
Press/Back answer), and the order things happen in on a first start.

## Setup

1. A tree: the official kindle-legacy release's `koreader/` folder, with this
   branch's `frontend/`, `reader.lua`, `platform/kindle/koreader.sh` (as
   `koreader.sh`), `GZREADER_VERSION` (as `gzreader-version`) and the five
   kept plugins copied over (what `package-kindle-legacy.sh` does). Point
   `GZ_EMU_TREE` at it.
2. `qemu-arm-static` and the ARM loader in `/usr/arm-linux-gnueabi`.
3. The mock Grimmory: `python3 mock_grimmory.py 18080` (test suite).
4. Optional remote debugging: `python3 feed.py 18091 feed.log` and
   `echo http://127.0.0.1:18091/open/feed/test > /mnt/us/gzreader-remote.txt`.

## Scripts

- `setup_qr.lua` — first start: setup guide, QR login (the phone's GET and
  POST are sent straight to the pairing server), the rest of the guide, keys
  on Home.
- `picture_book.lua` — open `GZ_EMU_BOOK` (e.g. Diary of a Wimpy Kid), turn
  pages, close.

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

The books are Project Gutenberg texts (NLTK's `gutenberg` corpus) with plain
generated covers. Read aloud is stubbed (no speech daemon in the emulator), so
the highlight stays on the first sentence.
