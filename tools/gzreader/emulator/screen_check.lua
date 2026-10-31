-- The 8-bit shadow screen on the Kindle 3's 4-bit framebuffer (1.6.3): what
-- the panel shows (the emulator copies the framebuffer, as the Kindle 3's
-- is: 4-bit, inverted) on Home, Settings, a book page, a rotated page and in
-- night mode. GZ_EMU_FB8=1 runs it on a plain 8-bit framebuffer instead.
local s = { start = 12, { key = "Back", after = 4 } }
local function add(t) s[#s + 1] = t end
local function shot(name, after)
    add({ fn = function(E)
        local Screen = require("device").screen
        E.say(name .. ":", "night_mode", tostring(Screen.night_mode), "packed inverted", tostring(Screen._gz_night),
            "setting", tostring(G_reader_settings:isTrue("night_mode")), "rotation", Screen:getRotationMode())
    end, after = 0.2 })
    add({ shot = name, after = after or 1 })
end
local function key(k, after) add({ key = k, after = after or 3 }) end
add({ fn = function(E)
    local Screen = require("device").screen
    E.say("screen bb type", Screen.bb:getType(), "framebuffer type",
        Screen._gz_fb_bb and Screen._gz_fb_bb:getType() or "-", "C blitter", tostring(require("ffi/blitbuffer"):getUseCBB()))
end, after = 1 })
shot("sc-1-home")
key("Menu", 4); key("U", 8)
shot("sc-2-settings")
key("Back", 3); key("Back", 3)
add({ fn = function()
    os.execute("mkdir -p /mnt/us/GZreader && cp /root/work/demo/lib/9.epub /mnt/us/GZreader/check.epub")
    require("apps/reader/readerui"):showReader("/mnt/us/GZreader/check.epub")
end, after = 15 })
key("RPgFwd", 4)
shot("sc-3-page")
add({ fn = function()
    local UIManager = require("ui/uimanager")
    local Event = require("ui/event")
    UIManager:broadcastEvent(Event:new("SetRotationMode", 1))
end, after = 8 })
shot("sc-4-rotated")
add({ fn = function()
    local UIManager = require("ui/uimanager")
    local Event = require("ui/event")
    UIManager:broadcastEvent(Event:new("SetRotationMode", 0))
end, after = 8 })
add({ fn = function() require("ui/uimanager"):broadcastEvent(require("ui/event"):new("ToggleNightMode")) end, after = 6 })
shot("sc-5-night")
add({ fn = function() require("ui/uimanager"):broadcastEvent(require("ui/event"):new("ToggleNightMode")) end, after = 6 })
shot("sc-6-day-again")
key("Back", 10)
shot("sc-7-home-after-book")
return s
