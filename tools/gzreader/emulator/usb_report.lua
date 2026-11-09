-- Send to the developer on a Kindle without Wi-Fi (dx, k2): Diagnostics offers
-- it "at the next sync"; the box asks what happened; the report is saved in
-- .gzsync/reports/ for the sync page; the Sync window exports latest.txt
-- (gzreader_usbreport.lua). Writes <out>/usb_report.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function plugin() return require("gzreader_usbsync").plugin end
local function texts(w)
    local out, seen = {}, {}
    local function walk(x, d)
        if type(x) ~= "table" or seen[x] or d > 40 then return end
        seen[x] = true
        if type(rawget(x, "text")) == "string" then out[#out + 1] = x.text end
        for k, v in pairs(x) do if type(v) == "table" and k ~= "parent" and k ~= "show_parent" then walk(v, d + 1) end end
    end
    walk(w, 0)
    return table.concat(out, "\n")
end

add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 8 })
add({ fn = function()
    local p = plugin()
    check(p and require("gzreader_net").usb == true, "a Kindle without Wi-Fi (" .. tostring(require("device").model) .. ")")
    p:showDiagnostics()
end, after = 3 })
add({ shot = "report-1-diagnostics" })
add({ fn = function()
    local t = texts(top())
    check(t:find("Send to the developer (at the next sync)", 1, true) ~= nil, "Diagnostics: Send to the developer (at the next sync)")
    UIM():close(top())
    plugin():sendLogToDeveloper()
end, after = 3 })
add({ shot = "report-2-box" })
add({ fn = function()
    local dlg = plugin().report_dialog
    check(dlg and tostring(dlg.description):find("next sync", 1, true) ~= nil, "the box says it's sent at the next sync")
    dlg:setInputText("the DX froze turning a page")
    for _i, row in ipairs(dlg.buttons or {}) do
        for _j, b in ipairs(row) do if b.text == "Send" then b.callback() end end
    end
end, after = 3 })  -- (the message closes by itself after 6 s)
add({ shot = "report-3-saved" })
add({ fn = function()
    local Rep = require("gzreader_usbreport")
    local saved = Rep.saved(plugin())
    local dir = Rep.dir(plugin())
    local f = saved[#saved] and io.open(dir .. "/report-" .. saved[#saved] .. ".json", "rb")
    local meta = f and f:read("*a") or ""
    if f then f:close() end
    local tf = saved[#saved] and io.open(dir .. "/report-" .. saved[#saved] .. ".txt", "rb")
    local txt = tf and tf:read("*a") or ""
    if tf then tf:close() end
    check(#saved >= 1 and meta:find("the DX froze turning a page", 1, true) and txt:find("===== staying awake =====", 1, true),
        "saved for the sync page: " .. tostring(saved[#saved]) .. " (" .. #txt .. " bytes, with what was typed)")
    check(texts(top()):find("next sync", 1, true) ~= nil, "the Kindle says it goes at the next sync")
    UIM():close(top())
    os.remove(dir .. "/latest.txt")
    require("gzreader_usbsync").show(plugin())
end, after = 4 })
add({ shot = "report-4-sync" })
add({ fn = function(E)
    local Rep = require("gzreader_usbreport")
    local f = io.open(Rep.dir(plugin()) .. "/latest.txt", "rb")
    local t = f and f:read("*a") or ""
    if f then f:close() end
    check(t:find("Grimmory plugin log, exported", 1, true) ~= nil, "Sync: a fresh log exported for the page (" .. #t .. " bytes)")
    local out = require("gzreader_usbsync").outbox(plugin())
    check(out.report and out.report.feed and out.report.device, "the outbox names the feed and the Kindle: " .. tostring(out.report and out.report.device))
    local fo = io.open(E.out .. "/usb_report.txt", "w")
    if fo then fo:write(table.concat(lines, "\n") .. "\n"); fo:close() end
    for _i, l in ipairs(lines) do print("[emu] " .. l) end
end, after = 1 })
return s
