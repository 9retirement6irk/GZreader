-- Saving a note: "Saving…" on the screen while it's saved; Back saves what's
-- written (⋮ → Discard changes doesn't); a draft is kept every few seconds
-- while writing and offered back if the editor was closed without saving
-- (a crash, a restart); the drawing screen's ✕ asks, and Save saves what was drawn.
--   python3 -I demo/mock_memos.py 18090 --sample &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh note_autosave.lua <out>   (k3: keys)
-- Checks go to <out>/note-autosave-checks.txt.
local MODEL = os.getenv("GZ_EMU_MODEL") or "pw3"
local TOUCH = MODEL ~= "k3" and MODEL ~= "k4" and MODEL ~= "dx"
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
local function Saving() return require("gzreader_saving") end
local function editor()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.barOptions then return w.widget end end
end
local function named(n) for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == n then return w.widget end end end
local function find(pat)
    for _i, m in ipairs(N().visible()) do if tostring(m.content):find(pat, 1, true) then return m end end
end
local function state()
    return require("json").decode((require("socket.http").request("http://127.0.0.1:18090/__state")))
end
local function inMemos(pat)
    for _i, m in ipairs(state().memos) do if m.content:find(pat, 1, true) then return m end end
end
local function type_(text) local ed = editor(); ed.input:addChars(text) end

add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    Saving().dropDraft("new")
    N().show(p)
end, after = 9 })
add({ wait_for = function() return find("Georgia section") ~= nil end, timeout = 60 })
-- 1. an existing note: typed into, then Back → saved, with Saving… on the screen
add({ fn = function(E) E.shown0 = Saving().shown or 0; N().edit(plugin(), find("Georgia section")) end, after = 5 })
add({ fn = function() type_(" autosaved-words") end, after = 7 }) -- (more than DRAFT_EVERY: a draft kept)
add({ fn = function(E)
    local ed = editor()
    local d = Saving().readDraft(ed.draft_key)
    check(d and d.text:find("autosaved-words", 1, true) ~= nil, "while writing: a draft kept on the Kindle (" .. tostring(ed.draft_key) .. ")")
    ed:onCloseDialog()
end, after = 0.3 })
add({ fn = function(E)
    check(named("gz_saving") ~= nil, "Back: \"Saving…\" on the screen at once")
end, after = 8 })
add({ fn = function(E)
    local m = inMemos("autosaved-words")
    check(editor() == nil and m ~= nil, "…no question asked: the note saved to Memos")
    check(named("gz_saving") == nil and (Saving().shown or 0) > E.shown0, "…and Saving… put away after")
    check(Saving().readDraft(Saving().keyOf(find("Georgia section"))) == nil, "…its draft gone")
end, after = 1 })
-- 2. Discard changes (⋮): not saved
add({ fn = function() N().edit(plugin(), find("Georgia section")) end, after = 5 })
add({ fn = function() type_(" thrown-away") end, after = 1 })
add({ fn = function()
    local ed = editor()
    ed:barOptions()
    local d = ed.options_dialog
    local found
    for _i, row in ipairs(d.buttons) do if row[1].text == "Discard changes" then found = row[1] end end
    check(found ~= nil, "⋮ has Discard changes when something changed")
    if found then found.callback() end
end, after = 4 })
add({ fn = function()
    check(editor() == nil and inMemos("thrown-away") == nil, "Discard changes: closed, nothing sent")
end, after = 1 })
-- 3. a new note left without saving (as after a crash): offered back next time
add({ fn = function() N().edit(plugin(), nil) end, after = 5 })
add({ fn = function() type_("draft-after-crash") end, after = 7 })
add({ fn = function()
    local ed = editor()
    check(Saving().readDraft("new") ~= nil, "a new note: its draft kept too")
    -- (closed with no save and no question: what a crash or a restart does)
    ed.closed = true
    UIM():close(ed, "full")
end, after = 4 })
add({ fn = function() N().edit(plugin(), nil) end, after = 5 })
add({ shot = "1-draft-offered", after = 0.5 })
add({ fn = function(E)
    local d = editor() and editor().draft_dialog or {}
    check(UIM()._window_stack[#UIM()._window_stack].widget == d, "…on top (the keyboard waits for the answer)")
    local put
    for _i, row in ipairs(d.buttons or {}) do if row[1].text == "Put them back" then put = row[1] end end
    check(put ~= nil, "opened again: Put them back? offered")
    if put then put.callback() end
end, after = 3 })
add({ fn = function()
    local ed = editor()
    check(ed and ed:text():find("draft-after-crash", 1, true) ~= nil, "Put them back: the words are back in the note")
    ed:onCloseDialog()
end, after = 8 })
add({ fn = function()
    check(inMemos("draft-after-crash") ~= nil and Saving().readDraft("new") == nil, "…Back saved it; the draft gone")
end, after = 1 })
if TOUCH then
    -- 4. the drawing screen: ✕ with something drawn asks; Save saves it (back to the note), with Saving…
    add({ fn = function(E)
        N().edit(plugin(), find("Georgia section"))
    end, after = 5 })
    add({ fn = function() editor():openDrawing() end, after = 4 })
    add({ fn = function(E)
        if named("gz_paperlist") then E.tap("Create") end
    end, after = 4 })
    add({ fn = function(E)
        local Screen = require("device").screen
        local W, H = Screen:getWidth(), Screen:getHeight()
        local pts = {}
        for i = 0, 10 do pts[#pts + 1] = { math.floor(W * (0.3 + 0.04 * i)), math.floor(H * 0.5) } end
        E.finger(pts, 0.4)
    end, after = 3 })
    add({ fn = function(E)
        local d = named("gz_drawscreen")
        check(d and d.changed, "a page drawn on")
        E.shown1 = Saving().shown or 0
        for _i, b in ipairs(d.buttons) do
            if b.tool.id == "cancel" and not b.tool.row then E.tap({ b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) }) end
        end
    end, after = 4 })
    add({ fn = function(E)
        -- (✕ asks since 2026-11-19: Save)
        local asked
        for _i, w in ipairs(UIM()._window_stack) do if w.widget.title == "Save this drawing?" then asked = true end end
        check(asked, "✕ on the drawing screen: Save this drawing?")
        dialogButton(E, "Save this drawing?", "Save")
    end, after = 4 })
    add({ fn = function(E)
        local ed = editor()
        check(named("gz_drawscreen") == nil and ed ~= nil and ed:hasDrawing() and #ed:drawingChanges() == 1,
            "…Save: the page kept, back to the note")
        check((Saving().shown or 0) > E.shown1, "…Saving… shown while its page was made into a picture")
        ed:discard()
    end, after = 4 })
end
add({ fn = function(E)
    local f = io.open(E.out .. "/note-autosave-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
