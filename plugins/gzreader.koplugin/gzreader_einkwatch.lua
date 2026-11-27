--[[--
When the e-ink display stops finishing its updates.

The owner's Scribe (2026-11-26, 16:40): every screen update from then on took
exactly 5 seconds and a keypress 25, with no work done by GZreader ("0.0 s
CPU"): KOReader was waiting for the display driver to say each update was
done, and the driver gave up after its own 5 seconds each time. Nothing
redrew; the light still answered the sleep button; it took a restart.

This times each update GZreader's screen sends (the screen's refresh…Imp
methods, as gzreader_penmode.lua's are). One that takes `SLOW` seconds or
more is logged with what it was (its kind and where), so the next log says
which update the display wouldn't finish. Two in a row: GZreader tries to
get the display going again: the Scribe's pen mode off (MXCFB_SET_STYLUS_MODE
0, as gzreader_penmode.lua leaves it) and one full refresh of the screen,
at most once every `RESET_EVERY` seconds.
]]

local Log = require("gzreader_log")

local W = {
    SLOW = 4,          -- (s) an update this long: the display didn't say it was done
    STREAK = 2,        -- this many in a row: reset
    RESET_EVERY = 60,  -- (s) at most one reset this often
    streak = 0,
    stalls = 0,
    resets = 0,
    last_reset = nil,
}

local IMPS = { "refreshFullImp", "refreshPartialImp", "refreshNoMergePartialImp", "refreshFlashPartialImp",
    "refreshUIImp", "refreshNoMergeUIImp", "refreshFlashUIImp", "refreshFastImp", "refreshA2Imp" }

function W.now()
    local ok, time = pcall(require, "ui/time")
    if ok and time then return time.to_s(time.now()) end
    return os.time()
end

--- The log line for a slow update. Pure.
function W.line(name, x, y, w, h, took, cpu)
    local kind = tostring(name):gsub("^refresh", ""):gsub("Imp$", "")
    local where = (tonumber(w) and tonumber(h)) and string.format("%dx%d at %d,%d", w, h, tonumber(x) or 0, tonumber(y) or 0) or "the whole screen"
    return string.format("display: an update took %.1f s (%s, %s; %.1f s CPU): the display didn't say it was done", took, kind, where, cpu or 0)
end

--- An update has taken `took` seconds: logged, and counted towards a reset.
--- Returns true when the display is to be reset now.
function W.note(name, x, y, w, h, took, cpu)
    W.stalls = W.stalls + 1
    W.streak = W.streak + 1
    Log.warn(W.line(name, x, y, w, h, took, cpu))
    if W.streak < W.STREAK then return false end
    local now = W.now()
    if W.last_reset and now - W.last_reset < W.RESET_EVERY then return false end
    W.last_reset, W.streak = now, 0
    return true
end

--- The display made to start again: pen mode off (the Scribe), then one full refresh.
function W.reset(screen)
    W.resets = W.resets + 1
    local pen = "not a pen Kindle"
    local okp, PenMode = pcall(require, "gzreader_penmode")
    if okp and PenMode.capable(require("device")) then
        local r, why = PenMode.send(screen, 0)
        pen = r == 0 and "pen mode off" or ("pen mode off refused: " .. tostring(why))
        PenMode.on = false
    end
    Log.warn("display: updates kept timing out;", pen .. "; the whole screen refreshed")
    local UIManager = require("ui/uimanager")
    UIManager:nextTick(function() UIManager:setDirty("all", "full") end)
end

--- Wraps `screen`'s update methods (once).
function W.install(screen)
    if W.installed then return false end
    screen = screen or require("device").screen
    if type(screen) ~= "table" then return false end
    W.installed = true
    for _i, name in ipairs(IMPS) do
        local orig = screen[name]
        if type(orig) == "function" then
            local kind = name
            rawset(screen, name, function(fb, x, y, w, h, ...)
                local t0, c0 = W.now(), os.clock()
                local res = { orig(fb, x, y, w, h, ...) }
                local took = W.now() - t0
                if took >= W.SLOW then
                    if W.note(kind, x, y, w, h, took, os.clock() - c0) then pcall(W.reset, fb) end
                else
                    W.streak = 0
                end
                return unpack(res)
            end)
        end
    end
    return true
end

return W
