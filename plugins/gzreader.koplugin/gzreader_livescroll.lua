--[[--
Scrolling that follows the finger (the owner, 2026-11-16): the notes list
and an opened note moved only when the finger lifted. They now move while
it drags, a step at a time (an e-ink screen can't redraw at every sample:
at most one step each `INTERVAL` seconds, and only once the finger has gone
`MIN_STEP` pixels further), and settle where the finger lifts.

`LiveScroll.step(state, rel, now)` is the rule (pure, tested):
state = { applied, at } (how far the finger had gone at the last step, and when).
`LiveScroll.on(scroller)` puts it on a KOReader ScrollableContainer.
]]

local LiveScroll = { INTERVAL = 0.18, MIN_STEP = 12 }

--- The finger is `rel` pixels from where the drag began, at time `now`
--- (seconds): how far to scroll now (0: not yet). Updates `state`.
function LiveScroll.step(state, rel, now)
    local d = rel - (state.applied or 0)
    if math.abs(d) < LiveScroll.MIN_STEP then return 0 end
    if state.at and now - state.at < LiveScroll.INTERVAL then return 0 end
    state.applied, state.at = rel, now
    return d
end

local function seconds()
    local ok, time = pcall(require, "ui/time")
    if ok and time then return time.to_s(time.now()) end
    return os.clock()
end
LiveScroll.now = seconds

--- `scroller` (a ScrollableContainer) follows the finger. What was moved
--- while dragging is taken back just before KOReader's own handlers move
--- it by the whole drag (a lift) or by a swipe, so nothing counts twice.
function LiveScroll.on(scroller)
    if not scroller or scroller._gz_live then return scroller end
    local function fresh() return { x = {}, y = {}, moved_x = 0, moved_y = 0 } end
    scroller._gz_live = fresh()
    local pan, release, swipe = scroller.onScrollablePan, scroller.onScrollablePanRelease, scroller.onScrollableSwipe
    local function takeBack(self)
        local live = self._gz_live
        self._scroll_offset_x = self._scroll_offset_x - live.moved_x
        self._scroll_offset_y = self._scroll_offset_y - live.moved_y
        self._gz_live = fresh()
    end
    function scroller:onScrollablePan(arg, ges)
        local was = self._scrolling
        local handled = pan(self, arg, ges)
        if handled and self._scrolling and ges.relative then
            if not was then self._gz_live = fresh() end
            local live, now = self._gz_live, LiveScroll.now()
            local dy = LiveScroll.step(live.y, ges.relative.y or 0, now)
            local dx = self._max_scroll_offset_x > 0 and LiveScroll.step(live.x, ges.relative.x or 0, now) or 0
            if dx ~= 0 or dy ~= 0 then
                local x0, y0 = self._scroll_offset_x, self._scroll_offset_y
                self:_scrollBy(-dx, -dy)
                -- (at an end it moves less than asked: what really moved is what's taken back)
                live.moved_x = live.moved_x + self._scroll_offset_x - x0
                live.moved_y = live.moved_y + self._scroll_offset_y - y0
            end
        end
        return handled
    end
    function scroller:onScrollablePanRelease(arg, ges)
        if self._scrolling then takeBack(self) end
        return release(self, arg, ges)
    end
    function scroller:onScrollableSwipe(arg, ges)
        if self._is_scrollable and ges.pos and ges.pos:intersectWith(self.dimen) then takeBack(self) end
        return swipe(self, arg, ges)
    end
    return scroller
end

return LiveScroll
