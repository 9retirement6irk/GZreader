-- A fixed-layout EPUB (rendition:layout pre-paginated: each page one picture
-- plus an invisible, absolutely positioned text layer, as made from a PDF):
-- opened, its pages counted and shot, then Fit pictures to the screen.
-- GZ_EMU_BOOK: such an EPUB. Writes <out>/fixed_layout.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function note(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end lines[#lines + 1] = table.concat(t, " ") end
local function UIM() return require("ui/uimanager") end
local function R() return require("apps/reader/readerui").instance end

add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 6 })
add({ fn = function()
    os.execute("mkdir -p /mnt/us/GZreader && cp " .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. " /mnt/us/GZreader/fixed.epub")
    require("apps/reader/readerui"):showReader("/mnt/us/GZreader/fixed.epub")
end, after = 40 })
local function state(tag)
    return { fn = function()
        local ui = R()
        local PB = require("gzreader_picturebook")
        note(tag, "pages", ui and ui.document and ui.document:getPageCount(),
            "picture book", ui and tostring(ui.doc_settings:readSetting("gzreader_picture_book")),
            "fitted", ui and tostring(PB.isOn(ui)))
    end, after = 1 }
end
add(state("opened:"))
add({ shot = "fixed-1-page1" })
add({ fn = function() R():handleEvent(require("ui/event"):new("GotoViewRel", 1)) end, after = 3 })
add({ shot = "fixed-2-page2" })
add({ fn = function() R():handleEvent(require("ui/event"):new("GotoViewRel", 1)) end, after = 3 })
add({ shot = "fixed-3-page3" })
add({ fn = function()
    local PB = require("gzreader_picturebook")
    if not PB.isOn(R()) then PB.menuItem(R()).callback() end
end, after = 60 })
add(state("after Fit pictures:"))
add({ fn = function() R():handleEvent(require("ui/event"):new("GotoPage", 1)) end, after = 3 })
add({ shot = "fixed-4-fit-page1" })
add({ fn = function() R():handleEvent(require("ui/event"):new("GotoViewRel", 1)) end, after = 3 })
add({ shot = "fixed-5-fit-page2" })
add({ fn = function() R():handleEvent(require("ui/event"):new("GotoViewRel", 1)) end, after = 3 })
add({ shot = "fixed-6-fit-page3" })
add({ fn = function(E)
    local f = io.open(E.out .. "/fixed_layout.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
end, after = 1 })
return s
