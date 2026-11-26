-- The quick panel's Reader controls tile in a book (GZ_EMU_BOOK = an EPUB):
-- ZenOS's reader controls open, Layout has Fit pictures; on a keyboard model
-- (k3) a line under them names their keys, and a number / a letter picks a
-- tab / a section.
--   GZ_EMU_MODEL=k3 GZ_EMU_BOOK=<epub> GZ_EMU_TREE=<tree>/koreader run.sh reader_controls_tile.lua <out>
-- Checks go to <out>/reader-controls-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function reader() return require("apps/reader/readerui").instance end
local function controls()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        local m = w and w[1]
        if m and m.item_table and m.item_table.id == "reader_controls" then return m end
    end
end
local function texts(widget, out)
    out = out or {}
    if type(widget) ~= "table" then return out end
    if type(widget.text) == "string" then out[#out + 1] = widget.text end
    for _i, child in ipairs(widget) do texts(child, out) end
    for _i, k in ipairs({ "frame", "widget", "_box", "label_widget", "text_widget" }) do
        if type(widget[k]) == "table" then texts(widget[k], out) end
    end
    return out
end
add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    require("apps/reader/readerui"):showReader(os.getenv("GZ_EMU_BOOK"))
end, after = 14 })
add({ fn = function(E)
    local ui = reader()
    local tile
    for _i, t in ipairs(require("gzreader_panel").bookTiles(ui.gzreader, ui)) do if t.id == "controls" then tile = t end end
    check(tile ~= nil and tile.label == "Reader controls", "the quick panel in a book: Reader controls")
    if tile then tile.run() end
end, after = 4 })
add({ shot = "rc-1-open" })
add({ fn = function(E)
    local m = controls()
    check(m ~= nil, "…opens ZenOS's reader controls")
    local refs = m and m._zen_panel_refs
    local all = table.concat(texts(m), " | ")
    E.say("texts:", all)
    local keyboard = require("device"):hasKeyboard() and not require("device"):isTouchDevice()
    if keyboard then
        check(all:find("Back closes", 1, true) ~= nil and refs and refs.gz_tab_keys and #refs.gz_tab_keys > 0,
            "a Kindle with a keyboard: the keys on a line under the controls")
    end
    -- the Layout section: Fit pictures
    if refs and refs.select_section then refs.select_section("page") end
    if refs and refs.gz_tab_keys then
        for _i, t in ipairs(refs.gz_tab_keys) do if t.label == "Aa" or (t.label or ""):find("Font") then t.run() end end
    end
end, after = 3 })
add({ fn = function(E)
    local m = controls()
    local refs = m and m._zen_panel_refs
    if refs and refs.select_section then refs.select_section("page") end
end, after = 3 })
add({ shot = "rc-2-layout" })
add({ fn = function(E)
    local m = controls()
    local all = table.concat(texts(m), " | ")
    E.say("layout:", all)
    check(all:find("Fit pictures", 1, true) ~= nil, "reader controls → Layout: Fit pictures")
    local f = io.open(E.out .. "/reader-controls-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
end, after = 1 })
return s
