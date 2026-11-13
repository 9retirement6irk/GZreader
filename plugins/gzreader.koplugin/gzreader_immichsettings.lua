--[[--
Settings → Connections → Immich (Photos): the connection, the album, what
its pictures are used for (the sleep screen, the Home wallpaper), how many
are kept on the Kindle, and Get new pictures now (gzreader_immich.lua).
Kindles without Wi‑Fi set it up on the sync page; here they only choose what
the album's pictures are used for.
]]

local UIManager = require("ui/uimanager")
local Immich = require("gzreader_immich")
local _ = require("gettext")
local T = require("ffi/util").template

local S = {}

local function info(text, timeout)
    UIManager:show(require("ui/widget/infomessage"):new{ text = text, timeout = timeout })
end

local function host(url) return (tostring(url or ""):gsub("^https?://", ""):gsub("/.*$", "")) end

local function Net() return require("gzreader_net") end

local function sleepUse()
    local cur = require("gzsleepmode").current(G_reader_settings)
    return (cur == "immich" or cur == "immich_auto") and cur or nil
end

local function Wallpaper()
    local ok, W = pcall(require, "common/gz_immich_wallpaper")
    return ok and W or nil
end

--- Pictures on the Kindle now.
function S.pictureCount()
    return #Immich.have()
end

--- After a refresh asked for here: what happened.
local function refreshNow(plugin, touchmenu)
    Net().run(function()
        info(_("Getting pictures from Immich…"), 2)
        Immich.refresh(plugin, { force = true }, function(ok, res)
            if ok then
                info(T(_("Immich: %1 new pictures, %2 on the Kindle."), res.got, S.pictureCount()), 4)
            elseif res ~= "busy" then
                info(T(_("Couldn't get pictures from Immich (%1)."), tostring(res)), 5)
            end
            if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end
        end)
    end, { reason = "getting pictures from Immich" })
end

function S.typeConnect(plugin, on_done)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local d
    d = MultiInputDialog:new{
        title = _("Connect to Immich"),
        fields = {
            { description = _("Immich address"), text = (plugin.store.immich or {}).server or "", hint = "https://photos.example.com" },
            { description = _("API key"), text = "", hint = _("from Immich → Account Settings → API Keys"), text_type = "password" },
        },
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Connect"), is_enter_default = true, callback = function()
                local f = d:getFields()
                UIManager:close(d)
                Net().run(function()
                    local ok, err = Immich.connect(plugin, f[1], f[2])
                    if ok then
                        -- (then the album: the list's already here)
                        S.chooseAlbum(plugin)
                    else
                        info(err)
                    end
                    if on_done then on_done(ok) end
                end, { reason = "connecting to Immich" })
            end },
        } },
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

function S.qrConnect(plugin, on_done)
    require("gzreader_phone").open(plugin, { section = "immich", on_close = function(ch)
        if on_done then on_done(ch.immich) end
    end })
end

