**Package:** `gzreader-kindlehf-<version>.zip` — for any Kindle on firmware **5.16.3 or newer**: the **Paperwhite 3** (tested), and untested: Paperwhite 4, 5 and Signature Edition, Paperwhite 6, Kindle 2019, 2022, 2024, Oasis 3, Scribe, Colorsoft (shown in greys). Built on KOReader's `kindlehf` package (hard-float, for the newer system libraries).

On firmware 5.6.1 – 5.16.2.x take the [`kindlepw2` package](Install-Kindle-PW2) instead. The firmware version is in **Settings → Device Options → Device Info**.

## 1. Jailbreak

Use the method kindlemodding.org's [Jailbreak Wizard](https://kindlemodding.org/jailbreak-wizard.html) names for your Kindle and firmware: [Jailbreaking and rooting → Paperwhite and newer](Jailbreaking-and-Rooting#paperwhite-and-newer-touch-kindles). Newer firmware is patched against older methods, so check before updating a jailbroken Kindle: one updated past what any jailbreak handles can't be jailbroken until a new method comes out (and can't be downgraded without one).

## 2. Download

From the [latest release](https://github.com/9retirement6irk/GZreader/releases/latest), take `gzreader-kindlehf-<version>.zip`.

## 3. Copy it to the Kindle

1. Connect the Kindle to the computer with USB; it shows up as a drive.
2. Unzip the package on the computer. Inside are the folders `koreader`, `extensions` and `documents` (with one file, `GZreader.sh`).
3. Copy those folders to the **top of the Kindle's drive**, merging with what's there (your books stay). If an old KOReader is installed, its `koreader` folder is replaced.
4. **Eject** the Kindle safely and unplug it.

## 4. Start GZreader

- Tap the **GZreader** item with GZreader's logo on the Kindle's home screen (`documents/GZreader.sh`, a scriptlet, which the current jailbreaks run).
- Or, with KUAL: **GZreader → Start GZreader**.

The setup guide runs on the first start ([After installing](Installing#after-installing)), followed by a short tour of the quick panel.

## Notes for these Kindles

- Touch throughout. → [Using GZreader → Touch Kindles](Using-GZreader#touch-kindles-kindle-touch-paperwhite-3)
- Kindles with a frontlight get a light slider in the quick panel; those with a warm light (Paperwhite 5 and newer, Oasis 3, Scribe, Colorsoft) also a warmth slider, Cool to Warm. → [Using GZreader → Touch Kindles](Using-GZreader#touch-kindles-kindle-touch-paperwhite-3)
- These Kindles have no speaker or headphone jack (the newer ones play audio over Bluetooth only, which GZreader doesn't use): audiobooks, music and read aloud aren't offered.

Updating and uninstalling: [Updating and uninstalling](Updating-and-Uninstalling).
