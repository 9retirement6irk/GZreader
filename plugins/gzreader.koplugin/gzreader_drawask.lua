--[[--
A pen pal on a drawing's page (after rocoloco/pen-pal, MIT; no code taken):
write a question, a note or a few sums with the pen, tap ✦ in the top bar,
and the AI (Settings → Accounts and services → AI) writes back under each,
in a handwriting font (Caveat) about the size of your writing.

What's asked: the writing that hasn't been asked about yet (not inside an
earlier question's area). Its separate pieces (`Ask.pieces`: strokes close
together) are boxed and numbered in one black-and-white picture of that
writing alone (gzreader_handwriting's), never the rest of the page; the AI
answers in JSON, one reply per question (which may take several boxes: the
lines of one question) and says what each one reads. Each reply goes under
its own question, as wide as the room to its right. What earlier questions
said and their replies on the page go with the next ask, so "what is the
square root of it?" follows on.

Each answer is a text box with `customData.gzAsk`:
  { state = "waiting" | "answer", q = { x0, y0, x1, y1 }, read = "…" }
`q`: its question's area in scene units (a waiting box: all of what was
asked). A box still waiting (no Wi-Fi, or the drawing closed before the
answer came) keeps its place and is asked again when ✦ is tapped, or when
the page opens with Wi-Fi on. The eraser takes an answer off (gzreader_sketch's
Sketch.answerAt). Memos shows the boxes as text boxes (a cursive font).
]]

local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local Ask = {
    FONT = "'Caveat', cursive", -- (memos: a CSS font list; on the Kindle, fonts/Caveat-Regular.ttf, OFL)
    SIZE = 28, -- scene units, when the writing's size can't be told
    MIN_SIZE = 18, MAX_SIZE = 72,
    LETTER = 1.25, -- the font size for writing whose letters are this many times smaller
    MAX_TOKENS = 600,
    MAX_WORDS = 30, -- a reply longer than this is cut at a sentence (the AI is asked for about 20)
    MARGIN = 8, -- canvas px kept clear round a reply and inside the page's edges
    GAP = 6, -- scene units between a question and its answer
    HISTORY = 8, -- earlier questions and replies sent along
}

Ask.SYSTEM = "You are a friendly pen pal writing back on a page of someone's handwritten notebook. "
    .. "Reply warmly and briefly, in plain words: no Markdown, no lists, no headings. "
    .. "Keep every reply short, like a note in a margin: one or two sentences, about 20 words at most. "
    .. "For a sum or a maths problem, the reply is its result (with a short working only when it helps). "
    .. "Use what was said earlier on the page: a question can follow on from an earlier one."

