--[[--
The Music tab (ZenOS tab bar, off until turned on in Settings → Navbar →
Tabs), and "Now playing": music from Plex (gzreader_music.lua,
gzreader_plex.lua).

  Now playing: Title — Artist
  Downloaded             (offline: albums and playlists on the Kindle)
  Shuffle all downloaded
  Artists · Albums · Playlists · Search…
  Plex: <account> · <server>

An album or playlist: Play, Shuffle, Download (or Delete the download),
then its tracks (from that one). Play on one that isn't downloaded yet
downloads it in order and starts with the first track as soon as it's in.
]]

local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local function Music() return require("gzreader_music") end
local function Async() return require("gzreader_async") end

local Tab = { TAB_ID = "ct_music" }

local function fmtTime(ms)
    ms = tonumber(ms) or 0
    local s = math.floor(ms / 1000)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
Tab.fmtTime = fmtTime

local function busy(text)
    local m = InfoMessage:new{ text = text, timeout = 0 }
    UIManager:show(m)
    UIManager:forceRePaint()
    return m
end

local WHY = {
    unreachable = _("Couldn't reach Plex. Is Wi-Fi on?"),
    unauthorized = _("Plex says the sign-in isn't valid any more: sign in again."),
    no_server = _("This Plex account has no Plex Media Server."),
    server_unreachable = _("Couldn't reach your Plex Media Server from this Wi-Fi."),
    not_connected = _("Sign in to Plex first."),
    no_music = _("This Plex server has no music library."),
}
local function why(err) return WHY[err] or tostring(err) end

---------------------------------------------------------------- the menu

function Tab.new(plugin)
    local self = setmetatable({ plugin = plugin }, { __index = Tab })
    return self
end

function Tab:decorate(title)
    local menu = self.menu
    local FileManager = require("apps/filemanager/filemanager")
    local zen = (FileManager.instance and FileManager.instance.zenos) or rawget(_G, "__ZEN_UI_PLUGIN")
    if not (menu and menu.title_bar and zen) then return end
    local SharedState = require("common/shared_state")
    local createStatusRow = SharedState.get(zen, "createStatusRow")
    if type(createStatusRow) ~= "function" then return end
    local nested = #(menu.item_table_stack or {}) > 0
    require("modules/filebrowser/patches/standalone_page").apply_status_row(menu, {
        createStatusRow = createStatusRow,
        createStatusRowCustomBack = SharedState.get(zen, "createStatusRowCustomBack"),
        repaintTitleBar = SharedState.get(zen, "repaintTitleBar"),
        label = title,
        back_callback = nested and function() menu:onClose() end or nil,
    })
end

function Tab:push(title, items)
    if #items == 0 then items = { { text = _("Nothing here."), select_enabled = false } } end
    self.menu.item_table.title = self.menu.title
    table.insert(self.menu.item_table_stack, self.menu.item_table)
    self.menu:switchItemTable(title, items)
end

function Tab:replace(title, items) self.menu:switchItemTable(title, items) end

--- Fetch in the background (Plex on the network), then show.
function Tab:fetch(what, fn, on_data)
    local msg = busy(what)
    local plex = Music().plex(self.plugin)
    Async().run(nil, function() return fn(plex) end, function(a, b, c)
        UIManager:close(msg)
        if self.closed then return end
        if a == nil then return UIManager:show(InfoMessage:new{ text = why(b) }) end
        on_data(a, b, c)
    end, "plex " .. what)
end

--- The CD player with its library (1.22: all of music happens there); the
--- list menu below only if it fails, or without a speaker (it says why).
function Tab.player(plugin, opts)
    if Tab.LIST_PLAYER or not require("gzreader_touch").audio() then return nil end
    local ok, w = pcall(function() return require("gzreader_cdscreen").show(plugin, opts) end)
    if ok then return w end
    require("gzreader_log").warn("CD player screen:", tostring(w))
end

function Tab.show(plugin)
    pcall(function() require("gzreader_tabs").closeOthers(Tab.TAB_ID) end)
    local w = Tab.player(plugin, { library = not Music().current })
    if w then return w end
    return Tab.showList(plugin)
end

--- The Music tab as a list (KOReader's menu).
function Tab.showList(plugin)
    local self = Tab.new(plugin)
    self.menu = Menu:new{
        title = _("Music"), item_table = self:rootItems(), covers_fullscreen = true, is_borderless = true,
        is_popout = false, title_bar_fm_style = true, _gz_navbar_tab_id = Tab.TAB_ID,
        onMenuSelect = function(_m, item) if item.callback then item.callback() end return true end,
    }
    self.menu.key_events.LeftButtonTap = nil
    pcall(self.decorate, self, _("Music"))
    require("gzreader_rows").apply(self.menu)
    local orig_switch = self.menu.switchItemTable
    self.menu.switchItemTable = function(m, title, ...)
        local r = orig_switch(m, title, ...)
        if title then pcall(self.decorate, self, title) end
        return r
    end
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
    -- a download's progress line, kept current
    self.menu.onGzMusicDownload = function(m, st)
        -- (the 5-way stays on the line it was on)
        if Tab.updateProgress(m.item_table, st) then m:updateItems(m.selected and m.selected.y or nil, true) end
    end
    local key = "musictab-" .. tostring(self)
    Music().listeners[key] = function() self:refreshRoot() end
    local orig_close = self.menu.onCloseWidget
    self.menu.onCloseWidget = function(m, ...)
        self.closed = true
        Music().listeners[key] = nil
        if orig_close then return orig_close(m, ...) end
    end
    Tab.instance = self
    UIManager:show(self.menu)
    return self
end

--- A download's line in `items` (its progress): updated to `st`. True if
--- there was one.
function Tab.updateProgress(items, st)
    local found = false
    for _i, it in ipairs(items or {}) do
        if it.gz_music_dl and it.gz_music_dl == st.dir then
            it.text = st.finished and _("Download finished") or Music().progressText(st)
            found = true
        end
    end
    return found
end

--- The root list again (Now playing changed), when it's the one showing.
function Tab:refreshRoot()
    if self.closed or #self.menu.item_table_stack > 0 then return end
    self.menu:switchItemTable(nil, self:rootItems())
end

--- A list line with the Plex item it's for (`gz_music`: the Catalog draws
--- albums and playlists as CD cases, artists as compartments,
--- gzreader_shopviews.lua). Tracks stay plain lines.
function Tab.entry(item, it)
    if type(it) == "table" and (it.type == "album" or it.type == "playlist" or it.type == "artist") then
        item.gz_music = { type = it.type, key = it.key, title = it.title, artist = it.artist, year = it.year,
            thumb = it.thumb, count = it.count }
        if it.type == "artist" then item.gz_kind, item.gz_contents = "artist", "cds" end
    end
    return item
