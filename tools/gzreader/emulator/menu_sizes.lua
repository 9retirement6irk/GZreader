-- How big menu text is on this model (GZ_EMU_MODEL), in pixels and in
-- millimetres on the real screen: the setup guide, Home, the GZreader menu,
-- the Settings page, KOReader's menu, a book and its Reading menu. Writes
-- <out>/sizes.json and a screenshot of each. (menu_sizes.py compares models.)
local DPI = { k2 = 167, k3 = 167, k4 = 167, kt = 167, nook = 167, nst = 167, dx = 150, dxg = 150, pw3 = 300 }
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local results = {}

local function plugin()
    local fm = require("apps/filemanager/filemanager").instance
    return fm and fm.gzreader
end

--- Font sizes of the text in the top window (the most used one is "its" size).
local function measure(name)
    return function(E)
        local UIManager = require("ui/uimanager")
        local top = UIManager._window_stack[#UIManager._window_stack]
        local counts, samples, seen = {}, {}, {}
        local function walk(w, depth)
            if type(w) ~= "table" or seen[w] or depth > 60 then return end
            seen[w] = true
            local face = rawget(w, "face")
            local text = rawget(w, "text")
            if type(face) == "table" and face.size and type(text) == "string" and #text >= 6 and text:match("%a%a%a") and type(w.paintTo) == "function" then
                local px = face.size
                counts[px] = (counts[px] or 0) + 1
                if #samples < 40 then samples[#samples + 1] = { px = px, text = text:sub(1, 40) } end
            end
            for k, v in pairs(w) do
                if type(v) == "table" and k ~= "parent" and k ~= "show_parent" and k ~= "ui" and k ~= "document"
                        and k ~= "dialog" and k ~= "menu" and k ~= "plugin" and k ~= "view" then
                    walk(v, depth + 1)
                end
            end
        end
        if top then walk(top.widget, 0) end
        local mode, n = nil, 0
        for px, c in pairs(counts) do if c > n or (c == n and px > mode) then mode, n = px, c end end
        local dpi = DPI[E.model] or 167
        results[name] = { window = tostring(top and (top.widget.name or top.widget.title) or "?"), mode_px = mode,
            mode_mm = mode and (mode / dpi * 25.4) or nil, counts = counts, samples = samples }
        E.shot(name)
    end
end

local function closeTop()
    local UIManager = require("ui/uimanager")
    local top = UIManager._window_stack[#UIManager._window_stack]
    if top then UIManager:close(top.widget) end
end

add({ fn = measure("1-guide"), after = 1 })
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = measure("2-home"), after = 1 })
add({ fn = function() require("gzreader_homemenu").show(plugin()) end, after = 4 })
add({ fn = measure("3-gz-menu"), after = 1 })
add({ fn = closeTop, after = 3 })
add({ fn = function() require("gzreader_homemenu").settings() end, after = 6 })
add({ fn = measure("4-settings"), after = 1 })
add({ fn = closeTop, after = 3 })
add({ fn = function() require("gzreader_homemenu").fullMenu() end, after = 5 })
add({ fn = measure("5-main-menu"), after = 1 })
add({ fn = closeTop, after = 3 })
add({ fn = function()
    local Device = require("device")
    local dir = (Device.home_dir or "/mnt/us") .. "/GZreader"
    os.execute("mkdir -p '" .. dir .. "' && cp '" .. os.getenv("GZ_EMU_BOOK") .. "' '" .. dir .. "/sizes.epub'")
    require("apps/reader/readerui"):showReader(dir .. "/sizes.epub")
end, after = 25 })
add({ fn = measure("6-book"), after = 1 })
add({ fn = function()
    local ui = require("apps/reader/readerui").instance
    require("gzreader_readmenu").show(ui and ui.gzreader)
end, after = 4 })
add({ fn = measure("7-reading-menu"), after = 1 })
add({ fn = function(E)
    local json = require("json")
    local f = io.open(E.out .. "/sizes.json", "w")
    f:write(json.encode({ model = E.model, dpi = DPI[E.model] or 167, screens = results }))
    f:close()
end, after = 1 })
return s
