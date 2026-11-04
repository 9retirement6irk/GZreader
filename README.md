<p align="center">
  <img src="docs/gzreader-logo.svg" alt="GZreader logo" width="120">
</p>

<h1 align="center">GZreader</h1>

<p align="center">
  <b>Grimmory + ZenOS + KOReader for older Kindles</b><br>
  Your <a href="https://grimmory.org">Grimmory</a> library on a Kindle: download books, read them,
  and keep your place, bookmarks and highlights in sync. Notes, calendars, and books
  sent from your phone too.
</p>

<p align="center">
  <a href="https://github.com/9retirement6irk/GZreader/releases/latest"><b>Download the latest release</b></a> ·
  <a href="GZREADER.md">Full guide</a> ·
  <a href="plugins/gzreader.koplugin/gzreader_changelog.lua">Changelog</a>
</p>

---

GZreader is [KOReader](https://github.com/koreader/koreader) trimmed down to
reading, with the [ZenOS](https://github.com/xZenLabs/zen-os) interface and a
built-in connection to your self-hosted **Grimmory** book server.

| Kindle / Nook | How you use it |
| --- | --- |
| **Kindle 2**, **Keyboard (3)**, **DX** | the keyboard: a letter key for everything |
| **Kindle 4** | the 5-way and Menu |
| **Kindle Touch**, **Paperwhite 3** | touch |
| **Nook 1st Edition**, **Nook Simple Touch** — *test builds* | the colour touchscreen / touch |

<table>
<tr><td align="center" width="25%"><img src="docs/screenshots/home.png" alt="Home" width="200"><br><sub>Home</sub></td><td align="center" width="25%"><img src="docs/screenshots/grimmory-all-books.png" alt="Your Grimmory library" width="200"><br><sub>Your Grimmory library</sub></td><td align="center" width="25%"><img src="docs/screenshots/notes-board.png" alt="Notes from Memos" width="200"><br><sub>Notes from Memos</sub></td><td align="center" width="25%"><img src="docs/screenshots/phone-start.png" alt="Set up from your phone" width="200"><br><sub>Set up from your phone</sub></td></tr>
</table>

[More screenshots](docs/screenshots/)

## What it does

- 📚 **Grimmory:** search and browse your library, download books in the background,
  and keep your **place, bookmarks and highlights in sync** with Grimmory's web reader.
- 📱 **Set up from your phone:** scan one QR code to connect everything (single
  sign-on works too) and **send books** straight from your phone.
- 🔁 **Copy connections** from another GZreader over the Wi‑Fi with a PIN.
- 📝 **Notes:** your [Memos](https://usememos.com) notes as sticky notes; tick
  checklists, write and edit, offline too.
- 📅 **Calendar:** CalDAV accounts and calendar links (Proton, Google…): agenda,
  day, week, month.
- 🎵 **Music** *(new, Kindles with audio)*: albums and playlists from **Plex**, played
  while you read. Turn the Music tab on in Settings → Navbar → Tabs.
- 🎧 **Audiobooks** from Grimmory and 🔊 **read aloud** with the Kindle's voice
  (Kindle 2, 3, DX, Touch).
- 🔋 Wi‑Fi only when needed, a built-in English dictionary, updates from GitHub.

All the details: **[the full guide](GZREADER.md)**.

## Install

1. **Jailbreak** the Kindle and install **KUAL**
   ([kindlemodding.org](https://kindlemodding.org/jailbreaking/); Kindle 2, 3, DX, 4,
   Touch: [MobileRead](https://www.mobileread.com/forums/forumdisplay.php?f=150)).
2. **Download** the package for your Kindle from the
   [latest release](https://github.com/9retirement6irk/GZreader/releases/latest):

   | Kindle | Package |
   | --- | --- |
   | Kindle 2, Keyboard (3), DX | `gzreader-kindle-legacy-<version>.zip` |
   | Kindle 4, Kindle Touch | `gzreader-kindle-<version>.zip` |
   | Paperwhite 3, firmware 5.16.3 or newer | `gzreader-kindlehf-<version>.zip` |
   | Paperwhite 3, older firmware | `gzreader-kindlepw2-<version>.zip` |

3. **Unzip** it and copy its folders to the top of the Kindle's USB drive, merging
   with what's there. Eject.
4. **Start** it: KUAL → **GZreader → Start GZreader**. The setup guide shows a QR code
   for your phone.

Updates come by themselves (Settings → General → Updates). Step-by-step help,
uninstalling and the Nooks: [Install in the full guide](GZREADER.md#install).

## Privacy

Passwords and tokens stay on the Kindle and are never written to its log.
GZreader sends anonymous usage statistics (no titles, addresses or accounts) to
help fix problems; choose Basic, Full or Off in the setup guide or Settings →
General → Usage statistics ([what's sent](GZREADER.md#usage-statistics)).

## More

- [The full guide](GZREADER.md) · [Changelog](plugins/gzreader.koplugin/gzreader_changelog.lua)
- [Developing GZreader](DEVELOPING.md): building, tests, releases, keeping up with KOReader and ZenOS

## Credits and license

Built on **[KOReader](https://github.com/koreader/koreader)** (AGPL-3.0) and
**[ZenOS](https://github.com/xZenLabs/zen-os)**, connecting to
**[Grimmory](https://grimmory.org)**. Dictionary: [Open English WordNet](https://en-word.net)
(CC BY 4.0). GZreader is free software under the
[GNU Affero General Public License v3](COPYING); KOReader's README is
[README.koreader.md](README.koreader.md).
