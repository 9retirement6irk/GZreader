GZreader runs next to the device's own software, so a Kindle has to be **jailbroken** (allowed to run software Amazon didn't sign) and a Nook **rooted**. Neither is done by GZreader: these are community methods, and the guides linked below are where they're kept up to date. Read the guide for your device in full first, charge the battery, and back up your books.

> Jailbreaking and rooting are at your own risk. Methods change as firmware changes: when this page and the linked guide disagree, follow the guide.

## Kindles

**The easy way: the [setup page](https://9retirement6irk.github.io/GZreader/setup/)** (Chrome or Edge on a computer, the Kindle plugged in). It tells the model from the serial number, picks the jailbreak for its firmware, puts each file on the Kindle's drive at the right step (the jailbreak, Launchpad, KUAL, the hotfix, WinterBreak's hidden folder…), checks the drive where a step leaves something to see, and ends by installing the right GZreader package. A Kindle that's already jailbroken goes straight to GZreader. Some files it carries itself (the ones whose licence allows it: NiLuJe's Kindle 2/DX/3 jailbreak, the Universal Hotfix, WinterBreak, the KUAL fix for the DX); for the others it links the exact file and checks the one you drop on it. The steps below are the same, by hand.

**Before anything:** turn on **airplane mode**, so the Kindle doesn't update itself to a firmware the jailbreak can't handle (kindlemodding.org also suggests [filling the storage](https://kindlemodding.org/jailbreaking/prevent-auto-update/) to block updates until the jailbreak is in). Find the firmware version in **Settings → Device Options → Device Info** (older Kindles: Menu → Settings).

[kindlemodding.org](https://kindlemodding.org/jailbreaking/) lists the current methods; its **[Jailbreak Wizard](https://kindlemodding.org/jailbreak-wizard.html)** picks the one for your Kindle from its serial number and firmware. A Kindle can't be downgraded without a jailbreak, and a firmware that's been patched against every method has to wait for a new one.

### Kindle 2, Kindle Keyboard (3), DX, DX Graphite

1. [NiLuJe's K2/DX/DXG/K3 jailbreak](https://kindlemodding.org/jailbreaking/Legacy/K2DXDXGK3-Jailbreak/): copy its `Update_jailbreak_….bin` for your model to the Kindle (delete any other `.bin` or `update.bin.tmp.partial` files there), eject, then **Home → Menu → Settings → Menu → Update Your Kindle**. Error U006 on firmware 2.x is expected (it worked; don't run it again). Kindle Keyboard: the `_3.0-to-3.2_` file is for firmware **3.2 and older only**; 3.2.1 and newer take the other one (NiLuJe's README; kindlemodding.org's table gives 3.2.1 the wrong one).
2. **Launchpad** (`update_launchpad_0.0.1d_<model>_install.bin` from `lpad-pkg-001d.zip`, [MobileRead](https://www.mobileread.com/forums/showthread.php?p=1155117)): copy it to the Kindle and run **Update Your Kindle** again. Press Shift three times: a `screenshot.bmp` on the drive means it's running. GZreader starts from Launchpad (**Shift, G, G**), so these Kindles don't need KUAL.
3. **KUAL (optional):** since the developer keys expired in April 2025, the usual KUAL doesn't open on a Kindle 2/DX ("not signed by a registered developer"), and may not on a Kindle Keyboard. On a DX or DX Graphite use the [KUAL DX fix](https://github.com/9retirement6irk/kual-dx-fix) (re-signed KUAL, keys that don't expire; Shift, K, I installs them).

Then: [install the `kindle-legacy` package](Install-Kindle-Legacy).

### Kindle 4

1. [NiLuJe's K4 jailbreak](https://kindlemodding.org/jailbreaking/Legacy/K4-Jailbreak/): copy its three files (`data.tar.gz`, `ENABLE_DIAGS`, `diagnostic_logs`) to the Kindle — not the `…_uninstall.bin` in the same zip, which the next Update Your Kindle would install — eject, restart it (Menu → Settings → Menu → Restart) into diagnostics mode, then with the 5-way: **D) Exit, Reboot or Disable Diags → R) Reboot System → Q) To continue**. A "You are Jailbroken" book appears.
2. **New developer keys:** the ones the jailbreak installs expired in April 2025. Install NiLuJe's 2025 keys (`Update_mkk-…-install.bin` from the MKK package in [his snapshots](https://www.mobileread.com/forums/showthread.php?t=225030)) with **Update Your Kindle**.
3. **KUAL:** `KUAL-KDK-1.0.azw2` (2.7.37, April 2025, or newer) in `documents` ([Installing KUAL & MRPI](https://kindlemodding.org/jailbreaking/Legacy/post-jailbreak/installing-kual-mrpi/)).

Then: [install the `kindle` package](Install-Kindle).

### Kindle Touch

1. [NiLuJe's K5 jailbreak](https://kindlemodding.org/jailbreaking/Legacy/K5-Jailbreak/): copy the files from its zip to the top of the Kindle's drive, eject, then **Home → Menu → Settings → Menu → Update Your Kindle**; "**** JAILBREAK ****" shows at the bottom of the screen when it's done. Restarting the Kindle afterwards is recommended.
2. **KUAL and MRPI:** [Installing KUAL & MRPI](https://kindlemodding.org/jailbreaking/Legacy/post-jailbreak/installing-kual-mrpi/) (KUAL's `KUAL.sh` and `KUAL.jar`, and MRPI's `extensions` and `mrpackages` folders); also [a hotfix](https://kindlemodding.org/jailbreaking/Legacy/post-jailbreak/setting-up-a-hotfix/) so a firmware update doesn't undo the jailbreak.

Then: [install the `kindle` package](Install-Kindle).

### Paperwhite and newer touch Kindles

Use the method the **[Jailbreak Wizard](https://kindlemodding.org/jailbreak-wizard.html)** names for your Kindle and firmware. For example [WinterBreak](https://kindlemodding.org/jailbreaking/WinterBreak/) works on firmware below 5.18.1 (it runs from the Kindle Store, with Wi‑Fi briefly on); older firmware has older methods (LanguageBreak, WatchThis, Popcorn for the PW2/PW3…, under kindlemodding.org's Legacy section, with a [hotfix](https://kindlemodding.org/jailbreaking/Legacy/post-jailbreak/setting-up-a-hotfix/) and [KUAL & MRPI](https://kindlemodding.org/jailbreaking/Legacy/post-jailbreak/installing-kual-mrpi/)).

The current jailbreaks block updates themselves and run *scriptlets* (`.sh` files in `documents`, shown as books): GZreader's package brings one, `documents/GZreader.sh`, so nothing else is needed.

Then: [`kindlepw2`](Install-Kindle-PW2) (firmware 5.6.1 – 5.16.2.x) or [`kindlehf`](Install-Kindle-HF) (5.16.3 or newer).

## Nooks

GZreader needs root on a Nook (to pause the Nook's software and reach its screens), and adb to install it: [Android's platform tools](https://developer.android.com/tools/releases/platform-tools) on your computer.

### Nook 1st Edition

1. Find the serial number (Settings → About your nook, or under the back cover). **It decides the method:** methods for older Nooks can brick newer hardware.
2. Serial **below 1003**: nookDevs' [Softroot](https://nookdevs.com/Softroot) (an update file on a microSD card; adds adb over USB). GZreader has been run on a Nook with firmware 1.0.0 and Softroot 2.5.1.
3. Serial **1003 or above** (firmware 1.4.1 and later): nookDevs' [Rooting New Hardware](https://nookdevs.com/Rooting_New_Hardware), or the newer browser-based method in [Rooting the Barnes & Noble Nook 1st Generation](https://letsdecentralize.org/tutorials/root-nook.html) (adb over Wi‑Fi).
4. Check that `adb shell id` says `uid=0(root)`.
5. Take `bravo_update.dat` off the card afterwards: holding the page button while turning the Nook on would install it again.

Then: [install the `nook-1st-edition` package](Install-Nook-1st-Edition).

### Nook Simple Touch

1. Root it with **NookManager** (a bootable microSD card image; firmware 1.2.x): back up the Nook with it first, then root. Guides: [NookManager on XDA](https://forum.xda-developers.com/t/root-nookmanager-graphical-rooter-for-1-2-x-and-beyond.2040351/), [a 2023 walkthrough](https://storiesofmaria.blogspot.com/2023/03/root-nook-simple-touch-with-updated.html).
2. Connect adb (over USB, or Wi‑Fi: `adb connect <the Nook's IP>`) and check that `adb shell id` says root (or that `su` works).

Then: [install the `nook` package](Install-Nook-Simple-Touch).
