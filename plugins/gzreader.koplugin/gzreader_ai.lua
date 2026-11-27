--[[--
The AI connection: one key of your own for everything in GZreader that asks
an AI service something. Settings → Accounts and services → AI, and the
setup page's AI tab.

Used by:
- handwriting to text (gzreader_handwriting.lua): a picture of the writing;
- the daily paper's AI edition (gzreader_daily.lua): a story's headline and
  text, for its summary;
- whatever comes next: `AI.ask` (from the screen, in the background) or
  `AI.complete` (inside a background job).

Two kinds of service:
- **Claude** (Anthropic's Messages API): a key, and a model's name if not the
  usual one;
- **an online service (OpenAI-style)**: anything that speaks OpenAI's Chat
  Completions API (OpenAI itself, a model you run): its address, a key, a
  model's name.

Nothing is sent until a key is given and something that uses it is switched
on. Keys are kept with GZreader's other sign-ins, off the USB drive
(gzreader_secrets.lua), never written to the log and never sent back to the
setup page.

  store.ai = { provider = "claude" | "openai" }          -- which one, when both are set up
  store.handwriting.claude = { key, model }              -- (where the keys were before this
  store.handwriting.openai = { url, key, model }         --  was a connection of its own)
]]

local Log = require("gzreader_log")

local AI = {
    TIMEOUT = 60, -- (s) an answer at most
    CLAUDE_URL = "https://api.anthropic.com/v1/messages",
    CLAUDE_MODEL = "claude-haiku-5-5",
    CLAUDE_VERSION = "2023-06-01",
    OPENAI_URL = "https://api.openai.com/v1",
}

---------------------------------------------------------------- settings

--- { provider = the one chosen (may be nil), claude = { key, model },
--- openai = { url, key, model } }: the tables kept, to change in place.
function AI.settings(plugin)
    local store = plugin and plugin.store
    if not store then return { claude = {}, openai = {} } end
    local hw = type(store.handwriting) == "table" and store.handwriting or {}
    store.handwriting = hw
    hw.claude = type(hw.claude) == "table" and hw.claude or {}
    hw.openai = type(hw.openai) == "table" and hw.openai or {}
    local ai = type(store.ai) == "table" and store.ai or {}
    store.ai = ai
    return { provider = ai.provider, claude = hw.claude, openai = hw.openai }
end

--- Is a service set up? ("claude": a key; "openai": a key and a model.)
function AI.ready(plugin, provider)
    local s = AI.settings(plugin)
    if provider == "claude" then return (s.claude.key or "") ~= "" end
    if provider == "openai" then return (s.openai.key or "") ~= "" and (s.openai.model or "") ~= "" end
    return AI.provider(plugin) ~= nil
end

--- The service in use: the one chosen when it's set up, else the one that
--- is (Claude first); nil when neither.
function AI.provider(plugin)
    local s = AI.settings(plugin)
    local function ok(p)
        if p == "claude" then return (s.claude.key or "") ~= "" end
        return p == "openai" and (s.openai.key or "") ~= "" and (s.openai.model or "") ~= ""
    end
    if ok(s.provider) then return s.provider end
    if ok("claude") then return "claude" end
    if ok("openai") then return "openai" end
    return nil
end

function AI.setProvider(plugin, provider)
    if provider ~= "claude" and provider ~= "openai" then return false end
    AI.settings(plugin)
    plugin.store.ai.provider = provider
    return true
end

--- A service's name for a person.
function AI.name(provider)
    local _ = require("gettext")
    if provider == "claude" then return "Claude" end
    if provider == "openai" then return _("Online service") end
    return _("not set up")
end

--- Take both keys off the Kindle.
function AI.clear(plugin)
    local s = AI.settings(plugin)
    s.claude.key, s.openai.key = nil, nil
    plugin.store.ai.provider = nil
end

--- Is `url` one a key may be sent to? HTTPS; plain HTTP only to this network
--- (a model on your own computer).
function AI.safeUrl(url)
    if type(url) ~= "string" then return false end
    if url:match("^https://[%w%.%-]+") then return true end
    local host = url:match("^http://([%w%.%-]+)")
    if not host then return false end
    return host == "localhost" or host:match("^127%.") ~= nil or host:match("^10%.") ~= nil
        or host:match("^192%.168%.") ~= nil or host:match("^172%.1[6-9]%.") ~= nil
        or host:match("^172%.2%d%.") ~= nil or host:match("^172%.3[01]%.") ~= nil
end

--- What a job needs to ask, copied (a background job has no plugin):
--- { provider, cfg = { key, model, url } }, or nil when nothing is set up.
function AI.snapshot(plugin)
    local provider = AI.provider(plugin)
    if not provider then return nil end
    local c = AI.settings(plugin)[provider]
    return { provider = provider, cfg = { key = c.key, model = c.model, url = c.url } }
end

---------------------------------------------------------------- asking

--- A conversation's messages: `history` ({ role = "user" | "assistant", text }
--- each, oldest first: what was asked and answered before), then `last`.
function AI.withHistory(history, last)
    local out = {}
    for _i, h in ipairs(type(history) == "table" and history or {}) do
        if type(h) == "table" and type(h.text) == "string" and h.text ~= "" and (h.role == "user" or h.role == "assistant") then
            out[#out + 1] = { role = h.role, content = h.text }
        end
    end
    out[#out + 1] = last
    return out
end

--- The request for a question: url, headers, body (JSON).
--- `q` = { text = what to do, png = a picture's base64 (optional),
--- system = standing instructions (optional), max_tokens, history = the
--- conversation before it (optional: AI.withHistory) }.
function AI.request(provider, cfg, q)
    local Json = require("gzreader_json")
    local max_tokens = q.max_tokens or 1024
    if provider == "claude" then
        local content = {}
        if q.png then content[#content + 1] = { type = "image", source = { type = "base64", media_type = "image/png", data = q.png } } end
        content[#content + 1] = { type = "text", text = q.text }
        local body = {
            model = (cfg.model or "") ~= "" and cfg.model or AI.CLAUDE_MODEL,
            max_tokens = max_tokens,
            messages = AI.withHistory(q.history, { role = "user", content = content }),
        }
        if q.system then body.system = q.system end
        return AI.CLAUDE_URL, {
            ["x-api-key"] = cfg.key,
            ["anthropic-version"] = AI.CLAUDE_VERSION,
            ["content-type"] = "application/json",
        }, Json.encode(body)
    end
    local base = ((cfg.url or "") ~= "" and cfg.url or AI.OPENAI_URL):gsub("/+$", "")
    local url = base:match("/chat/completions$") and base or (base .. "/chat/completions")
    local content = { { type = "text", text = q.text } }
    if q.png then content[#content + 1] = { type = "image_url", image_url = { url = "data:image/png;base64," .. q.png } } end
    local messages = {}
    if q.system then messages[#messages + 1] = { role = "system", content = q.system } end
    for _i, m in ipairs(AI.withHistory(q.history, { role = "user", content = content })) do messages[#messages + 1] = m end
    return url, { ["Authorization"] = "Bearer " .. tostring(cfg.key), ["Content-Type"] = "application/json" },
        Json.encode({ model = cfg.model, max_tokens = max_tokens, messages = messages })
end

--- The text in a service's answer (`code`, `body`), or nil and a reason a person can read.
function AI.answerText(provider, code, body)
    local Json = require("gzreader_json")
    local ok, data = pcall(Json.decode, body or "")
    data = ok and type(data) == "table" and data or nil
    if code ~= 200 then
        local msg = data and type(data.error) == "table" and data.error.message
        if code == 401 or code == 403 then return nil, "the key was refused (" .. tostring(code) .. ")" end
        if code == 404 then return nil, "no such model or address (404)" end
        if code == 429 then return nil, "too many requests for now (429)" end
        return nil, "the service answered " .. tostring(code) .. (msg and (": " .. tostring(msg):sub(1, 120)) or "")
    end
    if not data then return nil, "the answer wasn't readable" end
    local text
    if provider == "claude" then
        local parts = {}
        for _i, c in ipairs(type(data.content) == "table" and data.content or {}) do
            if type(c) == "table" and c.type == "text" and type(c.text) == "string" then parts[#parts + 1] = c.text end
        end
        text = table.concat(parts)
    else
        local ch = type(data.choices) == "table" and data.choices[1]
        local m = type(ch) == "table" and ch.message
        text = type(m) == "table" and m.content
        if type(text) == "table" then -- (content as parts)
            local parts = {}
            for _i, c in ipairs(text) do if type(c) == "table" and type(c.text) == "string" then parts[#parts + 1] = c.text end end
            text = table.concat(parts)
        end
    end
    if type(text) ~= "string" then return nil, "the answer had no text" end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    -- (a model that wraps its answer anyway: quotes or a code fence off)
    text = text:gsub("^```%w*\n(.-)\n```$", "%1"):gsub('^"(.*)"$', "%1")
    return text
end

--- POST `body` to `url` (blocking: call it in a background process): code, body or nil, why.
function AI.post(url, headers, body, timeout)
    local ltn12 = require("ltn12")
    local socketutil = require("socketutil")
    local https = url:match("^https:") and require("ssl.https") or require("socket.http")
    local chunks = {}
    headers["Content-Length"] = tostring(#body)
    socketutil:set_timeout(20, timeout or AI.TIMEOUT)
    local ok, r, code = pcall(https.request, {
        url = url, method = "POST", headers = headers,
        source = ltn12.source.string(body), sink = ltn12.sink.table(chunks),
    })
    socketutil:reset_timeout()
    if not ok then return nil, tostring(r) end
    if r == nil then return nil, tostring(code) end
    return tonumber(code), table.concat(chunks)
end

--- Ask and wait (inside a background job): the answer's text, or nil and why.
--- `snap` = AI.snapshot(plugin); `post` stands in for AI.post in tests.
function AI.complete(snap, q, post)
    if not snap then return nil, "no AI key" end
    local url, headers, body = AI.request(snap.provider, snap.cfg, q)
    if not AI.safeUrl(url) then return nil, "the address must start with https://" end
    local code, rbody = (post or AI.post)(url, headers, body, q.timeout)
    if not code then return nil, rbody == "timeout" and "it took too long" or ("no answer (" .. tostring(rbody) .. ")") end
    return AI.answerText(snap.provider, code, rbody)
end

--- Ask from the screen: in the background, Wi-Fi turned on as set;
--- on_done(text) or on_done(nil, why). `q.what` names the use in the log
--- (never what's asked, nor the key).
function AI.ask(plugin, q, on_done)
    local snap = AI.snapshot(plugin)
    if not snap then return on_done(nil, "no AI key") end
    local url, headers, body = AI.request(snap.provider, snap.cfg, q)
    if not AI.safeUrl(url) then return on_done(nil, "the address must start with https://") end
    local what = q.what or "ai"
    Log.info(string.format("%s: asking %s (%s), %d KB", what, snap.provider, url:match("^https?://([^/]+)") or "?", math.floor(#body / 1024)))
    local t0 = os.time()
    require("gzreader_net").run(function()
        require("gzreader_async").background(function() return AI.post(url, headers, body, q.timeout) end, function(code, rbody)
            if not code then
                Log.warn(what .. ": no answer:", tostring(rbody))
                return on_done(nil, rbody == "timeout" and "it took too long" or "no answer (" .. tostring(rbody) .. ")")
            end
            local text, why = AI.answerText(snap.provider, code, rbody)
            Log.info(what .. ": answered", code, "in", os.time() - t0, "s", text and (#text .. " characters") or why)
            on_done(text, why)
        end, what, { timeout = (q.timeout or AI.TIMEOUT) + 10 })
    end, { reason = q.reason or what })
end

---------------------------------------------------------------- Settings → Accounts and services → AI

--- What uses the key now, for a person: { "Handwriting to text", … }. A new
--- use adds its line here.
function AI.uses(plugin)
    local _ = require("gettext")
    local out = {}
    if AI.ready(plugin) then out[#out + 1] = _("Explain and Translate (the question mark and Translate when you select text in a book)") end
    local okh, Hw = pcall(require, "gzreader_handwriting")
    if okh and Hw.engine(plugin) ~= "kindle" then out[#out + 1] = _("Handwriting to text") end
    local okd, D = pcall(require, "gzreader_daily")
    if okd and D.aiOn(plugin) then out[#out + 1] = _("The daily paper's AI edition") end
    return out
end

function AI.settingsItems(plugin)
    local _ = require("gettext")
    local T = require("ffi/util").template
    local UIManager = require("ui/uimanager")
    local s = AI.settings(plugin)
    local function save() if plugin.save then plugin:save() end end
    local function note(text, timeout)
        UIManager:show(require("ui/widget/infomessage"):new{ text = text, timeout = timeout })
    end
    local function ask(title, value, hint, password, on_done)
        local InputDialog = require("ui/widget/inputdialog")
        local d
        d = InputDialog:new{ title = title, input = value or "", input_hint = hint, text_type = password and "password" or nil,
            buttons = { { { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
                { text = _("Save"), is_enter_default = true, callback = function()
                    local v = (d:getInputText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    UIManager:close(d)
                    on_done(v)
                end } } } }
        UIManager:show(d)
        d:onShowKeyboard()
    end
    local function keyLabel(k) return (k or "") ~= "" and _("set") or _("not set") end
    local function choose(p)
        AI.setProvider(plugin, p)
        save()
        Log.info("ai: service chosen:", p)
    end
    return {
        { text = _("Set up from your browser (QR code)"),
          help_text = _("The setup page's AI tab: choose the service and paste the key from your phone or computer instead of typing it here."),
          callback = function(tm)
              if tm and tm.closeMenu then tm:closeMenu() end
              require("gzreader_phone").open(plugin, { section = "ai" })
          end, separator = true },
        { text = "Claude", radio = true,
          help_text = _("Anthropic's Claude. Needs an API key from console.anthropic.com (paid by use: reading a few handwritten words costs a fraction of a cent)."),
          enabled_func = function() return AI.ready(plugin, "claude") end,
          checked_func = function() return AI.provider(plugin) == "claude" end, callback = function() choose("claude") end },
        { text = _("Online service (OpenAI-style)"), radio = true,
          help_text = _("Any service that speaks OpenAI's Chat Completions API: OpenAI itself, or a model you run yourself. Needs its address, a key and a model's name. For handwriting the model must read pictures."),
          enabled_func = function() return AI.ready(plugin, "openai") end,
          checked_func = function() return AI.provider(plugin) == "openai" end, callback = function() choose("openai") end,
          separator = true },
        { text_func = function() return T(_("Claude key: %1"), keyLabel(s.claude.key)) end, keep_menu_open = true,
          callback = function(tm)
              ask(_("Claude API key"), "", "sk-ant-…", true, function(v)
                  s.claude.key = v ~= "" and v or nil
                  if v ~= "" then AI.setProvider(plugin, "claude") end
                  save()
                  Log.info("ai: Claude key", v ~= "" and "set" or "removed")
                  if tm then tm:updateItems() end
              end)
          end },
        { text_func = function() return T(_("Claude model: %1"), (s.claude.model or "") ~= "" and s.claude.model or AI.CLAUDE_MODEL) end,
          keep_menu_open = true,
          callback = function(tm)
              ask(_("Claude model"), s.claude.model or AI.CLAUDE_MODEL, AI.CLAUDE_MODEL, false, function(v)
                  s.claude.model = v ~= "" and v or nil
                  save()
                  if tm then tm:updateItems() end
              end)
          end, separator = true },
        { text_func = function() return T(_("Service address: %1"), (s.openai.url or "") ~= "" and s.openai.url or AI.OPENAI_URL) end,
          keep_menu_open = true,
          callback = function(tm)
              ask(_("Service address"), s.openai.url or AI.OPENAI_URL, "https://…/v1", false, function(v)
                  if v ~= "" and not AI.safeUrl(v) then
                      return note(_("The address must start with https:// (http:// only for a computer on this network)."), 4)
                  end
                  s.openai.url = v ~= "" and v or nil
                  save()
                  if tm then tm:updateItems() end
              end)
          end },
        { text_func = function() return T(_("Service key: %1"), keyLabel(s.openai.key)) end, keep_menu_open = true,
          callback = function(tm)
              ask(_("Service key"), "", "sk-…", true, function(v)
                  s.openai.key = v ~= "" and v or nil
                  save()
                  Log.info("ai: service key", v ~= "" and "set" or "removed")
                  if tm then tm:updateItems() end
              end)
          end },
        { text_func = function() return T(_("Service model: %1"), (s.openai.model or "") ~= "" and s.openai.model or _("not set")) end,
          keep_menu_open = true,
          callback = function(tm)
              ask(_("Model"), s.openai.model or "", _("the model's name"), false, function(v)
                  s.openai.model = v ~= "" and v or nil
                  if v ~= "" and (s.openai.key or "") ~= "" and not AI.ready(plugin, "claude") then AI.setProvider(plugin, "openai") end
                  save()
                  if tm then tm:updateItems() end
              end)
          end, separator = true },
        { text = _("Try it"),
          help_text = _("Asks the service for one word, to check the key, the model and the address."),
          enabled_func = function() return AI.ready(plugin) end, keep_menu_open = true,
          callback = function()
              local name = AI.name(AI.provider(plugin))
              note(T(_("Asking %1…"), name), 2)
              AI.ask(plugin, { text = "Reply with the single word: ready", max_tokens = 16, what = "ai test", timeout = 30 }, function(text, why)
                  if text then note(T(_("%1 answered. The key works."), name))
                  else note(T(_("%1 didn't answer: %2."), name, tostring(why))) end
              end)
          end },
        { text_func = function()
              local uses = AI.uses(plugin)
              return #uses == 0 and _("Used for: nothing yet") or T(_("Used for: %1"), table.concat(uses, ", "))
          end,
          help_text = _("Handwriting to text: Settings → Accounts and services → Notes → Handwriting to text. The daily paper's AI edition: Settings → Accounts and services → Daily paper → AI edition."),
          keep_menu_open = true,
          callback = function()
              note(_("Switch each on where it lives:\n\n• Handwriting to text: Notes → Handwriting to text\n• The daily paper's AI edition: Daily paper → AI edition\n\nOnly what's needed is sent: the writing being read, as a picture, or a news story's headline and text for its summary."))
          end },
        { text = _("Remove the keys"),
          enabled_func = function() return (s.claude.key or "") ~= "" or (s.openai.key or "") ~= "" end, keep_menu_open = true,
          callback = function(tm)
              UIManager:show(require("ui/widget/confirmbox"):new{
                  text = _("Remove the AI keys from this Kindle? Handwriting is then read on the Kindle, and the daily paper is the ordinary one."),
                  ok_text = _("Remove"),
                  ok_callback = function()
                      AI.clear(plugin)
                      save()
                      Log.info("ai: keys removed")
                      if tm then tm:updateItems() end
                  end })
          end },
    }
end

return AI
