GZreader runs on the Kindles KOReader supports and on two Nooks. Each kind of device has its own [package](Whats-in-GZreader#the-packages).

## Tested devices

"Real device" means GZreader has been run on that model itself; "emulator" means GZreader's emulator (the real KOReader programs for that Kindle or Nook, under qemu, with that model's screen, keys and touch), which every change to GZreader is checked in before it's released.

| Device | Package | How you use it | Tested |
| --- | --- | --- | --- |
| **Kindle 2** (2009) | `kindle-legacy` | keyboard, 5-way | emulator |
| **Kindle Keyboard (3)** (2010) | `kindle-legacy` | keyboard, 5-way | real device, emulator |
| **Kindle DX**, DX Graphite | `kindle-legacy` | keyboard, 5-way | real device (DX), emulator (both) |
| **Kindle 4** (2011) | `kindle` | 5-way and Menu | real device, emulator |
| **Kindle Touch** (2011) | `kindle` | touch | real device, emulator |
| **Paperwhite 3** (2015) | `kindlepw2` or `kindlehf` (by firmware) | touch | real device, emulator |
| **Nook 1st Edition** (2009) — *test build* | `nook-1st-edition` | the colour touchscreen | real device (firmware 1.0.0, Softroot 2.5.1), emulator |
| **Nook Simple Touch**, with GlowLight (2011–2012) — *test build* | `nook` | touch | emulator only |

## Untested Kindles

These run the touch packages with the same KOReader device support as the Paperwhite 3, so they should work, but their screens and buttons haven't been tried. Reports are welcome ([open an issue](https://github.com/9retirement6irk/GZreader/issues)).

| Kindle | Package |
| --- | --- |
| Paperwhite 1 (2012) | `kindle` |
| Paperwhite 2 (2013), Voyage, Oasis 1–3, Kindle 2014, 2016 | `kindlepw2` (firmware 5.16.2.x or older) |
| Paperwhite 4 (2018), Paperwhite 5 and Signature Edition (2021), Kindle 2019, 2022 | `kindlepw2` (firmware ≤ 5.16.2.x) or `kindlehf` (5.16.3 or newer) |
| Paperwhite 6 and Signature Edition (2024), Kindle 2024, Scribe (2022, 2024), Colorsoft (in greys) | `kindlehf` |

The firmware version is in the Kindle's Settings → Device Options → Device Info. Packages for another Kindle or firmware don't start (the Kindle flashes and goes back to its home screen; `koreader/crash.log` says why).

## What each device does

| | Kindle 2, 3, DX | Kindle 4 | Kindle Touch | Paperwhite 3 | Nook 1st Edition (test) | Nook Simple Touch (test) |
| --- | --- | --- | --- | --- | --- | --- |
| Use | keyboard, 5-way | 5-way, Menu | touch | touch | the colour touchscreen's buttons and keyboard | touch |
| Wi‑Fi | Kindle 3; the Kindle 2 and DX have none: [sync with a computer](Sync-with-a-Computer) | yes | yes | yes | yes | yes |
| Screen | 600 × 800 (DX 824 × 1200), 16 greys | 600 × 800, 16 greys | 600 × 800 | 1072 × 1448, 300 dpi | 600 × 800 + a 480 × 144 colour touchscreen | 600 × 800 (GlowLight: frontlight) |
| Faster drawing (shadow screen) | yes | yes | (not needed) | (not needed) | (not needed) | (not needed) |
| Audiobooks, music | yes | — (no audio) | yes (player buttons) | — (no audio) | — (not yet) | — (no audio) |
| Read aloud (Kindle voice) | yes (Shift + Sym) | — | yes (Listen in the quick panel) | — | — | — |
| Volume buttons | yes | — | — | — | — | — |
| Clock | UTC: set Settings → General → Time and date → Time zone | same | the Kindle's own | the Kindle's own | the Nook's own | the Nook's own |
| Flash on every page turn (default) | on | on | off | off | off | off |
| Start from | KUAL, Shift G G | KUAL | KUAL or the home screen item | the home screen item | its app icon | adb or a terminal app |

**Ghosting** (a grey trace of the last pages): the Kindle 2, 3, DX and 4 have no REAGL, so a page turn without a flash leaves a trace that adds up. Settings → General → Screen refresh → **Flash on every page turn** flashes the screen clean at every turn, as the Kindle's own reader does; it's on by default on those Kindles and can be turned on on any device. Off: a flash every 6 pages (quicker turns).

On the same Kindles, Settings → General → Screen refresh → **Flash when the screen changes** flashes when most of the screen changes because of something you did (a key or a tap: a tab, a menu, a list's next page). What changes by itself doesn't flash: a book finishing its download and appearing in Downloads, covers arriving, the download status in the status bar.

Every setting about when the screen flashes is in **Settings → General → Screen refresh**: Flash on every page turn, Flash on every CBZ page turn (comics), Flash when the screen changes (the Kindle 2, 3, DX and 4 only) and Partial pages refresh (a flash when a page of Downloads isn't full of books).

KOReader's own device code decides the model from the serial number (the DX runs as KOReader's Kindle 2 class, with its bigger screen); GZreader adapts each screen to keys, the 5-way or touch. More on each: [Using GZreader](Using-GZreader), [Nook 1st Edition](Nook-1st-Edition), [Nook Simple Touch](Nook-Simple-Touch).
