## Updating

GZreader checks for a new release once a day (while Wi‑Fi is on) and offers it; or open **Settings → General → Updates**, or the quick panel → **Updates**. Updating keeps your books, settings, connections and reading progress, and a **What's new** screen shows what changed. Installing a newer package over USB the same way as the first time also works.

- **Kindle 2 and DX** (no Wi‑Fi): the [sync page](Sync-with-a-Computer) brings new versions with the sync.
- **Nooks:** over Wi‑Fi as on a Kindle; a new KOReader version needs the full package pushed again.
- **Test builds:** Settings → General → Updates → **Test builds** gets changes before they're released.

More: [Updates and test builds](Updates-and-Test-Builds).

## Resetting GZreader

**Settings → About → Advanced → Reset GZreader** (the last item) puts GZreader back to how it was when you installed it, without reinstalling. It asks first. Then:

- every setting goes back to its default, and your reading statistics are removed;
- everything GZreader downloaded is removed: the **GZreader** folder is emptied (books, audiobooks, music, and the sync page's saved keys and reports);
- every account is forgotten on this device: Grimmory, Plex, Memos, calendars, Home Assistant, Immich. Nothing is signed out on the servers, so your other devices stay signed in;
- GZreader restarts and the setup guide opens, as on the first start.

Changes not sent yet (reading progress, notes made without Wi‑Fi) are lost. Books outside the GZreader folder (for example in `documents`), the diagnostic log and the device's Wi‑Fi networks stay.

## Uninstalling

**Kindles:** delete the `koreader` folder, `extensions/koreader`, `launchpad/koreader.ini` (Kindle 2/3/DX) and `documents/GZreader.sh` (Kindle 4 and newer). The **GZreader** folder with your books stays until you delete it.

**Nook 1st Edition:** remove the icon's helper and app first (`adb shell sh /data/gzreader/launcher.sh uninstall`, `adb uninstall gzreader.nook.launcher`), then `adb shell rm -r /data/gzreader`, and on the microSD card (or the Nook's own storage) the `.gzreader-app` folder. The `GZreader` folder with your books stays until you delete it.

**Nook Simple Touch:** `adb shell rm -r /data/gzreader`, and the `.gzreader-app` folder on the card or the NOOK drive.

Neither Nook's system is changed for good by running GZreader: restarting the Nook always brings back its own software.
