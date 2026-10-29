-- GZreader changelog, newest first. Shown in Settings → Updates → Changelog.
-- Add an entry (and bump GZREADER_VERSION) for every release.
return {
    {
        version = "1.0.7",
        changes = {
            "Updates: fixed \"Download failed: err 415\" when a release had no attached packages yet (GitHub refused the source code zip request).",
        },
    },
    {
        version = "1.0.6",
        changes = {
            "Grimmory settings are in Settings → General → Grimmory (no more digging through KOReader → Tools).",
        },
    },
    {
        version = "1.0.5",
        changes = {
            "Read aloud speaks whole sentences at normal speed (it was sending one word at a time), and the last word of each sentence is no longer held back.",
            "Read aloud volume: Quieter / Louder in Read-aloud settings, or the Kindle's volume buttons while reading.",
            "Settings: the entry that opens KOReader's own settings is called KOReader again.",
            "Downloaded tab: books show on the first visit (no more \"Set home folder\" until Home was opened).",
        },
    },
    {
        version = "1.0.4",
        changes = {
            "Read aloud: \"Find the Kindle voice\" now learns the request the Kindle's speech service (ttsd) expects from its own error messages (it asked for an id), instead of guessing numbered variants.",
            "Starting the voice test twice no longer runs two tests at once.",
            "Diagnostic log: lists the speech service's request fields.",
        },
    },
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
