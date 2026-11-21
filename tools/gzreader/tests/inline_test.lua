-- gzreader_inline.lua's pure part: what kind a line of a note is, how its
-- words wrap, a table read from its rows, and its columns' widths.
--   luajit inline_test.lua   (from tools/gzreader/tests)
package.path = (arg[1] or "../../../plugins/gzreader.koplugin") .. "/?.lua;" .. package.path
local Inline = require("gzreader_inline")
local Blocks = require("gzreader_blocks")
local pass, fail = 0, 0
local function check(ok, what)
    if ok then pass = pass + 1 else fail = fail + 1; print("FAIL " .. what) end
end
local function kind(l) local c = Inline.classify(l); return c.kind .. ":" .. c.text .. ":" .. tostring(c.depth or "") .. ":" .. tostring(c.num or "") end

check(kind("") == "blank:::" and kind("   ") == "blank:::" and kind("&nbsp;") == "blank:::", "a blank line, and Memos' empty paragraph (&nbsp;)")
check(kind("---") == "rule:::" and kind("***") == "rule:::" and kind(" ____ ") == "rule:::", "a rule: ---, ***, ___")
check(kind("> said") == "quote:said::" and kind(">said") == "quote:said::", "a quote, its mark off")
check(Inline.classify("> [!WARNING]").kind == "callout" and Inline.classify("> [!WARNING]").callout == "warning"
    and Inline.classify(">[!tip]").callout == "tip" and kind("> [!SOMETHING]") == "quote:[!SOMETHING]::"
    and kind("> [!NOTE] words") == "quote:[!NOTE] words::",
    "a callout's first line (> [!WARNING], Memos' five kinds); anything else stays a quote")
check(kind("- milk") == "bullet:milk:0:" and kind("  * eggs") == "bullet:eggs:1:" and kind("    + tea") == "bullet:tea:2:", "bullets, and how deep")
check(kind("1. one") == "ordered:one:0:1" and kind("  12) twelve") == "ordered:twelve:1:12", "numbered items, their number")
check(kind("Plain words") == "para:Plain words::" and kind("-not a list") == "para:-not a list::" and kind("1.5 km") == "para:1.5 km::",
    "anything else is a paragraph (a dash or a number without a space after it too)")

-- wrapping (every character 10 wide)
local function wrap(text, max)
    local chars = Blocks.chars(text)
    local w = {}
    for k, ch in ipairs(chars) do w[k] = ch == "\n" and 0 or 10 end
    local out = {}
    for _i, l in ipairs(Inline.wrap(chars, w, max)) do out[#out + 1] = table.concat(chars, "", l.a, l.z) end
    return table.concat(out, "|")
end
check(wrap("one two three", 80) == "one two |three", "words wrap at a space (which stays at the line's end)")
check(wrap("abcdefghijkl", 50) == "abcde|fghij|kl", "a word longer than the line is cut")
check(wrap("a\nb", 100) == "a\n|b", "a line break ends a line")
check(wrap("", 100) == "", "no words: one empty line")
check(wrap("ab cd", 20) == "ab |cd", "a space may hang past the edge")

-- inline marks, as the widget reads them (the editor's reader)
local chars, marks = Blocks.readInline("a **b** *c* ~~d~~ `e` [f](https://example.com)")
local seen = {}
for k, ch in ipairs(chars) do
    local m = marks[k]
    if m then seen[#seen + 1] = ch .. (m.b and "b" or "") .. (m.i and "i" or "") .. (m.s and "s" or "") .. (m.c and "c" or "") .. (m.link and "l" or "") end
end
check(table.concat(chars) == "a b c d e f" and table.concat(seen, " ") == "bb ci ds ec fl", "bold, italic, struck, code and a link: the marks off, each character marked")

-- tables
local function cells(l) local c = Inline.cells(l); return c and table.concat(c, "/") end
check(cells("| a | b |") == "a/b" and cells("|a|b") == "a/b" and cells("| a \\| b | c |") == "a | b/c" and cells("| | x |") == "/x",
    "a row's cells (a \\| is a bar in a cell; an empty cell kept)")
check(Inline.cells("not a row") == nil, "a line that doesn't start with | isn't a row")
local t = Inline.tableAt({ "| Item | Weight | Note |", "| --- | ---: | :-: |", "| Tent | 1.2 kg | x |", "| Stove | 300 g |", "after" }, 1)
check(t and t.n == 4 and table.concat(t.head, "/") == "Item/Weight/Note" and table.concat(t.align, "/") == "left/right/center"
    and #t.rows == 2 and t.rows[2][2] == "300 g" and t.rows[2][3] == nil, "a table: its head, how each column is aligned, its rows (a short row kept), the lines it took")
check(Inline.tableAt({ "| a | b |", "words" }, 1) == nil and Inline.tableAt({ "| a | b |", "| x | y |" }, 1) == nil,
    "rows without the row of dashes under the first aren't a table")
check(Inline.tableAt({ "| a |" }, 1) == nil, "…nor is a single row")

-- columns
local function cols(nat, width, min) return table.concat(Inline.columns(nat, width, min), "/") end
check(cols({ 100, 50 }, 400, 40) == "100/50", "columns that fit keep their own widths")
check(cols({ 700, 60 }, 500, 40) == "440/60", "too wide: the narrow column keeps its width, the wide one takes the rest")
check(cols({ 600, 600 }, 400, 40) == "200/200", "two wide columns share the room")
check(cols({ 900, 300, 30 }, 430, 40) == "300/100/30", "…by how wide they are")
local c = Inline.columns({ 500, 500, 500, 500 }, 100, 40)
check(c[1] == 25 and c[4] == 25, "more columns than there's room for at the least width: an even share")

print(string.format("inline: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
