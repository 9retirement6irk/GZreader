--[[--
Scrolling that follows the finger (the owner, 2026-11-16): the notes list
and an opened note moved only when the finger lifted. They now move while
it drags, a step at a time (an e-ink screen can't redraw at every sample:
at most one step each `INTERVAL` seconds, and only once the finger has gone
`MIN_STEP` pixels further), and settle where the finger lifts.

`LiveScroll.step(state, rel, now)` is the rule (pure, tested):
state = { applied, at } (how far the finger had gone at the last step, and when).
`LiveScroll.on(scroller, opts)` puts it on a KOReader ScrollableContainer.

The daily paper's stories (`opts.coarse`, the owner's video of 2026-11-26:
the free scroll redrew so often that lines ghosted over each other) move
less often: a step only after a good part of the screen (`COARSE_STEP`) and
`COARSE_INTERVAL` apart; a flick moves a screenful, as a page turn; and the
page is shown once more with a flash when the finger lifts, which clears
what the steps left behind.
]]

local LiveScroll = { INTERVAL = 0.18, MIN_STEP = 12,
    COARSE_INTERVAL = 0.6, COARSE_STEP = 0.3, -- (a third of the screen, at most every 0.6 s)
    FLICK_PAGE = 0.85, -- a flick moves this much of the screen (as the page keys do)
    COARSE_SETTLE = "flashpartial" }

--- The finger is `rel` pixels from where the drag began, at time `now`
--- (seconds): how far to scroll now (0: not yet). Updates `state`.
--- `interval` and `min_step`: the defaults' INTERVAL and MIN_STEP otherwise.
function LiveScroll.step(state, rel, now, interval, min_step)
    local d = rel - (state.applied or 0)
    if math.abs(d) < (min_step or LiveScroll.MIN_STEP) then return 0 end
    if state.at and now - state.at < (interval or LiveScroll.INTERVAL) then return 0 end
    state.applied, state.at = rel, now
    return d
end

--- Runs `fn` with every screen refresh it asks for turned into `mode`
--- ("fast": straight to black or white, no flash; greys look rough until
--- the next ordinary refresh). The steps of a drag are shown this way: the
--- usual refresh flashed dark behind what changed at every step (the owner,
--- 2026-11-16); the page is refreshed properly once when the finger lifts.
function LiveScroll.quiet(fn, mode)
    local UIManager = require("ui/uimanager")
    mode = mode or LiveScroll.STEP_REFRESH
    local orig = UIManager.setDirty
    UIManager.setDirty = function(self, widget, refresh, region, dither)
        if type(refresh) == "function" then
            local inner = refresh
            refresh = function()
                local _, r, d = inner()
                return mode, r, d
            end
        elseif refresh ~= nil then
            refresh = mode
        end
        return orig(self, widget, refresh, region, dither)
    end
    local ok, err = pcall(fn)
    UIManager.setDirty = orig
    if not ok then error(err, 0) end
end
LiveScroll.STEP_REFRESH = "fast"

--- Once the finger lifts, the page is shown again with this: on the Scribe
--- and the other REAGL Kindles, the refresh the Kindle turns pages with: no
--- flash, and it clears what the steps left behind. The ordinary "ui" one
--- didn't: after a scroll, lines stood two or three times where they'd been
--- (the owner's video IMG_0270, 2026-11-17). (Like a page turn, KOReader makes
--- one in every few of them a flash of that part of the screen.)
LiveScroll.SETTLE_REFRESH = "partial"

--- `widget`'s `region` shown again cleanly (after a drag's rough steps); `mode`: SETTLE_REFRESH otherwise.
function LiveScroll.settle(widget, region, mode)
    require("ui/uimanager"):setDirty(widget, function() return mode or LiveScroll.SETTLE_REFRESH, region end)
end

--- How far a flick moves (coarse): `page` px forward for one upwards, back for
--- one downwards; 0 for one sideways. Pure.
function LiveScroll.flickBy(ges, page)
    local dir = ges and ges.direction or ""
    if dir:find("north", 1, true) then return page end
    if dir:find("south", 1, true) then return -page end
    return 0
end

