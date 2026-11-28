## Before you start

1. **Jailbreak the Kindle, or root the Nook.** GZreader runs alongside the device's own software, which needs a jailbreak (Kindles) or root (Nooks): see [Jailbreaking and rooting](Jailbreaking-and-Rooting). A Kobo needs neither, only NickelMenu or KFMon to start GZreader: [Kobo](Install-Kobo). Turn on **airplane mode** on a Kindle before you start, so it doesn't update itself to a firmware the jailbreak can't handle.
2. **Find your package.** Each package is built for one kind of device; the others won't start on it. Download it from the [latest release](https://github.com/9retirement6irk/GZreader/releases/latest):

| Device | Firmware | Package | Steps |
| --- | --- | --- | --- |
| Kindle 2, Kindle Keyboard (3), DX, DX Graphite | any | `gzreader-kindle-legacy-<version>.zip` | [Kindle 2, 3, DX](Install-Kindle-Legacy) |
| Kindle 4, Kindle Touch (Paperwhite 1, untested) | any | `gzreader-kindle-<version>.zip` | [Kindle 4 and Touch](Install-Kindle) |
| Paperwhite 2 and newer touch Kindles | 5.6.1 – 5.16.2.x | `gzreader-kindlepw2-<version>.zip` | [Touch Kindles, firmware ≤ 5.16.2](Install-Kindle-PW2) |
| Any Kindle | 5.16.3 or newer | `gzreader-kindlehf-<version>.zip` | [Touch Kindles, firmware 5.16.3+](Install-Kindle-HF) |
| Kobo: any KOReader runs on (test build) | any, with NickelMenu or KFMon | `gzreader-kobo-<version>.zip` | [Kobo](Install-Kobo) |
| Nook 1st Edition (test build) | 1.x, rooted | `gzreader-nook-1st-edition-<version>.zip` | [Nook 1st Edition](Install-Nook-1st-Edition) |
| Nook Simple Touch, GlowLight (test build) | 1.2.x, rooted | `gzreader-nook-<version>.zip` | [Nook Simple Touch](Install-Nook-Simple-Touch) |

The Kindle's firmware version is in **Settings → Device Options → Device Info** (older Kindles: Menu → Settings, bottom of the page). Which models have been tested: [Device compatibility](Device-Compatibility).

You'll need a computer with a USB cable, and about 100 MB free on the device.

## After installing

**The first start.** A setup guide runs. It first asks how you want to set up:

- **Set up with my phone**: when the guide ends, a QR code shows. Scan it with your phone, or type the address under it into any browser on the same Wi‑Fi and enter the PIN. The page there connects your book server (Grimmory or [BookOrbit](BookOrbit)), Notes (Memos), Calendar and the rest, and sends books.
- **Set up on this device**: the next page lists the services to tick: Grimmory, BookOrbit, Plex (on devices that play audio), Memos, Home Assistant, Immich, Mealie (once its Recipes tab is in your build) and Calendar. Grimmory and BookOrbit are both book servers, so ticking one unticks the other. The tabs follow your ticks (Notes, Calendar, Music, House, Recipes). When the guide ends, a list of the ticked services opens: pick each one to type its address and sign in; a connected one gets a ✓. Tick neither book server and GZreader works on its own, with books sent from your browser.
- **Skip for now**: nothing is connected; everything is in Settings → Accounts and services later.

You can come back to it any time: the quick panel → **Send books** (Menu, or on a touch Kindle swipe down from the top). The guide then asks about the library view, tabs, sleep screen, clock and whether to send debug reports. → [Setup page and connections](Setup-Page-and-Connections)

Books you download or send go to **GZreader/books** on the Kindle's drive; the **Downloads** tab shows them.

### Where GZreader keeps things

Everything is in one **GZreader** folder at the top of the drive, beside KOReader (if you have it), never in its place:

| | |
| --- | --- |
| `GZreader/app` | GZreader itself: its settings, its logs (`gzreader.log`, `crash.log`) |
| `GZreader/books` | your books, each with its `.sdr` folder (reading position, highlights) |
| `GZreader/music` | music you downloaded |
| `GZreader/audiobooks` | audiobooks you downloaded |
| `GZreader/notes` | your notes kept on the device, their attachments, drawings waiting to go to Memos |

**On a Nook** it's the same folder on the microSD card (or the Nook's storage), except that `GZreader/app` holds only the parts of GZreader that are read, not run: its programs, settings and logs stay in `/data/gzreader` (the card can't run programs), and the code on the card is checked against fingerprints kept there at every start.

Sign-ins (passwords, tokens, calendar links) are kept on the device's own disk instead, where a computer can't read them. KOReader keeps `koreader/`, its own KUAL entry and its settings; GZreader has its own (`extensions/gzreader`, the **GZreader** item), so you can use both.

**A version before 1.35** (GZreader installed in KOReader's place, `koreader/`) can't be updated straight to this one: the step that moved it into the GZreader folder is gone. Update to 1.35 first and start it once, or install this version fresh.

Kindle 2 and DX (no Wi‑Fi): the setup is done from a computer instead. → [Sync with a computer](Sync-with-a-Computer)

Updating, uninstalling: [Updating and uninstalling](Updating-and-Uninstalling).

## If something goes wrong

- **GZreader isn't in KUAL:** check that `extensions/gzreader` is on the drive (not `extensions/extensions/gzreader` or inside another folder).
- **It flashes and returns to the Kindle's home screen:** most likely the package for another Kindle or firmware; take the one from the table above. `GZreader/app/crash.log` on the drive says why.
- **The setup page doesn't open:** the phone or computer must be on the same Wi‑Fi as the Kindle, and the Kindle's Wi‑Fi must be on. Type the address exactly as the Kindle shows it (with `:8642` if it shows one), starting `http://` if the browser insists on `https://`.
- **Something else:** quick panel → **Diagnostics** → **Send to the developer**, or *Save to the Kindle* and attach the file to an [issue](https://github.com/9retirement6irk/GZreader/issues). → [Diagnostic log](Privacy-and-Diagnostics#diagnostic-log)
