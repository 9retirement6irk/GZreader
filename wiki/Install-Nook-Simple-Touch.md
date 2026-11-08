**Package:** `gzreader-nook-<version>.zip` — for the **Nook Simple Touch** and the **Simple Touch with GlowLight** (2011–2012). **A test build** that has only been tried in GZreader's emulator so far: try it on a Nook you're prepared to restore, and send back what happens. How to use it: [Nook Simple Touch](Nook-Simple-Touch).

You need: the Nook rooted with adb working ([Jailbreaking and rooting → Nook Simple Touch](Jailbreaking-and-Rooting#nook-simple-touch)), a computer with [Android's platform tools](https://developer.android.com/tools/releases/platform-tools) (adb). Download `gzreader-nook-<version>.zip` from the [latest release](https://github.com/9retirement6irk/GZreader/releases/latest) and unzip it: you get a folder, `gzreader`.

## Root, install, start

1. Root it with **NookManager** (a bootable microSD card image; firmware
   1.2.x): back up the Nook with it first, then root. Guides:
   [NookManager on XDA](https://forum.xda-developers.com/t/root-nookmanager-graphical-rooter-for-1-2-x-and-beyond.2040351/),
   [a 2023 walkthrough](https://storiesofmaria.blogspot.com/2023/03/root-nook-simple-touch-with-updated.html).
2. Connect adb (over USB, or Wi‑Fi: `adb connect <the Nook's IP>`) and
   check that `adb shell id` says root (or that `su` works).
3. Install as for the 1st Edition: `adb push gzreader /data/gzreader`.
   GZreader's folder, `GZreader`, goes on the **microSD card** when one is
   in, else on the Nook's own storage (the **NOOK** drive over USB). As on
   the 1st Edition, the first start moves what GZreader only reads (about
   55 MB) out of the Nook's small app storage to the same place.
4. Start: `adb shell sh /data/gzreader/gzreader.sh`, or
   `su -c "sh /data/gzreader/gzreader.sh"` in a terminal app. Exit to Nook in the
   quick panel brings back the Nook's own software (press **n** if its
   screen doesn't redraw by itself).

Send back the same logs as for the 1st Edition, and a photo if the screen
looks wrong.
