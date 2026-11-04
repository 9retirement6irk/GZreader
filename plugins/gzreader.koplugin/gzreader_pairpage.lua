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

function PairPage.gone()
    return shell("Link expired", '<h1>This page has closed</h1><div class="card"><p>The page works while its QR code is on the Kindle\'s screen. To open it again: Send books from your phone in the Home menu (on a touch Kindle: Phone in the launcher), or Connect with QR code in the Grimmory, Notes or Calendar tab.</p></div>')
end

---------------------------------------------------------------- the phone page

local HUB_STYLE = [[
a{color:inherit;text-underline-offset:2px}
nav{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 18px}
nav a{font-size:14px;color:var(--ink);text-decoration:none;border:1px solid var(--line);border-radius:999px;padding:5px 12px;background:var(--card)}
section{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:18px;margin:0 0 16px;scroll-margin-top:12px}
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
    local parts = { '<section id="grimmory"><h2>Grimmory</h2>',
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
            .. (g.sso_relay and " (the same for every Kindle; the phone just needs to be on the Kindle's Wi-Fi to finish)" or "")
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
    local parts = { '<section id="notes"><h2>Notes (Memos)</h2>',
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
    local parts = { '<section id="calendar"><h2>Calendar</h2>',
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
    parts[#parts + 1] = '<h3 style="font-size:15px;margin:18px 0 6px">Add calendar links</h3>'
    parts[#parts + 1] = form(base .. "/links",
        '<textarea name="links" rows="4" autocapitalize="off" autocorrect="off" spellcheck="false" required placeholder="webcal://calendar.example.com/…&#10;Work | https://…/calendar.ics"></textarea>'
        .. '<button type="submit">Add links</button>'
        .. '<p class="note">One per line. To name one, write the name first: <code>Work | webcal://…</code>. Links are secret: the Kindle keeps them to sync and never writes them to its log.</p>'
        .. '<details><summary>Proton Calendar</summary><p class="note">Proton Calendar on the web: Settings → Calendars → a calendar → Share → Share with anyone → Create link (Full view shows event details). Do this for each calendar.</p></details>'
        .. '<details><summary>Google, Outlook, iCloud</summary><p class="note">Google: Settings → your calendar → Secret address in iCal format. Outlook: Settings → Calendar → Shared calendars → Publish → ICS. iCloud: share a calendar as a Public Calendar.</p></details>',
        "Checking…")
    -- CalDAV account
    parts[#parts + 1] = '<h3 style="font-size:15px;margin:18px 0 6px">CalDAV account</h3>'
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
    parts[#parts + 1] = "</section>"
    return table.concat(parts)
end

local function booksSection(st, base)
    local b = st.books or {}
    local received = {}
    for _i, name in ipairs(b.received or {}) do received[#received + 1] = '<p class="ok">✓ ' .. esc(name) .. "</p>" end
    return table.concat({
        '<section id="books"><h2>Send books</h2>',
        '<p class="what">Books from your phone go straight onto the Kindle (into the ', esc(b.folder or "GZreader"),
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

--- The phone page: every connection and sending books. `st` (see gzreader_phone.lua):
--- base, flash = { ok, text }, grimmory, memos, caldav, links, books.
function PairPage.hub(st)
    local base = st.base
    local flash = ""
    if st.flash then
        flash = '<div class="flash ' .. (st.flash.ok and "ok" or "bad") .. '">' .. (st.flash.ok and "✓ " or "")
            .. esc(st.flash.text) .. "</div>"
    end
    return shell("Kindle setup", table.concat({
        "<style>", HUB_STYLE, "</style>",
        "<h1>Set up your Kindle</h1>",
        '<p class="sub">Connect GZreader to your services and send it books. Everything on this page goes straight to your Kindle over your Wi‑Fi.</p>',
        flash,
        '<nav><a href="#grimmory">Grimmory</a><a href="#notes">Notes</a><a href="#calendar">Calendar</a><a href="#books">Send books</a></nav>',
        grimmorySection(st, base), memosSection(st, base), calendarSection(st, base), booksSection(st, base),
        '<p class="note">This page works while the code is on the Kindle\'s screen; when you\'re done, press Back (or tap Done) on the Kindle. Your phone and Kindle must be on the same Wi‑Fi.</p>',
    }))
end

return PairPage