--- The albums to choose from (Immich's list, asked now).
function S.chooseAlbum(plugin, touchmenu)
    Net().run(function()
        local albums, err = Immich.client(plugin):albums()
        if not albums then return info(T(_("Couldn't get the albums from Immich (%1)."), tostring(err))) end
        if #albums == 0 then return info(_("There are no albums in Immich yet: make one there and add the pictures you want to see here.")) end
        plugin.store.immich.albums = albums
        local ButtonDialog = require("ui/widget/buttondialog")
        local d
        local buttons = {}
        local cur = (plugin.store.immich.album or {}).id
        for _i, a in ipairs(albums) do
            buttons[#buttons + 1] = { {
                text = (a.id == cur and "✓ " or "") .. T(_("%1 (%2)"), a.name, a.count),
                callback = function()
                    UIManager:close(d)
                    Immich.setAlbum(plugin, a)
                    if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end
                    refreshNow(plugin, touchmenu)
                end,
            } }
        end
        buttons[#buttons + 1] = { { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end } }
        d = ButtonDialog:new{ title = _("Which album?"), buttons = buttons }
        UIManager:show(d)
    end, { reason = "listing Immich albums" })
end

local function useItem(id, text)
    return {
        text = text,
        radio = true,
        checked_func = function()
            if id == "none" then return sleepUse() == nil end
            return sleepUse() == id
        end,
        callback = function()
            if id == "none" then
                if sleepUse() == "immich_auto" then require("gzsleepmode").use(G_reader_settings, "auto")
                elseif sleepUse() == "immich" then require("gzsleepmode").use(G_reader_settings, "random_image") end
            else
                require("gzsleepmode").use(G_reader_settings, id)
            end
        end,
    }
end

function S.items(plugin)
    local st = plugin.store.immich or {}
    local usb = Net().usb
    local connected = Immich.client(plugin):isConnected() or (usb and st.usb == true)
    local items = {}
    if usb and not connected then
        items[#items + 1] = { text = _("Set up Immich on the sync page (Connections → Immich), then sync."), enabled = false }
    elseif not connected then
        items[#items + 1] = { text = _("Connect with QR code"), keep_menu_open = true,
            callback = function(tm) Net().run(function() S.qrConnect(plugin, function() if tm and tm.updateItems then tm:updateItems() end end) end, { reason = "connecting to Immich" }) end }
        items[#items + 1] = { text = _("Connect by typing"), keep_menu_open = true,
            callback = function(tm) S.typeConnect(plugin, function() if tm and tm.updateItems then tm:updateItems() end end) end }
        items[#items + 1] = { text = _("About Immich"), keep_menu_open = true, callback = function()
            info(_("Pictures from one of your Immich albums for the sleep screen and the Home wallpaper. You need your Immich address and an API key: in Immich, Account Settings → API Keys → New API key (with album.read, asset.read and asset.view, or all permissions)."))
        end }
        return items
    else
        items[#items + 1] = { text_func = function()
            if usb then return T(_("Immich: through the sync page (%1)"), host(st.server)) end
            return T(_("Connected to %1"), host(st.server)) .. (st.user and (" · " .. st.user) or "")
        end, enabled = false }
        items[#items + 1] = { text_func = function()
            local a = (plugin.store.immich or {}).album
            return a and T(_("Album: %1"), a.name) or _("Album: choose one")
        end, keep_menu_open = true, enabled = not usb,
            callback = function(tm) S.chooseAlbum(plugin, tm) end, separator = true }
    end
    -- what it's for
    items[#items + 1] = { text = _("Sleep screen"), sub_item_table = {
        useItem("immich_auto", _("Book cover while reading, an Immich picture elsewhere")),
        useItem("immich", _("An Immich picture, always")),
        useItem("none", _("Not used (pictures from the screensavers folder)")),
    } }
    items[#items + 1] = { text = _("Home wallpaper"), help_text = _("A picture from the album as the wallpaper of Home and the tabs (Settings → Interface → Wallpaper); another one each time new pictures come."),
        checked_func = function() local W = Wallpaper(); return W ~= nil and W.isOn() end,
        keep_menu_open = true,
        callback = function(tm)
            local W = Wallpaper()
            if not W then return end
            local r = W.toggle(plugin)
            if r == "waiting" then info(_("The wallpaper changes to a picture from Immich once the album's pictures are on the Kindle."), 4) end
            if tm and tm.updateItems then tm:updateItems() end
        end, separator = true }
    if not usb then
        local counts = {}
        for _i, n in ipairs(Immich.COUNTS) do
            counts[#counts + 1] = { text = T(_("%1 pictures"), n), radio = true,
                checked_func = function() return Immich.count(plugin) == n end,
                callback = function() plugin.store.immich.count = n; plugin:save() end }
        end
        items[#items + 1] = { text_func = function() return T(_("Pictures kept on the Kindle: %1"), Immich.count(plugin)) end, sub_item_table = counts }
        items[#items + 1] = { text_func = function()
            local s = plugin.store.immich or {}
            local when = s.at and os.date("%Y-%m-%d %H:%M", s.at) or _("not yet")
            return T(_("Get new pictures now (last: %1)"), when)
        end, keep_menu_open = true, enabled_func = function() return (plugin.store.immich or {}).album ~= nil end,
            callback = function(tm) refreshNow(plugin, tm) end }
    end
    items[#items + 1] = { text = usb and _("Remove Immich from this Kindle") or _("Disconnect"), keep_menu_open = true, callback = function(tm)
        UIManager:show(require("ui/widget/confirmbox"):new{
            text = usb and _("Remove Immich's pictures from this Kindle? The sleep screen goes back to the screensavers folder. The next sync brings them again unless Immich is disconnected on the sync page.")
                or _("Disconnect Immich? Its pictures are removed from the Kindle; the sleep screen goes back to the screensavers folder."),
            ok_text = _("Disconnect"),
            ok_callback = function()
                Immich.disconnect(plugin)
                if tm and tm.updateItems then tm:updateItems() end
            end,
        })
    end }
    return items
end

return S
