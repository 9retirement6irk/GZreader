-- The setup guide's first question (How will you use GZreader?) and the page
-- that follows each answer. A fresh install: the guide is on screen at start.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function guide()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" then return w end
    end
end
local function answer(E, id, what)
    local g = guide()
    if not g then return E.say(what, "no setup guide") end
    if g._page_idx > 1 then g:_prevPage() end
    g._selections[1] = { [id] = true }
    g:_nextPage()
    local page = g.pages[g._page_idx]
    local ids = {}
    for _i, c in ipairs(page.choices or {}) do ids[#ids + 1] = c.id .. ((g._selections[g._page_idx] or {})[c.id] and "*" or "") end
    E.say(what, "->", tostring(page.title), "|", table.concat(ids, ","), "| saved:", tostring(require("apps/filemanager/filemanager").instance.gzreader.store.book_source))
end
add({ fn = function(E)
    local g = guide()
    E.say("first page:", tostring(g and g.pages[g._page_idx].title), "of", tostring(g and g._total))
end, after = 2 })
add({ shot = "how-1-question" })
add({ fn = function(E) answer(E, "grimmory", "Grimmory") end, after = 3 })
add({ shot = "how-2-grimmory" })
add({ fn = function(E) answer(E, "bookorbit", "BookOrbit") end, after = 3 })
add({ shot = "how-3-bookorbit" })
add({ fn = function(E) answer(E, "local", "on its own") end, after = 3 })
add({ shot = "how-4-on-its-own" })
return s
