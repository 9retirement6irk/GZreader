-- Memos spaces in the Notes tab: Filter → Space…, the board showing one
-- space, the editor's space chip and its picker, Space members, the note's
-- page. With demo/mock_memos.py --sample --spaces on 127.0.0.1:18090 (no
-- Grimmory needed). Any model.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function N() return require("gzreader_notes") end
local function top()
    local UIManager = require("ui/uimanager")
    return UIManager._window_stack[#UIManager._window_stack].widget
end
local function closeTop() require("ui/uimanager"):close(top()) end
local function editor()
    for _i, w in ipairs(require("ui/uimanager")._window_stack) do
        if w.widget.on_save and w.widget.input then return w.widget end
    end
end

add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    E.say("connect ->", tostring(N().connect(plugin(), "127.0.0.1:18090", "memos-test-token")))
    if N().connect_menu then require("ui/uimanager"):close(N().connect_menu, "full"); N().connect_menu = nil end
    N().show(plugin())
end, after = 16 })
add({ fn = function(E)
    local sp = N().spaces(plugin())
    E.say("spaces:", sp and #sp or "none", "notes:", #(N().notes or {}))
    N().showFilter(plugin())
end, after = 4 })
shot("spaces-1-filter")
add({ fn = function() closeTop(); N().showSpaceFilter(plugin()) end, after = 5 })
shot("spaces-2-space-list")
add({ fn = function()
    closeTop()
    N().setFilter(plugin(), { kind = "space", value = "spaces/family", label = "Family" })
end, after = 10 })
add({ fn = function(E) E.say("board:", N().title(), #(N().notes or {})) end })
shot("spaces-3-board-family")
add({ fn = function() N().edit(plugin()) end, after = 6 })
add({ fn = function(E) local e = editor(); E.say("editor space:", tostring(e and e.space), tostring(e and e.visibility)) end })
shot("spaces-4-editor-new-in-family")
add({ fn = function() editor():onShortcut("A") end, after = 4 })
shot("spaces-5-space-picker")
add({ fn = function() closeTop(); editor():onShortcut("V") end, after = 4 })
add({ fn = function(E) E.say("visibility now:", editor().visibility) end })
shot("spaces-6-space-members")
add({ fn = function()
    local e = editor()
    e.saved = true
    require("ui/uimanager"):close(e, "full")
    N().setFilter(plugin(), { kind = "all" })
end, after = 10 })
add({ fn = function()
    for _i, m in ipairs(N().notes or {}) do
        if m.space == "spaces/book-club" then N().showNote(plugin(), m) end
    end
end, after = 6 })
shot("spaces-7-note-page")
return s
