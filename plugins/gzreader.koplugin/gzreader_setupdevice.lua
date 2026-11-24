--[[--
Setting up on the device itself (the setup guide's "Set up on this device",
ZenOS common/quickstart/quickstart_pages.lua): which services to set up,
ticked there, and after the guide a list of the ticked ones, each connected
by typing on the device.

The services, in the order asked: Grimmory, BookOrbit (the book server: one
of the two, never both), Plex, Memos, Home Assistant, Immich, Mealie,
Calendar. One whose part this build or this device doesn't have isn't asked
(Plex on a device that plays no audio; Mealie before its tab exists).

A ticked service's tab is switched on, an unticked one's off: Notes (Memos),
Calendar, Music (Plex), House (Home Assistant), Recipes (Mealie).

Nothing typed is kept here: each service's own connect window does its own
signing in. Only which services were ticked is remembered
(store.setup_services), to show the list again.
]]

local _ = require("gettext")
local T = require("ffi/util").template

local Setup = {}

local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local function mod(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
end

--- The services: id, name, what it gives, the tab it has (`tab`: listed on
--- the guide's Navbar Tabs page; `setTab`: switched here), whether this
--- device has it, whether it's connected, and its connect-by-typing window.
Setup.SERVICES = {
    { id = "grimmory", name = "Grimmory", what = _("books, audiobooks, sync"), books = true,
        connected = function(p) return p.api:isPaired() and (type(p.backend) ~= "function" or p:backend() ~= "bookorbit") end,
        connect = function(p) p:keyboardLogin(nil, "grimmory") end },
    { id = "bookorbit", name = "BookOrbit", what = _("books, audiobooks, sync"), books = true,
        connected = function(p) return p.api:isPaired() and type(p.backend) == "function" and p:backend() == "bookorbit" end,
        connect = function(p) p:keyboardLogin(nil, "bookorbit") end },
    { id = "plex", name = "Plex", what = _("music, audiobooks"), tab = "ct_music",
        available = function() local Touch = mod("gzreader_touch"); return Touch ~= nil and try(Touch.player) == true end,
        connected = function(p) return require("gzreader_music").plex(p):isConnected() end,
        connect = function(p) require("gzreader_musictab").linkSignIn(p) end },
    { id = "memos", name = "Memos", what = _("notes, drawings, journal"), tab = "ct_notes",
        connected = function(p) return type(p.store.memos) == "table" and p.store.memos.token ~= nil end,
        connect = function(p) require("gzreader_notes").typeConnect(p) end },
    { id = "house", name = "Home Assistant", what = _("the House tab"),
        setTab = function(on) require("gzreader_house").setTabShown(on) end,
        connected = function(p) return require("gzreader_house").client(p):isConnected() end,
        connect = function(p) require("gzreader_house").typeConnect(p) end },
    { id = "immich", name = "Immich", what = _("photos for the sleep screen and wallpaper"),
        connected = function(p) return require("gzreader_immich").client(p):isConnected() end,
        connect = function(p) require("gzreader_immichsettings").typeConnect(p) end },
    { id = "mealie", name = "Mealie", what = _("the Recipes tab"),
        available = function() return mod("gzreader_recipes") ~= nil end,
        setTab = function(on) require("gzreader_recipes").setTabShown(on) end,
        connected = function(p) return require("gzreader_recipes").client(p):isConnected() end,
        connect = function(p) require("gzreader_recipes").typeConnect(p) end },
    { id = "calendar", name = _("Calendar"), what = _("CalDAV calendars and tasks"), tab = "ct_calendar",
        connected = function(p) return type(p.store.caldav) == "table" and p.store.caldav.password ~= nil end,
        connect = function(p) require("gzreader_calendar").typeConnect(p) end },
}

local function byId(id)
    for _i, s in ipairs(Setup.SERVICES) do if s.id == id then return s end end
    return nil
end

--- The services this device can set up, in the order asked.
function Setup.available()
    local out = {}
    for _i, s in ipairs(Setup.SERVICES) do
        if not s.available or try(s.available) == true then out[#out + 1] = s end
    end
    return out
end

function Setup.isConnected(plugin, id)
    local s = byId(id)
    return s ~= nil and try(s.connected, plugin) == true
end

--- The guide's tick boxes: { id, text, checked } per service; ticked to
--- start with: what's connected already.
function Setup.choices(plugin)
    local out = {}
    for _i, s in ipairs(Setup.available()) do
        out[#out + 1] = { id = s.id, text = T("%1: %2", s.name, s.what), checked = Setup.isConnected(plugin, s.id) }
    end
    return out
end

--- One book server at a time: ticking Grimmory unticks BookOrbit and the
--- other way round (`id`: the box just ticked or unticked). Pure.
function Setup.exclusive(sel, id)
    local s = byId(id)
    if s and s.books and sel[id] == true then
        for _i, other in ipairs(Setup.SERVICES) do
            if other.books and other.id ~= id then sel[other.id] = nil end
        end
    end
    return sel
end

--- The book server ticked: "grimmory", "bookorbit", or "local" (neither:
--- books sent from a browser).
function Setup.bookSource(sel)
    return (sel.bookorbit and "bookorbit") or (sel.grimmory and "grimmory") or "local"
end

--- The ticked services' ids, in the order asked.
function Setup.ticked(sel)
    local out = {}
    for _i, s in ipairs(Setup.available()) do
        if sel[s.id] == true then out[#out + 1] = s.id end
    end
    return out
end

--- The guide's answer: the book server and which services to set up are
--- remembered; tabs that aren't on the guide's Navbar Tabs page (House,
--- Recipes) are switched on or off here. Returns, for the Navbar Tabs
--- page, { [tab id] = on } for the tabs it lists.
function Setup.apply(plugin, sel)
    local store = plugin.store
    store.book_source = Setup.bookSource(sel)
    store.setup_services = Setup.ticked(sel)
    if type(plugin.save) == "function" then pcall(plugin.save, plugin) end
    local tabs = {}
    for _i, s in ipairs(Setup.available()) do
        local on = sel[s.id] == true
        if s.tab then tabs[s.tab] = on end
        if s.setTab then pcall(s.setTab, on) end
    end
    pcall(function() require("gzreader_log").info("setup on this device:", #store.setup_services, "service(s) chosen") end)
    return tabs
end

--- The list's rows for these ids: { text, mandatory, callback }.
function Setup.rows(plugin, ids, again)
    local rows = {}
    for _i, id in ipairs(ids) do
        local s = byId(id)
        if s then
            local on = Setup.isConnected(plugin, id)
            rows[#rows + 1] = {
                text = on and T(_("%1: connected"), s.name) or T(_("Connect %1"), s.name),
                mandatory = on and "✓" or _("not yet"),
                gz_service = id, gz_connected = on,
                callback = function()
                    pcall(s.connect, plugin)
                    if again then again() end
                end,
            }
        end
    end
    return rows
end

--- How the list stands, as one string (to see a change).
local function stamp(plugin, ids)
    local out = {}
    for _i, id in ipairs(ids) do out[#out + 1] = Setup.isConnected(plugin, id) and "1" or "0" end
    return table.concat(out)
end

--- After the guide (or from the event GzSetupOnDevice): the ticked services
--- as a list; a tap opens that service's own connect-by-typing window over
--- it. The list stays underneath and marks what got connected.
function Setup.show(plugin, ids)
    ids = ids or plugin.store.setup_services
    if type(ids) ~= "table" or #ids == 0 then return false end
    local UIManager = require("ui/uimanager")
    local Menu = require("ui/widget/menu")
    local Screen = require("device").screen
    local menu, last, tick
    local function items()
        local rows = Setup.rows(plugin, ids)
        rows[#rows + 1] = { text = _("Done"), callback = function() UIManager:close(menu) end }
        return rows
    end
    tick = function()
        if not menu or menu.gz_closed then return end
        local now = stamp(plugin, ids)
        if now ~= last then
            last = now
            menu:switchItemTable(nil, items(), -1)
        end
        UIManager:scheduleIn(3, tick)
    end
    menu = Menu:new{
        title = _("Set up on this device"),
        subtitle = _("Pick one to type its address and sign in"),
        item_table = items(),
        covers_fullscreen = true, is_borderless = true, is_popout = false,
        width = Screen:getWidth(), height = Screen:getHeight(),
        close_callback = function() UIManager:close(menu) end,
    }
    local closeWidget = menu.onCloseWidget
    function menu:onCloseWidget()
        self.gz_closed = true
        UIManager:unschedule(tick)
        if closeWidget then return closeWidget(self) end
    end
    function menu:onMenuSelect(item)
        if item and item.callback then item.callback() end
        return true
    end
    last = stamp(plugin, ids)
    UIManager:show(menu)
    UIManager:scheduleIn(3, tick)
    Setup.menu = menu
    return true
end

return Setup
