-- The quick panel's Controls: Home first, and one Rotate tile (Auto or Manual
-- under it; while Manual, the rotate icon on its bottom quarter turns the
-- screen). Run on the Scribe, its accelerometer stood in for:
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh rotate_tile.lua <out>
-- Checks go to <out>/rotate-tile-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function rotateTile()
    local Panel = require("gzreader_panel")
    for _i, p in ipairs(Panel.open and Panel.open.placed or {}) do
        if p.tile.gz_tile and p.tile.gz_tile.id == "rotate" then return p.tile end
    end
end

add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
    local Device = require("device")
    Device.hasGSensor = function() return true end
    require("gzreader_rotation").setAuto(false)
    require("gzreader_panel").show(plugin())
end, after = 4 })
add({ shot = "1-manual" })
add({ fn = function()
    local Panel = require("gzreader_panel")
    local first = Panel.open and Panel.open.placed[1]
    check(first and first.tile.label == "Home", "Controls start with Home")
    local t = rotateTile()
    check(t and t.label == "Rotate" and t.sub == "Manual" and t.side ~= nil, "Rotate: Manual, the turn along its bottom")
    -- a tap on the main part: Auto, the panel stays
    t:onTapTile(nil, { pos = { x = t.dimen.x + 10, y = t.dimen.y + 10 } })
end, after = 2 })
add({ shot = "2-auto" })
add({ fn = function()
    local t = rotateTile()
    check(t and t.sub == "Auto" and t.side == nil and t.on and not G_reader_settings:isTrue("input_ignore_gsensor"),
        "a tap on it: Auto, drawn inverted, the panel still open")
    t:onTapTile(nil, { pos = { x = t.dimen.x + 10, y = t.dimen.y + 10 } })
end, after = 2 })
add({ fn = function(E)
    local t = rotateTile()
    E.mode = require("device").screen:getRotationMode()
    check(t and t.sub == "Manual" and t.side ~= nil, "a tap again: Manual")
    -- a tap on its bottom quarter: the panel closes, the screen turns
    t:onTapTile(nil, { pos = { x = t.dimen.x + 10, y = t.dimen.y + t.h - 5 } })
end, after = 4 })
add({ shot = "3-turned" })
add({ fn = function(E)
    local Panel = require("gzreader_panel")
    check(Panel.open == nil and require("device").screen:getRotationMode() ~= E.mode, "a tap on its bottom part: the panel closed, the screen turned")
    local f = io.open(E.out .. "/rotate-tile-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
end, after = 1 })
return s
