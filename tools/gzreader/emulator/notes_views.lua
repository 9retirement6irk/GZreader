-- The Notes tab's views: List, Two and Three side by side, Auto; Compact
-- and Full (a long note going on in the next column and on the next page),
-- the Layout dialog. With demo/mock_memos.py
-- --sample on 127.0.0.1:18090 (no Grimmory needed). Any model: no keys
-- pressed except L on models with a keyboard.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function post(content)
    local body = content:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
    local h = io.popen("curl -s -X POST -H 'Authorization: Bearer memos-test-token' -H 'Content-Type: application/json' "
        .. "--data-binary @- http://127.0.0.1:18090/api/v1/memos > /dev/null", "w")
    h:write('{"content":"' .. body .. '","visibility":"PRIVATE"}')
    h:close()
end
local function board(E, what)
    local Notes = require("gzreader_notes")
    local b = Notes.board
    local v = Notes.view(plugin())
    local parts = 0
    for _k in pairs(b and b._gz_keyed or {}) do parts = parts + 1 end
    E.say(what, "view:", v.columns, v.display, "page", tostring(b and b.page), "of", tostring(b and b.page_num),
        "notes on it:", parts, "first:", tostring(b and b._gz_first))
end
local function view(field, value, name)
    add({ fn = function() require("gzreader_notes").setView(plugin(), field, value) end, after = 10 })
    add({ fn = function(E) board(E, name) end })
    shot(name)
end

add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    -- a long note (taller than a column), and two more of different lengths
    local long = { "## Packing list for the whole trail", "" }
    for i = 1, 40 do long[#long + 1] = string.format("- [ ] item %d: something to remember to pack for the trail", i) end
    long[#long + 1] = ""
    long[#long + 1] = "#travel #hiking"
    post(table.concat(long, "\n"))
    post("Call the outfitter about the shuttle. #travel")
    post("Ideas for the Notes tab: a list view, columns like Memos' masonry view, and whole notes when there's room for them. Compact keeps them all the same size, so a page holds more of them. #ideas #gzreader")
    local Notes = require("gzreader_notes")
    E.say("connect ->", tostring(Notes.connect(plugin(), "127.0.0.1:18090", "memos-test-token")))
    if Notes.connect_menu then require("ui/uimanager"):close(Notes.connect_menu, "full"); Notes.connect_menu = nil end
    Notes.show(plugin())
end, after = 16 })
add({ fn = function(E) board(E, "default") end })
shot("views-1-two-compact")
view("columns", "list", "views-2-list-compact")
view("columns", "3", "views-3-three-compact")
view("columns", "auto", "views-4-auto-compact")
view("display", "full", "views-5-auto-full")
view("columns", "list", "views-6-list-full")
add({ fn = function() require("gzreader_notes").board:onNextPage() end, after = 8 })
add({ fn = function(E) board(E, "list full, page 2") end })
shot("views-7-list-full-page2")
view("columns", "2", "views-8-two-full")
add({ fn = function() require("gzreader_notes").board:onNextPage() end, after = 8 })
add({ fn = function(E) board(E, "two full, page 2") end })
shot("views-9-two-full-page2")
view("columns", "3", "views-10-three-full")
add({ fn = function(E)
    if require("device"):hasKeyboard() then E.key("L") else require("gzreader_notes").showView(plugin()) end
end, after = 5 })
shot("views-11-view-dialog")
add({ fn = function()
    local UIManager = require("ui/uimanager")
    local top = UIManager._window_stack[#UIManager._window_stack]
    if top and top.widget ~= require("gzreader_notes").board then UIManager:close(top.widget) end
end, after = 4 })
-- back to compact, two side by side: the page with the note that was first on screen
view("display", "compact", "views-12-three-compact-again")
view("columns", "2", "views-13-two-compact-again")
return s
