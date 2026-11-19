GZreader on a Kobo (*test build*: tried in GZreader's emulator as a Clara HD and a Libra 2, not yet on a real Kobo). Installing: [Kobo](Install-Kobo).

## What's the same

A Kobo is used as a touch Kindle: tap or swipe to turn pages, swipe down from the top for the quick panel, the tabs along the bottom. Grimmory (library, downloads, reading position, bookmarks, highlights and notes), Notes with drawing, the Calendar, the daily paper, Home Assistant, Immich pictures for the sleep screen and the setup page on your phone all work as on a Kindle. GZreader's messages say "Kobo".

- **Page keys** (Libra, Sage, Elipsa, Forma): turn pages, as KOReader sets them.
- **Light:** the quick panel's slider, and a warmth slider on Kobos with a warm light (Clara HD and newer, Forma, Libra, Sage).
- **Wi‑Fi:** KOReader's own Wi‑Fi for Kobos, with GZreader's On / Off / Auto: [Wi‑Fi](Wi-Fi).
- **Clock:** the Kobo's own. If it's plainly wrong (a Kobo whose battery ran down), GZreader sets it from the internet once Wi‑Fi connects.
- **Updates:** Settings → General → Software update, as on a Kindle. An update brings the Kobo's own start script (`GZreader/app/koreader.sh`), never a Kindle's. From a version before 1.35 (installed in `.adds/koreader`), the first start after the update moves GZreader into `GZreader/app`, with your books, music, audiobooks and notes, and points the NickelMenu and KFMon entries there.

## What's different

- **Sync with a computer → Connect to computer:** GZreader steps aside and KOReader's USB mode shares the drive. When you eject the Kobo, GZreader comes back and takes in what the [sync page](Sync-with-a-Computer) brought. (Turned off in KOReader's USB settings: exit GZreader first.)
- **Sign-ins** (passwords, tokens, calendar links) are kept on the Kobo's own disk, `/usr/local/gzreader`, not on the USB drive a computer can read. A Kobo firmware update can clear that folder: GZreader then asks you to connect again.
- **No sound:** no audiobooks, music or read aloud. Kobos have no speaker or headphone jack, and the ones with Bluetooth play audiobooks only in Kobo's own software, which GZreader can't use.
- **A pen** (Kobo Stylus or Stylus 2: Elipsa, Sage, Elipsa 2E, Libra Colour) draws in Notes as on the Kindle Scribe: with its **pressure**, while a **hand can rest on the screen** (a finger draws nothing); its **other end** and its **buttons** rub out or highlight, as KOReader reads them. The drawing screen's pen / finger button lets a finger draw instead. Tried in the emulator as an Elipsa 2E, not yet on a real Kobo. On the first Elipsa (2021), whose screen holds everything up while it updates, the ink may trail behind the pen.
- **Exit to Kobo** (quick panel) goes back to the Kobo's Home. With KFMon set to restart the Kobo on exit, it restarts instead.

## Files on the Kobo's drive

| | |
| --- | --- |
| `GZreader/app/` | GZreader (settings in `GZreader/app/settings`, logs `GZreader/app/gzreader.log` and `crash.log`) |
| `.adds/nm/gzreader` | NickelMenu's GZreader item |
| `.adds/kfmon/config/gzreader.ini`, `gzreader.png` | KFMon's GZreader book |
| `GZreader/books`, `music`, `audiobooks`, `notes` | your books, what you downloaded, your notes |
| `.adds/koreader/` | KOReader, if you have it: GZreader leaves it alone |

Uninstalling: [Updating and uninstalling](Updating-and-Uninstalling#uninstalling).
