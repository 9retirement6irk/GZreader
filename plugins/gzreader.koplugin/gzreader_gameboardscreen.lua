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

--- The paper's puzzles done today, and how many there are.
function Screen_.paperDone(plugin)
    local ok, out, n = pcall(Pz().finished, plugin)
    if not ok then return {}, 0, #Pz().KINDS end
    return out, n, #Pz().KINDS
end

--- The themed set's puzzles done, and how many there are.
function Screen_.setDone(plugin, set)
    local pz = Pz().forSet(plugin, set)
    local ok, out, n = pcall(Pz().finished, pz)
    if not ok then return {}, 0, #Pz().kindsOf(pz) end
    return out, n, #Pz().kindsOf(pz)
end

--- The lid's lines: { "Today's paper 2/4", "Autumn 1/4", "★ 3/22" }.
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

    --- Lay it out: the heading, then sections of tiles and buttons (self.items,
    --- each { x, y, w, h, label, sub, run, row }).
    function Page:build()
        self:freeWidgets()
        local B = Board()
        local plugin = self.plugin
        local W, H = self.dimen.w, self.dimen.h
        local margin = S(12)
        local room = W - margin * 2
        self.close_w = self.touch and S(44) or 0
        local title = self:text(_("GAME BOARD"), face("NotoSerif-Bold.ttf", 18, "smallinfofontbold"))
        local date = self:text(require("gzreader_dailyscreen").dateText(os.time()), face("NotoSerif-Italic.ttf", 9, "smallinfofont"),
            room - margin - title:getSize().w - self.close_w)
        self.head = { title = title, date = date, y = S(8), h = title:getSize().h }
        local y = self.head.y + self.head.h + S(6)
        self.rule_y = y
        y = y + S(3) + S(12)
        self.items, self.heads = {}, {}
        local head_face = face("NotoSerif-Bold.ttf", 10, "smallinfofontbold")
        local label_face = Font:getFace("smallinfofontbold", 12)
        local sub_face = Font:getFace("smallinfofont", 9)
        local row = 0
        local function heading(str)
            local w = self:text(str, head_face, room)
            self.heads[#self.heads + 1] = { widget = w, y = y }
            y = y + w:getSize().h + S(6)
        end
        local function tiles(list)
            row = row + 1
            local n = #list
            local gap = S(8)
            local tw = math.floor((room - gap * (n - 1)) / n)
            local th = S(56)
            local lh = 0
            for _i, t in ipairs(list) do
                t.label_w = self:text(t.label, label_face, tw - S(10))
                t.sub_w = t.sub and self:text(t.sub, sub_face, tw - S(10)) or nil
                lh = math.max(lh, t.label_w:getSize().h + (t.sub_w and t.sub_w:getSize().h + S(4) or 0))
            end
            th = math.max(th, lh + S(16))
            for i, t in ipairs(list) do
                t.x, t.y, t.w, t.h, t.row = margin + (i - 1) * (tw + gap), y, tw, th, row
                self.items[#self.items + 1] = t
            end
            y = y + th + S(12)
        end
        -- today's paper puzzles: the paper's own
        local pdone, pn, pof = Screen_.paperDone(plugin)
        heading(T(_("TODAY'S PAPER PUZZLES · %1/%2"), pn, pof))
        local list = {}
        for _i, kind in ipairs(Pz().KINDS) do
            list[#list + 1] = { label = PzScreen().tabLabel(kind), sub = pdone[kind] and _("Done \u{2713}") or nil, done = pdone[kind],
                run = function() return self:open(kind) end }
        end
        tiles(list)
        -- the themed set
        local set = B.current(plugin)
        local sdone, sn, sof = Screen_.setDone(plugin, set)
        heading(T(_("THEME: %1 · %2/%3"), tostring(set.title or ""):upper(), sn, sof))
        list = {}
        for _i, kind in ipairs(Pz().kindsOf(Pz().forSet(plugin, set))) do
            list[#list + 1] = { label = PzScreen().tabLabel(kind), sub = sdone[kind] and _("Done \u{2713}") or nil, done = sdone[kind],
                run = function() return self:open(kind, set) end }
        end
        tiles(list)
        tiles({
            { label = _("Choose a theme"), sub = _("Your books, seasons, categories, AI"), run = function()
                Screen_.chooseTheme(plugin, function() self:rebuild() end)
                return true
            end },
            { label = _("New puzzles"), sub = _("The same theme, new puzzles"), run = function()
                B.again(plugin)
                self:rebuild()
                return true
            end },
        })
        -- records
        local an = select(2, B.achievements(plugin))
        local stats = B.store(plugin).stats
        heading(_("RECORDS"))
        tiles({
            { label = T(_("\u{2605} Achievements %1/%2"), an, #B.ACHIEVEMENTS), run = function() return self:viewer(_("Achievements"), B.achievementsText(plugin)) end },
            { label = _("History"), sub = (function()
                local run = B.streak(stats.days, os.date("%Y-%m-%d"))
                return T(_("%1 finished"), stats.total or 0) .. " · " .. (run == 1 and _("1 day running") or T(_("%1 days running"), run))
            end)(),
              run = function() return self:viewer(_("History"), B.historyText(plugin)) end },
        })
        if self.focus > #self.items then self.focus = #self.items end
        local small = Font:getFace("smallinfofont", 10)
        local help = self.touch and _("Tap a puzzle to play. The paper's puzzles are the same here and in the paper.")
            or _("5-way: move · Press: open · Back: close")
        local help_w = self:text(help, small, room)
        self.foot = { help = help_w, y = H - S(8) - help_w:getSize().h }
        -- the room left: the puzzles finished last, as many as fit
        self.recent = {}
        local history = B.store(plugin).history
        local line_face = Font:getFace("smallinfofont", 11)
        local probe = self:text("Ag", line_face)
        local line_h = probe:getSize().h + S(8)
        local head_h = self:text("A", head_face):getSize().h + S(6)
        local room_lines = math.floor((self.foot.y - S(10) - y - head_h) / line_h)
        if #history > 0 and room_lines >= 2 then
            heading(_("FINISHED LATELY"))
            for i = 1, math.min(#history, room_lines - 1) do
                local h = history[i]
                local took = B.tookText(h.d)
                local when = os.date("%d %b", h.t):gsub("^0", "")
                local line = when .. "  ·  " .. B.kindName(h.k) .. "  ·  " .. (h.s or _("the daily paper")) .. (took and ("  ·  " .. took) or "")
                self.recent[#self.recent + 1] = { widget = self:text(line, line_face, room), y = y }
                y = y + line_h
            end
        end
    end

    function Page:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local W, H = self.dimen.w, self.dimen.h
        local margin = S(12)
        bb:paintRect(x, y, W, H, Blitbuffer.COLOR_WHITE)
        local h = self.head
        h.title:paintTo(bb, x + margin, y + h.y)
        h.date:paintTo(bb, x + margin + h.title:getSize().w + margin, y + h.y + h.h - h.date:getSize().h - S(3))
        local red = require("gzreader_dailyscreen").ink(require("gzreader_dailyscreen").MAST_COLOR)
        if red and bb.paintRectRGB32 then bb:paintRectRGB32(x + margin, y + self.rule_y, W - margin * 2, S(3), red)
        else bb:paintRect(x + margin, y + self.rule_y, W - margin * 2, S(3), Blitbuffer.COLOR_BLACK) end
        if self.close_w > 0 then
            local cx, cy, arm = x + W - math.floor(self.close_w / 2), y + math.floor(self.close_w / 2), S(7)
            for d = -arm, arm do
                bb:paintRect(cx + d, cy + d, 2, 2, Blitbuffer.COLOR_BLACK)
                bb:paintRect(cx + d, cy - d, 2, 2, Blitbuffer.COLOR_BLACK)
            end
        end
        for _i, hd in ipairs(self.heads) do hd.widget:paintTo(bb, x + margin, y + hd.y) end
        for _i, r in ipairs(self.recent or {}) do r.widget:paintTo(bb, x + margin, y + r.y) end
        for i, t in ipairs(self.items) do
            if t.done then bb:paintRect(x + t.x, y + t.y, t.w, t.h, Blitbuffer.COLOR_GRAY_E) end
            local focused = self.keys and i == self.focus
            bb:paintBorder(x + t.x, y + t.y, t.w, t.h, focused and S(3) or 1, Blitbuffer.COLOR_BLACK, S(6))
            local lh = t.label_w:getSize().h + (t.sub_w and t.sub_w:getSize().h + S(4) or 0)
            local ty = y + t.y + math.floor((t.h - lh) / 2)
            t.label_w:paintTo(bb, x + t.x + math.floor((t.w - t.label_w:getSize().w) / 2), ty)
            if t.sub_w then t.sub_w:paintTo(bb, x + t.x + math.floor((t.w - t.sub_w:getSize().w) / 2), ty + t.label_w:getSize().h + S(4)) end
        end
        bb:paintRect(x + margin, y + self.foot.y - S(5), W - margin * 2, 1, Blitbuffer.COLOR_BLACK)
        self.foot.help:paintTo(bb, x + margin, y + self.foot.y)
    end

    function Page:rebuild()
        if self.closed then return end
        self:build()
        UIManager:setDirty(self, "ui")
    end

    function Page:open(kind, set)
        PzScreen().show(self.plugin, kind, set and { set = set } or nil)
        return true
    end

    function Page:viewer(title, text)
        UIManager:show(require("ui/widget/textviewer"):new{ title = title, text = text, justified = false })
        return true
    end

    function Page:at_(px, py)
        if self.close_w > 0 and px >= self.dimen.w - self.close_w and py <= self.close_w then return "close" end
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

---------------------------------------------------------------- Settings → Home and tabs → Home

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
