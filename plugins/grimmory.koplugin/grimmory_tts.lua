--[[--
Read aloud for GZreader on the Kindle Keyboard, using the Kindle's own
text-to-speech voice (the one behind Amazon's "Experimental → Text-to-Speech").

What the diagnostic log showed on a Kindle 3 (firmware 3.4.3):
- No espeak/flite/mplayer; ALSA (WM8960) with aplay and GStreamer 0.10.
- Amazon's speech services are running and reachable over lipc:
  com.lab126.ttsd  playSnippetNow / enqueueSnippet (hash properties),
                   cancelSnippetPlayback, pause2, unpause2
  com.lab126.tts   playFile (hash), stop, pause, unpause, TtsISpeed [100],
                   TtsSVoice [Tom]
- Amazon never documented the fields of those hash properties. So the
  first time, "Find the Kindle voice" plays a short numbered test through
  each plausible way of calling them; you pick the number you heard and it is
  remembered (Read aloud → Find the Kindle voice).

Reading: one sentence at a time (crengine sentence boundaries). The sentence
being spoken is highlighted, pages turn by themselves, Shift + Sym plays and
stops (like the stock Kindle). The Kindle's speech service does not report
when a sentence ends, so the next one starts after a time worked out from
the sentence length and the speed setting.

Reflowable books only (EPUB, FB2, MOBI, AZW3, TXT, HTML); not PDF or comics.
]]

local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local Log = require("grimmory_log")
local _ = require("gettext")
local T = require("ffi/util").template

local TEXT_FILE = "/tmp/gzreader-tts.txt"

local TTS = {
    -- Candidate ways to make the Kindle speak `text`. The test speaks
    -- "Voice test <n>" with each; the working one is saved by index.
    METHODS = {
        { label = "ttsd playSnippetNow {text}", pub = "com.lab126.ttsd", prop = "playSnippetNow", key = "text" },
        { label = "ttsd playSnippetNow {snippet}", pub = "com.lab126.ttsd", prop = "playSnippetNow", key = "snippet" },
        { label = "ttsd playSnippetNow {Text}", pub = "com.lab126.ttsd", prop = "playSnippetNow", key = "Text" },
        { label = "ttsd playSnippetNow {content}", pub = "com.lab126.ttsd", prop = "playSnippetNow", key = "content" },
        { label = "ttsd playSnippetNow {string}", pub = "com.lab126.ttsd", prop = "playSnippetNow", key = "string" },
        { label = "ttsd enqueueSnippet {text}", pub = "com.lab126.ttsd", prop = "enqueueSnippet", key = "text" },
        { label = "tts playFile {file}", pub = "com.lab126.tts", prop = "playFile", key = "file", file = true },
        { label = "tts playFile {path}", pub = "com.lab126.tts", prop = "playFile", key = "path", file = true },
        { label = "tts playFile {filename}", pub = "com.lab126.tts", prop = "playFile", key = "filename", file = true },
        { label = "tts playFile {fileName}", pub = "com.lab126.tts", prop = "playFile", key = "fileName", file = true },
        { label = "tts playFile {uri}", pub = "com.lab126.tts", prop = "playFile", key = "uri", file = true, uri = true },
    },
    BASE_WPM = 165,   -- words per minute at speed 100 (generous, so sentences aren't cut off)
    lipc = nil,       -- injectable for tests: { open_no_name = function() ... end }
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

function TTS.available()
    local h = openLipc()
    if h then pcall(h.close, h); return true end
    return false
end

--- Speak `text` with method `m`. Returns true or nil, err. Does not wait.
function TTS.say(text, m)
    m = m or TTS.METHODS[settings():readSetting("gzreader_tts_method") or 1]
    if not m then return nil, "no method" end
    local value = text
    if m.file then
        local f = io.open(TEXT_FILE, "wb")
        if not f then return nil, "cannot write " .. TEXT_FILE end
        f:write(text); f:close()
        value = m.uri and ("file://" .. TEXT_FILE) or TEXT_FILE
    end
    local h, err = openLipc()
    if not h then return nil, err end
    local ok, res = pcall(function()
        local ha = h:new_hasharray()
        ha:add_hash()
        ha:put_string(0, m.key, value)
        local out = h:access_hash_property(m.pub, m.prop, ha)
        if out then out:destroy() end
        ha:destroy()
    end)
    pcall(h.close, h)
    if not ok then return nil, tostring(res) end
    return true
end

local function intProp(pub, prop, value)
    local h = openLipc()
    if not h then return end
    pcall(h.set_int_property, h, pub, prop, value)
    pcall(h.close, h)
end

function TTS.cancel()
    intProp("com.lab126.ttsd", "cancelSnippetPlayback", 1)
    intProp("com.lab126.tts", "stop", 1)
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

---------------------------------------------------------------- voice test

--- Speak a numbered phrase with every method, then ask which was heard.
function TTS.findVoice(on_done)
    local h, err = openLipc()
    if not h then
        UIManager:show(InfoMessage:new{ text = T(_("The Kindle's speech service can't be reached:\n%1"), err) })
        return
    end
    pcall(h.close, h)
    UIManager:show(InfoMessage:new{
        text = T(_("Listen: the Kindle will now say \"Voice test\" and a number, up to %1 times, a few seconds apart. Then choose the number you heard."), #TTS.METHODS),
        timeout = 6,
    })
    local i = 0
    local function step()
        i = i + 1
        if i > #TTS.METHODS then
            TTS.cancel()
            return TTS.askHeard(on_done)
        end
        local m = TTS.METHODS[i]
        local ok, serr = TTS.say(T("Voice test %1.", i), m)
        Log.info("tts test", i, m.label, ok and "sent" or ("error: " .. tostring(serr)))
        UIManager:scheduleIn(ok and 3.5 or 0.2, step)
    end
    UIManager:scheduleIn(6.5, step)
end

function TTS.askHeard(on_done)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local rows, row = {}, {}
    for n = 1, #TTS.METHODS do
        row[#row + 1] = { text = tostring(n), callback = function()
            UIManager:close(dialog)
            settings():saveSetting("gzreader_tts_method", n)
            Log.info("tts method chosen", n, TTS.METHODS[n].label)
            UIManager:show(InfoMessage:new{ text = T(_("Kindle voice set (method %1). Press Shift + Sym while reading to start or stop."), n) })
            if on_done then on_done(n) end
        end }
        if #row == 4 then rows[#rows + 1] = row; row = {} end
    end
    if #row > 0 then rows[#rows + 1] = row end
    rows[#rows + 1] = {
        { text = _("I heard nothing"), callback = function()
            UIManager:close(dialog)
            Log.warn("tts: no method worked")
            UIManager:show(InfoMessage:new{ text = _("None of the ways worked on this Kindle. Save the diagnostic log (Grimmory menu) and send it so this can be fixed; it records what the speech service answered.") })
        end },
        { text = _("Test again"), callback = function() UIManager:close(dialog); TTS.findVoice(on_done) end },
    }
    dialog = ButtonDialog:new{ title = _("Which number did you hear?"), buttons = rows }
    UIManager:show(dialog)
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
    if not settings():readSetting("gzreader_tts_method") then
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
    self.next_xp = self.ui.document:getNextVisibleWordStart(xp1)
    self.timer = function() self.timer = nil; self:speakNext() end
    UIManager:scheduleIn(TTS.duration(text), self.timer)
end

function Reader:stop()
    if self.timer then UIManager:unschedule(self.timer); self.timer = nil end
    if self.active then Log.info("tts stop") end
    self.active, self.paused = false, false
    TTS.cancel()
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
