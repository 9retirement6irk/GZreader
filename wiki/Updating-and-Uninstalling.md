## Updating

GZreader checks for a new release once a day (while Wi‑Fi is on) and offers it; or open **Settings → General → Software update**, or the quick panel → **Updates**. Updating keeps your books, settings, connections and reading progress, and a **What's new** screen shows what changed. Installing a newer package over USB the same way as the first time also works.

- **Kindle 2 and DX** (no Wi‑Fi): the [sync page](Sync-with-a-Computer) brings new versions with the sync.
- **Nooks:** over Wi‑Fi as on a Kindle; a new KOReader version needs the full package pushed again.
- **Kobos:** over Wi‑Fi as on a Kindle (the update brings the Kobo's own start script); a new KOReader version needs the full package unzipped again.
- **Test builds:** Settings → General → Software update → **Test builds** gets changes before they're released.

More: [Updates and test builds](Updates-and-Test-Builds).

## Resetting GZreader

**Settings → General → Transfer or reset → Reset GZreader** (the last item) puts GZreader back to how it was when you installed it, without reinstalling. It asks first. Then:

- every setting goes back to its default, and your reading statistics are removed;
- everything GZreader downloaded is removed: `GZreader/books`, `music`, `audiobooks` and `notes` are emptied, and the sync page's saved keys and reports go (`GZreader/app`, GZreader itself, stays);
- every account is forgotten on this device: Grimmory, Plex, Memos, calendars, Home Assistant, Immich. Nothing is signed out on the servers, so your other devices stay signed in;
- GZreader restarts and the setup guide opens, as on the first start.

Changes not sent yet (reading progress, notes made without Wi‑Fi) are lost. Books outside the GZreader folder (for example in `documents`), the diagnostic log and the device's Wi‑Fi networks stay.

## Uninstalling

**Kindles:** delete `GZreader/app`, `extensions/gzreader`, `launchpad/gzreader.ini` (Kindle 2/3/DX) and `documents/GZreader.sh` (Kindle 4 and newer). Your books, music, audiobooks and notes (`GZreader/books`, `music`, `audiobooks`, `notes`) stay until you delete the whole **GZreader** folder. KOReader, if you have it, isn't touched.

**Kobos:** delete `GZreader/app`, `.adds/nm/gzreader`, `.adds/kfmon/config/gzreader.ini` and `gzreader.png`. Your books, music, audiobooks and notes stay until you delete the whole **GZreader** folder. KOReader (`.adds/koreader`), if you have it, isn't touched. Sign-ins kept on the Kobo's own disk go with Reset GZreader (do it before deleting), or with the next Kobo update.

**Nook 1st Edition:** remove the icon's helper and app first (`adb shell sh /data/gzreader/launcher.sh uninstall`, `adb uninstall gzreader.nook.launcher`), then `adb shell rm -r /data/gzreader`, and on the microSD card (or the Nook's own storage) the `GZreader/app` folder (`.gzreader-app` before 1.35). The rest of the `GZreader` folder (books, music, audiobooks, notes) stays until you delete it.

**Nook Simple Touch:** `adb shell rm -r /data/gzreader`, and the `GZreader/app` folder (`.gzreader-app` before 1.35) on the card or the NOOK drive.

Neither Nook's system is changed for good by running GZreader: restarting the Nook always brings back its own software.
