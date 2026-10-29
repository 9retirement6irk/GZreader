-- GZreader changelog, newest first. Shown in Settings → Updates → Changelog.
-- Add an entry (and bump GZREADER_VERSION) for every release.
return {
    {
        version = "1.0.3",
        changes = {
            "Updates work with any GitHub release: the Kindle uses the attached gzreader-update.zip, or else the release's source code zip (nothing to upload). Tags like v.1.0.2 are understood.",
            "Settings → Updates is GZreader's updater, with this changelog (no more ZenOS updater or ZenOS changelog).",
            "New GZreader logo (setup guide, settings, sleep fallback).",
            "Read aloud on the Kindle 3 through the Kindle's own lipc-hash-prop tool; the voice test only offers ways the speech service accepted.",
            "Bottom tabs: Alt + Q, W, E, R, T (the Kindle Keyboard has no number row).",
            "Setup guide: sleep-screen option no longer cut off.",
        },
    },
    {
        version = "1.0.0",
        changes = {
            "First GZreader release: Grimmory + ZenOS + KOReader for the Kindle Keyboard.",
            "QR / SSO sign-in, Grimmory library browser (Libraries, Authors, Series, no audiobooks), background downloads.",
            "Native progress sync and two-way bookmark sync with Grimmory, offline queue.",
            "Reading menu on the Menu key, read aloud with Shift + Sym, book-cover / screensavers-folder sleep screen.",
            "Speed fixes for the Kindle 3, English dictionary, diagnostic log.",
        },
    },
}
