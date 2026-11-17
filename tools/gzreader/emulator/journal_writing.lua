-- A journal entry on a touch Kindle: the words typed right under the prompt
-- in a formatted box on lined paper (no "Write about it" button), the
-- keyboard making room for them (Done puts it away), ✎ in the box's corner
-- for a drawing on lined paper, and Save sending words and drawing.
--   python3 -I demo/mock_memos.py 18090 --sample --journal &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh journal_writing.lua <out>
-- (GZ_EMU_MODEL=scribe too.) Checks go to <out>/journal-writing-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function fm() return require("apps/filemanager/filemanager").instance end
local function plugin() return fm() and fm().gzreader end
local MODEL = os.getenv("GZ_EMU_MODEL") or "pw3"
local PEN = MODEL == "scribe"
local W, H
local function pt(fx, fy) return { math.floor(W * fx), math.floor(H * fy) } end
local function find(name) for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == name then return w.widget end end end
local function journal() return find("gz_journal") end
local function screen() return find("gz_drawscreen") end
local function centre(d) return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) } end
local function tapAt(E, p) if PEN then E.penTap(p) else E.tap(p) end end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
    end
end

add({ fn = function(_E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will", queue = {} }
    require("gzreader_notes").journal(p)
end, after = 3 })
add({ shot = "1-journal", after = 0.5 })
add({ fn = function(E)
    local j = journal()
    check(j and j.inline and j.rich and j.rich.ruled, "a journal entry: the words' box on the page, on lined paper")
    check(j and j.buttons.write == nil and E.findText("Write about it") == nil, "…no Write about it button")
    local pd, bd = j.buttons.prompt and j.buttons.prompt.dimen, j.rich and j.rich.dimen
    check(pd and bd and bd.y > pd.y and bd.y - (pd.y + pd.h) < 80, "…right under the prompt")
    check(j and j.draw_chip and j.draw_chip.dimen.x > bd.x + bd.w / 2 and j.draw_chip.dimen.y <= bd.y + 10,
        "…✎ in its top right corner")
    E.tap({ bd.x + 40, bd.y + 60 })
end, after = 3 })
add({ shot = "2-writing", after = 0.5 })
add({ fn = function(_E)
    local j = journal()
    check(j and j.writing and j.rich:isKeyboardVisible(), "a tap in it: the keyboard, the entry folded to the prompt and the words")
    local kb = j.rich.keyboard.dimen
    check(j.rich.dimen.y + j.rich.dimen.h <= kb.y + 2, "…the words above the keyboard")
    j.rich:addChars("Walked to the lake.")
end, after = 1 })
add({ fn = function(E)
    local j = journal()
    tapAt(E, centre(j.buttons["done-writing"].dimen))
end, after = 3 })
add({ fn = function(_E)
    local j = journal()
    check(j and not j.writing and not j.rich:isKeyboardVisible() and j.state.body:find("Walked to the lake.", 1, true),
        "Done: the keyboard away, the whole entry again, the words kept")
end, after = 1 })
add({ fn = function(E) E.tap(centre(journal().draw_chip.dimen)) end, after = 4 })
add({ fn = function(E)
    local d = screen()
    check(d ~= nil and d.sketch:paper() == "ruled-medium", "✎: a drawing, on lined paper")
    local pts = {}
    for i = 0, 10 do pts[#pts + 1] = pt(0.3 + 0.04 * i, 0.5 + 0.02 * math.sin(i)) end
    if PEN then E.pen(pts, 0.4) else E.finger(pts, 0.4) end
end, after = 3 })
add({ fn = function(E) tapAt(E, button("done")) end, after = 4 })
add({ shot = "3-drawn", after = 0.5 })
add({ fn = function(E)
    local j = journal()
    check(j and screen() == nil and j:sheetCount() == 1 and #j:drawings() == 1, "Done: back to the entry, one sheet with it")
    E.tap(centre(j.buttons.save.dimen))
end, after = 4 })
add({ fn = function(E)
    -- (sent a moment after Save: in the queue still, or in Memos already)
    local q = plugin().store.memos.queue or {}
    local last = q[#q]
    local queued = last and last.op == "create" and last.content:find("Walked to the lake.", 1, true) and last.drawings and #last.drawings == 1
    local h = io.popen("curl -s http://127.0.0.1:18090/__state")
    local st = require("json").decode(h:read("*a") or "{}") or {}
    h:close()
    local sent = false
    for _i, m in ipairs(st.memos or {}) do
        if tostring(m.content):find("Walked to the lake.", 1, true) and #(m.attachments or {}) == 1 then sent = true end
    end
    check(journal() == nil and (queued or sent), "Save: the entry's words and its drawing together (" .. (sent and "in Memos" or "queued") .. ")")
    local f = io.open(E.out .. "/journal-writing-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })

return s
