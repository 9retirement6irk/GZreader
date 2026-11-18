**Package:** `gzreader-kobo-<version>.zip` — for every **Kobo** KOReader runs on: Touch, Mini, Glo, Glo HD, Aura (all of them), Touch 2.0, Clara HD, Clara 2E, Clara BW, Clara Colour, Forma, Libra H2O, Libra 2, Libra Colour, Nia, Sage, Elipsa, Elipsa 2E. **A test build:** it has been run in GZreader's emulator as a Clara HD and a Libra 2, not yet on a real Kobo. Try it on a Kobo whose books you've backed up, and send back what happens. How to use it: [Kobo](Kobo).

A Kobo needs no jailbreak. GZreader starts from **NickelMenu** (an item in the Kobo's menu) or **KFMon** (a "GZreader" book in your library): you need one of them. NickelMenu is the simpler one, and a Kobo update doesn't remove it.

## Install

1. **Install NickelMenu** ([pgaskin.net/NickelMenu](https://pgaskin.net/NickelMenu/): copy its `KoboRoot.tgz` into the Kobo's `.kobo` folder, eject; the Kobo installs it and restarts), **or KFMon** (its package unzipped onto the drive: [KOReader's Kobo guide](https://github.com/koreader/koreader/wiki/Installation-on-Kobo-devices) has both).
2. **Plug the Kobo into a computer** and download `gzreader-kobo-<version>.zip` from the [latest release](https://github.com/9retirement6irk/GZreader/releases/latest).
3. **Unzip it onto the Kobo's drive** (`KOBOeReader`), at the top: you get a hidden `.adds` folder (on a Mac press ⌘ ⇧ . to see it) and a picture, `gzreader.png`. If a `.adds` folder is there already, merge them (don't replace it: NickelMenu and KFMon keep their files there too).
   - GZreader goes into `.adds/koreader`, where KOReader goes. **A KOReader installed there is replaced by GZreader** (its settings folder stays).
   - With NickelMenu and no KFMon, delete `gzreader.png`: it's only KFMon's book.
4. **Firmware 4.17 and newer:** keep the Kobo from listing GZreader's own files as books. Open `.kobo/Kobo/Kobo eReader.conf` on the drive in a text editor and add, under `[FeatureSettings]` (make that line if there isn't one):

   ```
   ExcludeSyncFolders=(\\.(?!kobo|adobe).+|([^.][^/]*/)+\\..+)
   ```
5. **Eject the Kobo** and unplug it. It takes in what's new (and restarts, the first time with NickelMenu or KFMon).
6. **Start GZreader:** NickelMenu: the **GZreader** item in its menu (bottom right of Home, or the main menu). KFMon: open the **GZreader** book in your library.

The first start shows the setup guide, as on a Kindle: [Installing → After installing](Installing#after-installing). Books you download go to the **GZreader** folder at the top of the Kobo's drive; the Kobo's own library lists them too.

**Back to the Kobo's own software:** the quick panel (swipe down from the top) → **Exit to Kobo**.

## If something goes wrong

- **No GZreader item or book:** check that the folders are `.adds/koreader` and `.adds/nm` (or `.adds/kfmon`) at the top of the drive, not inside another folder. With KFMon, a Kobo update turns KFMon off: install it again.
- **It flashes and goes back to the Kobo's Home:** `.adds/koreader/crash.log` on the drive says why. Attach it to an [issue](https://github.com/9retirement6irk/GZreader/issues).
- **Something else:** quick panel → **Diagnostics** → **Send to the developer**, or *Save to the Kobo* and attach the file. → [Diagnostic log](Privacy-and-Diagnostics#diagnostic-log)

**What to send back** from a first try: which Kobo and firmware (Settings → Device information), whether it started, a photo if the screen looks wrong, and `.adds/koreader/crash.log`.
