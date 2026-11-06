<p align="center">
  <img src="docs/gzreader-logo.svg" alt="GZreader logo" width="120">
</p>

<h1 align="center">GZreader</h1>

<p align="center">
  <b>Grimmory + ZenOS + KOReader for Kindles</b><br>
  Your <a href="https://grimmory.org">Grimmory</a> (formerly BookLore) library on a Kindle,
  from the Kindle Keyboard to the Paperwhite: download books, read them
  or have them read aloud, and keep your place, bookmarks and highlights in sync.
  Notes, calendars, and books sent from your browser too.
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

| Kindle / Nook | How you use it | Tested |
| --- | --- | --- |
| **Kindle 2**, **Keyboard (3)**, **DX** | the keyboard: a letter key for everything | yes |
| **Kindle 4** | the 5-way and Menu | yes |
| **Kindle Touch** | touch | yes |
| **Paperwhite 3** (2015) | touch | yes |
| Paperwhite 1 (2012) | touch | *untested* |
| Paperwhite 2 (2013) | touch | *untested* |
| Paperwhite 4 (2018) | touch | *untested* |
| Paperwhite 5 (2021), Signature Edition | touch | *untested* |
| Paperwhite 6 (2024), Signature Edition | touch | *untested* |
| Kindle Basic 2014 (7th gen), 2016 (8th gen), 2019 (10th gen) | touch | *untested* |
| Kindle 2022 (11th gen), Kindle 2024 | touch | *untested* |
| Kindle Voyage | touch | *untested* |
| Kindle Oasis 1, 2, 3 | touch | *untested* |
| Kindle Scribe (2022, 2024) | touch | *untested* |
| Kindle Colorsoft | touch (in greys) | *untested* |
| **Nook 1st Edition**, **Nook Simple Touch** — *test builds* | the colour touchscreen / touch | yes |

*Tested* means run on that Kindle or its emulator; the untested ones use the
same KOReader device support and should work, but their screens and buttons
haven't been tried.

<table>
<tr><td align="center" width="25%"><img src="docs/screenshots/home.png" alt="Home" width="200"><br><sub>Home</sub></td><td align="center" width="25%"><img src="docs/screenshots/grimmory-tab.png" alt="Your Grimmory library as a bookshop" width="200"><br><sub>Your Grimmory library</sub></td><td align="center" width="25%"><img src="docs/screenshots/notes-board.png" alt="Notes from Memos" width="200"><br><sub>Notes from Memos</sub></td><td align="center" width="25%"><img src="docs/screenshots/phone-start.png" alt="Set up from your browser" width="200"><br><sub>Set up from your browser</sub></td></tr>
</table>

[More screenshots](docs/screenshots/)

## What it does

- 📚 **Grimmory:** search and browse your library (laid out like a bookshop: covers on
  display ledges, a bookcase for libraries, shelves, authors and series), download books in the background,
  and keep your **place, bookmarks, highlights and ratings in sync** with Grimmory.
- 🗄️ **Bookshelves:** your books stand on shelves, spines out; the one you pick turns
  to show its cover. Audiobooks sit on the shelf as a cassette walkman (each one a
  cassette tape inside), music as a CD player (each album a CD). Lists and tiles are a tap away.
- 🌐 **Set up from your browser:** scan one QR code, or type the Kindle's address
  into any browser on your Wi‑Fi and enter the PIN it shows. One page connects
  everything (single sign-on works too) and **sends books** straight to the Kindle.
- 🔁 **Copy connections** from another GZreader over the Wi‑Fi with a PIN.
- 🔌 **No Wi‑Fi? Sync with a computer** *(Kindle 2, DX)*: plug the Kindle in and open
  the [sync page](https://9retirement6irk.github.io/GZreader/sync/) in Chrome or Edge.
  Your reading goes to Grimmory; books, audiobooks and Plex music (chosen on the Kindle
  or the page), notes, calendars, GZreader updates and a copy of your library (to browse
  the Grimmory tab) come back.
- 📝 **Notes:** your [Memos](https://usememos.com) notes as sticky notes; tick
  checklists, write and edit, offline too.
- 📅 **Calendar:** CalDAV accounts and calendar links (Proton, Google…): agenda,
  day, week, month.
- 🎵 **Music** *(new, Kindles with audio)*: albums and playlists from **Plex**, played
  while you read, all in a portable CD player: browse, download and play there. Turn the
  Music tab on in Settings → Navbar → Tabs.
- 🔊 **Read aloud** *(Kindle 2, 3, DX, Touch)*: any EPUB, MOBI, AZW3, FB2 or TXT
  read to you in the Kindle's own voice, the sentence being spoken highlighted and the
  pages turning by themselves. Shift + Sym plays and stops, like the stock Kindle.
- 🎧 **Audiobooks** from Grimmory, with your place kept.
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
   | Kindle 4, Kindle Touch, Paperwhite 1 *(untested)* | `gzreader-kindle-<version>.zip` |
   | Any Kindle on firmware 5.16.3 or newer: Paperwhite 3, *untested:* Paperwhite 4, 5, 6, Kindle 2019, 2022, 2024, Oasis 3, Scribe, Colorsoft | `gzreader-kindlehf-<version>.zip` |
   | Paperwhite 2 and newer on firmware 5.16.2.1.1 or older: Paperwhite 3, *untested:* Paperwhite 2, 4, 5, Voyage, Oasis 1–3, Kindle 2014, 2016, 2019, 2022 | `gzreader-kindlepw2-<version>.zip` |

   The firmware version is in the Kindle's Settings → Device Info.

3. **Unzip** it and copy its folders to the top of the Kindle's USB drive, merging
   with what's there (your books stay). Eject.
4. **Start** it: KUAL → **GZreader → Start GZreader**, or on a Kindle Touch,
   Paperwhite or newer the **GZreader** item on the Kindle's home screen. The setup
   guide shows a QR code for your phone, and an address and PIN for any browser.

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
