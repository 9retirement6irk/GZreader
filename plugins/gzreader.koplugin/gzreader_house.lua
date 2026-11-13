--[[--
The House tab: Home Assistant's rooms and what's in them, to switch from the
Kindle (ZenOS's tab bar; off until turned on in Settings → Connections →
Home Assistant → House tab, or Settings → Interface → Navbar → Tabs).

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

Rooms are Home Assistant's areas; with a token that isn't an administrator's
the list is grouped by kind instead (gzreader_homeassistant.lua says why).
The list shown at once is the last one kept on the Kindle; it's fetched again
when the tab opens and every REFRESH seconds while it's on the screen (not
under a book or another window), and a switch's answer goes straight in. The
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
    MAX_TABS = 7, -- (ZenOS's tab bar)
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

local function navbar()
    local zen = require("gzreader_tabs").zen()
    local nb = zen and type(zen.config) == "table" and zen.config.navbar
    if type(nb) ~= "table" then return nil end
    return nb, zen
end

--- Whether the House tab is in the tab bar.
function House.tabShown()
    local nb = navbar()
    return nb ~= nil and type(nb.show_tabs) == "table" and nb.show_tabs[House.TAB_ID] == true
end

--- Put the House tab in the tab bar, or take it out (as Settings → Interface
--- → Navbar → Tabs does). False when it can't (no ZenOS, or 7 tabs already).
function House.setTabShown(on)
    local nb, zen = navbar()
    if not nb then return false end
    nb.show_tabs = type(nb.show_tabs) == "table" and nb.show_tabs or {}
    nb.tab_order = type(nb.tab_order) == "table" and nb.tab_order or {}
    nb.custom_tabs = type(nb.custom_tabs) == "table" and nb.custom_tabs or {}
    local has_tab, listed = false, false
    for _i, t in ipairs(nb.custom_tabs) do if type(t) == "table" and t.id == House.TAB_ID then has_tab = true end end
    if not has_tab then table.insert(nb.custom_tabs, House.tabEntry()) end
    for _i, id in ipairs(nb.tab_order) do if id == House.TAB_ID then listed = true end end
    if not listed then table.insert(nb.tab_order, House.TAB_ID) end
    if on and nb.show_tabs[House.TAB_ID] ~= true then
        local count = 0
        for _i, id in ipairs(nb.tab_order) do if nb.show_tabs[id] == true then count = count + 1 end end
        if count >= House.MAX_TABS then
            info(_("The tab bar has 7 tabs already: turn one off first (Settings → Interface → Navbar → Tabs)."))
            return false
        end
    end
    nb.show_tabs[House.TAB_ID] = on and true or false
    if type(zen.saveConfig) == "function" then pcall(zen.saveConfig, zen) end
    local reinject = rawget(_G, "__ZEN_UI_REINJECT_NAVBARS") or rawget(_G, "__ZEN_UI_REINJECT_FM_NAVBAR")
    if type(reinject) == "function" then UIManager:scheduleIn(0, reinject) end
    Log.info("house: tab", on and "shown" or "hidden")
    return true
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
        text = Ha.shortName(e.name, id), mandatory = Ha.stateText(e), gz_icon = Ha.iconFile(e),
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
            _("Home Assistant is reached over Wi-Fi, and this Kindle syncs through a computer (it has no Wi-Fi, or Sync through a computer is chosen in Settings → Connections).")) })
    end
    if not House.client(plugin):isConnected() then
        return House.connectItems(plugin, function() self:reload() end)
    end
    local st = store(plugin)
    local hidden, hidden_rooms = st.hidden or {}, st.hidden_rooms or {}
    local items = {
        { text = _("Refresh"), gz_icon = Rows.FILE.sync, mandatory = self:updatedText(), gz_no_arrow = true,
          keep_menu_open = true, callback = function() self:refresh(true) end },
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

--- Draw the list again (keeping the page).
function House:redraw()
    if self.closed or not self.menu then return end
    self.menu:switchItemTable(nil, self:rootItems(), -1)
end

--- After connecting or disconnecting: the list from the start.
function House:reload()
    if self.closed or not self.menu then return end
    self.house, self.err = HA().loadCache(), nil
    self.menu:switchItemTable(nil, self:rootItems())
    if House.client(self.plugin):isConnected() and not House.noWifi() then self:refresh(true) end
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
            self:redraw()
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
    Log.info("house:", domain .. "." .. service, e.id)
    Net().run(function()
        Async().run(nil, function() return client:call(domain, service, data) end, function(changed, err)
            if self.closed then return end
            if not changed then
                Log.warn("house:", domain .. "." .. service, "failed:", tostring(err))
                return info(Ha.why(err))
            end
            if Ha.applyChanged(self.house, changed) then Ha.saveCache(self.house) end
            self:redraw()
            if what == "scene" or what == "script" then toast(T(_("%1: done"), self:label(e))) end
            -- (a scene changes others; an answer without the state: fetch again in a moment)
            if what == "scene" or #changed == 0 then
                UIManager:scheduleIn(2, function() self:refresh(false) end)
            end
            if after then after(Ha.find(self.house, e.id) or e) end
        end, "house " .. service)
    end, { reason = "Home Assistant" })
end

--- A dimmable light: On, Off, a step dimmer or brighter, or a level.
function House:lightDialog(e)
    local Ha = HA()
    local ButtonDialog = require("ui/widget/buttondialog")
    local d
    local function act(what, arg, again)
        UIManager:close(d)
        self:run(e, what, arg, again and function(now) self:lightDialog(now) end or nil)
    end
    local cur = (e.state == "on" and e.bri) or 0
    local function level(p) return { text = p .. "%", callback = function() act("brightness", p) end } end
    d = ButtonDialog:new{
        title = self:label(e) .. "\n" .. (Ha.stateText(e) or ""),
        title_align = "center",
        buttons = {
            { { text = _("On"), callback = function() act("on") end }, { text = _("Off"), callback = function() act("off") end } },
            { { text = _("− 10%"), enabled = e.state == "on" and cur > 1, callback = function() act("brightness", math.max(1, cur - 10), true) end },
              { text = _("+ 10%"), enabled = cur < 100, callback = function() act("brightness", math.min(100, cur + 10), true) end } },
            { level(10), level(40), level(80), level(100) },
            { { text = _("Close"), callback = function() UIManager:close(d) end } },
        },
    }
    UIManager:show(d)
    return d
end

--- A thermostat: its target a step down or up.
function House:climateDialog(e)
    local Ha = HA()
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
    d = ButtonDialog:new{
        title = table.concat(lines, "\n"),
        title_align = "center",
        buttons = {
            { step(-1), step(1) },
            { { text = _("Close"), callback = function() UIManager:close(d) end } },
        },
    }
    UIManager:show(d)
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
        if self.tick then UIManager:unschedule(self.tick) end
        pcall(function() Net().release("house") end)
        if House.instance == self then House.instance = nil end
        if orig_close then return orig_close(m, ...) end
    end
    House.instance = self
    UIManager:show(self.menu)
    if House.client(plugin):isConnected() and not House.noWifi() then
        -- (Wi-Fi stays on while the tab is open: it's asked every REFRESH seconds)
        pcall(function() Net().hold("house") end)
        self:refresh(true)
        self:schedule()
    end
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

--- Settings → Connections → Home Assistant.
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
        help_text = _("Its own tab in the tab bar, with Home Assistant's rooms. It can also be turned on or moved in Settings → Interface → Navbar → Tabs."),
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

--- Settings → Connections → Home Assistant → Rooms and devices: a room's
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
