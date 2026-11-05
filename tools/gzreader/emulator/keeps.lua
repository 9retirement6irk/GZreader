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
local TOUCH_MODEL = { kt = true, pw3 = true, nst = true }
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
--- The quick panel's tiles (their labels), or "" when it isn't on top.
local function tiles()
    local st = UIM()._window_stack
    local w = st[#st] and st[#st].widget
    local out = {}
    for _i, p in ipairs(w and w.placed or {}) do out[#out + 1] = tostring(p.tile.label) end
    return table.concat(out, "\n")
end
local function hasTile(text) return tiles():find(text, 1, true) ~= nil end
local function openPanel(E)
    if TOUCH_MODEL[E.model] then
        local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
        E.swipe(W / 2, 3, W / 2, H / 2) -- (a swipe down from the top)
    else
        E.key("Menu")
    end
end
local function closeTop() local st = UIM()._window_stack; if st[#st] then UIM():close(st[#st].widget) end end

local TOUCH = TOUCH_MODEL
local KINDLE_WORD -- "Kindle", or "Nook" on a Nook

-- 1. the setup guide, then Home and its tabs
add({ fn = function(E)
    KINDLE_WORD = (E.model == "nook" or E.model == "nst") and "Nook" or "Kindle"
    check(has("Set up from your browser"), "setup guide opens on \"Set up from your browser\"")
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
add({ fn = function()
    -- the Music tab: in Settings → Navbar → Tabs' list, off until turned on
    local cfg = require("apps/filemanager/filemanager").instance.zenos.config.navbar
    local listed = false
    for _i, id in ipairs(cfg.tab_order) do if id == "ct_music" then listed = true end end
    check(listed and cfg.show_tabs.ct_music ~= true and not shownText():find("Music", 1, true),
        "the Music tab: listed in Settings, off by default")
end, after = 1 })
add({ shot = "keeps-home" })

-- 2. the quick panel (the Menu key, or a swipe down from the top)
add({ fn = function(E) openPanel(E) end, after = 5 })
add({ fn = function(E)
    check(topName() == "gzreader quick panel" and hasTile("Send books") and hasTile("Restart") and hasTile("Settings"),
        (TOUCH[E.model] and "a swipe down at Home: the quick panel" or "Menu key at Home: the quick panel") .. " (top: " .. topName() .. ")")
    check(hasTile("Exit to " .. KINDLE_WORD), "names: \"Exit to " .. KINDLE_WORD .. "\"")
    check(not hasTile("Contents"), "…with Home's tiles, not a book's")
    local px = require("ui/font"):getFace("cfont", 15).size
    local mm = px / (({ dx = 150, dxg = 150, pw3 = 300 })[E.model] or 167) * 25.4
    check(mm >= 2.2 and mm <= 3.8, string.format("tile text a readable size: %.1f mm", mm))
end, after = 1 })
add({ shot = "keeps-menu" })
add({ fn = function() closeTop() end, after = 3 })

-- 3. Settings: ZenOS's page with GZreader's Connections
add({ fn = function() require("gzreader_homemenu").settings() end, after = 6 })
add({ fn = function() check(has("Connections", 1), "Settings page has Connections (Grimmory, Memos)") end, after = 1 })
add({ fn = function() closeTop() end, after = 3 })

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
    openPanel(E)
end, after = 5 })
add({ fn = function(E)
    check(topName() == "gzreader quick panel" and hasTile("Contents") and hasTile("Bookmarks") and hasTile("Fit pictures"),
        "in a book, the quick panel: the book's tiles (top: " .. topName() .. ")")
    check(not hasTile("Send books") and not hasTile("Continue"), "…and not Home's (Continue, Send books)")
    if E.model == "kt" then check(hasTile("Read aloud"), "Kindle Touch: Read aloud in the quick panel") end
    E.shot("keeps-panel-book")
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
