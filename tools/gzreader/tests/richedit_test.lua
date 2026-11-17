-- The note editor's formatted page (gzreader_richedit.lua), on touch Kindles:
-- typing, Enter and Backspace, selections (hold and drag), the toolbar on a
-- selection or the cursor's line or word, ticking, tags, scrolling, the
-- keyboard's input box, and what Save writes. KOReader's widgets stubbed;
-- every character is 10 px wide.
--   luajit richedit_test.lua <gzreader.koplugin>
local PLUGIN = arg[1]
package.path = PLUGIN .. "/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
local function show(s) return (tostring(s):gsub("\n", "\\n")) end

-- ------------------------------------------------------------ stubs
local dirty = 0
local function class()
    local c = {}
    c.__index = c
    function c:extend(o) o = o or {}; setmetatable(o, { __index = self }); o.__index = o; return o end
    function c:new(o) o = o or {}; setmetatable(o, self); if o.init then o:init() end; return o end
    return c
end
local function stub(name, v) package.preload[name] = function() return v end end
stub("ffi/blitbuffer", { COLOR_BLACK = 0, COLOR_WHITE = 1, COLOR_LIGHT_GRAY = 2, COLOR_DARK_GRAY = 3 })
stub("device", { screen = { scaleBySize = function(_s, n) return n end, getHeight = function() return 1000 end,
    getWidth = function() return 600 end } })
