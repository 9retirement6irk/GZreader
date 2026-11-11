**Package:** `gzreader-kindle-legacy-<version>.zip` — for the **Kindle 2**, **Kindle Keyboard (3)**, **Kindle DX** and **DX Graphite**. Built on KOReader's `kindle-legacy` package.

The [setup page](https://9retirement6irk.github.io/GZreader/setup/) does all of this for you, jailbreak included: it puts each file on the Kindle at the right step.

## 1. Jailbreak and install Launchpad

You need a jailbroken Kindle with Launchpad (or KUAL): [Jailbreaking and rooting → Kindle 2, 3, DX](Jailbreaking-and-Rooting#kindle-2-kindle-keyboard-3-dx-dx-graphite). Turn wireless off first (Menu → Turn Wireless Off; the Kindle 2 and DX have 3G instead of Wi‑Fi).

## 2. Download

From the [latest release](https://github.com/9retirement6irk/GZreader/releases/latest), take `gzreader-kindle-legacy-<version>.zip`.

## 3. Copy it to the Kindle

1. Connect the Kindle to the computer with USB; it shows up as a drive.
2. Unzip the package on the computer. Inside are the folders `koreader`, `extensions` and `launchpad`.
3. Copy those folders to the **top of the Kindle's drive**, merging with any folders of the same name already there (your books in `documents` and KUAL's own `extensions` folder stay; GZreader adds `extensions/koreader` and `launchpad/koreader.ini`). If an old KOReader is installed, its `koreader` folder is replaced.
4. **Eject** the Kindle safely and unplug it.

## 4. Start GZreader

- Restart the Kindle once (Menu → Settings → Menu → Restart) so Launchpad reads GZreader's shortcuts, then press **Shift, G, G** (the last book), **Shift, G, L** (the library) or **Shift, G, N** (without the Kindle's framework: more free memory, and the Kindle restarts its home screen when you exit).
- Or, with KUAL: open the **KUAL** book, then **GZreader → Start GZreader** (or *Start GZreader (no framework)*).

The setup guide runs on the first start ([After installing](Installing#after-installing)).

## Notes for these Kindles

- **Kindle 2 and DX have no Wi‑Fi:** GZreader notices and syncs through a web page on a computer instead, with the Kindle plugged in. → [Sync with a computer](Sync-with-a-Computer)
- **Keys:** a letter for everything, shown next to each entry; Menu opens the quick panel. → [Using GZreader](Using-GZreader#keyboard-kindle-2-3-dx)
- **Clock:** these Kindles keep UTC; set Settings → General → Time and date → Time zone.
- **Flash on every page turn** is on by default against ghosting (Settings → General → Screen refresh).
- **Audio:** audiobooks, Plex music and read aloud in the Kindle's own voice (Shift + Sym).
- **DX:** the bigger screen gets two shelves on Home and bigger books in Downloads.

Updating and uninstalling: [Updating and uninstalling](Updating-and-Uninstalling).
