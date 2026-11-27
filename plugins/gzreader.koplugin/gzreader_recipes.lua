--[[--
The Recipes tab: your Mealie recipes, to read from the Kindle (ZenOS's tab
bar; off until turned on in Settings → Accounts and services → Recipes →
Recipes tab, or Settings → Home and tabs → Tab bar → Tabs).

  Refresh                               340 recipes · 2 min ago
  Search                                                 ›
  Category                              All              ›
  Order                                 A to Z           ›
  Apple pie                             1 hour 20 minutes ›
  Banana bread                          1 hour           ›
  …
  More recipes                          50 of 340        ›

A recipe opens as a page of text: what it makes and how long it takes, the
ingredients, the numbered steps, the notes.

The list shown at once is the last one kept on the Kindle; it's fetched
again when the tab opens (when Wi-Fi is on, or may be turned on by itself)
and with Refresh. A recipe you've opened is kept too, so it opens at once
the next time and can be read with Wi-Fi off; it's fetched again quietly when
Wi-Fi is on. The Kindles without Wi-Fi (2, DX) can't reach Mealie: the tab
says so, and Settings doesn't offer it.

In the Bookshelf view the same rows are drawn as a recipe box: the
categories as its dividers' tabs, the recipes as the cards filed in it
(gzreader_recipebox.lua); the other views keep this list.

gzreader_mealie.lua talks to Mealie.
]]

local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local function M() return require("gzreader_mealie") end
local function Async() return require("gzreader_async") end
local function Net() return require("gzreader_net") end

local Recipes = {
    TAB_ID = "ct_recipes",
}
Recipes.__index = Recipes

local here = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$") or "plugins/gzreader.koplugin"
Recipes.ICON = here .. "/icons/recipes/recipe.svg"

local function info(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

local function confirm(text, ok_text, fn)
    UIManager:show(require("ui/widget/confirmbox"):new{ text = text, ok_text = ok_text, ok_callback = fn })
end

local function store(plugin)
    plugin.store.mealie = plugin.store.mealie or {}
    return plugin.store.mealie
end

function Recipes.client(plugin) return M():new(store(plugin)) end

--- No Wi-Fi to reach Mealie with: a Kindle 2 or DX, or syncing through a
--- computer chosen in Settings.
function Recipes.noWifi()
    if Net().usb then return true end
    local ok, Usb = pcall(require, "gzreader_usbsync")
    return ok and Usb.noWifi() or false
end

---------------------------------------------------------------- the tab bar

--- Whether the Recipes tab is in the tab bar.
function Recipes.tabShown() return require("gzreader_tabs").shown(Recipes.TAB_ID) end

--- Put the Recipes tab in the tab bar, or take it out (as Settings → Home
--- and tabs → Tab bar → Tabs does). False when it can't (no ZenOS, or 7
--- tabs already).
function Recipes.setTabShown(on)
    return require("gzreader_tabs").setShown(Recipes.TAB_ID, on, Recipes.tabEntry(), info)
end

--- The tab's entry in ZenOS's tab list (config/defaults.lua has the same).
function Recipes.tabEntry()
    return { id = Recipes.TAB_ID, type = "action", action = { gzreader_recipes = true }, label = "Recipes", icon = "tab_recipes" }
end

---------------------------------------------------------------- the list

function Recipes.new(plugin)
    return setmetatable({ plugin = plugin, filter = {} }, Recipes)
end

local function ago(at)
    if not at then return nil end
    local m = math.floor((os.time() - at) / 60)
    if m < 1 then return _("just now") end
    if m < 60 then return T(_("%1 min ago"), m) end
    if m < 24 * 60 then return os.date("%H:%M", at) end
    return os.date("%d %b", at)
end

--- Whether the list is narrowed (a search or a category).
function Recipes:filtered()
    return self.filter.search ~= nil or self.filter.category ~= nil
end

--- What the Refresh row says.
function Recipes:updatedText()
    if self.fetching then return _("updating…") end
    if self.err and not self.list then return _("couldn't update") end
    local list = self.list
    if not list then return "" end
    local n = list.total or #list.items
    local count = n == 1 and _("1 recipe") or T(_("%1 recipes"), n)
    local when = ago(list.at)
    return when and (count .. " · " .. when) or count
