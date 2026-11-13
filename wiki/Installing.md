## Before you start

**On a Kindle, the [setup page](https://9retirement6irk.github.io/GZreader/setup/) walks you through it all** (Chrome or Edge on a computer): the jailbreak for your model and firmware, then the right package, each file put on the Kindle at the right step. The steps below are the same, by hand.

1. **Jailbreak the Kindle, or root the Nook.** GZreader runs alongside the device's own software, which needs a jailbreak (Kindles) or root (Nooks): see [Jailbreaking and rooting](Jailbreaking-and-Rooting). Turn on **airplane mode** on a Kindle before you start, so it doesn't update itself to a firmware the jailbreak can't handle.
2. **Find your package.** Each package is built for one kind of device; the others won't start on it. Download it from the [latest release](https://github.com/9retirement6irk/GZreader/releases/latest):

| Device | Firmware | Package | Steps |
| --- | --- | --- | --- |
| Kindle 2, Kindle Keyboard (3), DX, DX Graphite | any | `gzreader-kindle-legacy-<version>.zip` | [Kindle 2, 3, DX](Install-Kindle-Legacy) |
| Kindle 4, Kindle Touch (Paperwhite 1, untested) | any | `gzreader-kindle-<version>.zip` | [Kindle 4 and Touch](Install-Kindle) |
| Paperwhite 2 and newer touch Kindles | 5.6.1 – 5.16.2.x | `gzreader-kindlepw2-<version>.zip` | [Touch Kindles, firmware ≤ 5.16.2](Install-Kindle-PW2) |
| Any Kindle | 5.16.3 or newer | `gzreader-kindlehf-<version>.zip` | [Touch Kindles, firmware 5.16.3+](Install-Kindle-HF) |
| Nook 1st Edition (test build) | 1.x, rooted | `gzreader-nook-1st-edition-<version>.zip` | [Nook 1st Edition](Install-Nook-1st-Edition) |
| Nook Simple Touch, GlowLight (test build) | 1.2.x, rooted | `gzreader-nook-<version>.zip` | [Nook Simple Touch](Install-Nook-Simple-Touch) |

The Kindle's firmware version is in **Settings → Device Options → Device Info** (older Kindles: Menu → Settings, bottom of the page). Which models have been tested: [Device compatibility](Device-Compatibility).

You'll need a computer with a USB cable, and about 100 MB free on the device.

## After installing

**The first start.** A setup guide runs. Its first page, **Set up from your browser**, shows a QR code: scan it with your phone, or type the address under it into any browser on the same Wi‑Fi and enter the PIN, to connect Grimmory, Notes (Memos) and Calendar, or to send books, or pick *Skip for now*. You can come back to it any time: the quick panel → **Send books** (Menu, or on a touch Kindle swipe down from the top). The guide then asks about the library view, tabs, sleep screen, clock and whether to send debug reports. → [Setup page and connections](Setup-Page-and-Connections)

Books you download or send go to the **GZreader** folder at the top of the Kindle's drive; the **Downloads** tab shows them.

Kindle 2 and DX (no Wi‑Fi): the setup is done from a computer instead. → [Sync with a computer](Sync-with-a-Computer)

Updating, uninstalling: [Updating and uninstalling](Updating-and-Uninstalling).

## If something goes wrong

- **GZreader isn't in KUAL:** check that `extensions/koreader` is on the drive (not `extensions/extensions/koreader` or inside another folder).
- **It flashes and returns to the Kindle's home screen:** most likely the package for another Kindle or firmware; take the one from the table above. `koreader/crash.log` on the drive says why.
- **The setup page doesn't open:** the phone or computer must be on the same Wi‑Fi as the Kindle, and the Kindle's Wi‑Fi must be on. Type the address exactly as the Kindle shows it (with `:8642` if it shows one), starting `http://` if the browser insists on `https://`.
- **Something else:** quick panel → **Diagnostics** → **Send to the developer**, or *Save to the Kindle* and attach the file to an [issue](https://github.com/9retirement6irk/GZreader/issues). → [Diagnostic log](Privacy-and-Diagnostics#diagnostic-log)
