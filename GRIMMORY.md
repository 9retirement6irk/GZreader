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
| `kosync.koplugin` | Progress sync — pointed at Grimmory's KOReader endpoint. |
| `statistics.koplugin` | Feeds ZenOS's Home reading-stats widgets. |
| `autosuspend.koplugin` | Battery. |
| `grimmory.koplugin` | New: QR pairing, library browser, downloads, sync setup. |

Removed: the other 31 bundled plugins, SSH/SFTP binaries, OTA updater (it
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

Progress sync uses Grimmory's KOReader sync account for your user. If you
already have one (e.g. another device), it's reused; otherwise one is
created. Your account needs the **KOReader Sync** permission (admins have
it; others can be granted it in Grimmory → Settings → Users).

Progress only links up for books downloaded from Grimmory, because Grimmory
matches books by file hash.

## Rebuild the package

```sh
tools/grimmory/package-kindle-legacy.sh koreader-kindle-legacy-v2026.07.1.zip out/
```

The branch changes only Lua, so the script overlays it onto the official
release built from the same tag rather than rebuilding the native toolchain.
