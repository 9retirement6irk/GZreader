-- Every Settings menu, on the emulated Kindle (any model): the whole tree as
-- GZreader builds it (zen_settings.build), each submenu opened (its
-- sub_item_table or sub_item_table_func) down to 8 levels, and on every row
-- its text_func, checked_func, enabled_func, mandatory_func, help_text_func
-- run. Callbacks are not run (they change settings). Then every first- and
-- second-level submenu is opened on the screen through Settings' own page
-- (zen_settings_page.show with a path) and shot. Writes
-- <out>/settings_walk.txt: "ok"/"FAIL" lines, each error with its menu path.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local R = { lines = {}, errors = {}, rows = 0, menus = 0, paths = {} }

local function label(it)
    local t = it.text
    if t == nil and type(it.text_func) == "function" then
        local ok, v = pcall(it.text_func); t = ok and v or nil
    end
    return type(t) == "string" and t:gsub("\n.*", "") or ("<" .. tostring(it.id or "?") .. ">")
end
local FAKE_MENU = { closeMenu = function() end, updateItems = function() end, item_table = {}, onClose = function() end }
local SKIP = { ["Exit"] = true, ["Restart"] = true, ["Restart GZreader"] = true, ["Exit to Kindle"] = true }

local function walk(list, path, depth, seen)
    if type(list) ~= "table" or depth > 8 or seen[list] then return end
    seen[list] = true
    R.menus = R.menus + 1
    for _i, it in ipairs(list) do
        if type(it) == "table" then
            R.rows = R.rows + 1
            local name = label(it)
            local here = path .. " → " .. name
            for _j, f in ipairs({ "text_func", "checked_func", "enabled_func", "mandatory_func", "help_text_func", "hold_callback_enabled_func" }) do
                if type(it[f]) == "function" then
                    local ok, err = pcall(it[f], FAKE_MENU)
                    if not ok then R.errors[#R.errors + 1] = here .. " [" .. f .. "]: " .. tostring(err):sub(1, 200) end
                end
            end
            if not SKIP[name] then
                local sub = it.sub_item_table
                if not sub and type(it.sub_item_table_func) == "function" then
                    local ok, v = pcall(it.sub_item_table_func, FAKE_MENU)
                    if not ok then R.errors[#R.errors + 1] = here .. " [sub_item_table_func]: " .. tostring(v):sub(1, 200)
                    elseif type(v) == "table" then sub = v end
                end
                if sub then
                    if depth <= 1 then R.paths[#R.paths + 1] = { path = path, name = name, depth = depth } end
                    walk(sub, here, depth + 1, seen)
                end
            end
        end
    end
end

add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function()
    local fm = require("apps/filemanager/filemanager").instance
    local plugin = (fm and fm.zenos) or rawget(_G, "__ZEN_UI_PLUGIN")
    local c = os.clock()
    local ok, root = pcall(function() return require("modules/settings/zen_settings").build(plugin).sub_item_table end)
    if not ok then R.errors[#R.errors + 1] = "Settings root: " .. tostring(root); return end
    R.build_s = os.clock() - c
    local names = {}
    for _i, it in ipairs(root) do names[#names + 1] = label(it) end
    R.lines[#R.lines + 1] = "info sections: " .. table.concat(names, " | ")
    c = os.clock()
    walk(root, "Settings", 0, {})
    R.lines[#R.lines + 1] = string.format("info %d menus, %d rows walked; root built in %.2f s CPU, the tree in %.2f s CPU",
        R.menus, R.rows, R.build_s, os.clock() - c)
    R.lines[#R.lines + 1] = (#R.errors == 0 and "ok " or "FAIL ") .. "every row's functions and every submenu built (" .. #R.errors .. " errors)"
    for _i, e in ipairs(R.errors) do R.lines[#R.lines + 1] = "FAIL   " .. e end
end, after = 3 })

-- on the screen: each section and each submenu one level down
local MAX_SHOTS = tonumber(os.getenv("GZ_WALK_SHOTS") or "") or 40
add({ fn = function(E)
    local Page = require("modules/settings/zen_settings_page")
    local fm = require("apps/filemanager/filemanager").instance
    local plugin = (fm and fm.zenos) or rawget(_G, "__ZEN_UI_PLUGIN")
    local UIManager = require("ui/uimanager")
    local queue = {}
    for _i, p in ipairs(R.paths) do
        local path = {}
        for part in (p.path .. " → " .. p.name):gmatch("[^→]+") do
            part = part:gsub("^%s+", ""):gsub("%s+$", "")
            if part ~= "Settings" then path[#path + 1] = { key = "text", value = part } end
        end
        queue[#queue + 1] = { path = path, name = p.path .. " → " .. p.name }
    end
    local n, shown_ok, shown_bad = 0, 0, {}
    local function nextOne()
        n = n + 1
        local q = queue[n]
        if not q or n > MAX_SHOTS then
            R.lines[#R.lines + 1] = (#shown_bad == 0 and "ok " or "FAIL ") .. shown_ok .. " menus opened on the screen"
            for _i, b in ipairs(shown_bad) do R.lines[#R.lines + 1] = "FAIL   on screen: " .. b end
            pcall(Page.closeActive)
            local f = io.open(E.out .. "/settings_walk.txt", "w")
            f:write(table.concat(R.lines, "\n"), "\n")
            f:close()
            return
        end
        pcall(Page.closeActive)
        local ok, err = pcall(Page.show, plugin, { path = q.path })
        if not ok then shown_bad[#shown_bad + 1] = q.name .. ": " .. tostring(err):sub(1, 200) end
        UIManager:scheduleIn(2.5, function()
            local okshot = pcall(E.shot, string.format("w%02d-%s", n, q.name:gsub("[^%w]+", "-"):sub(1, 50)))
            if ok and okshot then shown_ok = shown_ok + 1 end
            UIManager:scheduleIn(0.5, nextOne)
        end)
    end
    nextOne()
end, after = 3 })
add({ wait_for = function(E) local f = io.open(E.out .. "/settings_walk.txt"); if f then f:close(); return true end end, timeout = 400 })
return s
