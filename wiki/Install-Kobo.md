**Package:** `gzreader-kobo-<version>.zip` — for every **Kobo** KOReader runs on: Touch, Mini, Glo, Glo HD, Aura (all of them), Touch 2.0, Clara HD, Clara 2E, Clara BW, Clara Colour, Forma, Libra H2O, Libra 2, Libra Colour, Nia, Sage, Elipsa, Elipsa 2E. **A test build:** it has been run in GZreader's emulator as a Clara HD and a Libra 2, not yet on a real Kobo. Try it on a Kobo whose books you've backed up, and send back what happens. How to use it: [Kobo](Kobo).

A Kobo needs no jailbreak. GZreader starts from **NickelMenu** (an item in the Kobo's menu) or **KFMon** (a "GZreader" book in your library): you need one of them. NickelMenu is the simpler one, and a Kobo update doesn't remove it.

## Install

1. **Install NickelMenu** ([pgaskin.net/NickelMenu](https://pgaskin.net/NickelMenu/): copy its `KoboRoot.tgz` into the Kobo's `.kobo` folder, eject; the Kobo installs it and restarts), **or KFMon** (its package unzipped onto the drive: [KOReader's Kobo guide](https://github.com/koreader/koreader/wiki/Installation-on-Kobo-devices) has both).
2. **Plug the Kobo into a computer** and download `gzreader-kobo-<version>.zip` from the [latest release](https://github.com/9retirement6irk/GZreader/releases/latest).
3. **Unzip it onto the Kobo's drive** (`KOBOeReader`), at the top: you get a `GZreader` folder (GZreader itself is in `GZreader/app`), a hidden `.adds` folder (on a Mac press ⌘ ⇧ . to see it) and a picture, `gzreader.png`. If a `.adds` or `GZreader` folder is there already, merge them (don't replace them: NickelMenu and KFMon keep their files in `.adds`, your books are in `GZreader`).
   - **A KOReader already installed (`.adds/koreader`) stays as it is**: GZreader has its own folder and its own NickelMenu item, so you can keep both.
   - With NickelMenu and no KFMon, delete `gzreader.png`: it's only KFMon's book.
4. **Firmware 4.17 and newer:** GZreader keeps the Kobo from listing its own files as books by itself, at its first start (the `ExcludeSyncFolders` line in `.kobo/Kobo/Kobo eReader.conf`: hidden folders, and `GZreader/app`, `notes`, `music` and `audiobooks`; your line, if you have one, is kept). Nothing to do.
5. **Eject the Kobo** and unplug it. It takes in what's new (and restarts, the first time with NickelMenu or KFMon).
6. **Start GZreader:** NickelMenu: the **GZreader** item in its menu (bottom right of Home, or the main menu). KFMon: open the **GZreader** book in your library.

The first start shows the setup guide, as on a Kindle: [Installing → After installing](Installing#after-installing). Books you download go to **GZreader/books** on the Kobo's drive; the Kobo's own library lists them too. → [Where GZreader keeps things](Installing#where-gzreader-keeps-things)

**Back to the Kobo's own software:** the quick panel (swipe down from the top) → **Exit to Kobo**.

## If something goes wrong

- **No GZreader item or book:** check that the folders are `GZreader/app` and `.adds/nm` (or `.adds/kfmon`) at the top of the drive, not inside another folder. With KFMon, a Kobo update turns KFMon off: install it again.
- **It flashes and goes back to the Kobo's Home:** `GZreader/app/crash.log` on the drive says why. Attach it to an [issue](https://github.com/9retirement6irk/GZreader/issues).
- **Something else:** quick panel → **Diagnostics** → **Send to the developer**, or *Save to the Kobo* and attach the file. → [Diagnostic log](Privacy-and-Diagnostics#diagnostic-log)

**What to send back** from a first try: which Kobo and firmware (Settings → Device information), whether it started, a photo if the screen looks wrong, and `GZreader/app/crash.log`.
