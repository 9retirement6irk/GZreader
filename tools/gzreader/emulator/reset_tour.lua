-- Reset GZreader end to end (gzreader_reset.lua), any model.
--   GZ_RESET_PHASE=arm   run.sh      reset_tour.lua <out>   a "used" install, then Reset (GZreader quits: exit 85)
--   GZ_RESET_PHASE=check run_keep.sh reset_tour.lua <out2>  the next start: setup guide, no account, settings gone
-- <out>/reset.txt: "ok …" / "FAIL …" per check (phase check), what was set up (phase arm).
local PHASE = os.getenv("GZ_RESET_PHASE") or "arm"
local function UIM() return require("ui/uimanager") end
local function fm() return require("apps/filemanager/filemanager").instance end
local function note(E, line) local f = io.open(E.out .. "/reset.txt", "a"); f:write(line, "\n"); f:close(); print("[reset] " .. line) end
local function stack()
    local out = {}
    for _i, w in ipairs(UIM()._window_stack) do out[#out + 1] = tostring(w.widget.name or w.widget.title or "?") end
    return table.concat(out, " | ")
end
local function exists(p) return require("libs/libkoreader-lfs").attributes(p) ~= nil end

if PHASE == "arm" then
    return {
        start = 16,
        { fn = function(E)
            for i = #UIM()._window_stack, 1, -1 do
                local w = UIM()._window_stack[i].widget
                if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
            end
            local z = fm().zenos
            z.config._meta.quickstart_shown_for_version = z.config._meta.quickstart_shown_for_version or "seen"
            z.config._meta.quickstart_completed = true
            z:saveConfig()
            G_reader_settings:saveSetting("gz_reset_marker", "still here")
            G_reader_settings:flush()
            local g = fm().gzreader
            g.store.server = "https://books.example.com"
            g.store.username = "tester"
            g.store.refresh_token = "not-a-real-token"
            g:save()
            local lib = g:libraryDir()
            local f = io.open(lib .. "/Downloaded Book.epub", "w"); f:write("x"); f:close()
            local DS = require("datastorage")
            note(E, "data " .. DS:getDataDir() .. " settings " .. DS:getSettingsDir() .. " library " .. lib
                .. " secrets " .. tostring(require("gzreader_secrets").active()))
            note(E, "before: stack " .. stack())
        end, after = 3 },
        { shot = "before" },
        { fn = function(E) E.box = require("gzreader_reset").confirm(fm().gzreader) end, after = 2 },
        { shot = "question" },
        { fn = function(E)
            UIM():close(E.box)
            E.box.ok_callback()
            note(E, "reset tapped; armed " .. tostring(require("gzreader_reset").armed ~= nil))
        end, after = 1 },
        { shot = "resetting", after = 10 },
    }
end

return {
    start = 16,
    { shot = "after" },
    { fn = function(E)
        local function check(ok, what) note(E, (ok and "ok   " or "FAIL ") .. what) end
        local g = fm().gzreader
        local DS = require("datastorage")
        note(E, "stack " .. stack())
        check(stack():find("setup guide", 1, true) ~= nil, "the setup guide is open")
        check(g.store.server == nil and g.store.refresh_token == nil, "no Grimmory account (server " .. tostring(g.store.server) .. ")")
        check(G_reader_settings:readSetting("gz_reset_marker") == nil, "KOReader's settings back to defaults")
        check(fm().zenos.config._meta.quickstart_completed ~= true, "ZenOS's config back to defaults")
        check(not exists(g:libraryDir() .. "/Downloaded Book.epub"), "the download is gone")
        check(exists(DS:getDataDir() .. "/gzreader.log"), "the log stays")
    end, after = 1 },
}
