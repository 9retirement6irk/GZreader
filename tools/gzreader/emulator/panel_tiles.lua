-- Settings → Interface → Quick panel: which tiles the quick panel shows
-- (Controls, Home, This book), with Interface's other items (no Controls,
-- Launcher or Zen mode any more), then the panel with tiles hidden.
-- Keyboard models: letter keys; touch models (kt, pw3): taps. Writes
-- <out>/panel_tiles.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function shownText()
    local st, out, seen = UIM()._window_stack, {}, {}
    local SKIP = { parent = true, show_parent = true, ui = true, document = true, dialog = true, plugin = true, view = true, menu = true }
    local function walk(w, d)
        if type(w) ~= "table" or seen[w] or d > 60 then return end
        seen[w] = true
        local t = rawget(w, "text")
        if type(t) == "string" and type(w.paintTo) == "function" then out[#out + 1] = t end
        for k, v in pairs(w) do if type(v) == "table" and not SKIP[k] then walk(v, d + 1) end end
    end
    for i = #st, 1, -1 do walk(st[i].widget, 0) end
    return table.concat(out, "\n")
end
local function has(text) return shownText():find(text, 1, true) ~= nil end
local TOUCH = { kt = true, pw3 = true, nst = true }
--- A letter on a keyboard model, a tap on the row's text on a touch one.
local function pick(letter, text)
    return { fn = function(E)
        if TOUCH[E.model] then E.tap(text) else E.key(letter) end
    end, after = 4 }
end
local function tiles()
    local st = UIM()._window_stack
    local w = st[#st] and st[#st].widget
    local out = {}
    for _i, p in ipairs(w and w.placed or {}) do out[#out + 1] = tostring(p.tile.label) end
    return "|" .. table.concat(out, "|") .. "|"
end

-- past the setup guide, to Home
add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
    require("gzreader_panel").showAll()
end, after = 10 })
-- Settings (as the quick panel's Settings tile opens it), then Interface (R)
add({ fn = function() require("gzreader_homemenu").settings() end, after = 6 })
add(pick("R", "Interface"))
add({ fn = function()
    check(has("Quick panel") and has("Navbar") and has("Status bar") and has("Blur menu background"),
        "Interface: Quick panel, Navbar, Status bar, Blur menu background")
    check(not has("Launcher") and not has("Zen mode"), "…no Launcher, no Zen mode")
end, after = 1 })
add({ shot = "panel-1-interface" })
add(pick("Q", "Quick panel"))
add({ fn = function()
    check(has("Controls") and has("This book") and has("Show every tile"), "Quick panel: Controls, Home, This book, Show every tile")
end, after = 1 })
add({ shot = "panel-2-quick-panel" })
add(pick("Q", "Controls"))
add({ fn = function() check(has("Wi-Fi") and has("Rotate") and has("Settings"), "Controls: the tiles listed (Exit to Kindle on page 2)") end, after = 1 })
add({ shot = "panel-3-controls" })
-- hide Rotate and Sort (as ticking them off does), back to Home, open the panel
add({ fn = function()
    local Panel = require("gzreader_panel")
    Panel.setShown("controls", "rotate", false)
    Panel.setShown("home", "sort", false)
end, after = 1 })
-- (close Settings, then the Menu key or a swipe down from the top)
add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "zen_settings" then UIM():close(w) end
    end
end, after = 5 })
add({ fn = function(E)
    if TOUCH[E.model] then
        local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
        E.swipe(W / 2, 3, W / 2, H / 2)
    else
        E.key("Menu")
    end
end, after = 5 })
add({ fn = function()
    local t = tiles()
    check(t:find("|Restart|", 1, true) and not t:find("|Rotate|", 1, true) and not t:find("|Sort|", 1, true)
        and t:find("|Settings|", 1, true) and t:find("|Exit to Kindle|", 1, true), "the panel without Rotate and Sort: " .. t)
end, after = 1 })
add({ shot = "panel-4-without-rotate-sort" })
add({ fn = function(E)
    require("gzreader_panel").showAll()
    local f = io.open(E.out .. "/panel_tiles.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do print("[emu] " .. l) end
end, after = 1 })
return s
