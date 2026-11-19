-- The note editor's and the drawing screen's top bars, alike (the owner,
-- 2026-11-19): ✕ at the top left (asks Save, Discard or Keep writing / Keep
-- drawing when something changed), and the note's own icons in both: a photo
-- from Immich (when it's set up), a tag, the note's space, who can see it.
--   python3 -I demo/mock_memos.py 18090 --sample --spaces &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh editor_bars.lua <out>   (scribe too)
-- Checks go to <out>/editor-bars-checks.txt.
local MODEL = os.getenv("GZ_EMU_MODEL") or "pw3"
local PEN = MODEL == "scribe"
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end

-- (a dialog's button by its exact text: "Save" is in its title too)
local function dialogButton(E, title, text)
    for _i, w in ipairs(require("ui/uimanager")._window_stack) do
        if w.widget.title == title then
            local seen = {}
            local function walk(t, depth)
                if type(t) ~= "table" or seen[t] or depth > 40 then return end
                seen[t] = true
                if t.text == text and t.callback and type(t.dimen) == "table" and t.dimen.w then return t end
                for k, v in pairs(t) do
                    if k ~= "show_parent" and k ~= "parent" then local r = walk(v, depth + 1); if r then return r end end
                end
            end
            local b = walk(w.widget, 0)
            if b then return E.tap({ b.dimen.x + math.floor(b.dimen.w / 2), b.dimen.y + math.floor(b.dimen.h / 2) }) end
        end
    end
    E.say("no button", text)
end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function N() return require("gzreader_notes") end
local function editor()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.barOptions then return w.widget end end
end
local function named(n) for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == n then return w.widget end end end
local function titled(t) for _i, w in ipairs(UIM()._window_stack) do if w.widget.title == t then return w.widget end end end
local function screen() return named("gz_drawscreen") end
local function tap(E, p) if PEN then E.penTap(p) else E.tap(p) end end
local function centre(w)
    local d = w.dimen or (w.getSize and w:getSize())
    return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) }
end
local function drawButton(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id and not b.tool.row then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) }, b end
    end
end
local function ids(list)
    local out = {}
    for k in pairs(list or {}) do out[#out + 1] = k end
    table.sort(out)
    return table.concat(out, ",")
end

add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    require("gzreader_saving").dropDraft("new")
    N().show(p)
end, after = 9 })
add({ fn = function() N().edit(plugin(), nil) end, after = 5 })
add({ shot = "1-editor", after = 0.5 })
add({ fn = function(E)
    local ed = editor()
    local b = ed and ed.bar_buttons or {}
    check(ed and b.back and b.tag and b.visibility and b.options and b.done and b.draw,
        "the note editor's bar: ✕, then Draw, a tag, who can see it, ⋮ and Done (" .. ids(b) .. ")")
    check(ed and (b.space ~= nil) == (ed.has_spaces == true), "…its space, when you have spaces (" .. tostring(ed and ed.has_spaces) .. ")")
    E.vis0 = ed and ed.visibility
    tap(E, centre(b.visibility))
end, after = 3 })
add({ shot = "2-who-can-see", after = 0.5 })
add({ fn = function(E)
    local d = titled("Who can see it")
    check(d ~= nil, "a tap on who can see it: the choices")
    if d then E.tap("Public") end
end, after = 3 })
add({ fn = function(E)
    local ed = editor()
    check(ed and ed.visibility == "PUBLIC", "…Public chosen (" .. tostring(ed and ed.visibility) .. ")")
    ed.input:addChars("Bars alike " .. os.time())
    tap(E, centre(ed.bar_buttons.back))
end, after = 3 })
add({ shot = "3-close-asks", after = 0.5 })
add({ fn = function(E)
    check(titled("Save this note?") ~= nil and editor() ~= nil, "✕ with something written: Save this note? (Save, Discard, Keep writing)")
    E.tap("Keep writing")
end, after = 3 })
add({ fn = function(E)
    local ed = editor()
    check(ed ~= nil and titled("Save this note?") == nil, "…Keep writing: the note still open")
    tap(E, centre(ed.bar_buttons.draw))
end, after = 4 })
add({ fn = function(E) if named("gz_paperlist") then E.tap("Create") end end, after = 4 })
add({ shot = "4-drawing", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local close, cb = drawButton("cancel")
    local vis, vb = drawButton("note-visibility")
    check(d and close and cb.tool.icon == "close", "the drawing screen: ✕ at the top left")
    check(vis and vb.tool.icon == "vis-public" and drawButton("note-tag") and drawButton("options")
        and (drawButton("note-space") ~= nil) == (editor().has_spaces == true),
        "…the note's icons, as in the editor: a tag, its space, who can see it (Public: a globe)")
    tap(E, vis)
end, after = 3 })
add({ fn = function(E)
    check(titled("Who can see it") ~= nil, "…a tap on who can see it: the same choices")
    E.tap("Private")
end, after = 3 })
add({ shot = "5-private", after = 0.5 })
add({ fn = function(E)
    local vb = select(2, drawButton("note-visibility"))
    check(editor().visibility == "PRIVATE" and vb and vb.tool.icon == "vis-private" and screen() ~= nil,
        "…Private: the note's, and the bar shows a lock; still drawing")
    local Screen = require("device").screen
    local W, H = Screen:getWidth(), Screen:getHeight()
    local pts = {}
    for i = 0, 10 do pts[#pts + 1] = { math.floor(W * (0.3 + 0.04 * i)), math.floor(H * 0.55) } end
    if PEN then E.pen(pts, 0.4) else E.finger(pts, 0.4) end
end, after = 3 })
add({ fn = function(E)
    check(screen() and screen().changed, "a page drawn on")
    tap(E, (drawButton("cancel")))
end, after = 3 })
add({ shot = "6-drawing-close-asks", after = 0.5 })
add({ fn = function(E)
    check(titled("Save this drawing?") ~= nil, "✕ with something drawn: Save this drawing? (Save, Discard changes, Keep drawing)")
    dialogButton(E, "Save this drawing?", "Save")
end, after = 5 })
add({ fn = function(E)
    local ed = editor()
    check(screen() == nil and ed and ed:hasDrawing(), "…Save: the page kept, back to the note")
    if ed then ed:discard() end
    local f = io.open(E.out .. "/editor-bars-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 2 })
return s
