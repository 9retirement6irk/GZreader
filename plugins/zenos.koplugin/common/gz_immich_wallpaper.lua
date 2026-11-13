-- GZreader: the Home wallpaper (Settings → Interface → Wallpaper) from a
-- picture of your Immich album (gzreader_immich.lua keeps them on the
-- Kindle). The picture is copied to FILE and library_background.path points
-- at it, so the pictures the album's next refresh removes never take the
-- wallpaper with them; each refresh copies another one there.
-- library_background.gz_immich marks it; gz_before = { path, enabled }: what
-- was set before, put back when it's turned off.
local M = {}

function M.file()
    if M.FILE then return M.FILE end -- (tests)
    return require("datastorage"):getDataDir() .. "/gzreader-immich-wallpaper.png"
end

local function zen()
    return rawget(_G, "__ZEN_UI_PLUGIN")
end

local function config()
    local p = M.plugin or zen()
    if p and type(p.config) == "table" then return p.config, p end
    local ok, cfg = pcall(function()
        local ConfigManager = require("config/manager")
        return ConfigManager.get() or ConfigManager.load()
    end)
    return ok and type(cfg) == "table" and cfg or nil, p
end

local function bg(create)
    local cfg = config()
    if type(cfg) ~= "table" then return nil end
    if type(cfg.library_background) ~= "table" then
        if not create then return nil end
        cfg.library_background = { enabled = false, path = "", opacity = 100 }
    end
    return cfg.library_background
end

local function save()
    local cfg, p = config()
    if p and type(p.saveConfig) == "function" then
        p:saveConfig()
    elseif cfg then
        pcall(function() require("config/manager").save(cfg) end)
    end
    pcall(function() require("common/ui/background").clearCache() end)
    -- Home and the tabs painted again with it
    pcall(function()
        local home = p and require("common/shared_state").get(p, "home")
        if home and type(home.invalidateNavbar) == "function" then home.invalidateNavbar() end
        if home and home.rebuildActive then home.rebuildActive() end
    end)
    pcall(function() require("ui/uimanager"):setDirty(nil, "full") end)
end

local function copy(src, dest)
    local i = io.open(src, "rb")
    if not i then return false end
    local data = i:read("*a")
    i:close()
    if not data or #data == 0 then return false end
    local tmp = dest .. ".part"
    local o = io.open(tmp, "wb")
    if not o then return false end
    o:write(data)
    o:close()
    return os.rename(tmp, dest) ~= nil
end

function M.isOn()
    local b = bg(false)
    return type(b) == "table" and b.gz_immich == true
end

--- The album's picture the wallpaper was made from (its name), or nil.
function M.source()
    local b = bg(false)
    return type(b) == "table" and b.gz_immich == true and b.gz_source or nil
end

--- Turn it on: with `picture` (a file) now, or once there are pictures
--- (M.changed). Returns "on" or "waiting".
function M.turnOn(picture)
    local b = bg(true)
    if not b then return nil end
    if b.gz_immich ~= true then
        b.gz_before = { path = b.path or "", enabled = b.enabled == true }
        b.gz_immich = true
    end
    if picture and copy(picture, M.file()) then
        b.path, b.enabled, b.gz_source = M.file(), true, picture
        save()
        return "on"
    end
    save()
    return "waiting"
end

--- Turn it off: the wallpaper set before (or none) back.
function M.turnOff()
    local b = bg(false)
    if not b or b.gz_immich ~= true then return end
    local before = type(b.gz_before) == "table" and b.gz_before or {}
    b.path = type(before.path) == "string" and before.path or ""
    b.enabled = before.enabled == true and b.path ~= ""
    b.gz_immich, b.gz_before, b.gz_source = nil, nil, nil
    save()
    os.remove(M.file())
end

--- Another picture (after new ones came from Immich).
function M.changed(picture)
    local b = bg(false)
    if not b or b.gz_immich ~= true or not picture then return false end
    if not copy(picture, M.file()) then return false end
    b.path, b.enabled, b.gz_source = M.file(), true, picture
    save()
    return true
end

local function gzreader()
    for _i, mod in ipairs({ "apps/reader/readerui", "apps/filemanager/filemanager" }) do
        local ok, cls = pcall(require, mod)
        local inst = ok and type(cls) == "table" and cls.instance
        if type(inst) == "table" and type(inst.gzreader) == "table" then return inst.gzreader end
    end
end

--- What turning it on does: "on", "waiting" (no pictures yet: they come with
--- the next refresh), or "no_album" (Immich not set up: nothing changes).
function M.toggle(gz)
    if M.isOn() then M.turnOff(); return "off" end
    local okI, Immich = pcall(require, "gzreader_immich")
    local st = gz and gz.store and gz.store.immich
    -- (a Kindle without Wi‑Fi: the album chosen on the sync page comes with the sync)
    if not okI or type(st) ~= "table" or not st.album then return "no_album" end
    local result = M.turnOn(okI and Immich.randomPicture() or nil)
    if result == "waiting" and gz and okI then
        pcall(Immich.refresh, gz, { force = true })
    end
    return result
end

--- Settings → Interface → Wallpaper → Picture from Immich.
function M.menuItem()
    local _ = require("gettext")
    return {
        text = _("Picture from Immich"),
        help_text = _("A picture from the Immich album chosen in Settings → Connections → Immich (Photos); another one each time new pictures come from the album."),
        checked_func = function() return M.isOn() end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local r = M.toggle(gzreader())
            local msg
            if r == "no_album" then
                msg = _("Connect Immich and choose an album first: Settings → Connections → Immich (Photos).")
            elseif r == "waiting" then
                msg = _("The wallpaper changes to a picture from Immich once the album's pictures are on the Kindle.")
            end
            if msg then
                local UIManager = require("ui/uimanager")
                UIManager:show(require("ui/widget/infomessage"):new{ text = msg, timeout = 5 })
            end
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }
end

--- An image chosen by hand (Wallpaper → Image): not Immich's any more.
function M.chosenByHand(b)
    if type(b) == "table" and b.gz_immich then b.gz_immich, b.gz_before, b.gz_source = nil, nil, nil end
end

return M
