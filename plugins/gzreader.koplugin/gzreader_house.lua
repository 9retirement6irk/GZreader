--[[--
The House tab: Home Assistant's rooms and what's in them, to switch from the
Kindle (ZenOS's tab bar; off until turned on in Settings → Accounts and services → House → House tab, or Settings → Home and tabs → Tab bar → Tabs).

  Refresh                               updated 1 min ago
  Living room
    Ceiling light                       On · 80%        ›   (a dimmer: On, Off, −/+ 10%, 10/40/80/100%)
    Floor lamp                          Off        [ toggle ]
    Thermostat                          20.5° → 21°     ›   (the target, a step down or up)
    Temperature                         20.5°
  Outside
    Front door                          Locked          ›   (asks before unlocking)
    Garage door                         Closed          ›   (asks before opening)
  Scenes
    Goodnight                                           ›

A speaker or TV (a media player) opens its buttons: play or pause, the song
before and after, the volume, shuffle and repeat, on and off, the ones it
can do; a Music Assistant player also chooses what to play (its playlists,
albums, artists, radio, or a search).

In the Bookshelf view the same rows are drawn as a wall with a fitting for
each device (gzreader_houseview.lua); the other views keep this list.

Rooms are Home Assistant's areas; with a token that isn't an administrator's
the list is grouped by kind instead (gzreader_homeassistant.lua says why).
The list shown at once is the last one kept on the Kindle; it's fetched again
when the tab opens and every REFRESH seconds while it's on the screen (not
under a book or another window), drawn again only when something it shows
changed (each draw is an e-ink refresh), and a switch's answer goes straight in. The
Kindles without Wi-Fi (2, DX) can't reach Home Assistant: the tab says so,
and Settings doesn't offer it.
]]

local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local function HA() return require("gzreader_homeassistant") end
local function Async() return require("gzreader_async") end
local function Net() return require("gzreader_net") end

local House = {
    TAB_ID = "ct_house",
    REFRESH = 30, -- seconds, while the tab is on the screen
    GATHER = 0.7, -- seconds: presses of a level this close together are sent as one (the last)
    HOLD = 4,     -- seconds a level that was set stays as asked before Home Assistant is believed again
    STUCK = 45,   -- seconds after which an answer that never came stops holding its device up
}
House.__index = House

