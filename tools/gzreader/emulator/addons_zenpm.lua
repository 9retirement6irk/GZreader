-- Add-ons and ZenPM (gzreader_addons.lua; a touch model). Settings → General →
-- Add-ons' rows; and, with ZenPM's plugin copied into the tree's plugins folder
-- (GZ_EMU_ZENPM=1: zenpm.koplugin from github.com/xZenLabs/zen-pm, by hand), that
-- it loads beside GZreader, gets its quick panel tile, and what the tile opens.
-- GZ_EMU_NO_MARK=1: the tree's ZenOS without GZreader's mark, for the guard's box.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local function UIM() return require("ui/uimanager") end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function name(w) return tostring(w and (w.name or w.title or w.text or (w.title_bar and w.title_bar.title) or w.id)) end
add({ fn = function()
    local st = UIM()._window_stack
    for i = #st, 1, -1 do
        local w = st[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 8 })
add({ fn = function(E)
    local Addons = require("gzreader_addons")
    E.say("on top after start:", name(top()):sub(1, 90))
    E.say("replaced:", table.concat(Addons.replaced(), ","), "ZenPM loaded:", tostring(Addons.zenpm() ~= nil))
    local rows = {}
    for _i, r in ipairs(plugin():addonItems()) do rows[#rows + 1] = tostring(r.text) end
    E.say("Add-ons rows:", table.concat(rows, " | "))
    local own = {}
    for _i, e in ipairs(require("gzreader_panelcustom").own()) do own[#own + 1] = e.label .. " (" .. tostring(e.key) .. ":" .. tostring(e.method) .. ")" end
    E.say("your tiles:", table.concat(own, " | "))
    local tiles = {}
    for _i, t in ipairs(require("gzreader_panelcustom").tiles()) do tiles[#tiles + 1] = t.label end
    E.say("tiles that open here:", table.concat(tiles, " | "))
end })
add({ shot = "addons-1" })
add({ fn = function(E)
    local t = require("gzreader_panelcustom").tiles()[1]
    if t then t.run() else E.say("no tile to open") end
end, after = 8 })
add({ fn = function(E) E.say("the tile opened:", name(top()):sub(1, 90)) end })
add({ shot = "addons-2-zenpm" })
return s
