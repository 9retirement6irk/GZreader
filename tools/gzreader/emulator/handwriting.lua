-- Handwriting to text in the drawing screen (gzreader_handwriting.lua):
-- the text tool's Write by hand (each word turns into typed text a moment
-- after the pen lifts, into the same box as you go on: the Apple Newton's
-- way), Undo bringing the writing back, the lasso's To text (checked before
-- it becomes a box), and the writing read online by Claude (a stand-in).
--   python3 -I demo/mock_claude.py 18300 "Speaking of work" &
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh handwriting.lua <out>
-- (pw3 too: written with a finger.) Checks go to <out>/handwriting-checks.txt.
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local MODEL = os.getenv("GZ_EMU_MODEL") or "scribe"
local PEN = MODEL == "scribe"
local HERE = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local TESTS = HERE .. "/../tests"
local W, H
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function screen()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then return w.widget end end
end
local function find(pred) for _i, w in ipairs(UIM()._window_stack) do if pred(w.widget) then return w.widget end end end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + d.ox + math.floor(b.rect.w / 2), b.rect.y + d.oy + math.floor(b.rect.h / 2) } end
    end
end
local function tap(E, p) if not p then return E.say("tap: nothing there") end; if PEN then E.penTap(p) else E.tap(p) end end
local function stroke(E, pts) if PEN then E.pen(pts, 0.25) else E.finger(pts, 0.25) end end
local function texts() return screen().sketch:liveTexts() end

