GZreader is a package of KOReader with a few of its plugins, ZenOS, and GZreader's own plugin. Based on KOReader `v2026.07.1` and ZenOS `4.3.1` (`tools/gzreader/UPSTREAM` in the repository); the version is in `GZREADER_VERSION`.

## What's kept

| Kept | Why |
| --- | --- |
| `zenos.koplugin` | The interface: Home, Downloads, the tab bar, the setup guide, settings. English only. |
| `coverbrowser.koplugin` | Required by ZenOS's library views. |
| `statistics.koplugin` | Feeds ZenOS's Home reading-stats widgets. |
| `autosuspend.koplugin` | Battery. |
| `gzreader.koplugin` | GZreader itself: the setup page (QR code or address + PIN: connections, sending books), the Grimmory library browser, downloads, progress, bookmark and highlight sync, the quick panel, Notes, Calendar, Music, audiobooks, read aloud, sync with a computer, updates, usage statistics and diagnostics. |

Added: an English dictionary (Open English WordNet, CC BY 4.0, 11 MB), and GZreader's launchers for each Kindle (KUAL, the Kindle 2/3/DX launchpad, a home-screen item on touch Kindles, an app icon on the Nook 1st Edition).

## What's left out

All of KOReader's other bundled plugins (34 in the Kindle 2/3/DX package; including KOReader's own progress sync: GZreader syncs with Grimmory itself), the SSH/SFTP binaries, KOReader's OTA updater (it would replace this build with stock KOReader; GZreader updates itself from its GitHub releases), the 16 MB CJK fallback font, the UI translations, and KOReader's first-run quickstart document (ZenOS's setup guide replaces it).

## The packages

Each release has one package per kind of device, plus the update every device downloads:

| Package | For | Install |
| --- | --- | --- |
| `gzreader-kindle-legacy-<version>.zip` | Kindle 2, Kindle Keyboard (3), DX, DX Graphite | [Kindle 2, 3, DX](Install-Kindle-Legacy) |
| `gzreader-kindle-<version>.zip` | Kindle 4, Kindle Touch (and Paperwhite 1, untested) | [Kindle 4 and Touch](Install-Kindle) |
| `gzreader-kindlepw2-<version>.zip` | Paperwhite 2 and newer on firmware 5.6.1 – 5.16.2.x | [Touch Kindles, firmware ≤ 5.16.2](Install-Kindle-PW2) |
| `gzreader-kindlehf-<version>.zip` | Any Kindle on firmware 5.16.3 or newer | [Touch Kindles, firmware 5.16.3+](Install-Kindle-HF) |
| `gzreader-nook-1st-edition-<version>.zip` | Nook 1st Edition (test build) | [Nook 1st Edition](Install-Nook-1st-Edition) |
| `gzreader-nook-<version>.zip` | Nook Simple Touch, with or without GlowLight (test build) | [Nook Simple Touch](Install-Nook-Simple-Touch) |
| `gzreader-update.zip` | Every device: what Settings → General → Updates and the sync page install (Lua only, ~6 MB, the same for all) | [Updates](Updates-and-Test-Builds) |

The Lua code is the same in every package; what differs is KOReader's native programs for that device (built by KOReader for the Kindles, and by GZreader without floating point for the Nook 1st Edition) and the launchers.
