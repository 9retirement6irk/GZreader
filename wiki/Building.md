For developers. More in [DEVELOPING.md](https://github.com/9retirement6irk/GZreader/blob/main/DEVELOPING.md) in the repository.

## Rebuild the package

```sh
tools/gzreader/package-kindle.sh koreader-kindle-legacy-v2026.07.1.zip out/   # Kindle 2, DX, 3
tools/gzreader/package-kindle.sh koreader-kindle-v2026.07.1.zip out/          # Kindle 4, Kindle Touch
tools/gzreader/package-kindle.sh koreader-kindlehf-v2026.07.1.zip out/        # touch, firmware 5.16.3+
tools/gzreader/package-kindle.sh koreader-kindlepw2-v2026.07.1.zip out/       # touch, firmware 5.6.1–5.16.2
```

The branch changes only Lua and shell scripts, so the script overlays it onto
the official release built from the same tag rather than rebuilding the
native toolchain.

It then precompiles every Lua file under `frontend/`, `plugins/` and
`common/` to LuaJIT bytecode with the release's own `luajit` (run through
`qemu-arm-static`; needs `qemu-user-static`, `libc6-armel-cross` and
`libgcc-s1-armel-cross`, or `libc6-armhf-cross` for the `kindlehf`
package; `GZ_LUAJIT` can name another package's `luajit` of the same
version instead: the bytecode is the same), keeping the `.lua` names and debug info (line
numbers, upvalue names, source paths), so loading skips parsing. Without
qemu it warns and ships source. `GZ_BYTECODE=0` turns it off.

## Publishing a release

Publishing an update is just making a GitHub release:

1. Bump `GZREADER_VERSION` and add an entry to
   `plugins/gzreader.koplugin/gzreader_changelog.lua`, push. Each line is
   `{ short = "…", text = "…" }`: `short` for the What's new screen (a few
   words), `text` for the changelog and the release notes.
2. On GitHub: Releases → Draft a new release → tag `v<version>` (for
   example `v1.0.4`; `v.1.0.4` also works) → Publish.

The "GZreader release packages" workflow then builds and attaches the full
installs (`gzreader-kindle-legacy-<version>.zip`,
`gzreader-kindle-<version>.zip`, `gzreader-kindlehf-<version>.zip`, `gzreader-kindlepw2-<version>.zip`) and
`gzreader-update.zip` (what every Kindle downloads, ~6 MB: Lua only, the same
for all of them). If a release has no
attached files, Kindles use the release's source code zip instead (~9 MB),
taking only `frontend/`, `reader.lua`, `koreader.sh` and the installed
plugins from it.
