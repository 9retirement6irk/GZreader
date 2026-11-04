-- What makes GZreader GZreader, checked on the running app (any
-- GZ_EMU_MODEL), so an update of KOReader or ZenOS can't quietly undo it:
-- the setup guide, the tabs, the GZreader menu and its names, the Menu key
-- (never ZenOS's touch quick panel without touch), Settings with Connections,
-- a book (pages turn, Home closes it), the Reading menu, picture books
-- (GZ_EMU_PICTURES) filling the screen, the touch launcher's entries, the
-- Kindle Touch's Listen button, the Nook's colour screen and its "Nook"
-- wording, and menu text of a similar real size on every screen.
-- Writes <out>/keeps.txt: one "ok …" or "FAIL …" line per check.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end

local function UIM() return require("ui/uimanager") end
local function topName()
    local st = UIM()._window_stack
    local w = st[#st] and st[#st].widget
    return w and tostring(w.name or w.title or "?") or ""
end
--- All the text shown in the open windows (top `n` windows; all by default).
local function shownText(n)
    local st, out, seen = UIM()._window_stack, {}, {}
    local SKIP = { parent = true, show_parent = true, ui = true, document = true, dialog = true, plugin = true, view = true, menu = true }
    local function walk(w, d)
        if type(w) ~= "table" or seen[w] or d > 60 then return end
        seen[w] = true
        local t = rawget(w, "text")
        if type(t) == "string" and type(w.paintTo) == "function" then out[#out + 1] = t end
        local tt = rawget(w, "title")
        if type(tt) == "string" then out[#out + 1] = tt end
        for k, v in pairs(w) do if type(v) == "table" and not SKIP[k] then walk(v, d + 1) end end
    end
    for i = #st, math.max(1, #st - (n or #st) + 1), -1 do walk(st[i].widget, 0) end
    return table.concat(out, "\n")
end
local function has(text, n) return shownText(n):find(text, 1, true) ~= nil end
--- The entries of the top window's list (all its pages), or nil.
local function items()
    local st = UIM()._window_stack
    local w = st[#st] and st[#st].widget
    if not (w and type(w.item_table) == "table") then return nil end
    local out = {}
    for _i, it in ipairs(w.item_table) do
        local t = it.text or (type(it.text_func) == "function" and it.text_func())
        if t then out[#out + 1] = tostring(t) end
    end
    return "\n" .. table.concat(out, "\n") .. "\n"
end
local function hasItem(text) local t = items(); return t ~= nil and t:find(text, 1, true) ~= nil end
local function closeTop() local st = UIM()._window_stack; if st[#st] then UIM():close(st[#st].widget) end end
local function plugin()
    local fm = require("apps/filemanager/filemanager").instance
    return fm and fm.gzreader
end
local function menuSizeMM(E)
    -- the most used text size in the top window, in mm on the real screen
    local DPI = { dx = 150, dxg = 150, pw3 = 300 }
    local st = UIM()._window_stack
    local counts, seen = {}, {}
    local function walk(w, d)
        if type(w) ~= "table" or seen[w] or d > 60 then return end
        seen[w] = true
        local f, t = rawget(w, "face"), rawget(w, "text")
        if type(f) == "table" and f.size and type(t) == "string" and #t >= 6 and t:match("%a%a%a") and type(w.paintTo) == "function" then
            counts[f.size] = (counts[f.size] or 0) + 1
        end
        for k, v in pairs(w) do if type(v) == "table" and k ~= "parent" and k ~= "show_parent" then walk(v, d + 1) end end
    end
    walk(st[#st] and st[#st].widget, 0)
    local mode, n = nil, 0
    for px, c in pairs(counts) do if c > n then mode, n = px, c end end
    return mode and mode / (DPI[E.model] or 167) * 25.4
end

local TOUCH = { kt = true, pw3 = true, nst = true }
local KINDLE_WORD -- "Kindle", or "Nook" on a Nook

-- 1. the setup guide, then Home and its tabs
add({ fn = function(E)
    KINDLE_WORD = (E.model == "nook" or E.model == "nst") and "Nook" or "Kindle"
    check(has("Connect your phone"), "setup guide opens on \"Connect your phone\"")
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 6 })
add({ fn = function()
    local t = shownText()
    local tabs = {}
    for _i, name in ipairs({ "Home", "Downloads", "Grimmory", "Notes", "Calendar" }) do
        if not t:find(name, 1, true) then tabs[#tabs + 1] = name end
    end
    check(#tabs == 0, "Home's tabs: Home, Downloads, Grimmory, Notes, Calendar" .. (#tabs > 0 and (" (missing: " .. table.concat(tabs, ", ") .. ")") or ""))
end, after = 1 })
add({ shot = "keeps-home" })

-- 2. the GZreader menu (by the Menu key where there's one)
add({ fn = function(E)
    if TOUCH[E.model] then require("gzreader_homemenu").show(plugin()) else E.key("Menu") end
end, after = 4 })
add({ fn = function(E)
    check(topName() == "Menu" and hasItem("Send books from your phone (QR code)") and hasItem("Restart GZreader"),
        (TOUCH[E.model] and "GZreader menu" or "Menu key at Home: the GZreader menu") .. " (top: " .. topName() .. ")")
    check(hasItem("Exit to the " .. KINDLE_WORD), "names: \"Exit to the " .. KINDLE_WORD .. "\"")
    if not TOUCH[E.model] then check(not hasItem("Quick panel"), "no touch quick panel in it (no touch screen)") end
    local mm = menuSizeMM(E)
    check(mm and mm >= 2.2 and mm <= 3.8, string.format("menu text a readable size: %.1f mm", mm or 0))
end, after = 1 })
add({ shot = "keeps-menu" })
add({ fn = function() closeTop() end, after = 3 })

-- 3. Settings: ZenOS's page with GZreader's Connections
add({ fn = function() require("gzreader_homemenu").settings() end, after = 6 })
add({ fn = function() check(has("Connections", 1), "Settings page has Connections (Grimmory, Memos)") end, after = 1 })
add({ fn = function() closeTop() end, after = 3 })

-- 4. the touch launcher's entries, the Kindle Touch's Listen
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    E.swipe(W / 2, 3, W / 2, H / 2)
end, after = 4 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    E.tap({ 200 * W / 1072, 48 * H / 1448 })
end, after = 4 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    check(has("GZreader") and has("Phone") and has("Send books") and has("Continue"),
        "touch launcher at Home: GZreader, Continue, Phone, Send books…")
    check(not has("Contents") and not has("Bookmarks"), "…and not the book's (Contents, Bookmarks)")
    E.shot("keeps-launcher-home")
    closeTop()
end, after = 4 })

-- 5. the Nook's colour screen
add({ fn = function(E)
    if E.model ~= "nook" then return end
    local NS = require("gzreader_nook")
    local labels = {}
    for _i, b in ipairs(NS.buttons or {}) do labels[b.label] = true end
    check(require("device").lcd ~= nil and labels.OK and labels.Menu and labels.Back, "Nook: colour screen with OK, Menu, Back")
end, after = 1 })

-- 6. a book: pages turn, the Reading menu, Home closes it
add({ fn = function()
    local dir = (require("device").home_dir or "/mnt/us") .. "/GZreader"
    os.execute("mkdir -p '" .. dir .. "' && cp '" .. os.getenv("GZ_EMU_BOOK") .. "' '" .. dir .. "/keeps.epub'")
    require("apps/reader/readerui"):showReader(dir .. "/keeps.epub")
end, after = 25 })
add({ fn = function(E)
    local ui = require("apps/reader/readerui").instance
    E.page1 = ui and ui.document and ui.document:getCurrentPage()
    check(E.page1 ~= nil, "a book opens")
end, after = 1 })
add({ fn = function(E)
    -- the page button; a tap on the right where there's none (Kindle Touch, Paperwhite)
    if not pcall(E.key, "RPgFwd") then
        local Screen = require("device").screen
        E.tap({ Screen:getWidth() * 0.9, Screen:getHeight() / 2 })
    end
end, after = 5 })
add({ fn = function(E)
    local ui = require("apps/reader/readerui").instance
    local p = ui and ui.document and ui.document:getCurrentPage()
    check(p and E.page1 and p > E.page1, "the page turns")
    if TOUCH[E.model] then return end
    E.key("Menu")
end, after = 4 })
add({ fn = function(E)
    if TOUCH[E.model] then return end
    check(topName() == "Reading menu" and hasItem("Fit pictures to the screen (picture books)") and hasItem("Close book (Home)"),
        "Menu key in a book: the Reading menu (top: " .. topName() .. ")")
    check(not hasItem("Quick panel"), "no touch quick panel in it")
    closeTop()
end, after = 3 })
-- (touch: the launcher in a book has the book's entries; GZreader opens the Reading menu)
local function launcher(E)
    local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    E.swipe(W / 2, 3, W / 2, H / 2)
    require("ui/uimanager"):scheduleIn(4, function() E.tap({ 200 * W / 1072, 48 * H / 1448 }) end)
end
add({ fn = function(E) if TOUCH[E.model] then launcher(E) end end, after = 9 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    check(has("Contents") and has("Bookmarks") and has("GZreader"), "touch launcher in a book: GZreader, Contents, Bookmarks…")
    check(not has("Send books") and not has("Continue"), "…and not Home's (Continue, Send books)")
    E.shot("keeps-launcher-book")
    E.tap("GZreader")
end, after = 5 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    check(topName() == "Reading menu", "touch launcher's GZreader in a book: the Reading menu (top: " .. topName() .. ")")
    if topName() ~= "ReaderUI" then closeTop() end
end, after = 3 })
-- (the Kindle Touch: Listen, read aloud, in a book's quick panel)
add({ fn = function(E)
    if E.model ~= "kt" then return end
    local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    E.swipe(W / 2, 3, W / 2, H / 2)
end, after = 4 })
add({ fn = function(E)
    if E.model ~= "kt" then return end
    check(has("Listen"), "Kindle Touch: Listen (read aloud) in the quick panel")
    E.shot("keeps-kt-quick-panel")
    if topName() ~= "ReaderUI" then closeTop() end
end, after = 3 })
add({ shot = "keeps-book" })
add({ fn = function(E)
    -- the Home button, or the Home event where there's none (Paperwhite)
    if not pcall(E.key, "Home") then UIM():sendEvent(require("ui/event"):new("Home")) end
end, after = 10 })
add({ fn = function() check(require("apps/reader/readerui").instance == nil, "Home closes the book") end, after = 1 })

-- 7. a picture book fills the screen
add({ fn = function()
    local dir = (require("device").home_dir or "/mnt/us") .. "/GZreader"
    os.execute("cp '" .. os.getenv("GZ_EMU_PICTURES") .. "' '" .. dir .. "/pictures.epub'")
    require("apps/reader/readerui"):showReader(dir .. "/pictures.epub")
end, after = 30 })
add({ wait_for = function()
    local ui = require("apps/reader/readerui").instance
    return ui and require("gzreader_picturebook").isOn(ui)
end, timeout = 60, after = 4 })
add({ fn = function()
    local ui = require("apps/reader/readerui").instance
    check(ui and require("gzreader_picturebook").isOn(ui), "picture book: recognised, pictures fill the screen")
end, after = 1 })
add({ shot = "keeps-picture-book" })
add({ fn = function(E)
    -- the Home button, or the Home event where there's none (Paperwhite)
    if not pcall(E.key, "Home") then UIM():sendEvent(require("ui/event"):new("Home")) end
end, after = 10 })

add({ fn = function(E)
    local f = io.open(E.out .. "/keeps.txt", "w")
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
end, after = 1 })
return s