--- How much further the page has to move when a drag ends as a swipe, so
--- it rests where the finger left it: `live` = { rel_x, rel_y (the finger's
--- last seen distance from where it came down), moved_x, moved_y (how far
--- the page went meanwhile) }. With no drag seen before the swipe (a very
--- quick flick), the swipe's own length in its direction.
function LiveScroll.freeEnd(live, ges)
    if live.rel_y or live.rel_x then
        return -(live.rel_x or 0) - (live.moved_x or 0), -(live.rel_y or 0) - (live.moved_y or 0)
    end
    local d = tonumber(ges and ges.distance) or 0
    local dir = ges and ges.direction or ""
    local diag = math.floor(d * 0.7 + 0.5)
    if dir == "north" then return 0, d end
    if dir == "south" then return 0, -d end
    if dir == "west" then return d, 0 end
    if dir == "east" then return -d, 0 end
    local dx = dir:find("west", 1, true) and diag or dir:find("east", 1, true) and -diag or 0
    local dy = dir:find("north", 1, true) and diag or dir:find("south", 1, true) and -diag or 0
    return dx, dy
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
--- opts.free: a drag that ends with the finger still moving (KOReader
--- calls it a swipe, and answers it by moving a whole screenful) leaves the
--- page exactly where the finger left it instead: no jump after the lift.
function LiveScroll.on(scroller, opts)
    if not scroller or scroller._gz_live then return scroller end
    local free = type(opts) == "table" and opts.free == true
    local coarse = type(opts) == "table" and opts.coarse == true
    local interval = coarse and LiveScroll.COARSE_INTERVAL or nil
    local function minStep(self) return coarse and math.max(LiveScroll.MIN_STEP, math.floor(self.dimen.h * LiveScroll.COARSE_STEP)) or nil end
    local settle_mode = coarse and LiveScroll.COARSE_SETTLE or nil
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
            -- (where the finger is now, for a lift that comes as a swipe)
            live.rel_x, live.rel_y = ges.relative.x or 0, ges.relative.y or 0
            local dy = LiveScroll.step(live.y, ges.relative.y or 0, now, interval, minStep(self))
            local dx = self._max_scroll_offset_x > 0 and LiveScroll.step(live.x, ges.relative.x or 0, now, interval, minStep(self)) or 0
            if dx ~= 0 or dy ~= 0 then
                local x0, y0 = self._scroll_offset_x, self._scroll_offset_y
                LiveScroll.quiet(function() self:_scrollBy(-dx, -dy) end)
                live.rough = true
                -- (at an end it moves less than asked: what really moved is what's taken back)
                live.moved_x = live.moved_x + self._scroll_offset_x - x0
                live.moved_y = live.moved_y + self._scroll_offset_y - y0
            end
        end
        return handled
    end
    -- (after steps shown roughly: the page once more, properly, even when it ends where the last step left it)
    local function settle(self, rough)
        if rough then LiveScroll.settle(self.show_parent, self.dimen, settle_mode) end
    end
    function scroller:onScrollablePanRelease(arg, ges)
        local rough = self._gz_live.rough
        if self._scrolling then takeBack(self) end
        local r = release(self, arg, ges)
        settle(self, rough)
        return r
    end
    function scroller:onScrollableSwipe(arg, ges)
        local rough = self._gz_live.rough
        if coarse and self._is_scrollable and ges.pos and ges.pos:intersectWith(self.dimen) then
            -- a flick: a screenful, as a page turn (what the steps moved first taken back)
            takeBack(self)
            self._scrolling, self._scroll_relative_x, self._scroll_relative_y = false, nil, nil
            local dy = LiveScroll.flickBy(ges, math.floor(self.dimen.h * LiveScroll.FLICK_PAGE))
            if dy ~= 0 then LiveScroll.quiet(function() self:_scrollBy(0, dy) end) end
            settle(self, true)
            return true
        end
        if free and self._is_scrollable and ges.pos and ges.pos:intersectWith(self.dimen) then
            -- to where the finger was last seen, less what the steps already moved
            local live = self._gz_live
            local dx, dy = LiveScroll.freeEnd(live, ges)
            self._scrolling, self._scroll_relative_x, self._scroll_relative_y = false, nil, nil
            self._gz_live = fresh()
            if dx ~= 0 or dy ~= 0 then self:_scrollBy(dx, dy) end
            settle(self, true)
            return true
        end
        if self._is_scrollable and ges.pos and ges.pos:intersectWith(self.dimen) then takeBack(self) end
        local r = swipe(self, arg, ges)
        settle(self, rough)
        return r
    end
    return scroller
end

return LiveScroll
