-- HTML served to the browser (a phone's or a computer's) during setup. Self-contained, no external assets.

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
input.pin{font-size:28px;letter-spacing:.25em;text-align:center;font-variant-numeric:tabular-nums}
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

local function shell(title, inner, body_class)
    local page = table.concat({
        '<!doctype html><html lang="en"><head><meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width,initial-scale=1">',
        '<meta name="robots" content="noindex">',
        "<title>", esc(title), "</title><style>", STYLE, "</style></head><body",
        body_class and (' class="' .. body_class .. '"') or "", "><main>",
        inner,
        "</main></body></html>",
    })
    -- (on a Nook the page talks about the Nook)
    local okd, Device = pcall(require, "device")
    if okd and Device.isNook and Device:isNook() then page = page:gsub("Kindle", "Nook") end
    return page
end

function PairPage.gone()
    return shell("Link expired", '<h1>This page has closed</h1><div class="card"><p>The page works while its QR code is on the Kindle\'s screen. To open it again: Send books in the quick panel (Menu, or on a touch Kindle swipe down from the top), or Connect with QR code in the Grimmory, Notes or Calendar tab.</p></div>')
end

--- The Kindle's address typed into a browser: the PIN on its screen first.
--- st = { tries_left, wrong, off }.
function PairPage.pin(st)
    st = st or {}
    local inner
    if st.off then
        inner = '<div class="card"><p class="err" style="margin:0 0 8px">The PIN is off after 5 wrong tries.</p>'
            .. '<p style="margin:0">Scan the QR code on the Kindle\'s screen instead, or close setup on the Kindle and open it again for a new PIN.</p></div>'
    else
        inner = '<form method="post" action="/" autocomplete="off">'
            .. '<label for="pin">PIN</label>'
            .. '<input id="pin" name="pin" class="pin" inputmode="numeric" autocomplete="one-time-code" maxlength="7" placeholder="123 456" required autofocus>'
            .. (st.wrong and ('<p class="err">That isn\'t the PIN. ' .. (st.tries_left == 1 and "1 try left." or (esc(st.tries_left) .. " tries left.")) .. "</p>") or "")
            .. '<button type="submit">Continue</button></form>'
            .. (st.log and '<p class="note">The PIN is under the QR code on the Kindle\'s screen, while it\'s sending the log.</p>'
                or '<p class="note">The PIN is under the QR code on the Kindle\'s screen, while setup is open there (Send books in its quick panel).</p>')
    end
    -- (st.log: the diagnostic log's page, GZreader → Send the diagnostic log)
    return shell(st.log and "Diagnostic log" or "Kindle setup", (st.log and "<h1>Get the diagnostic log</h1>" or "<h1>Set up your Kindle</h1>")
        .. '<p class="sub">Enter the PIN shown on the Kindle\'s screen.</p>' .. inner)
end

---------------------------------------------------------------- the phone page

local HUB_STYLE = [[
body.hub main{max-width:1040px}
a{color:inherit;text-underline-offset:2px}
a.button{display:block;text-align:center;font-weight:600;padding:12px;border-radius:10px;background:var(--accent);color:var(--bg);text-decoration:none}
nav{display:flex;gap:4px;margin:0 -16px 16px;padding:8px 16px;overflow-x:auto;position:sticky;top:0;background:var(--bg);z-index:2;scrollbar-width:none}
nav::-webkit-scrollbar{display:none}
nav a{flex:none;font-size:14px;color:var(--ink);text-decoration:none;border:1px solid var(--line);border-radius:999px;padding:6px 13px;background:var(--card);white-space:nowrap}
nav a.on{background:var(--accent);color:var(--bg);border-color:var(--accent)}
nav a .d{display:inline-block;width:7px;height:7px;border-radius:50%;background:var(--good);margin-left:6px;vertical-align:middle}
section{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:18px;margin:0 0 16px;scroll-margin-top:60px}
.js section.tab{display:none}.js section.tab.on{display:block}
details.box{border-top:1px solid var(--line);margin-top:14px;padding-top:12px}
details.box>summary{font-size:15px;font-weight:600;color:var(--ink)}
section h2{font-size:18px;margin:0 0 2px}
section .what{color:var(--muted);font-size:14px;margin:0 0 14px}
.status{display:flex;align-items:center;gap:8px;font-size:15px;margin:0 0 14px}
.dot{width:9px;height:9px;border-radius:50%;background:var(--line);flex:none}
.dot.on{background:var(--good)}
form{background:none;border:0;padding:0;margin:0}
.flash{border-radius:12px;padding:12px 14px;margin:0 0 16px;font-size:15px;border:1px solid var(--line);background:var(--card)}
.flash.ok{color:var(--good)}.flash.bad{color:var(--bad)}
.row{border-top:1px solid var(--line);padding:12px 0 2px}
.row:first-of-type{border-top:0;padding-top:0}
.row h3{font-size:15px;margin:0 0 8px;display:flex;justify-content:space-between;gap:8px}
.row h3 small{color:var(--muted);font-weight:400;font-size:12px}
.check{display:flex;align-items:center;gap:8px;font-size:14px;margin:0 0 12px;font-weight:400}
.check input{width:auto;margin:0}
.two{display:flex;gap:8px}.two button{flex:1}
button.danger{background:transparent;color:var(--bad);border:1px solid var(--line)}
button.small{width:auto;padding:8px 14px;font-size:14px}
textarea{width:100%;font:inherit;padding:11px 12px;border:1px solid var(--line);border-radius:10px;background:transparent;color:inherit;margin:0 0 14px}
#up p,.results p{margin:6px 0;font-size:14px;word-break:break-word}
.drop{border:2px dashed var(--line);border-radius:12px;padding:16px;text-align:center;margin:0 0 12px;color:var(--muted);font-size:14px}
.drop input{margin:10px 0 0}
/* wide screens: the tabs down the side, the page beside them */
@media (min-width:760px){
body{padding:40px 28px}
h1{font-size:26px}
.layout{display:grid;grid-template-columns:190px minmax(0,1fr);gap:28px;align-items:start}
nav{flex-direction:column;gap:6px;margin:0;padding:0;overflow:visible;top:24px}
nav a{border-radius:10px;padding:9px 14px;font-size:15px}
section{padding:24px 28px;scroll-margin-top:24px}
section h2{font-size:20px}
section>form,section>.what,section>.status,section>.err,section>details,section>p,section>a.button{max-width:600px}
.drop{padding:28px}
}
@media (min-width:1100px){.layout{grid-template-columns:220px minmax(0,1fr)}}
]]

local function form(action, inner, busy)
    return '<form method="post" action="' .. esc(action) .. '" autocomplete="off"'
        .. ' onsubmit="var b=event.submitter;if(b){setTimeout(function(){b.disabled=true;b.textContent=\'' .. (busy or "Working…") .. '\'},0)}">'
        .. inner .. "</form>"
end

--- A labelled text field: id (unique on the page), the form field's name.
local function input(id, name, label, value, attrs)
    return '<label for="' .. esc(id) .. '">' .. esc(label) .. '</label><input id="' .. esc(id) .. '" name="' .. name .. '" '
        .. (attrs or "") .. ' value="' .. esc(value) .. '">'
end

local URL_ATTRS = 'inputmode="url" autocapitalize="off" autocorrect="off" spellcheck="false"'
local NAME_ATTRS = 'autocapitalize="off" autocorrect="off" spellcheck="false"'

local function status(on, text)
    return '<p class="status"><span class="dot' .. (on and " on" or "") .. '"></span><span>' .. text .. "</span></p>"
end

local function confirmJs(text)
    return ' onclick="return confirm(\'' .. esc(text):gsub("'", "\\'") .. '\')"'
end

local function grimmorySection(st, base)
    local g = st.grimmory or {}
    local parts = { '<section id="grimmory" class="tab"><h2>Grimmory</h2>',
        '<p class="what">Your book library: browse and download books on the Kindle, reading progress kept in sync.</p>' }
    if g.connected then
        parts[#parts + 1] = status(true, "Connected as <b>" .. esc(g.username) .. "</b> · " .. esc(g.host))
        parts[#parts + 1] = form(base .. "/grimmory/disconnect",
            '<button class="danger" type="submit"' .. confirmJs("Disconnect the Kindle from Grimmory? Downloaded books stay on the Kindle.")
            .. ">Disconnect</button>", "Disconnecting…")
        parts[#parts + 1] = "<details><summary>Sign in again or with another account</summary><div style=\"margin-top:12px\">"
    else
        parts[#parts + 1] = status(false, "Not connected")
    end
    if g.error then parts[#parts + 1] = '<p class="err">' .. esc(g.error) .. "</p>" end
    local sso = g.sso
    local sso_block = ""
    if sso ~= false then
        local label = type(sso) == "table" and sso.name and ("Sign in with " .. sso.name) or "Sign in with SSO"
        sso_block = '<button class="' .. ((type(sso) == "table" and sso.only) and "" or "alt")
            .. '" type="submit" name="action" value="sso" formnovalidate>' .. esc(label) .. "</button>"
            .. '<p class="note">For single sign-on, your identity provider must allow this redirect address: <code>'
            .. esc(g.redirect_uri or "") .. "</code>"
            .. (g.sso_relay and " (the same for every Kindle; the browser just needs to be on the Kindle's Wi-Fi to finish)" or "")
            .. "</p>"
    end
    local pw = input("g_username", "username", "Username", (g.form or {}).username, 'autocomplete="username" ' .. NAME_ATTRS)
        .. '<label for="g_password">Password</label><input id="g_password" name="password" type="password" autocomplete="current-password">'
        .. '<button type="submit" name="action" value="password">Connect</button>'
    local body
    if type(sso) == "table" and sso.only then
        body = sso_block .. "<details><summary>Use a local Grimmory password instead</summary>" .. pw .. "</details>"
    elseif sso ~= false then
        body = pw .. '<div class="or">or</div>' .. sso_block
    else
        body = pw
    end
    parts[#parts + 1] = form(base .. "/grimmory",
        input("g_server", "server", "Grimmory address", (g.form or {}).server, 'required placeholder="https://books.example.com or 192.168.1.20:6060" ' .. URL_ATTRS)
        .. body, "Connecting…")
    if g.connected then parts[#parts + 1] = "</div></details>" end
    parts[#parts + 1] = "</section>"
    return table.concat(parts)
end

local function memosSection(st, base)
    local m = st.memos or {}
    local parts = { '<section id="notes" class="tab"><h2>Notes (Memos)</h2>',
        '<p class="what">The Notes tab shows your <a href="https://usememos.com">Memos</a> notes as sticky notes; write, edit and tick checklists on the Kindle.</p>' }
    if m.connected then
        parts[#parts + 1] = status(true, "Connected as <b>" .. esc(m.user) .. "</b> · " .. esc(m.host))
        parts[#parts + 1] = form(base .. "/memos/disconnect",
            '<button class="danger" type="submit"' .. confirmJs("Disconnect Notes from Memos? The notes kept on the Kindle are removed; your notes in Memos stay.")
            .. ">Disconnect</button>", "Disconnecting…")
        parts[#parts + 1] = "<details><summary>Change the address or access token</summary><div style=\"margin-top:12px\">"
    else
        parts[#parts + 1] = status(false, "Not connected")
    end
    if m.error then parts[#parts + 1] = '<p class="err">' .. esc(m.error) .. "</p>" end
    parts[#parts + 1] = form(base .. "/memos",
        input("m_server", "server", "Memos address", (m.form or {}).server, 'required placeholder="https://memos.example.com" ' .. URL_ATTRS)
        .. '<label for="m_token">Access token</label><input id="m_token" name="token" type="password" required ' .. NAME_ATTRS .. ">"
        .. '<button type="submit">Connect</button>'
        .. '<details><summary>Where do I get an access token?</summary><p class="note">In Memos: Settings → My account → Access Tokens → create one (no expiry, or a long one). The Kindle keeps the token, never your password.</p></details>',
        "Connecting…")
    if m.connected then parts[#parts + 1] = "</div></details>" end
    parts[#parts + 1] = "</section>"
    return table.concat(parts)
end

local function calendarSection(st, base)
    local c = st.caldav or {}
    local links = st.links or {}
    local parts = { '<section id="calendar" class="tab"><h2>Calendar</h2>',
        '<p class="what">The Calendar tab shows calendars from a CalDAV account (Nextcloud, iCloud, Fastmail, Google, Radicale…) and from calendar links (webcal:// or https://….ics, such as Proton Calendar\'s share links). Read-only.</p>' }
    if links.error then parts[#parts + 1] = '<p class="err">' .. esc(links.error) .. "</p>" end
    if links.results then parts[#parts + 1] = '<div class="results">' .. links.results .. "</div>" end
    -- the calendars there are now
    local cals = {}
    for _i, cal in ipairs(c.calendars or {}) do
        cals[#cals + 1] = '<div class="row">' .. form(base .. "/calendar/show",
            '<input type="hidden" name="href" value="' .. esc(cal.href) .. '">'
            .. "<h3>" .. esc(cal.name) .. " <small>CalDAV</small></h3>"
            .. '<label class="check"><input type="checkbox" name="shown" value="1"' .. (cal.shown and " checked" or "") .. '> Show its events</label>'
            .. '<button class="alt small" type="submit">Save</button>', "Saving…") .. "</div>"
    end
    for _i, f in ipairs(links.list or {}) do
        cals[#cals + 1] = '<div class="row">' .. form(base .. "/link",
            '<input type="hidden" name="id" value="' .. esc(f.id) .. '">'
            .. "<h3>" .. esc(f.name) .. " <small>link · " .. esc(f.host) .. "</small></h3>"
            .. input("name_" .. f.id, "name", "Name", f.custom_name or "", 'placeholder="' .. esc(f.own_name or f.name) .. '" ' .. NAME_ATTRS)
            .. input("url_" .. f.id, "url", "Replace the link (leave empty to keep it)", "", 'placeholder="webcal://…" ' .. URL_ATTRS)
            .. '<label class="check"><input type="checkbox" name="shown" value="1"' .. (f.shown and " checked" or "") .. '> Show its events</label>'
            .. '<div class="two"><button class="alt small" type="submit" name="action" value="save">Save</button>'
            .. '<button class="danger small" type="submit" name="action" value="remove"' .. confirmJs("Remove this calendar link from the Kindle?") .. ">Remove</button></div>",
            "Saving…") .. "</div>"
    end
    if #cals > 0 then
        parts[#parts + 1] = "<h3 style=\"font-size:15px;margin:4px 0 10px\">Your calendars</h3>" .. table.concat(cals)
    end
    -- calendar links
    parts[#parts + 1] = '<details class="box"' .. ((#cals == 0 or links.error) and " open" or "") .. '><summary>Add calendar links</summary><div style="margin-top:10px">'
    parts[#parts + 1] = form(base .. "/links",
        '<textarea name="links" rows="4" autocapitalize="off" autocorrect="off" spellcheck="false" required placeholder="webcal://calendar.example.com/…&#10;Work | https://…/calendar.ics"></textarea>'
        .. '<button type="submit">Add links</button>'
        .. '<p class="note">One per line. To name one, write the name first: <code>Work | webcal://…</code>. Links are secret: the Kindle keeps them to sync and never writes them to its log.</p>'
        .. '<details><summary>Proton Calendar</summary><p class="note">Proton Calendar on the web: Settings → Calendars → a calendar → Share → Share with anyone → Create link (Full view shows event details). Do this for each calendar.</p></details>'
        .. '<details><summary>Google, Outlook, iCloud</summary><p class="note">Google: Settings → your calendar → Secret address in iCal format. Outlook: Settings → Calendar → Shared calendars → Publish → ICS. iCloud: share a calendar as a Public Calendar.</p></details>',
        "Checking…")
    parts[#parts + 1] = "</div></details>"
    -- CalDAV account
    parts[#parts + 1] = '<details class="box"' .. ((not c.connected and #cals == 0 or c.error) and " open" or "") .. '><summary>CalDAV account</summary><div style="margin-top:10px">'
    if c.connected then
        parts[#parts + 1] = status(true, "<b>" .. esc(c.username) .. "</b> · " .. esc(c.host) .. " · " .. esc(#(c.calendars or {})) .. " calendars")
        parts[#parts + 1] = form(base .. "/caldav/disconnect",
            '<button class="danger" type="submit"' .. confirmJs("Disconnect the CalDAV account? Its password and events are removed from the Kindle; calendar links stay.")
            .. ">Disconnect the account</button>", "Disconnecting…")
        parts[#parts + 1] = "<details><summary>Connect again or another account</summary><div style=\"margin-top:12px\">"
    else
        parts[#parts + 1] = status(false, "No account")
    end
    if c.error then parts[#parts + 1] = '<p class="err">' .. esc(c.error) .. "</p>" end
    parts[#parts + 1] = form(base .. "/caldav",
        input("c_server", "server", "CalDAV address", (c.form or {}).server, 'required placeholder="https://cloud.example.com/remote.php/dav" ' .. URL_ATTRS)
        .. input("c_username", "username", "User name", (c.form or {}).username, 'required ' .. NAME_ATTRS)
        .. '<label for="c_password">Password (an app password where your server has them)</label><input id="c_password" name="password" type="password" required>'
        .. '<button type="submit">Connect</button>'
        .. '<details><summary>Which address?</summary><p class="note">Nextcloud: https://your.server/remote.php/dav · iCloud: https://caldav.icloud.com · Fastmail: https://caldav.fastmail.com · Google: https://apidata.googleusercontent.com/caldav/v2/ · Radicale or Baïkal: the server address.</p></details>',
        "Connecting…")
    if c.connected then parts[#parts + 1] = "</div></details>" end
    parts[#parts + 1] = "</div></details></section>"
    return table.concat(parts)
end

local function musicSection(st, base)
    local m = st.plex
    if not m then return "" end
    local parts = { '<section id="music" class="tab"><h2>Music (Plex)</h2>',
        '<p class="what">Albums and playlists from your Plex Media Server, to play while you read (the Music tab; turn it on in Settings → Navbar → Tabs).</p>' }
    if m.error then parts[#parts + 1] = '<p class="err">' .. esc(m.error) .. "</p>" end
    if m.connected then
        parts[#parts + 1] = status(true, "Signed in as <b>" .. esc(m.username) .. "</b> · " .. esc(m.server))
        if #(m.servers or {}) > 1 then
            local opts = {}
            for _i, sv in ipairs(m.servers) do
                opts[#opts + 1] = '<option value="' .. esc(sv.id) .. '"' .. (sv.current and " selected" or "") .. ">" .. esc(sv.name) .. "</option>"
            end
            parts[#parts + 1] = form(base .. "/plex/server", '<label for="p_server">Plex server</label><select id="p_server" name="id" style="width:100%;font:inherit;padding:10px;border:1px solid var(--line);border-radius:10px;background:transparent;color:inherit;margin:0 0 12px">'
                .. table.concat(opts) .. '</select><button class="alt small" type="submit">Use this server</button>', "Connecting…")
        end
        parts[#parts + 1] = form(base .. "/plex/disconnect",
            '<button class="danger" type="submit" style="margin-top:12px"' .. confirmJs("Sign out of Plex on the Kindle? Downloaded music stays.") .. ">Sign out</button>", "Signing out…")
    else
        parts[#parts + 1] = status(false, "Not signed in")
        parts[#parts + 1] = form(base .. "/plex/oauth", '<button type="submit">Sign in with Plex</button>', "Opening Plex…")
        parts[#parts + 1] = '<p class="note">Plex\'s own sign-in page opens, then brings you back here. Or on the Kindle: Music tab → Sign in with a code (plex.tv/link).</p>'
    end
    parts[#parts + 1] = "</section>"
    return table.concat(parts)
end

local function accessSection(st, base)
    local a = st.access or {}
    local parts = { '<section id="access" class="tab"><h2>Access</h2>',
        '<p class="what">If Cloudflare (or another proxy) blocks the Kindle with bot checks, GZreader can send a secret key to your servers for a rule that lets it through. Only to these servers, never anywhere else.</p>' }
    if a.error then parts[#parts + 1] = '<p class="err">' .. esc(a.error) .. "</p>" end
    parts[#parts + 1] = form(base .. "/access",
        '<label class="check"><input type="checkbox" name="enabled" value="1"' .. (a.enabled and " checked" or "") .. "> Send the key (header <code>X-GZreader-Key</code>)</label>"
        .. '<p style="font-size:14px;margin:0 0 6px">The key: <code>' .. esc(a.key or "") .. "</code></p>"
        .. '<label class="check"><input type="checkbox" name="new_key" value="1"> Make a new key</label>'
        .. input("a_hosts", "hosts", "Other servers (host names; each covers its subdomains)", a.hosts or "", 'placeholder="photos.example.com" ' .. NAME_ATTRS)
        .. '<p class="note" style="margin:-8px 0 14px">Already included: ' .. esc(table.concat(a.auto or {}, ", ")) .. "</p>"
        .. '<details><summary>Cloudflare Access (Zero Trust) service token</summary><div style="margin-top:10px">'
        .. input("a_cfid", "cf_id", "Client ID", a.cf_id or "", NAME_ATTRS)
        .. '<label for="a_cfsecret">Client Secret' .. (a.cf_secret_set and " (saved; leave empty to keep it)" or "") .. '</label><input id="a_cfsecret" name="cf_secret" type="password" ' .. NAME_ATTRS .. ">"
        .. '<label class="check"><input type="checkbox" name="cf_clear" value="1"> Remove the service token</label></div></details>'
        .. '<button type="submit" style="margin-top:12px">Save</button>', "Saving…")
    if a.enabled and a.rule then
        parts[#parts + 1] = '<details class="box" open><summary>The Cloudflare rule</summary>'
            .. '<p class="note">Cloudflare → your domain → Security → WAF → Custom rules → Create rule → Edit expression, paste this, Action: <b>Skip</b>, tick All remaining custom rules, All rate limiting rules, All managed rules, All Super Bot Fight Mode rules and (under More) Browser Integrity Check and Security Level. Put it first. Bot Fight Mode (Security → Bots) can\'t be skipped: turn it off if it blocks the Kindle.</p>'
            .. '<textarea rows="4" readonly onclick="this.select()">' .. esc(a.rule) .. "</textarea></details>"
    end
    parts[#parts + 1] = "</section>"
    return table.concat(parts)
end

local function booksSection(st, base)
    local b = st.books or {}
    local received = {}
    for _i, name in ipairs(b.received or {}) do received[#received + 1] = '<p class="ok">✓ ' .. esc(name) .. "</p>" end
    return table.concat({
        '<section id="books" class="tab"><h2>Send books</h2>',
        '<p class="what">Books from this browser go straight onto the Kindle (into the ', esc(b.folder or "GZreader"),
        ' folder; the Downloads tab shows them). No Grimmory needed.</p>',
        '<div class="drop"><label for="files" style="margin:0">EPUB, PDF, MOBI, AZW3, FB2, CBZ, TXT…</label>',
        '<input id="files" type="file" multiple accept="', esc(b.accept or ""), '"></div>',
        '<button id="send" type="button">Send to Kindle</button>',
        '<div id="up">', table.concat(received), '</div>',
        '<p class="note">Up to ', esc(b.max_mb or 0), ' MB each', b.free_mb and (" · " .. esc(b.free_mb) .. " MB free on the Kindle") or "",
        '. Keep this page open until each book shows ✓.</p>',
        '<script>(function(){var BASE=', string.format("%q", base), ';var f=document.getElementById("files"),b=document.getElementById("send"),out=document.getElementById("up");',
        'b.onclick=function(){var list=[].slice.call(f.files);if(!list.length){var p=document.createElement("p");p.className="err";p.textContent="Choose one or more books first.";out.appendChild(p);return}',
        'b.disabled=true;b.textContent="Sending…";next();',
        'function next(){var file=list.shift();if(!file){b.disabled=false;b.textContent="Send to Kindle";f.value="";return}',
        'var row=document.createElement("p");row.textContent=file.name+" …";out.appendChild(row);',
        'var x=new XMLHttpRequest();x.open("POST",BASE+"/upload?name="+encodeURIComponent(file.name));',
        'x.upload.onprogress=function(e){if(e.lengthComputable)row.textContent=file.name+" "+Math.round(e.loaded*100/e.total)+"%"};',
        'x.onload=function(){var ok=x.status==200;row.textContent=(ok?"✓ ":"✗ ")+x.responseText;row.className=ok?"ok":"err";next()};',
        'x.onerror=function(){row.textContent="✗ "+file.name+": the connection to the Kindle was lost";row.className="err";next()};',
        'x.send(file)}}})();</script>',
        "</section>",
    })
end

local function diagnosticsSection(st, base)
    if not st.diagnostics then return "" end
    return table.concat({
        '<section id="diagnostics" class="tab"><h2>Diagnostics</h2>',
        '<p class="what">The diagnostic log says what GZreader did and what went wrong, for a bug report or a chat about it. Passwords, tokens and calendar links are never in it.</p>',
        '<a class="button" href="', esc(base), '/log" download>Download the log</a>',
        '<p class="note">It\'s put together when you tap (a few seconds), and saved on the Kindle too. Diagnostic logging can be turned off on the Kindle: Settings → General → Diagnostic logging.</p>',
        "</section>",
    })
end

--- The setup page: every connection and sending books. `st` (see gzreader_phone.lua):
--- base, flash = { ok, text }, grimmory, memos, caldav, links, books.
function PairPage.hub(st)
    local base = st.base
    local flash = ""
    if st.flash then
        flash = '<div class="flash ' .. (st.flash.ok and "ok" or "bad") .. '">' .. (st.flash.ok and "✓ " or "")
            .. esc(st.flash.text) .. "</div>"
    end
    -- one tab at a time (all of them, one under the other, without JavaScript)
    local tabs = { { "grimmory", "Grimmory", (st.grimmory or {}).connected }, { "notes", "Notes", (st.memos or {}).connected },
        { "calendar", "Calendar", (st.caldav or {}).connected or #((st.links or {}).list or {}) > 0 } }
    if st.plex then tabs[#tabs + 1] = { "music", "Music", st.plex.connected } end
    tabs[#tabs + 1] = { "books", "Send books" }
    tabs[#tabs + 1] = { "access", "Access", (st.access or {}).enabled }
    if st.diagnostics then tabs[#tabs + 1] = { "diagnostics", "Diagnostics" } end
    local nav = {}
    for _i, t in ipairs(tabs) do
        nav[#nav + 1] = '<a href="#' .. t[1] .. '" data-tab="' .. t[1] .. '">' .. t[2] .. (t[3] and '<span class="d"></span>' or "") .. "</a>"
    end
    local alias = '{"caldav":"calendar","links":"calendar"}'
    return shell("Kindle setup", table.concat({
        "<style>", HUB_STYLE, "</style>",
        "<script>document.documentElement.className='js'</script>",
        "<h1>Set up your Kindle</h1>",
        '<p class="sub">Everything here goes straight to your Kindle over your Wi‑Fi.</p>',
        '<div class="layout"><nav>', table.concat(nav), "</nav><div>",
        flash,
        grimmorySection(st, base), memosSection(st, base), calendarSection(st, base), musicSection(st, base),
        booksSection(st, base), accessSection(st, base), diagnosticsSection(st, base),
        '<p class="note">This page works while setup is open on the Kindle\'s screen; press Back (or Done) there when you\'re done.</p>',
        "</div></div>",
        '<script>(function(){var A=', alias, ';function show(id){id=A[id]||id;var s=document.getElementById(id);if(!s||!/\\btab\\b/.test(s.className))id="', st.start or "grimmory", '";',
        '[].forEach.call(document.querySelectorAll("section.tab"),function(e){e.className=e.id==id?"tab on":"tab"});',
        '[].forEach.call(document.querySelectorAll("nav a"),function(a){a.className=a.getAttribute("data-tab")==id?"on":""});',
        'var on=document.querySelector("nav a.on");if(on&&on.scrollIntoView)try{on.scrollIntoView({inline:"center",block:"nearest"})}catch(e){}}',
        '[].forEach.call(document.querySelectorAll("nav a"),function(a){a.onclick=function(e){e.preventDefault();var id=a.getAttribute("data-tab");show(id);history.replaceState(null,"","#"+id);window.scrollTo(0,0)}});',
        'show(location.hash.slice(1));window.onhashchange=function(){show(location.hash.slice(1))}})();</script>',
    }), "hub")
end

return PairPage
