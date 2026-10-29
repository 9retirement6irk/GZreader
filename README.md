<p align="center">
  <img src="docs/gzreader-logo.svg" alt="GZreader logo" width="120">
</p>

<h1 align="center">GZreader</h1>

<p align="center">
  <b>Grimmory + ZenOS + KOReader for the Kindle Keyboard</b><br>
  Your <a href="https://grimmory.org">Grimmory</a> library on a Kindle 3: download books, read them,
  and keep your place and bookmarks in sync.
</p>

<p align="center">
  <a href="https://github.com/9retirement6irk/GZreader/releases/latest"><b>Download the latest release</b></a> ·
  <a href="GZREADER.md">Full guide</a> ·
  <a href="plugins/grimmory.koplugin/grimmory_changelog.lua">Changelog</a>
</p>

---

GZreader is a reading app for **legacy Kindles** (Kindle Keyboard / Kindle 3, also
Kindle 2 and DX). It is [KOReader](https://github.com/koreader/koreader) trimmed down
to reading, with the clean [ZenOS](https://github.com/xZenLabs/zen-os) interface, and
a built-in connection to a self-hosted **Grimmory** book server.

## Features

### 📚 Your Grimmory library
- **Sign in with a QR code.** The Kindle shows a code, you scan it with your phone and
  sign in there (no typing passwords on the Kindle keyboard). Single sign-on (OIDC:
  Authentik, Pocket ID, Authelia, Keycloak…) works too. Only Grimmory's login tokens
  are kept, never your password.
- **Browse** Continue reading, Recently added, All books, **Libraries**, **Authors**,
  **Series** (in reading order) and Search. Audiobooks are left out.
- **Background downloads** with a progress bar; keep using the Kindle while a book
  downloads. Books go to a `Grimmory` folder, shown in the **Downloaded** tab.

### 🔄 Sync with Grimmory
- **Reading position** syncs with Grimmory's own progress (the web reader's), not the
  KOReader sync endpoint. Pick up on the Kindle where you left off on the web, and the
  other way round.
- **Bookmarks** sync both ways, deletions included.
- **Works offline:** changes are saved on the Kindle and sent when Wi‑Fi is back.
- Reading sessions feed Grimmory's reading statistics.

### ⌨️ Made for the Kindle Keyboard
- **Reading menu** on the **Menu** key: contents, bookmarks, go to page, search, read
  aloud, fonts, sync, dictionary, book info. Every entry has a letter key.
- **GZreader menu** on the **Menu** key at Home: library, continue reading,
  audiobooks, search, Wi‑Fi, settings, updates, sleep, restart — also
  with letter keys.
- **Alt + Q, W, E, R, T** switch the bottom tabs (Home, Downloaded, Continue,
  Grimmory, Favorites).
- **Back** returns from a link, otherwise goes Home (never back to the book's start).

### 🔊 Read aloud
- Uses the **Kindle's own voice**. **Shift + Sym** starts and stops, like the stock
  Kindle's Text-to-Speech.
- The sentence being read is **highlighted** and **pages turn by themselves**.
- Speed and volume controls; the Kindle's volume buttons work while reading.

### 🎧 Audiobooks (experimental)
- Browse Grimmory's **audiobooks**, download them (M4B or MP3 tracks) and listen
  through the speaker or headphones.
- **Chapters**, ±30 seconds, **sleep timer** (15/30/60 minutes or end of chapter),
  volume; playback continues while you browse.
- Listening position **syncs with Grimmory's web player**.
- Plays through the Kindle 3's own hardware MP3/AAC decoders. M4B files are
  converted on the Kindle after download (no re-encoding) so they can start
  anywhere; downloads resume after a dropped connection. **Test audio playback**
  checks which player works on your firmware.

### 🌙 And more
- **Sleep screen:** the book's cover while reading, a picture from the `screensavers`
  folder on Home and in menus.
- **English dictionary** built in (Open English WordNet, 128,000 words).
- **Updates from GitHub releases**, installed from Settings → General → Updates.
  Your books, settings and progress are kept.
- **Faster on a Kindle 3:** unused plugins, fonts and translations removed, slow
  Home widgets off by default.
- **Diagnostic log** you can save and share (passwords and tokens are never written).

## Install

1. Jailbreak the Kindle and install **KUAL** (see [kindlemodding.org](https://kindlemodding.org)).
2. Download `gzreader-kindle-legacy-<version>.zip` from the
   [latest release](https://github.com/9retirement6irk/GZreader/releases/latest).
3. Unzip it and copy the `koreader`, `extensions` and `launchpad` folders to the root of
   the Kindle's USB drive, merging with what's there.
4. Eject, then open **KUAL → GZreader → Start GZreader**.

The setup guide starts by connecting to your Grimmory server. Later versions install
from **Settings → General → Updates**.

## Connecting to Grimmory

Open the **Grimmory** tab and choose **Connect with QR code**. For single sign-on, add
`http://<kindle-ip>:8642/oauth2-callback` as an extra redirect URI for Grimmory's client
at your identity provider; the exact address is shown on the QR page. Grimmory itself
needs no changes. All Grimmory options are in **Settings → General → Grimmory**.

## Publishing a release

1. Bump [`GZREADER_VERSION`](GZREADER_VERSION) and add an entry to
   [`grimmory_changelog.lua`](plugins/grimmory.koplugin/grimmory_changelog.lua).
2. Create a GitHub release tagged `v<version>` and publish it.

The [release workflow](.github/workflows/gzreader-release.yml) builds and attaches the
install zip and the update package. Kindles check for new releases once a day.

To build locally:

```sh
tools/grimmory/package-kindle-legacy.sh koreader-kindle-legacy-v2026.07.1.zip out/
```

The build reuses the native binaries of the official KOReader kindle-legacy release of
the same version and overlays GZreader's Lua code, plugins and dictionary.

## What's inside

| Part | Role |
| --- | --- |
| [`plugins/grimmory.koplugin`](plugins/grimmory.koplugin) | GZreader itself: Grimmory sign-in, browser, downloads, progress and bookmark sync, Reading menu, read aloud, updater |
| [`plugins/zenos.koplugin`](plugins/zenos.koplugin) | ZenOS 4.2.0 interface, adapted for GZreader and the Kindle keyboard |
| `frontend/`, `reader.lua` | KOReader v2026.07.1 with GZreader changes (branding, keyboard, sleep screen, speed fixes) |
| [`tools/grimmory`](tools/grimmory) | Packaging, dictionary builder, release script |

## Credits and license

GZreader is built on **[KOReader](https://github.com/koreader/koreader)** (AGPL-3.0) and
**[ZenOS](https://github.com/xZenLabs/zen-os)**, and connects to
**[Grimmory](https://grimmory.org)**. The dictionary is
[Open English WordNet](https://en-word.net) (CC BY 4.0).

GZreader is free software under the [GNU Affero General Public License v3](COPYING).
KOReader's original README is kept in [README.koreader.md](README.koreader.md).
