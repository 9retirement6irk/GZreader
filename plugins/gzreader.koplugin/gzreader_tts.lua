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
local Log = require("gzreader_log")
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
    TEST_TEXT = "This is the Kindle voice test. ",
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
local function fieldsFor(template, text, id)
    local fields = {}
    for _i, f in ipairs(template.fields) do
        if f[1] == "text" then
            -- ttsd holds back the last word until more text arrives; a
            -- trailing space lets it see that the word is complete
            fields[#fields + 1] = { "text", str = text .. " " }
        elseif f[1] == "id" and f.int ~= nil then
            fields[#fields + 1] = { "id", int = id or (TTS.seq + 1) } -- a fresh id per snippet
        else
            fields[#fields + 1] = { f[1], int = f.int, str = f.str }
        end
    end
    return fields
end

function TTS.template() return settings():readSetting("gzreader_tts_template") end

TTS.next_id = 100

--- Speak `text` with the saved request shape. opts.enqueue: queue it after
--- what is playing (ttsd's enqueueSnippet) instead of replacing it.
--- Returns a result handle (see TTS.result) and the snippet id, or nil, err.
--- Never waits for the speech.
function TTS.say(text, template, opts)
    template = template or TTS.template()
    if not template then return nil, "no voice set up" end
    opts = opts or {}
    TTS.next_id = TTS.next_id + 1
    local id = TTS.next_id
    local target = template.target
    if opts.enqueue and target.pub == "com.lab126.ttsd" then
        target = { pub = target.pub, prop = "enqueueSnippet" }
    end
    local handle, err = TTS.send(target, fieldsFor(template, text, id))
    if not handle then return nil, err end
    return handle, id
end

---------------------------------------------------------------- ttsd events

-- ttsd announces snippetStarted / snippetFinished (with the snippet id) over
-- lipc; lipc-wait-event writes them to a file we read. That paces reading by
-- the real speech instead of an estimate (estimates are the fallback).
TTS.EVENTS_FILE = OUT_PREFIX .. "events"
local events_offset = 0

function TTS.startEvents()
    TTS.stopEvents()
    os.remove(TTS.EVENTS_FILE)
    events_offset = 0
    run(string.format("(lipc-wait-event -m com.lab126.ttsd snippetStarted,snippetFinished > %s 2>&1 & echo $! > %s.pid) >/dev/null 2>&1",
        TTS.EVENTS_FILE, TTS.EVENTS_FILE))
end

function TTS.stopEvents()
    local f = io.open(TTS.EVENTS_FILE .. ".pid", "rb")
    local pid = f and tonumber(f:read("*a"))
    if f then f:close() end
    if pid then run("kill " .. pid .. " >/dev/null 2>&1") end
    os.remove(TTS.EVENTS_FILE .. ".pid")
end

--- New events since the last call: list of { name = "started"|"finished", id = n }.
function TTS.readEvents()
    local f = io.open(TTS.EVENTS_FILE, "rb")
    if not f then return {} end
    f:seek("set", events_offset)
    local chunk = f:read("*a") or ""
    f:close()
    -- only whole lines
    local last_nl = chunk:match(".*()\n")
    if not last_nl then return {} end
    chunk = chunk:sub(1, last_nl)
    events_offset = events_offset + #chunk
    local out = {}
    for line in chunk:gmatch("[^\n]+") do
        local kind = line:match("snippet(%a+)")
        local id = tonumber(line:match("(%d+)%s*$"))
        if kind and id then
            out[#out + 1] = { name = kind:lower(), id = id }
        end
    end
    return out
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

--- Like TTS.cancel, but waits until ttsd has it (so a request sent right
--- after can't be cancelled by it).
function TTS.cancelNow()
    local h = openLipc()
    if h then
        pcall(h.set_int_property, h, "com.lab126.ttsd", "cancelSnippetPlayback", 1)
        pcall(h.close, h)
        return
    end
    run("lipc-set-prop -i com.lab126.ttsd cancelSnippetPlayback 1 >/dev/null 2>&1")
end

--- Remove leftover result files of background calls.
function TTS.cleanup()
    run("rm -f " .. OUT_PREFIX .. "*.out " .. OUT_PREFIX .. "*.hash >/dev/null 2>&1")
end

function TTS.speed() return settings():readSetting("gzreader_tts_speed") or 100 end

--- Speaker volume, 0-15 (com.lab126.audio CmdIVolume; the Kindle's own range).
TTS.VOLUME_MAX = 15
function TTS.volume() return settings():readSetting("gzreader_tts_volume") or 10 end

function TTS.setVolume(v)
    v = math.max(0, math.min(TTS.VOLUME_MAX, v))
    settings():saveSetting("gzreader_tts_volume", v)
    intProp("com.lab126.audio", "CmdIVolume", v)
end

function TTS.applySettings()
    intProp("com.lab126.tts", "TtsISpeed", TTS.speed())
    if settings():readSetting("gzreader_tts_volume") then
        intProp("com.lab126.audio", "CmdIVolume", TTS.volume())
    end
end

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
    return 0.4 + words * 60 / wpm + pauses * 0.2
end

---------------------------------------------------------------- discovery

local function stamp()
    if TTS.now then return TTS.now() end
    -- the Kindle writes its system log in its own (UTC) clock, whatever time
    -- zone GZreader shows
    return os.date("!%y%m%d:%H%M%S", os.time() - 2) -- a little slack
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
    local fields = { { "text", str = TTS.TEST_TEXT } }
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
                fields = { { "text", str = TTS.TEST_TEXT } }
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
    local busy = InfoMessage:new{ text = _("Finding the Kindle's voice… Listen for \"This is the Kindle voice test\"."), timeout = 0 }
    UIManager:show(busy)
    TTS.discover(function(template, why)
        UIManager:close(busy)
        TTS.testing = false
        if not template then
            Log.warn("tts: discovery failed:", tostring(why))
            UIManager:show(InfoMessage:new{ text = T(_("The Kindle's speech service didn't accept any request:\n%1\n\nSave the diagnostic log (Settings → General) and send it so this can be fixed."),
                tostring(why):sub(1, 300)) })
            return
        end
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = _("The Kindle's speech service accepted the request. Did you hear \"This is the Kindle voice test\"?"),
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
                UIManager:show(InfoMessage:new{ text = _("Check the volume (the Kindle's speaker or headphones), then try again. If it stays silent, save the diagnostic log (Settings → General) and send it.") })
            end,
        })
        -- say it once more while the question is up
        TTS.say(TTS.TEST_TEXT, template)
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

-- A sentence is spoken as one piece. Very long ones are split at a comma,
-- semicolon, colon or dash once they reach CLAUSE_WORDS (never mid-clause
-- before MAX_WORDS); paragraph ends always end a piece.
Reader.CLAUSE_WORDS = 30
Reader.MAX_WORDS = 80

local SENTENCE_END = "[%.!%?…]['\"”’%)%]]*$"
local CLAUSE_END = "[,;:—–]['\"”’%)%]]*$"

--- What the voice says for a piece of text: web addresses are left out.
function TTS.speakable(text)
    text = tostring(text or "")
    text = text:gsub("[Hh][Tt][Tt][Pp][Ss]?://%S+", " ")
    text = text:gsub("[Ww][Ww][Ww]%.%S+%.%S+", " ")
    text = text:gsub("%s+", " ")
    return trim(text)
end

local function pageOf(doc, xp)
    if not xp or type(doc.getPageFromXPointer) ~= "function" then return nil end
    local ok, p = pcall(doc.getPageFromXPointer, doc, xp)
    return ok and p or nil
end

--- Sentence starting at (or after) xp: returns text, xp0, xp1, extra or nil
--- at the end. extra.turn_xp / extra.turn_frac: where the sentence crosses
--- onto the next page and how far into it (by characters), so the page can
--- turn while it's being said.
function Reader:sentenceAt(xp)
    local doc = self.ui.document
    if not xp then return nil end
    local first_end = doc:getNextVisibleWordEnd(xp)
    if not first_end then return nil end
    local start = xp
    local last_end = first_end
    local cur_end = first_end
    local start_page = pageOf(doc, start)
    local turn_xp
    for n = 1, Reader.MAX_WORDS do
        last_end = cur_end
        local word = trim(doc:getTextFromXPointers(doc:getPrevVisibleWordStart(cur_end) or start, cur_end, false))
        if word:find(SENTENCE_END) then break end
        if n >= Reader.CLAUSE_WORDS and word:find(CLAUSE_END) then break end
        local next_start = doc:getNextVisibleWordStart(cur_end)
        if not next_start then break end
        -- a paragraph (or heading, list item) ends here
        local gap = doc:getTextFromXPointers(cur_end, next_start, false) or ""
        if gap:find("\n") then break end
        local next_end = doc:getNextVisibleWordEnd(next_start)
        if not next_end or next_end == cur_end then break end
        if not turn_xp and start_page then
            local p = pageOf(doc, next_start)
            if p and p > start_page then turn_xp = next_start end
        end
        cur_end = next_end
    end
    local text = trim(doc:getTextFromXPointers(start, last_end, false))
    if text == "" then
        local nxt = doc:getNextVisibleWordStart(last_end)
        if not nxt or nxt == xp then return nil end
        return self:sentenceAt(nxt)
    end
    local extra
    if turn_xp then
        local before = #trim(doc:getTextFromXPointers(start, turn_xp, false))
        extra = { turn_xp = turn_xp, turn_frac = math.max(0, math.min(1, before / math.max(1, #text))) }
    end
    return text, start, last_end, extra
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

Reader.AHEAD = 2       -- sentences handed to ttsd ahead of what is being spoken
Reader.POLL = 0.4
Reader.EVENTS_GRACE = 4 -- seconds to wait for a first ttsd event before using estimates

function Reader:start()
    if self.active then return end
    if not self:supported() then
        UIManager:show(InfoMessage:new{ text = _("Read aloud works with EPUB, FB2, MOBI, AZW3 and text books, not PDFs or comics.") })
        return
    end
    if not TTS.template() then
        return TTS.findVoice(function() self:start() end)
    end
    -- the Kindle voice needs the sound device: no audiobook player holding it
    pcall(function() require("gzreader_abfolder").releaseAudio("read aloud", true) end)
    self.active, self.paused = true, false
    TTS.applySettings()
    TTS.startEvents()
    self.events_ok = nil
    self.started_at = os.time()
    self.next_xp = self.ui.document:getXPointer()
    Log.info("tts start")
    pcall(function() require("gzreader_usage").ttsStart() end)
    UIManager:show(Notification:new{ text = _("Reading aloud. Shift + Sym to stop.") })
    self:restartQueue()
    self.poller = function() self.poller_scheduled = false; self:poll() end
    self:schedulePoll()
end

function Reader:schedulePoll()
    if self.active and not self.poller_scheduled then
        self.poller_scheduled = true
        UIManager:scheduleIn(Reader.POLL, self.poller)
    end
end

--- Throw away what is queued and start from self.next_xp.
function Reader:restartQueue()
    if self.timer then UIManager:unschedule(self.timer); self.timer = nil end
    if self.turn_timer then UIManager:unschedule(self.turn_timer); self.turn_timer = nil end
    self.queue = {}
    self.outbox = {}
    self.no_more = false
    self.generation = (self.generation or 0) + 1
    -- Everything goes through ttsd's queue (enqueueSnippet). playSnippetNow
    -- flushes that queue, and requests sent close together could reach ttsd
    -- out of order, which dropped whole sentences (seen on a Kindle 3).
    TTS.cancelNow()
    self:fill()
    self:playHead()
end

--- Keep Reader.AHEAD sentences handed to ttsd.
function Reader:fill()
    while self.active and not self.no_more and #self.queue < Reader.AHEAD do
        local text, xp0, xp1, extra = self:sentenceAt(self.next_xp)
        if not text then self.no_more = true; break end
        self.next_xp = self.ui.document:getNextVisibleWordStart(xp1)
        local spoken = TTS.speakable(text)
        if spoken:find("%w") then -- a piece that was only a web link is skipped
            local item = { text = spoken, xp0 = xp0, xp1 = xp1,
                turn_xp = extra and extra.turn_xp, turn_frac = extra and extra.turn_frac }
            self.queue[#self.queue + 1] = item
            self.outbox[#self.outbox + 1] = item
        end
        if not self.next_xp then self.no_more = true; break end
    end
    self:sendNext()
    if self.active and #self.queue == 0 and self.no_more then
        self:stop()
        UIManager:show(Notification:new{ text = _("End of book.") })
    end
end

--- Send queued sentences to ttsd one at a time, each only after ttsd has
--- answered the previous request, so they arrive in order.
function Reader:sendNext()
    if not self.active or self.sending or #self.outbox == 0 then return end
    local item = table.remove(self.outbox, 1)
    local handle, id = TTS.say(item.text, nil, { enqueue = true })
    if not handle then
        Log.warn("tts say failed:", id)
        self:stop()
        UIManager:show(InfoMessage:new{ text = T(_("The Kindle voice didn't respond: %1"), id) })
        return
    end
    item.id = id
    if type(handle) ~= "string" then return self:sendNext() end -- answered already (lipc library)
    self.sending = handle
    local gen, tries = self.generation, 0
    local function check()
        if not self.active or gen ~= self.generation then self.sending = nil; return end
        tries = tries + 1
        local r, detail = TTS.result(handle)
        if r == nil and tries < 40 then return UIManager:scheduleIn(0.25, check) end
        self.sending = nil
        if r == false then
            Log.warn("tts rejected:", detail)
            self:stop()
            UIManager:show(InfoMessage:new{ text = T(_("The Kindle voice didn't respond: %1"), detail) })
            return
        end
        self:sendNext()
    end
    UIManager:scheduleIn(0.25, check)
end

--- Show the sentence at the head of the queue (the one being spoken).
function Reader:playHead()
    local head = self.queue and self.queue[1]
    if not self.active or not head or head.shown then return end
    head.shown = true
    head.shown_at = os.time()
    self.cur = { head.xp0, head.xp1 }
    self:follow(head.xp0)
    self:highlight(head.xp0, head.xp1)
    if self.turn_timer then UIManager:unschedule(self.turn_timer); self.turn_timer = nil end
    if head.turn_xp then
        -- the sentence goes on overleaf: turn when the voice gets there
        self.turn_timer = function()
            self.turn_timer = nil
            if self.active and self.queue[1] == head then
                self:follow(head.turn_xp)
                self:highlight(head.xp0, head.xp1)
            end
        end
        UIManager:scheduleIn(math.max(0.5, TTS.duration(head.text) * head.turn_frac), self.turn_timer)
    end
    if self.events_ok == false then self:armTimer(head) end
end

--- Estimate mode: move on when the head should be done.
function Reader:armTimer(head)
    if self.timer then UIManager:unschedule(self.timer) end
    self.timer = function()
        self.timer = nil
        if self.queue[1] == head then self:advance(head.id) end
    end
    UIManager:scheduleIn(TTS.duration(head.text), self.timer)
end

--- Snippet `id` is done: drop it (and anything before it), refill, show the next.
function Reader:advance(id)
    local idx
    for i, q in ipairs(self.queue) do if q.id == id then idx = i; break end end
    if not idx then return end
    for _i = 1, idx do table.remove(self.queue, 1) end
    self:fill()
    self:playHead()
end

function Reader:poll()
    if not self.active then return end
    for _i, ev in ipairs(TTS.readEvents()) do
        self.logged_events = (self.logged_events or 0) + 1
        if self.logged_events <= 12 then Log.info("tts event", ev.name, ev.id, "queue head", self.queue[1] and self.queue[1].id) end
        if self.events_ok ~= true then
            self.events_ok = true
            if self.timer then UIManager:unschedule(self.timer); self.timer = nil end
        end
        if ev.name == "started" then
            -- ttsd moved on to this one: everything before it is done
            local idx
            for i, q in ipairs(self.queue) do if q.id == ev.id then idx = i; break end end
            if idx and idx > 1 then
                for _j = 1, idx - 1 do table.remove(self.queue, 1) end
                self:fill()
            end
            self:playHead()
        elseif ev.name == "finished" then
            -- If ttsd reports "finished" when it has *rendered* the snippet
            -- rather than said it, don't race ahead (and pile the book into
            -- its queue): move on no sooner than ~60% of the estimate.
            local head = self.queue[1]
            local early = head and head.id == ev.id and head.shown_at
                and (TTS.duration(head.text) * 0.6 - (os.time() - head.shown_at))
            if early and early > 0.5 then
                local id = ev.id
                UIManager:scheduleIn(early, function() if self.active then self:advance(id) end end)
            else
                self:advance(ev.id)
            end
        end
        if not self.active then return end
    end
    if self.events_ok == nil and os.time() - self.started_at >= Reader.EVENTS_GRACE then
        self.events_ok = false
        Log.info("tts: no ttsd events, pacing by estimate")
        local head = self.queue[1]
        if head then self:armTimer(head) end
    end
    self:schedulePoll()
end

function Reader:stop()
    if self.timer then UIManager:unschedule(self.timer); self.timer = nil end
    if self.turn_timer then UIManager:unschedule(self.turn_timer); self.turn_timer = nil end
    if self.poller then UIManager:unschedule(self.poller); self.poller_scheduled = false end
    if self.active then
        Log.info("tts stop")
        pcall(function() require("gzreader_usage").ttsStop() end)
    end
    local was_active = self.active
    self.active, self.paused = false, false
    self.queue = {}
    TTS.cancel()
    if was_active then TTS.stopEvents(); TTS.cleanup() end
    self:clearHighlight()
end

function Reader:toggle()
    if self.active then self:stop() else self:start() end
end

--- A page turned by the reader (not by us): continue from the new page.
function Reader:onManualPageTurn()
    if not self.active or self.turning then return end
    self.next_xp = self.ui.document:getXPointer()
    UIManager:scheduleIn(0.3, function()
        if self.active then self:restartQueue() end
    end)
end

return TTS
