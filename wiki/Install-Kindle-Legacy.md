**Package:** `gzreader-kindle-legacy-<version>.zip` — for the **Kindle 2**, **Kindle Keyboard (3)**, **Kindle DX** and **DX Graphite**. Built on KOReader's `kindle-legacy` package.

## 1. Jailbreak and install KUAL

You need a jailbroken Kindle with KUAL: [Jailbreaking and rooting → Kindle 2, 3, DX](Jailbreaking-and-Rooting#kindle-2-kindle-keyboard-3-dx-dx-graphite). Turn on airplane mode first (the Kindle 2 and DX have no Wi‑Fi to turn off).

## 2. Download

From the [latest release](https://github.com/9retirement6irk/GZreader/releases/latest), take `gzreader-kindle-legacy-<version>.zip`.

## 3. Copy it to the Kindle

1. Connect the Kindle to the computer with USB; it shows up as a drive.
2. Unzip the package on the computer. Inside are the folders `koreader`, `extensions` and `launchpad`.
3. Copy those folders to the **top of the Kindle's drive**, merging with any folders of the same name already there (your books in `documents` and KUAL's own `extensions` folder stay; GZreader adds `extensions/koreader` and `launchpad/koreader.ini`). If an old KOReader is installed, its `koreader` folder is replaced.
4. **Eject** the Kindle safely and unplug it.

## 4. Start GZreader

- Open the **KUAL** book, then **GZreader → Start GZreader**. *Start GZreader (no framework)* stops the Kindle's own software while GZreader runs: more free memory, and the Kindle restarts its home screen when you exit.
- Or press **Shift, G, G** (the last book), **Shift, G, L** (the library) or **Shift, G, N** (without the Kindle's framework): the launchpad shortcuts.

The setup guide runs on the first start ([After installing](Installing#after-installing)).

## Notes for these Kindles

- **Kindle 2 and DX have no Wi‑Fi:** GZreader notices and syncs through a web page on a computer instead, with the Kindle plugged in. → [Sync with a computer](Sync-with-a-Computer)
- **Keys:** a letter for everything, shown next to each entry; Menu opens the quick panel. → [Using GZreader](Using-GZreader#keyboard-kindle-2-3-dx)
- **Clock:** these Kindles keep UTC; set Settings → General → Time zone.
- **Flash on every page turn** is on by default against ghosting (Settings → Reader → Appearance).
- **Audio:** audiobooks, Plex music and read aloud in the Kindle's own voice (Shift + Sym).
- **DX:** the bigger screen gets two shelves on Home and bigger books in Downloads.

Updating and uninstalling: [Updating and uninstalling](Updating-and-Uninstalling).
