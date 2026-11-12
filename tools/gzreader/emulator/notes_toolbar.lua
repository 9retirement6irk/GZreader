-- The Notes tab's buttons on a touch Kindle: New note, Filter, Layout, Sort,
-- Options and the full screen icon (an X while in full screen), tapped where
-- they are drawn. With demo/mock_memos.py --sample on 127.0.0.1:18090.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function N() return require("gzreader_notes") end
local function UI() return require("ui/uimanager") end
local function top() local st = UI()._window_stack; return st[#st].widget end
-- the centre of the board's button `i` (1–6), from where it was drawn
local function chip(i)
    local row = N().board.title_bar._gz_action_row
    local k = 0
    for _j, w in ipairs(row) do
        if w.dimen and (w.text or w.gz_label) then
            k = k + 1
            if k == i then return { w.dimen.x + math.floor(w.dimen.w / 2), w.dimen.y + math.floor(w.dimen.h / 2) } end
        end
    end
end
local function tapChip(i) return { fn = function(E) local p = chip(i); E.say("chip", i, p and (p[1] .. "," .. p[2]) or "?"); E.tap(p) end, after = 6 } end

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
shot("toolbar-1-board")
add(tapChip(4))
add({ fn = function(E) E.say("after Sort:", tostring(top().title)) end })
shot("toolbar-2-sort")
add({ fn = function() if top() ~= N().board then UI():close(top()) end end, after = 3 })
add(tapChip(5))
add({ fn = function(E) E.say("after Options:", tostring(top().title)) end })
shot("toolbar-3-options")
add({ fn = function() if top() ~= N().board then UI():close(top()) end end, after = 3 })
add(tapChip(6))
add({ fn = function(E) E.say("full screen:", tostring(N().fullscreen(plugin())), tostring(N().board and N().board.name)) end, after = 6 })
shot("toolbar-4-full-screen")
add(tapChip(6))
add({ fn = function(E) E.say("after X:", tostring(N().fullscreen(plugin())), tostring(N().board and N().board.name)) end, after = 6 })
shot("toolbar-5-back")
return s
