-- Fit pictures → "Bigger when the bars are hidden": a fitted picture book
-- (GZ_EMU_BOOK, e.g. a fixed-layout EPUB) with the bars shown, hidden (as a
-- tap on the status bar hides them), with the option off, and shown again.
-- Writes <out>/fit_bars.txt (the book's margins at each step) and shots.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function note(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end lines[#lines + 1] = table.concat(t, " ") end
local function UIM() return require("ui/uimanager") end
local function R() return require("apps/reader/readerui").instance end
local function footer() return R().view.footer end
local function bars(hide)
    return { fn = function()
        -- (what a tap on the status bar does: ZenOS's "Hide on tap", both bars)
        local f = footer()
        if (f.mode == f.mode_list.off) == hide then return end
        f:TapFooter()
    end, after = 12 }
end
local function state(tag)
    return { fn = function()
        local d = R().document
        local m = d._document and d._document.getPageMargins and d._document:getPageMargins()
        note(tag, "pages", d:getPageCount(), "fitted", tostring(require("gzreader_picturebook").isOn(R())),
            "reserve", tostring(d._zen_top_status_bar_reserved_height), "freed", tostring(d._gz_top_freed),
            "margins", m and (m.top .. "/" .. m.bottom) or "?",
            "fitted by", tostring(R().doc_settings:readSetting("gzreader_pb_by")),
            "room", (function() local l = require("gzreader_picturebook").layout(R()); return l.avail_w .. "x" .. l.avail_h end)())
    end, after = 1 }
end

add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 6 })
add({ fn = function()
    os.execute("mkdir -p /mnt/us/GZreader && cp " .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. " /mnt/us/GZreader/bars.epub")
    require("apps/reader/readerui"):showReader("/mnt/us/GZreader/bars.epub")
end, after = 45 })
add({ fn = function() R():handleEvent(require("ui/event"):new("GotoPage", 2)) end, after = 3 })
add(state("bars shown:"))
add({ shot = "bars-1-shown" })
add(bars(true))
add(state("bars hidden:"))
add({ shot = "bars-2-hidden" })
add({ fn = function()
    local PB = require("gzreader_picturebook")
    local d = PB.showOptions(R())
    note("options:", #d.buttons, "rows, first:", d.buttons[1][1].text)
    d.buttons[1][1].callback() -- Bigger when the bars are hidden: off
    note("option now", tostring(PB.fillOn()))
end, after = 12 })
add({ fn = function() for i = #UIM()._window_stack, 1, -1 do local w = UIM()._window_stack[i].widget; if w.title == "Fit pictures to the screen" then UIM():close(w) end end end, after = 3 })
add(state("hidden, option off:"))
add({ shot = "bars-3-hidden-off" })
add({ fn = function() G_reader_settings:saveSetting("gzreader_pb_fill_hidden", true) end, after = 1 })
add(bars(false))
add(state("bars shown again:"))
add({ shot = "bars-4-shown-again" })
add({ fn = function(E)
    local f = io.open(E.out .. "/fit_bars.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
end, after = 1 })
return s
