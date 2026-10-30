-- The 5-way on Home: open a few books so Home has Recent books, then step
-- ▼ and ▲ through Home with a screenshot after every press, and log which
-- widget has the focus.
local s = { start = 12, { key = "Back", after = 4 } }
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function key(k, after) add({ key = k, after = after or 3 }) end
local books = { "/root/work/demo/lib/9.epub", "/root/work/demo/lib/10.epub", "/root/work/demo/lib/11.epub",
    "/root/work/demo/lib/12.epub" }
for i, b in ipairs(books) do
    add({ fn = function()
        os.execute("mkdir -p /mnt/us/GZreader && cp " .. b .. " /mnt/us/GZreader/book" .. i .. ".epub")
        require("apps/reader/readerui"):showReader("/mnt/us/GZreader/book" .. i .. ".epub")
    end, after = 14 })
    key("RPgFwd", 3)
    key("Back", 10)
end
-- which Home stop the 5-way is on (ZenOS Home keeps its own focus list)
local function where(E, label)
    local UIManager = require("ui/uimanager")
    local menu
    for _i, w in ipairs(UIManager._window_stack) do
        if w.widget and w.widget._zen_home_focus_targets then menu = w.widget end
    end
    if not menu then
        local fm = require("apps/filemanager/filemanager").instance
        menu = fm and fm.file_chooser
    end
    local t = menu and menu._zen_home_focus_targets or {}
    local i = menu and menu._zen_home_focus_index
    local cur = i and t[i]
    local keys = {}
    for _j, x in ipairs(t) do keys[#keys + 1] = tostring(x.key) end
    E.say(label, cur and (tostring(cur.key) .. " (row " .. tostring(cur.row_order) .. ", col " .. tostring(cur.col) .. ")")
        or (menu and menu._zen_home_focus_suspended and "tab bar" or "none"), "| stops:", table.concat(keys, " "))
end
add({ wait = 4 })
add({ fn = function(E) where(E, "home:") end, after = 1 })
shot("home-0")
for i = 1, 5 do
    key("Down", 3)
    add({ fn = function(E) where(E, "down " .. i .. ":") end, after = 1 })
    shot("home-down-" .. i)
end
for i = 1, 4 do
    key("Up", 3)
    add({ fn = function(E) where(E, "up " .. i .. ":") end, after = 1 })
    shot("home-up-" .. i)
end
-- the Grimmory and Notes tabs: ZenOS's status row in the title, no close button
key("Back", 3)
add({ combo = { "Alt", "R" }, after = 8 })
shot("grimmory-tab")
add({ combo = { "Alt", "T" }, after = 8 })
shot("notes-tab")
return s
