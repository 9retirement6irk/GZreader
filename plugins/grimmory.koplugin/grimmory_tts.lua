--[[--
Read aloud for GZreader on the Kindle Keyboard, using the Kindle's own
text-to-speech voice (the one behind Amazon's "Experimental → Text-to-Speech").

What the diagnostic logs showed on a Kindle 3 (firmware 3.4.3):
- Amazon's speech daemon /usr/sbin/ttsd is running and reachable over lipc:
  com.lab126.ttsd  playSnippetNow / enqueueSnippet (hash properties),
                   cancelSnippetPlayback, pause2, unpause2
  com.lab126.tts   playFile (hash), stop, pause, unpause, TtsISpeed [100],
                   TtsSVoice [Tom]
- KOReader's lipc library doesn't load there, so requests go through the
  Kindle's lipc-hash-prop tool: {key = "string", key2 = (int)} on stdin.
- Amazon never documented the fields. ttsd says in /var/log/messages which
  one it is missing ("enqueueSnippet unable to read id", "… unable to read
  text"), so "Find the Kindle voice" learns the request shape from those
  messages: it adds the missing field, retries, and stops when ttsd accepts
  it; then it asks whether you heard the test sentence. The shape is saved.

Reading: one sentence at a time (crengine sentence boundaries). The sentence
being spoken is highlighted, pages turn by themselves, Shift + Sym plays and
stops (like the stock Kindle). The next sentence starts after a time worked
out from the sentence length and the speed setting.

Reflowable books only (EPUB, FB2, MOBI, AZW3, TXT, HTML); not PDF or comics.
]]

local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local Log = require("grimmory_log")
local _ = require("gettext")
local T = require("ffi/util").template

local OUT_PREFIX = "/tmp/gzreader-tts."

local TTS = {
    -- Where to send speech requests, tried in this order by the discovery.
    TARGETS = {
        { pub = "com.lab126.ttsd", prop = "playSnippetNow" },
        { pub = "com.lab126.ttsd", prop = "enqueueSnippet" },
    },
    -- First guesses for fields ttsd asks for (by name); anything else is
    -- tried as a number, then as a string.
    GUESSES = {
        id = { int = 1 }, priority = { int = 0 }, speed = { int = 100 },
        voice = { str = "Tom" }, lang = { str = "en-US" }, language = { str = "en-US" },
        locale = { str = "en_US" }, model = { str = "full_155mrf22" },
    },
    MAX_ROUNDS = 10,
    BASE_WPM = 165,   -- words per minute at speed 100 (generous, so sentences aren't cut off)
    -- injectable for tests
    lipc = nil,       -- KOReader's libopenlipclua (doesn't load on the Kindle 3)
    exec = nil,       -- function(cmd) running a shell command (default os.execute)
    syslog = "/var/log/messages",
    now = nil,        -- function() -> "yymmdd:HHMMSS" (syslog timestamp format)
    seq = 0,
    testing = false,
}

local function settings() return G_reader_settings end

local function openLipc()
    local lipc = TTS.lipc
    if not lipc then
        local ok, mod = pcall(require, "libopenlipclua")
        if not ok then return nil, "libopenlipclua: " .. tostring(mod) end
        lipc = mod
    end
    local ok, handle = pcall(lipc.open_no_name)
    if not ok or not handle then return nil, "lipc open failed: " .. tostring(handle) end
    return handle
end

local function run(cmd)
    if TTS.exec then return TTS.exec(cmd) end
    return os.execute(cmd)
end

function TTS.backend()
    local h = openLipc()
    if h then pcall(h.close, h); return "lib" end
    return "shell"
end

--- Make text safe inside lipc-hash-prop's quotes.
local function clean(value)
    return (tostring(value):gsub("[\r\n\t]+", " "):gsub('"', "'"):gsub("\\", "/"))
end

--- fields: ordered list of { name, int = n } / { name, str = "s" }.
--- Returns the lipc-hash-prop input, e.g. {text = "Hi", id = (1)}.
function TTS.hashText(fields)
    local parts = {}
    for _i, f in ipairs(fields) do
        if f.int ~= nil then
            parts[#parts + 1] = string.format("%s = (%d)", f[1], f.int)
        else
            parts[#parts + 1] = string.format('%s = "%s"', f[1], clean(f.str))
        end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

--- Run a lipc-hash-prop in the background (the UI never waits on it).
--- Returns the path of its output file: "rc=<n>" is appended when it ends.
local function hashPropAsync(pub, prop, hash)
    TTS.seq = TTS.seq + 1
    -- one input file per call: an earlier call may not have read its own yet
    local hash_file = OUT_PREFIX .. TTS.seq .. ".hash"
    local out = OUT_PREFIX .. TTS.seq .. ".out"
    local f = io.open(hash_file, "wb")
    if not f then return nil, "cannot write " .. hash_file end
    f:write(hash, "\n"); f:close()
    os.remove(out)
    -- pub/prop are constants from TARGETS; the text only goes in the file.
    run(string.format("(lipc-hash-prop %s %s < %s > %s 2>&1; echo \"rc=$?\" >> %s; rm -f %s) &",
        pub, prop, hash_file, out, out, hash_file))
    return out
end

--- Result of a background call: true (ok), false, details (failed), nil (still running).
function TTS.result(out)
    if out == true then return true, "" end
    local f = out and io.open(out, "rb")
    if not f then return nil end
    local text = f:read("*a") or ""
    f:close()
    local rc = tonumber(text:match("rc=(%d+)"))
    if not rc then return nil end
    os.remove(out)
    local body = text:gsub("rc=%d+%s*$", "")
    if rc ~= 0 or body:lower():find("fail") or body:lower():find("error") or body:lower():find("usage") then
        return false, (body ~= "" and body or ("exit code " .. rc))
    end
    return true, body
end

--- Send one request. Returns a result handle for TTS.result, or nil, err.
function TTS.send(target, fields)
    local h = openLipc()
    if not h then
        return hashPropAsync(target.pub, target.prop, TTS.hashText(fields))
    end
    local ok, res = pcall(function()
        local ha = h:new_hasharray()
        ha:add_hash()
        for _i, f in ipairs(fields) do
            if f.int ~= nil then ha:put_int(0, f[1], f.int) else ha:put_string(0, f[1], tostring(f.str)) end
        end
        local out = h:access_hash_property(target.pub, target.prop, ha)
        if out then out:destroy() end
        ha:destroy()
    end)
    pcall(h.close, h)
    if not ok then return nil, tostring(res) end
    return true
end

--- The saved request shape, filled in for `text`.
local function fieldsFor(template, text)
    local fields = {}
    for _i, f in ipairs(template.fields) do
        if f[1] == "text" then
            fields[#fields + 1] = { "text", str = text }
        elseif f[1] == "id" and f.int ~= nil then
            fields[#fields + 1] = { "id", int = TTS.seq + 1 } -- a fresh id per snippet
        else
            fields[#fields + 1] = { f[1], int = f.int, str = f.str }
        end
    end
    return fields
end

function TTS.template() return settings():readSetting("gzreader_tts_template") end

--- Speak `text` with the saved request shape. Returns a result handle
--- (see TTS.result) or nil, err. Never waits for the speech.
function TTS.say(text, template)
    template = template or TTS.template()
    if not template then return nil, "no voice set up" end
    return TTS.send(template.target, fieldsFor(template, text))
end

local function intProp(pub, prop, value)
    local h = openLipc()
    if not h then
        run(string.format("lipc-set-prop -i %s %s %d >/dev/null 2>&1 &", pub, prop, value))
        return
    end
    pcall(h.set_int_property, h, pub, prop, value)
    pcall(h.close, h)
end

function TTS.cancel()
    intProp("com.lab126.ttsd", "cancelSnippetPlayback", 1)
    intProp("com.lab126.tts", "stop", 1)
end

--- Remove leftover result files of background calls.
function TTS.cleanup()
    run("rm -f " .. OUT_PREFIX .. "*.out " .. OUT_PREFIX .. "*.hash >/dev/null 2>&1")
end

function TTS.speed() return settings():readSetting("gzreader_tts_speed") or 100 end

function TTS.setSpeed(v)
    settings():saveSetting("gzreader_tts_speed", v)
    intProp("com.lab126.tts", "TtsISpeed", v)
end

--- Seconds the Kindle needs to say `text` at the current speed.
function TTS.duration(text)
    local words = 0
    for _w in tostring(text):gmatch("%S+") do words = words + 1 end
    local pauses = select(2, tostring(text):gsub("[,;:%.!%?]", ""))
    local wpm = TTS.BASE_WPM * TTS.speed() / 100
    return 0.8 + words * 60 / wpm + pauses * 0.25
end

---------------------------------------------------------------- discovery

local function stamp()
    if TTS.now then return TTS.now() end
    return os.date("%y%m%d:%H%M%S", os.time() - 2) -- a little slack
end

--- The newest ttsd complaint in the system log written at or after `since`.
function TTS.ttsdComplaint(since)
    local f = io.open(TTS.syslog, "rb")
    if not f then return nil end
    local size = f:seek("end") or 0
    f:seek("set", math.max(0, size - 16384))
    local tail = f:read("*a") or ""
    f:close()
    local found
    for line in tail:gmatch("[^\n]+") do
        local ts = line:match("^(%d%d%d%d%d%d:%d%d%d%d%d%d)")
        if ts and ts >= since and line:find("ttsd%[") and line:find("lipc_handling") then found = line end
    end
    return found
end

--- What ttsd wants, from a complaint line: "unable to read id" -> "id".
function TTS.missingField(line)
    if not line then return nil end
    return line:match("unable to read ([%w_]+)") or line:match("bad_([%w_]+):")
end

--- Learn the request shape ttsd accepts. on_done(template_or_nil, why).
function TTS.discover(on_done)
    local ti, rounds = 1, 0
    local fields = { { "text", str = "Voice test." } }
    local tried = {}
    local last_err
    local function attempt()
        rounds = rounds + 1
        local target = TTS.TARGETS[ti]
        if not target or rounds > TTS.MAX_ROUNDS * #TTS.TARGETS then
            return on_done(nil, last_err or "no answer from ttsd")
        end
        local since = stamp()
        local handle, err = TTS.send(target, fields)
        local function wait(n)
            local ok, detail = TTS.result(handle)
            if handle and ok == nil and n < 8 then return UIManager:scheduleIn(0.5, function() wait(n + 1) end) end
            if not handle then ok, detail = false, err end
            local desc = target.prop .. " " .. TTS.hashText(fields)
            if ok then
                Log.info("tts discover: accepted", desc)
                return on_done({ target = target, fields = fields })
            end
            local complaint = TTS.ttsdComplaint(since)
            last_err = complaint or detail
            Log.info("tts discover: rejected", desc, "|", tostring(detail), "|", tostring(complaint))
            local name = TTS.missingField(complaint)
            local next_fields
            if name then
                local key = name
                local existing
                for _i, f in ipairs(fields) do if f[1] == name then existing = f end end
                local guess = TTS.GUESSES[name] or {}
                if not existing and not tried[key .. ":int"] and not (guess.str and not guess.int) then
                    tried[key .. ":int"] = true
                    next_fields = {}
                    for _i, f in ipairs(fields) do next_fields[#next_fields + 1] = f end
                    next_fields[#next_fields + 1] = { name, int = guess.int or 1 }
                elseif not tried[key .. ":str"] then
                    -- added as a number already (or a string is the better guess)
                    tried[key .. ":str"] = true
                    next_fields = {}
                    for _i, f in ipairs(fields) do if f[1] ~= name then next_fields[#next_fields + 1] = f end end
                    next_fields[#next_fields + 1] = { name, str = guess.str or "1" }
                end
            end
            if next_fields then
                fields = next_fields
            else
                -- nothing new to try here: next target, starting over
                ti = ti + 1
                fields = { { "text", str = "Voice test." } }
                tried = {}
            end
            UIManager:scheduleIn(0.5, attempt)
        end
        UIManager:scheduleIn(1, function() wait(0) end)
    end
    attempt()
end

--- Menu action: find the request shape, then check it was heard.
function TTS.findVoice(on_done)
    if TTS.testing then return end
    TTS.testing = true
    Log.info("tts backend", TTS.backend())
    local busy = InfoMessage:new{ text = _("Finding the Kindle's voice… Listen for \"Voice test\"."), timeout = 0 }
    UIManager:show(busy)
    TTS.discover(function(template, why)
        UIManager:close(busy)
        TTS.testing = false
        if not template then
            Log.warn("tts: discovery failed:", tostring(why))
            UIManager:show(InfoMessage:new{ text = T(_("The Kindle's speech service didn't accept any request:\n%1\n\nSave the diagnostic log (Grimmory menu) and send it so this can be fixed."),
                tostring(why):sub(1, 300)) })
            return
        end
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = _("The Kindle's speech service accepted the request. Did you hear \"Voice test\"?"),
            ok_text = _("Yes"),
            cancel_text = _("No"),
            ok_callback = function()
                settings():saveSetting("gzreader_tts_template", template)
                Log.info("tts template saved", template.target.prop, TTS.hashText(template.fields))
                UIManager:show(InfoMessage:new{ text = _("Kindle voice set. Press Shift + Sym while reading to start or stop."), timeout = 4 })
                if on_done then on_done(template) end
            end,
            cancel_callback = function()
                Log.warn("tts: accepted but not heard", template.target.prop, TTS.hashText(template.fields))
                UIManager:show(InfoMessage:new{ text = _("Check the volume (the Kindle's speaker or headphones), then try again. If it stays silent, save the diagnostic log (Grimmory menu) and send it.") })
            end,
        })
        -- say it once more while the question is up
        TTS.say("Voice test.", template)
    end)
end

---------------------------------------------------------------- reader

local Reader = {}
Reader.__index = Reader
TTS.Reader = Reader

function Reader:new(ui)
    return setmetatable({ ui = ui, active = false, paused = false }, self)
end

function Reader:supported()
    local doc = self.ui and self.ui.document
    return doc and not doc.info.has_pages and doc.extendXPointersToSentenceSegment ~= nil
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

--- Sentence starting at (or after) xp: returns text, xp0, xp1 or nil at end.
function Reader:sentenceAt(xp)
    local doc = self.ui.document
    for _try = 1, 20 do
        if not xp then return nil end
        local wend = doc:getNextVisibleWordEnd(xp)
        if not wend then return nil end
        local seg0, seg1 = doc:extendXPointersToSentenceSegment(xp, wend)
        if type(seg0) == "table" then seg0, seg1 = seg0.pos0 or seg0[1], seg0.pos1 or seg0[2] end
        seg0, seg1 = seg0 or xp, seg1 or wend
        local text = trim(doc:getTextFromXPointers(seg0, seg1, false))
        if text ~= "" then
            return text, seg0, seg1
        end
        xp = doc:getNextVisibleWordStart(seg1)
    end
end

function Reader:highlight(xp0, xp1)
    local doc = self.ui.document
    pcall(doc.getTextFromXPointers, doc, xp0, xp1, true) -- crengine draws the selection
    UIManager:setDirty(self.ui.dialog, "ui")
end

function Reader:clearHighlight()
    pcall(self.ui.document.clearSelection, self.ui.document)
    UIManager:setDirty(self.ui.dialog, "ui")
end

--- Make sure xp is on screen, turning pages forward as needed.
function Reader:follow(xp)
    local doc = self.ui.document
    for _i = 1, 4 do
        if doc:isXPointerInCurrentPage(xp) then return true end
        self.turning = true
        self.ui:handleEvent(Event:new("GotoViewRel", 1))
        self.turning = false
    end
    if not doc:isXPointerInCurrentPage(xp) then
        self.turning = true
        self.ui:handleEvent(Event:new("GotoXPointer", xp, xp))
        self.turning = false
    end
    return true
end

function Reader:start()
    if self.active then return end
    if not self:supported() then
        UIManager:show(InfoMessage:new{ text = _("Read aloud works with EPUB, FB2, MOBI, AZW3 and text books, not PDFs or comics.") })
        return
    end
    if not TTS.template() then
        return TTS.findVoice(function() self:start() end)
    end
    self.active, self.paused = true, false
    intProp("com.lab126.tts", "TtsISpeed", TTS.speed())
    self.next_xp = self.ui.document:getXPointer()
    Log.info("tts start")
    UIManager:show(Notification:new{ text = _("Reading aloud. Shift + Sym to stop.") })
    self:speakNext()
end

function Reader:speakNext()
    if not self.active or self.paused then return end
    local text, xp0, xp1 = self:sentenceAt(self.next_xp)
    if not text then
        self:stop()
        UIManager:show(Notification:new{ text = _("End of book.") })
        return
    end
    self.cur = { xp0, xp1 }
    self:follow(xp0)
    self:highlight(xp0, xp1)
    local ok, err = TTS.say(text)
    if not ok then
        Log.warn("tts say failed:", err)
        self:stop()
        UIManager:show(InfoMessage:new{ text = T(_("The Kindle voice didn't respond: %1"), err) })
        return
    end
    if type(ok) == "string" then
        -- shell backend: find out (without waiting) whether the speech
        -- service accepted it; a rejection stops reading with its message
        local out, tries = ok, 0
        local function check()
            tries = tries + 1
            local r, detail = TTS.result(out)
            if r == nil and tries < 4 then return UIManager:scheduleIn(1.5, check) end
            if r == false and self.active then
                Log.warn("tts rejected:", detail)
                self:stop()
                UIManager:show(InfoMessage:new{ text = T(_("The Kindle voice didn't respond: %1"), detail) })
            end
        end
        UIManager:scheduleIn(1.5, check)
    end
    self.next_xp = self.ui.document:getNextVisibleWordStart(xp1)
    self.timer = function() self.timer = nil; self:speakNext() end
    UIManager:scheduleIn(TTS.duration(text), self.timer)
end

function Reader:stop()
    if self.timer then UIManager:unschedule(self.timer); self.timer = nil end
    if self.active then Log.info("tts stop") end
    local was_active = self.active
    self.active, self.paused = false, false
    TTS.cancel()
    if was_active then TTS.cleanup() end
    self:clearHighlight()
end

function Reader:toggle()
    if self.active then self:stop() else self:start() end
end

--- A page turned by the reader (not by us): continue from the new page.
function Reader:onManualPageTurn()
    if not self.active or self.turning then return end
    if self.timer then UIManager:unschedule(self.timer); self.timer = nil end
    TTS.cancel()
    self.next_xp = self.ui.document:getXPointer()
    UIManager:scheduleIn(0.3, function() self:speakNext() end)
end

return TTS
