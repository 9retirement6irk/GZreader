-- The block editor's model (gzreader_blocks.lua): Memos Markdown read into
-- blocks and written back as Memos' rich editor (@usememos/editor 26.11)
-- writes it: unchanged blocks exactly as they were, `&nbsp;` for an empty
-- paragraph, escapes only where needed, Enter / Backspace as in its editor.
--   luajit blocks_test.lua <gzreader.koplugin>
local PLUGIN = arg[1]
package.path = PLUGIN .. "/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
local function eq(got, want, msg)
    if got == want then check(true, msg)
    else check(false, msg .. "\n         got:  " .. string.format("%q", tostring(got)) .. "\n         want: " .. string.format("%q", tostring(want))) end
end

local Blocks = require("gzreader_blocks")
local T = Blocks.textOf

local function kinds(doc)
    local t = {}
    for _i, b in ipairs(doc.blocks) do t[#t + 1] = b.kind .. (b.level and b.level or "") .. (b.done ~= nil and (b.done and "x" or "o") or "") end
    return table.concat(t, " ")
end

print("== reading Memos' notes")
;(function()
    local md = "# Garden plan\n\nBeds by the fence, **tomatoes** on the left.\n\n&nbsp;\n\n- [ ] seeds\n- [x] stakes\n\n1. dig\n2. plant\n\n- one\n- two\n\n#garden"
    local doc = Blocks.parse(md)
    eq(kinds(doc), "heading1 paragraph paragraph tasko taskx ordered ordered bullet bullet paragraph", "blocks: heading, text, empty line, tasks, numbers, bullets, tags")
    eq(T(doc.blocks[1]), "Garden plan", "a heading's words, no #")
    eq(T(doc.blocks[2]), "Beds by the fence, tomatoes on the left.", "a paragraph's words, no **")
    check(doc.blocks[2].marks[21] and doc.blocks[2].marks[21].b and not doc.blocks[2].marks[1], "…with tomatoes marked bold")
    check(Blocks.isEmptyParagraph(doc.blocks[3]), "&nbsp; is an empty line, not text")
    eq(T(doc.blocks[4]), "seeds", "a task's words, no - [ ]")
    check(doc.blocks[4].done == false and doc.blocks[5].done == true, "ticked or not")
    check(doc.blocks[6].num == 1 and doc.blocks[7].num == 2, "numbers kept")
    eq(T(doc.blocks[10]), "#garden", "tags stay words")
    eq(Blocks.write(doc), md, "unchanged: written back exactly")
end)()

print("== Memos 26.11's leftovers read as what they stand for")
;(function()
    local doc = Blocks.parse("a &#124; b \\* c &amp; d\\\ne")
    eq(T(doc.blocks[1]), "a | b * c & d\ne", "references, escapes and a hard line break")
    doc = Blocks.parse("&#160;")
    check(Blocks.isEmptyParagraph(doc.blocks[1]), "&#160; is an empty line too")
    doc = Blocks.parse("2 * 3 * 4 and snake_case_name")
    eq(T(doc.blocks[1]), "2 * 3 * 4 and snake_case_name", "a lone * and intraword _ aren't emphasis")
    check(not Blocks.hasMarks(doc.blocks[1]), "…no marks")
    doc = Blocks.parse("see [the docs](https://example.com/a) and `x*y` and ~~old~~ and *new*")
    local b = doc.blocks[1]
    eq(T(b), "see the docs and x*y and old and new", "links, code, strikethrough, italic: their words")
    check(b.marks[5].link == "https://example.com/a" and b.marks[19].c and b.marks[27].s and b.marks[35].i, "…with their marks")
end)()

print("== kept as written (shown, edited as Markdown)")
;(function()
    local md = "Intro\n\n```lua\nlocal x = 1\n```\n\n> a quote\n> more\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n---\n\n![](/file/attachments/a1/p.png)\n\n<details>\n<summary>More</summary>\n\nBody\n\n</details>"
    local doc = Blocks.parse(md)
    eq(kinds(doc), "paragraph raw raw raw raw image raw paragraph raw", "code, quote, table, divider, picture, HTML: kept whole")
    eq(Blocks.write(doc), md, "written back exactly")
    Blocks.setText(doc.blocks[1], "Intro!")
    local out = Blocks.write(doc)
    check(out:find("```lua\nlocal x = 1\n```", 1, true) and out:find("| a | b |\n|---|---|", 1, true) and out:sub(1, 7) == "Intro!\n",
        "one block edited: only it changes")
end)()

print("== writing as Memos' editor does")
;(function()
    local doc = { blocks = {}, original = "" }
    local h = Blocks.new("heading"); h.level = 1; Blocks.setText(h, "Shopping")
    local p = Blocks.new("paragraph"); Blocks.setText(p, "For the weekend")
    local e = Blocks.new("paragraph")
    local t1 = Blocks.new("task"); Blocks.setText(t1, "milk")
    local t2 = Blocks.new("task", t1); Blocks.setText(t2, "eggs"); t2.done = true
    local o1 = Blocks.new("ordered"); Blocks.setText(o1, "first")
    local o2 = Blocks.new("ordered", o1); Blocks.setText(o2, "second")
    local tail = Blocks.new("paragraph")
    doc.blocks = { h, p, e, t1, t2, o1, o2, tail }
    eq(Blocks.write(doc), "# Shopping\n\nFor the weekend\n\n&nbsp;\n\n- [ ] milk\n- [x] eggs\n\n1. first\n2. second",
        "blank line between blocks, list items together, &nbsp; for an empty line, none at the end")
end)()

print("== escaping only what would read as Markdown")
;(function()
    local function w(text) local b = Blocks.new("paragraph"); Blocks.setText(b, text); return Blocks.writeBlock(b) end
    eq(w("2 * 3 = 6"), "2 \\* 3 = 6", "* escaped")
    eq(w("snake_case and _x_"), "snake_case and \\_x\\_", "_ escaped outside words only")
    eq(w("- not a list"), "\\- not a list", "a line that would be a list")
    eq(w("1. not numbered"), "1\\. not numbered", "…or a numbered item")
    eq(w("# not a heading"), "&#35; not a heading", "…or a heading (# as &#35;, Memos reads \\# as a tag's)")
    eq(w("#tag stays a tag"), "#tag stays a tag", "a #tag isn't escaped")
    do -- a bold backslash: "**\\\\**" (an escaped backslash) closes the bold
        local c, m = Blocks.readInline("**\\\\**")
        eq(table.concat(c) .. (m[1] and m[1].b and "|b" or "|"), "\\|b", "**\\\\** reads as a bold backslash")
    end
    do -- a "#" or "-" alone before bold: not a heading or a list (the marker follows it)
        local d = Blocks.parse("#tag")
        Blocks.toggleMark(d.blocks[1], "b", 2, 4)
        eq(Blocks.write(d), "#**tag**", "\"#\" then bold: the # written as it is")
        local d2 = Blocks.parse("x")
        Blocks.setText(d2.blocks[1], "-x")
        Blocks.toggleMark(d2.blocks[1], "i", 2, 2)
        eq(Blocks.write(d2), "-*x*", "\"-\" then italic: not a list")
        local d3 = Blocks.parse("x")
        Blocks.setText(d3.blocks[1], "#")
        eq(Blocks.write(d3), "&#35;", "a lone # still escaped")
    end
    eq(w("a < b and <b>"), "a < b and \\<b>", "< only before a tag")
    eq(w("&amp; vs & alone"), "\\&amp; vs & alone", "& only before a reference")
    eq(w("[x]!"), "\\[x\\]!", "brackets")
    eq(w(" padded "), "&#32;padded&#32;", "spaces at the ends kept (as references)")
    eq(w("line one\nline two"), "line one\nline two", "a line break in a paragraph: a plain line ending")
    local back = Blocks.parse(w("2 * 3 = 6 - [x] snake_case & <b> # x"))
    eq(T(back.blocks[1]), "2 * 3 = 6 - [x] snake_case & <b> # x", "reads back as typed")
end)()

print("== marks written")
;(function()
    local b = Blocks.new("paragraph")
    Blocks.setText(b, "make this bold and that italic")
    Blocks.toggleMark(b, "b", Blocks.wordAt(b, 7))
    Blocks.toggleMark(b, "i", Blocks.wordAt(b, 21))
    eq(Blocks.writeBlock(b), "make **this** bold and *that* italic", "B and I on the word at the cursor")
    Blocks.toggleMark(b, "b", 1, #b.chars)
    eq(Blocks.writeBlock(b), "**make this bold and *that* italic**", "B on everything: one bold run, italic inside")
    Blocks.toggleMark(b, "b", 1, #b.chars)
    eq(Blocks.writeBlock(b), "make this bold and *that* italic", "B again: off")
    local doc = Blocks.parse("say **hi** there")
    Blocks.setText(doc.blocks[1], "say hi there") -- (the words its edit box shows: unchanged)
    check(not doc.blocks[1].dirty, "the same words: not changed")
    Blocks.setText(doc.blocks[1], "say hiya there")
    eq(Blocks.writeBlock(doc.blocks[1]), "say **hiya** there", "typing inside bold stays bold")
    Blocks.setText(doc.blocks[1], "well, say hiya there")
    eq(Blocks.writeBlock(doc.blocks[1]), "well, say **hiya** there", "typing before it doesn't")
    local link = Blocks.parse("[docs](https://example.com) here")
    Blocks.setText(link.blocks[1], "the docs here")
    eq(Blocks.writeBlock(link.blocks[1]), "the [docs](https://example.com) here", "a link keeps its address")
end)()

print("== Enter, Backspace, kinds")
;(function()
    local doc = Blocks.parse("- [ ] milk")
    local b = doc.blocks[1]
    local nb = Blocks.split(doc, b, #b.chars + 1)
    check(nb.kind == "task" and nb.done == false and #doc.blocks == 2, "Enter at a task's end: a new task")
    Blocks.setText(nb, "eggs")
    eq(Blocks.write(doc), "- [ ] milk\n- [ ] eggs", "…written in the same list")
    local nb2 = Blocks.split(doc, nb, #nb.chars + 1)
    local again = Blocks.split(doc, nb2, 1)
    check(again == nb2 and nb2.kind == "paragraph", "Enter on an empty item ends the list (a paragraph)")
    doc = Blocks.parse("Hello world")
    local p2 = Blocks.split(doc, doc.blocks[1], 6)
    eq(T(doc.blocks[1]) .. "|" .. T(p2), "Hello| world", "Enter in a paragraph splits it")
    local back, at = Blocks.joinPrevious(doc, p2)
    eq(T(back) .. "|" .. at, "Hello world|6", "Backspace at its start joins them back")
    doc = Blocks.parse("one\n\n- item")
    local item = doc.blocks[2]
    local same = Blocks.joinPrevious(doc, item)
    check(same == item and item.kind == "paragraph", "Backspace at a list item's start: a paragraph first")
    Blocks.setKind(item, "heading", 2)
    eq(Blocks.writeBlock(item), "## item", "Heading")
    Blocks.setKind(item, "heading", 2)
    eq(Blocks.writeBlock(item), "item", "Heading again: back to text")
    Blocks.setKind(item, "ordered")
    eq(Blocks.writeBlock(item, 1), "1. item", "Num")
    Blocks.setKind(item, "task")
    Blocks.toggleDone(item)
    eq(Blocks.writeBlock(item), "- [x] item", "Check, ticked")
    local nxt = Blocks.remove(doc, item)
    check(#doc.blocks == 1 and nxt == doc.blocks[1], "Delete takes the block away")
    eq(Blocks.write(doc), "one", "…and it's gone from the note")
    local first = Blocks.parse("x")
    check(Blocks.joinPrevious(first, first.blocks[1]) == nil, "Backspace at the very start does nothing")
end)()

print("== Memos' block menu (\"/\")")
;(function()
    local ids = {}
    for _i, m in ipairs(Blocks.MENU) do ids[#ids + 1] = m.id end
    eq(table.concat(ids, ","), "h1,h2,h3,h4,bullet,ordered,task,quote,callout,details,code,table,divider",
        "the menu has what Memos' \"/\" menu has, in its order")
    eq(table.concat(Blocks.CALLOUTS, ","), "NOTE,TIP,IMPORTANT,WARNING,CAUTION", "…callouts of Memos' five kinds")
    -- the Markdown each one writes (the plain page), and where the cursor goes
    local function md(id, c) local t, at = Blocks.menuMarkdown(id, c); return t .. "@" .. at end
    eq(md("h3"), "### @5", "Heading 3: ### ")
    eq(md("task"), "- [ ] @7", "To-do list: - [ ] ")
    eq(md("quote"), "> @3", "Quote: > ")
    eq(md("callout", "TIP"), "> [!TIP]\n> @12", "Callout: > [!TIP] and a line for its words")
    eq(md("code"), "```\n\n```@5", "Code block: a fence, the cursor on the empty line inside")
    eq(md("divider"), "---@4", "Divider: ---")
    local det, at = Blocks.menuMarkdown("details")
    check(det == "<details open>\n<summary></summary>\n\n\n\n</details>" and Blocks.chars(det)[at] == "\n"
        and table.concat(Blocks.chars(det), "", 1, at - 1):sub(-2) == "\n\n",
        "Collapsible section: <details open>, its summary, an empty line inside, </details>")
    local tb, tat = Blocks.menuMarkdown("table")
    check(tb:match("^| Column 1 | Column 2 |\n| %-%-%- | %-%-%- |\n|  |  |$") and table.concat(Blocks.chars(tb), "", 1, tat - 1):sub(-3) == "\n| ",
        "Table: two columns, the cursor in its first cell")

    -- into the formatted page: a heading or list turns the line into it
    local doc = Blocks.parse("Shopping\n\nmilk")
    local b, i = Blocks.addFromMenu(doc, doc.blocks[1], "h2")
    check(b == doc.blocks[1] and b.kind == "heading" and b.level == 2 and i == 9, "Heading 2 on a line: the line becomes it, the cursor at its end")
    Blocks.addFromMenu(doc, doc.blocks[2], "task")
    eq(Blocks.write(doc), "## Shopping\n\n- [ ] milk", "…and a To-do list: written as Memos writes it")
    -- the others: on an empty line, in its place; else after the line
    doc = Blocks.parse("Notes\n\n&nbsp;\n\nend")
    b, i = Blocks.addFromMenu(doc, doc.blocks[2], "callout", "WARNING")
    check(b.kind == "raw" and T(b) == "> [!WARNING]\n> " and i == 16 and #doc.blocks == 3, "Callout on an empty line: in its place, the cursor on its words' line")
    Blocks.insert(b, i, "Mind the step")
    eq(Blocks.write(doc), "Notes\n\n> [!WARNING]\n> Mind the step\n\nend", "…written as Memos writes a callout")
    eq(Blocks.parse(Blocks.write(doc)).blocks[2].kind, "raw", "…and read back as the same block")
    doc = Blocks.parse("Notes")
    b, i = Blocks.addFromMenu(doc, doc.blocks[1], "code")
    check(doc.blocks[2] == b and i == 5, "Code block after a line with words: on a new line after it")
    Blocks.insert(b, i, "print(1)")
    eq(Blocks.write(doc), "Notes\n\n```\nprint(1)\n```", "…the code inside the fence")
    doc = Blocks.parse("Notes")
    b = Blocks.addFromMenu(doc, doc.blocks[1], "divider")
    check(doc.blocks[2].kind == "raw" and T(doc.blocks[2]) == "---" and b == doc.blocks[3] and b.kind == "paragraph",
        "Divider: ---, the cursor on a new line after it")
    Blocks.insert(b, 1, "after")
    eq(Blocks.write(doc), "Notes\n\n---\n\nafter", "…written with the words after it")
    doc = Blocks.parse("Notes")
    b = Blocks.addFromMenu(doc, doc.blocks[1], "details")
    check(doc.blocks[2].section == "start" and doc.blocks[2].folded == false and b == doc.blocks[3] and doc.blocks[4].section == "end",
        "Collapsible section: its row, a line inside (the cursor), its end")
    Blocks.insert(b, 1, "hidden words")
    local out = Blocks.write(doc)
    eq(out, "Notes\n\n<details open>\n<summary></summary>\n\nhidden words\n\n</details>", "…written as the web editor writes a section")
    local back = Blocks.parse(out)
    check(back.blocks[2].section == "start" and back.blocks[4].section == "end", "…and read back as a section")
    doc = Blocks.parse("Notes")
    b, i = Blocks.addFromMenu(doc, doc.blocks[1], "table")
    Blocks.insert(b, i, "a")
    eq(Blocks.write(doc), "Notes\n\n| Column 1 | Column 2 |\n| --- | --- |\n| a |  |", "Table: typed into its first cell")
    eq(Blocks.parse(Blocks.write(doc)).blocks[2].kind, "raw", "…read back as a table")
end)()

print("== numbering and separators")
;(function()
    local doc = Blocks.parse("1. a\n2. b\n3. c")
    Blocks.remove(doc, doc.blocks[2])
    eq(Blocks.write(doc), "1. a\n2. c", "numbers follow on after a removal")
    doc = Blocks.parse("Para one\n\n\n\nPara two")
    Blocks.setText(doc.blocks[1], "Para 1")
    eq(Blocks.write(doc), "Para 1\n\nPara two", "a changed block: one blank line after it")
    doc = Blocks.parse("keep\n\n\nthis spacing\n")
    eq(Blocks.write(doc), "keep\n\n\nthis spacing\n", "nothing changed: spacing and the last newline kept")
    local ins = Blocks.insertAfter(doc, doc.blocks[1], "paragraph")
    Blocks.setText(ins, "middle")
    eq(Blocks.write(doc), "keep\n\nmiddle\n\nthis spacing\n", "a block put in between")
end)()

print("== lists with more lines; headings with #")
;(function()
    local doc = Blocks.parse("- first line\n  second line\n- next")
    eq(T(doc.blocks[1]), "first line\nsecond line", "an item's second line is part of it")
    Blocks.setText(doc.blocks[1], "first line\nsecond line!")
    eq(Blocks.write(doc), "- first line\n  second line!\n- next", "…written indented under it")
    local h = Blocks.new("heading"); h.level = 2
    Blocks.setText(h, "Notes #")
    eq(Blocks.writeBlock(h), "## Notes \\#", "a heading ending in \" #\" (would close it) escaped")
    Blocks.setText(h, "C# and F#")
    eq(Blocks.writeBlock(h), "## C# and F#", "…but not F#")
end)()

print("== what's typed reads back as typed (generated text)")
;(function()
    local pieces = { "*", "**", "_", "__", "#", "# ", "- ", "1. ", "[", "]", "(", ")", "`", "~~", "&amp;", "&", "<b>", "<",
        "\\", " ", "  ", "a", "word", "x_y", "!", "![", "|", "> ", "+ ", "=", "---", "\194\160", "\u{2014}", "#tag", "1)" }
    local seed = 12345
    local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
    local bad, first
    for _k = 1, 3000 do
        local t = {}
        for _j = 1, rnd(8) do t[#t + 1] = pieces[rnd(#pieces)] end
        local text = table.concat(t)
        for _i, kind in ipairs({ "paragraph", "heading", "bullet" }) do
            local b = Blocks.new(kind)
            Blocks.setText(b, text)
            local md = Blocks.writeBlock(b, 1)
            local back = Blocks.parse(md).blocks[1]
            local got = back and (back.kind == "paragraph" and #back.chars == 0 and "" or T(back)) or ""
            local want = text
            if text:gsub("[ \t\194\160]", "") == "" then want = got end -- (only spaces: an empty block)
            if got ~= want or (back and back.kind ~= kind and want ~= "") then
                bad = (bad or 0) + 1
                first = first or (kind .. ": " .. string.format("%q", text) .. " -> " .. string.format("%q", md) .. " -> " .. string.format("%q", got))
            end
        end
    end
    check(bad == nil, "3000 generated texts, as a paragraph, a heading and a list item: read back as typed"
        .. (first and ("\n         " .. bad .. " differ, e.g. " .. first) or ""))
end)()

print("== marks read back as set (generated)")
;(function()
    local pieces = { "word", "a", "b2", " ", " ", "*", "_", "x_y", "-", ".", ",", "#", "`", "~", "!", "?", "\u{00E9}t\u{00E9}" }
    local seed = 777
    local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
    local bad, first = 0, nil
    for _k = 1, 2000 do
        local t = {}
        for _j = 1, rnd(10) do t[#t + 1] = pieces[rnd(#pieces)] end
        local b = Blocks.new("paragraph")
        Blocks.setText(b, table.concat(t))
        if #b.chars > 0 then
            for _j = 1, rnd(3) do
                local a = rnd(#b.chars)
                local z = math.min(#b.chars, a + rnd(6) - 1)
                Blocks.toggleMark(b, ({ "b", "i", "s" })[rnd(3)], a, z)
            end
            local md = Blocks.writeBlock(b)
            local back = Blocks.parse(md).blocks[1]
            local ok = back and T(back) == T(b)
            if ok then
                for k, ch in ipairs(b.chars) do
                    if ch ~= " " then
                        local m1, m2 = b.marks[k] or {}, back.marks[k] or {}
                        if (m1.b or false) ~= (m2.b or false) or (m1.i or false) ~= (m2.i or false) or (m1.s or false) ~= (m2.s or false) then ok = false end
                    end
                end
            end
            if not ok then
                bad = bad + 1
                if not first then
                    local desc = {}
                    for k, ch in ipairs(b.chars) do local m = b.marks[k] or {}; desc[#desc + 1] = ch .. ((m.b and "B" or "") .. (m.i and "I" or "") .. (m.s and "S" or "")) end
                    first = table.concat(desc, "|") .. " -> " .. string.format("%q", md)
                end
            end
        end
    end
    check(bad == 0, "2000 texts with bold / italic / strikethrough on random stretches: read back with the same marks"
        .. (first and ("\n         " .. bad .. " differ, e.g. " .. first) or ""))
end)()

-- a <details> section (Memos' web editor, the fork's "Text from …" blocks): its start and end blocks of their own
;(function()
    local md = "## Tuesday\n\n<details>\n<summary>Text from a &amp; b.png</summary>\n\n```text\nWork took most\n```\n\n</details>\n\nafter"
    local doc = Blocks.parse(md)
    local k = {}
    for _i, b in ipairs(doc.blocks) do k[#k + 1] = b.kind .. (b.section and (":" .. b.section) or "") end
    check(table.concat(k, ",") == "heading,raw:start,raw,raw:end,paragraph", "a <details> section: its start, what's in it, its end (" .. table.concat(k, ",") .. ")")
    check(doc.blocks[2].folded == true and Blocks.write(doc) == md, "…folded as the web shows it; written back exactly as it was")
    local s1 = Blocks.sectionStart(table.concat(doc.blocks[2].chars))
    local s2 = Blocks.sectionStart("<details open><summary>Inner &lt;1&gt;</summary>")
    check(s1 and s1.title == "Text from a & b.png" and not s1.open and s2 and s2.open and s2.title == "Inner <1>"
        and Blocks.sectionStart("<details>").title == "" and Blocks.sectionStart("<detailsx>") == nil
        and Blocks.sectionStart("<details>\nwords") == nil,
        "a section's start: open or not, its title as plain text")
    check(Blocks.sectionMarkdown("A & <b>", false) == "<details>\n<summary>A &amp; &lt;b&gt;</summary>"
        and Blocks.sectionMarkdown("x", true) == "<details open>\n<summary>x</summary>",
        "a section's start written as the web editor writes it (the title escaped)")
    local tight = Blocks.parse("<details open><summary>T</summary>\nline one\n</details>\nmore")
    local k2 = {}
    for _i, b in ipairs(tight.blocks) do k2[#k2 + 1] = b.kind .. (b.section and (":" .. b.section) or "") end
    check(table.concat(k2, ",") == "raw:start,paragraph,raw:end,paragraph" and tight.blocks[1].folded == false
        and Blocks.write(tight) == "<details open><summary>T</summary>\nline one\n</details>\nmore",
        "…written without blank lines: still its own blocks, open, kept as written (" .. table.concat(k2, ",") .. ")")
end)()

print(string.format("blocks: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
