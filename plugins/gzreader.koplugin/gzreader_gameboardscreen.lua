--[[--
The game board's screens (its puzzles, themes and records:
gzreader_gameboard.lua).

- On Home's shelf (ZenOS's shelf.lua asks through __GZ_SHELF_GAMES): a game
  box standing on its side among the books, beside the daily paper;
  picked, it turns to show its lid (a grid, the name, how far you are);
  a second tap or Press opens it.
- The board: today's paper puzzles (the paper's own: done here, done there),
  the themed set's four, Choose a theme, New puzzles, Achievements and
  History. Touch: tap. Keys: the 5-way moves, Press opens, Back closes,
  Menu: the quick panel.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local function Board() return require("gzreader_gameboard") end
local function Pz() return require("gzreader_puzzles") end
local function PzScreen() return require("gzreader_puzzlescreen") end

local Screen_ = {}

local function face(file, size, fallback)
    local ok, f = pcall(Font.getFace, Font, file, size)
    if ok and f then return f end
    return Font:getFace(fallback or "smallinfofont", size)
end

--- A widget painted by hand, `w` × `h`.
local function drawn(w, h, paint)
    local Widget = require("ui/widget/widget")
    local wd = Widget:new{ dimen = Geom:new{ w = w, h = h } }
    wd.getSize = function() return Geom:new{ w = w, h = h } end
    wd.paintTo = function(self_, bb, x, y)
        self_.dimen.x, self_.dimen.y = x, y
        paint(bb, x, y)
    end
    return wd
end

---------------------------------------------------------------- what the board says

--- The paper's puzzles on the board (Puzzles.BOARD_KINDS: no sudoku) done
--- today, and how many there are.
function Screen_.paperDone(plugin)
    local kinds = Pz().BOARD_KINDS
    local ok, out = pcall(Pz().finished, plugin)
    if not ok then return {}, 0, #kinds end
    local n = 0
    for _i, k in ipairs(kinds) do if out[k] then n = n + 1 end end
    return out, n, #kinds
end

--- The themed set's puzzles done, and how many there are.
function Screen_.setDone(plugin, set)
    local pz = Pz().forSet(plugin, set)
    local ok, out, n = pcall(Pz().finished, pz)
    if not ok then return {}, 0, #Pz().kindsOf(pz) end
    return out, n, #Pz().kindsOf(pz)
end

