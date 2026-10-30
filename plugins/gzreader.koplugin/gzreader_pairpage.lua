-- HTML served to the phone during QR pairing. Self-contained, no external assets.

local PairPage = {}

local function esc(s)
    return (tostring(s or ""):gsub("[&<>\"']", {
        ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;",
    }))
end

local STYLE = [[
:root{--bg:#f6f4ef;--card:#fff;--ink:#1d1b18;--muted:#6b665d;--line:#d9d4c9;--accent:#1d1b18;--bad:#9b2c1f;--good:#2f6b3a}
@media (prefers-color-scheme:dark){:root{--bg:#141311;--card:#1e1c19;--ink:#efebe3;--muted:#a59f93;--line:#38342e;--accent:#efebe3;--bad:#e2786a;--good:#86c393}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;padding:24px 16px}
main{max-width:420px;margin:0 auto}
h1{font-size:22px;margin:0 0 4px;letter-spacing:-.01em}
p.sub{margin:0 0 20px;color:var(--muted);font-size:14px}
form,.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:18px}
label{display:block;font-size:13px;font-weight:600;margin:0 0 6px}
input{width:100%;font:inherit;padding:11px 12px;border:1px solid var(--line);border-radius:10px;background:transparent;color:inherit;margin:0 0 14px}
input:focus{outline:2px solid var(--accent);outline-offset:1px}
button{width:100%;font:inherit;font-weight:600;padding:12px;border:0;border-radius:10px;background:var(--accent);color:var(--bg);cursor:pointer}
button:disabled{opacity:.6}
button.alt{background:transparent;color:var(--ink);border:1px solid var(--line);margin-top:10px}
.or{display:flex;align-items:center;gap:10px;color:var(--muted);font-size:12px;margin:16px 0 6px}
.or:before,.or:after{content:"";flex:1;border-top:1px solid var(--line)}
code{font-size:12px;word-break:break-all;background:var(--bg);padding:1px 4px;border-radius:4px}
details{margin-top:14px}summary{cursor:pointer;font-size:14px;color:var(--muted)}
.err{color:var(--bad);font-size:14px;margin:0 0 14px}
.ok{color:var(--good);font-weight:600}
.note{color:var(--muted);font-size:12px;margin-top:16px}
]]

local function shell(title, inner)
    return table.concat({
        '<!doctype html><html lang="en"><head><meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width,initial-scale=1">',
        '<meta name="robots" content="noindex">',
        "<title>", esc(title), "</title><style>", STYLE, "</style></head><body><main>",
        inner,
        "</main></body></html>",
    })
end

--- opts: server, username, error, redirect_uri (SSO callback on the Kindle),
--- sso = nil (unknown: offer generic SSO) | false (server has no SSO) |
--- { name = provider name, only = true when the server is SSO-only }
function PairPage.form(opts)
    opts = opts or {}
    local err = opts.error and ('<p class="err">' .. esc(opts.error) .. "</p>") or ""
    local sso = opts.sso
    local sso_label = type(sso) == "table" and sso.name and ("Sign in with " .. sso.name) or "Sign in with SSO"
    local sso_block = ""
    if sso ~= false then
        sso_block = table.concat({
            '<button class="', (type(sso) == "table" and sso.only) and "" or "alt",
            '" type="submit" name="action" value="sso" formnovalidate>', esc(sso_label), "</button>",
            '<p class="note">For single sign-on, your identity provider must allow this redirect address: <code>',
            esc(opts.redirect_uri or ""), "</code></p>",
        })
    end
    local password_block = table.concat({
        '<label for="username">Username</label>',
        '<input id="username" name="username" autocomplete="username" autocapitalize="off" autocorrect="off" required value="', esc(opts.username), '">',
        '<label for="password">Password</label>',
        '<input id="password" name="password" type="password" autocomplete="current-password" required>',
        '<button type="submit" name="action" value="password">Connect Kindle</button>',
    })
    local body
    if type(sso) == "table" and sso.only then
        body = sso_block .. "<details><summary>Use a local Grimmory password instead</summary>" .. password_block .. "</details>"
    elseif sso ~= false then
        body = password_block .. '<div class="or">or</div>' .. sso_block
    else
        body = password_block
    end
    return shell("Connect Kindle to Grimmory", table.concat({
        "<h1>Connect your Kindle</h1>",
        '<p class="sub">Sign in to Grimmory. Your Kindle signs in directly and keeps only a login token, not your password.</p>',
        '<form method="post" autocomplete="on" onsubmit="var b=event.submitter;if(b){setTimeout(function(){b.disabled=true;b.textContent=\'Connecting…\'},0)}">',
        err,
        '<label for="server">Grimmory address</label>',
        '<input id="server" name="server" inputmode="url" autocapitalize="off" autocorrect="off" spellcheck="false" required placeholder="https://books.example.com or 192.168.1.20:6060" value="', esc(opts.server), '">',
        body,
        '<p class="note">Your phone and Kindle must be on the same Wi‑Fi. This page works once and closes on the Kindle when you finish or press Back.</p>',
        "</form>",
    }))
end

function PairPage.success(username)
    return shell("Kindle connected", table.concat({
        '<h1>Kindle connected</h1><div class="card"><p class="ok">Signed in as ', esc(username), ".</p>",
        "<p>Books you download on the Kindle will keep their reading progress in sync with Grimmory.</p>",
        "<p>You can close this page.</p></div>",
    }))
end

function PairPage.gone()
    return shell("Link expired", '<h1>This link has expired</h1><div class="card"><p>Open Grimmory on your Kindle and choose “Connect with QR code” to get a new one.</p></div>')
end

--- Connecting the Notes tab to Memos. opts: server, error.
function PairPage.memosForm(opts)
    opts = opts or {}
    local err = opts.error and ('<p class="err">' .. esc(opts.error) .. "</p>") or ""
    return shell("Connect Kindle to Memos", table.concat({
        "<h1>Connect Notes to Memos</h1>",
        '<p class="sub">Your Kindle\'s Notes tab shows your Memos notes as sticky notes. It needs your Memos address and an access token.</p>',
        '<form method="post" autocomplete="off" onsubmit="var b=event.submitter;if(b){setTimeout(function(){b.disabled=true;b.textContent=\'Connecting…\'},0)}">',
        err,
        '<label for="server">Memos address</label>',
        '<input id="server" name="server" inputmode="url" autocapitalize="off" autocorrect="off" spellcheck="false" required placeholder="https://memos.example.com" value="', esc(opts.server), '">',
        '<label for="token">Access token</label>',
        '<input id="token" name="token" type="password" autocapitalize="off" autocorrect="off" spellcheck="false" required>',
        '<button type="submit">Connect Kindle</button>',
        '<details><summary>Where do I get an access token?</summary><p class="note">In Memos, open Settings → My account → Access Tokens, create a token (no expiry, or a long one) and paste it here. The Kindle keeps the token, never your password.</p></details>',
        '<p class="note">Your phone and Kindle must be on the same Wi‑Fi. This page works once and closes on the Kindle when you finish or press Back. New notes are private unless you choose otherwise on the Kindle.</p>',
        "</form>",
    }))
end

function PairPage.memosSuccess(user)
    return shell("Kindle connected", table.concat({
        '<h1>Notes connected</h1><div class="card"><p class="ok">Connected to Memos as ', esc(user), ".</p>",
        "<p>Your notes are on the Kindle's Notes tab. You can close this page.</p></div>",
    }))
end

--- Connecting the Calendar tab (CalDAV). opts: server, username, error.
function PairPage.caldavForm(opts)
    opts = opts or {}
    local err = opts.error and ('<p class="err">' .. esc(opts.error) .. "</p>") or ""
    return shell("Connect Kindle to your calendar", table.concat({
        "<h1>Connect your calendar</h1>",
        '<p class="sub">The Kindle\'s Calendar tab shows your CalDAV calendars (Nextcloud, iCloud, Fastmail, Google, Radicale…), read-only.</p>',
        '<form method="post" autocomplete="off" onsubmit="var b=event.submitter;if(b){setTimeout(function(){b.disabled=true;b.textContent=\'Connecting…\'},0)}">',
        err,
        '<label for="server">CalDAV address</label>',
        '<input id="server" name="server" inputmode="url" autocapitalize="off" autocorrect="off" spellcheck="false" required placeholder="https://cloud.example.com/remote.php/dav" value="', esc(opts.server), '">',
        '<label for="username">User name</label>',
        '<input id="username" name="username" autocapitalize="off" autocorrect="off" spellcheck="false" required value="', esc(opts.username), '">',
        '<label for="password">Password</label>',
        '<input id="password" name="password" type="password" required>',
        '<button type="submit">Connect Kindle</button>',
        '<details><summary>Which address and password?</summary><p class="note">Nextcloud: https://your.server/remote.php/dav · iCloud: https://caldav.icloud.com · Fastmail: https://caldav.fastmail.com · Google: https://apidata.googleusercontent.com/caldav/v2/ · Radicale or Baïkal: the server address. Use an app password where your server has them (iCloud, Fastmail and Google need one): the Kindle keeps it to sync, and you can revoke it any time.</p></details>',
        '<p class="note">Your phone and Kindle must be on the same Wi‑Fi. This page works once and closes on the Kindle when you finish or press Back.</p>',
        "</form>",
    }))
end

function PairPage.caldavSuccess(count)
    return shell("Kindle connected", table.concat({
        '<h1>Calendar connected</h1><div class="card"><p class="ok">Found ', esc(count), " calendars.</p>",
        "<p>They're on the Kindle's Calendar tab. You can close this page.</p></div>",
    }))
end

--- Adding calendar links (webcal / ICS). opts: count (links so far), error.
function PairPage.feedsForm(opts)
    opts = opts or {}
    local err = opts.error and ('<p class="err">' .. esc(opts.error) .. "</p>") or ""
    local have = (opts.count or 0) > 0 and ('<p class="note">' .. esc(opts.count) .. " calendar links on the Kindle already.</p>") or ""
    return shell("Add calendar links", table.concat({
        "<h1>Add calendar links</h1>",
        '<p class="sub">Paste one or more calendar links, one per line: webcal://… or https://….ics. To give one a name, write it first: <code>Work | webcal://…</code></p>',
        '<form method="post" autocomplete="off" onsubmit="var b=event.submitter;if(b){setTimeout(function(){b.disabled=true;b.textContent=\'Checking…\'},0)}">',
        err, have,
        '<label for="links">Calendar links</label>',
        '<textarea id="links" name="links" rows="6" autocapitalize="off" autocorrect="off" spellcheck="false" required ',
        'style="width:100%;font:inherit;padding:11px 12px;border:1px solid var(--line);border-radius:10px;background:transparent;color:inherit;margin:0 0 14px" ',
        'placeholder="webcal://calendar.example.com/…"></textarea>',
        '<button type="submit">Add to Kindle</button>',
        '<details><summary>Proton Calendar</summary><p class="note">In Proton Calendar on the web: Settings → Calendars → pick a calendar → Share → Share with anyone → Create link (Full view shows event details; Limited view only shows busy times). Copy the link and paste it here. Do this for each calendar you want on the Kindle.</p></details>',
        '<details><summary>Other calendars</summary><p class="note">Google Calendar: Settings → your calendar → Secret address in iCal format. Outlook: Settings → Calendar → Shared calendars → Publish a calendar → ICS. Apple iCloud: share a calendar as a Public Calendar. Any https://….ics link works.</p></details>',
        '<p class="note">These links are secret (anyone with one can read the calendar). The Kindle keeps them to sync and never writes them to its log. Your phone and Kindle must be on the same Wi‑Fi; this page works until you press Back on the Kindle.</p>',
        "</form>",
    }))
end

function PairPage.feedsResult(results, total)
    local rows = {}
    for _i, r in ipairs(results or {}) do
        if r.ok then
            rows[#rows + 1] = '<p class="ok">✓ ' .. esc(r.label) .. (r.note and (" (" .. esc(r.note) .. ")")
                or (r.count and (" (" .. esc(r.count) .. " events)") or "")) .. "</p>"
        else
            rows[#rows + 1] = '<p class="err">✗ ' .. esc(r.label) .. ": " .. esc(r.err) .. "</p>"
        end
    end
    return shell("Calendar links", table.concat({
        '<h1>Calendar links</h1><div class="card">', table.concat(rows),
        "<p>", esc(total or 0), " calendar links on the Kindle now. Add more below, or press Back on the Kindle when you're done.</p></div>",
        '<p class="note"><a href="">Add more links</a></p>',
    }))
end

return PairPage