local function info(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

local function toast(text)
    pcall(function() UIManager:show(require("ui/widget/notification"):new{ text = text, timeout = 3 }) end)
end

local function confirm(text, ok_text, fn)
    UIManager:show(require("ui/widget/confirmbox"):new{ text = text, ok_text = ok_text, ok_callback = fn })
end

local function Panel() return require("gzreader_housepanel") end

local function store(plugin)
    plugin.store.homeassistant = plugin.store.homeassistant or {}
    return plugin.store.homeassistant
end

function House.client(plugin) return HA():new(store(plugin)) end

--- "Ask before unlocking or opening" (on unless turned off).
function House.asks(plugin) return store(plugin).ask ~= false end

--- No Wi-Fi to reach Home Assistant with: a Kindle 2 or DX, or syncing
--- through a computer chosen in Settings.
function House.noWifi()
    if Net().usb then return true end
    local ok, Usb = pcall(require, "gzreader_usbsync")
    return ok and Usb.noWifi() or false
end

---------------------------------------------------------------- the tab bar

--- Whether the House tab is in the tab bar.
function House.tabShown() return require("gzreader_tabs").shown(House.TAB_ID) end

--- Put the House tab in the tab bar, or take it out (as Settings → Home and tabs
--- → Tab bar → Tabs does). False when it can't (no ZenOS, or 7 tabs already).
function House.setTabShown(on)
    return require("gzreader_tabs").setShown(House.TAB_ID, on, House.tabEntry(), info)
end

--- The tab's entry in ZenOS's tab list (config/defaults.lua has the same).
function House.tabEntry()
    return { id = House.TAB_ID, type = "action", action = { gzreader_house = true }, label = "House", icon = "tab_house" }
end

---------------------------------------------------------------- the list

function House.new(plugin)
    return setmetatable({ plugin = plugin }, House)
end

local function minutesAgo(at)
    if not at then return nil end
    local m = math.floor((os.time() - at) / 60)
    if m < 1 then return _("updated just now") end
    if m < 60 then return T(_("updated %1 min ago"), m) end
    return T(_("updated at %1"), os.date("%H:%M", at))
end

--- What the Refresh row says.
function House:updatedText()
    if self.fetching then return _("updating…") end
    if self.err and not self.house then return _("couldn't update") end
    return minutesAgo(self.house and self.house.at) or ""
end

--- One device's row.
function House:entityRow(e, room_name)
    local Ha = HA()
    local id = self.house and self.house.by_kind and "" or room_name
    local what = Ha.action(e)
    local row = {
        text = Ha.shortName(e.name, id), mandatory = Ha.stateText(e), gz_icon = Ha.iconFile(e, require("gzreader_colour").enabled()),
        gz_house_id = e.id, keep_menu_open = true,
    }
    if what == "toggle" then
        row.checked_func = function()
            local cur = Ha.find(self.house, e.id)
            return cur ~= nil and cur.state == "on"
        end
    end
    if what then row.callback = function() self:tap(e.id) end end
    return row
end

--- The list: the Refresh row, then each room (Settings can hide rooms and
--- devices) with its devices.
function House:rootItems()
    local plugin = self.plugin
    local Rows = require("gzreader_rows")
    if House.noWifi() then
        return Rows.mark({ Rows.about(_("No Wi-Fi here"),
            _("Home Assistant is reached over Wi-Fi, and this Kindle syncs through a computer (it has no Wi-Fi, or Sync through a computer is chosen in Settings → General → Transfer).")) })
    end
    if not House.client(plugin):isConnected() then
        return House.connectItems(plugin, function() self:reload() end)
    end
    local st = store(plugin)
    local hidden, hidden_rooms = st.hidden or {}, st.hidden_rooms or {}
    local items = {
        { text = _("Refresh"), gz_icon = Rows.FILE.sync, mandatory = self:updatedText(), gz_no_arrow = true,
          gz_house_refresh = true, keep_menu_open = true, callback = function() self:refresh(true) end },
    }
    if not self.house then
        items[#items + 1] = { text = self.err and HA().why(self.err) or _("Loading…"), select_enabled = false, dim = true }
        return Rows.mark(items)
    end
    local shown_any = false
    for _i, r in ipairs(self.house.rooms or {}) do
        if not hidden_rooms[r.id] then
            local rows = {}
            for _j, e in ipairs(r.entities or {}) do
                if not hidden[e.id] then rows[#rows + 1] = self:entityRow(e, r.name) end
            end
            if #rows > 0 then
                shown_any = true
                items[#items + 1] = { text = r.name, bold = true, gz_icon = HA().ROOM_ICON, select_enabled = false,
                    gz_house_room = r.id }
                for _j, row in ipairs(rows) do items[#items + 1] = row end
            end
        end
    end
    if not shown_any then
        items[#items + 1] = { text = _("Nothing to show: every room is hidden, or Home Assistant has no lights, switches or the like."),
            select_enabled = false, dim = true }
    end
    if self.err then
        items[#items + 1] = { text = HA().why(self.err), select_enabled = false, dim = true }
    end
    if self.house.by_kind then
        items[#items + 1] = Rows.about(_("Why no rooms?"),
            _("Rooms come from Home Assistant's areas, which only an administrator's token can read. With this token the House tab groups things by kind. Make the token as an administrator in Home Assistant (your profile → Security → Long-lived access tokens) and connect again to see rooms."))
    end
    return Rows.mark(items)
end

--- What a list shows, as one string: each row's words, icon and marks (all
--- its plain fields, whatever they are) and whether it's ticked. Two lists
--- with the same one look the same on the screen.
function House.signature(items)
    local out = {}
    for _i, it in ipairs(items or {}) do
        local parts = {}
        if type(it) == "table" then
            local keys = {}
            for k, v in pairs(it) do
                local t = type(v)
                if type(k) == "string" and (t == "string" or t == "number" or t == "boolean") then keys[#keys + 1] = k end
            end
            table.sort(keys)
            for _j, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(it[k]) end
            if type(it.checked_func) == "function" then
                local ok, on = pcall(it.checked_func)
                parts[#parts + 1] = "ticked=" .. tostring(ok and on)
            end
        end
        out[#out + 1] = table.concat(parts, "\1")
    end
    return table.concat(out, "\2")
end

--- Draw the list again (keeping the page). `if_changed` (a refresh by
--- itself): only when it would look different from what's on the screen,
--- as each draw is an e-ink refresh. False when it wasn't drawn.
function House:redraw(if_changed)
    if self.closed or not self.menu then return false end
    local items = self:rootItems()
    local sig = House.signature(items)
    if if_changed and sig == self.drawn_sig then
        self.unchanged = (self.unchanged or 0) + 1
        if self.unchanged == 1 then Log.info("house: refreshed, nothing changed: not drawn again until something does") end
        return false
    end
    if if_changed then Log.info("house: refreshed, something changed after", self.unchanged or 0, "unchanged refreshes: drawn again") end
    self.drawn_sig, self.unchanged = sig, 0
    self.menu:switchItemTable(nil, items, -1)
    -- (a device's panel that is open: as the device is now)
    if self.panel and not self.panel.closed then self.panel:sync() end
    return true
end

--- The thermostat's unit, as Settings has it.
function House:unit() return store(self.plugin).unit end

--- After connecting or disconnecting: the list from the start.
function House:reload()
    if self.closed or not self.menu then return end
    self.house, self.err = HA().loadCache(), nil
    local items = self:rootItems()
    self.drawn_sig, self.unchanged = House.signature(items), 0
    self.menu:switchItemTable(nil, items)
    self:follow()
end

--- While connected (and on Wi-Fi): Wi-Fi held and the list asked for now
--- and every REFRESH seconds; otherwise neither. (Opening the tab, and
--- connecting from inside it: before, a tab connected from inside never
--- refreshed by itself until it was opened again.)
function House:follow()
    if self.closed then return end
    if House.client(self.plugin):isConnected() and not House.noWifi() then
        -- (Wi-Fi stays on while the tab is open: it's asked every REFRESH seconds)
        pcall(function() Net().hold("house") end)
        self:refresh(true)
        self:schedule()
    else
        if self.tick then UIManager:unschedule(self.tick) end
        pcall(function() Net().release("house") end)
    end
end

--- Fetch the list. `asked`: you asked for it (Wi-Fi may be turned on);
--- otherwise only when Wi-Fi is on already (or may be, by its mode).
function House:refresh(asked)
    if self.fetching or self.closed then return end
    local plugin = self.plugin
    local client = House.client(plugin)
    if not client:isConnected() or House.noWifi() then return end
    Net().run(function()
        if self.fetching or self.closed then return end
        self.fetching = true
        if asked then self:redraw() end
        Async().run(nil, function() return client:fetch() end, function(house, err)
            self.fetching = false
            if self.closed then return end
            if house then
                house.at = os.time()
                self.house, self.err = house, nil
                -- (a level just asked for stays as asked until it's let go)
                self:keepHeld()
                HA().saveCache(house)
                -- (found out in the background process: not an administrator's token)
                if house.by_kind and not store(plugin).no_template then
                    store(plugin).no_template = true
                    plugin:save()
                end
            else
                self.err = err
                Log.warn("house: couldn't update:", tostring(err))
            end
            -- (by itself, every REFRESH seconds: drawn only if something changed)
            self:redraw(not asked)
        end, "house")
    end, { reason = "Home Assistant", quiet = not asked })
end

--- Every REFRESH seconds while the list is the top window.
function House:schedule()
    self.tick = self.tick or function()
        if self.closed then return end
        local stack = UIManager._window_stack or {}
        local top = stack[#stack]
        if top and top.widget == self.menu then self:refresh(false) end
        UIManager:scheduleIn(House.REFRESH, self.tick)
    end
    UIManager:unschedule(self.tick)
    UIManager:scheduleIn(House.REFRESH, self.tick)
end

---------------------------------------------------------------- switching

--- A device's name as its row shows it (without its room's in front).
function House:label(e)
    local Ha = HA()
    local r = select(2, Ha.find(self.house, e.id))
    if not r or (self.house and self.house.by_kind) then return e.name end
    return Ha.shortName(e.name, r.name)
end

--- Tapped a device's row.
function House:tap(id)
    local Ha = HA()
    local e = Ha.find(self.house, id)
    local what = Ha.action(e)
    if not what then return end
    if what == "light" then return self:lightDialog(e) end
    if what == "climate" then return self:climateDialog(e) end
    if what == "media" then return self:mediaDialog(e) end
    if Ha.guarded(e, what) and House.asks(self.plugin) then
        if what == "unlock" then
            return confirm(T(_("Unlock %1?"), self:label(e)), _("Unlock"), function() self:run(e, what) end)
        end
        return confirm(T(_("Open %1?"), self:label(e)), _("Open"), function() self:run(e, what) end)
    end
    self:run(e, what)
end

--- Ask Home Assistant to do `what` to `e`; the answer goes into the list.
--- `after(e)`: with the device as it is now, if it worked.
function House:run(e, what, arg, after)
    local Ha = HA()
    local domain, service, data = Ha.service(e, what, arg)
    if not domain then return end
    local client = House.client(self.plugin)
    -- (pressed again before Home Assistant answered the first: once is enough)
    self.running = self.running or {}
    local doing = e.id .. "|" .. what
    if self.running[doing] then return end
    local mark = {}
    self.running[doing] = mark
    UIManager:scheduleIn(House.STUCK, function() if self.running[doing] == mark then self.running[doing] = nil end end)
    Log.info("house:", domain .. "." .. service, e.id)
    Net().run(function()
        Async().run(nil, function() return client:call(domain, service, data) end, function(changed, err)
            self.running[doing] = nil
            if self.closed then return end
            if not changed then
                Log.warn("house:", domain .. "." .. service, "failed:", tostring(err))
                return info(Ha.why(err))
            end
            local answered = false
            for _i, st in ipairs(changed) do if type(st) == "table" and st.entity_id == e.id then answered = true end end
            local known = Ha.applyChanged(self.house, changed)
            self:keepHeld()
            -- (a media player answers before it has changed: what it should be, for now)
            if not answered and Ha.assume(Ha.find(self.house, e.id), what, arg) then known = true end
            if known then Ha.saveCache(self.house) end
            self:redraw()
            if what == "scene" or what == "script" then toast(T(_("%1: done"), self:label(e))) end
            -- (a scene changes others; an answer without the state: fetch again in a moment)
            if what == "scene" or #changed == 0 or e.domain == "media_player" then
                UIManager:scheduleIn(2, function() self:refresh(false) end)
            end
            if after then after(Ha.find(self.house, e.id) or e) end
        end, "house " .. service)
    end, { reason = "Home Assistant" })
end

--- Set a level (a volume, a brightness, a thermostat's target) from a
--- control that can be pressed again and again (the panels' lights, − and
--- +). The screen shows it at once; Home Assistant is told once the
--- presses stop (House.GATHER), and never while an earlier one for the
--- same device is still on its way: the last press wins, the ones between
--- are never sent. Sent one after another they would each take their time,
--- arrive in a row and move a speaker's volume up and down.
function House:level(e, what, value)
    local Ha = HA()
    if self.closed or not Ha.LEVELS[what] then return end
    self.levels = self.levels or {}
    local key = e.id .. "|" .. what
    local L = self.levels[key] or { id = e.id, what = what }
    self.levels[key] = L
    L.want = value
    self:hold(e.id, what, value)
    if self.panel and not self.panel.closed then self.panel:sync() end
    if L.busy then return end
    if L.timer then UIManager:unschedule(L.timer) end
    L.timer = function()
        L.timer = nil
        self:sendLevel(key)
    end
    UIManager:scheduleIn(House.GATHER, L.timer)
end

--- A level that was asked for stays on the screen, whatever a refresh
--- says in the meantime (a player takes a moment to report it): kept in
--- `held` until it's let go (House.HOLD seconds after the last answer).
function House:hold(id, what, value)
    self.held = self.held or {}
    self.held[id] = self.held[id] or {}
    self.held[id][what] = value
    HA().setLevel(HA().find(self.house, id), what, value)
end

--- The levels held, put back into the devices as they are now (after
--- Home Assistant's states came in).
function House:keepHeld()
    local Ha = HA()
    for id, levels in pairs(self.held or {}) do
        local e = Ha.find(self.house, id)
        for what, value in pairs(levels) do Ha.setLevel(e, what, value) end
    end
end

function House:sendLevel(key)
    local Ha = HA()
    local L = self.levels and self.levels[key]
    if not L or L.busy or self.closed then return end
    local e = Ha.find(self.house, L.id)
    local value = L.want
    local domain, service, data = Ha.service(e, L.what, value)
    if not domain then self.levels[key] = nil; return end
    L.busy, L.sent = true, value
    -- (an answer that never comes, e.g. Wi-Fi gone: not busy for ever)
    UIManager:scheduleIn(House.STUCK, function()
        if self.levels and self.levels[key] == L and L.busy and L.sent == value then L.busy = false end
    end)
    local client = House.client(self.plugin)
    Log.info("house:", domain .. "." .. service, L.id)
    Net().run(function()
        Async().run(nil, function() return client:call(domain, service, data) end, function(changed, err)
            self:levelBack(key, changed, err)
        end, "house " .. service)
    end, { reason = "Home Assistant" })
end

--- Home Assistant answered a level (or didn't). A newer press since it
--- was sent: that one goes now. Otherwise it's done: the level is let go
--- of in a moment, and the tab fetched again.
function House:levelBack(key, changed, err)
    local Ha = HA()
    local L = self.levels and self.levels[key]
    if not L then return end
    L.busy = false
    if self.closed then return end
    if not changed then
        Log.warn("house: a level wasn't set:", L.what, L.id, tostring(err))
        self.levels[key] = nil
        if self.held and self.held[L.id] then self.held[L.id][L.what] = nil end
        info(Ha.why(err))
        return self:refresh(false)
    end
    if Ha.applyChanged(self.house, changed) then self:keepHeld() end
    if L.want ~= L.sent then return self:sendLevel(key) end
    self.levels[key] = nil
    Ha.saveCache(self.house)
    self:redraw()
    -- let go of it once the device has had time to report it
    local id, what, value = L.id, L.what, L.sent
    UIManager:scheduleIn(House.HOLD, function()
        if self.closed then return end
        local busy = self.levels and self.levels[key]
        if busy or not (self.held and self.held[id]) or self.held[id][what] ~= value then return end
        self.held[id][what] = nil
        if next(self.held[id]) == nil then self.held[id] = nil end
        self:refresh(false)
    end)
end

--- Every light in a room on or off (the wall's All lights): Home
--- Assistant's own light.turn_on / turn_off for the area.
function House:allLights(room_id, on)
    local Ha = HA()
    if type(room_id) ~= "string" or room_id:sub(1, 1) == "_" then return end
    local client = House.client(self.plugin)
    local service = on and "turn_on" or "turn_off"
    Log.info("house: light." .. service, "area", room_id)
    Net().run(function()
        Async().run(nil, function() return client:call("light", service, { area_id = room_id }) end, function(changed, err)
            if self.closed then return end
            if not changed then
                Log.warn("house: light." .. service, "failed:", tostring(err))
                return info(Ha.why(err))
            end
            if Ha.applyChanged(self.house, changed) then Ha.saveCache(self.house) end
            self:redraw()
            -- (lights answer as they change: the rest in a moment)
            UIManager:scheduleIn(2, function() self:refresh(false) end)
        end, "house lights")
    end, { reason = "Home Assistant" })
end

--- A dimmable light: On, Off, a step dimmer or brighter, or a level; a
--- colour, for a bulb that takes one.
function House:lightDialog(e)
    local Ha = HA()
    if Panel().wanted() then return Panel().show(self, e, "light") end
    local ButtonDialog = require("ui/widget/buttondialog")
    local d
    local function act(what, arg, again)
        UIManager:close(d)
        self:run(e, what, arg, again and function(now) self:lightDialog(now) end or nil)
    end
    local cur = (e.state == "on" and e.bri) or 0
    local function level(p) return { text = p .. "%", callback = function() act("brightness", p) end } end
    local buttons = {
        { { text = _("On"), callback = function() act("on") end }, { text = _("Off"), callback = function() act("off") end } },
        { { text = _("− 10%"), enabled = e.state == "on" and cur > 1, callback = function() act("brightness", math.max(1, cur - 10), true) end },
          { text = _("+ 10%"), enabled = cur < 100, callback = function() act("brightness", math.min(100, cur + 10), true) end } },
        { level(10), level(40), level(80), level(100) },
    }
    if e.col then
        -- a bulb that takes a colour: the colours, in two rows (the one it has now marked)
        local row
        for i, c in ipairs(Ha.BULB_COLORS) do
            if i % 4 == 1 then row = {}; buttons[#buttons + 1] = row end
            row[#row + 1] = { text = (e.state == "on" and e.rgb == c[1] and "● " or "") .. c[2], callback = function() act("color", c[1]) end }
        end
    end
    buttons[#buttons + 1] = { { text = _("Close"), callback = function() UIManager:close(d) end } }
    d = ButtonDialog:new{
        title = self:label(e) .. "\n" .. (Ha.stateText(e) or ""),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(d)
    return d
end

--- A thermostat: its target a step down or up, and its modes (heat, cool…).
function House:climateDialog(e)
    local Ha = HA()
    if Panel().wanted() then return Panel().show(self, e, "climate") end
    local ButtonDialog = require("ui/widget/buttondialog")
    local unit = store(self.plugin).unit
    local d
    local lines = { self:label(e) }
    if e.cur then lines[#lines + 1] = T(_("%1 now"), Ha.fmt(e.cur) .. "°") .. (e.action and e.action ~= "idle" and e.action ~= "off" and (" · " .. e.action) or "") end
    if e.target then lines[#lines + 1] = T(_("Target %1"), Ha.fmt(e.target) .. "°") end
    local function step(dir)
        local t = Ha.nextTarget(e, dir, unit)
        return { text = (dir < 0 and "− " or "+ ") .. Ha.fmt(t) .. "°", enabled = e.target ~= nil and t ~= e.target, callback = function()
            UIManager:close(d)
            self:run(e, "target", t, function(now) self:climateDialog(now) end)
        end }
    end
    local buttons = { { step(-1), step(1) } }
    if e.modes then
        -- heat, cool, off… (the one it's in marked)
        local row = {}
        for _i, m in ipairs(e.modes) do
            row[#row + 1] = { text = (e.state == m and "● " or "") .. Ha.modeName(m), callback = function()
                UIManager:close(d)
                self:run(e, "mode", m, function(now) self:climateDialog(now) end)
            end }
        end
        buttons[#buttons + 1] = row
    end
    buttons[#buttons + 1] = { { text = _("Close"), callback = function() UIManager:close(d) end } }
    d = ButtonDialog:new{
        title = table.concat(lines, "\n"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(d)
    return d
end

--- A media player (a speaker, a TV): play or pause, the song before and
--- after, its volume, shuffle and repeat, on and off: the ones it can do.
--- Music Assistant's players also choose what to play.
function House:mediaDialog(e)
    local Ha = HA()
    if Panel().wanted() then return Panel().show(self, e, "media") end
    local ButtonDialog = require("ui/widget/buttondialog")
    local d
    local function again(now) self:mediaDialog(now) end
    local function act(what, arg, stay)
        UIManager:close(d)
        self:run(e, what, arg, stay and again or nil)
    end
    local off = e.state == "off" or e.state == "standby"
    local lines = { self:label(e), Ha.stateText(e) or "" }
    if e.artist and (e.state == "playing" or e.state == "paused") then lines[#lines + 1] = e.artist end
    if e.vol then lines[#lines + 1] = e.muted and T(_("Volume %1% · muted"), e.vol) or T(_("Volume %1%"), e.vol) end
    local buttons = {}
    local function row(r) if #r > 0 then buttons[#buttons + 1] = r end end
    -- play or pause, the song before and after
    local r = {}
    if Ha.can(e, "previous") then r[#r + 1] = { text = _("Previous"), enabled = not off, callback = function() act("previous", nil, true) end } end
    if Ha.can(e, "play") or Ha.can(e, "pause") then
        r[#r + 1] = { text = e.state == "playing" and _("Pause") or _("Play"), enabled = not off, callback = function() act("play_pause", nil, true) end }
    end
    if Ha.can(e, "next") then r[#r + 1] = { text = _("Next"), enabled = not off, callback = function() act("next", nil, true) end } end
    row(r)
    -- its volume: a step down or up (it stays open for another), mute, and levels
    r = {}
    if Ha.can(e, "volume_set") and e.vol then
        r[#r + 1] = { text = T(_("− %1%"), Ha.VOLUME_STEP), enabled = e.vol > 0, callback = function() act("volume", Ha.nextVolume(e, -1), true) end }
        r[#r + 1] = { text = T(_("+ %1%"), Ha.VOLUME_STEP), enabled = e.vol < 100, callback = function() act("volume", Ha.nextVolume(e, 1), true) end }
    elseif Ha.can(e, "volume_step") then
        r[#r + 1] = { text = _("Quieter"), callback = function() act("volume_down", nil, true) end }
        r[#r + 1] = { text = _("Louder"), callback = function() act("volume_up", nil, true) end }
    end
    if Ha.can(e, "volume_mute") then
        r[#r + 1] = { text = e.muted and _("Unmute") or _("Mute"), callback = function() act("mute", nil, true) end }
    end
    row(r)
    if Ha.can(e, "volume_set") then
        r = {}
        for _i, p in ipairs(Ha.VOLUME_LEVELS) do
            r[#r + 1] = { text = (e.vol == p and "● " or "") .. p .. "%", callback = function() act("volume", p, true) end }
        end
        row(r)
    end
    -- shuffle and repeat (what each is now)
    r = {}
    if Ha.can(e, "shuffle") and e.shuffle ~= nil then
        r[#r + 1] = { text = e.shuffle and _("Shuffle: on") or _("Shuffle: off"), callback = function() act("shuffle", nil, true) end }
    end
    if Ha.can(e, "repeat") and e.rep then
        local words = { off = _("Repeat: off"), all = _("Repeat: all"), one = _("Repeat: one") }
        r[#r + 1] = { text = words[e.rep], callback = function() act("repeat", nil, true) end }
    end
    row(r)
    r = {}
    if e.ma and e.entry and Ha.can(e, "play_media") then
        r[#r + 1] = { text = _("Choose music…"), callback = function() UIManager:close(d); self:musicDialog(e) end }
    end
    if off and Ha.can(e, "turn_on") then r[#r + 1] = { text = _("Turn on"), callback = function() act("media_on", nil, true) end } end
    if not off and Ha.can(e, "turn_off") then r[#r + 1] = { text = _("Turn off"), callback = function() act("media_off") end } end
    row(r)
    buttons[#buttons + 1] = { { text = _("Close"), callback = function() UIManager:close(d) end } }
    d = ButtonDialog:new{ title = table.concat(lines, "\n"), title_align = "center", buttons = buttons }
    UIManager:show(d)
    return d
end

--- Choose music (a Music Assistant player): its playlists, albums, artists
--- or radio stations, or a search.
function House:musicDialog(e)
    local Ha = HA()
    local ButtonDialog = require("ui/widget/buttondialog")
    local d
    local buttons = {}
    local row
    for i, k in ipairs(Ha.MUSIC_KINDS) do
        if i % 2 == 1 then row = {}; buttons[#buttons + 1] = row end
        row[#row + 1] = { text = k[2], callback = function() UIManager:close(d); self:musicList(e, k[1], k[2], 0) end }
    end
    buttons[#buttons + 1] = { { text = _("Search…"), callback = function() UIManager:close(d); self:musicSearch(e) end } }
    buttons[#buttons + 1] = { { text = _("Back"), callback = function() UIManager:close(d); self:mediaDialog(HA().find(self.house, e.id) or e) end } }
    d = ButtonDialog:new{ title = T(_("Play on %1"), self:label(e)), title_align = "center", buttons = buttons }
    UIManager:show(d)
    return d
end

--- The rows of a list of Music Assistant's things: each plays when picked.
--- `more`: a last row to go on with (a list that may have more).
function House:musicRows(e, list, pick, more)
    local Ha = HA()
    local rows = {}
    for _i, it in ipairs(list or {}) do
        rows[#rows + 1] = { text = it.name, mandatory = pick.kinds and Ha.musicKindName(it.media_type) or it.by,
            gz_music_uri = it.uri, callback = function() pick.play(it) end }
    end
    if #rows == 0 then rows[1] = { text = pick.empty or _("Nothing here."), select_enabled = false, dim = true } end
    if more then rows[#rows + 1] = { text = _("More…"), callback = more } end
    return rows
end

--- Ask Music Assistant (in the background), then show what it has in a list.
function House:musicShow(e, title, ask, rows_of)
    local msg = InfoMessage:new{ text = _("Asking Music Assistant…"), timeout = 0 }
    Net().run(function()
        UIManager:show(msg)
        Async().run(nil, ask, function(list, err)
            UIManager:close(msg)
            if self.closed then return end
            if not list then
                Log.warn("house: Music Assistant didn't answer:", tostring(err))
                return info(HA().why(err))
            end
            local menu
            local pick = { play = function(it)
                UIManager:close(menu)
                self:run(e, "play", it)
                toast(T(_("%1: playing on %2"), it.name, self:label(e)))
            end }
            menu = Menu:new{
                title = title, item_table = rows_of(list, pick, function() UIManager:close(menu) end),
                covers_fullscreen = true, is_borderless = true, is_popout = false, title_bar_fm_style = true,
                onMenuSelect = function(_m, item) if item.callback then item.callback() end return true end,
            }
            menu.close_callback = function() UIManager:close(menu) end
            self.music_menu = menu
            UIManager:show(menu)
        end, "house music")
    end, { reason = "Home Assistant" })
end

--- One kind of Music Assistant's library (its playlists…), by name.
function House:musicList(e, media_type, title, offset)
    local Ha = HA()
    local client = House.client(self.plugin)
    Log.info("house: music_assistant.get_library", media_type, "from", offset)
    self:musicShow(e, title, function() return client:library(e.entry, media_type, offset) end, function(list, pick, close)
        pick.empty = offset > 0 and _("That's all of them.") or _("Music Assistant has none of these.")
        local more = #list >= Ha.MUSIC_PAGE and function()
            close()
            self:musicList(e, media_type, title, offset + Ha.MUSIC_PAGE)
        end or nil
        return self:musicRows(e, list, pick, more)
    end)
end

--- Search Music Assistant: what's typed, then what it found (each with its kind).
function House:musicSearch(e)
    local InputDialog = require("ui/widget/inputdialog")
    local client = House.client(self.plugin)
    local d
    d = InputDialog:new{
        title = _("Search Music Assistant"),
        input_hint = _("an artist, an album, a song, a playlist"),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                local q = (d:getInputText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
                UIManager:close(d)
                if q == "" then return end
                -- (what was typed isn't logged)
                Log.info("house: music_assistant.search")
                self:musicShow(e, T(_("Search: %1"), q), function() return client:searchMusic(e.entry, q) end, function(list, pick)
                    pick.kinds = true
                    pick.empty = _("Music Assistant found nothing for that.")
                    return self:musicRows(e, list, pick)
                end)
            end },
        } },
    }
    UIManager:show(d)
    d:onShowKeyboard()
    return d
end

---------------------------------------------------------------- the tab

--- The House tab (ZenOS's tab bar).
function House.show(plugin)
    pcall(function() require("gzreader_tabs").closeOthers(House.TAB_ID) end)
    local self = House.new(plugin)
    self.house = House.client(plugin):isConnected() and HA().loadCache() or nil
    self.menu = Menu:new{
        title = _("House"), item_table = self:rootItems(), covers_fullscreen = true, is_borderless = true,
        is_popout = false, title_bar_fm_style = true, _gz_navbar_tab_id = House.TAB_ID,
        onMenuSelect = function(_m, item) if item.callback then item.callback() end return true end,
    }
    self.menu.key_events = self.menu.key_events or {}
    self.menu.key_events.LeftButtonTap = nil
    pcall(require("gzreader_tabs").decorate, self.menu, _("House"))
    require("gzreader_rows").apply(self.menu)
    -- the Bookshelf view: the rooms as a wall with their fittings (gzreader_houseview.lua)
    pcall(function() require("gzreader_houseview").apply(self) end)
    -- Alt + Q, W, E… switch the bottom tabs (as in the other tabs)
    local digits = { "1", "2", "3", "4", "5", "6", "7", "8", "9" }
    local row = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O" }
    self.menu.key_events.GzTabKey = { { digits }, { "Alt", digits }, { "Alt", row } }
    self.menu.onGzTabKey = function(menu, _args, key)
        UIManager:close(menu)
        UIManager:nextTick(function()
            local FileManager = require("apps/filemanager/filemanager")
            local fc = FileManager.instance and FileManager.instance.file_chooser
            if fc and fc.onKeyPress then fc:onKeyPress(key) end
        end)
        return true
    end
    local orig_close = self.menu.onCloseWidget
    self.menu.onCloseWidget = function(m, ...)
        self.closed = true
        if self.panel and not self.panel.closed then UIManager:close(self.panel) end
        if self.tick then UIManager:unschedule(self.tick) end
        pcall(function() Net().release("house") end)
        if House.instance == self then House.instance = nil end
        if orig_close then return orig_close(m, ...) end
    end
    House.instance = self
    UIManager:show(self.menu)
    if House.client(plugin):isConnected() and not House.noWifi() then self:follow() end
    return self
end

---------------------------------------------------------------- connecting

--- How to connect (in the tab and in Settings). after() once connected.
function House.connectItems(plugin, after)
    local Rows = require("gzreader_rows")
    return Rows.mark({
        { text = _("Connect with QR code"), gz_icon = "send", callback = function() House.qrConnect(plugin, after) end },
        { text = _("Find Home Assistant on this Wi-Fi"), gz_icon = "search", callback = function() House.find(plugin, after) end },
        { text = _("Connect by typing"), gz_icon = "keyboard", callback = function() House.typeConnect(plugin, nil, after) end },
        Rows.about(_("About Home Assistant"), _("The House tab shows Home Assistant's rooms with their lights, switches, thermostats, locks, garage doors and scenes, to switch from here. GZreader talks to Home Assistant directly over your Wi-Fi.\n\nYou need Home Assistant's address (e.g. homeassistant.local:8123) and a long-lived access token: in Home Assistant open your profile → Security → Long-lived access tokens → Create token. An administrator's token also brings the rooms.\n\nConnect with QR code: a code to open on your phone, where you paste them.")),
    })
end

local function connected(plugin, after)
    local st = store(plugin)
    info(T(_("Connected to Home Assistant (%1)."), st.name or st.server or "?"), 3)
    if after then after() end
end

--- Connect with QR code: the phone page (gzreader_phone.lua), at House.
function House.qrConnect(plugin, after)
    Net().run(function()
        require("gzreader_phone").open(plugin, { section = "house", on_close = function(changes)
            if changes.house and House.client(plugin):isConnected() and after then after() end
        end })
    end, { reason = "connecting to Home Assistant" })
end

--- Address and token typed on the Kindle (`server`: an address to start with).
function House.typeConnect(plugin, server, after)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local d
    d = MultiInputDialog:new{
        title = _("Connect to Home Assistant"),
        fields = {
            { description = _("Home Assistant address"), text = server or store(plugin).server or "", hint = "homeassistant.local:8123" },
            { description = _("Long-lived access token"), text = "", hint = _("your profile → Security in Home Assistant"), text_type = "password" },
        },
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Connect"), is_enter_default = true, callback = function()
                local f = d:getFields()
                UIManager:close(d)
                Net().run(function()
                    local ok, err = HA().connect(plugin, f[1], f[2])
                    if ok then connected(plugin, after) else info(err) end
                end, { reason = "connecting to Home Assistant" })
            end },
        } },
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

--- What Home Assistant's announcement on the Wi-Fi (mDNS, _home-assistant._tcp)
--- gives as its address: its own internal address, else the one it says, else
--- where it answered from.
function House.foundAddress(dev)
    local t = type(dev) == "table" and type(dev.txt) == "table" and dev.txt or {}
    for _i, k in ipairs({ "internal_url", "base_url" }) do
        local u = t[k]
        if type(u) == "string" and u:match("^https?://[^/]+") then return (u:gsub("/+$", "")) end
    end
    if dev and dev.ip and dev.port then return "http://" .. dev.ip .. ":" .. dev.port end
end

--- Look for Home Assistant on the Wi-Fi for a few seconds, then connect by
--- typing with the address it found (only the token to paste).
function House.find(plugin, after)
    Net().run(function()
        local Mdns = require("gzreader_mdns")
        local browser = Mdns.browse({ service = Mdns.HA_SERVICE, collect = Mdns.collectService(Mdns.HA_SERVICE), duration = 4 })
        if not browser then return House.typeConnect(plugin, nil, after) end
        local msg = InfoMessage:new{ text = _("Looking for Home Assistant on this Wi-Fi…"), timeout = 0 }
        UIManager:show(msg)
        local function poll()
            browser:poll()
            if not browser:done() then return UIManager:scheduleIn(0.5, poll) end
            local found = browser:devices()
            browser:close()
            UIManager:close(msg)
            Log.info("house: found", #found, "on the Wi-Fi")
            if #found == 0 then
                info(_("No Home Assistant answered on this Wi-Fi. Type its address instead."), 3)
                return House.typeConnect(plugin, nil, after)
            end
            if #found == 1 then return House.typeConnect(plugin, House.foundAddress(found[1]), after) end
            local ButtonDialog = require("ui/widget/buttondialog")
            local d
            local buttons = {}
            for _i, dev in ipairs(found) do
                local addr = House.foundAddress(dev)
                local name = (dev.txt and dev.txt.location_name) or dev.name or addr
                buttons[#buttons + 1] = { { text = tostring(name) .. " · " .. (tostring(addr):gsub("^https?://", "")), callback = function()
                    UIManager:close(d)
                    House.typeConnect(plugin, addr, after)
                end } }
            end
            buttons[#buttons + 1] = { { text = _("Cancel"), callback = function() UIManager:close(d) end } }
            d = ButtonDialog:new{ title = _("Which Home Assistant?"), buttons = buttons }
            UIManager:show(d)
        end
        poll()
    end, { reason = "finding Home Assistant" })
end

---------------------------------------------------------------- Settings

--- Settings → Accounts and services → House.
function House.settingsItems(plugin)
    local Ha = HA()
    local function closeTouchMenu(tm) if tm and tm.closeMenu then pcall(tm.closeMenu, tm) end end
    local function refreshTab()
        if House.instance and not House.instance.closed then House.instance:reload() end
    end
    local items = {}
    local st = store(plugin)
    if House.client(plugin):isConnected() then
        items[#items + 1] = {
            text_func = function()
                local s = store(plugin)
                return T(_("Connected: %1 · %2"), s.name or _("Home Assistant"), (tostring(s.server or ""):gsub("^https?://", "")))
            end,
            enabled = false, separator = true,
        }
    else
        for _i, it in ipairs(House.connectItems(plugin, refreshTab)) do
            local cb = it.callback
            it.callback = function(tm) closeTouchMenu(tm); cb() end
            items[#items + 1] = it
        end
        items[#items].separator = true
    end
    local icons = Ha.ROOM_ICON:match("^(.*)/[^/]+$")
    items[#items + 1] = {
        text = _("House tab"), icon_file = Ha.ROOM_ICON,
        help_text = _("Its own tab in the tab bar, with Home Assistant's rooms. It can also be turned on or moved in Settings → Home and tabs → Tab bar → Tabs."),
        checked_func = House.tabShown,
        callback = function() House.setTabShown(not House.tabShown()) end,
    }
    if House.client(plugin):isConnected() then
        items[#items + 1] = {
            text = _("Rooms and devices"), icon_file = icons .. "/light.svg",
            help_text = _("Which rooms and devices the House tab shows. Devices Home Assistant hides are never shown."),
            sub_item_table_func = function() return House.roomItems(plugin) end,
        }
        items[#items + 1] = {
            text = _("Ask before unlocking or opening"), icon_file = icons .. "/lock.svg",
            help_text = _("Locks, garage doors, gates and doors ask before they're unlocked or opened from the House tab."),
            checked_func = function() return House.asks(plugin) end,
            callback = function() st = store(plugin); st.ask = not House.asks(plugin); plugin:save() end,
        }
        items[#items + 1] = {
            text = _("Disconnect"),
            keep_menu_open = true,
            callback = function(tm)
                confirm(_("Disconnect from Home Assistant? Its address and token are removed from the Kindle (the token still works until you delete it in Home Assistant: your profile → Security)."),
                    _("Disconnect"), function()
                        Ha.disconnect(plugin)
                        closeTouchMenu(tm)
                        refreshTab()
                    end)
            end,
        }
    end
    return items
end

--- Settings → Accounts and services → House → Rooms and devices: a room's
--- devices to tick, and the room itself.
function House.roomItems(plugin)
    local house = (House.instance and House.instance.house) or HA().loadCache()
    if not house or #(house.rooms or {}) == 0 then
        return { { text = _("Open the House tab once to load your rooms."), enabled = false } }
    end
    local function refreshTab() if House.instance and not House.instance.closed then House.instance:redraw() end end
    local items = {}
    for _i, r in ipairs(house.rooms) do
        items[#items + 1] = {
            text_func = function()
                local hr = store(plugin).hidden_rooms or {}
                return r.name .. (hr[r.id] and ("  " .. _("(hidden)")) or "")
            end,
            sub_item_table_func = function()
                local sub = {
                    { text = _("Show this room"), separator = true,
                      checked_func = function() return not (store(plugin).hidden_rooms or {})[r.id] end,
                      callback = function()
                          local s = store(plugin)
                          s.hidden_rooms = s.hidden_rooms or {}
                          s.hidden_rooms[r.id] = (not s.hidden_rooms[r.id]) or nil
                          plugin:save(); refreshTab()
                      end },
                }
                for _j, e in ipairs(r.entities or {}) do
                    sub[#sub + 1] = {
                        text = HA().shortName(e.name, house.by_kind and "" or r.name),
                        checked_func = function() return not (store(plugin).hidden or {})[e.id] end,
                        callback = function()
                            local s = store(plugin)
                            s.hidden = s.hidden or {}
                            s.hidden[e.id] = (not s.hidden[e.id]) or nil
                            plugin:save(); refreshTab()
                        end,
                    }
                end
                return sub
            end,
        }
    end
    return items
end

return House
