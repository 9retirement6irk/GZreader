# GZreader — Grimmory + ZenOS + KOReader for the Kindle Keyboard

A trimmed KOReader for legacy Kindles (Kindle 2, DX, Kindle Keyboard / K3)
that reads books, pulls them from a [Grimmory](https://grimmory.org) server
and keeps reading position and bookmarks in sync with it. ZenOS is the
interface. Releases and updates: <https://github.com/9retirement6irk/GZreader>.

Based on KOReader `v2026.07.1` and ZenOS `4.2.0`. Version: see `GZREADER_VERSION`.

## What's in it

| Kept | Why |
| --- | --- |
| `zenos.koplugin` | The interface (Home, Downloaded, navbar). English only. |
| `coverbrowser.koplugin` | Required by ZenOS's library views. |
| `statistics.koplugin` | Feeds ZenOS's Home reading-stats widgets. |
| `autosuspend.koplugin` | Battery. |
| `grimmory.koplugin` | GZreader itself: QR sign-in, library browser, downloads, progress + bookmark sync, Reading menu, read aloud, updates. |

Added: an English dictionary (Open English WordNet, CC BY 4.0, 11 MB).

Removed: the other 32 bundled plugins (including KOReader's own progress
sync), SSH/SFTP binaries, KOReader's OTA updater (it would replace this
build with stock KOReader), the 16 MB CJK fallback font, UI translations and
KOReader's first-run quickstart document (ZenOS's setup guide replaces it).

## Install

1. Jailbreak the Kindle and install KUAL (see kindlemodding.org).
2. Unzip `gzreader-kindle-legacy-<version>.zip` and copy the `koreader`,
   `extensions` and `launchpad` folders to the root of the Kindle's USB
   drive, merging with anything already there.
3. Eject, open KUAL → GZreader → Start GZreader. Or the launchpad shortcuts:
   Shift, G, G (last book), Shift, G, L (library), Shift, G, N (without the
   Kindle framework, more memory). The old Shift, P, … shortcuts still work.

The first start runs the setup guide: connect to Grimmory, then the library
view, keyboard, sync, sleep screen, clock and reading defaults.

## Updates

GZreader checks the latest release of github.com/9retirement6irk/GZreader
once a day (Settings → Updates, or Grimmory menu → GZreader updates). An
update is simply the latest GitHub release: the Kindle downloads its
`gzreader-update.zip` over HTTPS, checks the size matches what GitHub lists
(no hashing on the Kindle), checks the zip has a complete GZreader layout,
then swaps in the new `frontend/`,
plugins, `reader.lua`, `koreader.sh` and version, and restarts. Settings,
books, `.sdr` folders, history and the Grimmory folder are never touched; if
anything fails, the previous files are put back.

Publishing a release:

```sh
echo 1.0.1 > GZREADER_VERSION
tools/grimmory/package-kindle-legacy.sh koreader-kindle-legacy-v2026.07.1.zip out/
tools/grimmory/publish-github-release.sh out/      # needs gh, creates tag v1.0.1
```

## Keyboard (Kindle 3)

| Where | Key | Does |
| --- | --- | --- |
| Home / lists | 1 – 9 | Switch the bottom tabs, counted from the left (Home, Downloaded, Continue, Grimmory, Favorites). Also works from the Grimmory browser. |
| Any list | Q, W, E, … | Pick the item with that letter (shown next to it). |
| Reading | Menu | Reading menu: contents, bookmarks, bookmark this page, go to page, search, read aloud, fonts, sync, dictionary, page browser, book info, all settings, close book. |
| Reading | Hold Menu | ZenOS page browser. |
| Reading | AA | Fonts and layout. |
| Reading | Shift + Sym | Read aloud / stop. |
| Reading | Back | Return from a followed link or TOC jump; otherwise go to Home. |
| Reading | 1 – 0 | Jump to 0 – 90 % (KOReader). |

## Connect to Grimmory

Open the **Grimmory** tab (or Tools → Grimmory).

- **Connect with QR code**: the Kindle shows a QR code. Scan it with your
  phone; a sign-in page opens, served by the Kindle itself over your Wi‑Fi.
  The Kindle keeps only Grimmory's login tokens (never the password). The
  page works once, expires after 10 minutes, and stops when you press Back.
- **Connect by typing**: the same, using the Kindle's keyboard.

### Single sign-on (SSO / OIDC)

