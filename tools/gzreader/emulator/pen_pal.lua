-- A pen pal on a drawing's page (gzreader_drawask.lua): with the AI set up
-- (an example key: nothing is asked; the answer is put in by the tour), ✦ in
-- the top bar; writing on the page, ✦, a box under it "thinking", then the
-- answer in a handwriting font; a second question with no answer (no Wi-Fi):
-- the box says to try again; Done saves the boxes into memos' drawing.
--   python3 -I demo/mock_memos.py 18090 &
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh pen_pal.lua <out>
-- Checks go to <out>/pen-pal-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function fm() return require("apps/filemanager/filemanager").instance end
local function plugin() return fm() and fm().gzreader end
local MODEL = os.getenv("GZ_EMU_MODEL") or "scribe"
local PEN = MODEL == "scribe"
local W, H
local function find(name) for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == name then return w.widget end end end
local function screen() return find("gz_drawscreen") end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
    end
end
local function tapAt(E, p) if PEN then E.penTap(p) else E.tap(p) end end
-- a line of "writing": small loops along it
local function write(E, x0, y, x1)
    local pts = {}
    local n = 40
    for i = 0, n do
        local x = x0 + (x1 - x0) * i / n
        pts[#pts + 1] = { math.floor(x + 10 * math.cos(i * 1.7)), math.floor(y + 14 * math.sin(i * 1.7)) }
    end
    if PEN then E.pen(pts, 0.8) else E.finger(pts, 0.8) end
end
local pending = {}

add({ fn = function(_E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    require("gzreader_ai").settings(p).claude.key = "sk-ant-example-not-a-key"
    -- (nothing leaves the emulator: the tour answers)
    require("gzreader_ai").ask = function(_p, q, done) pending[#pending + 1] = { q = q, done = done } end
    require("gzreader_notes").draw(p)
end, after = 3 })
add({ fn = function(E) if find("gz_paperlist") then tapAt(E, "Create") end end, after = 4 })
add({ fn = function(E)
    check(screen() ~= nil and button("ask") ~= nil, "the drawing screen: ✦ in the top bar, with the AI set up")
    write(E, W * 0.15, H * 0.2, W * 0.7)
end, after = 2 })
add({ fn = function(E) write(E, W * 0.15, H * 0.25, W * 0.5) end, after = 2 })
add({ fn = function(E) tapAt(E, button("ask")) end, after = 2 })
add({ shot = "penpal-1-thinking", after = 0.5 })
add({ fn = function(_E)
    local d = screen()
    local el = d.sketch:liveTexts()[1]
    check(#pending == 1 and pending[1].q.png ~= nil and el and el.text == "✦ …", "✦: the writing sent as a picture, a box under it thinking")
    check(#d.sketch:live() == 2, "…the writing stays as it was")
    pending[1].done("Dear friend, Paris is the capital of France. It sits on the Seine, and its bakeries open early. What are you reading these days?")
end, after = 3 })
add({ shot = "penpal-2-answer", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local el = d.sketch:liveTexts()[1]
    local _x, bottom = d.sketch:toCanvas(el.x, el.y + el.height)
    check(el.text:find("^Dear friend") ~= nil and el.customData.gzAsk.state == "answer" and el.fontFamily:find("Patrick Hand", 1, true) ~= nil,
        "the answer in the box, in the handwriting font")
    write(E, W * 0.15, bottom + H * 0.06, W * 0.6)
end, after = 2 })
add({ fn = function(E) tapAt(E, button("ask")) end, after = 2 })
add({ fn = function(_E)
    check(#pending == 2 and #screen().sketch:liveTexts() == 2, "the next question: only the new writing, a second box")
    pending[2].done(nil, "no answer (timeout)")
end, after = 3 })
add({ shot = "penpal-3-waiting", after = 0.5 })
add({ fn = function(E)
    local el = screen().sketch:liveTexts()[2]
    check(el.customData.gzAsk.state == "waiting" and el.text:find("try again", 1, true) ~= nil, "no answer: the box says to try again")
    tapAt(E, button("done"))
end, after = 5 })
add({ wait_for = function()
    local q = plugin().store.memos.queue
    return q and #q == 0
end, timeout = 30 })
add({ fn = function(E)
    local h = io.popen("curl -s http://127.0.0.1:18090/__state")
    local st = require("json").decode(h:read("*a") or "{}") or {}
    h:close()
    local made
    for _i, m in ipairs(st.memos or {}) do
        for _j, a in ipairs(m.attachments or {}) do if tostring(a.filename):match("canvas%.png$") then made = a end end
    end
    local boxes = {}
    if made then
        local path = E.out .. "/pen-pal.canvas.png"
        require("gzreader_memos"):new(plugin().store.memos):download(made, path)
        local scene = require("gzreader_drawing").readFile(path)
        for _i, el in ipairs(scene and scene.elements or {}) do if el.type == "text" then boxes[#boxes + 1] = el end end
    end
    check(#boxes == 2 and boxes[1].customData and boxes[1].customData.gzAsk and boxes[1].customData.gzAsk.state == "answer"
        and boxes[2].customData.gzAsk.state == "waiting",
        "Done: both boxes in memos' drawing, the waiting one kept waiting")
    local f = io.open(E.out .. "/pen-pal-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })

return s
