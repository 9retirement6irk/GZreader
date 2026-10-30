-- The Notes tab (Memos), with demo/mock_memos.py --sample on 127.0.0.1:18090
-- and demo/demo_grimmory.py on 18080 (for the sign-in at the start):
-- not connected yet, connected (board), a note, ticking a box, a picture,
-- filters and tags, pages, the editor with its toolbar, saving, and a PDF.
local readme = dofile("/root/work/koreader/tools/gzreader/emulator/readme_shots.lua")
local s = { start = readme.start }
for _i, step in ipairs(readme) do
    s[#s + 1] = step
    if step.shot == "home-empty" then break end
end
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function key(k, after) add({ key = k, after = after or 3 }) end
local function combo(a, b, after) add({ combo = { a, b }, after = after or 3 }) end
local function typed(text, after)
    add({ fn = function(E)
        for ch in text:gmatch(".") do
            if ch == " " then E.key("Space")
            elseif ch == "\n" then E.key("Press")
            elseif ch:match("%u") then E.combo("Shift", ch)
            else E.key(ch:upper()) end
        end
    end, after = after or (2 + #text * 0.25) })
end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end

shot("notes-0-tabbar")
combo("Alt", "T", 6) -- the 5th tab: Notes
shot("notes-1-connect")
add({ fn = function(E)
    local Notes = require("gzreader_notes")
    local ok, err = Notes.connect(plugin(), "127.0.0.1:18090", "memos-test-token")
    E.say("connect ->", tostring(ok), tostring(err))
    local UIManager = require("ui/uimanager")
    if Notes.connect_menu then UIManager:close(Notes.connect_menu, "full"); Notes.connect_menu = nil end
    Notes.show(plugin())
end, after = 14 })
shot("notes-2-board")
key("Right", 4)
key("Down", 4)
shot("notes-3-focus")
key("W", 6) -- the Georgia note
shot("notes-4-note")
key("W", 5) -- tick "trail map printed"
shot("notes-5-ticked")
add({ wait = 6 })
add({ fn = function(E)
    local h = io.popen("curl -s http://127.0.0.1:18090/__state")
    local st = h:read("*a"); h:close()
    E.say("memos has the tick:", tostring(st:find("- [x] trail map printed", 1, true) ~= nil))
end, after = 1 })
key("Back", 6)
key("Y", 12) -- the picture note
shot("notes-6-picture")
key("Back", 6)
key("F", 4)
shot("notes-7-filter")
key("W", 5) -- Tag…
shot("notes-8-tags")
key("Q", 10) -- the first tag
shot("notes-9-filtered")
key("F", 4)
key("Q", 10) -- All notes
key("RPgFwd", 8)
shot("notes-10-page2")
key("RPgBack", 8)
key("N", 6)
shot("notes-11-new")
typed("Pack for Springer Mountain")
key("Press", 1)
combo("Alt", "C", 2)
typed("stove fuel")
key("Press", 1)
combo("Alt", "C", 2)
typed("headlamp ")
combo("Alt", "G", 4) -- # Tag
shot("notes-12-tagpicker")
key("W", 3) -- a tag from the list
shot("notes-13-editor")
key("Down", 3) -- to the toolbar (from the last line)
key("Right", 2)
shot("notes-14-toolbar")
combo("Alt", "S", 14) -- save: queued, then sent
shot("notes-15-saved")
add({ fn = function(E)
    local h = io.popen("curl -s http://127.0.0.1:18090/__state")
    local st = h:read("*a"); h:close()
    E.say("memos has the new note:", tostring(st:find("Pack for Springer Mountain", 1, true) ~= nil),
        "private:", tostring(st:find('"content": "Pack for Springer Mountain[^"]*", "visibility": "PRIVATE"') ~= nil))
end, after = 1 })
key("E", 6) -- the Georgia note again (now 3rd)
shot("notes-16-note-again")
combo("Alt", "E", 6)
shot("notes-17-edit")
key("Back", 4) -- unchanged: closes without asking
key("R", 25) -- its PDF: downloaded, opened in the reader
shot("notes-18-pdf")
-- an older ZenOS config (Favorites tab) gets the Notes tab in its place
add({ fn = function(E)
    local M = require("config/manager")
    local cur = M.load()
    local old = require("common/utils").deepcopy(cur)
    old._meta.gz_notes_tab_migrated = nil
    old.navbar.custom_tabs = { { id = "ct_grimmory", type = "action", action = { grimmory_library = true }, label = "Grimmory", icon = "library" } }
    old.navbar.tab_order = { "home", "books", "continue", "ct_grimmory", "favorites" }
    old.navbar.show_tabs.favorites = true
    old.navbar.show_tabs.ct_notes = nil
    M.save(old)
    local new = M.load()
    E.say("migrated:", table.concat(new.navbar.tab_order, ","), "favorites shown:", tostring(new.navbar.show_tabs.favorites),
        "notes tab:", tostring(new.navbar.custom_tabs[2] and new.navbar.custom_tabs[2].id), tostring(new.navbar.show_tabs.ct_notes))
    local again = M.load()
    E.say("migrated twice: tabs", #again.navbar.custom_tabs)
end, after = 2 })
return s
