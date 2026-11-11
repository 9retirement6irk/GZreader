-- GZreader's menus drawn as ZenOS rows (gzreader_rows.lua): an icon on the
-- left, the label, an arrow on the right, ZenOS's row height. Opens each
-- one, takes a shot, checks every row is a ZenOS row and no label is cut
-- off (`text_truncated`, set by ZenOS's row), then closes it. Any model:
--   GZ_EMU_MODEL=k4 GZ_EMU_TREE=<tree>/koreader ./run.sh menu_rows.lua <out>
-- (the test suite's mock on 18080 isn't needed: nothing is signed in)
local s = { start = 12, { key = "Back", after = 4 } }
local function add(t) s[#s + 1] = t end

local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function top()
    local st = require("ui/uimanager")._window_stack
    return st[#st] and st[#st].widget
end
local function check(E, ok, what) E.say((ok and "ok " or "FAIL ") .. what) end
local function rowsCheck(E, name)
    local m = top()
    local rows, plain, cut = 0, 0, {}
    for _i, row in ipairs(m and m.item_group or {}) do
        if row.entry and row.entry._zen_settings_row and row._zen_settings_style then rows = rows + 1 else plain = plain + 1 end
        if row.text_truncated then cut[#cut + 1] = tostring(row.entry and row.entry.text) end
    end
    check(E, rows > 0 and plain == 0, name .. ": ZenOS rows (" .. rows .. ", plain " .. plain .. ")")
    check(E, #cut == 0, name .. ": no label cut off" .. (#cut > 0 and (": " .. table.concat(cut, " | ")) or ""))
end
local function close()
    local m = top()
    if m then require("ui/uimanager"):close(m) end
end
local function screen(name, open)
    add({ fn = function() open() end, after = 4 })
    add({ shot = name })
    add({ fn = function(E) rowsCheck(E, name); close() end, after = 2 })
end

screen("calendar-connect", function() require("gzreader_calendar").showConnect(plugin()) end)
screen("notes-connect", function() require("gzreader_notes").showConnect(plugin(), true) end)
screen("music-signed-out", function()
    local Tab = require("gzreader_musictab")
    Tab.showList(plugin())
end)
screen("downloads", function()
    local D = require("gzreader_download")
    D.active = { title = "Diper Överlöde", last_size = 30 * 1048576, expected = 77 * 1048576, book_id = 1 }
    D.queue = { { book = { id = 2, title = "Diary of a Wimpy Kid: No Brainer" } }, { book = { id = 3, title = "Hot Mess" } },
        { book = { id = 4, title = "Diary of a Wimpy Kid: Fight or Flight" } } }
    require("gzreader_tasks").show()
end)
add({ fn = function()
    local D = require("gzreader_download")
    D.active, D.queue = nil, {}
end, after = 1 })
screen("copy-choose", function()
    require("gzreader_copy").choose(plugin(), {
        offer = { name = "Kindle Touch", grimmory = { host = "books.example.com", username = "reader" },
            memos = { host = "memos.example.com" }, caldav = { host = "dav.example.com", username = "reader" },
            links = { { n = 1, name = "Holidays" } } },
        dev = { name = "Kindle Touch" },
    }, {})
end)
return s
