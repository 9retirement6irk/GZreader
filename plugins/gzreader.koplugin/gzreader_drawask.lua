--[[--
A pen pal on a drawing's page (after rocoloco/pen-pal, MIT; no code taken):
write a question or a note with the pen, tap ✦ in the top bar, and the AI
(Settings → Accounts and services → AI) writes back under it, in a text box
in a handwriting font (Patrick Hand, as the sticky notes').

The question is the writing under the last answer on the page (all of it on a
page with none). It's sent as a black-and-white picture of that writing
alone (gzreader_handwriting's), never the page or other notes; the answer is
asked for in plain words. The writing stays as it was written.

Each answer is a text box with `customData.gzAsk`:
  { state = "waiting" | "answer", q = { x0, y0, x1, y1 } }
`q`: where its question is, in scene units. A box still waiting (no Wi-Fi,
or the drawing closed before the answer came) keeps its place on the page
and is asked again when ✦ is tapped, or when the page opens with Wi-Fi on.
Memos shows the boxes as text boxes too (its own cursive font).
]]

local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local Ask = {
    FONT = "'Patrick Hand', cursive", -- (memos: a CSS font list; on the Kindle, the sticky notes' Patrick Hand)
    SIZE = 24, -- scene units
    MAX_TOKENS = 500,
    GAP = 12, -- scene units between the question and its answer
}

Ask.SYSTEM = "You are a friendly pen pal writing back on a page of someone's handwritten notebook. "
    .. "The picture is what they just wrote. Read it, then answer their question or reply to their note "
    .. "warmly and briefly: a few short sentences at most. Write only your reply, as plain text: "
    .. "no Markdown, no lists, no headings, and don't repeat what they wrote."
Ask.PROMPT = "Please write back to this."

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

--- Is box `el` in the handwriting font (a pen pal's answer, or set so in memos)?
function Ask.isHand(el)
    return Ask.info(el) ~= nil or (type(el) == "table" and type(el.fontFamily) == "string" and el.fontFamily:find("Patrick Hand", 1, true) ~= nil)
end

--- The boxes still waiting for an answer among `texts`.
function Ask.waiting(texts)
    local out = {}
    for _i, el in ipairs(texts or {}) do
        local a = Ask.info(el)
        if a and a.state == "waiting" then out[#out + 1] = el end
    end
    return out
end

--- How far down the answers go (scene units): the bottom of the lowest one, or nil.
function Ask.lowest(texts)
    local y
    for _i, el in ipairs(texts or {}) do
        if Ask.info(el) then
            local b = (tonumber(el.y) or 0) + (tonumber(el.height) or 0)
            if not y or b > y then y = b end
        end
    end
    return y
end

--- The question: the strokes (`strokes`, live) whose top is under `below`
--- (canvas y; nil: all of them). `box(st)` gives a stroke's canvas box.
function Ask.question(strokes, below, box)
    local out = {}
    for _i, st in ipairs(strokes or {}) do
        local b = box(st)
        if b and (not below or b.y0 >= below) then out[#out + 1] = st end
    end
    return out
end

--- The strokes inside scene rectangle `q` (a waiting box's question), through `toCanvas`.
function Ask.within(strokes, q, toCanvas, box)
    local x0, y0 = toCanvas(q[1], q[2])
    local x1, y1 = toCanvas(q[3], q[4])
    local out = {}
    for _i, st in ipairs(strokes or {}) do
        local b = box(st)
        if b and b.x1 >= x0 - 2 and b.x0 <= x1 + 2 and b.y1 >= y0 - 2 and b.y0 <= y1 + 2 then out[#out + 1] = st end
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

-- (the boxes being asked about now: not kept in the drawing, so a box saved
-- while asking is asked again when it's opened)
Ask.busy = setmetatable({}, { __mode = "k" })

Ask.THINKING = _("✦ …")
Ask.WAITING = _("✦ Waiting for Wi-Fi. Tap ✦ to try again.")

-- ------------------------------------------------------------ on the drawing screen

--- A new box, waiting, under the question at canvas `area` (`screen`: the drawing screen).
function Ask.newBox(screen, area)
    local DrawText = require("gzreader_drawtext")
    local Drawing = require("gzreader_drawing")
    local sk = screen.sketch
    local qx0, qy0 = sk:toScene(area.x0, area.y0)
    local qx1, qy1 = sk:toScene(area.x1, area.y1)
    local c = screen.canvas
    local right = sk:toScene(c.w * 0.92, 0)
    local x = qx0
    local w = math.max(DrawText.MIN_WIDTH * 4, right - x)
    local el = DrawText.element(x, qy1 + Ask.GAP, w, Ask.THINKING, nil, Ask.SIZE)
    el.fontFamily = Ask.FONT
    el.customData = { gzAsk = { state = "waiting",
        q = { Drawing.round2(qx0), Drawing.round2(qy0), Drawing.round2(qx1), Drawing.round2(qy1) } } }
    el.height = Drawing.round2(math.max(el.height, screen:textHeight(el)))
    return el
end

--- Box `el` says `text`: its height follows (one Undo for the asking, its own for this).
local function say(screen, el, text, state)
    local Drawing = require("gzreader_drawing")
    local probe = { text = text, width = el.width, fontSize = el.fontSize, fontFamily = el.fontFamily, customData = el.customData }
    screen.sketch:changeText(el, { text = text, height = Drawing.round2(math.max(el.height, screen:textHeight(probe))) })
    if state then el.customData.gzAsk.state = state end
    screen:touched()
    screen:redrawAll()
end

--- Asks for box `el` (waiting) with `strokes` as its question: "sent", "asking"
--- (already), or nil (nothing to send).
function Ask.send(screen, el, strokes)
    local Hw = require("gzreader_handwriting")
    local sk = screen.sketch
    local a = Ask.info(el)
    if not a then return nil end
    if Ask.busy[el] then return "asking" end
    local png, err = Hw.png(Hw.flat(strokes), sk:radius(2))
    if not png then
        Log.info("drawing: pen pal, nothing to send:", tostring(err))
        return nil
    end
    Ask.busy[el] = true
    if el.text ~= Ask.THINKING then say(screen, el, Ask.THINKING) end
    Log.info("drawing: pen pal asked,", #strokes, "strokes")
    require("gzreader_ai").ask(screen.plugin, { text = Ask.PROMPT, png = Hw.base64(png), system = Ask.SYSTEM,
        max_tokens = Ask.MAX_TOKENS, what = "drawing: pen pal", reason = "pen pal" }, function(text, why)
        Ask.busy[el] = nil
        -- (the drawing closed, or another page: asked again when it's opened)
        if screen._closed or sk ~= screen.sketch or sk.text_gone[el] then return end
        local answer = Ask.clean(text)
        if answer then
            say(screen, el, answer, "answer")
        else
            Log.info("drawing: pen pal, no answer:", tostring(why))
            -- ("no answer (timeout)" from gzreader_ai: the reason inside)
            local reason = tostring(why or _("nothing came back")):gsub("^no answer %((.*)%)$", "%1")
            say(screen, el, T(_("✦ No answer yet (%1). Tap ✦ to try again."), reason))
        end
    end)
    return "sent"
end

--- ✦ tapped: what's waiting is asked again, and the new writing (under the last
--- answer) is asked. Returns how many were asked.
function Ask.tap(screen)
    local sk = screen.sketch
    local texts = sk:liveTexts()
    local box = function(st) return sk:strokeBox(st) end
    local live = sk:live()
    local n, busy = 0, false
    for _i, el in ipairs(Ask.waiting(texts)) do
        local q = Ask.within(live, Ask.info(el).q, function(x, y) return sk:toCanvas(x, y) end, box)
        local r = #q > 0 and Ask.send(screen, el, q) or nil
        if r == "sent" then n = n + 1 elseif r == "asking" then busy = true end
    end
    local lowest = Ask.lowest(texts)
    local below = lowest and select(2, sk:toCanvas(0, lowest)) or nil
    local strokes = Ask.question(live, below, box)
    if #strokes > 0 then
        local el = Ask.newBox(screen, sk:strokesArea(strokes))
        sk:addText(el)
        screen:touched()
        screen:redrawAll()
        Ask.send(screen, el, strokes)
        n = n + 1
    end
    if n == 0 and not busy then
        local UIManager = require("ui/uimanager")
        UIManager:show(require("ui/widget/infomessage"):new{ timeout = 3,
            text = _("Write a question or a note under the last answer, then tap ✦: the AI writes back under it.") })
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
        local q = Ask.within(live, Ask.info(el).q, function(x, y) return sk:toCanvas(x, y) end, function(st) return sk:strokeBox(st) end)
        if #q > 0 and Ask.send(screen, el, q) == "sent" then n = n + 1 end
    end
    return n
end

return Ask
