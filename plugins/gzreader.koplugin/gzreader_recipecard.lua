--[[--
A recipe in the Bookshelf view (common/gz_view.lua; the other views keep
the page of text, gzreader_recipes.lua): a ruled index card on the kitchen
counter, as it would stand in the recipe box (gzreader_recipebox.lua).

- the recipe's name in handwriting under a paper clip, a rule under it,
  then what it makes and how long it takes; its first category on a
  divider's tab behind the card;
- on the card's ruled lines: the ingredients, each with a circle (a tap,
  or Press on it, crosses the ingredient off, for the time GZreader runs),
  the steps, numbered, and the notes;
- what doesn't fit goes on the next card: "Turn the card" (a tap on it or
  on the right of the card, a swipe, the page keys) and back again. A
  heading is never left alone at the foot of a card;
- "Recipe box" (or Back) puts the card away.

On a colour screen the card is cream with blue lines and a red rule, the
counter warm; greys everywhere else.

The words are gzreader_mealie.lua's (Mealie.recipe): Card.rows turns them
into the card's lines, Card.paginate into cards. Both are pure and tested.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local Screen = Device.screen
local function S(px) return Screen:scaleBySize(px) end

local function Shop() return require("gzreader_bookshop") end
local function Box() return require("gzreader_recipebox") end

local Card = {
    ROW_H = 32,
    HEAD = { 0.55, { 216, 105, 92 } },  -- the rule under the name
    CLIP = { 0.7, { 120, 126, 136 } },
    crossed = {},                        -- [slug] = { [ingredient] = true }, while GZreader runs
}

---------------------------------------------------------------- the lines

