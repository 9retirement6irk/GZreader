**Package:** `gzreader-kindlepw2-<version>.zip` — for touch Kindles from the Paperwhite 2 on, running firmware **5.6.1 – 5.16.2.x**: the **Paperwhite 3** (tested), and untested: Paperwhite 2, 4, 5, Voyage, Oasis 1–3, Kindle 2014, 2016, 2019, 2022. Built on KOReader's `kindlepw2` package.

On firmware **5.16.3 or newer** take the [`kindlehf` package](Install-Kindle-HF) instead: Amazon changed the system libraries there, and this one won't start. The firmware version is in **Settings → Device Options → Device Info**.

## 1. Jailbreak

Use the method kindlemodding.org's [Jailbreak Wizard](https://kindlemodding.org/jailbreak-wizard.html) names for your Kindle and firmware: [Jailbreaking and rooting → Paperwhite and newer](Jailbreaking-and-Rooting#paperwhite-and-newer-touch-kindles). Turn on airplane mode first. Kindles jailbroken with an older method (LanguageBreak, WatchThis…) should also have its hotfix and KUAL with MRPI.

## 2. Download

From the [latest release](https://github.com/9retirement6irk/GZreader/releases/latest), take `gzreader-kindlepw2-<version>.zip`.

## 3. Copy it to the Kindle

1. Connect the Kindle to the computer with USB; it shows up as a drive.
2. Unzip the package on the computer. Inside are the folders `koreader`, `extensions` and `documents` (with one file, `GZreader.sh`).
3. Copy those folders to the **top of the Kindle's drive**, merging with what's there (your books stay). If an old KOReader is installed, its `koreader` folder is replaced.
4. **Eject** the Kindle safely and unplug it.

## 4. Start GZreader

- Tap the **GZreader** item with GZreader's logo on the Kindle's home screen (`documents/GZreader.sh`, a scriptlet: modern jailbreaks run these; older ones with their hotfix).
- Or, with KUAL: **GZreader → Start GZreader**. If the home screen item is missing, starting from KUAL once puts it back.

The setup guide runs on the first start ([After installing](Installing#after-installing)), followed on touch Kindles by a short tour of the quick panel.

## Notes for these Kindles

- Touch throughout: tabs at the bottom, swipe down from the top for the quick panel (with a light slider), tap the sides to turn pages, swipe up for the page browser. → [Using GZreader → Touch Kindles](Using-GZreader#touch-kindles-kindle-touch-paperwhite-3)
- The Paperwhite has no speaker or headphone jack: audiobooks, music and read aloud aren't offered.
- The Kindle's own time zone is used.

Updating and uninstalling: [Updating and uninstalling](Updating-and-Uninstalling).