--- The lid's lines: { "Today's paper 2/3", "Autumn 1/4", "★ 3/21" }.
function Screen_.lidLines(plugin)
    local B = Board()
    local pn, pof = select(2, Screen_.paperDone(plugin))
    local set = B.current(plugin)
    local sn, sof = select(2, Screen_.setDone(plugin, set))
    local an = select(2, B.achievements(plugin))
    return {
        T(_("Today's paper %1/%2"), pn, pof),
        T("%1 %2/%3", tostring(set.title or ""), sn, sof),
        T("\u{2605} %1/%2", an, #B.ACHIEVEMENTS),
    }
end

---------------------------------------------------------------- on Home's shelf

function Screen_.spineWidth(area_h) return math.max(26, math.floor(area_h * 0.22)) end
function Screen_.spineHeight(area_h) return math.floor(area_h * 0.86) end
function Screen_.lidSize(area_h)
    local h = math.floor(area_h * 0.8)
    return math.floor(h * 0.82), h
end

--- The game box among Home's books: { spine, spine_w, h, face, face_w,
--- face_h, open } or nil (the board is off).
function Screen_.shelfItem(plugin, ctx, area_h)
    if not Board().enabled(plugin) then return nil end
    local TextWidget = require("ui/widget/textwidget")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local Screen = Device.screen
    local S = function(n) return Screen:scaleBySize(n) end

    -- the lid, when it's picked: a crossword's corner, the name, how far you are
    local w, h = Screen_.lidSize(area_h)
    local pad = S(5)
    local inner = w - pad * 2
    local lines = {}
    pcall(function() lines = Screen_.lidLines(plugin) end)
    local name
    for size = 13, 6, -1 do
        if name then name:free() end
        name = TextWidget:new{ text = _("Game Board"), face = face("NotoSerif-Bold.ttf", size, "smallinfofontbold") }
        if name:getSize().w <= inner then break end
    end
    name:setMaxWidth(inner)
    local info = TextBoxWidget:new{ text = table.concat(lines, "\n"), face = face("NotoSans-Regular.ttf", 6, "smallinfofont"),
        width = inner, alignment = "center" }
    local lid = drawn(w, h, function(bb, x, y)
        bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)
        bb:paintBorder(x, y, w, h, math.max(2, S(2)), Blitbuffer.COLOR_BLACK)
        -- a grid of squares, some black, a few with letters' strokes
        local grid_h = h - pad * 3 - name:getSize().h - info:getSize().h
        local n = 6
        local cell = math.max(3, math.floor(math.min(inner, grid_h) / n))
        local gx, gy = x + math.floor((w - cell * n) / 2), y + pad
        local blacks = { [2] = true, [5] = true, [9] = true, [13] = true, [16] = true, [20] = true, [23] = true, [27] = true, [31] = true, [34] = true }
        for i = 0, n * n - 1 do
            local cx, cy = gx + (i % n) * cell, gy + math.floor(i / n) * cell
            if blacks[i] then bb:paintRect(cx, cy, cell, cell, Blitbuffer.COLOR_BLACK)
            else
                bb:paintBorder(cx, cy, cell + 1, cell + 1, 1, Blitbuffer.COLOR_DARK_GRAY)
                if (i * 7) % 5 == 0 then bb:paintRect(cx + math.floor(cell / 3), cy + math.floor(cell / 3), math.max(1, math.floor(cell / 3)), math.max(1, math.floor(cell / 3)), Blitbuffer.gray(0.5)) end
            end
        end
        local ny = gy + cell * n + pad
        bb:paintRect(x + pad, ny - math.floor(pad / 2), inner, 1, Blitbuffer.COLOR_BLACK)
        name:paintTo(bb, x + math.floor((w - name:getSize().w) / 2), ny)
        info:paintTo(bb, x + pad, ny + name:getSize().h + math.floor(pad / 2))
    end)
    lid.free = function() name:free(); info:free() end

    -- on its side: the box's edge, dark, chequered at both ends, its name along it
    local spine_w, spine_h = Screen_.spineWidth(area_h), Screen_.spineHeight(area_h)
    local spine_bb
    local spine = drawn(spine_w, spine_h, function(bb, x, y)
        if not spine_bb then
            local L = spine_h
            local lying = Blitbuffer.new(L, spine_w, Blitbuffer.TYPE_BB8)
            lying:fill(Blitbuffer.gray(0.82))
            local edge = math.max(2, S(2))
            -- the lid's rim (lighter) over the box's side
            lying:paintRect(0, 0, L, math.max(2, math.floor(spine_w * 0.18)), Blitbuffer.gray(0.6))
            lying:paintRect(0, math.max(2, math.floor(spine_w * 0.18)), L, 1, Blitbuffer.COLOR_BLACK)
            -- chequers at both ends
            local sq = math.max(3, math.floor(spine_w / 4))
            local band = sq * 2
            for e = 0, 1 do
                local x0 = e == 0 and edge * 2 or (L - edge * 2 - band)
                for c = 0, 1 do
                    for r = 0, math.floor(spine_w / sq) do
                        local yy = math.max(2, math.floor(spine_w * 0.18)) + 2 + r * sq
                        if yy + sq <= spine_w - edge and (c + r) % 2 == 0 then
                            lying:paintRect(x0 + c * sq, yy, sq, sq, Blitbuffer.COLOR_WHITE)
                        end
                    end
                end
            end
            -- the name, white, as big as fits
            local room_h = spine_w - math.max(2, math.floor(spine_w * 0.18)) - S(4)
            local room_w = L - band * 2 - S(24)
            local title
            for size = 16, 6, -1 do
                if title then title:free() end
                title = TextWidget:new{ text = _("GAME BOARD"), face = face("NotoSans-Bold.ttf", size, "smallinfofontbold"), fgcolor = Blitbuffer.COLOR_WHITE }
                if title:getSize().h <= room_h and title:getSize().w <= room_w then break end
            end
            local ts = title:getSize()
            local ty = math.max(2, math.floor(spine_w * 0.18)) + math.floor((spine_w - math.max(2, math.floor(spine_w * 0.18)) - ts.h) / 2)
            title:paintTo(lying, math.floor((L - ts.w) / 2), ty)
            title:free()
            lying:paintBorder(0, 0, L, spine_w, 1, Blitbuffer.COLOR_BLACK)
            spine_bb = lying:rotatedCopy(270)
            lying:free()
        end
        bb:blitFrom(spine_bb, x, y, 0, 0, spine_w, spine_h)
        if Screen_.home then Screen_.home.spine_at = { x = x, y = y, w = spine_w, h = spine_h } end
    end)
    spine.free = function() if spine_bb then spine_bb:free(); spine_bb = nil end end
    Screen_.home = { menu = ctx and ctx.menu }
    return { spine = spine, spine_w = spine_w, h = spine_h, face = lid, face_w = w, face_h = h,
        open = function() Screen_.show(plugin) end }
end

--- Home again (the lid shows how far you are).
function Screen_.redrawHome()
    pcall(function() require("common/gz_view").redrawHome() end)
end

---------------------------------------------------------------- choosing a theme

