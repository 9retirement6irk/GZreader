-- An opened note formatted as Memos shows it (gzreader_inline.lua), on any
-- model: bold, italic, struck, code and a link; a quote; lists; a rule; a
-- table (its columns within the page).
--   python3 -I demo/mock_memos.py 18090 --sample &
--   GZ_EMU_MODEL=k3|pw3|scribe GZ_EMU_TREE=<tree>/koreader run.sh note_view_format.lua <out>
-- Checks go to <out>/note-view-format-checks.txt; the shot is 1-formatted.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function N() return require("gzreader_notes") end
local NOTE = table.concat({
    "# Packing list", "",
    "Some **bold**, *italic*, ~~struck~~, `code` and a [link](https://example.com). A longer sentence follows so that the paragraph wraps onto a second line on every screen.", "",
    "> A quoted line from the guide book.", "",
    "1. First step", "2. Second step", "",
    "- a bullet with *italic*", "  - nested", "",
    "- [ ] tent", "- [x] **stove**", "",
    "| Item | Weight |", "| --- | ---: |", "| Tent | 1.2 kg |",
    "| **Stove** with a long name that has to wrap in its cell on a small screen | 300 g |", "",
    "---", "", "#travel #gear" }, "\n")
--- Every widget under `w` (its numbered children), depth first.
local function walk(w, fn, seen)
    seen = seen or {}
    if type(w) ~= "table" or seen[w] then return end
    seen[w] = true
    fn(w)
    for _i, c in ipairs(w) do walk(c, fn, seen) end
end
add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    -- (the note put into the mock Memos, so it's opened as any other is)
    local http, ltn12 = require("socket.http"), require("ltn12")
    local body = require("json").encode({ content = NOTE, visibility = "PRIVATE" })
    http.request{ url = "http://127.0.0.1:18090/api/v1/memos", method = "POST", source = ltn12.source.string(body),
        headers = { ["Content-Type"] = "application/json", ["Content-Length"] = #body, ["Authorization"] = "Bearer memos-test-token" } }
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    N().show(p)
end, after = 10 })
add({ fn = function(E)
    for _i, m in ipairs(N().visible()) do
        if tostring(m.content):find("Packing list", 1, true) then E.v = N().showNote(plugin(), m) end
    end
end, after = 5 })
add({ shot = "1-formatted", after = 0.5 })
add({ fn = function(E)
    local sw = require("device").screen:getWidth()
    local texts, grid = {}, nil
    walk(E.v[1], function(w)
        if w.chars and w.marks and w.lines then texts[#texts + 1] = w end
        if w.cells and w.cols then grid = w end
    end)
    local function has(pred)
        for _i, t in ipairs(texts) do
            for k = 1, #t.chars do if t.marks[k] and pred(t.marks[k], t, k) then return t end end
        end
    end
    local para = has(function(m) return m.b end)
    check(para and has(function(m) return m.i end) and has(function(m) return m.s end) and has(function(m) return m.c end)
        and has(function(m) return m.link == "https://example.com" end),
        "the paragraph's words: bold, italic, struck, code and a link, each marked (not plain)")
    check(para and #para.lines >= 2 and not table.concat(para.chars):find("*", 1, true), "…wrapped onto more lines; no stars left in it")
    local bold, plain
    for k = 1, #para.chars do if para.marks[k] and para.marks[k].b then bold = para.faces[k] elseif not para.marks[k] then plain = para.faces[k] end end
    check(bold and plain and bold ~= plain, "…bold in another face than the plain words")
    local quote
    for _i, t in ipairs(texts) do if table.concat(t.chars) == "A quoted line from the guide book." then quote = t end end
    check(quote and type(quote.color) == "cdata", "the quote: its words without the >, grey")
    local right = grid and grid.dimen.x + grid.dimen.w
    check(grid and #grid.cols == 2 and #grid.cells == 3 and grid.align[2] == "right" and right <= sw and grid.dimen.x >= 0,
        "the table: two columns, a head and two rows, the second column to the right; inside the page (" .. tostring(right) .. " of " .. sw .. ")")
    check(grid and grid.cells[1][2].lines and #grid.cells[1][2].lines == 1, "…a short head (Weight) on one line")
    check(#E.v.picks == 2, "the two checklist items still have their keys / taps")
    local f = io.open(E.out .. "/note-view-format-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
