-- The Grimmory and Notes tabs with ZenOS's status row (no close button),
-- and Settings → Connections → Memos (Notes): connection, synced tags, storage used / free up
-- space, notes kept, attachment limit. With demo/demo_grimmory.py on
-- 127.0.0.1:18080 and demo/mock_memos.py --sample on 18090.
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
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function say(label, fn) add({ fn = function(E) E.say(label, fn()) end, after = 1 }) end

-- the tabs' title bars
combo("Alt", "R", 8)
shot("ns-1-grimmory-tab")
combo("Alt", "T", 6)
shot("ns-2-notes-connect")
add({ fn = function(E)
    local Notes = require("gzreader_notes")
    E.say("connect ->", tostring(Notes.connect(plugin(), "127.0.0.1:18090", "memos-test-token")))
    if Notes.connect_menu then require("ui/uimanager"):close(Notes.connect_menu, "full"); Notes.connect_menu = nil end
    Notes.show(plugin())
end, after = 12 })
shot("ns-3-notes-board")
-- an attachment downloaded, so there's storage to show
add({ fn = function()
    local Notes = require("gzreader_notes")
    for _i, m in ipairs(Notes.notes or {}) do
        for _j, a in ipairs(m.attachments or {}) do Notes.fetchFile(plugin(), a) end
    end
end, after = 8 })
key("Back", 3)
-- Settings → Notes
key("Menu", 4)
key("U", 6)
shot("ns-4-settings")
key("U", 5) -- Connections
shot("ns-4b-connections")
key("W", 5) -- Memos (Notes)
shot("ns-5-notes-settings")
key("Q", 4)
shot("ns-6-connection")
key("Back", 3)
key("W", 4)
shot("ns-7-sync")
key("E", 4) -- the first tag
key("T", 4) -- another
shot("ns-8-sync-tags-chosen")
say("synced tags:", function() return table.concat(plugin().store.memos.sync_tags or { "(all)" }, ",") end)
key("Back", 3)
shot("ns-9-notes-settings-after")
key("E", 4)
shot("ns-10-storage")
key("Back", 3)
key("R", 4)
shot("ns-11-kept")
key("Back", 3)
key("T", 4)
shot("ns-12-attachment-limit")
key("Q", 3) -- 10 MB
say("attachment limit:", function() return tostring(require("gzreader_notes").prefs(plugin()).files_mb) end)
key("Back", 3); key("Back", 3); key("Back", 3); key("Back", 3); key("Back", 3)
-- the board now has only the synced tags
combo("Alt", "T", 12)
add({ wait = 6 })
shot("ns-13-board-synced")
say("board notes:", function()
    local t = {}
    for _i, m in ipairs(require("gzreader_notes").notes or {}) do t[#t + 1] = table.concat(m.tags, "/") end
    return table.concat(t, " ")
end)
return s