--- The themes on offer: { { text, enabled, set = function() → set or nil, menu } }.
function Screen_.themeChoices(plugin)
    local B = Board()
    local W = require("gzreader_gamewords")
    local st = B.store(plugin)
    local out = {}
    local first = st.books[1]
    out[#out + 1] = {
        text = first and T(_("From %1"), first.title or "?") or _("From your book (close a book you've read a few pages of first)"),
        enabled = first ~= nil, set = function() return B.bookSet(plugin, first and first.key) end,
    }
    if #st.books > 1 then
        out[#out + 1] = { text = _("From another book…"), enabled = true, menu = "books" }
        out[#out + 1] = { text = T(_("From your books (%1 of them)"), #st.books), enabled = true, set = function() return B.booksSet(plugin) end }
    end
    local season = W.season(tonumber(os.date("%m")))
    out[#out + 1] = { text = T(_("This season: %1"), season.title), enabled = true, set = function()
        local set = B.seasonSet()
        set.src.auto = true
        return set
    end }
    out[#out + 1] = { text = _("A category…"), enabled = true, menu = "categories" }
    out[#out + 1] = { text = _("Another season…"), enabled = true, menu = "seasons" }
    local okai, ready = pcall(function() return require("gzreader_ai").ready(plugin) end)
    out[#out + 1] = {
        text = okai and ready and _("Ask the AI for a theme your books share") or _("Ask the AI for a theme (set up AI first: Settings → Accounts and services)"),
        enabled = okai and ready == true, menu = "ai",
    }
    return out
end

function Screen_.chooseTheme(plugin, after)
    local ButtonDialog = require("ui/widget/buttondialog")
    local B = Board()
    local W = require("gzreader_gamewords")
    local dialog
    local function put(set)
        if dialog then UIManager:close(dialog) end
        if set and B.choose(plugin, set) then
            if after then after() end
        end
    end
    local function list(title, items)
        local rows = {}
        for _i, it in ipairs(items) do rows[#rows + 1] = { { text = it.text, enabled = it.enabled ~= false, callback = it.callback } } end
        rows[#rows + 1] = { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } }
        if dialog then UIManager:close(dialog) end
        dialog = ButtonDialog:new{ title = title, title_align = "center", buttons = rows }
        UIManager:show(dialog)
    end
    local function themes(season)
        local items = {}
        for _i, t in ipairs(season and {} or W.categories()) do
            items[#items + 1] = { text = t.title, callback = function() put(B.categorySet(t.id)) end }
        end
        if season then
            for _i, t in ipairs(W.THEMES) do
                if t.season then items[#items + 1] = { text = t.title, callback = function() put(B.categorySet(t.id)) end } end
            end
        end
        list(season and _("A season") or _("A category"), items)
    end
    local function books()
        local items = {}
        for _i, b in ipairs(B.store(plugin).books) do
            items[#items + 1] = { text = tostring(b.title or "?"), callback = function() put(B.bookSet(plugin, b.key)) end }
        end
        list(_("A book"), items)
    end
    local function ai()
        if dialog then UIManager:close(dialog); dialog = nil end
        local InfoMessage = require("ui/widget/infomessage")
        local name = require("gzreader_ai").name(require("gzreader_ai").provider(plugin))
        local waiting = InfoMessage:new{ text = T(_("Asking %1 for a theme your books share…"), name) }
        UIManager:show(waiting)
        B.askAI(plugin, function(set, why)
            UIManager:close(waiting)
            if not set then
                UIManager:show(InfoMessage:new{ text = T(_("%1 didn't send a theme: %2"), name, tostring(why or _("no answer"))) })
                return
            end
            B.choose(plugin, set)
            UIManager:show(InfoMessage:new{ text = T(_("The theme: %1"), set.title) .. "\n\n" .. _("An AI chose these words and clues. They can be wrong."), timeout = 4 })
            if after then after() end
        end)
    end
    local items = {}
    for _i, c in ipairs(Screen_.themeChoices(plugin)) do
        items[#items + 1] = { text = c.text, enabled = c.enabled, callback = function()
            if c.menu == "categories" then return themes(false) end
            if c.menu == "seasons" then return themes(true) end
            if c.menu == "books" then return books() end
            if c.menu == "ai" then return ai() end
            put(c.set())
        end }
    end
    list(_("Choose a theme"), items)
end

---------------------------------------------------------------- the board

local Page

local function pageClass()
    if Page then return Page end
    local GestureRange = require("ui/gesturerange")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen
    local S = function(n) return Screen:scaleBySize(n) end

    Page = InputContainer:extend{ covers_fullscreen = true, name = "game board" }

    function Page:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
        self.touch = Device:isTouchDevice()
        self.keys = Device:hasKeys() and Device:hasDPad() and not self.touch
        self.focus = 1
        if Device:hasKeys() then
            local g = Device.input.group
            self.key_events = {
                GbClose = { { g.Back } },
                GbUp = { { "Up" }, event = "GbMove", args = "n" },
                GbDown = { { "Down" }, event = "GbMove", args = "s" },
                GbLeft = { { "Left" }, event = "GbMove", args = "w" },
                GbRight = { { "Right" }, event = "GbMove", args = "e" },
                GbPress = { { "Press" } },
            }
            if Device:hasKeyboard() then self.key_events.GbPanel = { { "Menu" } } end
        end
        if self.touch then
            self.ges_events = {
                GbTap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
                GbSwipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
            }
        end
        self.widgets = {}
        self:build()
    end

    function Page:freeWidgets()
        for _i, w in ipairs(self.widgets) do if w.free then w:free() end end
        self.widgets = {}
    end

    function Page:text(str, f, max_w)
        local w = TextWidget:new{ text = str, face = f, max_width = max_w }
        self.widgets[#self.widgets + 1] = w
        return w
    end

    --- A font size whose letters are about `px` pixels tall.
    local function sizeFor(px) return math.max(5, math.floor(px * 160 / Screen:getDPI() + 0.5)) end

    --- Lay it out as a game table (everything drawn in paintTo):
    --- - the board's frame, its name and the date on a banner, a round close token;
    --- - TODAY'S PAPER: three playing cards (no sudoku), each a picture of its puzzle;
    --- - the theme's box lid (tap: choose a theme) and a die (New puzzles), then its four cards;
    --- - the trophy cabinet (every achievement, the ones won dark) and the score card.
    --- self.items: what a tap or Press runs, { x, y, w, h, row, run, … }.
    function Page:build()
        self:freeWidgets()
        local B = Board()
        local plugin = self.plugin
        local W, H = self.dimen.w, self.dimen.h
        local frame = S(10)
        local margin = frame + S(10)
        local room = W - margin * 2
        self.frame = frame
        self.items = {}
        -- the banner
        local white = Blitbuffer.COLOR_WHITE
        local title = TextWidget:new{ text = _("GAME BOARD"), face = face("NotoSerif-Bold.ttf", 16, "smallinfofontbold"), fgcolor = white }
        self.widgets[#self.widgets + 1] = title
        local close_d = self.touch and math.max(S(34), title:getSize().h + S(8)) or 0
        local date = TextWidget:new{ text = require("gzreader_dailyscreen").dateText(os.time()), face = face("NotoSerif-Italic.ttf", 9, "smallinfofont"),
            max_width = room - title:getSize().w - close_d - S(40), fgcolor = white }
        self.widgets[#self.widgets + 1] = date
        local banner_h = title:getSize().h + S(12)
        self.banner = { title = title, date = date, x = margin, y = frame + S(8), w = room - close_d - S(10), h = banner_h }
        self.close = self.touch and { x = W - margin - close_d, y = frame + S(8) + math.floor((banner_h - close_d) / 2), d = close_d } or nil
        local y = self.banner.y + banner_h + S(10)
        local label_face = face("NotoSerif-Bold.ttf", 10, "smallinfofontbold")
        local card_face = Font:getFace("smallinfofontbold", 12)
        local note_face = Font:getFace("smallinfofont", 9)
        local keys_hint = (not self.touch) and self:text(_("5-way: move · Press: open · Back: close"), Font:getFace("smallinfofont", 9), room) or nil
        local bottom = H - frame - S(8) - (keys_hint and keys_hint:getSize().h + S(6) or 0)
        self.hint = keys_hint and { widget = keys_hint, y = bottom + S(4) } or nil
        -- how tall each part can be
        local gap = S(10)
        local cw = math.floor((room - gap * 3) / 4)
        local label_h = self:text("Ag", label_face):getSize().h + S(10)
        local lid_h = math.max(S(44), label_h + S(18))
        local fixed = label_h * 2 + lid_h + gap * 5
        local avail = bottom - y - fixed
        local ch = math.floor(math.min(cw * 1.3, avail * 0.31))
        self.labels, self.cards = {}, {}
        local function label(str, right)
            local l = self:text(str, label_face, room)
            local r = right and self:text(right, note_face, room - l:getSize().w - S(20)) or nil
            self.labels[#self.labels + 1] = { widget = l, right = r, y = y }
            y = y + label_h
        end
        local function cards(kinds, done, began, row, run)
            for i, kind in ipairs(kinds) do
                local c = { kind = kind, done = done[kind], began = began and began[kind], row = row,
                    x = margin + (i - 1) * (cw + gap), y = y, w = cw, h = ch, run = function() return run(kind) end }
                c.name = self:text(PzScreen().tabLabel(kind), card_face, cw - S(12))
                c.note = (not c.done and c.began) and self:text(_("Started"), note_face, cw - S(12)) or nil
                self.cards[#self.cards + 1] = c
                self.items[#self.items + 1] = c
            end
            y = y + ch + gap
        end
        -- today's paper
        local pdone, pn, pof = Screen_.paperDone(plugin)
        local pstate = {}
        pcall(function() pstate = Pz().state(plugin) end)
        label(_("TODAY'S PAPER · BINGO"), T(_("%1 of %2 done"), pn, pof))
        cards(Pz().BOARD_KINDS, pdone, type(pstate.began) == "table" and pstate.began or nil, 1, function(kind) return self:open(kind) end)
        -- bingo: the fourth card of the row (gzreader_bingo.lua; its own page)
        do
            local okb, bingo = pcall(function() return require("gzreader_bingo").state(plugin) end)
            local c = { kind = "bingo", done = okb and bingo.won ~= nil, began = okb and (bingo.called or 0) > 0, row = 1,
                x = margin + #Pz().BOARD_KINDS * (cw + gap), y = y - ch - gap, w = cw, h = ch,
                run = function()
                    require("gzreader_bingoscreen").show(plugin, { on_close = function()
                        if not self.closed then self:rebuild() end
                    end })
                    return true
                end }
            c.name = self:text(_("Bingo"), card_face, cw - S(12))
            c.note = (not c.done and c.began) and self:text(_("Started"), note_face, cw - S(12)) or nil
            self.cards[#self.cards + 1] = c
            self.items[#self.items + 1] = c
        end
        -- the theme: its lid, the die, its cards
        local set = B.current(plugin)
        local sdone, sn, sof = Screen_.setDone(plugin, set)
        local die_w = lid_h + S(6)
        local lid = { row = 2, x = margin, y = y, w = room - die_w - gap, h = lid_h,
            run = function() Screen_.chooseTheme(plugin, function() self:rebuild() end) return true end }
        lid.small = self:text(_("THEME · tap to change"), note_face, lid.w - S(24))
        lid.title = self:text(tostring(set.title or ""), Font:getFace("smallinfofontbold", 13), lid.w - S(24))
        lid.count = self:text(T(_("%1 of %2"), sn, sof), note_face)
        local die = { row = 2, x = margin + room - die_w, y = y, w = die_w, h = lid_h, die = true,
            run = function() B.again(plugin); self:rebuild(); return true end }
        die.label = self:text(_("New"), note_face)
        self.lid, self.die = lid, die
        self.items[#self.items + 1] = lid
        self.items[#self.items + 1] = die
        y = y + lid_h + gap
        cards(Pz().kindsOf(Pz().forSet(plugin, set)), sdone, type(set.began) == "table" and set.began or nil, 3,
            function(kind) return self:open(kind, set) end)
        -- the cabinet and the score card
        local list, an = B.achievements(plugin)
        local stats = B.store(plugin).stats
        local run_days = B.streak(stats.days, os.date("%Y-%m-%d"))
        label(_("TROPHIES AND SCORES"), T(_("%1 of %2 won"), an, #list))
        local cab_w = math.floor(room * 0.56)
        local cab = { row = 4, x = margin, y = y, w = cab_w, h = math.max(S(80), bottom - y), trophies = list,
            run = function() return self:viewer(_("Achievements"), B.achievementsText(plugin)) end }
        cab.title = self:text(_("Achievements"), card_face, cab_w - S(20))
        local card = { row = 4, x = margin + cab_w + gap, y = y, w = room - cab_w - gap, h = cab.h,
            run = function() return self:viewer(_("History"), B.historyText(plugin)) end }
        card.title = self:text(_("Score card"), card_face, card.w - S(30))
        card.sum = self:text(T(_("%1 finished"), stats.total or 0) .. " · " .. (run_days == 1 and _("1 day running") or T(_("%1 days running"), run_days)),
            note_face, card.w - S(30))
        card.lines = {}
        local line_face = Font:getFace("smallinfofont", 9)
        local lh = self:text("Ag", line_face):getSize().h + S(6)
        local room_lines = math.floor((card.h - card.title:getSize().h - card.sum:getSize().h - S(30)) / lh)
        local history = B.store(plugin).history
        for i = 1, math.min(#history, math.max(0, room_lines)) do
            local h = history[i]
            local when = os.date("%d %b", h.t):gsub("^0", "")
            card.lines[i] = self:text(when .. "  " .. B.kindName(h.k) .. " · " .. (h.s or _("the paper")), line_face, card.w - S(36))
        end
        if #history == 0 then card.lines[1] = self:text(_("Nothing finished yet."), line_face, card.w - S(36)) end
        card.line_h = lh
        self.cab, self.score = cab, card
        self.items[#self.items + 1] = cab
        self.items[#self.items + 1] = card
        if self.focus > #self.items then self.focus = #self.items end
    end

    ---------------------------------------------------------------- drawing

    local function shade(v) return Blitbuffer.gray(v) end

    --- A card's shadow, then the card.
    local function cardBox(bb, x, y, w, h, r, fill)
        local off = math.max(2, S(3))
        bb:paintRoundedRect(x + off, y + off, w, h, shade(0.55), r)
        bb:paintRoundedRect(x, y, w, h, fill or Blitbuffer.COLOR_WHITE, r)
        bb:paintBorder(x, y, w, h, math.max(1, S(1)), Blitbuffer.COLOR_BLACK, r)
    end

    function Page:glyph(ch, px)
        self.glyphs = self.glyphs or {}
        local key = ch .. ":" .. px
        if not self.glyphs[key] then
            self.glyphs[key] = TextWidget:new{ text = ch, face = Font:getFace("smallinfofontbold", sizeFor(px)) }
            self.widgets[#self.widgets + 1] = self.glyphs[key]
        end
        return self.glyphs[key]
    end

    local function centred(bb, w, x, y, cw, chh)
        local sz = w:getSize()
        w:paintTo(bb, x + math.floor((cw - sz.w) / 2), y + math.floor(((chh or cw) - sz.h) / 2))
    end

    --- The picture on a card: a little puzzle of its kind in a square of side `d`.
    function Page:picture(bb, kind, x, y, d)
        local black = Blitbuffer.COLOR_BLACK
        local thin = math.max(1, math.floor(d / 120))
        if kind == "words" then
            local rows = { "GAMEBO", "RTWORD", "AXPUZL", "SEARCH", "ZLEFUN", "MQBOOK" }
            local c = math.floor(d / 6)
            for r, line in ipairs(rows) do
                for k = 1, 6 do
                    if c >= S(7) then centred(bb, self:glyph(line:sub(k, k), math.floor(c * 0.55)), x + (k - 1) * c, y + (r - 1) * c, c)
                    else bb:paintRect(x + (k - 1) * c + math.floor(c / 3), y + (r - 1) * c + math.floor(c / 3), 2, 2, shade(0.6)) end
                end
            end
            -- a word found: ringed
            bb:paintBorder(x + 1, y + 3 * c + math.floor(c * 0.1), c * 6 - 2, math.floor(c * 0.8), math.max(1, thin * 2), black, math.floor(c * 0.4))
            bb:paintBorder(x + 3 * c + math.floor(c * 0.1), y + 1, math.floor(c * 0.8), c * 3 - 2, math.max(1, thin * 2), black, math.floor(c * 0.4))
        elseif kind == "cross" then
            local n = 7
            local c = math.floor(d / n)
            local blacks = { [1] = true, [3] = true, [5] = true, [15] = true, [17] = true, [19] = true, [29] = true, [31] = true, [33] = true,
                [43] = true, [45] = true, [47] = true, [8] = true, [12] = true, [36] = true, [40] = true }
            for i = 0, n * n - 1 do
                local cx, cy = x + (i % n) * c, y + math.floor(i / n) * c
                if blacks[i] then bb:paintRect(cx, cy, c, c, black)
                else bb:paintBorder(cx, cy, c + thin, c + thin, thin, black) end
            end
            local word = "BOOK"
            for k = 1, 4 do
                if c >= S(8) then centred(bb, self:glyph(word:sub(k, k), math.floor(c * 0.55)), x + k * c, y + 3 * c, c) end
            end
            if c >= S(8) then
                for _i, at in ipairs({ 0, 2, 4, 6, 14, 28 }) do
                    bb:paintRect(x + (at % n) * c + thin * 2, y + math.floor(at / n) * c + thin * 2, math.max(2, math.floor(c / 6)), math.max(2, math.floor(c / 6)), shade(0.6))
                end
            end
        elseif kind == "maze" then
            local n = 7
            local m = Pz().maze("game board picture", n, n)
            local c = math.floor(d / n)
            local t = math.max(2, thin * 2)
            for i = 1, n * n do
                local open = m.cells[i] or 0
                local cx, cy = x + ((i - 1) % n) * c, y + math.floor((i - 1) / n) * c
                if open % 2 == 0 then bb:paintRect(cx, cy, c + t, t, black) end                          -- north
                if math.floor(open / 8) % 2 == 0 then bb:paintRect(cx, cy, t, c + t, black) end          -- west
                if i > n * (n - 1) and math.floor(open / 4) % 2 == 0 then bb:paintRect(cx, cy + c, c + t, t, black) end
                if i % n == 0 and math.floor(open / 2) % 2 == 0 then bb:paintRect(cx + c, cy, t, c + t, black) end
            end
            bb:paintCircle(x + math.floor(c / 2), y + math.floor(c / 2), math.max(2, math.floor(c / 4)), black)
            bb:paintRect(x + (n - 1) * c + math.floor(c / 3), y + (n - 1) * c + math.floor(c / 3), math.max(2, math.floor(c / 3)), math.max(2, math.floor(c / 3)), shade(0.4))
        elseif kind == "bingo" then
            -- a little card: five by five, a line of counters across it, a ball beside
            local n = 5
            local c = math.floor(d * 0.78 / n)
            local gx, gy = x, y + math.floor((d - c * n) / 2)
            for i = 0, n do
                bb:paintRect(gx + i * c, gy, thin, c * n + thin, black)
                bb:paintRect(gx, gy + i * c, c * n + thin, thin, black)
            end
            local dots = { { 0, 0 }, { 1, 1 }, { 2, 2 }, { 3, 3 }, { 4, 4 }, { 3, 0 }, { 0, 3 }, { 4, 1 } }
            for _i, p in ipairs(dots) do
                bb:paintCircle(gx + p[1] * c + math.floor(c / 2), gy + p[2] * c + math.floor(c / 2), math.max(2, math.floor(c * 0.34)), black)
            end
            local r = math.floor(d * 0.12)
            bb:paintCircle(x + d - r, y + r + math.floor(d * 0.06), r, black)
            bb:paintCircle(x + d - r, y + r + math.floor(d * 0.06), math.floor(r * 0.6), Blitbuffer.COLOR_WHITE)
        else -- the scramble: letter tiles, out of line
            local word = "PUZLE"
            local c = math.floor(d / 5.6)
            local r = math.max(2, math.floor(c / 6))
            local ups = { 0.15, -0.1, 0.2, -0.15, 0.05 }
            for k = 1, 5 do
                local tx = x + math.floor((d - c * 5.3) / 2) + (k - 1) * math.floor(c * 1.08)
                local ty = y + math.floor(d / 2 - c / 2 + ups[k] * c)
                bb:paintRoundedRect(tx + 2, ty + 2, c, c, shade(0.55), r)
                bb:paintRoundedRect(tx, ty, c, c, shade(0.08), r)
                bb:paintBorder(tx, ty, c, c, math.max(1, thin), black, r)
                centred(bb, self:glyph(word:sub(k, k), math.floor(c * 0.55)), tx, ty, c)
            end
        end
    end

    --- A trophy cup in a box `w` × `h`: dark when won, an outline when not.
    local function trophy(bb, x, y, w, h, won)
        local ink = won and Blitbuffer.COLOR_BLACK or shade(0.45)
        local cw = math.floor(w * 0.56)
        local cx = x + math.floor((w - cw) / 2)
        local bowl_h = math.floor(h * 0.46)
        local function bar(yy, ww, hh) bb:paintRect(x + math.floor((w - ww) / 2), yy, ww, hh, ink) end
        if won then
            for k = 0, bowl_h - 1 do
                local ww = math.floor(cw * (1 - 0.45 * (k / bowl_h) ^ 2))
                bar(y + k, ww, 1)
            end
        else
            bb:paintBorder(cx, y, cw, bowl_h, math.max(1, math.floor(w / 24)), ink, math.floor(cw / 3))
        end
        -- handles
        local hw = math.max(2, math.floor(w * 0.14))
        bb:paintBorder(cx - hw, y + math.floor(bowl_h * 0.12), hw + 1, math.floor(bowl_h * 0.5), math.max(1, math.floor(w / 28)), ink)
        bb:paintBorder(cx + cw - 1, y + math.floor(bowl_h * 0.12), hw + 1, math.floor(bowl_h * 0.5), math.max(1, math.floor(w / 28)), ink)
        -- stem and base
        bar(y + bowl_h, math.max(2, math.floor(w * 0.1)), math.floor(h * 0.24))
        bar(y + bowl_h + math.floor(h * 0.24), math.floor(w * 0.42), math.max(2, math.floor(h * 0.08)))
        bar(y + bowl_h + math.floor(h * 0.32), math.floor(w * 0.6), math.max(2, math.floor(h * 0.12)))
    end

    --- A die showing five, `d` across.
    local function die(bb, x, y, d)
        local r = math.floor(d / 6)
        bb:paintRoundedRect(x + 3, y + 3, d, d, shade(0.55), r)
        bb:paintRoundedRect(x, y, d, d, Blitbuffer.COLOR_WHITE, r)
        bb:paintBorder(x, y, d, d, math.max(2, S(2)), Blitbuffer.COLOR_BLACK, r)
        local p = math.max(2, math.floor(d / 11))
        for _i, at in ipairs({ { 0.27, 0.27 }, { 0.73, 0.27 }, { 0.5, 0.5 }, { 0.27, 0.73 }, { 0.73, 0.73 } }) do
            bb:paintCircle(x + math.floor(d * at[1]), y + math.floor(d * at[2]), p, Blitbuffer.COLOR_BLACK)
        end
    end

    function Page:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local W, H = self.dimen.w, self.dimen.h
        local f = self.frame
        local black = Blitbuffer.COLOR_BLACK
        -- the board: a dark frame, chequered at its corners, a light playing field
        bb:paintRect(x, y, W, H, shade(0.75))
        local sq = f
        for k = 0, 5 do
            for _i, corner in ipairs({ { 0, 0 }, { W - sq * 6, 0 }, { 0, H - f }, { W - sq * 6, H - f } }) do
                if k % 2 == 0 then bb:paintRect(x + corner[1] + k * sq, y + corner[2], sq, f, Blitbuffer.COLOR_WHITE) end
            end
        end
        bb:paintRect(x + f, y + f, W - f * 2, H - f * 2, shade(0.06))
        bb:paintBorder(x + f, y + f, W - f * 2, H - f * 2, math.max(1, S(1)), black)
        -- the banner
        local b = self.banner
        bb:paintRoundedRect(x + b.x + 3, y + b.y + 3, b.w, b.h, shade(0.55), S(4))
        bb:paintRoundedRect(x + b.x, y + b.y, b.w, b.h, black, S(4))
        b.title:paintTo(bb, x + b.x + S(12), y + b.y + math.floor((b.h - b.title:getSize().h) / 2))
        b.date:paintTo(bb, x + b.x + S(24) + b.title:getSize().w, y + b.y + math.floor((b.h - b.date:getSize().h) / 2))
        if self.close then
            local c = self.close
            local cx, cy, r = x + c.x + math.floor(c.d / 2), y + c.y + math.floor(c.d / 2), math.floor(c.d / 2)
            bb:paintCircle(cx + 2, cy + 2, r, shade(0.55))
            bb:paintCircle(cx, cy, r, Blitbuffer.COLOR_WHITE)
            bb:paintCircle(cx, cy, r, black, math.max(1, S(1)))
            local arm = math.floor(r * 0.45)
            for d = -arm, arm do
                bb:paintRect(cx + d - 1, cy + d - 1, 3, 3, black)
                bb:paintRect(cx + d - 1, cy - d - 1, 3, 3, black)
            end
        end
        -- the parts' labels
        local margin = self.banner.x
        for _i, l in ipairs(self.labels) do
            l.widget:paintTo(bb, x + margin, y + l.y)
            if l.right then l.right:paintTo(bb, x + self.dimen.w - margin - l.right:getSize().w, y + l.y + l.widget:getSize().h - l.right:getSize().h) end
            bb:paintRect(x + margin, y + l.y + l.widget:getSize().h + S(3), self.dimen.w - margin * 2, 1, shade(0.5))
        end
        -- the cards
        for _i, c in ipairs(self.cards) do
            local r = S(8)
            cardBox(bb, x + c.x, y + c.y, c.w, c.h, r)
            local name_h = c.name:getSize().h + (c.note and c.note:getSize().h or 0) + S(12)
            local d = math.min(c.w - S(24), c.h - name_h - S(20))
            local px, py = x + c.x + math.floor((c.w - d) / 2), y + c.y + S(12)
            self:picture(bb, c.kind, px, py, d)
            local ny = y + c.y + c.h - name_h + S(2)
            c.name:paintTo(bb, x + c.x + math.floor((c.w - c.name:getSize().w) / 2), ny)
            if c.note then c.note:paintTo(bb, x + c.x + math.floor((c.w - c.note:getSize().w) / 2), ny + c.name:getSize().h) end
            if c.done then
                -- a stamp: a ringed tick over the card's corner
                local sr = math.max(S(12), math.floor(c.w / 7))
                local sx, sy = x + c.x + c.w - sr - S(4), y + c.y + sr + S(4)
                bb:paintCircle(sx, sy, sr, black)
                bb:paintCircle(sx, sy, sr - math.max(2, S(2)), Blitbuffer.COLOR_WHITE)
                local tick = self:glyph("\u{2713}", math.floor(sr * 1.2))
                tick:paintTo(bb, sx - math.floor(tick:getSize().w / 2), sy - math.floor(tick:getSize().h / 2))
                bb:lightenRect(x + c.x + S(6), y + c.y + S(6), c.w - sr * 2 - S(14), c.h - name_h - S(12), 0.5)
            end
        end
        -- the theme's lid and the die
        local lid = self.lid
        cardBox(bb, x + lid.x, y + lid.y, lid.w, lid.h, S(6), shade(0.2))
        bb:paintRect(x + lid.x + S(6), y + lid.y + S(6), lid.w - S(12), lid.h - S(12), Blitbuffer.COLOR_WHITE)
        local th = lid.small:getSize().h + lid.title:getSize().h
        local ty = y + lid.y + math.floor((lid.h - th) / 2)
        lid.small:paintTo(bb, x + lid.x + S(14), ty)
        lid.title:paintTo(bb, x + lid.x + S(14), ty + lid.small:getSize().h)
        lid.count:paintTo(bb, x + lid.x + lid.w - S(14) - lid.count:getSize().w, y + lid.y + math.floor((lid.h - lid.count:getSize().h) / 2))
        local dd = self.die
        local dsz = math.min(dd.w, dd.h) - dd.label:getSize().h - S(4)
        die(bb, x + dd.x + math.floor((dd.w - dsz) / 2), y + dd.y, dsz)
        dd.label:paintTo(bb, x + dd.x + math.floor((dd.w - dd.label:getSize().w) / 2), y + dd.y + dsz + S(3))
        -- the trophy cabinet: glass-fronted shelves, a cup for every achievement
        local cab = self.cab
        cardBox(bb, x + cab.x, y + cab.y, cab.w, cab.h, S(6), shade(0.6))
        local ix, iy, iw, ih = x + cab.x + S(8), y + cab.y + S(8) + cab.title:getSize().h + S(6), cab.w - S(16), cab.h - S(16) - cab.title:getSize().h - S(6)
        bb:paintRect(x + cab.x + S(8), y + cab.y + S(6), cab.w - S(16), cab.title:getSize().h + S(4), Blitbuffer.COLOR_WHITE)
        cab.title:paintTo(bb, x + cab.x + math.floor((cab.w - cab.title:getSize().w) / 2), y + cab.y + S(8))
        bb:paintRect(ix, iy, iw, ih, shade(0.1))
        local n = #cab.trophies
        local best_cols, best_size = 1, 0
        for cols = 1, n do
            local rows = math.ceil(n / cols)
            local size = math.min(math.floor(iw / cols), math.floor(ih / rows))
            if size > best_size then best_cols, best_size = cols, size end
        end
        local cols, size = best_cols, best_size
        local rows = math.ceil(n / cols)
        local row_h = math.floor(ih / rows)
        local ox = ix + math.floor((iw - cols * size) / 2)
        for i, t in ipairs(cab.trophies) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            local ty2 = iy + row * row_h
            trophy(bb, ox + col * size + math.floor(size * 0.12), ty2 + math.floor((row_h - size) / 2) + math.floor(size * 0.1), math.floor(size * 0.76), math.floor(size * 0.76), t.at ~= nil)
            if col == 0 then bb:paintRect(ix, ty2 + row_h - math.max(2, S(3)), iw, math.max(2, S(3)), shade(0.6)) end
        end
        -- the score card: ruled paper, a margin line, the last finishes
        local sc = self.score
        cardBox(bb, x + sc.x, y + sc.y, sc.w, sc.h, S(4))
        local tx = x + sc.x + S(22)
        sc.title:paintTo(bb, tx, y + sc.y + S(8))
        local ly = y + sc.y + S(8) + sc.title:getSize().h
        sc.sum:paintTo(bb, tx, ly)
        ly = ly + sc.sum:getSize().h + S(10)
        local red = require("gzreader_dailyscreen").ink(require("gzreader_dailyscreen").MAST_COLOR)
        if red and bb.paintRectRGB32 then bb:paintRectRGB32(x + sc.x + S(14), y + sc.y + S(2), math.max(1, S(1)), sc.h - S(4), red)
        else bb:paintRect(x + sc.x + S(14), y + sc.y + S(2), math.max(1, S(1)), sc.h - S(4), shade(0.5)) end
        local k = 0
        while ly + k * sc.line_h + sc.line_h < y + sc.y + sc.h - S(4) do
            bb:paintRect(x + sc.x + S(4), ly + (k + 1) * sc.line_h - 1, sc.w - S(8), 1, shade(0.3))
            local line = sc.lines[k + 1]
            if line then line:paintTo(bb, tx, ly + k * sc.line_h + sc.line_h - line:getSize().h - S(3)) end
            k = k + 1
        end
        -- the frame round what Press would open
        if self.keys then
            local t = self.items[self.focus]
            if t then bb:paintBorder(x + t.x - S(4), y + t.y - S(4), t.w + S(8), t.h + S(8), math.max(3, S(3)), black, S(10)) end
        end
        if self.hint then self.hint.widget:paintTo(bb, x + margin, y + self.hint.y) end
    end

    function Page:rebuild()
        if self.closed then return end
        self:build()
        UIManager:setDirty(self, "ui")
    end

    function Page:open(kind, set)
        PzScreen().show(self.plugin, kind, set and { set = set } or { kinds = Pz().BOARD_KINDS })
        return true
    end

    function Page:viewer(title, text)
        UIManager:show(require("ui/widget/textviewer"):new{ title = title, text = text, justified = false })
        return true
    end

    function Page:at_(px, py)
        local c = self.close
        if c and px >= c.x - S(8) and px < c.x + c.d + S(8) and py >= c.y - S(8) and py < c.y + c.d + S(8) then return "close" end
        for i, t in ipairs(self.items) do
            if px >= t.x and px < t.x + t.w and py >= t.y and py < t.y + t.h then return i end
        end
    end

    function Page:onGbTap(_arg, ges)
        local what = self:at_(ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y)
        if what == "close" then return self:onGbClose() end
        if what then return self.items[what].run() end
        return true
    end

    function Page:onGbSwipe(_arg, ges)
        local Paper = require("gzreader_dailyscreen")
        if Paper.pulledDown(ges) then return Paper.openPanel(self.plugin) end
        return false
    end

    function Page:onGbMove(side)
        local cur = self.items[self.focus]
        if not cur then return true end
        local best, best_d
        for i, t in ipairs(self.items) do
            if i ~= self.focus then
                local ok
                if side == "e" then ok = t.row == cur.row and t.x > cur.x
                elseif side == "w" then ok = t.row == cur.row and t.x < cur.x
                elseif side == "s" then ok = t.row == cur.row + 1
                else ok = t.row == cur.row - 1 end
                if ok then
                    local d = math.abs(t.x + t.w / 2 - (cur.x + cur.w / 2)) + math.abs(t.y - cur.y)
                    if not best_d or d < best_d then best, best_d = i, d end
                end
            end
        end
        if best then
            self.focus = best
            UIManager:setDirty(self, "ui")
        end
        return true
    end

    function Page:onGbPress()
        local t = self.items[self.focus]
        if t then return t.run() end
        return true
    end

    function Page:onGbPanel() return require("gzreader_dailyscreen").openPanel(self.plugin, "Menu") end

    function Page:onGbClose()
        UIManager:close(self, "full")
        return true
    end

    function Page:onCloseWidget()
        self.closed = true
        self:freeWidgets()
        if Screen_.instance == self then Screen_.instance = nil end
        pcall(function() self.plugin:save() end)
        Screen_.redrawHome()
    end

    return Page
end

--- Open the game board.
function Screen_.show(plugin)
    if Screen_.instance and not Screen_.instance.closed then return Screen_.instance end
    local self = pageClass():new{ plugin = plugin }
    Screen_.instance = self
    UIManager:show(self)
    require("gzreader_log").info("game board: opened")
    return self
end

---------------------------------------------------------------- Settings → Home and tabs → Game board

function Screen_.settingsItems(plugin)
    local B = Board()
    return {
        {
            text = _("Game board on Home's bookshelf"),
            help_text = _("A box of puzzles stands on Home's bookshelf beside the daily paper (Home's Bookshelf view). Tap it to see its lid, again to open it: today's paper puzzles (the same ones as in the paper), and a crossword, a word search, a word scramble and a maze on a theme you choose: words from the book you're reading or several of your books, the season, a category, or a theme the AI finds in your books. With achievements and a history of the puzzles you've finished. Everything is made on this Kindle; only asking the AI for a theme sends anything (your books' titles and authors, to the AI service you set up)."),
            checked_func = function() return B.enabled(plugin) end,
            callback = function()
                B.setEnabled(plugin, not B.enabled(plugin))
                Screen_.redrawHome()
            end,
        },
        { text = _("Open the game board"), keep_menu_open = true, callback = function() Screen_.show(plugin) end },
    }
end

return Screen_
