-- The Notes tab's actions in the quick panel: New note, Filter, Layout, Sort,
-- Options; Sort notes by; Layout → Full screen (no tab bar) and back. With
-- demo/mock_memos.py --sample on 127.0.0.1:18090 (no Grimmory needed). Any
-- model; on a Kindle 4 (k4) the Menu key opens the panel.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function N() return require("gzreader_notes") end
local function UI() return require("ui/uimanager") end
local function top() local st = UI()._window_stack; return st[#st].widget end
local function tiles(E, what)
    local P = require("gzreader_panel")
    local out = {}
    for _i, t in ipairs(P.open and P.open.section or {}) do out[#out + 1] = t.label end
    E.say(what, "panel:", P.open and P.open.section_title or "(closed)", table.concat(out, ", "))
end
local function tile(id)
    for _i, t in ipairs(require("gzreader_panel").open.section) do if t.id == id then return t end end
end

add({ fn = function()
    for i = #UI()._window_stack, 1, -1 do
        local w = UI()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UI():close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    E.say("connect ->", tostring(N().connect(plugin(), "127.0.0.1:18090", "memos-test-token")))
    if N().connect_menu then UI():close(N().connect_menu, "full"); N().connect_menu = nil end
    N().show(plugin())
end, after = 16 })
shot("panel-1-board")
add({ fn = function(E)
    if require("device"):hasDPad() and not require("device"):hasKeyboard() then E.key("Menu") else require("gzreader_panel").show(plugin()) end
end, after = 4 })
add({ fn = function(E) tiles(E, "notes tab") end })
shot("panel-2-quick-panel")
add({ fn = function() local t = tile("sort"); UI():close(require("gzreader_panel").open); t.run() end, after = 4 })
shot("panel-3-sort")
add({ fn = function() top().buttons[3][1].callback() end, after = 10 }) -- Reverse order
add({ fn = function(E) local f = N().notes[2]; E.say("sorted:", N().orderBy(plugin()), "second:", f and f.content:sub(1, 30)) end })
shot("panel-4-oldest-first")
add({ fn = function() require("gzreader_panel").show(plugin()) end, after = 4 })
add({ fn = function() local t = tile("view"); UI():close(require("gzreader_panel").open); t.run() end, after = 4 })
shot("panel-5-layout")
add({ fn = function() local b = top().buttons; b[#b][1].callback() end, after = 12 }) -- Full screen
add({ fn = function(E) E.say("full screen:", tostring(N().fullscreen(plugin())), "board name:", tostring(N().board and N().board.name)) end })
shot("panel-6-full-screen")
add({ fn = function() require("gzreader_panel").show(plugin()) end, after = 4 })
add({ fn = function(E) tiles(E, "full screen") end })
shot("panel-7-panel-in-full-screen")
add({ fn = function() local t = tile("note"); UI():close(require("gzreader_panel").open); t.run() end, after = 6 })
add({ fn = function(E) E.say("top:", tostring(top().on_save ~= nil and "editor" or top().name)) end })
shot("panel-8-new-note")
add({ fn = function()
    for _i, w in ipairs(UI()._window_stack) do if w.widget.on_save then w.widget.saved = true; UI():close(w.widget, "full") end end
    N().setFullscreen(plugin(), false)
end, after = 12 })
add({ fn = function(E) E.say("back:", tostring(N().fullscreen(plugin())), tostring(N().board and N().board.name)) end })
shot("panel-9-tab-bar-back")
-- leave things as they were for the next run
add({ fn = function() N().setSort(plugin(), "sort_reverse", nil) end, after = 6 })
return s
