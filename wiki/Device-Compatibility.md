GZreader runs on the Kindles KOReader supports, on Kobos (test build) and on two Nooks. Each kind of device has its own [package](Whats-in-GZreader#the-packages).

## Tested devices

"Real device" means GZreader has been run on that model itself; "emulator" means GZreader's emulator (the real KOReader programs for that Kindle, Kobo or Nook, under qemu, with that model's screen, keys and touch), which every change to GZreader is checked in before it's released.

| Device | Package | How you use it | Tested |
| --- | --- | --- | --- |
| **Kindle 2** (2009) | `kindle-legacy` | keyboard, 5-way | emulator |
| **Kindle Keyboard (3)** (2010) | `kindle-legacy` | keyboard, 5-way | real device, emulator |
| **Kindle DX**, DX Graphite | `kindle-legacy` | keyboard, 5-way | real device (DX), emulator (both) |
| **Kindle 4** (2011) | `kindle` | 5-way and Menu | real device, emulator |
| **Kindle Touch** (2011) | `kindle` | touch | real device, emulator |
| **Paperwhite 3** (2015) | `kindlepw2` or `kindlehf` (by firmware) | touch | real device, emulator |
| **Kindle Scribe** | `kindlehf` | touch and pen | real device (firmware 5.20.2), emulator |
| **Nook 1st Edition** (2009) — *test build* | `nook-1st-edition` | the colour touchscreen | real device (firmware 1.0.0, Softroot 2.5.1), emulator |
| **Nook Simple Touch**, with GlowLight (2011–2012) — *test build* | `nook` | touch | emulator only |
| **Kobo Clara HD** (2018) — *test build* | `kobo` | touch | emulator only |
| **Kobo Libra 2** (2021) — *test build* | `kobo` | touch, page keys | emulator only |

## Kobos

One package, `kobo`, for every Kobo KOReader runs on, with KOReader's own device support for each: Touch, Mini, Glo, Glo HD, Aura, Aura HD, Aura H2O (both), Aura One, Aura Edition 2, Touch 2.0, Clara HD, Clara 2E, Clara BW, Clara Colour, Forma, Libra H2O, Libra 2, Libra Colour, Nia, Sage, Elipsa, Elipsa 2E. Only the Clara HD and Libra 2 have been tried, in the emulator; reports from any Kobo are welcome. On a Kobo there's no sound (no audiobooks, music or read aloud), and a pen draws as a finger. More: [Kobo](Kobo).

## Untested Kindles

These run the touch packages with the same KOReader device support as the Paperwhite 3 and the Scribe, so they should work, but their screens and buttons haven't been tried. Reports are welcome ([open an issue](https://github.com/9retirement6irk/GZreader/issues)).

| Kindle | Package |
| --- | --- |
| Paperwhite 1 (2012) | `kindle` |
| Paperwhite 2 (2013), Voyage, Oasis 1–3, Kindle 2014, 2016 | `kindlepw2` (firmware 5.16.2.x or older) |
| Paperwhite 4 (2018), Paperwhite 5 and Signature Edition (2021), Kindle 2019, 2022 | `kindlepw2` (firmware ≤ 5.16.2.x) or `kindlehf` (5.16.3 or newer) |
| Paperwhite 6 and Signature Edition (2024), Kindle 2024, Colorsoft and Scribe Colorsoft (in colour: covers as KOReader shows them, the shelf ornaments and the players) | `kindlehf` |

The firmware version is in the Kindle's Settings → Device Options → Device Info. Packages for another Kindle or firmware don't start (the Kindle flashes and goes back to its home screen; `GZreader/app/crash.log` says why).

**Big screens (Scribe, DX).** KOReader draws menus, buttons and text bigger the more pixels a screen has across, so on a Scribe they came out about 1.7 times their size on a 6" Kindle. GZreader sizes them for the screen's density instead and lets them grow only a little on a bigger screen (on a Scribe about 1.3 times a 6" Kindle's, on a DX a fifth smaller than before). Books look as before: their font size and margins aren't changed. On those Kindles **Settings → Display and light → Size of menus and text** offers Automatic, Smaller, Larger or As large as KOReader makes them (after a restart).

## What each device does

