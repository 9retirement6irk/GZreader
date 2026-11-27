--[[--
Making the quick panel your own (Settings → Home and tabs → Quick panel):

- **Arrange tiles**: each group's tiles in the order you put them
  (G_reader_settings "gzreader_panel_order" = { <group> = { ids… } }). A tile
  that isn't in the saved order (a new one, one that wasn't on this Kindle
  then) comes after the ones that are, in its usual place among those.
- **Your tiles**: tiles of your own, in a third group on the panel, at Home
  and in a book ("gzreader_panel_own" = { { id, kind, label, … }, … }, at most
  MAX). Two kinds, as ZenOS's launcher has them (its scanners are used:
  modules/menu/app_launcher/plugin_scan.lua and native_menu.lua):
    plugin  a plugin's own screen or menu ({ key, method }): how a plugin
            copied into GZreader/app/plugins is opened, since the quick
            panel stands where KOReader's menu (with the plugins' entries) was
    menu    one of KOReader's own submenus ({ menu, scope }: "filemanager"
            at Home, "reader" in a book). A tile shows where its menu is.
]]

local _ = require("gettext")
local T = require("ffi/util").template

local Custom = {
    ORDER_KEY = "gzreader_panel_order",
    OWN_KEY = "gzreader_panel_own",
    MAX = 10,
    GROUP = "own",
    -- (GZreader's own plugins: their screens are the tabs and Settings)
    NOT_OFFERED = { gzreader = true, zenos = true, zen_ui = true },
}

local function settings() return rawget(_G, "G_reader_settings") end

---------------------------------------------------------------- the order

local function orders()
    local s = settings()
    local o = s and s:readSetting(Custom.ORDER_KEY)
    return type(o) == "table" and o or {}
end

--- `list` ({ { id = … }, … }) in the order saved for `group`. Pure but for the setting.
function Custom.ordered(group, list)
    local saved = orders()[group]
    if type(saved) ~= "table" or #saved == 0 then return list end
    local at = {}
    for i, id in ipairs(saved) do at[id] = i end
    local known, rest = {}, {}
    for i, t in ipairs(list) do
        if t.id and at[t.id] then known[#known + 1] = { t = t, k = at[t.id], i = i } else rest[#rest + 1] = t end
    end
    table.sort(known, function(a, b) if a.k ~= b.k then return a.k < b.k end; return a.i < b.i end)
    local out = {}
    for _i, k in ipairs(known) do out[#out + 1] = k.t end
    for _i, t in ipairs(rest) do out[#out + 1] = t end
    return out
end

function Custom.setOrder(group, ids)
    local s = settings()
    if not s then return end
    local o = {}
    for k, v in pairs(orders()) do o[k] = v end
    o[group] = (type(ids) == "table" and #ids > 0) and ids or nil
    if next(o) then s:saveSetting(Custom.ORDER_KEY, o) else s:delSetting(Custom.ORDER_KEY) end
end

function Custom.resetOrder()
    local s = settings()
    if s then s:delSetting(Custom.ORDER_KEY) end
end

---------------------------------------------------------------- your tiles

local function scanners()
    local okp, PluginScan = pcall(require, "modules/menu/app_launcher/plugin_scan")
    local okm, NativeMenu = pcall(require, "modules/menu/app_launcher/native_menu")
    return okp and type(PluginScan) == "table" and PluginScan or nil, okm and type(NativeMenu) == "table" and NativeMenu or nil
end

--- The saved tiles: { { id, kind = "plugin" | "menu", label, key, method, menu, scope }, … }.
function Custom.own()
    local s = settings()
    local list = s and s:readSetting(Custom.OWN_KEY)
    local out = {}
    for _i, e in ipairs(type(list) == "table" and list or {}) do
        if type(e) == "table" and type(e.id) == "string" and type(e.label) == "string"
                and ((e.kind == "plugin" and type(e.key) == "string" and type(e.method) == "string")
                    or (e.kind == "menu" and type(e.menu) == "string")) then
            out[#out + 1] = e
        end
    end
    return out
end

local function save(list)
    local s = settings()
    if not s then return end
    if #list > 0 then s:saveSetting(Custom.OWN_KEY, list) else s:delSetting(Custom.OWN_KEY) end
end

local function same(a, b)
    if a.kind ~= b.kind then return false end
    if a.kind == "plugin" then return a.key == b.key and a.method == b.method end
    return a.menu == b.menu and (a.scope or "filemanager") == (b.scope or "filemanager")
end

--- Add a tile; false and why ("full", "there") when it can't be.
function Custom.add(entry)
    local list = Custom.own()
    if #list >= Custom.MAX then return false, "full" end
    for _i, e in ipairs(list) do if same(e, entry) then return false, "there" end end
    local n, taken = 1, {}
    for _i, e in ipairs(list) do taken[e.id] = true end
    while taken["own" .. n] do n = n + 1 end
    entry.id = "own" .. n
    list[#list + 1] = entry
    save(list)
    return true
end

function Custom.remove(id)
    local list = {}
    for _i, e in ipairs(Custom.own()) do if e.id ~= id then list[#list + 1] = e end end
    save(list)
end

--- What a tile opens now: a function, or nil when it can't here (its plugin
--- isn't loaded; a book's menu at Home).
function Custom.resolve(e)
    local PluginScan, NativeMenu = scanners()
    if e.kind == "plugin" then
        if not (PluginScan and PluginScan.exists(e.key, e.method)) then return nil end
        return PluginScan.resolve(e.key, e.method)
    end
    local scope = e.scope or "filemanager"
    if not (NativeMenu and NativeMenu.exists(e.menu, scope)) then return nil end
    return NativeMenu.resolve(e.menu, scope)
end

--- The panel's tiles for them: { id, icon, label, run }, the ones that open here.
function Custom.tiles()
    local out = {}
    for _i, e in ipairs(Custom.own()) do
        local ok, launch = pcall(Custom.resolve, e)
        if ok and launch then
            out[#out + 1] = { id = e.id, icon = e.kind == "plugin" and "manage" or "more", label = e.label, full = true,
                run = function()
                    local okr, err = pcall(launch)
                    if not okr then require("gzreader_log").warn("quick panel: your tile", e.kind, "failed:", tostring(err)) end
                end }
        end
    end
    return Custom.ordered(Custom.GROUP, out)
end

--- What can be added: plugins' screens ({ kind = "plugin", key, method, label }).
function Custom.pluginChoices()
    local PluginScan = scanners()
    local out = {}
    local ok, found = pcall(function() return PluginScan and PluginScan.scan() or {} end)
    for _i, c in ipairs(ok and found or {}) do
        if type(c) == "table" and type(c.key) == "string" and not Custom.NOT_OFFERED[c.key] then
            -- (a menu row's text can carry its value, "Autosuspend timeout: 15m": the name alone)
            local label = tostring(c.title or c.key):gsub(":%s.*$", "")
            out[#out + 1] = { kind = "plugin", key = c.key, method = c.method, label = label ~= "" and label or c.key }
        end
    end
    return out
end

--- …and KOReader's submenus, where there's one now (`scope`: "filemanager" or "reader").
function Custom.menuChoices(scope)
    local NativeMenu = select(2, scanners())
    local out = {}
    local ok, found = pcall(function() return NativeMenu and NativeMenu.scan(scope) or {} end)
    for _i, c in ipairs(ok and found or {}) do
        if type(c) == "table" and type(c.id) == "string" and type(c.title) == "string" and c.title ~= "" then
            out[#out + 1] = { kind = "menu", menu = c.id, scope = scope, label = c.title, depth = tonumber(c.indent_level) or 0 }
        end
    end
    return out
end

---------------------------------------------------------------- Settings' rows

local function say(text)
    pcall(function()
        require("ui/uimanager"):show(require("ui/widget/infomessage"):new{ text = text, timeout = 2 })
    end)
end

local function redraw(touchmenu)
    if touchmenu and touchmenu.updateItems then pcall(touchmenu.updateItems, touchmenu) end
end

--- KOReader's "arrange" window for `tiles` ({ id, label }); on_done(ids).
function Custom.arrange(title, tiles, on_done)
    local UIManager = require("ui/uimanager")
    local SortWidget = require("ui/widget/sortwidget")
    local items = {}
    for _i, t in ipairs(tiles) do items[#items + 1] = { text = t.label, id = t.id } end
    local widget
    widget = SortWidget:new{
        title = title,
        item_table = items,
        callback = function()
            local ids = {}
            for _i, it in ipairs(items) do ids[#ids + 1] = it.id end
            on_done(ids)
        end,
    }
    UIManager:show(widget)
    return widget
end

local function addRow(choice, label)
    return {
        text = label or choice.label,
        keep_menu_open = true,
        callback = function(touchmenu)
            local ok, why = Custom.add({ kind = choice.kind, key = choice.key, method = choice.method, menu = choice.menu,
                scope = choice.scope, label = choice.label })
            if ok then
                say(T(_("%1 is on the quick panel, under Your tiles."), choice.label))
            elseif why == "full" then
                say(T(_("Your tiles are full (%1). Take one off first."), Custom.MAX))
            else
                say(T(_("%1 is already one of your tiles."), choice.label))
            end
            redraw(touchmenu)
        end,
    }
end

--- "Your tiles": the ones there (a tap takes one off), then what can be added.
function Custom.ownItem()
    return {
        text_func = function()
            local n = #Custom.own()
            return n == 0 and _("Your tiles") or T(_("Your tiles (%1)"), n)
        end,
        help_text = _("Tiles of your own on the quick panel, in a group under the others: a plugin's screen (the way to open a plugin you added to GZreader) or one of KOReader's own menus. A tile shows where it can open: a book's menu only in a book."),
        sub_item_table_func = function()
            local rows = {}
            for _i, e in ipairs(Custom.own()) do
                local gone = false
                rows[#rows + 1] = {
                    text_func = function()
                        if gone then return T(_("Taken off: %1"), e.label) end
                        return T(_("Take off: %1"), e.label) .. ((e.kind == "menu" and (e.scope or "filemanager") == "reader") and " " .. _("(in a book)") or "")
                    end,
                    enabled_func = function() return not gone end,
                    keep_menu_open = true,
                    callback = function(touchmenu)
                        Custom.remove(e.id)
                        gone = true
                        redraw(touchmenu)
                    end,
                }
            end
            if #rows > 0 then rows[#rows].separator = true end
            rows[#rows + 1] = {
                text = _("Add a plugin's screen"),
                help_text = _("The plugins that have a screen or a menu to open, GZreader's own aside."),
                sub_item_table_func = function()
                    local out = {}
                    for _i, c in ipairs(Custom.pluginChoices()) do out[#out + 1] = addRow(c) end
                    if #out == 0 then out[1] = { text = _("No plugin with a screen to open."), enabled_func = function() return false end } end
                    return out
                end,
            }
            rows[#rows + 1] = {
                text = _("Add one of KOReader's menus (Home)"),
                sub_item_table_func = function()
                    local out = {}
                    for _i, c in ipairs(Custom.menuChoices("filemanager")) do
                        out[#out + 1] = addRow(c, string.rep("    ", c.depth) .. c.label)
                    end
                    if #out == 0 then out[1] = { text = _("Open this from Home to list its menus."), enabled_func = function() return false end } end
                    return out
                end,
            }
            rows[#rows + 1] = {
                text = _("Add one of KOReader's menus (in a book)"),
                sub_item_table_func = function()
                    local out = {}
                    for _i, c in ipairs(Custom.menuChoices("reader")) do
                        out[#out + 1] = addRow(c, string.rep("    ", c.depth) .. c.label)
                    end
                    if #out == 0 then out[1] = { text = _("Open Settings from a book to list a book's menus."), enabled_func = function() return false end } end
                    return out
                end,
            }
            return rows
        end,
    }
end

--- "Arrange tiles": a row a group (`groups`: { { id, title, tiles = { { id, label } } } },
--- the tiles this Kindle has, in their order now), Your tiles, and the usual order back.
function Custom.arrangeItem(groups)
    local rows = {}
    for _i, g in ipairs(groups) do
        rows[#rows + 1] = {
            text = g.title,
            keep_menu_open = true,
            callback = function()
                local tiles = Custom.ordered(g.id, g.tiles())
                Custom.arrange(T(_("Arrange: %1"), g.title), tiles, function(ids) Custom.setOrder(g.id, ids) end)
            end,
        }
    end
    rows[#rows + 1] = {
        text = _("Your tiles"),
        enabled_func = function() return #Custom.own() > 1 end,
        keep_menu_open = true,
        callback = function()
            local tiles = {}
            for _i, e in ipairs(Custom.own()) do tiles[#tiles + 1] = { id = e.id, label = e.label } end
            Custom.arrange(T(_("Arrange: %1"), _("Your tiles")), Custom.ordered(Custom.GROUP, tiles),
                function(ids) Custom.setOrder(Custom.GROUP, ids) end)
        end,
        separator = true,
    }
    rows[#rows + 1] = {
        text = _("Back to the usual order"),
        keep_menu_open = true,
        callback = function()
            Custom.resetOrder()
            say(_("The tiles are in their usual order again."))
        end,
    }
    return {
        text = _("Arrange tiles"),
        help_text = _("Put each group's tiles in the order you like. On Kindles with keys the letters follow: the first tile of Controls is Q."),
        sub_item_table = rows,
    }
end

return Custom
