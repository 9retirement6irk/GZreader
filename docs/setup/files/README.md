# Files the setup page puts on a Kindle

The setup page (`docs/setup/`) copies these to a Kindle's drive at the right
step. They are other people's work, kept here unchanged so the page can use
them (a web page can't download them from where they're published). Each is
here only because its licence allows passing it on; files without a licence
are not kept here: the page links to them and checks the file you download.

| Folder | What | Version | From | Licence |
|---|---|---|---|---|
| `jailbreak-0.13.N/` | NiLuJe's jailbreak for the Kindle 2, DX, DX Graphite and Kindle Keyboard (`Update_jailbreak_<model>_install.bin`; `_3.0-to-3.2_` for a Kindle Keyboard on firmware 3.2 or older) | 0.13.N (r18833) | [NiLuJe's snapshots, MobileRead](https://www.mobileread.com/forums/showthread.php?t=225030), as kept by [kindlemodding.org](https://github.com/KindleModding/kindlemodding.github.io/tree/main/content/jailbreaking/Legacy/K2DXDXGK3-Jailbreak) | Permissive, `LICENSE.txt` (the package's README) |
| `hotfix/` | The Universal Hotfix (`Update_hotfix_universal.bin`): keeps a jailbreak through updates and shows `.sh` scriptlets in the library | v3.4.0 | [KindleModding/Hotfix](https://github.com/KindleModding/Hotfix) (source there) | GPL-3.0, `LICENSE.txt` |
| `winterbreak/` | WinterBreak (`WinterBreak.tar.gz`), Hackerdude's jailbreak through the Kindle Store, with Mesquito | v2.1.0 | [KindleModding/WinterBreak](https://github.com/KindleModding/WinterBreak) (source there), [KindleModding/Mesquito](https://github.com/KindleModding/Mesquito) | WinterBreak GPL-3.0 (`LICENSE-WinterBreak.txt`, also inside the archive); Mesquito MIT (`LICENSE-Mesquito.txt`) |
| `kual-dx-fix/` | KUAL 2.7.37 re-signed for the Kindle DX/DX Graphite (and Kindle 2), a non-expiring developer keystore, its install/undo scripts and Launchpad shortcuts | 2026-11 | [9retirement6irk/kual-dx-fix](https://github.com/9retirement6irk/kual-dx-fix) (KUAL by ixtab, NiLuJe, twobob and stepk) | The repository owner's, GZreader's maintainer |

The keystore in `kual-dx-fix/` has its private keys published with it
(password `password`), like the original Kindle developer keys: anyone can
sign Kindlets a Kindle with it will trust. See that repository's README.

Linked, not kept here (no licence that allows passing them on): the Kindle 4
jailbreak, the Kindle Touch (K5) jailbreak, WinterBreak2, KUAL, Launchpad and
NiLuJe's 2025 developer keys (MKK). The page names each file and checks what
you drop on it before copying.

When updating a file here, change the version in this table and the size and
SHA-256 in `docs/setup/setup.js` (`BUNDLED`); `setup_page_test.py` checks them.