| | Kindle 2, 3, DX | Kindle 4 | Kindle Touch | Paperwhite 3 | Kindle Scribe | Kobo (test) | Nook 1st Edition (test) | Nook Simple Touch (test) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Use | keyboard, 5-way | 5-way, Menu | touch | touch | touch and pen (pressure; the side button erases; your hand can rest on the screen) | touch; page keys on Libra, Sage, Elipsa, Forma (a pen draws as a finger) | the colour touchscreen's buttons and keyboard | touch |
| Wi‑Fi | Kindle 3; the Kindle 2 and DX have none: [sync with a computer](Sync-with-a-Computer) | yes | yes | yes | yes | yes (KOReader's own for Kobos) | yes | yes |
| Screen | 600 × 800 (DX 824 × 1200), 16 greys | 600 × 800, 16 greys | 600 × 800 | 1072 × 1448, 300 dpi | 1860 × 2480, 300 dpi | Clara HD 1072 × 1448, Libra 2 1264 × 1680, 300 dpi (others as KOReader knows them); light and warmth | 600 × 800 + a 480 × 144 colour touchscreen | 600 × 800 (GlowLight: frontlight) |
| Faster drawing (shadow screen) | yes | yes | (not needed) | (not needed) | (not needed) | (not needed) | (not needed) | (not needed) |
| Audiobooks, music | yes | — (no audio) | yes (player buttons) | — (no audio) | yes, through Bluetooth headphones or a speaker ([Bluetooth](Bluetooth)) | — (no speaker; Kobo's Bluetooth only in its own software) | — (not yet) | — (no audio) |
| Read aloud (Kindle voice) | yes (Shift + Sym) | — | yes (Listen in the quick panel) | — | yes, Amazon's voice through Bluetooth (Read aloud in the quick panel) | — | — | — |
| Volume buttons | yes | — | — | — | — (the Bluetooth volume: the quick panel's slider) | — | — | — |
| Clock | UTC: set Settings → General → Time and date → Time zone | same | the Kindle's own | the Kindle's own | the Kindle's own | the Kobo's own | the Nook's own | the Nook's own |
| Flash on every page turn (default) | on | on | off | off | off | off | off | off |
| Start from | KUAL, Shift G G | KUAL | KUAL or the home screen item | the home screen item | the home screen item | NickelMenu or KFMon | its app icon | adb or a terminal app |

**Ghosting** (a grey trace of the last pages): the Kindle 2, 3, DX and 4 have no REAGL, so a page turn without a flash leaves a trace that adds up. Settings → Display and light → Screen → E-ink settings → **Flash on every page turn** flashes the screen clean at every turn, as the Kindle's own reader does; it's on by default on those Kindles and can be turned on on any device. Off: a flash every 6 pages (quicker turns).

On the same Kindles, Settings → Display and light → Screen → E-ink settings → **Flash when the screen changes** flashes when most of the screen changes because of something you did (a key or a tap: a tab, a menu, a list's next page). What changes by itself doesn't flash: a book finishing its download and appearing in Downloads, covers arriving, the download status in the status bar.

Every setting about when the screen flashes is in **Settings → Display and light → Screen → E-ink settings**: KOReader's Full refresh rate (with Always flash on pages with images, which covers comics too: every CBZ page flashes while it's ticked), then GZreader's Flash on every page turn, Flash when the screen changes (the Kindle 2, 3, DX and 4 only) and Partial pages refresh (a flash when a page of Downloads isn't full of books), then KOReader's other e-ink settings. Whichever of Full refresh rate and Flash on every page turn you set last counts. KOReader's Avoid mandatory black flashes in UI works against Flash when the screen changes: leave it off on those Kindles.

KOReader's own device code decides the model from the serial number (the DX runs as KOReader's Kindle 2 class, with its bigger screen); GZreader adapts each screen to keys, the 5-way or touch. More on each: [Using GZreader](Using-GZreader), [Kobo](Kobo), [Nook 1st Edition](Nook-1st-Edition), [Nook Simple Touch](Nook-Simple-Touch).

**A book's font size on big screens (Scribe, DX).** KOReader's font sizes grow with the screen's width in pixels, so the default (23) made a Scribe's books large print (about 17 points; 10 on a Paperwhite). On a screen more than 5 inches across the default is smaller in step: **14** on a Scribe, 16 on a DX, the same size to the eye as 23 on a 6" Kindle. It's used for books opened from now on, and once replaces the old default (22, 22.5 or 23) saved for all books or kept by a book you'd already opened; a size you chose yourself stays. Change it as always with the quick panel's **Layout** (font size).