--- Text cut into lines of at most `max` characters (the tests' wrap; the
--- screen's measures the font).
function Card.wrapChars(text, max)
    local lines = {}
    for para in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        local cur = ""
        for word in para:gmatch("%S+") do
            local try = cur == "" and word or (cur .. " " .. word)
            if #try <= max or cur == "" then cur = try else lines[#lines + 1] = cur; cur = word end
        end
        if cur ~= "" then lines[#lines + 1] = cur end
    end
    return lines
end

--- A recipe (Mealie.recipe) as the card's lines, in order. `wrap(text,
--- indent)` → the text's lines for the card's width (indent: "mark" for a
--- line behind a circle or a number, nil for the full width). Each line:
--- { kind = "head" | "section" | "ing" | "step" | "note" | "text" | "blank",
--- text, first (the paragraph's first line: its circle or number is drawn
--- there), ing (which ingredient), n (the step's number), keep (never the
--- last line on a card) }.
function Card.rows(r, wrap)
    local out = {}
    local function add(row) out[#out + 1] = row end
    local function blank() if #out > 0 and out[#out].kind ~= "blank" then add({ kind = "blank" }) end end
    local function para(kind, text, more)
        for i, line in ipairs(wrap(text, kind ~= "text" and kind ~= "note" and "mark" or nil)) do
            local row = { kind = kind, text = line, first = i == 1 }
            for k, v in pairs(more or {}) do row[k] = v end
            add(row)
        end
    end
    if r.desc then
        para("text", r.desc)
        blank()
    end
    if #(r.ingredients or {}) > 0 then
        add({ kind = "head", text = _("INGREDIENTS"), keep = true })
        local n = 0
        for _i, ing in ipairs(r.ingredients) do
            if ing.title then add({ kind = "section", text = ing.title, keep = true })
            else
                n = n + 1
                para("ing", ing.text, { ing = n })
            end
        end
        blank()
    end
    if #(r.steps or {}) > 0 then
        add({ kind = "head", text = _("STEPS"), keep = true })
        local n = 0
        for _i, st in ipairs(r.steps) do
            if st.title then
                add({ kind = "section", text = st.title, keep = true })
                n = 0
            else
                n = n + 1
                para("step", st.text, { n = n })
            end
        end
        blank()
    end
    if #(r.notes or {}) > 0 then
        add({ kind = "head", text = _("NOTES"), keep = true })
        for _i, nt in ipairs(r.notes) do
            if nt.title then add({ kind = "section", text = nt.title, keep = true }) end
            para("note", nt.text)
        end
    end
    while #out > 0 and out[#out].kind == "blank" do out[#out] = nil end
    if #out == 0 then add({ kind = "text", text = _("This recipe has no ingredients or steps yet."), first = true }) end
    return out
end

--- The lines on each card: { { first, last } … } (indexes into rows).
--- `first_rows` lines fit on the first card, `next_rows` on the others. A
--- card never starts with a blank line, and never ends on a heading (it
--- goes to the next card with what it heads).
function Card.paginate(rows, first_rows, next_rows)
    local cards = {}
    local i, n = 1, #rows
    while i <= n do
        while i <= n and rows[i].kind == "blank" do i = i + 1 end
        if i > n then break end
        local room = math.max(1, #cards == 0 and first_rows or next_rows)
        local last = math.min(n, i + room - 1)
        if last < n then
            local cut = last
            while cut > i and (rows[cut].keep or rows[cut].kind == "blank") do cut = cut - 1 end
            if not rows[cut].keep then last = cut end
        end
        while last > i and rows[last].kind == "blank" do last = last - 1 end
        cards[#cards + 1] = { first = i, last = last }
        i = last + 1
    end
    if #cards == 0 then cards[1] = { first = 1, last = 0 } end
    return cards
end

---------------------------------------------------------------- where things go

--- The card's place on a w x h screen (px; s = the screen's scale
--- function). Pure. { card, tab, row_h, text_x, mark_w, text_w, first = { y,
--- rows }, next = { y, rows }, tags = { y, h } }.
function Card.layout(w, h, s)
    s = s or S
    local mx = s(24)
    local row_h = s(Card.ROW_H)
    local L = { w = w, h = h, row_h = row_h }
    L.card = { x = mx, y = s(44), w = w - 2 * mx, h = h - s(44) - s(70) }
    L.tab = { x = L.card.x + L.card.w - s(160), y = s(12), w = s(130), h = s(32) }
    L.text_x = L.card.x + s(22)
    L.mark_w = s(30)
    L.text_w = L.card.w - 2 * s(22)
    L.first = { y = L.card.y + s(96) }
    L.next = { y = L.card.y + s(54) }
    L.first.rows = math.floor((L.card.y + L.card.h - s(10) - L.first.y) / row_h)
    L.next.rows = math.floor((L.card.y + L.card.h - s(10) - L.next.y) / row_h)
    L.tags = { y = L.card.y + L.card.h + s(18), h = s(34) }
    L.fits = L.first.rows >= 4 and L.text_w >= s(200)
    return L
end

---------------------------------------------------------------- the card

local Page = InputContainer:extend{ covers_fullscreen = true, recipe = nil, page = 1 }

local function face() return Font:getFace("cfont", 16) end

--- The screen's wrap: by what the font measures.
local function wrapFor(L)
    local RenderText = require("ui/rendertext")
    local f = face()
    return function(text, indent)
        local max = L.text_w - (indent and L.mark_w or 0)
        local lines = {}
        for para in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
            local cur = ""
            for word in para:gmatch("%S+") do
                local try = cur == "" and word or (cur .. " " .. word)
                if cur == "" or RenderText:sizeUtf8Text(0, max * 4, f, try, true, false).x <= max then cur = try
                else lines[#lines + 1] = cur; cur = word end
            end
            if cur ~= "" then lines[#lines + 1] = cur end
        end
        return lines
    end
end

function Page:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.colour = require("gzreader_colour").enabled()
    self.L = Card.layout(self.dimen.w, self.dimen.h)
    self.rows = Card.rows(self.recipe, wrapFor(self.L))
    self.cards = Card.paginate(self.rows, self.L.first.rows, self.L.next.rows)
    Card.crossed[self.recipe.slug] = Card.crossed[self.recipe.slug] or {}
    self.done = Card.crossed[self.recipe.slug]
    self.zones = {}
    self.keys = Device:hasDPad() and not Device:isTouchDevice()
    if Device:hasKeys() then
        local g = Device.input.group
        self.key_events = {
            GzClose = { { g.Back } },
            GzNextCard = { { g.PgFwd } },
            GzPrevCard = { { g.PgBack } },
            GzRight = { { "Right" } },
            GzLeft = { { "Left" } },
            GzDown = { { "Down" } },
            GzUp = { { "Up" } },
            GzPress = { { "Press" } },
        }
    end
    if Device:isTouchDevice() then
        local range = function() return self.dimen end
        self.ges_events = {
            GzTap = { GestureRange:new{ ges = "tap", range = range } },
            GzSwipe = { GestureRange:new{ ges = "swipe", range = range } },
        }
    end
end

function Page:getSize() return self.dimen end

function Page:redraw() UIManager:setDirty(self, function() return "ui", self.dimen end) end

--- The ingredients on this card, in order (the 5-way moves over them).
function Page:ingredientsHere()
    local c = self.cards[self.page]
    local out = {}
    for i = c.first, c.last do
        local row = self.rows[i]
        if row.kind == "ing" and row.first then out[#out + 1] = row.ing end
    end
    return out
end

function Page:turn(by)
    local to = math.max(1, math.min(#self.cards, self.page + by))
    if to == self.page then return true end
    self.page = to
    self.focus = nil
    self:redraw()
    return true
end

function Page:cross(ing)
    if not ing then return true end
    self.done[ing] = not self.done[ing] or nil
    self:redraw()
    return true
end

function Page:onGzClose() UIManager:close(self); return true end
function Page:onGzNextCard() return self:turn(1) end
function Page:onGzPrevCard() return self:turn(-1) end
function Page:onGzRight() return self:turn(1) end
function Page:onGzLeft() return self:turn(-1) end

function Page:moveFocus(by)
    local here = self:ingredientsHere()
    if #here == 0 then return true end
    local at = 0
    for k, ing in ipairs(here) do if ing == self.focus then at = k end end
    at = math.max(1, math.min(#here, at + by))
    self.focus = here[at]
    self:redraw()
    return true
end
function Page:onGzDown() return self:moveFocus(1) end
function Page:onGzUp() return self:moveFocus(-1) end
function Page:onGzPress() return self:cross(self.focus) end

local function inside(r, pos) return r and pos.x >= r.x and pos.x < r.x + r.w and pos.y >= r.y and pos.y < r.y + r.h end

function Page:onGzTap(_arg, ges)
    local pos = ges.pos
    if inside(self.zones.close, pos) then return self:onGzClose() end
    if inside(self.zones.next, pos) then return self:turn(1) end
    if inside(self.zones.prev, pos) then return self:turn(-1) end
    for _i, z in ipairs(self.zones.ings or {}) do
        if inside(z, pos) then return self:cross(z.ing) end
    end
    -- the card's right edge turns it, its left edge turns it back
    local c = self.L.card
    if inside(c, pos) then
        if pos.x > c.x + c.w * 0.75 then return self:turn(1) end
        if pos.x < c.x + c.w * 0.25 then return self:turn(-1) end
    end
    return true
end

function Page:onGzSwipe(_arg, ges)
    if ges.direction == "west" then return self:turn(1) end
    if ges.direction == "east" then return self:turn(-1) end
    if ges.direction == "south" then return self:onGzClose() end
    return true
end

--- A paper tag under the card. Returns its place.
function Page:tag(bb, label, x, y, h, right)
    local TextWidget = require("ui/widget/textwidget")
    local t = TextWidget:new{ text = label, face = Font:getFace("cfont", 14), bold = true }
    local sz = t:getSize()
    local w = sz.w + S(28)
    if right then x = x - w end
    local r = math.floor(h / 2)
    Box().fillWith(bb, self.colour, Box().PAL.card, x, y, w, h, r)
    bb:paintBorder(x, y, w, h, math.max(2, S(2)), Blitbuffer.COLOR_BLACK, r)
    t:paintTo(bb, x + S(14), y + math.floor((h - sz.h) / 2))
    t:free()
    return { x = x, y = y, w = w, h = h }
end

function Page:paintTo(bb, x, y)
    local D = Shop().draw
    local fill, PAL = Box().fillWith, Box().PAL
    local L, r = self.L, self.recipe
    local bw = math.max(2, S(2))
    local c = { x = x + L.card.x, y = y + L.card.y, w = L.card.w, h = L.card.h }
    local first = self.page == 1
    fill(bb, self.colour, PAL.counter, x, y, self.dimen.w, self.dimen.h)
    -- the category's divider, behind the card
    local cat = r.cats and r.cats[1]
    if cat then
        local tb = L.tab
        fill(bb, self.colour, PAL.tabs[2], x + tb.x, y + tb.y, tb.w, tb.h + S(8), S(7))
        bb:paintBorder(x + tb.x, y + tb.y, tb.w, tb.h + S(8), bw, Blitbuffer.COLOR_BLACK, S(7))
        D.text(bb, cat, Font:getFace("cfont", 13), x + tb.x + math.floor(tb.w / 2), y + tb.y + math.floor(tb.h / 2),
            { center = true, middle = true, bold = true, max_width = tb.w - S(12) })
    end
    -- the next card, behind this one
    if self.page < #self.cards then
        fill(bb, self.colour, PAL.card, c.x + S(7), c.y + S(7), c.w, c.h, S(6))
        bb:paintBorder(c.x + S(7), c.y + S(7), c.w, c.h, bw, Blitbuffer.COLOR_BLACK, S(6))
    end
    fill(bb, self.colour, PAL.card, c.x, c.y, c.w, c.h, S(6))
    bb:paintBorder(c.x, c.y, c.w, c.h, bw, Blitbuffer.COLOR_BLACK, S(6))
    -- the name, the rule under it, what it makes
    local top = first and L.first or L.next
    local name_x = c.x + (first and S(56) or S(22))
    if first then
        D.text(bb, r.name or "", D.hand(34), name_x, c.y + S(34), { middle = true, max_width = c.x + c.w - S(22) - name_x })
        fill(bb, self.colour, Card.HEAD, c.x + bw, c.y + S(62), c.w - 2 * bw, math.max(2, S(3)))
        if #(r.facts or {}) > 0 then
            D.text(bb, table.concat(r.facts, "  ·  "), Font:getFace("cfont", 13), c.x + S(22), c.y + S(80),
                { middle = true, max_width = c.w - S(44), color = D.gray(0.85) })
        end
        -- the paper clip
        local clip = fill
        clip(bb, self.colour, Card.CLIP, c.x + S(24), c.y - S(16), math.max(2, S(3)), S(46))
        clip(bb, self.colour, Card.CLIP, c.x + S(38), c.y - S(10), math.max(2, S(3)), S(34))
        clip(bb, self.colour, Card.CLIP, c.x + S(24), c.y - S(16), S(17), math.max(2, S(3)))
        clip(bb, self.colour, Card.CLIP, c.x + S(24), c.y + S(28), S(17), math.max(2, S(3)))
    else
        D.text(bb, r.name or "", D.hand(24), name_x, c.y + S(24), { middle = true, max_width = c.w - S(44) })
        fill(bb, self.colour, Card.HEAD, c.x + bw, c.y + S(42), c.w - 2 * bw, math.max(2, S(3)))
    end
    -- the ruled lines, and what's written on them
    local rows_y = y + top.y
    local page = self.cards[self.page]
    local f = face()
    self.zones = { ings = {} }
    for k = 0, top.rows - 1 do
        fill(bb, self.colour, PAL.rule, c.x + bw, rows_y + (k + 1) * L.row_h - math.max(1, S(1)), c.w - 2 * bw, math.max(1, S(1)))
    end
    local tx = x + L.text_x
    for i = page.first, page.last do
        local row = self.rows[i]
        local ry = rows_y + (i - page.first) * L.row_h
        local mid = ry + math.floor(L.row_h / 2)
        if row.kind == "head" then
            D.text(bb, row.text, Font:getFace("cfont", 12), tx, mid, { middle = true, bold = true })
        elseif row.kind == "section" then
            D.text(bb, row.text, f, tx, mid, { middle = true, bold = true, max_width = L.text_w })
        elseif row.kind == "ing" then
            local done = self.done[row.ing]
            if row.first then
                local rad = S(8)
                if done then bb:paintCircle(tx + rad, mid, rad, Blitbuffer.COLOR_BLACK)
                else bb:paintCircle(tx + rad, mid, rad, Blitbuffer.COLOR_BLACK, bw) end
                if self.keys and self.focus == row.ing then
                    D.focusRing(bb, { x = tx - S(2), y = ry + S(4), w = L.text_w + S(4), h = L.row_h - S(8) })
                end
            end
            local sz = D.text(bb, row.text, f, tx + L.mark_w, mid, { middle = true, max_width = L.text_w - L.mark_w, color = done and D.gray(0.6) or nil })
            if done then bb:paintRect(tx + L.mark_w, mid, sz.w, math.max(1, S(1)), D.gray(0.7)) end
            table.insert(self.zones.ings, { x = c.x, y = ry, w = c.w * 0.75, h = L.row_h, ing = row.ing })
        elseif row.kind == "step" then
            if row.first then D.text(bb, row.n .. ".", f, tx, mid, { middle = true, bold = true }) end
            D.text(bb, row.text, f, tx + L.mark_w, mid, { middle = true, max_width = L.text_w - L.mark_w })
        elseif row.kind ~= "blank" then
            D.text(bb, row.text, f, tx, mid, { middle = true, max_width = L.text_w })
        end
    end
    -- under the card: back to the box, which card, turn it
    local ty = y + L.tags.y
    self.zones.close = self:tag(bb, "‹ " .. _("Recipe box"), c.x, ty, L.tags.h)
    if #self.cards > 1 then
        local right = c.x + c.w
        if self.page < #self.cards then
            self.zones.next = self:tag(bb, _("Turn the card") .. " ›", right, ty, L.tags.h, true)
            right = self.zones.next.x - S(10)
        end
        if self.page > 1 then
            self.zones.prev = self:tag(bb, "‹ " .. _("Back"), right, ty, L.tags.h, true)
            right = self.zones.prev.x - S(10)
        end
        local label = T(_("Card %1 of %2"), self.page, #self.cards)
        local left = self.zones.close.x + self.zones.close.w + S(10)
        if right - left > S(60) then
            D.text(bb, label, Font:getFace("cfont", 13), left + math.floor((right - left) / 2), ty + math.floor(L.tags.h / 2),
                { center = true, middle = true, max_width = right - left, color = D.gray(0.85) })
        end
    end
end

Card.Page = Page

--- Whether a recipe opens as a card: the Bookshelf view, on a screen the
--- card fits.
function Card.applies()
    return Shop().bookshelf() and Card.layout(Screen:getWidth(), Screen:getHeight()).fits
end

--- Show `r` (Mealie.recipe) as a card. Returns the widget.
function Card.show(r)
    local page = Page:new{ recipe = r }
    UIManager:show(page, "full")
    return page
end

return Card
