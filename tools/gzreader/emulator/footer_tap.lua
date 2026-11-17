-- A tap on a book's bottom status bar after the setup guide's reader defaults
-- (touch models: kt, pw3, scribe): it hides the bar and stays on the page.
-- Before, ZenOS's locked bar let the tap through to the next page (owner's
-- Kindle Scribe, 2026-11-16). <out>/footer.txt: the state before and after,
-- with the tap zones; the checks in <out>/footer_checks.txt.
--   GZ_EMU_BOOK=book.epub GZ_EMU_MODEL=scribe run.sh tools/gzreader/emulator/footer_tap.lua <out>
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function UIM() return require("ui/uimanager") end
local function out(E, line) local f = io.open(E.out .. "/footer.txt", "a"); f:write(line, "\n"); f:close() end
add({ fn = function(E)
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
    local z = require("apps/filemanager/filemanager").instance.zenos
    z.config._meta.quickstart_menu_tour_pending = false
    z.config._meta.quickstart_reader_tour_pending = false
    require("common/reader_defaults").apply(G_reader_settings, z.config)
    z:saveConfig()
    local dir = (require("device").home_dir or "/mnt/us") .. "/GZreader"
    os.execute("mkdir -p '" .. dir .. "' && cp '" .. os.getenv("GZ_EMU_BOOK") .. "' '" .. dir .. "/t.epub'")
    require("apps/reader/readerui"):showReader(dir .. "/t.epub")
end, after = 14 })
local function state(E, what)
    local ui = require("apps/reader/readerui").instance
    local f = ui.view.footer
    local st = {}
    for _i, w in ipairs(UIM()._window_stack) do st[#st + 1] = tostring(w.widget.name or w.widget.title or "?") end
    out(E, string.format("%s: page %s footer mode %s visible %s footer_h %s screenH %s dimen %s | %s", what,
        tostring(ui:getCurrentPage()), tostring(f.mode), tostring(f.view.footer_visible),
        tostring(f:getHeight()), require("device").screen:getHeight(),
        f.footer_content and f.footer_content.dimen and tostring(f.footer_content.dimen.y) .. "+" .. tostring(f.footer_content.dimen.h) or "-",
        table.concat(st, ",")))
    local zones = {}
    for _i, z in ipairs(ui._ordered_touch_zones or {}) do
        if z.def.ges == "tap" then
            local sz = z.gs_range and z.gs_range.range
            zones[#zones + 1] = z.def.id .. (sz and ("[" .. sz.y .. "+" .. sz.h .. "]") or "")
        end
    end
    out(E, "  tap zones in order: " .. table.concat(zones, " "))
end
add({ fn = function(E) state(E, "before") end, after = 1 })
add({ shot = "f01" })
add({ fn = function(E)
    local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    E.tap(function() return W / 2, H - math.floor(H / 40) end)
end, after = 3 })
add({ fn = function(E) state(E, "after tap at bottom") end, after = 1 })
add({ shot = "f02" })
add({ fn = function(E)
    local ui = require("apps/reader/readerui").instance
    local f = io.open(E.out .. "/footer_checks.txt", "w")
    f:write((ui:getCurrentPage() == 1 and "ok   " or "FAIL ") .. "a tap on the bottom status bar stays on the page\n")
    f:write((ui.view.footer.mode == 0 and "ok   " or "FAIL ") .. "a tap on the bottom status bar hides it\n")
    f:close()
end })
return s
