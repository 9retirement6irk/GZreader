--[[--
Audio everywhere in GZreader, not tied to one screen:

- the Kindle 3's volume rocker (VPlus / VMinus) sets the speaker volume for
  audiobooks and read aloud, wherever you are; a short note shows the level
  (the audiobook player shows it on its own screen);
- leaving GZreader (Exit to the Kindle's menu, a restart) stops the
  audiobook and read aloud: the player runs as its own process and would
  otherwise go on playing on the Kindle's home screen.

Sleep (the power switch) pauses them: main.lua's onSuspend.
]]

local UIManager = require("ui/uimanager")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local AudioCtl = { installed = false }

local function TTS() return require("gzreader_tts") end

--- One step of the rocker: +1 / -1.
function AudioCtl.step(dir)
    local tts = TTS()
    local before = tts.volume()
    tts.setVolume(before + dir)
    local now = tts.volume()
    local AB = package.loaded["gzreader_audiobook"]
    local player = AB and AB.current
    local screen = player and player.screen
    if screen and UIManager:getTopmostVisibleWidget() == screen then
        pcall(screen.refreshVolume, screen) -- the level is on the player's screen
        return
    end
    if AudioCtl.note then UIManager:close(AudioCtl.note) end
    AudioCtl.note = require("ui/widget/notification"):new{
        text = T(_("Volume %1 / %2"), now, tts.VOLUME_MAX),
    }
    UIManager:show(AudioCtl.note)
end

--- Key press (1) and auto-repeat (2) step the volume; releases (0) don't.
function AudioCtl.onRockerEvent(dir, ev)
    if ev and ev.value == 0 then return end
    -- after the input is handled, on the UI's turn (never inside the input layer)
    UIManager:nextTick(function()
        local ok, err = pcall(AudioCtl.step, dir)
        if not ok then Log.warn("volume rocker:", tostring(err)) end
    end)
end

--- Stop whatever plays: the audiobook (its place saved) and read aloud.
function AudioCtl.stopAll(why)
    local AB = package.loaded["gzreader_audiobook"]
    if AB and AB.current then
        AB.quitting = true -- no network now: the position is sent at the next start
        Log.info("audiobook stopped:", why)
        pcall(AB.current.stop, AB.current)
    end
    local Engine = package.loaded["gzreader_audioengine"]
    if Engine then pcall(Engine.stop) end
    local ok_r, ReaderUI = pcall(require, "apps/reader/readerui")
    local reader = ok_r and ReaderUI.instance
    local gz = reader and reader.gzreader
    if gz and gz.tts and gz.tts.active then pcall(gz.tts.stop, gz.tts) end
end

function AudioCtl.install()
    if AudioCtl.installed then return end
    AudioCtl.installed = true
    local Device = require("device")
    local input = Device.input
    if input and Device.hasKeys and Device:hasKeys() then
        input.event_map_adapter = input.event_map_adapter or {}
        input.event_map_adapter.VPlus = function(ev) return AudioCtl.onRockerEvent(1, ev) end
        input.event_map_adapter.VMinus = function(ev) return AudioCtl.onRockerEvent(-1, ev) end
    end
    -- leaving GZreader: stop the player first
    local orig_quit = UIManager.quit
    UIManager.quit = function(self, ...)
        pcall(AudioCtl.stopAll, "GZreader is closing")
        return orig_quit(self, ...)
    end
end

return AudioCtl
