**Package:** `gzreader-kindle-<version>.zip` — for the **Kindle 4** (5-way, no keyboard) and the **Kindle Touch**, and the Paperwhite 1 (untested). Built on KOReader's `kindle` package.

The [setup page](https://9retirement6irk.github.io/GZreader/setup/) does all of this for you, jailbreak included: it puts each file on the Kindle at the right step.

## 1. Jailbreak and install KUAL

- **Kindle 4:** [Jailbreaking and rooting → Kindle 4](Jailbreaking-and-Rooting#kindle-4)
- **Kindle Touch:** [Jailbreaking and rooting → Kindle Touch](Jailbreaking-and-Rooting#kindle-touch)
- **Paperwhite 1:** the method kindlemodding.org's [Jailbreak Wizard](https://kindlemodding.org/jailbreak-wizard.html) names for its firmware.

Turn on airplane mode first.

## 2. Download

From the [latest release](https://github.com/9retirement6irk/GZreader/releases/latest), take `gzreader-kindle-<version>.zip`.

## 3. Copy it to the Kindle

1. Connect the Kindle to the computer with USB; it shows up as a drive.
2. Unzip the package on the computer. Inside are the folders `koreader`, `extensions` and `documents` (with one file, `GZreader.sh`: the GZreader item on a touch Kindle's home screen).
3. Copy those folders to the **top of the Kindle's drive**, merging with any folders of the same name already there (your books in `documents` and KUAL's own `extensions` folder stay; GZreader adds `documents/GZreader.sh` and `extensions/koreader`). If an old KOReader is installed, its `koreader` folder is replaced.
4. **Eject** the Kindle safely and unplug it.

## 4. Start GZreader

- Open the **KUAL** book, then **GZreader → Start GZreader**. *Start GZreader (no framework)* stops the Kindle's own software while GZreader runs (more free memory; the Kindle restarts its home screen when you exit).
- **Kindle Touch:** if its jailbreak runs scriptlets, the **GZreader** item with GZreader's logo on the home screen starts it too. If it isn't there, start from KUAL once: GZreader puts it back.

The setup guide runs on the first start ([After installing](Installing#after-installing)).

## Notes for these Kindles

- **Kindle 4:** the 5-way, its centre button, Menu (the quick panel), Back and the page keys. Flash on every page turn is on by default. No audio. → [Using GZreader → Kindle 4](Using-GZreader#kindle-4-5-way)
- **Kindle Touch:** touch, like the Paperwhite; it has a speaker and headphone jack, so audiobooks, music and read aloud (*Listen* in the quick panel) work. → [Using GZreader → Touch Kindles](Using-GZreader#touch-kindles-kindle-touch-paperwhite-3)

Updating and uninstalling: [Updating and uninstalling](Updating-and-Uninstalling).