-- a word in a UJI test writer's letters (tests/hwr/hwr_writers.lua), on the screen at (x, y): one step a stroke
local writers = dofile(TESTS .. "/hwr/hwr_writers.lua")
local write = dofile(TESTS .. "/hwr_write.lua")
local HAND = writers.UJI_W12 or writers[next(writers)]
local function writeSteps(word, fx, fy, xh)
    local steps = {}
    local strokes
    steps[#steps + 1] = { fn = function(_E) strokes = write(HAND, word, xh) end, after = 0.1 }
    -- (as many steps as the word has strokes, made when the word is laid out)
    local n = #write(HAND, word, xh)
    for i = 1, n do
        steps[#steps + 1] = { fn = function(E)
            local f = strokes[i]
            local pts = {}
            for j = 1, #f - 1, 2 do pts[#pts + 1] = { math.floor(W * fx + f[j]), math.floor(H * fy + f[j + 1]) } end
            -- (a dot: two points, so it's a stroke)
            if #pts == 1 then pts[2] = { pts[1][1] + 1, pts[1][2] + 1 } end
            stroke(E, pts)
        end, after = 0.45 }
    end
    return steps
end
local function addAll(list) for _i, st in ipairs(list) do add(st) end end

add({ fn = function(_E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    plugin().store.handwriting = nil
    G_reader_settings:delSetting("gzreader_drawing_write_text")
    G_reader_settings:saveSetting("gzreader_drawing_paper", "blank")
    -- (the pause before a word is read: long enough for the emulator's slower strokes)
    require("gzreader_handwriting").PAUSE = 3
    require("gzreader_drawscreen").show{ plugin = plugin(), on_done = function() end, on_cancel = function() end }
end, after = 4 })
add({ fn = function(E) tap(E, button("text")) end, after = 2 })
add({ fn = function(E) tap(E, button("text")) end, after = 2 })
add({ shot = "1-text-panel", after = 0.3 })
add({ fn = function(E)
    local d = screen()
    check(d.flyout == "text" and button("write-text") and button("hw-how"), "the text tool again: its panel, Write by hand and how writing is read")
    tap(E, button("write-text"))
end, after = 2 })
add({ fn = function(_E)
    local d = screen()
    check(d.write_text and d.sketch.hw and d.sketch.tool == "pen" and d:hint():find("turns into text", 1, true),
        "Write by hand on: the pen writes, and says it turns into text (" .. tostring(d:hint()) .. ")")
    if d.flyout then d:setFlyout(nil) end
end, after = 1 })
addAll(writeSteps("hello", 0.25, 0.25, 40))
add({ shot = "2-written", after = 0 })
add({ fn = function(_E)
    check(#screen().sketch:live() > 0 and #texts() == 0, "written: the ink on the page, not read yet (the pen only just lifted)")
end, after = 4.5 })
add({ shot = "3-read", after = 0.3 })
add({ fn = function(_E)
    local t = texts()
    check(#screen().sketch:live() == 0 and #t == 1 and t[1].text == "hello",
        "a moment after the pen lifts: the writing turns into typed text where it was (" .. tostring(t[1] and t[1].text) .. ")")
end, after = 0.5 })
addAll(writeSteps("world", 0.55, 0.25, 40))
add({ fn = function(_E) end, after = 4.5 })
add({ shot = "4-more", after = 0.3 })
add({ fn = function(E)
    local t = texts()
    check(#t == 1 and t[1].text == "hello world", "more writing after it: into the same box (" .. tostring(t[1] and t[1].text) .. ")")
    tap(E, button("undo"))
end, after = 2 })
add({ fn = function(_E)
    local t = texts()
    check(#t == 1 and t[1].text == "hello" and #screen().sketch:live() > 0, "Undo: the last word's writing back, the box as it was")
    -- the lasso's To text: written with the pen, chosen, read
    local d = screen()
    d.write_text = false
    d:setTool("pen")
end, after = 1 })
addAll(writeSteps("milk", 0.25, 0.5, 40))
add({ fn = function(E)
    tap(E, button("lasso"))
end, after = 2 })
add({ fn = function(E)
    -- a loop round the word
    local x0, y0, x1, y1 = W * 0.2, H * 0.5 - 30, W * 0.62, H * 0.5 + 140
    local loop = { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 }, { x0, y0 + 5 } }
    if PEN then E.pen(loop, 0.8) else E.finger(loop, 0.8) end
end, after = 3 })
add({ shot = "5-chosen", after = 0.3 })
add({ fn = function(E)
    local d = screen()
    local n = d.sketch.selection and #d.sketch.selection.strokes or 0
    check(n >= 4 and button("sel-text") ~= nil, "the lasso round it: " .. n .. " strokes, and To text beside Copy, Cut, Delete")
    tap(E, button("sel-text"))
end, after = 4 })
add({ shot = "6-check", after = 0.3 })
add({ fn = function(E)
    local dlg = find(function(w) return w.getInputText ~= nil and w.title == "Text from your writing" end)
    check(dlg and dlg:getInputText() == "milk", "To text: the words read, to check and change first (" .. tostring(dlg and dlg:getInputText()) .. ")")
    local conv = E.findText("Convert")
    if conv then tap(E, { conv.x + math.floor(conv.w / 2), conv.y + math.floor(conv.h / 2) }) end
end, after = 3 })
add({ fn = function(_E)
    local found = false
    for _i, t in ipairs(texts()) do if t.text == "milk" then found = true end end
    check(found and screen().sketch.selection == nil, "Convert: a text box where the writing was")
    -- online: Claude (the stand-in), with a key
    local p = plugin()
    p.store.handwriting = { engine = "claude", claude = { key = "sk-ant-test-key" }, openai = {} }
    require("gzreader_handwriting").CLAUDE_URL = "http://127.0.0.1:18300/v1/messages"
    local d = screen()
    d.write_text = true
    d.hw_box = nil
    d:setTool("text")
end, after = 1 })
addAll(writeSteps("work", 0.25, 0.7, 40))
add({ fn = function(_E) end, after = 9 })
add({ shot = "7-claude", after = 0.3 })
add({ fn = function(E)
    local got
    for _i, t in ipairs(texts()) do if t.text == "Speaking of work" then got = t end end
    local hello
    for _i, t in ipairs(texts()) do if t.text == "hello" then hello = t end end
    check(got ~= nil and hello ~= nil and got.y > hello.y + 50, "read online by Claude: its words in a text box where they were written")
    check(#screen().sketch:live() > 0, "…the writing an Undo brought back stays ink (not read with the next words)")
    local h = io.popen("curl -s http://127.0.0.1:18300/__state")
    local st = require("json").decode(h:read("*a") or "{}") or {}
    h:close()
    local r = st.requests and st.requests[#st.requests]
    check(r and r.path == "/v1/messages" and r.key == "sk-ant-test-key" and r.version == "2023-06-01" and r.image and r.image.png
        and r.image.media_type == "image/png" and tostring(r.agent):match("^GZreader/"),
        "…sent the writing as a PNG, with the key and version, as GZreader/<version>"
            .. (r and r.image and (" (" .. r.image.bytes .. " bytes)") or ""))
    local log = io.open(require("datastorage"):getDataDir() .. "/gzreader.log")
    local text = log and log:read("*a") or ""
    if log then log:close() end
    check(text:find("handwriting: reading", 1, true) and not text:find("sk-ant-test-key", 1, true), "…logged, never with the key")
    local f = io.open(E.out .. "/handwriting-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