local faces = {}
stub("ui/font", { getFace = function(_s, name, size)
    local key = name .. size
    faces[key] = faces[key] or { name = name, size = size,
        ftsize = { getHeightAndAscender = function() return size * 1.2, size end } }
    return faces[key]
end })
stub("ui/geometry", { new = function(_s, o) return o end })
stub("ui/gesturerange", { new = function(_s, o) return o end })
stub("ui/widget/container/inputcontainer", class())
local drawn = {}
stub("ui/rendertext", {
    sizeUtf8Text = function(_s, _x, _w, _face, text) return { x = 10 * #require("gzreader_blocks").chars(text) } end,
    renderUtf8Text = function(_s, _bb, x, y, face, text) drawn[#drawn + 1] = { x = x, y = y, face = face, text = text } end,
})
stub("ui/uimanager", { setDirty = function() dirty = dirty + 1 end, scheduleIn = function() end })
local KB = class()
function KB:init() self.dimen = { h = 400 }; self.visible = false end
function KB:showKeyboard() self.visible = true end
function KB:hideKeyboard() self.visible = false end
function KB:isVisible() return self.visible end
stub("ui/widget/virtualkeyboard", KB)

local Blocks = require("gzreader_blocks")
local RE = require("gzreader_richedit")

local function editor(content, at_start)
    local e = { tag_asked = false }
    function e.pickTag() e.tag_asked = true end
    local doc = Blocks.parse(content)
    local r = RE:new{ width = 300, max_height = 900, doc = doc, editor = e, at_start = at_start, hint = "Write" }
    return r, doc
end
local function text(r) return Blocks.write(r.doc) end
local function kinds(r)
    local out = {}
    for _i, b in ipairs(r.doc.blocks) do out[#out + 1] = b.kind end
    return table.concat(out, ",")
end
local function block(r, k) return r.doc.blocks[k] end
local function at(r, k, i) return { b = block(r, k), i = i } end
local function select(r, p, q) r.anchor = p; r.cur = q; r:update() end
-- a gesture at a widget point
local function ges(x, y, kind) return { pos = { x = x, y = y }, ges = kind } end

-- ------------------------------------------------------------ a new note, typed
do
    local r = editor("", true)
    check(#r.doc.blocks == 1 and text(r) == "" and r.keyboard and r.height == 500, "a new note: one empty line; the room less the keyboard")
    check(r.gz_multiline == true, "the keyboard keeps Enter and ← → for it")
    r:useTool("heading")
    r:addChars("Shopping")
    check(text(r) == "# Shopping", "Head, then typing: '# Shopping' … " .. show(text(r)))
    r:addChars("\n")
    r:useTool("task")
    r:addChars("milk\neggs")
    check(kinds(r) == "heading,task,task" and text(r) == "# Shopping\n\n- [ ] milk\n- [ ] eggs",
        "Check, then Enter: the next item … " .. show(text(r)))
    r:addChars("\n")
    r:addChars("\n")
    check(kinds(r) == "heading,task,task,paragraph", "Enter on an empty item ends the list")
    r:addChars("Thanks")
    r:delChar(); r:delChar()
    check(Blocks.plain(r.cur.b) == "Than" and r.cur.i == 5, "⌫ deletes the character before the cursor")
    r:goToStartOfLine()
    r:delChar()
    check(kinds(r) == "heading,task,task" and Blocks.plain(r.cur.b) == "eggsThan" and r.cur.i == 5,
        "⌫ at a line's start joins it to the line before (the cursor between)")
    check(r.charlist and table.concat(r.charlist) == "Shopping\nmilk\neggsThan" and r.charpos == 19,
        "the keyboard's flat text and cursor (the space bar moves it)")
    r:moveCursorToCharPos(12)
    check(r.cur.b == block(r, 2) and r.cur.i == 3, "…and a flat position back to the line and character")
end

-- ------------------------------------------------------------ a selection and the toolbar
do
    local r = editor("one\n\ntwo\n\nthree", false)
    check(r.cur.b == block(r, 3) and r.cur.i == 6, "an edit: the cursor at the end of the note")
    select(r, at(r, 1, 1), at(r, 3, 3))
    r:useTool("bullet")
    check(text(r) == "- one\n- two\n- three", "List on a selection over three lines: three items … " .. show(text(r)))
    r:useTool("bullet")
    check(text(r) == "one\n\ntwo\n\nthree", "List again: text again")
    select(r, at(r, 1, 2), at(r, 3, 3))
    r:useTool("bold")
    check(text(r) == "o**ne**\n\n**two**\n\n**th**ree", "B on a selection across lines … " .. show(text(r)))
    r:useTool("bold")
    check(text(r) == "one\n\ntwo\n\nthree", "B again: off")
    select(r, at(r, 2, 1), at(r, 2, 4))
    r:addChars("2")
    check(text(r) == "one\n\n2\n\nthree" and r:selection() == nil, "typing replaces the selection")
    select(r, at(r, 1, 3), at(r, 3, 2))
    r:delChar()
    check(text(r) == "onhree" and kinds(r) == "paragraph", "⌫ on a selection over lines: deleted, the ends joined")
    r:useTool("heading"); r:useTool("heading")
    check(text(r) == "## onhree", "Head twice: heading 2")
    r:useTool("heading"); r:useTool("heading")
    check(text(r) == "onhree", "…four times: text again")
    r:useTool("tag")
    check(r.editor.tag_asked, "# Tag: asks which tag")
    r:setCursor({ b = block(r, 1), i = 3 })
    r:insertTag("ideas")
    check(text(r) == "on #ideas hree", "the tag at the cursor, spaces around it … " .. show(text(r)))
end

-- ------------------------------------------------------------ B / I without a selection
do
    local r = editor("make it bold", false)
    r:setCursor({ b = block(r, 1), i = 10 })
    r:useTool("bold")
    check(text(r) == "make it **bold**", "B: the word at the cursor")
    local r2 = editor("plain ", false)
    r2:useTool("italic")
    r2:addChars("slanted")
    check(text(r2) == "plain *slanted*", "I with no word at the cursor: what's typed next … " .. show(text(r2)))
    r2:leftChar()
    r2:addChars("x")
    check(text(r2):match("%*slantexd%*") ~= nil, "typed inside an italic word: italic too")
end

-- ------------------------------------------------------------ touch: tap, hold and drag, tick, swipe
do
    local r = editor("Plan\n\n- [ ] stove\n- [x] water\n\nPack the tent and the maps for the trip", false)
    local ls = r.lines
    check(#ls >= 5 and ls[1].b == block(r, 1), "laid out: a line per short paragraph … " .. #ls)
    local long = {}
    for _i, l in ipairs(ls) do if l.b == block(r, 4) then long[#long + 1] = l end end
    check(#long == 2 and long[1].z == 31 and long[2].a == 32, "a long paragraph wraps after a space (300 px: 30 characters) … "
        .. tostring(long[1] and long[1].z))
    -- tap in "stove": the cursor there
    local stove = ls[2]
    r:onTapEdit(nil, ges(stove.x0 + 27, stove.y + 5))
    check(r.cur.b == block(r, 2) and r.cur.i == 4 and r.keyboard:isVisible(), "tap: the cursor between characters, the keyboard up")
    -- tap the box
    r:onTapEdit(nil, ges(5, stove.y + 5))
    check(block(r, 2).done == true and text(r):match("%- %[x%] stove"), "tap a ☐: ticked")
    -- hold "tent", drag to "maps"
    local l1 = long[1]
    r:onHoldEdit(nil, ges(l1.x0 + 10 * 10 + 5, l1.y + 5))
    check(r:selection() and r.anchor.i == 10 and r.cur.i == 14, "hold: the word ('tent') selected")
    r:onHoldPanEdit(nil, ges(l1.x0 + 10 * 26, l1.y + 5))
    r:onHoldReleaseEdit(nil, ges(l1.x0 + 10 * 26, l1.y + 5))
    local p, q = r:selection()
    check(p and p.i == 10 and q.i == 27, "drag: the selection stretches ('tent and the maps')")
    r:useTool("bold")
    check(text(r):match("Pack the %*%*tent and the maps%*%* for") ~= nil, "…and B makes it bold")
    -- hold on "Plan", drag down into the list
    r:onHoldEdit(nil, ges(5, ls[1].y + 5))
    r:onHoldPanEdit(nil, ges(stove.x0 + 30, ls[3].y + 5))
    r:onHoldReleaseEdit(nil, ges(stove.x0 + 30, ls[3].y + 5))
    p, q = r:selection()
    check(p and p.b == block(r, 1) and q.b == block(r, 3), "drag over lines: the selection spans them")
    r:useTool("ordered")
    check(text(r):match("^1%. Plan\n2%. stove\n3%. water") ~= nil, "Num on it: a numbered list … " .. show(text(r)))
    -- up and down keep the column
    r:setCursor({ b = block(r, 4), i = 33 })
    r:upLine()
    check(r.cur.b == block(r, 4) and r.cur.i == 2, "↑ from the wrapped line: the same column on the line above")
    r:upLine()
    check(r.cur.b == block(r, 3), "↑ again: the item above")
    r:downLine(); r:downLine()
    check(r.cur.b == block(r, 4) and r.cur.i == 33, "↓ ↓: back where it was")
end

-- ------------------------------------------------------------ Memos' notes: kept as they were
do
    local note = "## Weekend\n\nPack the **tent**.\n\n&nbsp;\n\n1. drive\n2. hike\n\n```\nsite 42\n```\n\n#trip"
    local r = editor(note, false)
    check(text(r) == note and not r:isTextEdited(), "opened, nothing changed: written exactly as it was")
    check(#block(r, 3).chars == 0, "the &nbsp; line: an empty line, nothing to see")
    check(r.cur.b == block(r, 7) and r.cur.i == 6, "the cursor after #trip")
    -- typing in code: a line break in it
    r:setCursor({ b = block(r, 6), i = 12 })
    r:addChars("\n")
    check(#r.doc.blocks == 7 and text(r):match("```\nsite 42\n\n```"), "Enter in code: a line break in it, not a new line")
    r:onTapEdit(nil, ges(5, r.lines[1].y + 5))
    r:addChars("Long ")
    check(text(r):match("^## Long Weekend\n\nPack the %*%*tent%*%*%.\n\n&nbsp;") ~= nil, "typed in the heading: the rest unchanged")
    drawn = {}
    r:paintTo({ paintRect = function() end }, 0, 0)
    local saw_nbsp, saw_marker = false, false
    for _i, d in ipairs(drawn) do
        if d.text:match("&nbsp;") or d.text:match("%*%*") then saw_nbsp = true end
        if d.text == "1." then saw_marker = true end
    end
    check(not saw_nbsp and saw_marker, "drawn: no &nbsp; or ** anywhere; numbers before the items")
    local heading_face
    for _i, d in ipairs(drawn) do if d.text:match("Weekend") then heading_face = d.face end end
    check(heading_face and heading_face.size == RE.HEADING_SIZE[2] and heading_face.name == "NotoSans-Bold.ttf",
        "the heading drawn big and bold")
end

-- ------------------------------------------------------------ pictures, sized with pull tabs
do
    local made = {}
    local function fakeBB(w, h) return { w = w, h = h, getWidth = function(b) return b.w end, getHeight = function(b) return b.h end } end
    local pictures = {
        size = function(src) if src:match("here") then return 400, 200 end end,
        bb = function(src, w, h) made[#made + 1] = src .. " " .. w .. "x" .. h; return fakeBB(w, h) end,
    }
    local doc = Blocks.parse("Trip\n\n![sea|center|320](/file/attachments/here/a.jpg)\n\n![far](/file/attachments/away/b.jpg)\n\nend")
    local r = RE:new{ width = 300, max_height = 900, doc = doc, editor = {}, hint = "Write", pictures = pictures }
    local pl
    for _i, l in ipairs(r.lines) do if l.picture then pl = l end end
    check(pl and pl.picture.w == 150 and pl.h == 75 and pl.picture.x == 75,
        "a picture sized in Memos (|center|320): half of the page (its share of Memos' 640-pixel column), centred")
    local far
    for _i, l in ipairs(r.lines) do if l.b.kind == "image" and not l.picture then far = l end end
    check(far ~= nil, "a picture not on the Kindle yet: its Markdown until it comes")
    local blits = {}
    local bb = { paintRect = function() end, paintBorder = function() end,
        blitFrom = function(_s, src, x, y) blits[#blits + 1] = { w = src.w, x = x, y = y } end }
    r.top = 0
    r:paintTo(bb, 0, 0)
    check(#blits == 1 and blits[1].w == 150 and blits[1].x == 75, "painted as the picture, where it's placed")
    -- a tap picks it: its pull tabs
    r:onTapEdit(nil, ges(150, pl.y + 30))
    check(r.picked == pl.b and r:onPicture(), "a tap on the picture picks it")
    local t = r:tabs()
    check(t and math.abs(t.left.x + t.left.w / 2 - 75) <= 1 and math.abs(t.right.x + t.right.w / 2 - 225) <= 1,
        "its pull tabs on its left and right sides")
    local tabs_drawn = 0
    r:paintTo({ paintRect = function(_s, _x, _y, w, h) if w == RE.TAB_W and h == RE.TAB_H then tabs_drawn = tabs_drawn + 1 end end,
        paintBorder = function() end, blitFrom = function() end, paintRoundedRect = function() end }, 0, 0)
    check(tabs_drawn == 2, "both tabs drawn")
    check(RE.tabY(-100, 400, 48, 200) == 76 and RE.tabY(10, 100, 48, 500) == 36 and RE.tabY(480, 300, 48, 500) == 606,
        "the tabs: in the middle of the part of a tall picture on the page (all of it when too little shows)")
    -- drag the right tab out by 30: centred, so 60 wider
    local rx, ry = t.right.x + 5, t.right.y + 5
    check(r:onPanEdit(nil, { start_pos = { x = rx, y = ry }, pos = { x = rx + 20, y = ry }, relative = { x = 20, y = 0 } }), "a drag from a tab is the tab's")
    r:onPanEdit(nil, { start_pos = { x = rx, y = ry }, pos = { x = rx + 30, y = ry }, relative = { x = 30, y = 0 } })
    check(r.drag and r.drag.w == 210, "while dragging: the new width (both sides, it's centred)")
    r:onPanReleaseEdit(nil, { pos = { x = rx + 30, y = ry } })
    check(text(r):match("!%[sea|center|448%]%(/file/attachments/here/a%.jpg%)"),
        "let go: written as Memos' web editor writes it (210 of 300 = 448 of 640) … " .. show(text(r)))
    for _i, l in ipairs(r.lines) do if l.picture then pl = l end end
    check(pl.picture.w == 210 and r.picked == pl.b, "shown at the new width, still picked")
    -- the left tab of a left-placed picture: drag it right to narrow it
    local d2 = Blocks.parse("![p](/file/attachments/here/c.jpg)")
    local r2 = RE:new{ width = 300, max_height = 900, doc = d2, editor = {}, pictures = pictures }
    local l2 = r2.lines[1]
    check(l2.picture and l2.picture.w == 300 and l2.picture.x == 0, "no size: as wide as fits (a photo only shrinks)")
    r2:onTapEdit(nil, ges(100, l2.y + 10))
    local lt = r2:tabs().left
    r2:onPanEdit(nil, { start_pos = { x = lt.x + 2, y = lt.y + 2 }, relative = { x = 150, y = 0 } })
    r2:onPanReleaseEdit(nil, {})
    check(Blocks.write(r2.doc) == "![p|320](/file/attachments/here/c.jpg)", "the left tab dragged in by half: |320 … " .. show(Blocks.write(r2.doc)))
    r2:onTapEdit(nil, ges(10, r2.lines[1].y + 5))
    lt = r2:tabs().left
    r2:onPanEdit(nil, { start_pos = { x = lt.x + 2, y = lt.y + 2 }, relative = { x = 290, y = 0 } })
    check(r2.drag.w == RE.MIN_PICTURE, "never narrower than " .. RE.MIN_PICTURE)
    r2:onPanReleaseEdit(nil, {})
    -- a quick drag comes as a swipe
    r2:onTapEdit(nil, ges(10, r2.lines[1].y + 5))
    local rt = r2:tabs().right
    r2:onSwipeEdit(nil, { direction = "east", distance = 500, pos = { x = rt.x + 2, y = rt.y + 2 } })
    check(Blocks.write(r2.doc) == "![p|640](/file/attachments/here/c.jpg)", "a quick drag (a swipe) out: the page's width, |640 … " .. show(Blocks.write(r2.doc)))
    -- typing with it picked: a new line after it
    r2:addChars("caption")
    check(Blocks.write(r2.doc) == "![p|640](/file/attachments/here/c.jpg)\n\ncaption" and not r2.picked,
        "typing with a picture picked: the words on a new line after it")
    -- a tap elsewhere lets it go
    r:onTapEdit(nil, ges(5, r.lines[1].y + 5))
    check(r.picked == nil and r:tabs() == nil, "a tap elsewhere: no picture picked")
    -- without `pictures` (a quick note): its Markdown, as before
    local r3 = RE:new{ width = 300, max_height = 900, doc = Blocks.parse("![p|320](/x.jpg)"), editor = {} }
    check(r3.lines[1].picture == nil and r3.lines[1].st.mono, "without pictures: the picture's Markdown in grey")

    -- the picked picture's toolbar (the web's: Left, Center, Right, then ↑ ↓, Alt, 1:1, ✕) and moving it
    local function picDoc(content)
        local d = Blocks.parse(content)
        local ed = RE:new{ width = 300, max_height = 900, doc = d, editor = {}, pictures = pictures }
        return ed, d
    end
    local function pl(ed) for _i, l in ipairs(ed.lines) do if l.picture then return l end end end
    local function tapPic(ed) local l = pl(ed); ed:onTapEdit(nil, ges(l.picture.x + 5, l.y - ed.top + 5)) end
    local function tapTool(ed, id)
        local rr = ed:pictureBarRect()
        for i, t in ipairs(RE.PICTURE_BAR) do
            if t.id == id then return ed:onTapEdit(nil, ges(rr.x + (i - 1) * rr.cell + 2, rr.y + 2)) end
        end
    end
    local pe = picDoc("Before\n\n![sea|320](/file/attachments/here/a.jpg)\n\nAfter")
    check(pe:pictureBarRect() == nil, "nothing picked: no picture toolbar")
    tapPic(pe)
    local br = pe:pictureBarRect()
    local bl = pl(pe)
    check(br and (br.y + br.h <= bl.y - pe.top or br.y >= bl.y - pe.top + bl.h), "picked: its toolbar above it (or under it), not over it")
    local painted = {}
    pe:paintTo({ paintRect = function() end, paintBorder = function() end, blitFrom = function() end,
        paintRoundedRect = function(_s, _x, _y, w, h) painted[#painted + 1] = w .. "x" .. h end }, 0, 0)
    check(#painted >= 1, "…drawn")
    tapTool(pe, "center")
    check(text(pe):find("![sea|center|320](", 1, true) ~= nil, "Center: written as the web does (|center|320) … " .. show(text(pe)))
    tapTool(pe, "right")
    check(text(pe):find("![sea|right|320](", 1, true) ~= nil and pe.picked ~= nil, "Right: |right|320, still picked")
    tapTool(pe, "left")
    check(text(pe):find("![sea|320](", 1, true) ~= nil, "Left: the place left out (left is the web's default)")
    tapTool(pe, "reset")
    check(text(pe):find("![sea](", 1, true) ~= nil, "1:1: its own size again")
    tapTool(pe, "up")
    check(text(pe) == "![sea](/file/attachments/here/a.jpg)\n\nBefore\n\nAfter", "↑: up a paragraph … " .. show(text(pe)))
    tapTool(pe, "up")
    check(text(pe) == "![sea](/file/attachments/here/a.jpg)\n\nBefore\n\nAfter", "↑ at the top: stays")
    tapTool(pe, "down"); tapTool(pe, "down")
    check(text(pe) == "Before\n\nAfter\n\n![sea](/file/attachments/here/a.jpg)", "↓ ↓: to the end … " .. show(text(pe)))
    check(RE.withAlt("![sea|center|320](/x.jpg)", "A calm [sea]") == "![A calm  sea |center|320](/x.jpg)",
        "Alt: the description changed, its size and place kept")
    tapTool(pe, "delete")
    check(text(pe) == "Before\n\nAfter" and pe.picked == nil, "✕: the picture deleted … " .. show(text(pe)))
    -- dragging the picture itself: to another place, a line showing where
    local pd = picDoc("One\n\nTwo\n\n![p](/file/attachments/here/b.jpg)\n\nThree")
    tapPic(pd)
    local l0 = pl(pd)
    local sy = l0.y - pd.top + 10
    local first_y = pd.lines[1].y - pd.top
    check(pd:onPanEdit(nil, { start_pos = { x = l0.picture.x + 20, y = sy }, pos = { x = 0, y = 0 }, relative = { x = 0, y = first_y + 2 - sy } }),
        "the picture dragged (not a tab): it's being moved")
    check(pd.moving and pd.moving.at == 1 and pd.moving.line_y == first_y, "…a line where it goes (before One)")
    pd:onPanReleaseEdit(nil, {})
    check(text(pd) == "![p](/file/attachments/here/b.jpg)\n\nOne\n\nTwo\n\nThree", "let go: there … " .. show(text(pd)))
    tapPic(pd)
    local l1 = pl(pd)
    local sy1 = l1.y - pd.top + 10
    pd:onPanEdit(nil, { start_pos = { x = l1.picture.x + 20, y = sy1 }, relative = { x = 0, y = pd.total_h - pd.top - sy1 + 50 } })
    pd:onPanReleaseEdit(nil, {})
    check(text(pd) == "One\n\nTwo\n\nThree\n\n![p](/file/attachments/here/b.jpg)", "dragged below the end: last … " .. show(text(pd)))
    -- a long note: dragged to the top edge, it scrolls up under the finger
    local paras = {}
    for i = 1, 40 do paras[#paras + 1] = "Paragraph " .. i end
    local pl2 = picDoc(table.concat(paras, "\n\n") .. "\n\n![p](/file/attachments/here/c.jpg)")
    pl2.top = math.max(0, pl2.total_h - pl2.height)
    tapPic(pl2)
    local lp = pl(pl2)
    local top_before = pl2.top
    local sy2 = lp.y - pl2.top + 10
    pl2:onPanEdit(nil, { start_pos = { x = lp.picture.x + 20, y = sy2 }, relative = { x = 0, y = 5 - sy2 } })
    pl2:onPanEdit(nil, { start_pos = { x = lp.picture.x + 20, y = sy2 }, relative = { x = 0, y = 5 - sy2 } })
    check(pl2.moving and pl2.top < top_before, "dragged to the page's top edge: the note scrolls up under it")
    local Screen = require("device").screen
    local rr2 = pl2:panRange()
    check(rr2.w == Screen:getWidth() and rr2.h == Screen:getHeight(), "…and the finger is followed off the page too")
    pl2:onPanReleaseEdit(nil, {})
    check(pl2:panRange() == pl2.dimen, "let go: pans on the page only again")
    local kbd = editor("Hi\n\n![p](/file/attachments/here/a.jpg)")
    kbd.pictures = pictures
    kbd:relayout()
    kbd.keyboard:showKeyboard()
    local kl = pl(kbd)
    kbd:onTapEdit(nil, ges(kl.picture.x + 5, kl.y - kbd.top + 5))
    check(kbd.picked and not kbd.keyboard:isVisible(), "picking a picture puts the keyboard away")
    -- a tab still resizes (not a move)
    tapPic(pd)
    local tr = pd:tabs().right
    pd:onPanEdit(nil, { start_pos = { x = tr.x + 2, y = tr.y + 2 }, relative = { x = -60, y = 0 } })
    check(pd.drag ~= nil and pd.moving == nil, "a pull tab dragged: resizing, not moving")
    pd:onPanReleaseEdit(nil, {})
end

-- ------------------------------------------------------------ a long note scrolls
do
    local parts = {}
    for k = 1, 40 do parts[#parts + 1] = "Paragraph " .. k end
    local r = editor(table.concat(parts, "\n\n"), false)
    check(r.top > 0 and r.total_h > r.height, "a long note opens scrolled to its end (the cursor in view)")
    r:onSwipeEdit(nil, { direction = "south", pos = { x = 1, y = 1 } })
    local up = r.top
    r:onSwipeEdit(nil, { direction = "north", pos = { x = 1, y = 1 } })
    check(up < r.top or r.top == 0, "swipe down / up scrolls")
    r:moveCursorToCharPos(1)
    check(r.top == 0 and r.cur.b == block(r, 1), "the cursor at the top: scrolled to it")
end

-- ------------------------------------------------------------ the keyboard's other keys
do
    local r = editor("one two three", false)
    r:delWord()
    check(Blocks.plain(block(r, 1)) == "one two ", "delete word")
    r:delToStartOfLine()
    check(text(r) == "", "delete to the line's start")
    r:addChars("ab")
    r:leftChar(); r:leftChar(); r:leftChar()
    check(r.cur.i == 1, "← stops at the start")
    r:rightChar(); r:rightChar(); r:rightChar()
    check(r.cur.i == 3, "→ stops at the end")
    check(r:getChar(-1) == "b", "the character before the cursor (ZenOS' double space)")
    r:onCloseKeyboard()
    check(not r.keyboard:isVisible(), "the keyboard hides")
end

-- ------------------------------------------------------------ random editing reads back as edited
do
    math.randomseed(tonumber(os.getenv("GZ_SEED") or "") or 7)
    local words = { "milk", "the", "a", "*", "_", "#tag", "x_y", "1.", "-", "[ ]", "<b>", "&amp;", "`c`", "\\", "  ", "~" }
    local tools = { "heading", "bullet", "task", "ordered", "bold", "italic" }
    local bad, sessions = nil, 400
    for n = 1, sessions do
        local r = editor("", true)
        for _step = 1, 25 do
            local op = math.random(10)
            if op <= 4 then r:addChars(words[math.random(#words)] .. (math.random(2) == 1 and " " or ""))
            elseif op == 5 then r:addChars("\n")
            elseif op == 6 then r:delChar()
            elseif op == 7 then r:useTool(tools[math.random(#tools)])
            elseif op == 8 then r:moveCursorToCharPos(math.random(#r.charlist + 1))
            else
                -- a selection between two random places
                local a = math.random(#r.charlist + 1)
                r:moveCursorToCharPos(a)
                local p = { b = r.cur.b, i = r.cur.i }
                r:moveCursorToCharPos(math.random(#r.charlist + 1))
                r.anchor = p
                if math.random(2) == 1 then r:useTool(tools[math.random(#tools)]) else r:addChars("z") end
            end
        end
        -- what Save writes reads back as the same lines, kinds and marks
        local md = Blocks.write(r.doc)
        local back = Blocks.parse(md)
        local function sig(doc)
            -- (empty lines at the end aren't written, as in Memos)
            local last = #doc.blocks
            while last > 0 and doc.blocks[last].kind == "paragraph" and #doc.blocks[last].chars == 0 do last = last - 1 end
            local out = {}
            for k = 1, last do
                local b = doc.blocks[k]
                local ms = {}
                for c = 1, #b.chars do
                    -- (bold or italic on a space next to a marker isn't kept: Memos moves it outside)
                    local m = not b.chars[c]:match("^%s$") and b.marks[c]
                    ms[c] = m and ((m.b and "b" or "") .. (m.i and "i" or "")) or ""
                end
                out[#out + 1] = b.kind .. (b.level or "") .. (b.done and "x" or "") .. ":" .. table.concat(b.chars) .. "|" .. table.concat(ms, ",")
            end
            return table.concat(out, "\n")
        end
        local s1, s2 = sig(r.doc), sig(back)
        if s1 ~= s2 then bad = { n = n, md = md, s1 = s1, s2 = s2 }; break end
    end
    check(bad == nil, ("%d random editing sessions (typing, Enter, ⌫, the toolbar, selections) read back as edited"):format(sessions)
        .. (bad and ("\n#" .. bad.n .. " " .. show(bad.md) .. "\n  edited: " .. show(bad.s1) .. "\n  read:   " .. show(bad.s2)) or ""))
end

do
    local r = editor("old", false)
    r:setText("# New\n\n- [ ] item")
    check(text(r) == "# New\n\n- [ ] item" and r.cur.b == block(r, 2) and r.cur.i == 5, "setText: the whole note replaced, the cursor at its end")
end

-- ------------------------------------------------------------ the formatting bar at the selection
do
    print("== the formatting bar comes up at the selection (hold), as in Memos' web editor")
    local r = editor("Pack the tent and the maps.\n\nsecond line here\n\n&nbsp;")
    local function line(k) for _i, l in ipairs(r.lines) do if l.b == block(r, k) then return l end end end
    check(r:barRect() == nil and r:barToolAt(20, 20) == nil, "no bar while typing")
    local l1 = line(1)
    r:onHoldEdit(nil, ges(l1.x0 + 10 * 10 + 5, l1.y + 5))
    local rect = r:barRect()
    check(rect ~= nil and r.bar_open == true, "hold a word: it's selected and the bar comes up")
    check(rect.y >= l1.y + l1.h and rect.x >= 0 and rect.x + rect.w <= r.width and rect.w == rect.cell * #RE.BAR,
        "…under the line when there's no room above it, inside the page")
    local ids = {}
    for i, t in ipairs(RE.BAR) do ids[i] = t.id end
    check(table.concat(ids, ",") == "bold,italic,heading,bullet,task,ordered,tag", "its buttons: B, I, H, list, checklist, numbered, tag")
    r:onHoldPanEdit(nil, ges(l1.x0 + 10 * 26, l1.y + 5))
    r:onHoldReleaseEdit(nil, ges(l1.x0 + 10 * 26, l1.y + 5))
    check(r.bar_open == true and r:selection() ~= nil, "drag for more: the bar stays")
    rect = r:barRect()
    local function barPoint(i) return ges(rect.x + (i - 1) * rect.cell + 5, rect.y + 5) end
    check(r:barToolAt(rect.x + 5, rect.y + 5).id == "bold" and r:barToolAt(rect.x + rect.w - 2, rect.y + 5).id == "tag"
        and r:barToolAt(rect.x + 5, rect.y + rect.h + 3) == nil, "a point on the bar is its button; beside it, none")
    r:onTapEdit(nil, barPoint(1))
    check(text(r):match("Pack the %*%*tent and the maps%*%*%.") ~= nil and r.bar_open == true and r:selection() ~= nil,
        "tap B on the bar: the selection bold, the bar and the selection still there … " .. show(text(r)))
    check(r:toolOn("bold") == true and r:toolOn("italic") == false and r:toolOn("heading") == false, "…B shown as on")
    r:onTapEdit(nil, barPoint(2))
    check(text(r):match("%*%*%*tent and the maps%*%*%*") ~= nil or text(r):match("_") ~= nil or text(r):match("%*%*%*") ~= nil,
        "…then I: bold and italic … " .. show(text(r)))
    r:onHoldEdit(nil, barPoint(3))
    check(r:selection() ~= nil and r.bar_open == true, "a hold on the bar itself changes nothing")
    r:onTapEdit(nil, barPoint(3))
    check(block(r, 1).kind == "heading" and r.bar_open == true, "H on the bar: the selection's line a heading")
    -- a tap on the text puts it away
    rect = r:barRect()
    r:onTapEdit(nil, ges(25, rect.y + rect.h + 60))
    check(r.bar_open == nil and r:barRect() == nil and r:selection() == nil, "a tap on the text: the bar goes away, the cursor there")
    local l2 = line(2)
    -- typing puts it away
    r:onHoldEdit(nil, ges(l2.x0 + 25, l2.y + 5))
    r:onHoldReleaseEdit(nil, ges(l2.x0 + 25, l2.y + 5))
    local hp, hq = r:selection()
    check(r.bar_open == true and hp and hp.i == 1 and hq.i == 7, "hold again (no drag): the bar again, the whole word still chosen when the finger lifts inside it")
    r:addChars("x")
    check(r.bar_open == nil, "typing puts it away")
    -- an empty line: the bar for the line itself
    local l3 = line(3)
    r:onHoldEdit(nil, ges(5, l3.y + 5))
    r:onHoldReleaseEdit(nil, ges(5, l3.y + 5))
    check(r.bar_open == true and r:selection() == nil, "hold an empty line: the bar, with nothing selected")
    rect = r:barRect()
    check(rect.y + rect.h <= line(3).y - r.top, "…above the line when there's room")
    r:onTapEdit(nil, barPoint(5))
    check(block(r, 3).kind == "task" and r.bar_open == true, "…its checklist button makes the line a checklist item")
    r:onTapEdit(nil, barPoint(7))
    check(r.editor.tag_asked == true, "# on the bar asks for a tag")
    -- arrows put it away
    r.bar_open = true
    r:leftChar()
    check(r.bar_open == nil, "moving the cursor puts it away")
    -- painted: its labels
    r:onHoldEdit(nil, ges(l2.x0 + 25, line(2).y + 5))
    drawn = {}
    local rects = 0
    r:paintTo({ paintRect = function() rects = rects + 1 end, paintRoundedRect = function() rects = rects + 1 end, paintBorder = function() rects = rects + 1 end }, 0, 0)
    local labels = {}
    for _i, d in ipairs(drawn) do labels[d.text] = true end
    check(labels["B"] and labels["I"] and labels["H"] and labels["1."] and labels["#"], "painted with the page: B I H … 1. #")
end

print(("richedit: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
