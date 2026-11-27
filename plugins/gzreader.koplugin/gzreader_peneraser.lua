--[[--
The pen's eraser removes highlights in a book: rub the Scribe's Premium Pen's
eraser end (or, on a Kobo with a pen, hold its eraser button) over a highlight
and it's gone, as a pencil mark would be. Each highlight it passes over is
deleted as the eraser reaches it (the same as Delete in its menu: its note
goes with it), and the page is drawn again when the eraser lifts.

- Only in a book with nothing on top of it (a menu, the drawing screen: the
  eraser does nothing there). The pen's tip, and fingers, work as before.
- Settings → Accounts and services → Notes → "Pen's eraser removes
  highlights" (on by default; a Kindle or Kobo with a pen only).
- The log says how many were removed (numbers only, never their text).

KOReader's Input:registerStylusCallback gets every pen point before the
gestures do; the eraser's are taken (no tap or swipe from them), the tip's
are left to the gestures.
]]

local Log = require("gzreader_log")

local Eraser = {
    SETTING = "gzreader_pen_eraser_highlights",
    active = nil, -- the ReaderUI the callback is for
    stroke = nil, -- { removed = n } while the eraser is down
}

local function inside(pos, r)
    return pos.x >= r.x and pos.x <= r.x + r.w and pos.y >= r.y and pos.y <= r.y + r.h
end

--- On (the default) unless turned off.
function Eraser.enabled(settings)
    settings = settings or G_reader_settings
    return settings:nilOrTrue(Eraser.SETTING)
end

--- The highlights (their indices, each once) whose boxes contain the page
--- position `pos`. `boxes` is ReaderView's highlight.visible_boxes; `pad`
--- widens each box a little (the eraser is wider than a point).
function Eraser.hits(boxes, pos, pad)
    pad = pad or 0
    local out, seen = {}, {}
    for _i, box in ipairs(boxes or {}) do
        local r = box.rect
        if r and box.index and not seen[box.index]
                and inside(pos, { x = r.x - pad, y = r.y - pad, w = r.w + 2 * pad, h = r.h + 2 * pad }) then
            seen[box.index] = true
            out[#out + 1] = box.index
        end
    end
    return out
end

--- Whether the book is what's on screen (nothing on top of it).
function Eraser.onTop(ui)
    local UIManager = require("ui/uimanager")
    local stack = UIManager._window_stack or {}
    for i = #stack, 1, -1 do
        local w = stack[i].widget
        if w == ui then return true end
        -- (things that don't cover the page: the footer's toast, a passing message)
        if not (w and (w.toast or w.invisible or w.name == "ScreenSaverLock")) then return false end
    end
    return false
end

--- Remove the highlights under the screen point x, y in `ui`'s book. Returns
--- how many went.
function Eraser.eraseAt(ui, x, y)
    local view, hl = ui and ui.view, ui and ui.highlight
    local annotations = ui and ui.annotation and ui.annotation.annotations
    if not (view and hl and annotations and view.highlight and view.highlight.visible_boxes) then return 0 end
    local pos = view:screenToPageTransform({ x = x, y = y })
    if not pos then return 0 end
    local pad = 6
    local okp, px = pcall(function() return require("device").screen:scaleBySize(6) end)
    if okp and type(px) == "number" then pad = px end
    local scale = view.state and tonumber(view.state.zoom) or 1
    if scale <= 0 then scale = 1 end
    local items = {}
    for _i, idx in ipairs(Eraser.hits(view.highlight.visible_boxes, pos, pad / scale)) do
        local item = annotations[idx]
        if item and not item.is_tmp then items[#items + 1] = item end
    end
    if #items == 0 then return 0 end
    -- each box's highlight, before any goes (a deletion moves the others along)
    local boxes = {}
    for _i, box in ipairs(view.highlight.visible_boxes) do
        boxes[#boxes + 1] = { box = box, item = annotations[box.index] }
    end
    local n = 0
    for _i, item in ipairs(items) do
        for k, a in ipairs(annotations) do
            if a == item then
                hl:deleteHighlight(k)
                n = n + 1
                break
            end
        end
    end
    -- the boxes left, with their highlights' places now (the next point,
    -- before the page is drawn again, finds the right ones)
    local where = {}
    for k, a in ipairs(annotations) do where[a] = k end
    local left = {}
    for _i, b in ipairs(boxes) do
        local k = b.item and where[b.item]
        if k then b.box.index = k; left[#left + 1] = b.box end
    end
    view.highlight.visible_boxes = left
    return n
end

--- The stylus callback: true takes the point (the eraser's), false leaves it
--- to the gestures (the tip's).
function Eraser.onStylus(input, slot)
    local ui = Eraser.active
    local Input = input and input.TOOL_TYPE_ERASER and input or require("device/input")
    if not ui or slot.tool ~= Input.TOOL_TYPE_ERASER then return false end
    if not Eraser.enabled() or not Eraser.onTop(ui) then return false end
    if slot.id == -1 or slot.id == nil then
        -- lifted
        local st = Eraser.stroke
        Eraser.stroke = nil
        if st and st.removed > 0 then
            Log.info("pen eraser:", st.removed, "highlights removed")
            require("ui/uimanager"):setDirty(ui.dialog or ui, "ui")
        end
        return true
    end
    Eraser.stroke = Eraser.stroke or { removed = 0 }
    if slot.x and slot.y then
        local ok, n = pcall(Eraser.eraseAt, ui, slot.x, slot.y)
        if ok then Eraser.stroke.removed = Eraser.stroke.removed + n
        else Log.warn("pen eraser:", tostring(n)) end
    end
    return true
end

--- A book opened on a Kindle or Kobo with a pen: watch for the eraser.
function Eraser.install(ui, device)
    device = device or require("device")
    local input = device.input
    if not (input and input.registerStylusCallback) then return false end
    if not require("gzreader_sketch").penDevice(device) then return false end
    Eraser.active = ui
    Eraser.stroke = nil
    input:registerStylusCallback(Eraser.onStylus)
    return true
end

--- The book closed.
function Eraser.uninstall(device)
    device = device or require("device")
    local input = device.input
    if Eraser.active and input and input.stylus_callback == Eraser.onStylus then
        input:unregisterStylusCallback()
    end
    Eraser.active, Eraser.stroke = nil, nil
end

return Eraser
