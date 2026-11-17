-- Screen rotation (gzreader_rotation.lua): the Auto-rotate tile on Kindles
-- with an accelerometer, Home and books keeping the screen's rotation, and
-- GZreader's own pages (a note, the note editor, a journal entry) turning
-- with the screen.
--   luajit rotation_test.lua <gzreader.koplugin>
local PLUGIN = arg[1]
package.path = PLUGIN .. "/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
local function source(name)
    local f = assert(io.open(PLUGIN .. "/" .. name)); local s = f:read("*a"); f:close(); return s
end

-- settings, as KOReader's LuaSettings
local data = {}
G_reader_settings = {
    readSetting = function(_s, k) return data[k] end,
    saveSetting = function(_s, k, v) data[k] = v end,
    delSetting = function(_s, k) data[k] = nil end,
    makeTrue = function(_s, k) data[k] = true end,
    isTrue = function(_s, k) return data[k] == true end,
}

-- a screen: portrait 600 × 800 (rotation 0, 2), landscape 800 × 600 (1, 3)
local Screen = { mode = 0, sets = 0 }
function Screen:getRotationMode() return self.mode end
function Screen:setRotationMode(m) self.mode = m; self.sets = self.sets + 1 end
function Screen:getWidth() return self.mode % 2 == 0 and 600 or 800 end
function Screen:getHeight() return self.mode % 2 == 0 and 800 or 600 end
local gyro = {}
local Device = { screen = Screen, has_g = false }
function Device:hasGSensor() return self.has_g end
function Device:toggleGSensor(on) gyro[#gyro + 1] = on end
package.loaded["device"] = Device

local shown, dirty, ticks = {}, {}, {}
local UIManager = { _window_stack = {} }
function UIManager:show(w) shown[#shown + 1] = w end
function UIManager:setDirty(w, how) dirty[#dirty + 1] = { w = w, how = how } end
function UIManager:nextTick(fn) ticks[#ticks + 1] = fn end
package.loaded["ui/uimanager"] = UIManager
package.loaded["gettext"] = function(s) return s end
package.loaded["gzreader_log"] = { info = function() end, warn = function() end }
package.loaded["ui/widget/infomessage"] = { new = function(_s, o) return o end }

local Rotation = require("gzreader_rotation")

print("== the Auto-rotate tile")
;(function()
    check(Rotation.autoTile() == nil, "no accelerometer (Kindle 3, Paperwhite 3…): no Auto-rotate tile")
    Device.has_g = true
    local t = Rotation.autoTile()
    check(t and t.id == "autorotate" and t.on == true and t.label == "Auto-rotate" and t.icon == "autorotate",
        "Oasis, Scribe: the tile, on by default (KOReader's default), drawn inverted")
    t.run()
    check(data.input_ignore_gsensor == true and gyro[#gyro] == false and shown[#shown].text:match("off"),
        "a tap: off, saved as KOReader saves it (input_ignore_gsensor), the accelerometer's events ignored, said so")
    t = Rotation.autoTile()
    check(t.on == false and t.label == "Auto-rotate off" and t.icon == "autorotate_off", "…and the tile says it's off")
    t.run()
    check(data.input_ignore_gsensor == nil and gyro[#gyro] == true and Rotation.autoOn() and shown[#shown].text:match("on"),
        "a tap again: on")
end)()

print("== Home and books keep the screen's rotation")
;(function()
    data = {}
    check(Rotation.setup() == true and data.lock_rotation == true and data.gzreader_rotation_kept == true,
        "first start: KOReader's \"Keep current rotation across views\" ticked")
    data.lock_rotation = false
    check(Rotation.setup() == false and data.lock_rotation == false, "once only: unticked later in KOReader's settings, it stays unticked")
    data = { lock_rotation = false }
    check(Rotation.setup() == false and data.lock_rotation == false and data.gzreader_rotation_kept, "unticked before: left as it was")
    -- KOReader's file manager honours it: Home doesn't go back to fm_rotation_mode
    local fm = source("../../frontend/apps/filemanager/filemanager.lua")
    check(fm:match('isTrue%("lock_rotation"%)') and fm:match('if not locked then%s+local mode = G_reader_settings:readSetting%("fm_rotation_mode"%)'),
        "Home (KOReader's file manager) keeps the rotation while lock_rotation is on")
    check(source("main.lua"):match('require%("gzreader_rotation"%)%.setup%(%)'), "set up at start (main.lua)")
end)()

print("== GZreader's pages turn with the screen")
;(function()
    Screen.mode = 0
    local fm_turns = {}
    local fm = { onSetRotationMode = function(_s, m) fm_turns[#fm_turns + 1] = m; Screen:setRotationMode(m) end }
    package.loaded["apps/filemanager/filemanager"] = { instance = fm }
    local Page = { covers_fullscreen = true }
    Page.__index = Page
    local laid = 0
    Rotation.follow(Page, function(p) laid = laid + 1; p.dimen = { w = Screen:getWidth(), h = Screen:getHeight() } end)
    local closed = 0
    local p = setmetatable({ dimen = { w = 600, h = 800 } }, Page)
    check(type(Page.onSetRotationMode) == "function" and Page.gzRelayout, "a followed page has a rotation handler")
    dirty = {}
    check(p:onSetRotationMode(1) == true and Screen.mode == 1 and fm_turns[1] == 1 and laid == 1 and p.dimen.w == 800,
        "a turn (the accelerometer's event, sent to the page in front): Home under it turned too, the page laid out at 800 × 600")
    check(dirty[#dirty].w == "all" and dirty[#dirty].how == "full", "…the whole screen drawn again")
    check(p:onSetRotationMode(1) == true and laid == 1, "the same rotation again: nothing laid out")
    check(p:onSetRotationMode(nil) == false, "no rotation: not handled")
    -- in a book: the book turns (its view), not Home
    local view_turns = {}
    package.loaded["apps/reader/readerui"] = { instance = { view = { onSetRotationMode = function(_s, m) view_turns[#view_turns + 1] = m; Screen:setRotationMode(m) end } } }
    p:onSetRotationMode(0)
    check(view_turns[1] == 0 and #fm_turns == 1 and laid == 2 and p.dimen.w == 600, "in a book (a quick note over it): the book laid out again")
    package.loaded["apps/reader/readerui"] = nil
    -- nothing under it handles rotations: the screen is still turned
    package.loaded["apps/filemanager/filemanager"] = nil
    p:onSetRotationMode(3)
    check(Screen.mode == 3 and laid == 3, "with neither: the screen turned all the same")
    package.loaded["apps/filemanager/filemanager"] = { instance = fm }
    -- closing it: the page under it laid out again
    Page.onCloseWidget = nil
    Rotation.follow(Page, Page.gzRelayout)
    local Old = { covers_fullscreen = true }; Old.__index = Old
    function Old.onCloseWidget() closed = closed + 1 end
    Rotation.follow(Old, function(o) o.relaid = true; o.dimen = { w = Screen:getWidth(), h = Screen:getHeight() } end)
    local o = setmetatable({}, Old)
    o._gz_turned = true
    ticks = {}
    o:onCloseWidget()
    check(closed == 1 and #ticks == 1, "closing a turned page: its own close runs, the page under it settled after")
    local under = setmetatable({ dimen = { w = 600, h = 800 } }, Page) -- (laid out in portrait; the screen is landscape now)
    UIManager._window_stack = { { widget = fm }, { widget = under } }
    ticks[1]()
    check(under.dimen.w == 800 and under._gz_turned, "a GZreader page under it (a note under the editor): laid out again, and settles its own when it closes")
    -- ZenOS's tab pages (the Notes tab) and KOReader's menus: their own handler, as if the screen were still the old way
    local seen
    local tab = { covers_fullscreen = true, dimen = { w = 600, h = 800 },
        onSetRotationMode = function(_s, m) seen = { m = m, screen_was = Screen:getRotationMode() }; Screen:setRotationMode(m); return true end }
    UIManager._window_stack = { { widget = fm }, { widget = tab }, { widget = { toast = true } } }
    check(Rotation.settle() == true and seen.m == 3 and seen.screen_was % 2 ~= 3 % 2 and Screen.mode == 3,
        "the Notes tab under it: reopened by its own handler (the screen the other way while it looks), the screen as it is")
    UIManager._window_stack = { { widget = fm }, { widget = { covers_fullscreen = true, dimen = { w = 800, h = 600 }, onSetRotationMode = function() error("laid out") end } } }
    check(Rotation.settle() == false, "a page already the screen's size: left alone")
    UIManager._window_stack = { { widget = fm } }
    check(Rotation.settle() == false, "Home in front: nothing (turned with the page)")
end)()

print("== which pages follow")
;(function()
    local notes, editor, journal = source("gzreader_notes.lua"), source("gzreader_noteeditor.lua"), source("gzreader_journalscreen.lua")
    check(notes:match('require%("gzreader_rotation"%)%.follow%(NoteView,'), "a note (Notes tab → a note)")
    check(editor:match('require%("gzreader_rotation"%)%.follow%(Editor, Editor%.gzRelayout%)'), "the note editor (and a quick note's window)")
    check(journal:match('require%("gzreader_rotation"%)%.follow%(JournalScreen,'), "a journal entry")
    local panel = source("gzreader_panel.lua")
    check(panel:match('{ id = "autorotate", label = _%("Auto%-rotate"%)') and panel:match('require%("gzreader_rotation"%)%.autoTile%(%)'),
        "the panel has the tile (and Settings → Interface → Quick panel a tick for it)")
    local f = io.open(PLUGIN .. "/icons/panel/autorotate.svg"); local g = io.open(PLUGIN .. "/icons/panel/autorotate_off.svg")
    check(f and g, "its icons, on and off"); if f then f:close() end; if g then g:close() end
end)()

print("== the note editor laid out again keeps what was written")
;(function()
    local src = source("gzreader_noteeditor.lua")
    local body = src:match("(function Editor:gzRelayout%(%).-\nend)\n")
    check(body ~= nil, "Editor:gzRelayout found")
    if not body then return end
    local env = setmetatable({ Editor = {}, UIManager = UIManager }, { __index = _G })
    assert(load(body, "gzRelayout", "t", env))()
    local inits = 0
    local function input(text)
        return { text = text, is_text_edited = false, freed = false,
            getText = function(i) return i.text end,
            setText = function(i, t) i.text = t end,
            onCloseKeyboard = function(i) i.kb_closed = true end,
            free = function(i) i.freed = true end }
    end
    local e = {
        rich = false, visibility = "PUBLIC", space = "spaces/1", original = "old", original_vis = "PRIVATE",
        original_space = nil, pages = { { path = "/x.png", changed = true } }, pages_reordered = true, vk = true,
        init = function(s)
            inits = inits + 1
            s.visibility, s.space, s.pages, s.pages_reordered = "PRIVATE", nil, nil, nil
            s.original = "from memo"
            s.input = input(s.original)
        end,
        text = function(s) return s.input:getText() end,
        drawChrome = function(s) s.chrome = true end,
        keyboardBack = function(s) s.kb_back = true end,
    }
    e.input = input("typed so far")
    e.input.is_text_edited = true
    local old_input = e.input
    ticks = {}
    env.Editor.gzRelayout(e)
    check(inits == 1 and old_input.kb_closed and old_input.freed, "the old text box and its keyboard put away, the page made again")
    check(e.input ~= old_input and e.input.text == "typed so far" and e.input.is_text_edited == true, "what was typed is still there")
    check(e.visibility == "PUBLIC" and e.space == "spaces/1" and e.original == "old" and e.pages[1].changed and e.pages_reordered,
        "who can see it, its space, its drawings and what it started as: kept (Back still asks to save)")
    check(e.chrome and #ticks == 1, "the title and toolbar drawn; the keyboard back a moment later")
    ticks[1]()
    check(e.kb_back, "…the keyboard is back")
    -- formatted notes: the page itself (its blocks) kept
    local doc = { "blocks" }
    local r = { rich = true, doc = doc, vk = false,
        init = function(s) s.got_doc = s._gz_doc; s.doc = s._gz_doc or { "parsed" }; s.input = input("") end,
        text = function() error("not read: the blocks are kept") end,
        drawChrome = function() end }
    r.input = input("")
    env.Editor.gzRelayout(r)
    check(r.got_doc == doc and r.doc == doc and r._gz_doc == nil, "a formatted note: its blocks given to the new page (not read again from the saved note)")
    check(src:match("local ok, doc = true, self%._gz_doc\n%s+if not doc then ok, doc = pcall%(require%(\"gzreader_blocks\"%)%.parse, self%.original%) end"),
        "Editor:init takes those blocks when it's laid out again")
end)()

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
