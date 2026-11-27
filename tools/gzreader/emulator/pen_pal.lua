-- A pen pal on a drawing's page (gzreader_drawask.lua): with the AI set up
-- (an example key: nothing is asked; the tour answers as the AI would), ✦
-- in the top bar. On ruled paper: two sums side by side and a question under
-- them, ✦, a box under them "thinking"; the answers each under their own,
-- in Caveat about the size of the writing, the paper's lines showing through;
-- a follow-up under them sent with what was said before; the eraser takes
-- an answer off; Done saves the boxes into memos' drawing.
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
local function line(E, pts) if PEN then E.pen(pts, 0.5) else E.finger(pts, 0.5) end end
-- a "word": small loops along a line, `h` high
local function word(E, x0, y, x1, h)
    local pts = {}
    local n = 24
    for i = 0, n do
        local x = x0 + (x1 - x0) * i / n
        pts[#pts + 1] = { math.floor(x + h * 0.2 * math.cos(i * 1.7)), math.floor(y + h * 0.45 * math.sin(i * 1.7)) }
    end
    line(E, pts)
end
local pending = {}
local erase_at
local function texts() return screen().sketch:liveTexts() end

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
    require("gzreader_drawscreen").setLastPaper("ruled-medium")
    require("gzreader_notes").draw(p)
end, after = 3 })
add({ fn = function(E) if find("gz_paperlist") then tapAt(E, "Create") end end, after = 4 })
add({ fn = function(E)
    check(screen() ~= nil and button("ask") ~= nil, "the drawing screen: ✦ in the top bar, with the AI set up")
    word(E, W * 0.22, H * 0.20, W * 0.32, 60)   -- 500
end, after = 1 })
add({ fn = function(E) word(E, W * 0.18, H * 0.225, W * 0.36, 60) end, after = 1 })     -- × 7520
add({ fn = function(E) line(E, { { math.floor(W * 0.17), math.floor(H * 0.245) }, { math.floor(W * 0.38), math.floor(H * 0.245) } }) end, after = 1 })
add({ fn = function(E) word(E, W * 0.66, H * 0.20, W * 0.72, 60) end, after = 1 })     -- 10
add({ fn = function(E) word(E, W * 0.64, H * 0.225, W * 0.74, 60) end, after = 1 })     -- + 10
add({ fn = function(E) word(E, W * 0.18, H * 0.40, W * 0.30, 60) end, after = 1 })     -- what
add({ fn = function(E) word(E, W * 0.33, H * 0.40, W * 0.40, 60) end, after = 1 })     -- is
add({ fn = function(E) word(E, W * 0.43, H * 0.40, W * 0.55, 60) end, after = 1 })     -- this?
add({ fn = function(E) tapAt(E, button("ask")) end, after = 2 })
add({ shot = "penpal-1-thinking", after = 0.5 })
add({ fn = function(_E)
    local el = texts()[1]
    check(#pending == 1 and pending[1].q.png ~= nil and pending[1].q.text:find("numbered 1 to 3", 1, true) and el and el.text == "✦ …",
        "✦: the writing sent as one picture, three pieces numbered; a box under it thinking")
    check(#screen().sketch:live() == 8, "…the writing stays as it was")
    pending[1].done('{"replies":[{"boxes":[1],"read":"500 x 7520","reply":"3,760,000"},{"boxes":[2],"read":"10 + 10","reply":"20"},'
        .. '{"boxes":[3],"read":"what is this?","reply":"Two sums: 500 × 7520 is 3,760,000, and 10 + 10 is 20."}]}')
end, after = 3 })
add({ shot = "penpal-2-answers", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local list = texts()
    local by = {}
    for _i, el in ipairs(list) do by[el.text] = el end
    local a1, a2, a3 = by["3,760,000"], by["20"], by["Two sums: 500 × 7520 is 3,760,000, and 10 + 10 is 20."]
    local function cx(el) return (d.sketch:toCanvas(el.x, el.y)) end
    local function cy(el) return select(2, d.sketch:toCanvas(el.x, el.y)) end
    check(#list == 3 and a1 and a2 and a3, "three answers, one per question")
    check(a1 and math.abs(cx(a1) - W * 0.18) < W * 0.03 and cy(a1) > H * 0.245 and cy(a1) < H * 0.29,
        "the first sum's under it")
    check(a2 and math.abs(cx(a2) - W * 0.64) < W * 0.04 and cy(a2) > H * 0.23 and cy(a2) < H * 0.28, "the second sum's under it, beside")
    local pr = d.sketch:pageRect()
    check(pr and a3 and (d.sketch:toCanvas(a3.x + a3.width, 0)) <= pr.x + pr.w, "the answers stay on the paper")
    check(a3 and cy(a3) > H * 0.41 and a1.fontSize > 24 and a1.fontFamily:find("Caveat", 1, true),
        "the question's under it; in Caveat, about the size of the writing (" .. tostring(a1 and a1.fontSize) .. ")")
    -- (the paper's lines through the answers' text: checked on the screenshot, penpal-2-answers.png)
    -- a follow-up under them
    word(E, W * 0.18, cy(a3) + d.sketch.per_unit * a3.height + H * 0.08, W * 0.45, 60)
end, after = 2 })
add({ fn = function(E) tapAt(E, button("ask")) end, after = 2 })
add({ fn = function(_E)
    check(#pending == 2 and pending[2].q.text:find("numbered 1 to 1", 1, true) and pending[2].q.text:find("They wrote: 500 x 7520", 1, true),
        "the follow-up: only the new writing, with the questions and replies before it")
    pending[2].done('{"replies":[{"boxes":[1],"read":"and its square root?","reply":"About 1,939."}]}')
end, after = 3 })
add({ shot = "penpal-3-follow-up", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local el
    for _i, t in ipairs(texts()) do if t.text == "20" then el = t end end
    local x, y = d.sketch:toCanvas(el.x + 5, el.y + el.height / 2)
    -- the eraser over it
    tapAt(E, button("eraser"))
    local ox, oy = d.canvas.x or 0, d.canvas.y or 0
    erase_at = { math.floor(x + ox), math.floor(y + oy) }
end, after = 2 })
add({ fn = function(E)
    local p = erase_at
    line(E, { p, { p[1] + 30, p[2] }, { p[1] + 60, p[2] + 4 } })
end, after = 2 })
add({ shot = "penpal-4-erased", after = 0.5 })
add({ fn = function(E)
    local gone = true
    for _i, t in ipairs(texts()) do if t.text == "20" then gone = false end end
    check(gone and #texts() == 3, "the eraser took that answer off")
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
    local reads = 0
    for _i, b in ipairs(boxes) do if b.customData and b.customData.gzAsk and b.customData.gzAsk.read then reads = reads + 1 end end
    check(#boxes == 3 and reads == 3 and boxes[1].fontFamily:find("Caveat", 1, true), "Done: the answers in memos' drawing, with what each question read")
    local f = io.open(E.out .. "/pen-pal-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })

return s
