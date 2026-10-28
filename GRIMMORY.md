# KOReader for Grimmory — Kindle Keyboard build

A trimmed KOReader for legacy Kindles (Kindle 2, DX, Kindle Keyboard / K3) that
does three things: read, pull books from a [Grimmory](https://grimmory.org)
server, and keep reading progress in sync with it. ZenOS is the default
interface.

Based on KOReader `v2026.07.1` and ZenOS `4.2.0`.

## What's in it

| Kept | Why |
| --- | --- |
| `zenos.koplugin` | The interface (Home, Library, navbar). English only. |
| `coverbrowser.koplugin` | Required by ZenOS's library views. |
| `statistics.koplugin` | Feeds ZenOS's Home reading-stats widgets. |
| `autosuspend.koplugin` | Battery. |
| `grimmory.koplugin` | New: QR pairing, library browser, downloads, native progress sync. |

Removed: the other 32 bundled plugins (including KOReader's own progress
sync, which this build replaces), SSH/SFTP binaries, OTA updater (it
would replace this build with stock KOReader), the 16 MB CJK fallback font,
and UI translations.

## Install

1. Jailbreak the Kindle and install KUAL (see kindlemodding.org).
2. Unzip `koreader-grimmory-kindle-legacy-*.zip` and copy the `koreader`,
   `extensions` and `launchpad` folders to the root of the Kindle's USB drive,
   merging with anything already there.
3. Eject, open KUAL → KOReader → Start KOReader.

## Connect to Grimmory

Tap the **Grimmory** tab in the bottom bar (or Tools → Grimmory).

- **Connect with QR code** — the Kindle shows a QR code. Scan it with your
  phone; a sign-in page opens, served by the Kindle itself over your Wi‑Fi.
  Enter the Grimmory address, username and password. The Kindle logs in,
  keeps only Grimmory's login tokens (never the password), and sets up
  progress sync. The page works once, expires after 10 minutes, and stops
  when you press Back.
- **Connect by typing** — same thing using the Kindle's keyboard.

## Progress sync

Sync is native: it talks to Grimmory's own reading-progress API (the one the
Grimmory web reader uses), not Grimmory's KOReader-compatible sync endpoint.
No KOReader sync account or "KOReader Sync" permission is needed.

- **Which books:** books downloaded through the Grimmory tab. They're matched
  by Grimmory book ID, not by file hash. Sideloaded books are left alone.
- **What's sent (EPUB):** the chapter (spine file), the position inside that
  chapter, and the whole-book percentage. No CFI is sent, which makes
  Grimmory's web reader resume from the chapter + in-chapter position.
  PDFs and comics send the page number; FB2/MOBI/AZW3 send the percentage.
- **From the web reader:** it saves a CFI, chapter and percentage. The Kindle
  opens that chapter and uses the percentage to pick the spot inside it, so it
  lands in the right chapter at roughly the same point (the web reader and
  KOReader measure percentages differently). Kindle-to-Kindle and
  Kindle-to-web are exact to the chapter position.
- **When:** pulled when you open a book and when the Kindle wakes; pushed every
  10 page turns (or 3 minutes), when you close the book and when it sleeps.
  Moving forward from another device is applied silently; going back asks
  first. Offline updates are queued and sent when Wi-Fi comes back.
- **Stats:** each reading session (30 s or longer) is sent to Grimmory's
  reading statistics.
- **Controls:** Tools → Grimmory → "Sync progress now" (in a book), and a
  "Sync reading progress" switch. With ZenOS's Zen Mode on, the Tools menu is
  hidden; add the "Grimmory: sync progress now" action to a ZenOS Launcher
  button or navbar tab instead.

## Rebuild the package

```sh
tools/grimmory/package-kindle-legacy.sh koreader-kindle-legacy-v2026.07.1.zip out/
```

The branch changes only Lua, so the script overlays it onto the official
release built from the same tag rather than rebuilding the native toolchain.
