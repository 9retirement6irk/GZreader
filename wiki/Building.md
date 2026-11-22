For developers. More in [DEVELOPING.md](https://github.com/9retirement6irk/GZreader/blob/main/DEVELOPING.md) in the repository.

## Rebuild the package

```sh
tools/gzreader/package-kindle.sh koreader-kindle-legacy-v2026.07.1.zip out/   # Kindle 2, DX, 3
tools/gzreader/package-kindle.sh koreader-kindle-v2026.07.1.zip out/          # Kindle 4, Kindle Touch
tools/gzreader/package-kindle.sh koreader-kindlehf-v2026.07.1.zip out/        # touch, firmware 5.16.3+
tools/gzreader/package-kindle.sh koreader-kindlepw2-v2026.07.1.zip out/       # touch, firmware 5.6.1–5.16.2
tools/gzreader/package-kobo.sh koreader-kobo-v2026.07.1.zip out/              # Kobos (.adds/koreader, NickelMenu, KFMon)
```

The steps both scripts share (the overlay, dictionary, trimming, bytecode) are
in `tools/gzreader/package-common.sh`. The update package comes from
`package-kindle.sh` and is the same for every device: it carries the Kobo's
start script as `koreader/kobo-koreader.sh` (a Kobo installs it as its
`koreader.sh`) and keeps KOReader's Kobo device code.

The branch changes only Lua and shell scripts, so the script overlays it onto
the official release built from the same tag rather than rebuilding the
native toolchain.

It then precompiles every Lua file under `frontend/`, `plugins/` and
`common/` to LuaJIT bytecode with the release's own `luajit` (run through
`qemu-arm-static`; needs `qemu-user-static`, `libc6-armel-cross` and
`libgcc-s1-armel-cross`, or `libc6-armhf-cross` for the `kindlehf`
and `kobo` packages; `GZ_LUAJIT` can name another package's `luajit` of the same
version instead: the bytecode is the same), keeping the `.lua` names and debug info (line
numbers, upvalue names, source paths), so loading skips parsing. Without
qemu it warns and ships source. `GZ_BYTECODE=0` turns it off.

## Publishing a release

Publishing an update is just making a GitHub release:

1. Set `GZREADER_VERSION` to the day's version and add an entry to
   `plugins/gzreader.koplugin/gzreader_changelog.lua` with that version, push.
   Releases are named for the day they're made, as **year.month.day** with
   two-digit months and days: `2026.11.21`. A second release on the same day
   adds `.2` (`2026.11.21.2`), a third `.3`.
   `tools/gzreader/next-version.py` prints the right one (the day in New
   York, counting the tags already made); `--write` puts it in
   `GZREADER_VERSION`. Each changelog line is
   `{ short = "…", text = "…" }`: `short` for the What's new screen (a few
   words), `text` for the changelog and the release notes.
2. On GitHub: Releases → Draft a new release → tag `v<version>` (for
   example `v2026.11.21`) → Publish.

Versions up to 1.35.0 were numbered (`1.35.0`); the first one named by date
comes after them, since every version is compared number by number
(2026 > 1). Test builds are `<version>-beta.<commit>` as before, for
example `2026.11.21-beta.d6819bd`, and come before that day's release.

The "GZreader release packages" workflow then builds and attaches the full
installs (`gzreader-kindle-legacy-<version>.zip`,
`gzreader-kindle-<version>.zip`, `gzreader-kindlehf-<version>.zip`, `gzreader-kindlepw2-<version>.zip`,
`gzreader-kobo-<version>.zip`) and
`gzreader-update.zip` (what every Kindle downloads, ~6 MB: Lua only, the same
for all of them). If a release has no
attached files, Kindles use the release's source code zip instead (~9 MB),
taking only `frontend/`, `reader.lua`, `koreader.sh` and the installed
plugins from it.
