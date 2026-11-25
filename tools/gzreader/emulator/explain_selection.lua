-- Explain: the selection menu's question mark (gzreader_explain.lua). A book
-- (GZ_EMU_BOOK = an EPUB), an AI key put in by hand (example), the menu for a
-- selection, then the answer's window, the service's answer stood in for.
--   GZ_EMU_MODEL=pw3 GZ_EMU_BOOK=<epub> GZ_EMU_TREE=<tree>/koreader run.sh explain_selection.lua <out>
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function UIM() return require("ui/uimanager") end
local function reader() return require("apps/reader/readerui").instance end
add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
end, after = 3 })
add({ fn = function(E)
    local plugin = require("apps/filemanager/filemanager").instance.gzreader
    require("gzreader_ai").settings(plugin).claude.key = "sk-example"
    require("apps/reader/readerui"):showReader(os.getenv("GZ_EMU_BOOK"))
end, after = 14 })
add({ fn = function(E)
    local h = reader().highlight
    local plugin = reader().gzreader
    require("gzreader_ai").settings(plugin).claude.key = "sk-example"
    E.say("button registered:", tostring(h._highlight_buttons and h._highlight_buttons["12_gz_explain"] ~= nil),
        "available:", tostring(require("gzreader_explain").available(plugin)))
    h.selected_text = { text = "April is the cruellest month", pos0 = {}, pos1 = {} }
    local ok, err = pcall(h.onShowHighlightMenu, h)
    E.say("menu:", tostring(ok), tostring(err))
    local d = h.highlight_dialog
    local ids = {}
    for _i, row in ipairs(d and d.buttons or {}) do for _k, b in ipairs(row) do ids[#ids + 1] = tostring(b.id or b.icon or b.text) end end
    E.say("the row:", table.concat(ids, " | "))
end, after = 4 })
add({ shot = "explain-1-menu" })
add({ fn = function(E)
    local AI = require("gzreader_ai")
    AI.ask = function(_p, q, cb)
        E.say("asked:", (q.text:gsub("\n", " / ")))
        cb("The poem opens by turning a familiar idea upside down. Spring is usually welcome, but here April is cruel because it stirs life, memory and desire in people who would rather stay numb, as they were under winter's snow.")
    end
    local h = reader().highlight
    for _i, row in ipairs(h.highlight_dialog.buttons) do
        for _k, b in ipairs(row) do if b.id == "gz_highlight_explain" then b.callback() end end
    end
end, after = 4 })
add({ shot = "explain-2-answer" })
return s
