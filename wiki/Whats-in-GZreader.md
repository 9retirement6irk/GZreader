GZreader is a package of KOReader with a few of its plugins, ZenOS, and GZreader's own plugin. Based on KOReader `v2026.07.1` and ZenOS `4.3.2` (`tools/gzreader/UPSTREAM` in the repository); the version is in `GZREADER_VERSION`.

## What's kept

| Kept | Why |
| --- | --- |
| `zenos.koplugin` | The interface: Home, Downloads, the tab bar, the setup guide, settings. English only. |
| `coverbrowser.koplugin` | Required by ZenOS's library views. |
| `statistics.koplugin` | Feeds ZenOS's Home reading-stats widgets. |
| `autosuspend.koplugin` | Battery. |
| `gzreader.koplugin` | GZreader itself: the setup page (QR code or address + PIN: connections, sending books), the Grimmory library browser, downloads, progress, bookmark and highlight sync, the quick panel, Notes, Calendar, Music, audiobooks, read aloud, sync with a computer, updates, debug reports and diagnostics. |

Added: an English dictionary (Open English WordNet, CC BY 4.0, 11 MB), emoji (OpenMoji's black and colour fonts, CC BY-SA 4.0, 4.3 MB; see [Emoji](#emoji)), and GZreader's launchers for each Kindle (KUAL, the Kindle 2/3/DX launchpad, a home-screen item on touch Kindles, NickelMenu and KFMon entries on Kobos, an app icon on the Nook 1st Edition).

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
| `gzreader-kobo-<version>.zip` | Kobos (test build) | [Kobo](Install-Kobo) |
| `gzreader-nook-1st-edition-<version>.zip` | Nook 1st Edition (test build) | [Nook 1st Edition](Install-Nook-1st-Edition) |
| `gzreader-nook-<version>.zip` | Nook Simple Touch, with or without GlowLight (test build) | [Nook Simple Touch](Install-Nook-Simple-Touch) |
| `gzreader-update.zip` | Every device: what Settings → General → Software update and the sync page install (Lua only, ~6 MB, the same for all) | [Updates](Updates-and-Test-Builds) |

The Lua code is the same in every package; what differs is KOReader's native programs for that device (built by KOReader for the Kindles and Kobos, and by GZreader without floating point for the Nook 1st Edition) and the launchers.

## Emoji

KOReader's own fonts have no emoji, so 😀 👍 📚 showed as empty boxes. GZreader adds [OpenMoji](https://openmoji.org/)'s emoji fonts (in `GZreader/app/plugins/gzreader.koplugin/fonts/`, so updates bring them):

- **Every device:** the black font is KOReader's last fallback font, so emoji show in black line drawings wherever text is: notes, the note editor, tags, calendar events, book titles. Older symbols that KOReader's own fonts already had (❤ ✔ ☺ ☀) look as before.
- **Colour Kindles** (Colorsoft, Scribe Colorsoft) **and colour Kobos**, with colour rendering on: the same emoji in OpenMoji's colours. KOReader can't draw colour fonts, so GZreader paints each emoji's coloured layers from OpenMoji's colour font itself.

The colour font (2.8 MB of the 4.3 MB) is only kept where it can show: the Kindle 2, 3, DX, Kindle 4 and Touch (and Nook) packages don't have it, and an update leaves it out on any device without a colour screen (it goes from one that had it). Those devices keep the black font (1.5 MB).

All emojis designed by [OpenMoji](https://openmoji.org/) – the open-source emoji and icon project. License: [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). The fonts are unchanged; their licence is in `fonts/OpenMoji-LICENSE.txt` and the credits in the plugin's `THIRD_PARTY_NOTICES.md`.

There's no emoji keyboard on the Kindle yet: emoji come from notes and events written elsewhere (Memos on a phone or computer, for instance).