If Grimmory has SSO turned on, the QR page shows **Sign in with <provider>**.
One-time setup: add `http://<kindle-ip>:8642/oauth2-callback` as an extra
redirect URI on Grimmory's client at your identity provider (shown on the QR
page and under Grimmory → Single sign-on (SSO) setup). Reserve the Kindle's
IP in your router. If `ALLOWED_ORIGINS` is set in Grimmory, add
`http://<kindle-ip>:8642` too.

## Browsing Grimmory

Continue reading, Recently added, All books (A–Z), **Libraries**, **Authors**
(with search), **Series** (in series order) and Search. Audiobooks are left
out everywhere: Authors, Series and Libraries come from a local index of the
readable books (built in the background, refreshed daily), so authors or
series with only audiobooks don't appear, and the lists open instantly.
If Grimmory's `/app/libraries` endpoint fails (HTTP 500, a server bug seen
on some installs), the web app's library list is used instead.

## Home folder and downloads

The Grimmory folder (`documents/Grimmory`) is the home folder; the
**Downloaded** tab shows it. Books download in a background process with a
progress bar (press any key for Stop / Continue in background / Keep
watching); a transfer that stalls for 90 s is stopped.

A backup list of downloaded books (`.gzreader-library.json`) is kept in the
Grimmory folder. If KOReader's settings are lost (for example the `koreader`
folder was replaced), the books are re-linked to Grimmory from it, or by file
name from the library index, so progress sync and "on Kindle" marks keep
working.

## Progress sync

Native: Grimmory's own reading-progress API (the web reader's), not its
KOReader-compatible endpoint.

- Books downloaded through the Grimmory tab, matched by Grimmory book ID.
- EPUB: chapter (spine file), position in the chapter and whole-book
  percentage. PDFs/comics: page. FB2/MOBI/AZW3: percentage.
- Pulled on open and wake; pushed every 10 page turns (or 3 minutes), on
  close and on sleep. Forward moves from other devices apply silently; going
  back asks. Offline updates are queued and sent when Wi‑Fi returns.
  Sync jumps are not added to the Back history.
- Reading sessions (30 s or longer) go to Grimmory's reading statistics.

## Bookmark sync

Page bookmarks are kept the same on the Kindle and in Grimmory (web reader,
other devices), both ways, including deletions. EPUB bookmarks are converted
between KOReader's XPointers and Grimmory's EPUB CFIs using the book's own
XHTML (paragraph precision); PDF/comic bookmarks use the page number.
Bookmarks made offline are sent later. Synced on open and with "Sync with
Grimmory now". Highlights and notes are not synced. Switch: Grimmory menu →
Sync bookmarks.

## Read aloud (Kindle 3 text-to-speech)

Uses the Kindle's own voice (Amazon's speech service, reached over lipc).
Shift + Sym (or Reading menu → Read aloud) starts and stops. The sentence
being read is highlighted and pages turn by themselves. EPUB/FB2/MOBI/AZW3
and text only.

Amazon never documented how its speech service is called, so the first time
GZreader plays "Voice test 1, 2, …" through each candidate way and you pick
the number you heard (Reading menu → Read-aloud settings → Find the Kindle
voice). The speech service doesn't report when a sentence ends, so the next
sentence starts after a time computed from its length and the speed setting
(Read-aloud settings → Slower / Faster). The diagnostic log records what the
speech service answered.

## Sleep screen

While a book is open: its cover. From Home and menus: a random picture from
the USB drive's `screensavers` folder (created by the setup guide), falling
back to the Kindle's own sleep pictures. Chosen in the setup guide; picking
another option there restores KOReader/ZenOS's own sleep-screen settings.

## Speed on the Kindle 3

- The removed CJK font was still listed as a fallback, so every missing
  glyph made KOReader try to load it again (dozens of errors per screen in
  the log). Missing fallbacks are now dropped at start.
- ZenOS's Home "quotes" row (about 0.5 s per Home rebuild) is off by default.
- ZenOS's icon font is no longer registered with the book renderer (it
  failed every time).
- The first open of a big EPUB is slow (crengine renders and caches it; 28 s
  seen for a large book). Later opens use the cache.

## Diagnostic log

`koreader/grimmory.log` (rotates at 512 KB): requests with status and timing,
pairing, SSO, downloads, sync, bookmarks, updates, read aloud. Passwords and
tokens are never written. Grimmory → Save diagnostic log copies it, the tail
of `crash.log` and a read-only audio/speech survey next to the Grimmory
folder.

## Rebuild the package

```sh
tools/grimmory/package-kindle-legacy.sh koreader-kindle-legacy-v2026.07.1.zip out/
```

The branch changes only Lua and shell scripts, so the script overlays it onto
the official release built from the same tag rather than rebuilding the
native toolchain.