--- What's asked: `n` boxes, `history` = { { read, reply }, … } (earlier on the page).
function Ask.prompt(n, history)
    local lines = {}
    if history and #history > 0 then
        lines[#lines + 1] = "Earlier on this page:"
        for _i, h in ipairs(history) do
            lines[#lines + 1] = "They wrote: " .. tostring(h.read or "(not known)")
            lines[#lines + 1] = "You replied: " .. tostring(h.reply or "")
        end
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = string.format("The picture is what they wrote next. Each separate piece of writing is in a box"
        .. " numbered 1 to %d. One question can take several boxes (its lines); a box can be a sum.", n)
    lines[#lines + 1] = 'Answer with JSON only: {"replies":[{"boxes":[numbers],"read":"what that writing says","reply":"your reply"}]}'
        .. " with one reply for each question, sum or note, in the order written."
    return table.concat(lines, "\n")
end

--- Is the AI set up (so ✦ is offered)?
function Ask.available(plugin)
    if not plugin then return false end
    local ok, provider = pcall(function() return require("gzreader_ai").provider(plugin) end)
    return ok and provider ~= nil
end

--- A pen pal's box (its customData.gzAsk), or nil.
function Ask.info(el)
    local cd = type(el) == "table" and el.customData
    local a = type(cd) == "table" and cd.gzAsk
    return type(a) == "table" and a or nil
end

---------------------------------------------------------------- the handwriting font

local here = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$") or "plugins/gzreader.koplugin"
Ask.FONT_FILE = here:gsub("^%./", "") .. "/fonts/Caveat-Regular.ttf"

-- KOReader opens a font name as <its fonts folder>/<name> (as gzreader_sticky's)
local font_name
local function fontName()
    if font_name ~= nil then return font_name or nil end
    font_name = false
    local ok, FontList = pcall(require, "fontlist")
    local fontdir = (ok and type(FontList) == "table" and FontList.fontdir) or "./fonts"
    local name
    if Ask.FONT_FILE:match("^/") then
        name = Ask.FONT_FILE
    elseif not fontdir:match("^/") then
        local depth = select(2, fontdir:gsub("^%./", ""):gsub("[^/]+", ""))
        name = string.rep("../", depth) .. Ask.FONT_FILE
    end
    local f = name and io.open(name:match("^/") and name or (fontdir .. "/" .. name), "rb")
    if f then f:close(); font_name = name end
    return font_name or nil
end

--- The face box `el` is drawn in at `size`: Caveat for a pen pal's answer (or
--- a box in Caveat from memos), Patrick Hand for one in that; nil: the usual.
function Ask.face(el, size)
    local fam = type(el) == "table" and type(el.fontFamily) == "string" and el.fontFamily or ""
    if fam:find("Patrick Hand", 1, true) then return require("gzreader_sticky").hand(size) end
    if Ask.info(el) or fam:find("Caveat", 1, true) then
        local name = fontName()
        local face = name and require("ui/font"):getFace(name, size)
        return face or require("gzreader_sticky").hand(size)
    end
    return nil
end

function Ask.isHand(el) return Ask.face(el, 20) ~= nil end

---------------------------------------------------------------- pure parts (run_tests.lua)

--- The boxes still waiting for an answer among `texts`.
function Ask.waiting(texts)
    local out = {}
    for _i, el in ipairs(texts or {}) do
        local a = Ask.info(el)
        if a and a.state == "waiting" then out[#out + 1] = el end
    end
    return out
end

--- Earlier questions and their replies on the page, top to bottom (the last HISTORY).
function Ask.history(texts)
    local list = {}
    for _i, el in ipairs(texts or {}) do
        local a = Ask.info(el)
        if a and a.state == "answer" then list[#list + 1] = el end
    end
    table.sort(list, function(a, b) return (tonumber(a.y) or 0) < (tonumber(b.y) or 0) end)
    local out = {}
    for i = math.max(1, #list - Ask.HISTORY + 1), #list do
        out[#out + 1] = { read = Ask.info(list[i]).read, reply = list[i].text }
    end
    return out
end

local function inside(b, r)
    local cx, cy = (b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2
    return cx >= r[1] and cx <= r[3] and cy >= r[2] and cy <= r[4]
end

--- The writing not asked about yet: strokes whose middle isn't inside an
--- earlier question's area (`areas`: canvas { x0, y0, x1, y1 } lists).
function Ask.unasked(strokes, areas, box)
    local out = {}
    for _i, st in ipairs(strokes or {}) do
        local b = box(st)
        local asked = false
        for _j, r in ipairs(areas or {}) do if b and inside(b, r) then asked = true; break end end
        if b and not asked then out[#out + 1] = st end
    end
    return out
end

--- The strokes inside canvas rectangle `r`.
function Ask.within(strokes, r, box)
    local out = {}
    for _i, st in ipairs(strokes or {}) do
        local b = box(st)
        if b and b.x1 >= r[1] - 2 and b.x0 <= r[3] + 2 and b.y1 >= r[2] - 2 and b.y0 <= r[4] + 2 then out[#out + 1] = st end
    end
    return out
end

--- How tall the letters are: the middle stroke's height (canvas px), or nil.
function Ask.letterHeight(strokes, box)
    local hs = {}
    for _i, st in ipairs(strokes or {}) do
        local b = box(st)
        if b then hs[#hs + 1] = b.y1 - b.y0 end
    end
    if #hs == 0 then return nil end
    table.sort(hs)
    return hs[math.floor((#hs + 1) / 2)]
end

--- The writing's separate pieces: strokes near each other (a word's letters,
--- a sum's lines) together; reading order (top to bottom, then left to
--- right). Each: { strokes, x0, y0, x1, y1 } (canvas).
function Ask.pieces(strokes, box)
    local lh = Ask.letterHeight(strokes, box) or 20
    local gx, gy = lh * 1.6, lh * 0.45 -- (across: a word's gap; down: less than a ruled line's)
    local items = {}
    for _i, st in ipairs(strokes) do
        local b = box(st)
        if b then items[#items + 1] = { strokes = { st }, x0 = b.x0, y0 = b.y0, x1 = b.x1, y1 = b.y1 } end
    end
    local merged = true
    while merged do
        merged = false
        for i = 1, #items do
            local a = items[i]
            for j = #items, i + 1, -1 do
                local b = items[j]
                if b.x0 <= a.x1 + gx and a.x0 <= b.x1 + gx and b.y0 <= a.y1 + gy and a.y0 <= b.y1 + gy then
                    for _k, st in ipairs(b.strokes) do a.strokes[#a.strokes + 1] = st end
                    a.x0, a.y0, a.x1, a.y1 = math.min(a.x0, b.x0), math.min(a.y0, b.y0), math.max(a.x1, b.x1), math.max(a.y1, b.y1)
                    table.remove(items, j)
                    merged = true
                end
            end
        end
    end
    table.sort(items, function(a, b)
        if a.y1 < b.y0 then return true end
        if b.y1 < a.y0 then return false end
        return a.x0 < b.x0
    end)
    return items
end

-- seven-segment digits for the boxes' numbers: segments a..g as (x0, y0, x1, y1) in a 1 x 2 cell
local SEG = { a = { 0, 0, 1, 0 }, b = { 1, 0, 1, 1 }, c = { 1, 1, 1, 2 }, d = { 0, 2, 1, 2 }, e = { 0, 1, 0, 2 }, f = { 0, 0, 0, 1 }, g = { 0, 1, 1, 1 } }
local DIGITS = { ["0"] = "abcdef", ["1"] = "bc", ["2"] = "abged", ["3"] = "abgcd", ["4"] = "fgbc", ["5"] = "afgcd",
    ["6"] = "afgedc", ["7"] = "abc", ["8"] = "abcdefg", ["9"] = "abcdfg" }

--- The flat strokes (gzreader_handwriting's) for number `n` at (x, y), each digit `h` high.
function Ask.number(n, x, y, h)
    local out = {}
    local w = h / 2
    local i = 0
    for ch in tostring(n):gmatch("%d") do
        for seg in DIGITS[ch]:gmatch(".") do
            local s = SEG[seg]
            local ox = x + i * (w + h * 0.35)
            out[#out + 1] = { ox + s[1] * w, y + s[2] * w, ox + s[3] * w, y + s[4] * w }
        end
        i = i + 1
    end
    return out
end

--- The picture's strokes: the writing, a box round each piece and its number left of it.
function Ask.pictureStrokes(pieces, flat, pad)
    local out = {}
    for _i, f in ipairs(flat) do out[#out + 1] = f end
    for i, p in ipairs(pieces) do
        local x0, y0, x1, y1 = p.x0 - pad, p.y0 - pad, p.x1 + pad, p.y1 + pad
        out[#out + 1] = { x0, y0, x1, y0, x1, y1, x0, y1, x0, y0 }
        local h = pad * 2.2
        local digits = #tostring(i)
        for _j, d in ipairs(Ask.number(i, x0 - pad * 0.6 - digits * h * 0.85, y0, h)) do out[#out + 1] = d end
    end
    return out
end

--- The answer's text made tidy: plain, its blank lines kept to one, trimmed;
--- nil when there's nothing in it.
function Ask.clean(text)
    if type(text) ~= "string" then return nil end
    local t = text:gsub("\r", ""):gsub("%*%*(.-)%*%*", "%1"):gsub("\n%s*\n[%s\n]*", "\n\n")
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    if t == "" then return nil end
    return t
end

--- `text` cut to `max` words (Ask.MAX_WORDS): whole sentences while they fit,
--- else the first `max` words and "…". Pure.
function Ask.short(text, max)
    max = max or Ask.MAX_WORDS
    if type(text) ~= "string" then return text end
    local n = 0
    for _w in text:gmatch("%S+") do n = n + 1 end
    if n <= max then return text end
    local out, count = {}, 0
    for sentence in text:gmatch("[^%.!?]+[%.!?]*%s*") do
        local words = 0
        for _w in sentence:gmatch("%S+") do words = words + 1 end
        if count + words > max then break end
        out[#out + 1] = sentence
        count = count + words
    end
    if #out > 0 then return (table.concat(out):gsub("%s+$", "")) end
    local words = {}
    for w in text:gmatch("%S+") do
        if #words == max then break end
        words[#words + 1] = w
    end
    return (table.concat(words, " "):gsub("[%s,;:]+$", "")) .. "…"
end

--- The AI's answer for `n` boxes: { { boxes = { i… }, read, reply }, … }.
--- Not JSON (or none of it usable): one reply for all of them, its text.
function Ask.parse(text, n)
    local all = {}
    for i = 1, n do all[i] = i end
    if type(text) ~= "string" then return {} end
    local body = text:match("%b{}")
    local ok, data = pcall(function() return body and require("gzreader_json").decode(body) end)
    local out = {}
    if ok and type(data) == "table" and type(data.replies) == "table" then
        local used = {}
        for _i, r in ipairs(data.replies) do
            local reply = type(r) == "table" and Ask.clean(r.reply)
            if reply then
                local boxes = {}
                for _j, b in ipairs(type(r.boxes) == "table" and r.boxes or {}) do
                    b = tonumber(b)
                    if b and b >= 1 and b <= n and not used[b] then boxes[#boxes + 1] = math.floor(b); used[b] = true end
                end
                out[#out + 1] = { boxes = boxes, read = type(r.read) == "string" and r.read or nil, reply = Ask.short(reply) }
            end
        end
        -- (a reply naming no box of its own: the boxes no reply took)
        for _i, r in ipairs(out) do
            if #r.boxes == 0 then
                for b = 1, n do if not used[b] then r.boxes[#r.boxes + 1] = b; used[b] = true end end
            end
        end
        if #out > 0 then return out end
    end
    local plain = Ask.clean(text)
    return plain and { { boxes = all, reply = Ask.short(plain) } } or {}
end

-- (the boxes being asked about now: not kept in the drawing, so a box saved
-- while asking is asked again when it's opened)
Ask.busy = setmetatable({}, { __mode = "k" })

Ask.THINKING = _("✦ …")

---------------------------------------------------------------- on the drawing screen

local function round(v) return require("gzreader_drawing").round2(v) end

--- The canvas areas already asked about on the page (answers' and waiting boxes' `q`).
local function askedAreas(sk)
    local out = {}
    for _i, el in ipairs(sk:liveTexts()) do
        local a = Ask.info(el)
        if a and type(a.q) == "table" then
            local x0, y0 = sk:toCanvas(a.q[1], a.q[2])
            local x1, y1 = sk:toCanvas(a.q[3], a.q[4])
            out[#out + 1] = { x0, y0, x1, y1 }
        end
    end
    return out
end

--- The font size (scene units) for writing whose letters are `lh` canvas px high.
function Ask.sizeFor(lh, per_unit)
    if not lh or lh <= 0 then return Ask.SIZE end
    return math.max(Ask.MIN_SIZE, math.min(Ask.MAX_SIZE, math.floor(lh / per_unit * Ask.LETTER + 0.5)))
end

--- A box for a reply under canvas area `r` (x0, y0, x1, y1), `room` px wide at most, its text `size`.
function Ask.box(screen, r, room, text, size, info)
    local DrawText = require("gzreader_drawtext")
    local sk = screen.sketch
    local sx, sy = sk:toScene(r.x0, r.y1)
    local el = DrawText.element(sx, sy + Ask.GAP, math.max(DrawText.MIN_WIDTH, room / sk.per_unit), text, nil, size)
    el.fontFamily = Ask.FONT
    el.customData = { gzAsk = info }
    el.height = round(math.max(el.height, screen:textHeight(el)))
    return el
end

--- Where the page's writing room ends on the right (canvas px): the paper's
--- edge less a margin, or most of the canvas on a blank page.
function Ask.rightEdge(screen)
    local pr = screen.sketch.pageRect and screen.sketch:pageRect()
    if pr and pr.w > 0 then return pr.x + pr.w - math.max(12, pr.w * 0.03) end
    return screen.canvas.w * 0.94
end

--- The room to the right of piece `p` among `all` (canvas px): up to the next
--- piece beside it, else `right_edge`.
function Ask.room(p, all, right_edge)
    local right = right_edge
    for _i, o in ipairs(all) do
        if o ~= p and o.x0 > p.x1 and o.y0 < p.y1 + (p.y1 - p.y0) * 2 and o.y1 > p.y0 then right = math.min(right, o.x0 - 8) end
    end
    local w = right - p.x0
    -- (too narrow to be read: up to the edge)
    if w < right_edge * 0.22 then w = right_edge - p.x0 end
    return w
end

--- Where a reply goes, canvas { x, y, w, h }: under question area `q` (as
--- wide as `room`); else beside it on the right; else the free place nearest
--- under it on `view` (the page as it's seen: { x0, y0, x1, y1 }). Never over
--- writing or another box (`taken`: canvas { x0, y0, x1, y1 }), never past
--- the view's edges. `measure(w)` is the text's height at width w. nil: no room.
function Ask.spot(q, room, measure, taken, view, gap)
    local pad = Ask.MARGIN
    -- (the question itself is taken too)
    local list = { q }
    for _i, o in ipairs(taken) do list[#list + 1] = o end
    taken = list
    local min_w = math.min(room, (view.x1 - view.x0) * 0.3)
    local function free(r)
        if r.x < view.x0 - 0.5 or r.y < view.y0 - 0.5 or r.x + r.w > view.x1 + 0.5 or r.y + r.h > view.y1 + 0.5 then return false end
        for _i, o in ipairs(taken) do
            if r.x < o.x1 + pad and r.x + r.w > o.x0 - pad and r.y < o.y1 + pad and r.y + r.h > o.y0 - pad then return false end
        end
        return true
    end
    local function try(x, y, w)
        w = math.min(w, view.x1 - x)
        if w < min_w then return nil end
        local r = { x = x, y = y, w = w, h = measure(w) }
        return free(r) and r or nil
    end
    local first = try(q.x0, q.y1 + gap, room) or try(q.x1 + gap * 2, q.y0, view.x1 - q.x1 - gap * 2)
    if first then return first end
    local best, best_d
    local step = math.max(8, (q.y1 - q.y0) / 2)
    local half = (view.x1 - view.x0) / 2
    local xs = { q.x0, view.x0, view.x0 + half }
    local y = view.y0
    while y < view.y1 do
        for _i, x in ipairs(xs) do
            for _j, w in ipairs({ view.x1 - x, half }) do
                local r = try(x, y, w)
                if r then
                    -- (nearest under the question; a place above it counts double)
                    local dy = y >= q.y1 and y - q.y1 or (q.y1 - y) * 2
                    local d = dy + math.abs(x - q.x0) / 2
                    if not best_d or d < best_d then best, best_d = r, d end
                end
            end
        end
        y = y + step
    end
    return best
end

--- The page's view for replies (canvas px): the paper as far as it's on the
--- screen, inside a margin.
function Ask.view(screen)
    local sk, m = screen.sketch, Ask.MARGIN
    local x0, y0, y1 = 0, 0, screen.canvas.h
    local pr = sk.pageRect and sk:pageRect()
    if pr and pr.w > 0 then
        x0, y0 = math.max(x0, pr.x), math.max(y0, pr.y)
        y1 = math.min(y1, pr.y + pr.h)
    end
    return { x0 = x0 + m, y0 = y0 + m, x1 = Ask.rightEdge(screen), y1 = y1 - m }
end

--- What's on the page already (canvas boxes): the writing and the text boxes but `except`.
local function takenOn(sk, except)
    local out = {}
    for _i, st in ipairs(sk:live()) do
        local b = sk:strokeBox(st)
        if b then out[#out + 1] = { x0 = b.x0, y0 = b.y0, x1 = b.x1, y1 = b.y1 } end
    end
    for _i, el in ipairs(sk:liveTexts()) do
        if el ~= except then
            local x0, y0 = sk:toCanvas(el.x or 0, el.y or 0)
            out[#out + 1] = { x0 = x0, y0 = y0, x1 = x0 + (el.width or 0) * sk.per_unit, y1 = y0 + (el.height or 0) * sk.per_unit }
        end
    end
    return out
end

local function sceneRect(sk, r)
    local x0, y0 = sk:toScene(r.x0, r.y0)
    local x1, y1 = sk:toScene(r.x1, r.y1)
    return { round(x0), round(y0), round(x1), round(y1) }
end

--- Box `el` says `text` (its height follows).
local function say(screen, el, text, state)
    local probe = { text = text, width = el.width, fontSize = el.fontSize, fontFamily = el.fontFamily, customData = el.customData }
    screen.sketch:changeText(el, { text = text, height = round(math.max(screen:textHeight(probe), el.fontSize * 1.25)) })
    if state then el.customData.gzAsk.state = state end
end

--- The replies came: each under its own question. Box `el` (waiting) becomes
--- the first; more boxes for the others.
function Ask.place(screen, el, pieces, replies, size)
    local sk = screen.sketch
    local edge = Ask.rightEdge(screen)
    local made = {}
    for i, r in ipairs(replies) do
        local area
        for _j, b in ipairs(r.boxes) do
            local p = pieces[b]
            if p then
                area = area and { x0 = math.min(area.x0, p.x0), y0 = math.min(area.y0, p.y0), x1 = math.max(area.x1, p.x1), y1 = math.max(area.y1, p.y1) }
                    or { x0 = p.x0, y0 = p.y0, x1 = p.x1, y1 = p.y1 }
            end
        end
        area = area or pieces[#pieces] or { x0 = 0, y0 = 0, x1 = 0, y1 = 0 }
        local lh = Ask.letterHeight((function()
            local list = {}
            for _j, b in ipairs(r.boxes) do for _k, st in ipairs(pieces[b] and pieces[b].strokes or {}) do list[#list + 1] = st end end
            return list
        end)(), function(st) return sk:strokeBox(st) end)
        local fsize = lh and Ask.sizeFor(lh, sk.per_unit) or size
        local room = Ask.room(area, pieces, edge)
        local info = { state = "answer", q = sceneRect(sk, area), read = r.read }
        -- where there's room on the page as it's seen; smaller writing when there's none
        local taken, view = takenOn(sk, i == 1 and el or nil), Ask.view(screen)
        local spot
        for _k, fs in ipairs({ fsize, math.max(Ask.MIN_SIZE, math.floor(fsize * 0.8)), Ask.MIN_SIZE }) do
            local function measure(w)
                local probe = { text = r.reply, width = w / sk.per_unit, fontSize = fs, fontFamily = Ask.FONT, customData = { gzAsk = info } }
                return screen:textHeight(probe) * sk.per_unit
            end
            spot = Ask.spot(area, room, measure, taken, view, Ask.GAP * sk.per_unit)
            if spot then fsize = fs; break end
        end
        local sx, sy, width
        if spot then
            sx, sy = sk:toScene(spot.x, spot.y)
            width = round(spot.w / sk.per_unit)
        else
            -- (no room anywhere: under its question, as before)
            sx, sy = sk:toScene(area.x0, area.y1)
            sy = sy + Ask.GAP
            width = round(room / sk.per_unit)
        end
        local probe = { text = r.reply, width = width, fontSize = fsize, fontFamily = Ask.FONT, customData = { gzAsk = info } }
        local fields = { text = r.reply, x = round(sx), y = round(sy), width = width, fontSize = fsize,
            height = round(screen:textHeight(probe)) }
        if i == 1 then
            sk:changeText(el, fields)
            el.customData.gzAsk = info
            made[#made + 1] = el
        else
            local nb = Ask.box(screen, area, room, r.reply, fsize, info)
            for k, v in pairs(fields) do nb[k] = v end
            sk:addText(nb)
            made[#made + 1] = nb
        end
    end
    return made
end

--- Asks for box `el` (waiting), its question the `strokes`: "sent", "asking"
--- (already), or nil (nothing to send).
function Ask.send(screen, el, strokes)
    local Hw = require("gzreader_handwriting")
    local sk = screen.sketch
    local a = Ask.info(el)
    if not a then return nil end
    if Ask.busy[el] then return "asking" end
    local box = function(st) return sk:strokeBox(st) end
    local pieces = Ask.pieces(strokes, box)
    if #pieces == 0 then return nil end
    local lh = Ask.letterHeight(strokes, box) or 20
    local pad = math.max(6, lh * 0.3)
    local flat = Ask.pictureStrokes(pieces, Hw.flat(strokes), pad)
    local png, err = Hw.png(flat, sk:radius(2))
    if not png then
        Log.info("drawing: pen pal, nothing to send:", tostring(err))
        return nil
    end
    Ask.busy[el] = true
    if el.text ~= Ask.THINKING then say(screen, el, Ask.THINKING); screen:touched(); screen:redrawAll() end
    Log.info("drawing: pen pal asked,", #strokes, "strokes in", #pieces, "pieces")
    local size = Ask.sizeFor(lh, sk.per_unit)
    require("gzreader_ai").ask(screen.plugin, { text = Ask.prompt(#pieces, Ask.history(sk:liveTexts())), png = Hw.base64(png),
        system = Ask.SYSTEM, max_tokens = Ask.MAX_TOKENS, what = "drawing: pen pal", reason = "pen pal" }, function(text, why)
        Ask.busy[el] = nil
        -- (the drawing closed, or another page: asked again when it's opened)
        if screen._closed or sk ~= screen.sketch or sk.text_gone[el] then return end
        local replies = Ask.parse(text, #pieces)
        if #replies > 0 then
            local made = Ask.place(screen, el, pieces, replies, size)
            Log.info("drawing: pen pal answered,", #made, "replies")
        else
            Log.info("drawing: pen pal, no answer:", tostring(why))
            -- ("no answer (timeout)" from gzreader_ai: the reason inside)
            local reason = tostring(why or _("nothing came back")):gsub("^no answer %((.*)%)$", "%1")
            say(screen, el, T(_("✦ No answer yet (%1). Tap ✦ to try again."), reason))
        end
        screen:touched()
        screen:redrawAll()
    end)
    return "sent"
end

--- A box waiting for what's asked: under the whole writing at canvas `area`.
function Ask.newBox(screen, area, size)
    local info = { state = "waiting", q = sceneRect(screen.sketch, area) }
    return Ask.box(screen, area, Ask.rightEdge(screen) - area.x0, Ask.THINKING, size, info)
end

--- ✦ tapped: what's waiting is asked again, and the new writing (not asked
--- about yet) is asked. Returns how many were asked.
function Ask.tap(screen)
    local sk = screen.sketch
    local box = function(st) return sk:strokeBox(st) end
    local live = sk:live()
    local n, busy = 0, false
    for _i, el in ipairs(Ask.waiting(sk:liveTexts())) do
        local q = Ask.info(el).q
        local x0, y0 = sk:toCanvas(q[1], q[2])
        local x1, y1 = sk:toCanvas(q[3], q[4])
        local strokes = Ask.within(live, { x0, y0, x1, y1 }, box)
        local r = #strokes > 0 and Ask.send(screen, el, strokes) or nil
        if r == "sent" then n = n + 1 elseif r == "asking" then busy = true end
    end
    local strokes = Ask.unasked(live, askedAreas(sk), box)
    if #strokes > 0 then
        local el = Ask.newBox(screen, sk:strokesArea(strokes), Ask.sizeFor(Ask.letterHeight(strokes, box), sk.per_unit))
        sk:addText(el)
        screen:touched()
        screen:redrawAll()
        Ask.send(screen, el, strokes)
        n = n + 1
    end
    if n == 0 and not busy then
        local UIManager = require("ui/uimanager")
        UIManager:show(require("ui/widget/infomessage"):new{ timeout = 3,
            text = _("Write a question, a note or a sum, then tap ✦: the AI writes back under it.") })
    end
    return n
end

--- A page opened: boxes still waiting are asked again when Wi-Fi is on (never turned on for it).
function Ask.resume(screen)
    local sk = screen.sketch
    if not sk or not Ask.available(screen.plugin) then return 0 end
    local waiting = Ask.waiting(sk:liveTexts())
    if #waiting == 0 then return 0 end
    local ok, on = pcall(function() return require("gzreader_net").connected() end)
    if not (ok and on) then return 0 end
    local live = sk:live()
    local n = 0
    for _i, el in ipairs(waiting) do
        local q = Ask.info(el).q
        local x0, y0 = sk:toCanvas(q[1], q[2])
        local x1, y1 = sk:toCanvas(q[3], q[4])
        local strokes = Ask.within(live, { x0, y0, x1, y1 }, function(st) return sk:strokeBox(st) end)
        if #strokes > 0 and Ask.send(screen, el, strokes) == "sent" then n = n + 1 end
    end
    return n
end

return Ask
