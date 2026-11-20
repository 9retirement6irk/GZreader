-- The note editor's block menu (Memos' "/" menu) on a touch Kindle: "/" on
-- an empty line opens it (Heading 1–4, the lists, Quote, Callout, Collapsible
-- section, Code block, Table, Divider); Callout asks its kind; the selection
-- bar's + and ⋮ → Add a block open it too.
--   python3 -I demo/mock_memos.py 18090 --sample &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh notes_blocks.lua <out>
-- Checks go to <out>/notes-blocks-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function editor()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.on_save and w.widget.input then return w.widget end end
end
local function shown(d)
    for _i, w in ipairs(UIM()._window_stack) do if w.widget == d then return true end end
    return false
end
local note

add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    note = require("gzreader_memos"):new(p.store.memos):create("Weekend", "PRIVATE")
    require("gzreader_notes").show(p)
end, after = 6 })
add({ fn = function(E)
    local Notes = require("gzreader_notes")
    for _i, n in ipairs(Notes.notes or {}) do if n.name == note.name then Notes.edit(plugin(), n) end end
end, after = 4 })
add({ fn = function(E)
    local e = editor()
    check(e and e.rich, "a touch Kindle: the formatted page")
    -- the keyboard types "/" on a new line
    e.input:addChars("\n")
    e.input:addChars("/")
end, after = 2 })
add({ shot = "1-slash-menu", after = 0.5 })
add({ fn = function(E)
    local e = editor()
    local d = e.block_dialog
    check(d and shown(d) and E.findText("Heading 1") and E.findText("Callout") and E.findText("Quote"),
        "/ on an empty line: the block menu (Heading 1 … Callout, Quote …)")
    E.tap("Callout")
end, after = 2 })
add({ shot = "2-callout-kinds", after = 0.5 })
add({ fn = function(E)
    check(E.findText("Warning") ~= nil and E.findText("Caution") ~= nil, "Callout: its kinds (Note … Caution)")
    E.tap("Warning")
end, after = 2 })
add({ fn = function(E)
    local e = editor()
    e.input:addChars("Bring a lamp")
    check(e:text() == "Weekend\n\n> [!WARNING]\n> Bring a lamp", "a callout typed into: " .. e:text():gsub("\n", "\\n"))
    -- ⋮ → Add a block → Table
    E.tap({ e.bar_buttons.options.dimen.x + 10, e.bar_buttons.options.dimen.y + 10 })
end, after = 2 })
add({ fn = function(E)
    check(E.findText("Add a block (heading, quote, table…)") ~= nil, "⋮: Add a block")
    E.tap("Add a block (heading, quote, table…)")
end, after = 2 })
add({ fn = function(E)
    -- the menu's second page (8 rows a page): Table
    if not E.findText("Table") then
        local d = editor().block_dialog
        if d and d.buttontable and d.buttontable.onNextPage then d.buttontable:onNextPage() end
    end
end, after = 1 })
add({ fn = function(E)
    check(E.findText("Table") ~= nil, "…the menu, Table on it")
    E.tap("Table")
end, after = 2 })
add({ fn = function(E)
    local e = editor()
    e.input:addChars("tent")
    check(e:text():find("> Bring a lamp\n\n| Column 1 | Column 2 |\n| --- | --- |\n| tent |  |", 1, true) ~= nil,
        "Table: after the callout, typed into its first cell")
end, after = 2 })
add({ shot = "3-page", after = 0.5 })
add({ fn = function(E) editor():save() end, after = 5 })
add({ fn = function(E)
    local N = require("gzreader_notes")
    for _i, m in ipairs(N.visible()) do
        if tostring(m.content):find("[!WARNING]", 1, true) then E.v = N.showNote(plugin(), m) end
    end
end, after = 5 })
add({ shot = "4-opened", after = 0.5 })
add({ fn = function(E)
    local words = {}
    local function walk(w, seen)
        seen = seen or {}
        if type(w) ~= "table" or seen[w] then return end
        seen[w] = true
        if w.chars and w.lines then words[#words + 1] = table.concat(w.chars) end
        for _i, c in ipairs(w) do walk(c, seen) end
    end
    walk(E.v and E.v[1])
    local all = table.concat(words, "|")
    check(E.v ~= nil and all:find("Warning", 1, true) ~= nil and not all:find("[!WARNING]", 1, true) and all:find("Bring a lamp", 1, true) ~= nil,
        "saved and opened: the callout shows its kind (Warning), not [!WARNING]: " .. all)
end, after = 1 })
add({ fn = function(E)
    local f = io.open(E.out .. "/notes-blocks-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })
return s