end

--- The Catalog's Music page (gzreader_catalog.lua): search at the top, then
--- Playlists, Albums, Artists (and what plays, what's on the Kindle, the
--- Plex account), each a compartment in the Bookshelf view (gz_kind
--- "section"). Not signed in: the sign-in lines. `after`: once signed in.
function Tab:catalogItems(after)
    local plugin = self.plugin
    local plex = Music().plex(plugin)
    if not plex:isConnected() then return self:rootItems(after) end
    local items = {
        gz_root = true, -- (the Bookshelf view: a shop, gzreader_bookshop.lua)
        { gz_id = "mu_search", gz_action = "search", text = _("Search music…"), callback = function() self:promptSearch() end },
        { gz_id = "mu_played", text = _("Recently played"), callback = function() self:openRecent("played") end },
        { gz_id = "mu_recent", text = _("Recently added"), callback = function() self:openRecent("added") end },
        { gz_id = "mu_playlists", gz_kind = "section", gz_contents = "cds", text = _("Playlists"), mandatory = _("yours on Plex"),
            callback = function() self:openPlaylists() end },
        { gz_id = "mu_albums", gz_kind = "section", gz_contents = "cds", text = _("Albums"), mandatory = _("A–Z"),
            callback = function() self:openSection("albums") end },
        { gz_id = "mu_artists", gz_kind = "section", gz_contents = "dividers", text = _("Artists"), mandatory = _("A–Z"),
            callback = function() self:openSection("artists") end },
    }
    local now = Music().nowText()
    if now then
        items[#items + 1] = { gz_id = "mu_now", gz_kind = "section", gz_contents = "cds", text = _("Now playing"), mandatory = now,
            callback = function() Tab.nowPlaying(plugin) end }
    end
    local list = Music().downloaded(plugin, { any = true })
    if #list > 0 then
        items[#items + 1] = { gz_id = "mu_downloaded", gz_kind = "section", gz_contents = "cds", text = _("On this Kindle"),
            mandatory = #list == 1 and _("1 album or playlist") or T(_("%1 albums and playlists"), #list),
            callback = function() self:openDownloaded() end }
        items[#items + 1] = { gz_id = "mu_shuffle", gz_kind = "section", gz_contents = "none", text = _("Shuffle all"),
            mandatory = _("everything on this Kindle"), callback = function() Music().shuffleAll(plugin) end }
    end
    local st = plugin.store.plex or {}
    items[#items + 1] = { gz_id = "mu_account", gz_kind = "section", gz_contents = "none", text = _("Plex"),
        mandatory = T(_("%1 · %2"), st.username or "?", (st.server or {}).name or "?"), callback = function() self:openAccount() end }
    return items
end