end

--- The list: Refresh, Search, Category and Order, then the recipes, and
--- More recipes while Mealie has more.
function Recipes:rootItems()
    local plugin = self.plugin
    local Rows = require("gzreader_rows")
    if Recipes.noWifi() then
        return Rows.mark({ Rows.about(_("No Wi-Fi here"),
            _("Mealie is reached over Wi-Fi, and this Kindle syncs through a computer (it has no Wi-Fi, or Sync through a computer is chosen in Settings → General → Transfer).")) })
    end
    if not Recipes.client(plugin):isConnected() then
        return Recipes.connectItems(plugin, function() self:reload() end)
    end
    local f = self.filter
    local items = {
        { text = _("Refresh"), gz_icon = Rows.FILE.sync, mandatory = self:updatedText(), gz_no_arrow = true,
          gz_recipes = "refresh", keep_menu_open = true, callback = function() self:refresh(true) end },
        { text = _("Search"), gz_icon = "search", mandatory = f.search, gz_recipes = "search", keep_menu_open = true, callback = function() self:askSearch() end },
        { text = _("Category"), gz_icon = "label", mandatory = f.category and f.category.name or _("All"), gz_recipes = "category", keep_menu_open = true,
          callback = function() self:askCategory() end },
        { text = _("Order"), gz_icon = "sort", mandatory = f.newest and _("Newest first") or _("A to Z"), gz_recipes = "order", keep_menu_open = true,
          callback = function() self:setFilter({ newest = not f.newest }) end },
    }
    local list = self.list
    if not list then
        items[#items + 1] = { text = self.err and M().why(self.err) or _("Loading…"), select_enabled = false, dim = true }
        return Rows.mark(items)
    end
    for _i, r in ipairs(list.items) do
        items[#items + 1] = { text = r.name, mandatory = r.time, gz_icon = Recipes.ICON, gz_recipe = r.slug, keep_menu_open = true,
            callback = function() self:open(r) end }
    end
    if #list.items == 0 then
        items[#items + 1] = { text = self:filtered() and _("No recipes found. Change the search or the category.") or _("No recipes in Mealie yet."),
            select_enabled = false, dim = true }
    end
    if (list.page or 1) < (list.pages or 1) then
        items[#items + 1] = { text = _("More recipes"), gz_icon = "download", gz_more = true, keep_menu_open = true,
            mandatory = self.fetching_more and _("loading…") or T(_("%1 of %2"), #list.items, list.total or "?"),
            callback = function() self:more() end }
    end
    if self.err then
        items[#items + 1] = { text = M().why(self.err), select_enabled = false, dim = true }
    end
    return Rows.mark(items)
end

--- Draw the list again. `keep_page`: on the page it's on (a refresh, More
--- recipes); otherwise from the top.
function Recipes:redraw(keep_page)
    if self.closed or not self.menu then return end
    self.menu:switchItemTable(nil, self:rootItems(), keep_page and -1 or nil)
end

--- After connecting or disconnecting: the list from the start.
function Recipes:reload()
    if self.closed or not self.menu then return end
    self.filter, self.err = {}, nil
    self.list = Recipes.client(self.plugin):isConnected() and M().loadList() or nil
    self.cats = self.list and self.list.cats or nil
    self:redraw()
    if Recipes.client(self.plugin):isConnected() and not Recipes.noWifi() then self:refresh(true) end
end

--- Change the search, category or order (`changes`: the fields to set;
--- `false` clears one) and fetch the list again.
function Recipes:setFilter(changes)
    for k, v in pairs(changes) do self.filter[k] = v or nil end
    self.list, self.err = nil, nil
    -- (the whole list, by name: the one kept on the Kindle, shown meanwhile)
    if not self:filtered() and not self.filter.newest then self.list = M().loadList() end
    self:redraw()
    self:refresh(true)
end

--- Fetch the list's first page. `asked`: you asked for it (Wi-Fi may be
--- turned on); otherwise only when Wi-Fi is on already (or may be, by its
--- mode).
function Recipes:refresh(asked)
    if self.fetching or self.closed then return end
    local plugin = self.plugin
    local client = Recipes.client(plugin)
    if not client:isConnected() or Recipes.noWifi() then return end
    local f = self.filter
    local opts = { search = f.search, category = f.category and f.category.id, newest = f.newest }
    local plain = not self:filtered() and not f.newest
    Net().run(function()
        if self.fetching or self.closed then return end
        self.fetching = true
        if asked then self:redraw(true) end
        Async().run(nil, function()
            local list, err = client:recipes(1, opts)
            -- (the categories with it: the recipe box's dividers; the list does without them)
            if list then list.cats = client:categories() end
            return list, err
        end, function(list, err)
            self.fetching = false
            if self.closed then return end
            -- (the search or category changed meanwhile: that one's answer is on its way)
            if f ~= self.filter or opts.search ~= self.filter.search or opts.newest ~= self.filter.newest
                    or opts.category ~= (self.filter.category and self.filter.category.id) then
                return self:refresh(true)
            end
            if list then
                list.at = os.time()
                self.cats = list.cats or self.cats
                list.cats = self.cats
                self.list, self.err = list, nil
                if plain then M().saveList(list) end
                Log.info("recipes: list fetched,", #list.items, "of", tostring(list.total), self:filtered() and "(narrowed)" or "")
            else
                self.err = err
                Log.warn("recipes: couldn't update:", tostring(err))
            end
            self:redraw(true)
        end, "recipes")
    end, { reason = "Mealie", quiet = not asked })
end

--- More recipes: the next page, added to the list.
function Recipes:more()
    local list = self.list
    if self.fetching or self.fetching_more or self.closed or not list or (list.page or 1) >= (list.pages or 1) then return end
    local client = Recipes.client(self.plugin)
    local f = self.filter
    local opts = { search = f.search, category = f.category and f.category.id, newest = f.newest }
    local next_page = (list.page or 1) + 1
    Net().run(function()
        if self.fetching_more or self.closed then return end
        self.fetching_more = true
        self:redraw(true)
        Async().run(nil, function() return client:recipes(next_page, opts) end, function(more, err)
            self.fetching_more = false
            if self.closed or self.list ~= list then return end
            if more then
                local seen = {}
                for _i, r in ipairs(list.items) do seen[r.slug] = true end
                for _i, r in ipairs(more.items) do
                    if not seen[r.slug] then list.items[#list.items + 1] = r end
                end
                list.page, list.pages, list.total = next_page, more.pages, more.total
                self.err = nil
            else
                self.err = err
                Log.warn("recipes: couldn't fetch more:", tostring(err))
            end
            self:redraw(true)
        end, "recipes more")
    end, { reason = "Mealie" })
end

--- Search: words to look for (in names, descriptions and ingredients, as
--- Mealie's own search does); empty shows every recipe again.
function Recipes:askSearch()
    local InputDialog = require("ui/widget/inputdialog")
    local d
    local function go(q)
        UIManager:close(d)
        q = tostring(q or ""):gsub("^%s+", ""):gsub("%s+$", "")
        self:setFilter({ search = q ~= "" and q or false })
    end
    d = InputDialog:new{
        title = _("Search recipes"),
        input = self.filter.search or "",
        input_hint = _("A name or an ingredient"),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("All recipes"), callback = function() go("") end },
            { text = _("Search"), is_enter_default = true, callback = function() go(d:getInputText()) end },
        } },
    }
    UIManager:show(d)
    d:onShowKeyboard()
    return d
end

--- Category: Mealie's categories to choose one from (or All).
function Recipes:askCategory()
    local client = Recipes.client(self.plugin)
    Net().run(function()
        Async().run(nil, function() return client:categories() end, function(cats, err)
            if self.closed then return end
            if not cats then return info(M().why(err)) end
            if #cats == 0 then return info(_("Mealie has no categories yet. Add some to your recipes there."), 4) end
            local ButtonDialog = require("ui/widget/buttondialog")
            local d
            local cur = self.filter.category and self.filter.category.id
            local buttons = { { { text = (cur == nil and "● " or "") .. _("All"), callback = function()
                UIManager:close(d)
                self:setFilter({ category = false })
            end } } }
            for _i, c in ipairs(cats) do
                buttons[#buttons + 1] = { { text = (cur == c.id and "● " or "") .. c.name, callback = function()
                    UIManager:close(d)
                    self:setFilter({ category = c })
                end } }
            end
            buttons[#buttons + 1] = { { text = _("Cancel"), callback = function() UIManager:close(d) end } }
            d = ButtonDialog:new{ title = _("Category"), title_align = "center", buttons = buttons }
            UIManager:show(d)
        end, "recipes categories")
    end, { reason = "Mealie" })
end

---------------------------------------------------------------- a recipe

--- A recipe's page: its name on top, the text below (KOReader's text
--- window: page keys and swipes turn its pages).
function Recipes.showRecipe(r, note)
    local TextViewer = require("ui/widget/textviewer")
    local text = M().pageText(r)
    if note then text = note .. "\n\n" .. text end
    local viewer = TextViewer:new{ title = r.name, text = text, justified = false }
    UIManager:show(viewer)
    return viewer
end

--- Open a recipe from the list. One kept on the Kindle opens at once (and
--- is fetched again quietly, for the next time, when Wi-Fi is on); another
--- is fetched first.
function Recipes:open(item)
    local client = Recipes.client(self.plugin)
    local slug = item.slug
    local kept = M().loadRecipe(slug)
    if kept then
        Log.info("recipes: a recipe opened from the Kindle's copy")
        Recipes.showRecipe(kept)
        Net().run(function()
            Async().run(nil, function() return client:fetchRecipe(slug) end, function(r)
                if r then M().saveRecipe(r) end
            end, "recipe again")
        end, { reason = "Mealie", quiet = true })
        return
    end
    Net().run(function()
        local msg = InfoMessage:new{ text = T(_("Opening %1…"), item.name), timeout = 0 }
        UIManager:show(msg)
        Async().run(nil, function() return client:fetchRecipe(slug) end, function(r, err)
            UIManager:close(msg)
            if self.closed then return end
            if not r then
                Log.warn("recipes: couldn't open a recipe:", tostring(err))
                return info(M().why(err))
            end
            M().saveRecipe(r)
            Log.info("recipes: a recipe opened,", #r.ingredients, "ingredient lines,", #r.steps, "step lines")
            Recipes.showRecipe(r)
        end, "recipe")
    end, { reason = "Mealie" })
end

---------------------------------------------------------------- the tab

--- The Recipes tab (ZenOS's tab bar).
function Recipes.show(plugin)
    pcall(function() require("gzreader_tabs").closeOthers(Recipes.TAB_ID) end)
    local self = Recipes.new(plugin)
    local connected = Recipes.client(plugin):isConnected()
    self.list = connected and M().loadList() or nil
    self.cats = self.list and self.list.cats or nil
    self.menu = Menu:new{
        title = _("Recipes"), item_table = self:rootItems(), covers_fullscreen = true, is_borderless = true,
        is_popout = false, title_bar_fm_style = true, _gz_navbar_tab_id = Recipes.TAB_ID,
        onMenuSelect = function(_m, item) if item.callback then item.callback() end return true end,
    }
    self.menu.key_events = self.menu.key_events or {}
    self.menu.key_events.LeftButtonTap = nil
    pcall(require("gzreader_tabs").decorate, self.menu, _("Recipes"))
    require("gzreader_rows").apply(self.menu)
    -- the Bookshelf view: a recipe box, the recipes as its cards (gzreader_recipebox.lua)
    pcall(function() require("gzreader_recipebox").apply(self) end)
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
        if Recipes.instance == self then Recipes.instance = nil end
        if orig_close then return orig_close(m, ...) end
    end
    Recipes.instance = self
    UIManager:show(self.menu)
    -- (nothing kept yet: fetched now, Wi-Fi turned on for it; otherwise only when Wi-Fi is on)
    if connected and not Recipes.noWifi() then self:refresh(self.list == nil) end
    return self
end

---------------------------------------------------------------- connecting

--- How to connect (in the tab and in Settings). after() once connected.
function Recipes.connectItems(plugin, after)
    local Rows = require("gzreader_rows")
    return Rows.mark({
        { text = _("Connect with QR code"), gz_icon = "send", callback = function() Recipes.qrConnect(plugin, after) end },
        { text = _("Connect by typing"), gz_icon = "keyboard", callback = function() Recipes.typeConnect(plugin, after) end },
        Rows.about(_("About Mealie"), _("The Recipes tab shows the recipes of your Mealie (mealie.io), a recipe manager you host yourself: search them, pick a category, and read one with its ingredients and steps. GZreader talks to Mealie directly.\n\nThere are two ways to sign in.\n\nAn API token: in Mealie open your profile → API tokens → Generate, and paste it with Mealie's address. Connect by typing does this on the Kindle.\n\nSingle sign-on, if your Mealie signs you in through an identity provider: Connect with QR code opens a page on your phone with a Sign in with single sign-on button. GZreader then asks Mealie for an API token of its own, named GZreader in your profile.\n\nEither way the Kindle keeps a token, never your password.")),
    })
end

local function connected(plugin, after)
    local st = store(plugin)
    info(T(_("Connected to Mealie as %1."), st.name or st.username or "?"), 3)
    if after then after() end
end

--- Connect with QR code: the phone page (gzreader_phone.lua), at Recipes.
function Recipes.qrConnect(plugin, after)
    Net().run(function()
        require("gzreader_phone").open(plugin, { section = "recipes", on_close = function(changes)
            if changes.recipes and Recipes.client(plugin):isConnected() and after then after() end
        end })
    end, { reason = "connecting to Mealie" })
end

--- Address and API token typed on the Kindle.
function Recipes.typeConnect(plugin, after)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local d
    d = MultiInputDialog:new{
        title = _("Connect to Mealie"),
        fields = {
            { description = _("Mealie address"), text = store(plugin).server or "", hint = "mealie.example.com" },
            { description = _("API token"), text = "", hint = _("your profile → API tokens in Mealie"), text_type = "password" },
        },
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Connect"), is_enter_default = true, callback = function()
                local f = d:getFields()
                UIManager:close(d)
                Net().run(function()
                    local ok, err = M().connect(plugin, f[1], f[2])
                    if ok then connected(plugin, after) else info(err) end
                end, { reason = "connecting to Mealie" })
            end },
        } },
    }
    UIManager:show(d)
    d:onShowKeyboard()
    return d
end

---------------------------------------------------------------- Settings

--- Settings → Accounts and services → Recipes.
function Recipes.settingsItems(plugin)
    local function closeTouchMenu(tm) if tm and tm.closeMenu then pcall(tm.closeMenu, tm) end end
    local function refreshTab()
        if Recipes.instance and not Recipes.instance.closed then Recipes.instance:reload() end
    end
    local items = {}
    local is_connected = Recipes.client(plugin):isConnected()
    if is_connected then
        items[#items + 1] = {
            text_func = function()
                local s = store(plugin)
                return T(_("Connected: %1 · %2"), s.name or s.username or "Mealie", (tostring(s.server or ""):gsub("^https?://", "")))
            end,
            enabled = false, separator = true,
        }
    else
        for _i, it in ipairs(Recipes.connectItems(plugin, refreshTab)) do
            local cb = it.callback
            it.callback = function(tm) closeTouchMenu(tm); cb() end
            items[#items + 1] = it
        end
        items[#items].separator = true
    end
    items[#items + 1] = {
        text = _("Recipes tab"), icon_file = Recipes.ICON,
        help_text = _("Its own tab in the tab bar, with your Mealie recipes. It can also be turned on or moved in Settings → Home and tabs → Tab bar → Tabs."),
        checked_func = Recipes.tabShown,
        callback = function() Recipes.setTabShown(not Recipes.tabShown()) end,
    }
    if is_connected then
        local made = store(plugin).token_id ~= nil
        items[#items + 1] = {
            text = _("Disconnect"),
            keep_menu_open = true,
            callback = function(tm)
                confirm(made
                        and _("Disconnect from Mealie? Its address and token are removed from the Kindle, with the recipes kept here. GZreader also asks Mealie to delete the token it made (named GZreader in your profile → API tokens).")
                        or _("Disconnect from Mealie? Its address and token are removed from the Kindle, with the recipes kept here (the token still works until you delete it in Mealie: your profile → API tokens)."),
                    _("Disconnect"), function()
                        M().disconnect(plugin)
                        closeTouchMenu(tm)
                        refreshTab()
                    end)
            end,
        }
    end
    return items
end

return Recipes
