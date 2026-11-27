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
                or '<p class="note">The PIN is under the QR code on the Kindle\'s screen, while setup is open there (Connect in its quick panel).</p>')
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
.pair{border-left:3px solid var(--line);padding-left:10px;margin:0 0 12px}
.js-only{display:none}.js .js-only{display:block}
button.danger{background:transparent;color:var(--bad);border:1px solid var(--line)}
button.small{width:auto;padding:8px 14px;font-size:14px}
textarea{width:100%;font:inherit;padding:11px 12px;border:1px solid var(--line);border-radius:10px;background:transparent;color:inherit;margin:0 0 14px}
#up p,.results p{margin:6px 0;font-size:14px;word-break:break-word}
.drop{border:2px dashed var(--line);border-radius:12px;padding:16px;text-align:center;margin:0 0 12px;color:var(--muted);font-size:14px}
.drop input{margin:10px 0 0}
select.sel{width:100%;font:inherit;padding:10px;border:1px solid var(--line);border-radius:10px;background:transparent;color:inherit;margin:0 0 14px}
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
    local orbit = g.backend == "bookorbit"
    -- which book server the form is for: the one typed last, else the one signed in to
    local picked = ((g.form or {}).backend or g.backend) == "bookorbit" and "bookorbit" or "grimmory"
    -- The heading names the server: the one connected, else the one chosen below (it follows the choice).
    local title = g.connected and (orbit and "BookOrbit" or "Grimmory") or (picked == "bookorbit" and "BookOrbit" or "Grimmory")
    local parts = { '<section id="grimmory" class="tab"><h2 id="g_title"' .. (g.connected and ' data-fixed="1"' or "") .. ">" .. title .. "</h2>",
        '<p class="what">Your book library: browse and download books on the Kindle, reading progress kept in sync.</p>' }
    if g.connected then
        parts[#parts + 1] = status(true, (orbit and "Connected to BookOrbit as <b>" or "Connected as <b>") .. esc(g.username) .. "</b> · " .. esc(g.host))
        if orbit then
            parts[#parts + 1] = '<p class="note">' .. esc(g.bookorbit_note or "") .. "</p>"
            if g.bookorbit_advice then parts[#parts + 1] = '<p class="err">' .. esc(g.bookorbit_advice) .. "</p>" end
            -- the API key for BookOrbit's audiobooks (never shown back: only whether one is kept)
            if g.key_error then parts[#parts + 1] = '<p class="err">' .. esc(g.key_error) .. "</p>" end
            parts[#parts + 1] = form(base .. "/grimmory/apikey",
                '<label for="g_apikey">API key (audiobooks, collections, book requests)' .. (g.bookorbit_api_key and " (one is saved)" or "") .. "</label>"
                .. '<input id="g_apikey" name="api_key" type="password" autocomplete="off" placeholder="bok_…">'
                .. '<p class="note">From BookOrbit: Settings → You → API keys → Create API key. ' .. esc(g.bookorbit_key_needs or "")
                .. " Needed for audiobooks, changing collections and book requests. Leave empty and save to remove it.</p>"
                .. '<button type="submit">Save API key</button>', "Checking…")
        end
        parts[#parts + 1] = form(base .. "/grimmory/disconnect",
            '<button class="danger" type="submit"' .. confirmJs("Disconnect the Kindle from " .. (orbit and "BookOrbit" or "Grimmory") .. "? Downloaded books stay on the Kindle.")
            .. ">Disconnect</button>", "Disconnecting…")
        parts[#parts + 1] = "<details" .. (g.other and " open" or "") .. "><summary>Sign in again or with another account</summary><div style=\"margin-top:12px\">"
    else
        parts[#parts + 1] = status(false, "Not connected")
    end
    if g.error then parts[#parts + 1] = '<p class="err">' .. esc(g.error) .. "</p>" end
    -- Each server's own way in, in its own block: only the chosen server's block shows and is sent
    -- (the other's fields are disabled, so a browser leaves them out).
    local function block(server, inner)
        local on = picked == server
        return '<div data-for="' .. server .. '"' .. (on and "" or ' style="display:none"') .. ">" .. inner .. "</div>"
    end
    local function off(server) return picked == server and "" or " disabled" end
    -- Grimmory: user name and password, and single sign-on when the server has it
    local sso = g.sso
    local sso_block = ""
    if sso ~= false then
        local label = type(sso) == "table" and sso.name and ("Sign in with " .. sso.name) or "Sign in with SSO"
        sso_block = '<button class="' .. ((type(sso) == "table" and sso.only) and "" or "alt")
            .. '" type="submit" name="action" value="sso" formnovalidate' .. off("grimmory") .. ">" .. esc(label) .. "</button>"
            .. '<p class="note">For single sign-on, your identity provider must allow this redirect address: <code>'
            .. esc(g.redirect_uri or "") .. "</code>"
            .. (g.sso_relay and " (the same for every Kindle; the browser just needs to be on the Kindle's Wi-Fi to finish)" or "")
            .. "</p>"
    end
    local pw = input("g_username", "username", "Username", (g.form or {}).username, 'autocomplete="username" ' .. NAME_ATTRS .. off("grimmory"))
        .. '<label for="g_password">Password</label><input id="g_password" name="password" type="password" autocomplete="current-password"' .. off("grimmory") .. ">"
        .. '<button type="submit" name="action" value="password"' .. off("grimmory") .. ">Connect</button>"
    local grim
    if type(sso) == "table" and sso.only then
        grim = sso_block .. "<details><summary>Use a local Grimmory password instead</summary>" .. pw .. "</details>"
    elseif sso ~= false then
        grim = pw .. '<div class="or">or</div>' .. sso_block
    else
        grim = pw
    end
    -- BookOrbit: an API key alone (it fetches, or makes, the e-reader sign-in), or the KOReader
    -- sync user name and password. BookOrbit's e-reader sign-in has no single sign-on.
    local bo = '<label for="g_signin_key">BookOrbit API key</label>'
        .. '<input id="g_signin_key" name="api_key" type="password" autocomplete="off" placeholder="bok_…"' .. off("bookorbit") .. ">"
        .. '<p class="note">The easy way: with the key alone, the Kindle gets your KOReader sync sign-in from BookOrbit (or makes one if you have none) '
        .. "and keeps the key for audiobooks, collections and book requests. Make it in BookOrbit: Settings → You → API keys → Create API key. "
        .. esc(g.bookorbit_key_needs or "") .. "</p>"
        .. '<button type="submit" name="action" value="apikey" formnovalidate' .. off("bookorbit") .. ">Connect with the API key</button>"
        .. '<div class="or">or</div>'
        .. "<details" .. (((g.form or {}).username or "") ~= "" and " open" or "") .. "><summary>Use the KOReader sync user name and password instead</summary>"
        .. input("g_ko_username", "username", "KOReader sync user name", (g.form or {}).username, 'autocomplete="username" ' .. NAME_ATTRS .. off("bookorbit"))
        .. '<label for="g_ko_password">KOReader sync password</label><input id="g_ko_password" name="password" type="password" autocomplete="current-password"' .. off("bookorbit") .. ">"
        .. '<p class="note">From BookOrbit\'s Settings → Devices → KOReader (not your website sign-in). ' .. esc(g.bookorbit_note or "") .. "</p>"
        .. '<button class="alt" type="submit" name="action" value="password"' .. off("bookorbit") .. ">Connect</button></details>"
    local which = '<label for="g_backend">Book server</label><select id="g_backend" name="backend">'
        .. '<option value="grimmory">Grimmory</option>'
        .. '<option value="bookorbit"' .. (picked == "bookorbit" and " selected" or "") .. ">BookOrbit</option></select>"
    parts[#parts + 1] = form(base .. "/grimmory",
        which .. input("g_server", "server", "Server address", (g.form or {}).server, 'required placeholder="https://books.example.com or 192.168.1.20:6060" ' .. URL_ATTRS)
        .. block("grimmory", grim) .. block("bookorbit", bo), "Connecting…")
    -- choosing a server shows its block, names the heading after it, and switches the other's fields off
    parts[#parts + 1] = '<script>(function(){var s=document.getElementById("g_backend"),t=document.getElementById("g_title");if(!s||!s.form)return;'
        .. 'function set(){var v=s.value,g=s.form.querySelectorAll("[data-for]"),i,j,e;'
        .. 'if(t&&!t.getAttribute("data-fixed"))t.textContent=v=="bookorbit"?"BookOrbit":"Grimmory";'
        .. 'for(i=0;i<g.length;i++){var on=g[i].getAttribute("data-for")==v;g[i].style.display=on?"":"none";'
        .. 'e=g[i].querySelectorAll("input,button");for(j=0;j<e.length;j++)e[j].disabled=!on;}}'
        .. "s.onchange=set;set();})();</script>"
    if g.connected then parts[#parts + 1] = "</div></details>" end
    parts[#parts + 1] = "</section>"
    return table.concat(parts)
end

-- Handwriting to text (gzreader_handwriting.lua), in the Notes tab: where it's
-- read. The key for reading it with AI is the AI tab's.
local function handwritingPart(st, base)
    local h = st.handwriting
    if not h then return "" end
    local ai = h.ai_name
    local function choice(value, label, off)
        return '<label class="check"><input type="radio" name="engine" value="' .. value .. '"' .. (h.chosen == value and " checked" or "")
            .. (off and " disabled" or "") .. "> " .. label .. "</label>"
    end
    local parts = { '<h2 id="handwriting" style="margin-top:22px">Handwriting to text</h2>',
        '<p class="what">While drawing, the text tool\'s Write and the lasso\'s To text turn your writing into typed text. It can be read on the Kindle (nothing leaves it), or with AI: then only the writing being read is sent, as a black-and-white picture, never the page or your other notes.</p>',
        status(h.engine ~= "kindle", "Your writing is read " .. (h.engine == "kindle" and "<b>on the Kindle</b>" or ("with AI: <b>" .. esc(ai or "") .. "</b>"))) }
    if h.error then parts[#parts + 1] = '<p class="err">' .. esc(h.error) .. "</p>" end
    parts[#parts + 1] = form(base .. "/handwriting",
        choice("kindle", "On the Kindle") .. choice("ai", ai and ("With AI: " .. esc(ai)) or "With AI", not ai)
        .. '<p class="note">' .. (ai and "The AI service and its key are in the <a href=\"#ai\">AI tab</a>."
            or "To read it with AI, first give a key in the <a href=\"#ai\">AI tab</a>.") .. "</p>"
        .. '<button type="submit">Save</button>', "Saving…")
    return table.concat(parts)
end

-- The AI connection (gzreader_ai.lua): one key for everything that uses AI.
-- A key saved on the Kindle is never sent back to the page: it says "set",
-- and a field left empty keeps it.
local function aiSection(st, base)
    local a = st.ai
    if not a then return "" end
    local function choice(value, label)
        return '<label class="check"><input type="radio" name="provider" value="' .. value .. '"' .. (a.chosen == value and " checked" or "")
            .. "> " .. esc(label) .. "</label>"
    end
    local function key(id, name, label, set, hint)
        return '<label for="' .. id .. '">' .. esc(label) .. (set and " (set: leave empty to keep it)" or "") .. '</label><input id="' .. id
            .. '" name="' .. name .. '" type="password" placeholder="' .. esc(set and "••••••••" or hint) .. '" ' .. NAME_ATTRS .. ">"
    end
    local parts = { '<section id="ai" class="tab"><h2>AI</h2>',
        '<p class="what">One key of your own for everything on the Kindle that asks an AI service something: reading your handwriting (Notes), the daily paper\'s AI edition, and whatever comes next. Nothing is sent until you switch a use on, and then only what it needs: the writing being read, as a picture, or a news story\'s headline and text for its summary.</p>',
        status(a.provider ~= nil, a.provider and ("Set up: <b>" .. esc(a.name) .. "</b>") or "Not set up") }
    if a.provider then
        local uses = {}
        for _i, u in ipairs(a.uses or {}) do uses[#uses + 1] = esc(u) end
        parts[#parts + 1] = '<p class="note">Used for: ' .. (#uses > 0 and table.concat(uses, ", ") or "nothing yet (switch it on in the Notes tab or the Daily paper tab)") .. ".</p>"
    end
    if a.error then parts[#parts + 1] = '<p class="err">' .. esc(a.error) .. "</p>" end
    parts[#parts + 1] = form(base .. "/ai",
        choice("claude", "Claude (Anthropic)") .. choice("openai", "An online service (OpenAI-style)")
        .. '<details' .. ((a.chosen == "claude" or not a.claude_set) and " open" or "") .. '><summary>Claude</summary><div style="margin-top:10px">'
        .. key("ai_ckey", "claude_key", "Claude API key", a.claude_set, "sk-ant-…")
        .. input("ai_cmodel", "claude_model", "Model (empty: " .. a.claude_default .. ")", a.claude_model, 'placeholder="' .. esc(a.claude_default) .. '" ' .. NAME_ATTRS)
        .. '<p class="note">An API key from console.anthropic.com → API keys. Paid by use: reading a few handwritten words costs a fraction of a cent.</p>'
        .. "</div></details>"
        .. '<details' .. (a.chosen == "openai" and " open" or "") .. '><summary>An online service (OpenAI-style)</summary><div style="margin-top:10px">'
        .. input("ai_url", "openai_url", "Service address (empty: " .. a.openai_default .. ")", a.openai_url, 'placeholder="' .. esc(a.openai_default) .. '" ' .. URL_ATTRS)
        .. key("ai_okey", "openai_key", "Service key", a.openai_set, "sk-…")
        .. input("ai_omodel", "openai_model", "Model", a.openai_model, 'placeholder="the model\'s name" ' .. NAME_ATTRS)
        .. '<p class="note">Any service that speaks OpenAI\'s Chat Completions API: OpenAI itself, or a model you run yourself (http:// only for a computer on your own network). For handwriting the model must read pictures.</p>'
        .. "</div></details>"
        .. '<button type="submit">Save</button>', "Saving…")
    if a.claude_set or a.openai_set then
        parts[#parts + 1] = form(base .. "/ai",
            '<input type="hidden" name="clear" value="1"><button class="danger" type="submit"'
            .. confirmJs("Remove the AI keys from the Kindle? Handwriting is then read on the Kindle, and the daily paper is the ordinary one.") .. ">Remove the keys</button>", "Removing…")
    end
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
        .. '<div class="or">or</div><button class="alt" type="submit" name="action" value="sso" formnovalidate>Sign in with single sign-on (SSO)</button>'
        .. '<p class="note">Single sign-on needs an identity provider set up in Memos (Settings → SSO), and <code>' .. esc(m.redirect_uri or "") .. "</code> as a redirect URI on Memos' client there"
        .. (m.sso_relay and " (the same for every Kindle)" or "") .. '. The Kindle then makes an access token for itself in Memos, described “GZreader (this Kindle)”, and keeps only that.</p>'
        .. '<details><summary>Where do I get an access token?</summary><p class="note">In Memos: Settings → My account → Access Tokens → create one (no expiry, or a long one). The Kindle keeps the token, never your password.</p></details>',
        "Connecting…")
    if m.connected then parts[#parts + 1] = "</div></details>" end
    parts[#parts + 1] = handwritingPart(st, base)
    parts[#parts + 1] = "</section>"
    return table.concat(parts)
end

local function houseSection(st, base)
    local h = st.house
    if not h then return "" end
    local parts = { '<section id="house" class="tab"><h2>House (Home Assistant)</h2>',
        '<p class="what">The House tab shows your <a href="https://www.home-assistant.io">Home Assistant</a> rooms with their lights, switches, thermostats, locks and scenes, to switch from the Kindle. Turn the tab on in Settings → Accounts and services → House.</p>' }
    if h.connected then
        parts[#parts + 1] = status(true, "Connected to <b>" .. esc(h.name or "Home Assistant") .. "</b> · " .. esc(h.host))
        parts[#parts + 1] = form(base .. "/house/disconnect",
            '<button class="danger" type="submit"' .. confirmJs("Disconnect from Home Assistant? The address and token are removed from the Kindle (delete the token in Home Assistant too).")
            .. ">Disconnect</button>", "Disconnecting…")
        parts[#parts + 1] = "<details><summary>Change the address or token</summary><div style=\"margin-top:12px\">"
    else
        parts[#parts + 1] = status(false, "Not connected")
    end
    if h.error then parts[#parts + 1] = '<p class="err">' .. esc(h.error) .. "</p>" end
    parts[#parts + 1] = form(base .. "/house",
        input("h_server", "server", "Home Assistant address", (h.form or {}).server, 'required placeholder="homeassistant.local:8123" ' .. URL_ATTRS)
        .. '<label for="h_token">Long-lived access token</label><input id="h_token" name="token" type="password" required ' .. NAME_ATTRS .. ">"
        .. '<button type="submit">Connect</button>'
        .. '<details><summary>Where do I get a token?</summary><p class="note">In Home Assistant: your profile (bottom left) → Security → Long-lived access tokens → Create token. Copy it here: Home Assistant shows it only once. A token made by an administrator also brings your rooms (areas); with another one the tab groups things by kind. The Kindle keeps the token, never your password, and never writes it to its log.</p></details>'
        .. '<details><summary>Which address?</summary><p class="note">The one you open Home Assistant with on this Wi‑Fi, e.g. <code>homeassistant.local:8123</code> or <code>192.168.1.20:8123</code> (port 8123 is added when there\'s none). A Home Assistant Cloud or other https:// address works too.</p></details>',
        "Connecting…")
    if h.connected then parts[#parts + 1] = "</div></details>" end
    parts[#parts + 1] = "</section>"
    return table.concat(parts)
end

-- Mealie (the Recipes tab): an API token, or single sign-on.
local function recipesSection(st, base)
    local r = st.recipes
    if not r then return "" end
    local parts = { '<section id="recipes" class="tab"><h2>Recipes (Mealie)</h2>',
        '<p class="what">The Recipes tab shows the recipes of your <a href="https://mealie.io">Mealie</a>, to search and read on the Kindle. Turn the tab on in Settings → Accounts and services → Recipes.</p>' }
    if r.connected then
        parts[#parts + 1] = status(true, "Connected as <b>" .. esc(r.name or "?") .. "</b> · " .. esc(r.host)
            .. (r.sso and " · single sign-on" or ""))
        parts[#parts + 1] = form(base .. "/recipes/disconnect",
            '<button class="danger" type="submit"' .. confirmJs(r.sso
                and "Disconnect from Mealie? The address and token are removed from the Kindle, and Mealie is asked to delete the token GZreader made."
                or "Disconnect from Mealie? The address and token are removed from the Kindle (delete the token in Mealie too).")
            .. ">Disconnect</button>", "Disconnecting…")
        parts[#parts + 1] = "<details><summary>Change the address or sign in again</summary><div style=\"margin-top:12px\">"
    else
        parts[#parts + 1] = status(false, "Not connected")
    end
    if r.error then parts[#parts + 1] = '<p class="err">' .. esc(r.error) .. "</p>" end
    parts[#parts + 1] = form(base .. "/recipes",
        input("r_server", "server", "Mealie address", (r.form or {}).server, 'required placeholder="mealie.example.com" ' .. URL_ATTRS)
        .. '<label for="r_token">API token</label><input id="r_token" name="token" type="password" ' .. NAME_ATTRS .. ">"
        .. '<button type="submit" name="action" value="token">Connect</button>'
        .. '<div class="or">or</div>'
        .. '<button class="alt" type="submit" name="action" value="sso">Sign in with single sign-on</button>'
        .. '<details><summary>Where do I get a token?</summary><p class="note">In Mealie: your profile (top right) → API tokens → name it and Generate. Copy it here: Mealie shows it only once. The Kindle keeps the token, never your password, and never writes it to its log.</p></details>'
        .. '<details><summary>Single sign-on</summary><p class="note">For a Mealie that signs you in through an identity provider (OIDC: Authentik, Authelia, Keycloak, Pocket ID…). Leave the token empty and press the button: you sign in at your provider in this browser, and the Kindle then asks Mealie for an API token of its own, listed as <b>GZreader</b> in your Mealie profile. It needs a Mealie new enough to sign apps in, and this address allowed as a redirect for Mealie at your provider:<br><code>'
        .. esc(r.redirect_uri or "") .. "</code>"
        .. (r.sso_relay and " (the same for every Kindle; the browser just needs to be on the Kindle's Wi‑Fi to finish)" or "")
        .. "</p></details>",
        "Connecting…")
    if r.connected then parts[#parts + 1] = "</div></details>" end
    parts[#parts + 1] = "</section>"
    return table.concat(parts)
end

-- The daily paper (gzreader_daily.lua): on/off, on the shelf, which feeds.
local function paperSection(st, base)
    local p = st.paper
    if not p then return "" end
    local function tick(name, on, label)
        return '<label class="check"><input type="checkbox" name="' .. esc(name) .. '" value="1"' .. (on and " checked" or "") .. "> " .. label .. "</label>"
    end
    local parts = { '<section id="paper" class="tab"><h2>Daily paper</h2>',
        '<p class="what">A newspaper on Home\'s bookshelf, put together once a day from the news feeds you tick (a feed is a site\'s list of its newest stories: RSS or Atom). The Kindle fetches them itself over Wi‑Fi, from 5 in the morning, and keeps the paper to read with Wi‑Fi off.</p>' }
    parts[#parts + 1] = status(p.enabled, p.enabled and (p.stories and ("On · the last paper has " .. esc(p.stories) .. " stories") or "On · no paper fetched yet") or "Off")
    if p.error then parts[#parts + 1] = '<p class="err">' .. esc(p.error) .. "</p>" end
    local rows = { tick("enabled", p.enabled, "<b>Daily paper</b>"), tick("shelf", p.shelf, "Show it on Home's bookshelf"),
        tick("full", p.full, "Whole stories (each short story's own page is fetched too)"),
        tick("pictures", p.pictures, "With pictures (in opened stories, and a few on the pages)"),
        tick("calendar", p.calendar, "Today's calendar events on the front page") }
    if p.ai_ready or p.ai then
        rows[#rows + 1] = tick("ai", p.ai, "AI edition: a summary of each story, and pages of articles with their pictures")
            .. '<p class="note" style="margin:-4px 0 10px">Each story\'s headline and text are sent to the AI service of the <a href="#ai">AI tab</a> when the paper is fetched; nothing about you is.'
            .. (p.ai_ready and "" or " <b>The AI tab has no key yet.</b>") .. "</p>"
    else
        rows[#rows + 1] = '<p class="note" style="margin:0 0 10px">An AI edition (a summary of each story, pages of articles with their pictures) can be switched on here once the <a href="#ai">AI tab</a> has a key.</p>'
    end
    local wx = p.weather or {}
    rows[#rows + 1] = tick("weather", wx.on, "Weather on the front page")
    if wx.source == "ha" then
        rows[#rows + 1] = '<p class="note" style="margin:-4px 0 10px">The weather comes from your Home Assistant.</p>'
    else
        rows[#rows + 1] = input("p_town", "town", "Town for the weather" .. (wx.place and (" (now: " .. esc(wx.place) .. "; leave empty to keep it)") or ""), "",
                'placeholder="Springfield, Illinois" ' .. NAME_ATTRS)
            .. '<label for="p_unit">Degrees</label><select id="p_unit" name="unit" class="sel"><option value=""' .. (not wx.unit and " selected" or "")
            .. '>As the town\'s country uses</option><option value="C"' .. (wx.unit == "C" and " selected" or "") .. '>Celsius</option><option value="F"' .. (wx.unit == "F" and " selected" or "") .. ">Fahrenheit</option></select>"
            .. '<p class="note" style="margin:-4px 0 10px">From Open-Meteo (open-meteo.com), which is sent the town\'s name once and then its rounded coordinates.</p>'
    end
    local topic
    for _i, f in ipairs(p.defaults or {}) do
        if f.topic ~= topic then
            topic = f.topic
            rows[#rows + 1] = '<p style="font-size:14px;margin:12px 0 4px"><b>' .. esc(topic) .. "</b></p>"
        end
        rows[#rows + 1] = tick("d_" .. f.id, f.on, esc(f.name) .. ' <span style="font-size:13px;color:var(--muted)">' .. esc(f.site) .. "</span>")
    end
    if #(p.own or {}) > 0 then
        rows[#rows + 1] = '<p style="font-size:14px;margin:12px 0 4px"><b>Your feeds</b></p>'
        for _i, f in ipairs(p.own) do
            rows[#rows + 1] = tick("f_" .. f.n, f.on, esc(f.name or f.site) .. ' <span style="font-size:13px;color:var(--muted)">' .. esc(f.site)
                .. (f.topic and (" · " .. esc(f.topic)) or "") .. "</span>")
        end
    end
    rows[#rows + 1] = '<input type="hidden" name="count" value="' .. #(p.own or {}) .. '">'
    rows[#rows + 1] = '<button type="submit" style="margin-top:12px">Save</button>'
    parts[#parts + 1] = form(base .. "/paper", table.concat(rows), "Saving…")
    parts[#parts + 1] = '<details class="box"' .. (#(p.own or {}) == 0 and " open" or "") .. "><summary>Add feeds</summary>"
        .. form(base .. "/paper/add",
            '<label for="p_feeds">One feed per line: its address, or <code>Name | address</code>, or <code>Section | Name | address</code></label>'
            .. '<textarea id="p_feeds" name="feeds" rows="4" autocapitalize="off" autocorrect="off" spellcheck="false" required placeholder="https://blog.example.com/feed&#10;Knitting weekly | https://knitting.example.com/rss"></textarea>'
            .. '<button type="submit">Add</button>'
            .. '<p class="note">Most news sites and blogs have a feed; look for “RSS” at the foot of the site, or try its address with <code>/feed</code> or <code>/rss</code> after it. Up to ' .. esc(p.max or "") .. " feeds of your own. Addresses are kept on the Kindle and never written to its log.</p>",
            "Adding…")
        .. "</details>"
    if #(p.own or {}) > 0 then
        local list = { '<details class="box"><summary>Remove a feed</summary>' }
        for _i, f in ipairs(p.own) do
            list[#list + 1] = form(base .. "/paper/remove",
                '<input type="hidden" name="n" value="' .. f.n .. '"><input type="hidden" name="count" value="' .. #p.own .. '">'
                .. '<button class="danger" type="submit"' .. confirmJs("Remove this feed from the paper?") .. ">Remove " .. esc(f.name or f.site)
                .. (f.name and (" (" .. esc(f.site) .. ")") or "") .. "</button>", "Removing…")
        end
        list[#list + 1] = "</details>"
        parts[#parts + 1] = table.concat(list)
    end
    parts[#parts + 1] = '<p class="note">Fetching a feed tells its site this Kindle\'s internet address, as opening the site in a browser would; nothing else is sent.</p></section>'
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
    -- holidays (gzreader_holidays.lua): worked out on the Kindle
    local h = st.holidays
    if h then
        local opts = {}
        for _i, k in ipairs(h.countries or {}) do
            opts[#opts + 1] = '<option value="' .. esc(k.id) .. '"' .. (k.id == h.country and " selected" or "") .. ">" .. esc(k.name) .. "</option>"
        end
        parts[#parts + 1] = '<details class="box"' .. (h.enabled and " open" or "") .. '><summary>Holidays</summary><div style="margin-top:10px">'
            .. form(base .. "/calendar/holidays",
                '<label class="check"><input type="checkbox" name="shown" value="1"' .. (h.enabled and " checked" or "") .. "> Show holidays</label>"
                .. '<label for="h_country">Country</label><select id="h_country" name="country" class="sel">' .. table.concat(opts) .. "</select>"
                .. '<button class="alt small" type="submit">Save</button>'
                .. '<p class="note">A calendar of their own, worked out on the Kindle: no link, account or Wi-Fi needed.</p>', "Saving…")
            .. "</div></details>"
    end
    -- calendar links: a name and a link for each (more with "Add another link")
    local rows = {}
    for i = 1, 3 do
        rows[#rows + 1] = '<div class="pair">'
            .. input("ln_" .. i, "name_" .. i, "Name (optional)", "", 'placeholder="' .. (i == 1 and "Family" or i == 2 and "Work" or "School") .. '" ' .. NAME_ATTRS)
            .. input("lu_" .. i, "url_" .. i, "Calendar link", "", 'placeholder="webcal://calendar.example.com/…" ' .. URL_ATTRS .. (i == 1 and " required" or ""))
            .. "</div>"
    end
    parts[#parts + 1] = '<details class="box"' .. ((#cals == 0 or links.error) and " open" or "") .. '><summary>Add calendar links</summary><div style="margin-top:10px">'
    parts[#parts + 1] = form(base .. "/links",
        '<div id="pairs">' .. table.concat(rows) .. "</div>"
        .. '<p class="js-only"><button class="alt small" type="button" id="more_links">Add another link</button></p>'
        .. '<button type="submit">Add links</button>'
        .. '<p class="note">A name and a link for each calendar (webcal:// or https://….ics); empty rows are skipped. Links are secret: the Kindle keeps them to sync and never writes them to its log.</p>'
        .. '<details><summary>Proton Calendar</summary><p class="note">Proton Calendar on the web: Settings → Calendars → a calendar → Share → Share with anyone → Create link (Full view shows event details). Do this for each calendar.</p></details>'
        .. '<details><summary>Google, Outlook, iCloud</summary><p class="note">Google: Settings → your calendar → Secret address in iCal format. Outlook: Settings → Calendar → Shared calendars → Publish → ICS. iCloud: share a calendar as a Public Calendar.</p></details>',
        "Checking…")
    -- (another name + link row, up to 20; without JavaScript there are three)
    parts[#parts + 1] = '<script>(function(){var b=document.getElementById("more_links"),p=document.getElementById("pairs");if(!b||!p)return;'
        .. 'b.onclick=function(){var n=p.children.length+1;if(n>20)return;var r=p.children[0].cloneNode(true);'
        .. 'r.querySelectorAll("label,input").forEach(function(e){var i=e.getAttribute("id"),f=e.getAttribute("for"),m=e.getAttribute("name");'
        .. 'if(i)e.id=i.replace(/_\\d+$/,"_"+n);if(f)e.setAttribute("for",f.replace(/_\\d+$/,"_"+n));if(m)e.name=m.replace(/_\\d+$/,"_"+n);'
        .. 'if(e.tagName=="INPUT"){e.value="";e.required=false;e.placeholder=/^name/.test(e.name)?"":e.placeholder}});p.appendChild(r);r.querySelector("input").focus()}})()</script>'
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
        '<p class="what">Albums and playlists from your Plex Media Server, to play while you read (the Music tab; turn it on in Settings → Accounts and services → Music → Music tab).</p>' }
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

local SLEEP_LABELS = {
    auto = "The book's cover while reading, a picture from the screensavers folder elsewhere",
    always = "A picture from the screensavers folder, always",
    immich_auto = "The book's cover while reading, a picture from Immich elsewhere",
    immich = "A picture from Immich, always",
}

local function radio(name, value, label, checked)
    return '<label class="check"><input type="radio" name="' .. name .. '" value="' .. esc(value) .. '"' .. (checked and " checked" or "") .. "> " .. esc(label) .. "</label>"
end

local function immichSection(st, base)
    local m = st.immich or {}
    local parts = { '<section id="immich" class="tab"><h2>Immich</h2>',
        '<p class="what">Pictures from one of your <a href="https://immich.app">Immich</a> albums for the sleep screen and the Home wallpaper. The Kindle keeps a few of them (made to fit its screen) and gets new ones now and then on Wi‑Fi.</p>' }
    if m.error then parts[#parts + 1] = '<p class="err">' .. esc(m.error) .. "</p>" end
    if m.connected then
        parts[#parts + 1] = status(true, "Connected to <b>" .. esc(m.host) .. "</b>" .. (m.user and (" as <b>" .. esc(m.user) .. "</b>") or ""))
        -- the album and what it's for
        local opts = { m.album and "" or '<option value="" selected>Choose an album…</option>' }
        local cur = (m.album or {}).id
        local listed = false
        for _i, a in ipairs(m.albums or {}) do
            listed = listed or a.id == cur
            opts[#opts + 1] = '<option value="' .. esc(a.id) .. '"' .. (a.id == cur and " selected" or "") .. ">" .. esc(a.name) .. " (" .. esc(a.count) .. ")</option>"
        end
        if cur and not listed then opts[#opts + 1] = '<option value="' .. esc(cur) .. '" selected>' .. esc(m.album.name) .. "</option>" end
        local counts = {}
        for _i, n in ipairs(m.counts or { 10, 20, 50 }) do
            counts[#counts + 1] = '<option value="' .. n .. '"' .. (n == m.count and " selected" or "") .. ">" .. n .. " pictures</option>"
        end
        local sl = m.sleep
        local immich_sleep = sl == "immich_auto" or sl == "immich"
        parts[#parts + 1] = form(base .. "/immich/use",
            '<label for="i_album">Album</label><select id="i_album" name="album" class="sel">' .. table.concat(opts) .. "</select>"
            .. '<p style="font-size:14px;font-weight:600;margin:4px 0 8px">Sleep screen</p>'
            .. radio("sleep", "immich_auto", SLEEP_LABELS.immich_auto, sl == "immich_auto")
            .. radio("sleep", "immich", SLEEP_LABELS.immich, sl == "immich")
            .. radio("sleep", "none", "Not used for the sleep screen", not immich_sleep)
            .. '<label class="check"><input type="checkbox" name="wallpaper" value="1"' .. (m.wallpaper and " checked" or "") .. "> Home wallpaper: a picture from the album (another one each time new pictures come)</label>"
            .. '<label for="i_count">Pictures kept on the Kindle</label><select id="i_count" name="count" class="sel">' .. table.concat(counts) .. "</select>"
            .. '<button type="submit">Save</button>', "Saving…")
        local where = m.pictures .. (m.pictures == 1 and " picture" or " pictures") .. " on the Kindle"
            .. (m.at and (" · last brought " .. os.date("%Y-%m-%d %H:%M", m.at)) or "")
        parts[#parts + 1] = '<p class="note">' .. esc(where) .. (m.refresh_error and (' · <span class="err">the last try failed (' .. esc(m.refresh_error) .. ")</span>") or "") .. "</p>"
        parts[#parts + 1] = '<div class="two" style="margin-top:12px">' .. form(base .. "/immich/refresh", '<button class="alt small" type="submit">Get new pictures now</button>', "Asking…")
            .. form(base .. "/immich/albums", '<button class="alt small" type="submit">Update the album list</button>', "Asking…") .. "</div>"
        parts[#parts + 1] = form(base .. "/immich/disconnect",
            '<button class="danger" type="submit" style="margin-top:12px"' .. confirmJs("Disconnect Immich? Its pictures are removed from the Kindle; the sleep screen goes back to the screensavers folder.")
            .. ">Disconnect</button>", "Disconnecting…")
        parts[#parts + 1] = "<details><summary>Change the address or API key</summary><div style=\"margin-top:12px\">"
    else
        parts[#parts + 1] = status(false, "Not connected")
    end
    parts[#parts + 1] = form(base .. "/immich",
        input("i_server", "server", "Immich address (or an album's address from your browser)", (m.form or {}).server, 'required placeholder="https://photos.example.com" ' .. URL_ATTRS)
        .. '<label for="i_key">API key</label><input id="i_key" name="key" type="password" required ' .. NAME_ATTRS .. ">"
        .. '<button type="submit">Connect</button>'
        .. '<div class="or">or</div><button class="alt" type="submit" name="action" value="sso" formnovalidate>Sign in with single sign-on (SSO)</button>'
        .. '<p class="note">Single sign-on needs Immich\'s OAuth turned on, and <code>' .. esc(m.redirect_uri or "") .. "</code> as a redirect URI on Immich's client at your identity provider"
        .. (m.sso_relay and " (the same for every Kindle)" or "") .. '. The Kindle then makes an API key for itself in Immich, named “GZreader (this Kindle)”, and keeps only that.</p>'
        .. '<details><summary>Where do I get an API key?</summary><p class="note">In Immich: your picture (top right) → Account Settings → API Keys → New API Key. Give it at least album.read, asset.read and asset.view (or all permissions). The Kindle keeps the key, never your password, and never writes it to its log.</p></details>',
        "Connecting…")
    if m.connected then parts[#parts + 1] = "</div></details>" end
    parts[#parts + 1] = "</section>"
    return table.concat(parts)
end

local function sleepSection(st, base)
    local sl = st.sleep or {}
    local sc = sl.screen or { w = 600, h = 800 }
    local parts = { '<section id="sleep" class="tab"><h2>Sleep screen</h2>',
        '<p class="what">Your own pictures for the sleep screen: made in this browser to fit the Kindle\'s screen (',
        esc(sc.w), " × ", esc(sc.h), sl.colour and ', in colour' or ', in grey', ') and put in its <code>screensavers</code> folder. Nothing is sent anywhere else.</p>' }
    if sl.error then parts[#parts + 1] = '<p class="err">' .. esc(sl.error) .. "</p>" end
    -- which sleep screen
    local mode = sl.mode == "random_image" and "always" or sl.mode
    local radios = { radio("mode", "auto", SLEEP_LABELS.auto, mode == "auto"), radio("mode", "always", SLEEP_LABELS.always, mode == "always") }
    if sl.immich or mode == "immich_auto" or mode == "immich" then
        radios[#radios + 1] = radio("mode", "immich_auto", SLEEP_LABELS.immich_auto, mode == "immich_auto")
        radios[#radios + 1] = radio("mode", "immich", SLEEP_LABELS.immich, mode == "immich")
    end
    if not SLEEP_LABELS[mode or ""] then
        radios[#radios + 1] = '<p class="note" style="margin:0 0 12px">Now: another sleep screen, chosen on the Kindle (Settings → Sleep and wallpaper → Wallpaper).</p>'
    end
    parts[#parts + 1] = form(base .. "/sleep/mode", table.concat(radios) .. '<button class="alt small" type="submit">Use this sleep screen</button>', "Saving…")
    -- adding pictures (made here: the Kindle's size, grey (in colour for a colour screen), PNG)
    local received = {}
    for _i, name in ipairs(sl.received or {}) do received[#received + 1] = '<p class="ok">✓ ' .. esc(name) .. "</p>" end
    parts[#parts + 1] = table.concat({
        '<h3 style="font-size:15px;margin:18px 0 8px">Add pictures</h3>',
        '<div class="drop"><label for="ss_files" style="margin:0">Photos and pictures (JPEG, PNG, and whatever else this browser can open)</label>',
        '<input id="ss_files" type="file" multiple accept="image/*"></div>',
        '<label for="ss_fit">How they fit the screen</label><select id="ss_fit" class="sel"><option value="cover">Fill the screen (edges cropped)</option><option value="contain">Whole picture (white edges)</option></select>',
        '<button id="ss_send" type="button">Send to Kindle</button>',
        '<div id="ss_up">', table.concat(received), '</div>',
        '<script>(function(){var BASE=', string.format("%q", base), ',W=', tonumber(sc.w) or 600, ',H=', tonumber(sc.h) or 800, ',C=', sl.colour and "true" or "false", ';',
        'var f=document.getElementById("ss_files"),b=document.getElementById("ss_send"),out=document.getElementById("ss_up");',
        'function say(t,c){var p=document.createElement("p");p.textContent=t;if(c)p.className=c;out.appendChild(p);return p}',
        'function make(file,fit){return createImageBitmap(file).then(function(img){var c=document.createElement("canvas");c.width=W;c.height=H;var g=c.getContext("2d");g.fillStyle="#fff";g.fillRect(0,0,W,H);',
        'var k=fit=="contain"?Math.min(W/img.width,H/img.height):Math.max(W/img.width,H/img.height),w=img.width*k,h=img.height*k;g.imageSmoothingQuality="high";g.drawImage(img,(W-w)/2,(H-h)/2,w,h);if(img.close)img.close();',
        'if(!C){var d=g.getImageData(0,0,W,H),px=d.data;for(var i=0;i<px.length;i+=4){var y=Math.round(.299*px[i]+.587*px[i+1]+.114*px[i+2]);px[i]=px[i+1]=px[i+2]=y;px[i+3]=255}g.putImageData(d,0,0)}',
        'return new Promise(function(ok,bad){c.toBlob(function(x){x?ok(x):bad(new Error("couldn\'t make the picture"))},"image/png")})})}',
        'b.onclick=function(){var list=[].slice.call(f.files);if(!list.length){say("Choose one or more pictures first.","err");return}var fit=document.getElementById("ss_fit").value,sent=0;',
        'b.disabled=true;b.textContent="Sending…";next();',
        'function next(){var file=list.shift();if(!file){b.disabled=false;b.textContent="Send to Kindle";f.value="";if(sent)say("Reload the page to see them in the list below.","note");return}',
        'var row=say(file.name+" …"),name=(file.name.replace(/\\.[^.]*$/,"")||"picture")+".png";',
        'make(file,fit).then(function(png){var x=new XMLHttpRequest();x.open("POST",BASE+"/sleep/upload?name="+encodeURIComponent(name));',
        'x.onload=function(){var ok=x.status==200;if(ok)sent++;row.textContent=(ok?"✓ ":"✗ ")+x.responseText;row.className=ok?"ok":"err";next()};',
        'x.onerror=function(){row.textContent="✗ "+file.name+": the connection to the Kindle was lost";row.className="err";next()};x.send(png)},',
        'function(){row.textContent="✗ "+file.name+": this browser can\'t open that picture (an iPhone photo: choose it from Photos, which sends a JPEG)";row.className="err";next()})}}})();</script>',
    })
    -- the pictures there
    local rows = {}
    for _i, name in ipairs(sl.names or {}) do
        rows[#rows + 1] = '<div class="row">' .. form(base .. "/sleep/remove",
            '<input type="hidden" name="name" value="' .. esc(name) .. '">'
            .. "<h3>" .. esc(name) .. ' <button class="danger small" type="submit"' .. confirmJs("Take this picture off the Kindle?") .. ">Take off</button></h3>", "Taking off…") .. "</div>"
    end
    parts[#parts + 1] = '<h3 style="font-size:15px;margin:18px 0 8px">On the Kindle</h3>'
    parts[#parts + 1] = #rows > 0 and table.concat(rows) or '<p class="note" style="margin-top:0">No pictures yet: add some, or the Kindle shows its own.</p>'
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
--- base, flash = { ok, text }, grimmory, memos, caldav, links, immich, books, sleep.
function PairPage.hub(st)
    local base = st.base
    local flash = ""
    if st.flash then
        flash = '<div class="flash ' .. (st.flash.ok and "ok" or "bad") .. '">' .. (st.flash.ok and "✓ " or "")
            .. esc(st.flash.text) .. "</div>"
    end
    -- one tab at a time (all of them, one under the other, without JavaScript)
    local tabs = { { "grimmory", "Books", (st.grimmory or {}).connected }, { "notes", "Notes", (st.memos or {}).connected },
        { "calendar", "Calendar", (st.caldav or {}).connected or #((st.links or {}).list or {}) > 0 or (st.holidays or {}).enabled } }
    if st.house then tabs[#tabs + 1] = { "house", "House", st.house.connected } end
    if st.recipes then tabs[#tabs + 1] = { "recipes", "Recipes", st.recipes.connected } end
    if st.paper then tabs[#tabs + 1] = { "paper", "Daily paper", st.paper.enabled } end
    if st.ai then tabs[#tabs + 1] = { "ai", "AI", st.ai.provider ~= nil } end
    if st.plex then tabs[#tabs + 1] = { "music", "Music", st.plex.connected } end
    tabs[#tabs + 1] = { "immich", "Immich", (st.immich or {}).connected }
    tabs[#tabs + 1] = { "books", "Send books" }
    tabs[#tabs + 1] = { "sleep", "Sleep screen" }
    tabs[#tabs + 1] = { "access", "Access", (st.access or {}).enabled }
    if st.diagnostics then tabs[#tabs + 1] = { "diagnostics", "Diagnostics" } end
    local nav = {}
    for _i, t in ipairs(tabs) do
        nav[#nav + 1] = '<a href="#' .. t[1] .. '" data-tab="' .. t[1] .. '">' .. t[2] .. (t[3] and '<span class="d"></span>' or "") .. "</a>"
    end
    local alias = '{"caldav":"calendar","links":"calendar","handwriting":"notes"}'
    return shell("Kindle setup", table.concat({
        "<style>", HUB_STYLE, "</style>",
        "<script>document.documentElement.className='js'</script>",
        "<h1>Set up your Kindle</h1>",
        '<p class="sub">Everything here goes straight to your Kindle over your Wi‑Fi.</p>',
        '<div class="layout"><nav>', table.concat(nav), "</nav><div>",
        flash,
        grimmorySection(st, base), memosSection(st, base), calendarSection(st, base), musicSection(st, base),
        immichSection(st, base), booksSection(st, base), sleepSection(st, base), accessSection(st, base), diagnosticsSection(st, base),
        '<p class="note">This page works while setup is open on the Kindle\'s screen; press Back (or Done) there when you\'re done.</p>',
        houseSection(st, base), -- (after the note: one tab at a time with JavaScript; below the rest without)
        recipesSection(st, base),
        paperSection(st, base),
        aiSection(st, base),
        "</div></div>",
        '<script>(function(){var A=', alias, ';function show(id){id=A[id]||id;var s=document.getElementById(id);if(!s||!/\\btab\\b/.test(s.className))id="', ({ handwriting = "notes", caldav = "calendar", links = "calendar" })[st.start or ""] or st.start or "grimmory", '";',
        '[].forEach.call(document.querySelectorAll("section.tab"),function(e){e.className=e.id==id?"tab on":"tab"});',
        '[].forEach.call(document.querySelectorAll("nav a"),function(a){a.className=a.getAttribute("data-tab")==id?"on":""});',
        'var on=document.querySelector("nav a.on");if(on&&on.scrollIntoView)try{on.scrollIntoView({inline:"center",block:"nearest"})}catch(e){}}',
        '[].forEach.call(document.querySelectorAll("nav a"),function(a){a.onclick=function(e){e.preventDefault();var id=a.getAttribute("data-tab");show(id);history.replaceState(null,"","#"+id);window.scrollTo(0,0)}});',
        'show(location.hash.slice(1));window.onhashchange=function(){show(location.hash.slice(1))}})();</script>',
    }), "hub")
end

return PairPage
