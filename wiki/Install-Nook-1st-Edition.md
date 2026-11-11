**Package:** `gzreader-nook-1st-edition-<version>.zip` — for Barnes & Noble's **Nook 1st Edition** (2009), the one with a small colour touchscreen under the e-ink page. **A test build:** it runs on a real Nook (firmware 1.0.0 with nookDevs' Softroot 2.5.1); try it on a Nook you're prepared to restore. How it works and how to use it: [Nook 1st Edition](Nook-1st-Edition).

Not `gzreader-nook-<version>.zip`: that one is for the [Nook Simple Touch](Install-Nook-Simple-Touch).

You need: the Nook rooted with adb working (below, or [Jailbreaking and rooting → Nook 1st Edition](Jailbreaking-and-Rooting#nook-1st-edition)), a computer with [Android's platform tools](https://developer.android.com/tools/releases/platform-tools) (adb), a USB cable, and preferably a microSD card in the Nook.

## Root the Nook

GZreader needs root (to pause the Nook's software and reach the screens),
which on this Nook means a community rooting method. Read the guide for
yours in full first, charge the battery, and back up your books.

1. Find the serial number (Settings → About your nook, or under the back
   cover). **It decides the method:** methods for older Nooks can brick
   newer hardware.
2. Serial **below 1003**: nookDevs' [Softroot](https://nookdevs.com/Softroot)
   (an update file on a microSD card; adds ADB over USB).
3. Serial **1003 or above** (firmware 1.4.1 and later): nookDevs'
   [Rooting New Hardware](https://nookdevs.com/Rooting_New_Hardware), or the
   newer browser-based method in [Rooting the Barnes & Noble Nook 1st
   Generation](https://letsdecentralize.org/tutorials/root-nook.html) (ADB
   over Wi‑Fi).
4. Install [Android's platform tools](https://developer.android.com/tools/releases/platform-tools)
   (adb) on your computer and check that `adb shell id` says `uid=0(root)`.

## Install

1. Download **`gzreader-nook-1st-edition-<version>.zip`** from the
   [releases](https://github.com/9retirement6irk/GZreader/releases) and
   unzip it on your computer: you get a folder, `gzreader`. (Not
   `gzreader-nook-<version>.zip`: that one is built for the Kindle 2/3/DX's
   floating-point unit, which the Nook 1st Edition's kernel doesn't turn on
   (`/proc/cpuinfo` has no `vfp`), so it stops at once with exit code 132.
   The 1st Edition package is KOReader's programs rebuilt to do floating
   point in software: `.github/workflows/gzreader-nook.yml`.)
2. Check there's room (about 90 MB, for the first start) in the Nook's
   app storage: `adb shell df /data`.
3. Copy it there (the Nook's USB storage can't run programs):

   ```
   adb push gzreader /data/gzreader
   ```

4. Copy books to the Nook as usual over USB. GZreader keeps its folder,
   `GZreader` (books, audiobooks, what it downloads), on the **microSD card**
   when one is in (more room), else on the Nook's own storage next to B&N's
   `my documents`. A card put in later: GZreader uses it from its next
   start (books already in the Nook's own `GZreader` folder stay there:
   move them over USB). To choose yourself:
   `adb shell "GZ_NOOK_HOME=/system/media/sdcard sh /data/gzreader/gzreader.sh"`.
   (Take `bravo_update.dat` off the card after rooting: holding the page
   button while turning the Nook on would install it again.)
5. **GZreader moves most of itself out of the Nook's app storage** at its
   first start (a minute or two, with the Nook's own screen still showing).
   That storage is about 240 MB, shared with Android, and it filled up: an
   update couldn't unpack. What GZreader only reads (its Lua code, fonts,
   hyphenation, translations, about 55 MB) and its cache go to
   `.gzreader-app` on the microSD card when one is in, else on the Nook's
   own storage. They're mounted back into `/data/gzreader/koreader` while
   GZreader runs, so nothing else changes. Its programs and libraries
   (the card can't run them) and its settings and reading history (so a
   card swap can't lose them) stay in `/data/gzreader`, about 30 MB.
   - Leave the card in: without it GZreader says to put it back and
     doesn't start.
   - A full package pushed over it later is moved again at the next start.
   - To keep everything in `/data/gzreader` (and bring it back):
     `adb shell touch /data/gzreader/app-here`, then start GZreader.

## Start and exit

- **On the Nook: GZreader's icon** in the app list (the launcher Softroot
  installs). Set it up once, with the Nook connected to the computer:

  ```
  adb install gzreader/GZreader-launcher.apk
  adb shell sh /data/gzreader/launcher.sh install
  ```

  Starting GZreader needs root, which an app can't have on this Nook (its
  `su` only works for adb), so the second line sets up a small helper that
  runs as root and starts GZreader when the icon asks: it adds one line to
  the Nook's start-up script `/system/etc/bravo_pltinfo.sh` (so the helper
  starts with the Nook) and starts it now. Tapping the icon twice starts
  GZreader once. To undo it: `adb shell sh /data/gzreader/launcher.sh uninstall`
  and `adb uninstall gzreader.nook.launcher`. A newer icon app: uninstall
  the old one first (each build is signed with its own key).
- From the computer: `adb shell sh /data/gzreader/gzreader.sh`

GZreader starts with its setup guide, as on a Kindle. To go back to the
Nook's own software, choose **Exit to Nook** in the quick panel (Menu on the
colour screen). If anything goes wrong, holding power to restart the Nook
always brings back its own software.


## Updating

Once installed, the Nook updates over Wi‑Fi like a Kindle (Settings → General → Updates), from the same `gzreader-update.zip`; its start script comes with the update. A new KOReader version still needs the full package pushed again. → [Updates and test builds](Updates-and-Test-Builds)

## What to send back

`/data/gzreader/gzreader-start.log`, `/data/gzreader/koreader/crash.log` and `/data/gzreader/koreader/gzreader.log` (`adb pull` each), with what you saw on both screens. And the touch test's numbers if the touch was off.
