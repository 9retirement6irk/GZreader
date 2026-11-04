# Developing GZreader

For people changing GZreader itself. Using it: [README](README.md), [the full guide](GZREADER.md).

## Publishing a release

1. Bump [`GZREADER_VERSION`](GZREADER_VERSION) and add an entry to
   [`gzreader_changelog.lua`](plugins/gzreader.koplugin/gzreader_changelog.lua).
2. Create a GitHub release tagged `v<version>` and publish it.

The [release workflow](.github/workflows/gzreader-release.yml) builds and attaches the
install zip and the update package. Kindles check for new releases once a day.

To build locally:

```sh
tools/gzreader/package-kindle.sh koreader-kindle-legacy-v2026.07.1.zip out/   # or koreader-kindle-…, koreader-kindlehf-…, koreader-kindlepw2-…
```

The build reuses the native binaries of the official KOReader kindle-legacy release of
the same version and overlays GZreader's Lua code, plugins and dictionary.

## Tests and keeping up with KOReader and ZenOS

- **Tests** ([workflow](.github/workflows/gzreader-tests.yml), on every push and pull
  request, and on every upstream merge): luacheck, the plugin's tests against mock
  Grimmory, Memos and CalDAV servers, the setup guide, the Nooks' screen commands; that
  GZreader's changes to KOReader's and ZenOS's files are all still there
  ([`keeps.py`](tools/gzreader/tests/keeps.py)); and GZreader running in the emulator
  on a Kindle 3, Kindle 4, Kindle Touch, Paperwhite 3, Nook 1st Edition and Nook Simple
  Touch, checking what makes it GZreader
  ([`keeps.lua`](tools/gzreader/emulator/keeps.lua)): the setup guide, Home's tabs, the
  GZreader and Reading menus and their names (and the Menu key, never ZenOS's touch panel
  without touch), Settings' Connections, the touch launcher's entries at Home and in a
  book, the Kindle Touch's Listen, the Nook's colour screen, picture books filling the
  screen, pages turning, and menu text between 2.2 and 3.8 mm tall on the real screen. Locally: `tools/gzreader/ci-test.sh koreader-kindle-legacy-vX.zip out/`
  (Linux, with qemu), or just the tests: `tools/gzreader/tests/run.sh <unzipped koreader/>`.
- **Upstream check** ([workflow](.github/workflows/gzreader-upstream.yml), Mondays, or by
  hand from the Actions tab): compares [`tools/gzreader/UPSTREAM`](tools/gzreader/UPSTREAM)
  with KOReader's newest release that has Kindle packages and ZenOS's newest release. For
  each newer one it merges what changed upstream into GZreader
  ([`upstream.sh`](tools/gzreader/upstream.sh): three-way, keeping GZreader's changes;
  what GZreader removed stays removed) and runs the tests on the result. A clean merge
  becomes a **pull request** (a draft if a test failed) with the report and test results;
  conflicts become an **issue** listing them, with the merge as a patch. Run by hand it can
  include ZenOS pre-releases, or preview a KOReader branch such as `master` (report only).
  It needs *Settings → Actions → General → Allow GitHub Actions to create and approve pull
  requests*.
- Locally: `tools/gzreader/upstream.sh latest zenos --pre`,
  `tools/gzreader/upstream.sh merge zenos v4.3.0` (then resolve any `<<<<<<<`, test).

## What's inside

| Part | Role |
| --- | --- |
| [`plugins/gzreader.koplugin`](plugins/gzreader.koplugin) | GZreader itself: Grimmory sign-in, browser, downloads, progress, bookmark and highlight sync, Reading menu, read aloud, updater |
| [`plugins/zenos.koplugin`](plugins/zenos.koplugin) | ZenOS 4.2.0 interface, adapted for GZreader and the Kindle keyboard |
| `frontend/`, `reader.lua` | KOReader v2026.07.1 with GZreader changes (branding, keyboard, sleep screen, speed fixes) |
| [`tools/grimmory`](tools/grimmory) | Packaging, dictionary builder, release script |

