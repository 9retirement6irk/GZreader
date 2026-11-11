--[[--
GZreader's lists drawn like ZenOS's Settings rows: an icon on the left, the
label, what the row says on the right (a count, a percentage), and an arrow
on the right of every row that opens or does something; ZenOS's row height
and spacing.

Used by the lists GZreader shows as menus (the Calendar and Notes tabs'
connect lists, Plex's sign-in, the Music tab's list, Downloads, the sync
queue, copying from another GZreader, the Notes filters, the font list, Add
to shelf). Lists of books, albums and tracks keep their own look.

    local Rows = require("gzreader_rows")
    local items = Rows.mark({
        { text = _("Type a calendar link"), gz_icon = "keyboard", callback = … },
        Rows.about(_("About calendar links"), _("The long explanation…")),
    })
    local menu = Menu:new{ item_table = items, … }
    Rows.apply(menu)

The drawing is ZenOS's (common/ui/icon_menu_item.lua: rows with
`_zen_settings_row`); without ZenOS the rows stay KOReader's plain ones.
A row without an icon gets one from what its text says
(common/gz_settings_icons.lua).
]]

local Rows = {}

-- GZreader's own icons (icons/panel/…), for `gz_icon = Rows.FILE.music`
local here = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$") or "plugins/gzreader.koplugin"
Rows.FILE = {
    music = here .. "/icons/panel/music.svg",
    readaloud = here .. "/icons/panel/readaloud.svg",
    usb = here .. "/icons/panel/usb.svg",
    sync = here .. "/icons/panel/sync.svg",
}

--- `item` with icon `icon`: a key of ZenOS's common/inline_icon_map.lua
--- ("download"), "name:<one of ZenOS's icons>" ("name:usb") or a file
--- path. An icon the row already has is kept.
function Rows.icon(item, icon)
    if type(item) ~= "table" or type(icon) ~= "string" then return item end
    if item.icon_glyph or item.icon_name or item.icon_file then return item end
    local name = icon:match("^name:(.+)$")
    if name then
        item.icon_name = name
    elseif icon:find("/", 1, true) then
        item.icon_file = icon
    else
        local ok, map = pcall(require, "common/inline_icon_map")
        item.icon_glyph = ok and type(map) == "table" and map[icon] or nil
    end
    return item
end

--- Whether a row opens or does something (it gets the arrow). `gz_pick`:
--- the Menu's onMenuSelect does it (a list to pick from), unless greyed out.
function Rows.tappable(item)
    if type(item) ~= "table" or item.select_enabled == false or item.enabled == false then return false end
    if item.checked_func or item.radio then return false end -- (a switch or a choice: its mark instead)
    if item.gz_pick then return not item.dim end
    return item.callback ~= nil or item.sub_item_table ~= nil or item.sub_item_table_func ~= nil
end

local function caret()
    local ok, BD = pcall(require, "ui/bidi")
    return ok and type(BD) == "table" and BD.mirroredUILayout and BD.mirroredUILayout() and "chevron.left" or "chevron.right"
end

local function patch()
    if Rows.patched then return end
    Rows.patched = true
    -- (ZenOS installs it when its Settings load; once is enough)
    pcall(function() require("common/ui/icon_menu_item").installMenuPatch() end)
end

--- Mark the rows of `items` (a list) as ZenOS rows; returns `items`.
--- Per row: `gz_icon` (see Rows.icon), `gz_no_arrow`. opts.arrows = false:
--- no arrows at all (a list to pick one from).
function Rows.mark(items, opts)
    if type(items) ~= "table" then return items end
    patch()
    local arrows = not (opts and opts.arrows == false)
    local c = caret()
    for _i, it in ipairs(items) do
        if type(it) == "table" then
            if it.gz_icon then Rows.icon(it, it.gz_icon) end
            it._zen_settings_row = true
            if it.bold then it._zen_primary_bold = true end
            local arrow = arrows and not it.gz_no_arrow and Rows.tappable(it)
            it._zen_has_submenu = arrow or nil
            it._zen_caret_icon = arrow and c or nil
        end
    end
    items.gz_rows = true
    return items
end

--- Whether `items` was made with Rows.mark.
function Rows.isRows(items)
    return type(items) == "table" and items.gz_rows == true
end

--- A row for a longer explanation: tapped, it shows `body`. (A list's
--- explanation as a row of its own was cut off at the screen's edge.)
function Rows.about(label, body)
    return {
        text = label, gz_icon = "details", gz_about = body, keep_menu_open = true,
        callback = function()
            local UIManager = require("ui/uimanager")
            UIManager:show(require("ui/widget/infomessage"):new{ text = body })
        end,
    }
end

--- ZenOS's row height and font for a Menu's lists made with Rows.mark
--- (as ZenOS's Settings page does); its other lists keep the Menu's own.
--- Call after Menu:new (it draws the first list again).
function Rows.fit(m)
    if not (Rows.isRows(m.item_table) and m.available_height and m.item_dimen) then return end
    local ok, IconItem = pcall(require, "common/ui/icon_menu_item")
    if not (ok and type(IconItem) == "table" and IconItem.getSettingsRowHeight) then return end
    local h = IconItem.getSettingsRowHeight()
    m.perpage = math.max(1, math.floor(m.available_height / h))
    m.font_size = IconItem.getSettingsFontSize()
    m.item_dimen.h = h
    if m.getPageNumber then
        m.page_num = m:getPageNumber(#m.item_table)
        if m.page and m.page > m.page_num then m.page = m.page_num end
    end
end

function Rows.apply(menu)
    if type(menu) ~= "table" or menu._gz_rows then return menu end
    menu._gz_rows = true
    local orig = menu._recalculateDimen
    if type(orig) ~= "function" then return menu end
    menu._recalculateDimen = function(m, ...)
        local r = orig(m, ...)
        Rows.fit(m)
        return r
    end
    if Rows.isRows(menu.item_table) and menu.updateItems then menu:updateItems() end
    return menu
end

return Rows
