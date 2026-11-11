-- GZreader: Settings → Reader in fewer rows. ZenOS's Reader section had nine
-- entries side by side; related ones go into a submenu each:
--   Notes and footnotes    Annotation viewer, Footnotes and pinned pages
--   Gestures and controls  Bottom swipe gesture, Reader controls, Page Browser
-- A group takes the place of its first entry found; entries that aren't in
-- a group (Appearance, Highlight / Lookup, End of book, Restore library
-- location on exit, GZreader's own) stay where they are. A group with none of
-- its entries isn't made. Deep links into these entries
-- (zen_settings_page.show paths) go through the group: M.path().

local _ = require("gettext")
local icons = require("common/inline_icon_map")
local IconItem = require("common/ui/icon_menu_item")

local M = {}

M.GROUPS = {
    { text = "Notes and footnotes", icon = "edit",
      members = { "Annotation viewer", "Footnotes and pinned pages" } },
    { text = "Gestures and controls", icon = "bottom_swipe",
      members = { "Bottom swipe gesture", "Reader controls", "Page Browser" } },
}

--- `items` (the Reader section's rows) with each group's entries in their group.
function M.group(items)
    if type(items) ~= "table" then return items end
    local group_of, member_rank = {}, {}
    for gi, g in ipairs(M.GROUPS) do
        for mi, name in ipairs(g.members) do
            group_of[_(name)] = gi
            member_rank[_(name)] = mi
        end
    end
    local out, made = {}, {}
    for _i, item in ipairs(items) do
        local gi = type(item) == "table" and group_of[item.text]
        if gi then
            local group = made[gi]
            if not group then
                local g = M.GROUPS[gi]
                group = IconItem.decorate({ text = _(g.text), sub_item_table = {} }, icons[g.icon])
                made[gi] = group
                out[#out + 1] = group
            end
            item.separator = nil -- (a line inside a short submenu only splits it)
            table.insert(group.sub_item_table, item)
        else
            out[#out + 1] = item
        end
    end
    -- the members in the order GROUPS gives them
    for _gi, group in pairs(made) do
        table.sort(group.sub_item_table, function(a, b) return member_rank[a.text] < member_rank[b.text] end)
    end
    for key, value in pairs(items) do
        if type(key) ~= "number" then out[key] = value end
    end
    return out
end

--- A Settings path to one of Reader's entries (for zen_settings_page.show):
--- Reader → its group (if it has one) → the entry → `rest`…
function M.path(entry, ...)
    local path = { { key = "text", value = _("Reader") } }
    for _gi, g in ipairs(M.GROUPS) do
        for _mi, name in ipairs(g.members) do
            if _(name) == entry then path[#path + 1] = { key = "text", value = _(g.text) } end
        end
    end
    path[#path + 1] = { key = "text", value = entry }
    for _i, more in ipairs({ ... }) do path[#path + 1] = { key = "text", value = more } end
    return path
end

return M
