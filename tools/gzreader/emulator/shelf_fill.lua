-- The Downloads tab's shelves (bookshelf view) take as many books as fit by
-- their spines' widths, and letter keys go from Q to L only: the books after
-- L have none, and Del and the bottom row's keys aren't taken for them.
--   GZ_EMU_TREE=<tree>/koreader ./run.sh shelf_fill.lua <out>
-- Books: 40 copies of GZ_EMU_BOOK (an EPUB). Writes <out>/shelf_fill.txt.
local s = { start = 12, { key = "Back", after = 4 } }
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local st = {}
s[#s + 1] = { fn = function()
    local src = os.getenv("GZ_EMU_BOOK") or "/root/work/demo/lib/1.epub"
    local dir = require("apps/filemanager/filemanager").instance.gzreader:libraryDir()
    for i = 1, 40 do os.execute(string.format("cp '%s' '%s/Book %02d.epub'", src, dir, i)) end
    pcall(function() require("common/gz_view").set("bookshelf") end)
end, after = 2 }
s[#s + 1] = { combo = { "Alt", "W" }, after = 15 } -- the Downloads tab
s[#s + 1] = { shot = "shelves" }
s[#s + 1] = { fn = function()
    local fc = require("apps/filemanager/filemanager").instance.file_chooser
    st.fc = fc
    local View = require("gzreader_shelfview")
    local rows = fc._gz_rows or 0
    -- what's on the page, shelf by shelf, and the room left on each
    local shown, hidden, lettered, after_l = 0, 0, 0, 0
    for _i, row in ipairs(fc.item_group or {}) do
        for _j, it in ipairs(row.items or {}) do
            if it.hidden then hidden = hidden + 1 else shown = shown + 1 end
            local letter = it.slot <= View.KEYS and fc.item_shortcuts[it.slot]
            if letter then lettered = lettered + 1 elseif it.slot > View.KEYS then after_l = after_l + 1 end
        end
    end
    lines[#lines + 1] = string.format("info shelves %d, per page %d, shown %d, hidden %d", rows, fc.perpage, shown, hidden)
    check(fc.perpage > 20, "more than 20 books on a page when their spines fit (" .. fc.perpage .. ")")
    check(hidden == 0, "none of them hidden: they all fit on the shelves")
    check(lettered == math.min(View.KEYS, shown) and after_l == shown - lettered, "letters Q to L only; the books after L have none")
    st.page = fc.page
end, after = 1 }
-- Del: not a book's key any more (it was the 20th)
s[#s + 1] = { fn = function()
    st.opened = nil
    local RUI = require("apps/reader/readerui")
    st.show = RUI.showReader
    RUI.showReader = function(_r, file) st.opened = file end
end, after = 1 }
s[#s + 1] = { key = "Del", after = 4 }
s[#s + 1] = { fn = function()
    check(st.opened == nil, "Del opens nothing")
end, after = 1 }
s[#s + 1] = { key = "L", after = 6 }
s[#s + 1] = { fn = function(E)
    require("apps/reader/readerui").showReader = st.show
    check(st.opened ~= nil or (require("ui/uimanager"):getTopmostVisibleWidget() or {}).name ~= "filemanager",
        "L still opens its book (" .. tostring(st.opened) .. ")")
    local f = io.open(E.out .. "/shelf_fill.txt", "w")
    if f then f:write(table.concat(lines, "\n"), "\n"); f:close() end
end, after = 1 }
return s
