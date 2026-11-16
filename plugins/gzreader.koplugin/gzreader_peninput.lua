--[[--
Pen Kindles (the Kindle Scribe; KOReader's wacom protocol): the pen and the
touch screen kept apart.

KOReader reads both into one table of contacts ("slots"), and both write
into "the current slot":
- the pen goes to slot 4 (`input.pen_slot`) when it comes near, then sends
  its position without saying which slot again;
- the touch screen picks a slot with ABS_MT_SLOT, and only when it changes
  (the kernel leaves it out when it's the same as last time);
- the touch screen can also send its first contact again as a single-touch
  position (ABS_X / ABS_Y / BTN_TOUCH: the codes the pen uses).
So a hand on the screen while the pen writes mixed the two: a palm's fifth
contact took the pen's slot (slot 4) and drew, the pen's positions went into
the palm's slot and the palm's into the pen's, and a stroke jumped between
the pen and the palm (the owner's Scribe, 2026-11-16: rectangles with a
diagonal wherever a hand rested).

Here, on pen Kindles, before KOReader sees an event:
- each input frame comes from one device (the kernel delivers them whole);
  a frame with any multitouch event (ABS_MT_*) is the touch screen's;
- the touch screen's events go to its own slot (remembered across frames),
  moved past the pen's (slot n → n + `PANEL_SHIFT` from the pen's slot up),
  so a palm never lands in the pen's slot;
- its single-touch copy (ABS_X, ABS_Y, ABS_PRESSURE, BTN_TOUCH, BTN_TOOL_FINGER…
  after a multitouch event in the same frame) is dropped;
- the pen's events (anything else: its position, pressure, tilt, distance,
  BTN_TOUCH, BTN_TOOL_PEN/RUBBER, its buttons) go to the pen's slot.
Nothing changes on Kindles without a pen.

`PenInput.route(state, ev)` is the decision, on its own (tested in
`peninput_test.lua`); `PenInput.install(input)` wraps the input's handlers.
]]

local PenInput = {
    EV_SYN = 0, EV_KEY = 1, EV_ABS = 3,
    SYN_REPORT = 0,
    ABS_MT_FIRST = 0x2f, ABS_MT_LAST = 0x3e, -- ABS_MT_SLOT … ABS_MT_TOOL_Y
    ABS_MT_SLOT = 0x2f,
    -- the touch screen's slots from the pen's up are moved this far
    PANEL_SHIFT = 16,
    -- keys a touch screen may send as its single-touch copy (BTN_TOUCH,
    -- BTN_TOOL_FINGER, …DOUBLETAP, …TRIPLETAP, …QUADTAP, …QUINTTAP)
    PANEL_KEYS = { [0x14a] = true, [0x145] = true, [0x14d] = true, [0x14e] = true, [0x14f] = true, [0x148] = true },
    -- the pen's own keys: BTN_TOOL_PEN, BTN_TOOL_RUBBER, BTN_STYLUS, BTN_STYLUS2, BTN_TOUCH
    PEN_KEYS = { [0x140] = true, [0x141] = true, [0x14b] = true, [0x14c] = true, [0x14a] = true },
}

--- A new state: `pen_slot` (KOReader's), `main_slot` (its first finger's).
function PenInput.newState(pen_slot, main_slot)
    return { pen_slot = pen_slot or 4, main_slot = main_slot or 0, panel_slot = nil, mt_frame = false,
        stats = { panel = 0, pen = 0, dropped = 0 } }
end

--- The slot a touch screen slot `n` is kept in (never the pen's).
function PenInput.panelSlot(state, n)
    n = (n or 0) + state.main_slot
    if n >= state.pen_slot then return n + PenInput.PANEL_SHIFT end
    return n
end

--- What to do with `ev` ({ type, code, value }): "panel" (KOReader handles it
--- in the slot returned second), "pen" (in the pen's slot), "drop", or "pass"
--- (as it is: frame ends, other keys). Updates `state`.
function PenInput.route(state, ev)
    local t, c = ev.type, ev.code
    if t == PenInput.EV_SYN then
        if c == PenInput.SYN_REPORT then state.mt_frame = false end
        return "pass"
    end
    if t == PenInput.EV_ABS then
        if c >= PenInput.ABS_MT_FIRST and c <= PenInput.ABS_MT_LAST then
            state.mt_frame = true
            if c == PenInput.ABS_MT_SLOT then state.panel_slot = PenInput.panelSlot(state, ev.value) end
            state.stats.panel = state.stats.panel + 1
            return "panel", state.panel_slot or PenInput.panelSlot(state, 0)
        end
        if state.mt_frame then
            state.stats.dropped = state.stats.dropped + 1
            return "drop" -- the touch screen's single-touch copy
        end
        state.stats.pen = state.stats.pen + 1
        return "pen", state.pen_slot
    end
    if t == PenInput.EV_KEY then
        if state.mt_frame and PenInput.PANEL_KEYS[c] then
            state.stats.dropped = state.stats.dropped + 1
            return "drop"
        end
        if PenInput.PEN_KEYS[c] then
            state.stats.pen = state.stats.pen + 1
            return "pen", state.pen_slot
        end
    end
    return "pass"
end

--- Wraps `input`'s touch and key handlers (pen Kindles only; once). Returns
--- true when it did.
function PenInput.install(input)
    if not input or not input.wacom_protocol or input.gz_pen_input then return false end
    local state = PenInput.newState(input.pen_slot, input.main_finger_slot)
    input.gz_pen_input = state
    local function slotTo(self, slot)
        if slot and self.cur_slot ~= slot then self:setupSlotData(slot) end
    end
    local function wrap(name)
        local orig = input[name]
        if type(orig) ~= "function" then return end
        input[name] = function(self, ev)
            local what, slot = PenInput.route(state, ev)
            if what == "drop" then return nil end
            if what == "panel" then
                -- (ABS_MT_SLOT: KOReader would pick the touch screen's own number)
                if ev.code == PenInput.ABS_MT_SLOT then slotTo(self, slot); return nil end
                slotTo(self, slot)
            elseif what == "pen" then
                slotTo(self, slot)
            end
            return orig(self, ev)
        end
    end
    -- (KOReader swaps handleTouchEv out while touch is off and back after:
    -- the instance field it saves and puts back is this wrapper)
    wrap("handleTouchEv")
    wrap("handleKeyBoardEv")
    pcall(function() require("logger").info("gzreader: pen and touch screen kept apart, pen slot", state.pen_slot) end)
    return true
end

return PenInput
