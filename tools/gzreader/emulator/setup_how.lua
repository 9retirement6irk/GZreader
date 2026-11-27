-- The setup guide's first question (with my phone, or on this device) and the
-- page that follows each answer; then the list of services after the guide
-- (gzreader_setupdevice.lua). A fresh install: the guide is on screen at start.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function guide()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" then return w end
    end
end
local function answer(E, id, what)
    local g = guide()
    if not g then return E.say(what, "no setup guide") end
    if g._page_idx > 1 then g:_prevPage() end
    g._selections[1] = { [id] = true }
    g:_nextPage()
    local page = g.pages[g._page_idx]
    local ids = {}
    for _i, c in ipairs(page.choices or {}) do ids[#ids + 1] = c.id .. ((g._selections[g._page_idx] or {})[c.id] and "*" or "") end
    E.say(what, "->", tostring(page.title), "|", table.concat(ids, ","), "| saved:", tostring(require("apps/filemanager/filemanager").instance.gzreader.store.book_source))
end
add({ fn = function(E)
    local g = guide()
    E.say("first page:", tostring(g and g.pages[g._page_idx].title), "of", tostring(g and g._total))
end, after = 2 })
add({ shot = "how-1-question" })
add({ fn = function(E) answer(E, "phone", "with my phone") end, after = 3 })
add({ shot = "how-2-phone" })
add({ fn = function(E) answer(E, "device", "on this device") end, after = 3 })
add({ shot = "how-3-services" })
add({ fn = function(E)
    -- tick Grimmory, then BookOrbit (Grimmory unticks), Memos and Calendar, as taps would
    local g = guide()
    local page = g.pages[g._page_idx]
    local sel = g._selections[g._page_idx] or {}
    for _i, id in ipairs({ "grimmory", "bookorbit", "memos", "calendar" }) do
        sel[id] = true
        sel = page.on_toggle(sel, id) or sel
    end
    g._selections[g._page_idx] = sel
    require("ui/uimanager"):setDirty(g, "ui")
    local on = {}
    for _i, c in ipairs(page.choices) do if sel[c.id] then on[#on + 1] = c.id end end
    E.say("ticked:", table.concat(on, ","))
end, after = 3 })
add({ shot = "how-4-ticked" })
add({ fn = function(E)
    local g = guide()
    g:_nextPage()
    local plugin = require("apps/filemanager/filemanager").instance.gzreader
    E.say("chosen:", table.concat(plugin.store.setup_services or {}, ","), "| book server:", tostring(plugin.store.book_source))
    require("ui/uimanager"):close(g)
    require("gzreader_setupdevice").show(plugin)
    local m = require("gzreader_setupdevice").menu
    local rows = {}
    for _i, it in ipairs(m and m.item_table or {}) do rows[#rows + 1] = tostring(it.text) .. (it.mandatory and (" = " .. it.mandatory) or "") end
    E.say("the list:", table.concat(rows, " | "))
end, after = 4 })
add({ shot = "how-5-list" })
return s