--- Recently played (this Kindle's, then Plex's) or Recently added, as a
--- list of albums and playlists (CD cases in the Catalog).
function Tab:openRecent(by)
    local title = by == "played" and _("Recently played") or _("Recently added")
    local function show(list)
        local items = {}
        for _i, it in ipairs(list or {}) do
            items[#items + 1] = Tab.entry({ text = (it.title or "?") .. (it.artist and (" — " .. it.artist) or ""),
                mandatory = it.year and tostring(it.year) or nil, callback = function() self:openItem(it) end }, it)
        end
        self:push(title, items)
    end
    local local_played = by == "played" and type(self.plugin.store.music_recent) == "table" and self.plugin.store.music_recent or {}
    self:fetch(_("Loading…"), function(p)
        local sec, err = p:musicSection()
        if not sec then return err == "no_music" and {} or nil, err end
        return p:recentAlbums(sec.key, by, 50) or {}
    end, function(list)
        local seen, out = {}, {}
        for _i, src in ipairs({ local_played, list }) do
            for _j, it in ipairs(src) do
                if type(it) == "table" and it.key and not seen[tostring(it.key)] then seen[tostring(it.key)] = true; out[#out + 1] = it end
            end
        end
        show(out)
    end)
end

--- The library's first list; `after`: what to do once signed in to Plex
--- (the Catalog's Music page shows itself again; here, this list).
function Tab:rootItems(after)
    local plugin = self.plugin
    local Rows = require("gzreader_rows")
    if not require("gzreader_touch").audio() then
        return Rows.mark({ Rows.about(_("No speaker on this Kindle"),
            _("This Kindle has no speaker or headphone jack, so it can't play music. The Kindle 2, Keyboard, DX and Touch can.")) })
    end
    local plex = Music().plex(plugin)
    local items = {}
    local now = Music().nowText()
    if now then
        items[#items + 1] = { text = _("Now playing"), mandatory = now, bold = true, gz_icon = Rows.FILE.music,
            callback = function() Tab.nowPlaying(plugin) end }
    end
    local list = Music().downloaded(plugin)
    if #list > 0 then
        items[#items + 1] = { text = _("Downloaded"), mandatory = tostring(#list), gz_icon = "download", callback = function() self:openDownloaded() end }
        items[#items + 1] = { text = _("Shuffle all downloaded"), gz_icon = "enable", callback = function() Music().shuffleAll(plugin) end }
    end
    if plex:isConnected() then
        items[#items + 1] = { text = _("Artists"), gz_icon = "authors", callback = function() self:openSection("artists") end }
        items[#items + 1] = { text = _("Albums"), gz_icon = "name:tab_music", callback = function() self:openSection("albums") end }
        items[#items + 1] = { text = _("Playlists"), gz_icon = "view_list", callback = function() self:openPlaylists() end }
        items[#items + 1] = { text = _("Search"), gz_icon = "search", callback = function() self:promptSearch() end }
        local s = plugin.store.plex
        items[#items + 1] = { text = _("Plex"), mandatory = T(_("%1 · %2"), s.username or "?", (s.server or {}).name or "?"),
            gz_icon = "connect", callback = function() self:openAccount() end }
    else
        for _i, it in ipairs(Tab.signInItems(plugin, after or function() self:replace(_("Music"), self:rootItems()) end)) do items[#items + 1] = it end
    end
    return Rows.mark(items)
end

--- Sign-in choices (here and in Settings). after() once signed in.
function Tab.signInItems(plugin, after)
    local Rows = require("gzreader_rows")
    return Rows.mark({
        { text = _("Plex: sign in with a code"), gz_icon = "keyboard", callback = function() Tab.linkSignIn(plugin, after) end },
        { text = _("Plex: sign in with QR code"), gz_icon = "send", callback = function()
            require("gzreader_net").run(function()
                require("gzreader_phone").open(plugin, { section = "music", on_close = function() if after then after() end end })
            end, { reason = "connecting to Plex" })
        end },
        Rows.about(_("About Plex music"), _("Music from your Plex Media Server: download albums and playlists and play them while you read. The Kindle plays MP3 and AAC; Plex converts FLAC and others to MP3.\n\nSign in with a code: go to plex.tv/link on a phone or computer and enter the code the Kindle shows. With QR code: open the page on your phone and sign in to Plex there.")),
    })
end

---------------------------------------------------------------- sign-in on the Kindle

--- A 4-character code to enter at plex.tv/link; checks every 3 s.
function Tab.linkSignIn(plugin, after)
    require("gzreader_net").run(function()
        local plex = Music().plex(plugin)
        local msg = busy(_("Asking Plex for a code…"))
        local pin, err = plex:newPin(false)
        UIManager:close(msg)
        plugin:save()
        if not pin then return UIManager:show(InfoMessage:new{ text = why(err) }) end
        local screen = Tab.codeScreen(pin.code, function() end)
        local deadline = os.time() + math.min(pin.expires or 900, 900)
        local poll
        local stopped = false
        screen.on_cancel = function() stopped = true end
        poll = function()
            if stopped then return end
            if os.time() > deadline then
                UIManager:close(screen)
                return UIManager:show(InfoMessage:new{ text = _("The code expired. Try again for a new one.") })
            end
            Async().run(nil, function() return plex:checkPin(pin) end, function(token, cerr)
                if stopped then return end
                if not token then
                    if cerr then Log.warn("plex: checking the code:", tostring(cerr)) end
                    return UIManager:scheduleIn(3, poll)
                end
                screen:setStatus(_("Signed in. Finding your Plex server…"))
                Async().run(nil, function()
                    local ok, e = plex:connect(token)
                    return ok and plex.store or nil, e
                end, function(store, e2)
                    UIManager:close(screen)
                    if not store then return UIManager:show(InfoMessage:new{ text = why(e2) }) end
                    Tab.signedIn(plugin, store)
                    if after then after() end
                end, "plex connect")
            end, "plex pin")
        end
        UIManager:scheduleIn(3, poll)
    end, { reason = "signing in to Plex" })
end

--- Keep what a background sign-in found.
function Tab.signedIn(plugin, store)
    local s = plugin.store.plex or {}
    s.token, s.username, s.server, s.servers = store.token, store.username, store.server, store.servers
    s.client_id = store.client_id or s.client_id
    plugin.store.plex = s
    plugin:save()
    UIManager:show(InfoMessage:new{ text = T(_("Signed in to Plex as %1 (%2)."), s.username or "?", (s.server or {}).name or "?"), timeout = 3 })
end

--- The full screen with the code.
function Tab.codeScreen(code, on_cancel)
    local Blitbuffer = require("ffi/blitbuffer")
    local Button = require("ui/widget/button")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local Size = require("ui/size")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Screen = Device.screen
    local W = InputContainer:extend{ name = "plex code screen", modal = true }
    function W:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
        if Device:hasKeys() then self.key_events.Cancel = { { Device.input.group.Back } } end
        self:build()
    end
    function W:build()
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local tw = math.floor(sw * 0.86)
        local gap = VerticalSpan:new{ width = Size.span.vertical_large * 2 }
        local group = VerticalGroup:new{ align = "center",
            TextBoxWidget:new{ text = _("Sign in to Plex"), face = Font:getFace("tfont", 24), width = tw, alignment = "center" },
            gap,
            TextBoxWidget:new{ text = _("On your phone or computer, go to"), face = Font:getFace("cfont", 18), width = tw, alignment = "center" },
            TextWidget:new{ text = "plex.tv/link", face = Font:getFace("cfont", 26), bold = true },
            gap,
            TextBoxWidget:new{ text = _("sign in to Plex there and enter this code:"), face = Font:getFace("cfont", 18), width = tw, alignment = "center" },
            VerticalSpan:new{ width = Size.span.vertical_large },
            TextWidget:new{ text = tostring(code):upper():gsub("(.)", "%1 "):sub(1, -2), face = Font:getFace("tfont", 56), bold = true },
            gap,
            TextBoxWidget:new{ text = self.status or _("Waiting for Plex…"), face = Font:getFace("cfont", 16), width = tw, alignment = "center" },
            gap,
        }
        if Device:isTouchDevice() then
            table.insert(group, Button:new{ text = _("Cancel"), width = math.floor(sw * 0.4), callback = function() self:onCancel() end })
        else
            table.insert(group, TextBoxWidget:new{ text = _("Press Back to stop."), face = Font:getFace("smallinfofont", 16), width = tw, alignment = "center" })
        end
        self[1] = FrameContainer:new{ background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, width = sw, height = sh,
            CenterContainer:new{ dimen = Geom:new{ w = sw, h = sh }, group } }
    end
    function W:setStatus(text)
        self.status = text
        self:build()
        UIManager:setDirty(self, function() return "ui", self.dimen end)
    end
    -- (a flash, but not inside the music player: only its own opening and closing flash)
    local function flash() return require("gzreader_eink").inPlayer(UIManager._window_stack) and "ui" or "full" end
    function W:onShow() UIManager:setDirty(self, function() return flash(), self.dimen end) end
    function W:onCloseWidget() UIManager:setDirty(nil, flash()) end
    function W:onCancel()
        UIManager:close(self)
        if self.on_cancel then self.on_cancel() end
        if on_cancel then on_cancel() end
        return true
    end
    local w = W:new{}
    UIManager:show(w)
    return w
end

---------------------------------------------------------------- browsing

local function itemText(it)
    if it.type == "album" then return it.title .. (it.artist and (" — " .. it.artist) or "") end
    if it.type == "track" then return it.title end
    return it.title
end

--- The chosen music library's key for playlists and search when the server
--- has more than one (with one: Plex's answer as before). Runs in the
--- background, like the lists.
function Tab.only(p)
    local sec, all = p:musicSection()
    return sec and type(all) == "table" and #all > 1 and sec.key or nil
end

--- What the Music library line says: the one chosen, or the server's first.
function Tab.libraryText(plugin)
    local s = plugin.store.plex or {}
    local m = s.music_section
    if type(m) == "table" and m.title and m.server == (s.server or {}).id then return T(_("Music library: %1"), m.title) end
    return _("Music library: the server's first")
end

--- Pick the music library to browse (a server can have several: Artists,
--- Albums, Recently added/played, and with several libraries Playlists and
--- Search, all come from that one). Asks Plex for its libraries first.
--- after(): once one was picked.
function Tab.chooseLibrary(plugin, after)
    require("gzreader_net").run(function()
        local msg = busy(_("Asking Plex for its libraries…"))
        local plex = Music().plex(plugin)
        Async().run(nil, function() return plex:musicSections() end, function(list, err)
            UIManager:close(msg)
            if not list then return UIManager:show(InfoMessage:new{ text = why(err) }) end
            if #list == 0 then return UIManager:show(InfoMessage:new{ text = why("no_music") }) end
            local s = plugin.store.plex or {}
            local cur = require("gzreader_plex").pickSection(list, s.music_section, s.server)
            local ButtonDialog = require("ui/widget/buttondialog")
            local dialog
            local buttons = {}
            for _i, sec in ipairs(list) do
                buttons[#buttons + 1] = { { text = (sec.key == cur.key and "\u{2713} " or "") .. sec.title, callback = function()
                    UIManager:close(dialog)
                    Tab.setLibrary(plugin, sec)
                    if after then after() end
                end } }
            end
            dialog = ButtonDialog:new{ title = _("Music library"), buttons = buttons }
            local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
            if add then pcall(add, dialog) end
            UIManager:show(dialog)
        end, "plex libraries")
    end, { reason = "Plex's libraries" })
end

--- What the Audiobooks line says: Grimmory's, or which Plex library.
function Tab.audiobooksText(plugin)
    local sec = require("gzreader_plex").audiobookSection(plugin.store.plex)
    if sec then return T(_("Audiobooks: from Plex (%1)"), sec.title or "?") end
    return _("Audiobooks: from Grimmory")
end

--- Pick where the Catalog's audiobooks come from: Grimmory, or one of the
--- Plex server's music libraries (Plex keeps audiobooks in a music library:
--- an album per book, the author as its artist). after(): once picked.
function Tab.chooseAudiobooks(plugin, after)
    require("gzreader_net").run(function()
        local msg = busy(_("Asking Plex for its libraries…"))
        local plex = Music().plex(plugin)
        Async().run(nil, function() return plex:musicSections() end, function(list, err)
            UIManager:close(msg)
            if not list then return UIManager:show(InfoMessage:new{ text = why(err) }) end
            local cur = require("gzreader_plex").audiobookSection(plugin.store.plex)
            local ButtonDialog = require("ui/widget/buttondialog")
            local dialog
            local function pick(sec)
                UIManager:close(dialog)
                Tab.setAudiobooks(plugin, sec)
                if after then after() end
            end
            local buttons = { { { text = (cur and "" or "\u{2713} ") .. _("Grimmory"), callback = function() pick(nil) end } } }
            for _i, sec in ipairs(list) do
                buttons[#buttons + 1] = { { text = ((cur and cur.key == sec.key) and "\u{2713} " or "") .. T(_("Plex: %1"), sec.title),
                    callback = function() pick(sec) end } }
            end
            dialog = ButtonDialog:new{ title = _("Audiobooks from"), buttons = buttons }
            local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
            if add then pcall(add, dialog) end
            UIManager:show(dialog)
        end, "plex libraries")
    end, { reason = "Plex's libraries" })
end

--- Audiobooks from Plex library `sec` ({ key, title }) on this server, or
--- from Grimmory (nil). The Catalog's audiobook shelves (and the music
--- library left to be the server's first, which skips this one) start again.
function Tab.setAudiobooks(plugin, sec)
    local s = plugin.store.plex or {}
    plugin.store.plex = s
    local before = type(s.audiobook_section) == "table" and s.audiobook_section.key
    s.audiobook_section = sec and { server = (s.server or {}).id, key = sec.key, title = sec.title } or nil
    plugin:save()
    if before ~= (sec and sec.key) then
        pcall(function() require("gzreader_bookshop").forgetMusic(plugin) end)
        local B = package.loaded["gzreader_browser"]
        if type(B) == "table" and type(B.current) == "table" then B.current._shop_audio = nil end
    end
    Log.info("plex: audiobooks from", sec and "a Plex library" or "Grimmory")
end

--- Keep `sec` ({ key, title }) as the music library of this server; the
--- Catalog's Music shelves (the old library's) are asked for again.
function Tab.setLibrary(plugin, sec)
    local s = plugin.store.plex or {}
    plugin.store.plex = s
    local before = type(s.music_section) == "table" and s.music_section.key
    s.music_section = { server = (s.server or {}).id, key = sec.key, title = sec.title }
    plugin:save()
    if before ~= sec.key then pcall(function() require("gzreader_bookshop").forgetMusic(plugin) end) end
    Log.info("plex: music library chosen")
end

function Tab:openSection(kind)
    local plex = Music().plex(self.plugin)
    self:fetch(_("Loading…"), function(p)
        local sec, err = p:musicSection()
        if not sec then return nil, err end
        local list, total = p:list(sec.key, kind, 0)
        if not list then return nil, total end
        return { section = sec.key, list = list, total = total }
    end, function(data)
        self.section = data.section
        self:showPaged(kind == "albums" and _("Albums") or _("Artists"), kind, data.list, data.total, 0)
    end)
    return plex
end

function Tab:showPaged(title, kind, list, total, start)
    local items = {}
    for _i, it in ipairs(list) do
        items[#items + 1] = Tab.entry({ text = itemText(it), mandatory = it.year and tostring(it.year) or nil,
            callback = function() self:openItem(it) end }, it)
    end
    if total and start + #list < total then
        items[#items + 1] = { text = T(_("More (%1 of %2)…"), start + #list, total), callback = function()
            self:fetch(_("Loading…"), function(p) return p:list(self.section, kind, start + #list) end, function(more)
                -- (one page at a time: the list doesn't grow past what a Kindle holds)
                self:replace(title, {})
                self:showPagedInPlace(title, kind, more, total, start + #list)
            end)
        end }
    end
    self:push(title, items)
end

function Tab:showPagedInPlace(title, kind, list, total, start)
    table.remove(self.menu.item_table_stack) -- (replace, not stack another level)
    self:showPaged(title, kind, list, total, start)
end

function Tab:openItem(it)
    if it.type == "artist" then
        return self:fetch(_("Loading…"), function(p) return p:children(it.key) end, function(albums)
            local items = {}
            for _i, a in ipairs(albums) do
                items[#items + 1] = Tab.entry({ text = a.title, mandatory = a.year and tostring(a.year) or nil, callback = function() self:openItem(a) end }, a)
            end
            self:push(it.title, items)
        end)
    end
    if it.type == "album" then
        return self:fetch(_("Loading…"), function(p) return p:children(it.key) end, function(tracks)
            self:showCollection({ kind = "album", key = it.key, title = it.title, artist = it.artist, year = it.year, thumb = it.thumb, tracks = tracks })
        end)
    end
    if it.type == "playlist" then
        return self:fetch(_("Loading…"), function(p)
            local all, start = {}, 0
            while true do
                local page, total = p:playlistItems(it.key, start)
                if not page then return nil, total end
                for _i, t in ipairs(page) do all[#all + 1] = t end
                start = start + #page
                if #page == 0 or not total or start >= total or start >= 500 then break end
            end
            return all
        end, function(tracks)
            self:showCollection({ kind = "playlist", key = it.key, title = it.title, thumb = it.thumb, tracks = tracks })
        end)
    end
    if it.type == "track" and it.album_key then
        return self:openItem({ type = "album", key = it.album_key, title = it.album or it.title, artist = it.artist })
    end
end

function Tab:openPlaylists()
    self:fetch(_("Loading…"), function(p) return p:playlists(Tab.only(p)) end, function(list)
        local items = {}
        for _i, pl in ipairs(list) do
            items[#items + 1] = Tab.entry({ text = pl.title, mandatory = pl.count and T(_("%1 tracks"), pl.count) or nil,
                callback = function() self:openItem(pl) end }, pl)
        end
        self:push(_("Playlists"), items)
    end)
end

function Tab:promptSearch()
    local d
    d = InputDialog:new{
        title = _("Search music"), input_hint = _("Artist, album or track"),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                local q = d:getInputText()
                UIManager:close(d)
                if q and q:match("%S") then self:search(q) end
            end },
        } },
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

function Tab:search(q)
    self:fetch(_("Searching…"), function(p) return p:search(q, Tab.only(p)) end, function(res)
        local items = {}
        local function add(head, list)
            if #list == 0 then return end
            items[#items + 1] = { text = head, select_enabled = false, bold = true }
            for _i, it in ipairs(list) do
                -- (artists, albums and tracks together: a plain list, also in the Catalog)
                items[#items + 1] = { text = itemText(it) .. (it.type == "track" and it.artist and (" — " .. it.artist) or ""),
                    callback = function() self:openItem(it) end }
            end
        end
        add(_("Artists"), res.artists); add(_("Albums"), res.albums); add(_("Tracks"), res.tracks)
        if #items == 0 then items = { { text = T(_("Nothing matches “%1”."), q), select_enabled = false } } end
        self:push(T(_("Search: %1"), q), items)
    end)
end

---------------------------------------------------------------- an album or playlist

function Tab:collectionItems(c)
    local plugin = self.plugin
    local M = Music()
    local have = M.find(plugin, c.kind, c.key)
    local dl = M.downloads[M.dirFor(plugin, c.kind, c.key)]
    local items = {}
    local function play(start, shuffle)
        local local_c = M.find(plugin, c.kind, c.key)
        local complete = local_c and local_c.have == #c.tracks
        if not complete then
            -- download (in order) and start with the first track as soon as it's in
            local st = M.download(plugin, c, { on_done = function(ok, err, state)
                if not ok and err and state then UIManager:show(InfoMessage:new{ text = M.resultText(state, err) }) end
            end })
            local_c = M.find(plugin, c.kind, c.key)
            if not local_c then return end
            if st and st.total > 0 then
                UIManager:show(InfoMessage:new{ text = _("Downloading: it starts as soon as the first track is in."), timeout = 3 })
            end
        end
        M.play(plugin, local_c, start, shuffle)
        Tab.nowPlaying(plugin)
    end
    items[#items + 1] = { text = _("Play"), bold = true, callback = function() play(1, false) end }
    items[#items + 1] = { text = _("Shuffle"), callback = function() play(math.random(1, math.max(1, #c.tracks)), true) end }
    if dl then
        -- (kept current while the download runs: GzMusicDownload)
        items[#items + 1] = { text = M.progressText(dl), gz_music_dl = dl.dir, callback = function()
            UIManager:show(require("ui/widget/confirmbox"):new{
                text = T(_("Stop downloading “%1”? The tracks already on the Kindle stay."), c.title or ""),
                ok_text = _("Stop"),
                ok_callback = function() M.stop(dl.dir) end,
            })
        end }
    elseif have and have.have == #c.tracks then
        items[#items + 1] = { text = T(_("Delete the download (%1 MB)"), math.floor(M.dirSize(have.dir) / 1048576 + 0.5)), callback = function()
            UIManager:show(require("ui/widget/confirmbox"):new{
                text = T(_("Delete “%1” from the Kindle? It stays in Plex."), c.title or ""),
                ok_text = _("Delete"),
                ok_callback = function()
                    M.delete(plugin, have)
                    self:replace(c.title, self:collectionItems(c))
                end,
            })
        end }
    else
        local mb, missing = 0, 0
        for i, t in ipairs(c.tracks) do
            local ready = have and have.tracks[i] and have.tracks[i].key == t.key and M.trackReady(have, have.tracks[i])
            if not ready then
                missing = missing + 1
                mb = mb + ((t.part and t.part.size) or 0)
            end
        end
        local partly = have and have.have > 0
        local label = partly and T(_("Download the %1 missing tracks"), missing) or _("Download for offline")
        local mbs = math.floor(mb / 1048576 + 0.5)
        if mbs > 0 then label = label .. " " .. T(_("(about %1 MB)"), mbs) end
        items[#items + 1] = { text = label,
            callback = function()
                M.download(plugin, c, { on_done = function(ok, err, state)
                    UIManager:show(InfoMessage:new{ text = state and M.resultText(state, err)
                        or T(_("“%1” is on the Kindle."), c.title or ""), timeout = ok and 4 or nil })
                    -- (the list, if it's still there: the downloaded ticks and what's left)
                    if self.menu and self.menu.title == c.title then self:replace(c.title, self:collectionItems(c)) end
                end })
                self:replace(c.title, self:collectionItems(c))
            end }
    end
    for i, t in ipairs(c.tracks) do
        local ready = have and have.tracks[i] and M.trackReady(have, have.tracks[i])
        items[#items + 1] = { text = (t.index and (t.index .. ". ") or (i .. ". ")) .. (t.title or "?")
            .. (c.kind == "playlist" and t.artist and (" — " .. t.artist) or ""),
            mandatory = (ready and "\u{2713} " or "") .. fmtTime(t.duration), callback = function() play(i, false) end }
    end
    return items
end

function Tab:showCollection(c)
    self:push(c.title, self:collectionItems(c))
end

function Tab:openDownloaded()
    local plugin = self.plugin
    local items = {}
    for _i, c in ipairs(Music().downloaded(plugin)) do
        items[#items + 1] = Tab.entry({ text = c.title .. (c.artist and (" — " .. c.artist) or ""),
            mandatory = c.have < #c.tracks and T(_("%1 of %2"), c.have, #c.tracks) or T(_("%1 tracks"), #c.tracks),
            callback = function() self:showCollection(c) end },
            { type = c.kind, key = c.key, title = c.title, artist = c.artist, year = c.year, count = #c.tracks })
    end
    self:push(_("Downloaded"), items)
end

---------------------------------------------------------------- account

function Tab:openAccount()
    local plugin = self.plugin
    local s = plugin.store.plex
    local items = {}
    for _i, b in ipairs(Music().BITRATES) do
        items[#items + 1] = { text = T(_("Quality when converting: %1 kbps"), b), mandatory = ((s.bitrate or 192) == b) and "\u{2713}" or nil,
            callback = function()
                s.bitrate = b
                plugin:save()
                self:replace(_("Plex"), {}); table.remove(self.menu.item_table_stack); self:openAccount()
            end }
    end
    items[#items + 1] = { text = s.shrink and _("Bigger MP3 and AAC made smaller: on") or _("Bigger MP3 and AAC made smaller: off"),
        callback = function()
            s.shrink = not s.shrink or nil
            plugin:save()
            self:replace(_("Plex"), {}); table.remove(self.menu.item_table_stack); self:openAccount()
        end }
    items[#items + 1] = { text = Tab.libraryText(plugin), callback = function()
        Tab.chooseLibrary(plugin, function()
            if self.closed then return end
            self:replace(_("Plex"), {}); table.remove(self.menu.item_table_stack); self:openAccount()
        end)
    end }
    items[#items + 1] = { text = Tab.audiobooksText(plugin), callback = function()
        Tab.chooseAudiobooks(plugin, function()
            if self.closed then return end
            self:replace(_("Plex"), {}); table.remove(self.menu.item_table_stack); self:openAccount()
        end)
    end }
    for _i, srv in ipairs(s.servers or {}) do
        if srv.id ~= (s.server or {}).id then
            items[#items + 1] = { text = T(_("Use the server “%1”"), srv.name or "?"), callback = function()
                self:fetch(_("Connecting…"), function(p)
                    local ok, err = p:connect(s.token, srv.id)
                    return ok and p.store or nil, err
                end, function(store)
                    Tab.signedIn(plugin, store)
                    self.menu:onClose()
                end)
            end }
        end
    end
    items[#items + 1] = { text = _("Sign out of Plex"), callback = function()
        UIManager:show(require("ui/widget/confirmbox"):new{
            text = _("Sign out of Plex on this Kindle? Downloaded music stays."),
            ok_text = _("Sign out"),
            ok_callback = function()
                Music().plex(plugin):signOut()
                plugin:save()
                self.menu:onClose()
                self:replace(_("Music"), self:rootItems())
            end,
        })
    end }
    self:push(_("Plex"), items)
end

---------------------------------------------------------------- Settings

local function closeTouchMenu(touchmenu)
    if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
end

--- Settings → Connections → Plex (Music): the account, the server, the
--- quality, downloaded music, signing in or out.
function Tab.settingsItems(plugin)
    local function st() return plugin.store.plex or {} end
    if not st().token then
        local items = {}
        for _i, it in ipairs(Tab.signInItems(plugin)) do
            local cb = it.callback
            items[#items + 1] = { text = it.text, enabled = cb ~= nil,
                -- (About keeps Settings open)
            callback = cb and function(touchmenu) if not it.gz_about then closeTouchMenu(touchmenu) end cb() end or nil }
        end
        items[#items + 1] = { text = _("Then turn the Music tab on: Settings → Navbar → Tabs."), enabled = false }
        return items
    end
    local items = {
        { text_func = function() return T(_("Signed in as %1"), st().username or "?") end, enabled = false },
        { text_func = function() return T(_("Plex server: %1"), (st().server or {}).name or "?") end,
          sub_item_table_func = function()
              local list = {}
              for _i, srv in ipairs(st().servers or {}) do
                  list[#list + 1] = { text = srv.name or "?", radio = true,
                      checked_func = function() return (st().server or {}).id == srv.id end,
                      callback = function(touchmenu)
                          if (st().server or {}).id == srv.id then return end
                          closeTouchMenu(touchmenu)
                          require("gzreader_net").run(function()
                              local msg = busy(_("Connecting…"))
                              Async().run(nil, function()
                                  local p = Music().plex(plugin)
                                  local ok, err = p:connect(st().token, srv.id)
                                  return ok and p.store or nil, err
                              end, function(store, err)
                                  UIManager:close(msg)
                                  if not store then return UIManager:show(InfoMessage:new{ text = why(err) }) end
                                  Tab.signedIn(plugin, store)
                              end, "plex connect")
                          end, { reason = "connecting to Plex" })
                      end }
              end
              if #list == 0 then list[1] = { text = _("No other Plex servers on this account."), enabled = false } end
              return list
          end },
        { text_func = function() return Tab.libraryText(plugin) end,
          help_text = _("Artists, Albums and the Catalog's Recently added and Recently played come from this music library. With several music libraries on the server, Playlists and Search keep to it too."),
          keep_menu_open = true,
          callback = function(touchmenu)
              Tab.chooseLibrary(plugin, function()
                  if touchmenu and touchmenu.updateItems then pcall(touchmenu.updateItems, touchmenu) end
              end)
          end },
        { text_func = function() return Tab.audiobooksText(plugin) end,
          help_text = _("Where the Catalog's audiobooks come from: Grimmory, or a library of this Plex server (Plex keeps audiobooks in a music library: an album per book, the author as its artist). Listening positions go to the same place. Audiobooks already on the Kindle stay and play as before."),
          keep_menu_open = true,
          callback = function(touchmenu)
              Tab.chooseAudiobooks(plugin, function()
                  if touchmenu and touchmenu.updateItems then pcall(touchmenu.updateItems, touchmenu) end
              end)
          end },
        { text_func = function() return T(_("Quality when converting: %1 kbps"), st().bitrate or 192) end,
          help_text = _("For music the Kindle can't play as it is (FLAC and others), Plex converts it to MP3 at this quality. MP3 and AAC download as they are, unless “Make bigger MP3 and AAC smaller” is on."),
          sub_item_table_func = function()
              local list = {}
              for _i, b in ipairs(Music().BITRATES) do
                  list[#list + 1] = { text = T(_("%1 kbps"), b), radio = true,
                      checked_func = function() return (st().bitrate or 192) == b end,
                      callback = function() st().bitrate = b; plugin:save() end }
              end
              return list
          end },
        { text = _("Make bigger MP3 and AAC smaller"),
          help_text = _("MP3 and AAC tracks of a higher quality than the one above are converted to MP3 at that quality by Plex too, to save room on the Kindle. Music already downloaded stays as it is."),
          checked_func = function() return st().shrink == true end,
          callback = function() st().shrink = not st().shrink or nil; plugin:save() end },
        { text_func = function()
              local n = #Music().downloaded(plugin)
              local mb = Music().dirSize(Music().root(plugin)) / 1048576
              return T(_("Downloaded music: %1 (%2 MB)"), n, string.format("%.0f", mb))
          end,
          sub_item_table_func = function()
              return { { text = _("Remove all downloaded music"), callback = function(touchmenu)
                  UIManager:show(require("ui/widget/confirmbox"):new{
                      text = _("Remove all the music downloaded on this Kindle? It stays on your Plex server."),
                      ok_text = _("Remove"),
                      ok_callback = function()
                          for _i, c in ipairs(Music().downloaded(plugin)) do Music().delete(plugin, c) end
                          closeTouchMenu(touchmenu)
                          UIManager:show(InfoMessage:new{ text = _("Downloaded music removed."), timeout = 3 })
                      end,
                  })
              end } }
          end },
        { text = _("Sign out of Plex"), callback = function(touchmenu)
            UIManager:show(require("ui/widget/confirmbox"):new{
                text = _("Sign out of Plex on this Kindle? Downloaded music stays."),
                ok_text = _("Sign out"),
                ok_callback = function()
                    Music().plex(plugin):signOut()
                    plugin:save()
                    closeTouchMenu(touchmenu)
                end,
            })
        end },
        { text = _("The Music tab: Settings → Navbar → Tabs. Headphones: Settings → Reader."), enabled = false },
    }
    return items
end

---------------------------------------------------------------- now playing

--- What the controls do (the Now playing screen, the Home and Reading
--- menus, the quick panel).
function Tab.controlItems(plugin, after)
    local M = Music()
    local p = M.current
    local function done() if after then after() end end
    if not p then
        local items = {}
        if #M.downloaded(plugin) > 0 then
            items[#items + 1] = { text = _("Shuffle all downloaded"), callback = function() M.shuffleAll(plugin); done() end }
        end
        items[#items + 1] = { text = _("Open the Music tab"), callback = function() Tab.open(plugin) end }
        return items
    end
    return {
        { text = p.playing and _("Pause") or _("Play"), callback = function() p:toggle(); done() end },
        { text = _("Next track"), callback = function() p:step(1); done() end },
        { text = _("Previous track"), callback = function() p:step(-1); done() end },
        { text = p.shuffle and _("Shuffle: on") or _("Shuffle: off"), callback = function() p:setShuffle(not p.shuffle); done() end },
        { text = ({ off = _("Repeat: off"), all = _("Repeat: all"), one = _("Repeat: this track") })[p["repeat"]] or _("Repeat: off"),
          callback = function() p:cycleRepeat(); done() end },
        { text = _("Stop"), callback = function() p:stop(); done() end },
    }
end

--- Now playing: what plays, the controls, the queue.
function Tab.nowPlaying(plugin)
    local M = Music()
    -- the CD player (gzreader_cdscreen.lua): what plays, or its library
    local w = Tab.player(plugin)
    if w then return w end
    local menu
    local function build()
        local p = M.current
        local items = {}
        if p then
            local t = p:track() or {}
            items[#items + 1] = { text = (t.title or "?") .. (t.artist and (" — " .. t.artist) or ""), bold = true,
                mandatory = p.waiting and _("downloading…") or (fmtTime(p:position()) .. " / " .. fmtTime(t.duration)), select_enabled = false }
            items[#items + 1] = { text = p.c.title or "", select_enabled = false }
        end
        for _i, it in ipairs(Tab.controlItems(plugin, function() menu:switchItemTable(nil, build()) end)) do items[#items + 1] = it end
        if p then
            items[#items + 1] = { text = _("Queue"), select_enabled = false, bold = true }
            for n, i in ipairs(p.order) do
                local t = p.c.tracks[i]
                items[#items + 1] = { text = (n == p.at and "\u{25B6} " or "") .. (t.title or "?") .. (t.artist and (" — " .. t.artist) or ""),
                    mandatory = fmtTime(t.duration), callback = function() p:jump(n); menu:switchItemTable(nil, build()) end }
            end
        end
        return items
    end
    menu = Menu:new{ title = _("Now playing"), item_table = build(), covers_fullscreen = true, is_borderless = true,
        is_popout = false, title_bar_fm_style = true,
        onMenuSelect = function(_m, item) if item.callback then item.callback() end return true end }
    local key = "nowplaying-" .. tostring(menu)
    M.listeners[key] = function() if menu then menu:switchItemTable(nil, build()) end end
    local orig_close = menu.onCloseWidget
    menu.onCloseWidget = function(m, ...)
        M.listeners[key] = nil
        if orig_close then return orig_close(m, ...) end
    end
    UIManager:show(menu)
    return menu
end

--- The Home and Reading menus' Music line: what plays (or Music), opening
--- Now playing (or the Music tab at Home).
function Tab.menuItem(plugin)
    return { text_func = function()
        local M = Music()
        local now = M.nowText()
        if now then
            return T(M.current.playing and _("Music: %1") or _("Music (paused): %1"), now)
        end
        return _("Music")
    end, callback = function()
        if Music().current then return Tab.nowPlaying(plugin) end
        Tab.open(plugin)
    end }
end

--- The Music tab from anywhere (Home menu, the quick panel); in a book,
--- Now playing instead (the tabs are at Home).
function Tab.open(plugin)
    local w = Tab.player(plugin, { library = not Music().current })
    if w then return w end
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI.instance then return Tab.nowPlaying(plugin) end
    return Tab.showList(plugin)
end

return Tab
