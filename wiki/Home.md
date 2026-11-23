<p align="center"><img src="https://raw.githubusercontent.com/9retirement6irk/GZreader/main/docs/gzreader-logo.svg" alt="GZreader logo" width="96"></p>

**Your self-hosted library on a Kindle.** GZreader is
[KOReader](https://github.com/koreader/koreader) trimmed down to reading, with
the [ZenOS](https://github.com/xZenLabs/zen-os) interface and built-in
connections to the servers a self-hoster already runs, packaged for e-readers
from the Kindle 2 and Nook 1 to the Scribe: Kindle 2, Keyboard, DX, 4, Touch,
Paperwhite 3, Scribe and the other touch Kindles, and, as test builds, Kobos,
the Nook 1st Edition and Nook Simple Touch.

| Your server | What the e-reader does with it |
|---|---|
| [Grimmory](https://grimmory.org) (books; [BookOrbit](https://github.com/bookorbit/bookorbit) is in testing) | browse and download your books and audiobooks; keep your place, bookmarks, highlights and notes in sync |
| [Memos](https://usememos.com) | sticky notes, a rich text editor, drawings, a journal |
| [Plex](https://www.plex.tv) | music, and audiobooks from a Plex library |
| [Immich](https://immich.app) | your photos as the sleep screen and wallpaper, and in notes |
| CalDAV and calendar links (Nextcloud, Radicale, Baïkal, any `.ics` link) | your calendars |
| [Home Assistant](https://www.home-assistant.io) | lights, switches and the weather on the House tab |

Every connection is optional: without any server it's still a reader you can
send books to from your browser, and each one you connect adds its part. The
name is where it started: Grimmory + ZenOS + KOReader.

## Start here

| | |
| --- | --- |
| **[What's in GZreader](Whats-in-GZreader)** | What the package contains, and what was left out |
| **[Device compatibility](Device-Compatibility)** | Which Kindles, Kobos and Nooks run it, and what has been tested |
| **[Feature overview](Feature-Overview)** | Everything it does, with links to the details |
| **[Changes from KOReader and ZenOS](Changes-from-KOReader-and-ZenOS)** | What GZreader does differently |
| **[Installing](Installing)** | Which package, step by step, for each device |
| **[Jailbreaking and rooting](Jailbreaking-and-Rooting)** | Before installing: jailbreak the Kindle or root the Nook (a Kobo needs neither) |

## Using GZreader

- [Using GZreader](Using-GZreader): the quick panel, keys, the 5-way, touch
- [Setup page and connections](Setup-Page-and-Connections): Grimmory, single sign-on, copying connections, Cloudflare
- [Grimmory library](Grimmory-Library) and [Grimmory sync](Grimmory-Sync): browsing, downloads, progress, bookmarks, highlights
- [Home and bookshelves](Home-and-Bookshelves), [Picture books](Picture-Books)
- [Notes](Notes) (and drawing), [Calendar](Calendar), [Music](Music), [Audiobooks and read aloud](Audiobooks-and-Read-Aloud), [Bluetooth](Bluetooth), [House](House) (Home Assistant)
- [Sync with a computer](Sync-with-a-Computer) (Kindles without Wi‑Fi), [Wi‑Fi: on, off, auto](Wi-Fi)
- [Updates and test builds](Updates-and-Test-Builds), [Privacy and diagnostics](Privacy-and-Diagnostics)
- Kobos: [Kobo](Kobo); Nooks: [Nook 1st Edition](Nook-1st-Edition), [Nook Simple Touch](Nook-Simple-Touch)
- Under the hood: [Performance](Performance), [Building](Building)

Downloads: the [latest release](https://github.com/9retirement6irk/GZreader/releases/latest).
Changes: the [changelog](https://github.com/9retirement6irk/GZreader/blob/main/plugins/gzreader.koplugin/gzreader_changelog.lua).
Problems: [open an issue](https://github.com/9retirement6irk/GZreader/issues) with the diagnostic log, or send it from the Kindle ([how](Privacy-and-Diagnostics#diagnostic-log)).

*This wiki is published from the [`wiki/` folder](https://github.com/9retirement6irk/GZreader/tree/main/wiki) of the repository: edit it there.*
