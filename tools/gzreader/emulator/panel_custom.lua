-- The quick panel made your own (gzreader_panelcustom.lua; a touch model, e.g.
-- GZ_EMU_MODEL=pw3): what Settings → Quick panel → Your tiles offers (the plugins
-- with a screen, KOReader's menus at Home), two tiles added and Home's tiles put
-- in another order, then the panel (a third group, Your tiles) and a tap on each
-- of them. Prints what was offered and what each tile opened.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local function UIM() return require("ui/uimanager") end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function name(w) return tostring(w and (w.name or w.title or (w.title_bar and w.title_bar.title) or w.id)) end
add({ fn = function()
    local st = UIM()._window_stack
    for i = #st, 1, -1 do
        local w = st[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    local Custom = require("gzreader_panelcustom")
    local pc, mc = Custom.pluginChoices(), Custom.menuChoices("filemanager")
    local a, b = {}, {}
    for _i, c in ipairs(pc) do a[#a + 1] = c.label .. " (" .. c.key .. ":" .. c.method .. ")" end
    for i, c in ipairs(mc) do if i <= 12 then b[#b + 1] = c.label end end
    E.say("plugins offered:", #pc, table.concat(a, " | "))
    E.say("KOReader menus offered at Home:", #mc, table.concat(b, " | "))
    E.say("in a book (none at Home):", #Custom.menuChoices("reader"))
    if pc[1] then E.say("add plugin:", tostring(Custom.add(pc[1]))) end
    if mc[1] then E.say("add menu:", tostring(Custom.add(mc[1]))) end
    Custom.setOrder("home", { "history", "search" })
    require("gzreader_panel").show(plugin())
end, after = 4 })
add({ fn = function(E)
    local p = require("gzreader_panel").open
    local titles, labels = {}, {}
    for _i, t in ipairs(p and p.titles or {}) do titles[#titles + 1] = t.text end
    for _i, pl in ipairs(p and p.placed or {}) do labels[#labels + 1] = tostring(pl.tile.label) end
    E.say("panel groups:", table.concat(titles, " | "))
    E.say("tiles:", table.concat(labels, " | "))
    E.own = {}
    for _i, pl in ipairs(p and p.placed or {}) do
        local t = pl.tile.gz_tile
        if t and type(t.id) == "string" and t.id:match("^own") then E.own[#E.own + 1] = pl.tile end
    end
end })
add({ shot = "panel-custom-1" })
add({ fn = function(E) if E.own[1] then E.own[1].callback() end end, after = 4 })
add({ fn = function(E) E.say("first of your tiles opened:", name(top())) end })
add({ shot = "panel-custom-2-plugin" })
add({ fn = function(E)
    local w = top()
    if w and w ~= require("apps/filemanager/filemanager").instance then pcall(function() UIM():close(w) end) end
    require("gzreader_panel").show(plugin())
end, after = 4 })
add({ fn = function()
    local p = require("gzreader_panel").open
    for _i, pl in ipairs(p and p.placed or {}) do
        local t = pl.tile.gz_tile
        if t and t.id == "own2" then pl.tile.callback(); return end
    end
end, after = 4 })
add({ fn = function(E) E.say("second of your tiles opened:", name(top())) end })
add({ shot = "panel-custom-3-menu" })
return s
