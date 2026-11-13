--[[--
A note as blocks, for the block editor (touch Kindles): Memos Markdown read
into paragraphs, headings and list items with their words and inline marks
(bold, italic, strikethrough, code, links), and written back the way Memos'
rich editor (@usememos/editor 26.11) writes Markdown:

- `**bold**`, `*italic*`, `~~strike~~`, code spans, `[text](url)`;
- ATX headings, `-` bullets, numbered items, `- [ ]` / `- [x]` tasks;
- one blank line between blocks, list items on consecutive lines;
- an empty paragraph as `&nbsp;`;
- text escaped only where it would read as Markdown (a `*`, a line that
  would start a list or a heading, …), `#` at a line's start as `&#35;`
  (Memos reads `\#` as a tag's).

Like Memos' editor, blocks that weren't changed are written back exactly as
they were (`src`), and so is everything this editor doesn't take apart:
code, quotes, tables, dividers, HTML, pictures (`raw` blocks, edited as their
Markdown). No UI: `blocks_test.lua`.

A block: { kind = "paragraph" | "heading" | "bullet" | "ordered" | "task" |
"image" | "raw", level (heading 1–6), done (task), num (ordered), indent,
marker, chars = { utf-8 characters }, marks = { per character: a mark set
or false }, src (its Markdown as read), sep (what came before it), dirty }.
A mark set: { b, i, s, c (code), link = url } (shared, never changed).
]]

local Blocks = {}

local NBSP = "\194\160"

-- ------------------------------------------------------------- characters

--- The UTF-8 characters of `s`, in a list.
function Blocks.chars(s)
    local out = {}
    for ch in tostring(s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return out
end

local NAMED = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = NBSP, ["#"] = "#" }

local function utf8char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
    end
    return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
        0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

--- An HTML character reference at the start of `s` (`&amp;`, `&#124;`,
--- `&#x7C;`): its character and length, or nil.
local function entityAt(s)
    local num = s:match("^&#(%d+);")
    if num then
        local cp = tonumber(num)
        if cp and cp > 0 and cp < 0x110000 then return utf8char(cp), #num + 3 end
    end
    local hex = s:match("^&#[xX](%x+);")
    if hex then
        local cp = tonumber(hex, 16)
        if cp and cp > 0 and cp < 0x110000 then return utf8char(cp), #hex + 4 end
    end
    local name = s:match("^&(%a%w*);")
    if name and NAMED[name] then return NAMED[name], #name + 2 end
end

-- ------------------------------------------------------------ inline: read

local MARKSETS = {}
--- The shared mark set for these marks (false: none).
local function markset(b, i, s, c, link)
    if not (b or i or s or c or link) then return false end
    local key = (b and "b" or "") .. (i and "i" or "") .. (s and "s" or "") .. (c and "c" or "") .. "|" .. (link or "")
    local m = MARKSETS[key]
    if not m then
        m = { b = b or nil, i = i or nil, s = s or nil, c = c or nil, link = link }
        MARKSETS[key] = m
    end
    return m
end
Blocks.markset = markset

local PUNCT = "%p" -- (ASCII punctuation: what a backslash can escape)
local opensOrCloses

--- A closing delimiter `d` later in `s` from `from` (not right after a space): its position.
local function closer(s, d, from)
    local pos = from
    while true do
        local a = s:find(d, pos, true)
        if not a then return nil end
        local prev = s:sub(a - 1, a - 1)
        -- (escaped: after an odd number of backslashes; "\\\\**" closes)
        local bs, j = 0, a - 1
        while j >= from and s:sub(j, j) == "\\" do bs = bs + 1; j = j - 1 end
        if a > from and prev ~= " " and prev ~= "\n" and bs % 2 == 0 then return a end
        pos = a + 1
    end
end

--- A delimiter of `len` at `pos` can open (the next character isn't a
--- space) or, `closing`, close (the one before isn't).
function opensOrCloses(s, pos, len, closing)
    if closing then
        local prev = s:sub(pos - 1, pos - 1)
        return pos > 1 and prev ~= " " and prev ~= "\t" and prev ~= "\n"
    end
    local nxt = s:sub(pos + len, pos + len)
    return nxt ~= "" and nxt ~= " " and nxt ~= "\t" and nxt ~= "\n"
end

--- Markdown inline text `s` as characters and their marks.
function Blocks.readInline(s)
    s = tostring(s or "")
    local chars, marks = {}, {}
    local st = { b = false, i = false, s = false, link = nil }
    local stack_link = {}
    local function put(ch, code)
        chars[#chars + 1] = ch
        marks[#marks + 1] = markset(st.b, st.i, st.s, code, st.link)
    end
    local pos, n = 1, #s
    while pos <= n do
        local c = s:sub(pos, pos)
        local two = s:sub(pos, pos + 1)
        if c == "\\" and pos < n and s:sub(pos + 1, pos + 1) == "\n" then
            put("\n"); pos = pos + 2 -- (a hard line break)
        elseif c == "\\" and pos < n and s:sub(pos + 1, pos + 1):match(PUNCT) then
            put(s:sub(pos + 1, pos + 1)); pos = pos + 2
        elseif c == "&" and entityAt(s:sub(pos, pos + 40)) then
            local ch, len = entityAt(s:sub(pos, pos + 40))
            put(ch); pos = pos + len
        elseif c == "`" then
            local run = s:match("^`+", pos)
            local close = s:find(run, pos + #run, true)
            while close and s:sub(close + #run, close + #run) == "`" do close = s:find(run, close + #run + 1, true) end
            if close then
                local code = s:sub(pos + #run, close - 1)
                if #code >= 2 and code:sub(1, 1) == " " and code:sub(-1) == " " and code:match("[^ ]") then code = code:sub(2, -2) end
                for _i, ch in ipairs(Blocks.chars(code)) do put(ch, true) end
                pos = close + #run
            else
                for _i = 1, #run do put("`") end
                pos = pos + #run
            end
        elseif c == "[" then
            -- [text](url): the text with the link's mark
            local depth, j = 1, pos + 1
            while j <= n and depth > 0 do
                local cj = s:sub(j, j)
                if cj == "\\" then j = j + 1
                elseif cj == "[" then depth = depth + 1
                elseif cj == "]" then depth = depth - 1 end
                j = j + 1
            end
            local url = depth == 0 and s:match("^%(([^%s%)]*)[^%)]*%)", j)
            if url then
                stack_link[#stack_link + 1] = st.link
                st.link = url
                local inner_c, inner_m = Blocks.readInline(s:sub(pos + 1, j - 2))
                for k, ch in ipairs(inner_c) do
                    local im = inner_m[k] or {}
                    chars[#chars + 1] = ch
                    marks[#marks + 1] = markset(st.b or im.b, st.i or im.i, st.s or im.s, im.c, url)
                end
                st.link = table.remove(stack_link)
                pos = j + #s:match("^%([^%)]*%)", j)
            else
                put("["); pos = pos + 1
            end
        elseif c == "<" and s:match("^<(%a[%w+.-]*:[^%s<>]*)>", pos) then
            local url = s:match("^<(%a[%w+.-]*:[^%s<>]*)>", pos)
            local was = st.link
            st.link = url
            for _i, ch in ipairs(Blocks.chars(url)) do put(ch) end
            st.link = was
            pos = pos + #url + 2
        elseif two == "~~" and (st.s and opensOrCloses(s, pos, 2, true) or not st.s and opensOrCloses(s, pos, 2, false) and closer(s, "~~", pos + 2)) then
            st.s = not st.s; pos = pos + 2
        elseif (two == "**" or two == "__") and (st.b and opensOrCloses(s, pos, 2, true)
                or not st.b and opensOrCloses(s, pos, 2, false) and closer(s, two, pos + 2)) then
            st.b = not st.b; pos = pos + 2
        elseif (c == "*" or c == "_") and not (c == "_"
                and s:sub(pos - 1, pos - 1):match("[%w\128-\255]") and s:sub(pos + 1, pos + 1):match("[%w\128-\255]"))
                and (st.i and opensOrCloses(s, pos, 1, true) or not st.i and opensOrCloses(s, pos, 1, false) and closer(s, c, pos + 1)) then
            st.i = not st.i; pos = pos + 1
        else
            local ch = s:match("^[%z\1-\127\194-\244][\128-\191]*", pos)
            put(ch); pos = pos + #ch
        end
    end
    return chars, marks
end

-- ----------------------------------------------------------- inline: write

local ALNUM = "[%w\128-\255]"

--- Index of the character at a line's start that would start a block, or nil.
local function blockSyntaxAt(line)
    if line:match("^#+[ \t]") or line:match("^#+$") then
        local hashes = line:match("^#+")
        if #hashes <= 6 then return 1 end
    end
    if line:sub(1, 1) == ">" then return 1 end
    if line:match("^[-+][ \t]") or line:match("^[-+]$") or line:match("^%-+[ \t]*$") then return 1 end
    if line:match("^=+[ \t]*$") then return 1 end
    local num = line:match("^(%d+)[.)][ \t]") or line:match("^(%d+)[.)]$")
    if num and #num <= 9 then return #num + 1 end
end

--- Plain text `line` escaped so it reads back as itself (Memos' escapeLine:
--- `*`, `` ` ``, `~`, `[`, `]` always; `_` unless inside a word; `<` before a
--- tag; `&` before a reference; `!` before `[`; what would start a block at
--- the start of a line; spaces at the ends as references).
local function escapeLine(chars, line_start, line_end, before, after, encode_first, encode_last)
    local out = {}
    local bs_at
    if line_start then
        -- (what's written after the run counts: "#" then **bold** isn't a heading)
        local first = table.concat(chars, "", 1, math.min(#chars, 12))
        if #chars < 12 and after and after ~= "\n" then first = first .. after end
        bs_at = blockSyntaxAt(first)
    end
    for k, ch in ipairs(chars) do
        local prev = chars[k - 1] or before
        local next = chars[k + 1] or after
        if (k == 1 and (line_start or encode_first) and (ch == " " or ch == "\t"))
                or (k == #chars and (line_end or encode_last) and (ch == " " or ch == "\t")) then
            out[#out + 1] = "&#" .. string.byte(ch) .. ";"
        elseif k == bs_at then
            out[#out + 1] = ch == "#" and "&#35;" or ("\\" .. ch)
        elseif ch == "\\" then
            out[#out + 1] = "\\\\" -- (always: what follows may be written as a reference or an escape)
        elseif ch == "`" or ch == "*" or ch == "~" or ch == "[" or ch == "]" then
            out[#out + 1] = "\\" .. ch
        elseif ch == "_" then
            local intraword = prev and next and prev:match(ALNUM) and next:match(ALNUM)
            out[#out + 1] = intraword and ch or "\\_"
        elseif ch == "<" then
            out[#out + 1] = (next == nil or next:match("^[A-Za-z/!?]$")) and "\\<" or ch
        elseif ch == "&" then
            local rest = table.concat(chars, "", k, math.min(#chars, k + 40))
            out[#out + 1] = entityAt(rest) and "\\&" or ch
        elseif ch == "!" then
            out[#out + 1] = next == "[" and "\\!" or ch
        elseif ch == NBSP then
            out[#out + 1] = "&nbsp;"
        else
            out[#out + 1] = ch
        end
    end
    return table.concat(out)
end

local MARK_ORDER = { "b", "i", "s" }
local OPEN = { b = "**", i = "*", s = "~~" }

--- Characters and marks as Memos Markdown (inline: no block marker).
function Blocks.writeInline(chars, marks)
    marks = marks or {}
    -- a space takes only the emphasis both its neighbours have (spaces at a
    -- marked stretch's ends go outside its ** … **, as Markdown wants)
    local eff = {}
    local function nonspace(k, step)
        k = k + step
        while chars[k] and (chars[k] == " " or chars[k] == "\n") do k = k + step end
        return chars[k] and (marks[k] or false)
    end
    for k, ch in ipairs(chars) do
        local m = marks[k] or false
        if (ch == " " or ch == "\n") and m and not m.c then
            local p, q = nonspace(k, -1) or false, nonspace(k, 1) or false
            local function both(key) return m[key] and p and p[key] and q and q[key] end
            m = markset(both("b"), both("i"), both("s"), false, m.link)
        end
        eff[k] = m
    end
    local runs = {}
    for k, ch in ipairs(chars) do
        local m = eff[k]
        local last = runs[#runs]
        if last and last.m == m then last.chars[#last.chars + 1] = ch
        else runs[#runs + 1] = { m = m, chars = { ch } } end
    end
    local split = runs
    local out, open = {}, {} -- open: the emphasis marks open now, in order
    local link_open = nil
    local function closeTo(keep)
        while #open > 0 and not keep[open[#open]] do out[#out + 1] = OPEN[table.remove(open)] end
    end
    local at_line_start = true
    for idx, r in ipairs(split) do
        local m = r.m or {}
        -- a link: closes what's open, written whole as [text](url)
        if link_open and m.link ~= link_open then
            closeTo({})
            out[#out + 1] = "](" .. link_open .. ")"
            link_open = nil
        end
        if m.link and not link_open then
            closeTo({})
            out[#out + 1] = "["
            link_open = m.link
        end
        -- emphasis: close what this run doesn't have (and anything opened after it), open what it adds,
        -- the one that lasts longest first (outermost), so the one that ends first closes first
        local want = {}
        for _j, k in ipairs(MARK_ORDER) do if m[k] then want[k] = true end end
        local keep, ok = {}, true
        for _j, k in ipairs(open) do
            if ok and want[k] then keep[k] = true else ok = false end
        end
        closeTo(keep)
        local adds = {}
        for _j, k in ipairs(MARK_ORDER) do if want[k] and not keep[k] then adds[#adds + 1] = k end end
        local function lasts(k)
            local n = 0
            for j = idx, #split do
                local mj = split[j].m
                if not (mj and mj[k]) and not (j > idx and split[j].chars[1] == " " and #split[j].chars == 1) then break end
                n = n + #split[j].chars
            end
            return n
        end
        table.sort(adds, function(x, y)
            local lx, ly = lasts(x), lasts(y)
            if lx ~= ly then return lx > ly end
            return x < y
        end)
        for _j, k in ipairs(adds) do open[#open + 1] = k; out[#out + 1] = OPEN[k] end
        local opened_now = #adds > 0
        if m.c then
            local text = table.concat(r.chars)
            local longest = 0
            for run in text:gmatch("`+") do longest = math.max(longest, #run) end
            local fence = string.rep("`", longest + 1)
            local pad = (text:sub(1, 1) == "`" or text:sub(-1) == "`") and " " or ""
            out[#out + 1] = fence .. pad .. text .. pad .. fence
            at_line_start = false
        else
            -- line by line: a line break inside a paragraph is a plain line ending
            local line = {}
            -- what's written next to this run: a marker when the marks change there
            local nxt, prv = split[idx + 1], split[idx - 1]
            local after_run = nxt and ((nxt.m ~= r.m) and "*" or nxt.chars[1])
            local before_run = prv and ((prv.m ~= r.m) and "*" or prv.chars[#prv.chars])
            local first_line = true
            -- a space right after an opening marker or before a closing one: a reference (a marker next to a space isn't one)
            -- (markers written right before this run, or closing right after it)
            local marker_before = opened_now
            local marker_after = false
            for _j, k in ipairs(open) do
                if not (nxt and nxt.m and nxt.m[k]) then marker_after = true end
            end
            local function flush(line_end, after)
                out[#out + 1] = escapeLine(line, at_line_start, line_end, first_line and before_run or nil, after or after_run,
                    first_line and marker_before, not after and marker_after)
                line = {}
                first_line = false
            end
            for _k, ch in ipairs(r.chars) do
                if ch == "\n" then
                    flush(true, "\n")
                    out[#out + 1] = "\n"
                    at_line_start = true
                else
                    line[#line + 1] = ch
                end
            end
            if #line > 0 then
                flush(idx == #split)
                at_line_start = false
            end
        end
    end
    closeTo({})
    if link_open then out[#out + 1] = "](" .. link_open .. ")" end
    return table.concat(out)
end

-- ----------------------------------------------------------------- blocks

local function textOf(b) return table.concat(b.chars) end
Blocks.textOf = textOf

--- A block's words as plain text (no marks), for its edit box.
function Blocks.plain(b) return textOf(b) end

local function newBlock(kind, inline, extra)
    local b = extra or {}
    b.kind = kind
    if kind == "raw" or kind == "image" then
        b.chars, b.marks = Blocks.chars(inline), {}
    else
        b.chars, b.marks = Blocks.readInline(inline)
    end
    return b
end

local function isBlank(line) return line:match("^[ \t]*$") ~= nil end

local function emptyPara(text)
    local t = text:gsub("^%s+", ""):gsub("%s+$", "")
    return t == "&nbsp;" or t == "&#160;" or t == "&#xA0;" or t == NBSP
end

local LIST_TASK = "^([ \t]*)([-*+])[ \t]+%[([ xX])%][ \t]+(.*)$"
local LIST_TASK_EMPTY = "^([ \t]*)([-*+])[ \t]+%[([ xX])%][ \t]*$"
local LIST_BULLET = "^([ \t]*)([-*+])[ \t]+(.*)$"
local LIST_BULLET_EMPTY = "^([ \t]*)([-*+])$"
local LIST_ORDERED = "^([ \t]*)(%d+)([.)])[ \t]+(.*)$"
local LIST_ORDERED_EMPTY = "^([ \t]*)(%d+)([.)])$"

local function listItem(line)
    local ind, mk, x, rest = line:match(LIST_TASK)
    if not ind then ind, mk, x = line:match(LIST_TASK_EMPTY); rest = ind and "" end
    if ind then return "task", ind, mk, rest, x ~= " " end
    local oind, num, delim, orest = line:match(LIST_ORDERED)
    if not oind then oind, num, delim = line:match(LIST_ORDERED_EMPTY); orest = oind and "" end
    if oind and #num <= 9 then return "ordered", oind, delim, orest, tonumber(num) end
    ind, mk, rest = line:match(LIST_BULLET)
    if not ind then ind, mk = line:match(LIST_BULLET_EMPTY); rest = ind and "" end
    if ind and not line:match("^[ \t]*[-*+][ \t]*[-*+][ \t]*[-*+][ \t%-*+]*$") then return "bullet", ind, mk, rest end
end

local function isFence(line) return line:match("^[ \t]*```") or line:match("^[ \t]*~~~") end
local function isHeading(line) return line:match("^#+[ \t]") and #line:match("^#+") <= 6 or line:match("^#+$") and #line <= 6 end
local function isDivider(line)
    return line:match("^[ \t]*%-[ \t]*%-[ \t]*%-[ \t%-]*$") or line:match("^[ \t]*%*[ \t]*%*[ \t]*%*[ \t%*]*$")
        or line:match("^[ \t]*_[ \t]*_[ \t]*_[ \t_]*$")
end
local function isHtml(line) return line:match("^[ \t]*</?%a") ~= nil end
local function isImageLine(line) return line:match("^[ \t]*!%[[^%]]*%]%([^%)]*%)[ \t]*$") ~= nil end

--- Starts a block other than a paragraph's next line.
local function startsBlock(line)
    return isFence(line) or isHeading(line) or line:match("^[ \t]*>") or listItem(line) or isDivider(line)
        or isHtml(line) or isImageLine(line)
end

--- Memos Markdown `content` as a document: { blocks, original, lead, tail }.
function Blocks.parse(content)
    content = tostring(content or "")
    local lines = {}
    for line in (content .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = (line:gsub("\r$", "")) end
    if content:sub(-1) == "\n" then table.remove(lines) end
    local doc = { blocks = {}, original = content }
    local i, n = 1, #lines
    local blanks = 0
    local function add(b, from, to)
        b.src = table.concat(lines, "\n", from, to)
        b.sep = #doc.blocks == 0 and "" or ("\n" .. string.rep("\n", blanks))
        if #doc.blocks == 0 then doc.lead = string.rep("\n", blanks) end
        blanks = 0
        doc.blocks[#doc.blocks + 1] = b
    end
    while i <= n do
        local line = lines[i]
        if isBlank(line) then
            blanks = blanks + 1
            i = i + 1
        elseif isFence(line) then
            local fence = line:match("^[ \t]*(```+)") or line:match("^[ \t]*(~~~+)")
            local j = i + 1
            while j <= n and not lines[j]:match("^[ \t]*" .. fence:gsub("%p", "%%%0")) do j = j + 1 end
            j = math.min(j, n)
            add(newBlock("raw", table.concat(lines, "\n", i, j)), i, j)
            i = j + 1
        elseif isHeading(line) then
            local hashes, rest = line:match("^(#+)[ \t]*(.-)[ \t]*$")
            rest = rest:gsub("[ \t]+#+$", ""):gsub("^#+$", "")
            add(newBlock("heading", rest, { level = #hashes }), i, i)
            i = i + 1
        elseif line:match("^[ \t]*>") then
            local j = i
            while j + 1 <= n and lines[j + 1]:match("^[ \t]*>") do j = j + 1 end
            add(newBlock("raw", table.concat(lines, "\n", i, j)), i, j)
            i = j + 1
        elseif line:find("|", 1, true) and lines[i + 1] and lines[i + 1]:match("^[ \t|:%-]+$") and lines[i + 1]:find("-", 1, true) then
            local j = i + 1
            while j + 1 <= n and lines[j + 1]:find("|", 1, true) and not isBlank(lines[j + 1]) do j = j + 1 end
            add(newBlock("raw", table.concat(lines, "\n", i, j)), i, j)
            i = j + 1
        elseif isDivider(line) and not listItem(line) then
            add(newBlock("raw", line), i, i)
            i = i + 1
        elseif isImageLine(line) then
            add(newBlock("image", line), i, i)
            i = i + 1
        elseif isHtml(line) then
            local j = i
            while j + 1 <= n and not isBlank(lines[j + 1]) do j = j + 1 end
            add(newBlock("raw", table.concat(lines, "\n", i, j)), i, j)
            i = j + 1
        elseif listItem(line) then
            local kind, ind, mk, rest, x = listItem(line)
            -- continuation lines: indented further than the marker, not a new item
            local j = i
            local text = { rest }
            local cont_ind = #ind + 2
            while j + 1 <= n and not isBlank(lines[j + 1]) and not listItem(lines[j + 1])
                    and #(lines[j + 1]:match("^[ \t]*")) >= cont_ind and not startsBlock(lines[j + 1]:sub(cont_ind + 1)) do
                j = j + 1
                text[#text + 1] = lines[j]:sub(cont_ind + 1)
            end
            local extra = { indent = ind, marker = mk }
            if kind == "task" then extra.done = x elseif kind == "ordered" then extra.num = x end
            add(newBlock(kind, table.concat(text, "\n"), extra), i, j)
            i = j + 1
        else
            local j = i
            while j + 1 <= n and not isBlank(lines[j + 1]) and not startsBlock(lines[j + 1]) do j = j + 1 end
            local text = table.concat(lines, "\n", i, j)
            local setext = lines[j + 1] and (lines[j + 1]:match("^=+[ \t]*$") or lines[j + 1]:match("^%-+[ \t]*$"))
            if setext then
                add(newBlock("raw", text .. "\n" .. lines[j + 1]), i, j + 1)
                j = j + 1
            elseif emptyPara(text) then
                add(newBlock("paragraph", ""), i, j)
            elseif text:find("![", 1, true) or text:find("\n[ \t]*%[[^%]]+%]:") then
                add(newBlock("raw", text), i, j) -- (pictures in the text, link definitions: as written)
            else
                add(newBlock("paragraph", text), i, j)
            end
            i = j + 1
        end
    end
    doc.tail = string.rep("\n", blanks)
    return doc
end

-- ------------------------------------------------------------ writing out

local LIST = { bullet = true, ordered = true, task = true }

--- Two list items of the same list (written on consecutive lines).
local function sameList(a, b)
    return a and b and LIST[a.kind] and a.kind == b.kind and (a.indent or "") == (b.indent or "")
end

--- Block `b` as Markdown (`num`: the number an ordered item gets).
function Blocks.writeBlock(b, num)
    if not b.dirty and b.src and not (b.kind == "ordered" and num and num ~= b.num) then return b.src end
    if b.kind == "raw" or b.kind == "image" then return textOf(b) end
    local inline = Blocks.writeInline(b.chars, b.marks)
    if b.kind == "paragraph" then return inline == "" and "&nbsp;" or inline end
    if b.kind == "heading" then
        inline = inline:gsub("([ \t])(#+)$", "%1\\%2"):gsub("^(#+)$", "\\%1")
        return string.rep("#", b.level or 1) .. (inline ~= "" and (" " .. inline) or "")
    end
    local ind = b.indent or ""
    local marker
    if b.kind == "task" then marker = (b.marker or "-") .. " [" .. (b.done and "x" or " ") .. "]"
    elseif b.kind == "ordered" then marker = tostring(num or b.num or 1) .. ((b.marker == ")") and ")" or ".")
    else marker = b.marker or "-" end
    if inline == "" then return ind .. marker end
    -- lines after the first: indented to the item's text
    local pad = ind .. string.rep(" ", #marker + 1)
    inline = inline:gsub("\n", "\n" .. pad)
    return ind .. marker .. " " .. inline
end

--- The document as Memos Markdown. Unchanged: exactly as it was read.
function Blocks.write(doc)
    local any = doc.changed
    for _i, b in ipairs(doc.blocks) do if b.dirty or not b.src then any = true end end
    if not any then return doc.original end
    -- empty paragraphs at the end aren't written (as Memos' editor)
    local last = #doc.blocks
    while last > 0 and doc.blocks[last].kind == "paragraph" and #doc.blocks[last].chars == 0 do last = last - 1 end
    local out = { doc.lead or "" }
    local prev, prev_num
    for k = 1, last do
        local b = doc.blocks[k]
        local num
        if b.kind == "ordered" then
            if prev and prev.kind == "ordered" and (prev.indent or "") == (b.indent or "") then num = (prev_num or 1) + 1
            else num = b.num or 1 end
        end
        if k > 1 then
            local keep = b.sep and not b.dirty and not prev.dirty and b.src and prev.src and not b.moved
            if keep then out[#out + 1] = b.sep
            elseif sameList(prev, b) then out[#out + 1] = "\n"
            else out[#out + 1] = "\n\n" end
        end
        out[#out + 1] = Blocks.writeBlock(b, num)
        prev, prev_num = b, num
    end
    local text = table.concat(out)
    if doc.original:sub(-1) == "\n" and text ~= "" then text = text .. "\n" end
    return text
end

-- ------------------------------------------------------------------ editing

--- Sets block `b`'s words to `text` (from its edit box), keeping the marks
--- of the characters that stayed (what was typed takes the marks of the
--- character before it).
function Blocks.setText(b, text)
    local new = Blocks.chars(text)
    local old, om = b.chars, b.marks or {}
    if table.concat(new) == table.concat(old) then return false end
    if b.kind == "raw" or b.kind == "image" then
        b.chars, b.marks, b.dirty = new, {}, true
        return true
    end
    local pre = 0
    while pre < #old and pre < #new and old[pre + 1] == new[pre + 1] do pre = pre + 1 end
    local suf = 0
    while suf < #old - pre and suf < #new - pre and old[#old - suf] == new[#new - suf] do suf = suf + 1 end
    local marks = {}
    for k = 1, pre do marks[k] = om[k] or false end
    -- typed text: the emphasis of the character before it (at the start: of
    -- the first); a link or code only inside one (both sides have it)
    local before, after = om[pre] or false, om[#old - suf + 1] or false
    local like = before or (pre == 0 and after) or false
    local typed = false
    if like then
        local inside = before and after and before.link and before.link == after.link
        local code = before and after and before.c and after.c
        typed = markset(like.b, like.i, like.s, code, inside and before.link or nil)
    end
    for k = pre + 1, #new - suf do marks[k] = typed end
    for k = 1, suf do marks[#new - suf + k] = om[#old - suf + k] or false end
    b.chars, b.marks, b.dirty = new, marks, true
    return true
end

--- The word around character position `pos` (1-based, the cursor before
--- it): first and last index, or the whole block when there's no word.
function Blocks.wordAt(b, pos)
    local chars = b.chars
    if #chars == 0 then return nil end
    local function word(ch) return ch and not ch:match("^[%s%p]$") end
    local a = math.max(1, math.min(pos or 1, #chars))
    if not word(chars[a]) and word(chars[a - 1]) then a = a - 1 end
    if not word(chars[a]) then return 1, #chars end
    local z = a
    while a > 1 and word(chars[a - 1]) do a = a - 1 end
    while z < #chars and word(chars[z + 1]) do z = z + 1 end
    return a, z
end

--- Turns mark `key` ("b", "i", "s") on or off for characters a…z: off when
--- they all have it, on otherwise.
function Blocks.toggleMark(b, key, a, z)
    if not a or b.kind == "raw" or b.kind == "image" then return false end
    local all = true
    for k = a, z do local m = b.marks[k]; if not (m and m[key]) then all = false end end
    for k = a, z do
        local m = b.marks[k] or {}
        local f = { b = m.b, i = m.i, s = m.s }
        f[key] = not all or nil
        b.marks[k] = markset(f.b, f.i, f.s, m.c, m.link)
    end
    b.dirty = true
    return true
end

--- The marks text typed at `pos` in `b` takes: the emphasis of the character
--- before it (at the start: of the first), a link or code only inside one.
local function typedMarks(b, pos)
    local om = b.marks
    local before, after = om[pos - 1] or false, om[pos] or false
    local like = before or (pos == 1 and after) or false
    if not like then return false end
    local inside = before and after and before.link and before.link == after.link
    local code = before and after and before.c and after.c
    return markset(like.b, like.i, like.s, code, inside and before.link or nil)
end
Blocks.typedMarks = typedMarks

--- Inserts `text` (no line breaks, except in a block kept as Markdown) into
--- `b` at character `pos`, with `marks` (nil: as typed there). Returns the
--- position after it.
function Blocks.insert(b, pos, text, marks)
    local add = Blocks.chars(text)
    pos = math.max(1, math.min(pos, #b.chars + 1))
    local m = false
    if b.kind ~= "raw" and b.kind ~= "image" then
        if marks == nil then m = typedMarks(b, pos) else m = marks end
    end
    for k = #add, 1, -1 do
        table.insert(b.chars, pos, add[k])
        table.insert(b.marks, pos, m)
    end
    if #add > 0 then b.dirty = true end
    return pos + #add
end

--- Deletes characters a…z of `b`.
function Blocks.delete(b, a, z)
    a = math.max(1, a)
    z = math.min(z, #b.chars)
    if z < a then return false end
    for k = z, a, -1 do table.remove(b.chars, k); table.remove(b.marks, k) end
    b.dirty = true
    return true
end

local function blockIndex(doc, b)
    for k, x in ipairs(doc.blocks) do if x == b then return k end end
end
Blocks.indexOf = blockIndex

--- Orders two positions ({ b, i }) in `doc`: the first, the second.
function Blocks.order(doc, p, q)
    local kp, kq = blockIndex(doc, p.b), blockIndex(doc, q.b)
    if kp < kq or (kp == kq and p.i <= q.i) then return p, q end
    return q, p
end

--- Deletes from position `p` to `q` (before character q.i), across blocks:
--- what's left of the last block joins the first. Returns the position where
--- they met.
function Blocks.deleteRange(doc, p, q)
    p, q = Blocks.order(doc, p, q)
    if p.b == q.b then
        Blocks.delete(p.b, p.i, q.i - 1)
        return { b = p.b, i = p.i }
    end
    local kp, kq = blockIndex(doc, p.b), blockIndex(doc, q.b)
    Blocks.delete(p.b, p.i, #p.b.chars)
    for k = kq - 1, kp + 1, -1 do table.remove(doc.blocks, k) end
    local last = q.b
    for k = q.i, #last.chars do
        p.b.chars[#p.b.chars + 1] = last.chars[k]
        p.b.marks[#p.b.marks + 1] = last.marks[k] or false
    end
    table.remove(doc.blocks, kp + 1)
    if doc.blocks[kp + 1] then doc.blocks[kp + 1].moved = true end
    p.b.dirty = true
    doc.changed = true
    return { b = p.b, i = p.i }
end

--- The blocks from position `p`'s to `q`'s (in order).
function Blocks.span(doc, p, q)
    p, q = Blocks.order(doc, p, q)
    local out = {}
    for k = blockIndex(doc, p.b), blockIndex(doc, q.b) do out[#out + 1] = doc.blocks[k] end
    return out
end

--- Turns mark `key` on or off from `p` to `q` (across blocks): off when every
--- character there has it, on otherwise. False when there's nothing to mark.
function Blocks.toggleMarkRange(doc, p, q, key)
    p, q = Blocks.order(doc, p, q)
    local parts = {}
    for _i, b in ipairs(Blocks.span(doc, p, q)) do
        if b.kind ~= "raw" and b.kind ~= "image" then
            local a = b == p.b and p.i or 1
            local z = b == q.b and (q.i - 1) or #b.chars
            if z >= a then parts[#parts + 1] = { b, a, z } end
        end
    end
    if #parts == 0 then return false end
    local all = true
    for _i, part in ipairs(parts) do
        for k = part[2], part[3] do local m = part[1].marks[k]; if not (m and m[key]) then all = false end end
    end
    for _i, part in ipairs(parts) do
        local b = part[1]
        for k = part[2], part[3] do
            local m = b.marks[k] or {}
            local f = { b = m.b, i = m.i, s = m.s }
            f[key] = not all or nil
            b.marks[k] = markset(f.b, f.i, f.s, m.c, m.link)
        end
        b.dirty = true
    end
    return true
end

--- A new empty block of `kind` (a list item takes `like`'s marker and indent).
function Blocks.new(kind, like)
    local b = { kind = kind, chars = {}, marks = {}, dirty = true }
    if kind == "heading" then b.level = 2 end
    if like and LIST[like.kind] and LIST[kind] then b.indent, b.marker = like.indent, like.marker end
    if kind == "ordered" and b.marker ~= ")" then b.marker = "." end
    if kind ~= "ordered" and b.marker and not b.marker:match("^[-*+]$") then b.marker = nil end
    return b
end

--- Changes block `b` to `kind` (heading `level`); the same kind again makes it a paragraph.
function Blocks.setKind(b, kind, level)
    if b.kind == "raw" or b.kind == "image" then return false end
    if b.kind == kind and (kind ~= "heading" or (b.level or 1) == level) then
        b.kind = "paragraph"
    else
        if LIST[kind] and not LIST[b.kind] then b.indent = "" end
        if kind == "ordered" then b.marker = "." elseif LIST[kind] then b.marker = "-" end
        b.kind = kind
        b.level = kind == "heading" and (level or 2) or nil
        if kind == "task" then b.done = b.done or false end
    end
    b.dirty = true
    return true
end

--- Splits block `b` (in `doc`) at character position `pos`: the words from
--- there go to a new block after it, of the same kind for a list item
--- (Enter in Memos' editor), a paragraph otherwise. An empty list item
--- becomes a paragraph instead (Enter on an empty item ends the list).
--- Returns the block the cursor goes to.
function Blocks.split(doc, b, pos)
    local idx
    for k, x in ipairs(doc.blocks) do if x == b then idx = k end end
    if not idx then return b end
    if LIST[b.kind] and #b.chars == 0 then
        b.kind, b.indent, b.marker, b.done, b.num = "paragraph", nil, nil, nil, nil
        b.dirty = true
        return b
    end
    pos = math.max(1, math.min(pos or (#b.chars + 1), #b.chars + 1))
    local kind = LIST[b.kind] and b.kind or "paragraph"
    local nb = Blocks.new(kind, b)
    if kind == "task" then nb.done = false end
    for k = pos, #b.chars do
        nb.chars[#nb.chars + 1] = b.chars[k]
        nb.marks[#nb.marks + 1] = b.marks[k] or false
    end
    for k = #b.chars, pos, -1 do table.remove(b.chars, k); table.remove(b.marks, k) end
    b.dirty = true
    table.insert(doc.blocks, idx + 1, nb)
    return nb
end

--- Joins block `b` onto the one before it (Backspace at its start). Returns
--- the block the cursor goes to and the position, or nil when it's the first.
function Blocks.joinPrevious(doc, b)
    local idx
    for k, x in ipairs(doc.blocks) do if x == b then idx = k end end
    if not idx or idx == 1 then
        if idx == 1 and b.kind ~= "paragraph" and b.kind ~= "raw" and b.kind ~= "image" then
            b.kind, b.level, b.indent, b.marker, b.done, b.num = "paragraph", nil, nil, nil, nil, nil
            b.dirty = true
            return b, 1
        end
        return nil
    end
    -- a list item or heading turns into a paragraph first, as in Memos' editor
    if b.kind ~= "paragraph" and b.kind ~= "raw" and b.kind ~= "image" then
        b.kind, b.level, b.indent, b.marker, b.done, b.num = "paragraph", nil, nil, nil, nil, nil
        b.dirty = true
        return b, 1
    end
    local p = doc.blocks[idx - 1]
    if p.kind == "raw" or p.kind == "image" or b.kind == "raw" or b.kind == "image" then
        if #b.chars == 0 then table.remove(doc.blocks, idx); doc.changed = true; return p, #p.chars + 1 end
        return nil
    end
    local at = #p.chars + 1
    for k, ch in ipairs(b.chars) do p.chars[#p.chars + 1] = ch; p.marks[#p.marks + 1] = b.marks[k] or false end
    p.dirty = true
    table.remove(doc.blocks, idx)
    doc.changed = true
    return p, at
end

--- Removes block `b`. Returns the block next to it (or a new empty paragraph).
function Blocks.remove(doc, b)
    for k, x in ipairs(doc.blocks) do
        if x == b then
            table.remove(doc.blocks, k)
            doc.changed = true
            if doc.blocks[k] then doc.blocks[k].moved = true end
            if #doc.blocks == 0 then doc.blocks[1] = Blocks.new("paragraph") end
            return doc.blocks[math.min(k, #doc.blocks)]
        end
    end
end

--- Inserts a new block of `kind` after `b` (at the end when nil); returns it.
function Blocks.insertAfter(doc, b, kind)
    local nb = Blocks.new(kind or "paragraph", b)
    local idx = #doc.blocks
    for k, x in ipairs(doc.blocks) do if x == b then idx = k end end
    table.insert(doc.blocks, idx + 1, nb)
    if doc.blocks[idx + 2] then doc.blocks[idx + 2].moved = true end
    return nb
end

--- Ticks or unticks a task item.
function Blocks.toggleDone(b)
    if b.kind ~= "task" then return false end
    b.done = not b.done
    b.dirty = true
    return true
end

-- --------------------------------------------------------------- showing

local function htmlEscape(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\n", "<br/>"))
end

--- True when the block has marks (bold, italic, …) to show.
function Blocks.hasMarks(b)
    for _i, m in pairs(b.marks or {}) do if m then return true end end
    return false
end

--- A block's words as HTML with its marks (for KOReader's HtmlBoxWidget).
function Blocks.html(b)
    local out = {}
    local cur = false
    local function close(m)
        if not m then return end
        if m.link then out[#out + 1] = "</u>" end
        if m.c then out[#out + 1] = "</code>" end
        if m.s then out[#out + 1] = "</s>" end
        if m.i then out[#out + 1] = "</i>" end
        if m.b then out[#out + 1] = "</b>" end
    end
    local function open(m)
        if not m then return end
        if m.b then out[#out + 1] = "<b>" end
        if m.i then out[#out + 1] = "<i>" end
        if m.s then out[#out + 1] = "<s>" end
        if m.c then out[#out + 1] = "<code>" end
        if m.link then out[#out + 1] = "<u>" end
    end
    for k, ch in ipairs(b.chars) do
        local m = b.marks[k] or false
        if m ~= cur then close(cur); open(m); cur = m end
        out[#out + 1] = htmlEscape(ch)
    end
    close(cur)
    return table.concat(out)
end

--- Memos' `&nbsp;` lines and other leftovers: no block shows them.
function Blocks.isEmptyParagraph(b) return b.kind == "paragraph" and #b.chars == 0 end

return Blocks
