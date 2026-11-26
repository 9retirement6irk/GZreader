-- GZreader: Settings kept simple (the owner, 2026-11-26: "make sure that
-- simplicity stays true" to the iOS layout of common/gz_settings_tree.lua).
-- The tree puts ZenOS's and GZreader's rows on their pages; this goes over
-- the finished pages afterwards and keeps each thing in one place.
--
-- It works on rows by their text, as the tree does, so a row another part
-- adds later (a pull request, an upstream ZenOS) is moved too, and a row
-- that isn't there is simply left alone. Pages built when they open
-- (sub_item_table_func) are changed when they're built. Saved values never
-- change: only where a row is and what it's called.
local M = {}

local function gettext() return require("gettext") end

---------------------------------------------------------------- finding rows

--- A row's label: its text, or what its text_func says (nil if neither).
function M.label(item)
    if type(item) ~= "table" then return nil end
    local t = rawget(item, "text")
    if t == nil and type(rawget(item, "text_func")) == "function" then
        local ok, v = pcall(item.text_func)
        t = ok and v or nil
    end
    return type(t) == "string" and t or nil
end

--- Does `item`'s label start with `prefix`?
function M.startsWith(item, prefix)
    local l = M.label(item)
    return l ~= nil and l:sub(1, #prefix) == prefix
end

--- The index and row of `list` that `match` (a label, or a function) picks.
function M.find(list, match)
    if type(list) ~= "table" then return nil end
    for i, item in ipairs(list) do
        if type(item) == "table" then
            local hit
            if type(match) == "function" then hit = match(item) else hit = M.label(item) == match end
            if hit then return item, i end
        end
    end
end

--- Takes the row `match` picks out of `list` and returns it.
function M.take(list, match)
    local item, i = M.find(list, match)
    if i then table.remove(list, i) end
    return item
end

--- The first page's section `key` (its _zen_settings_root) and its rows.
function M.section(root, key)
    for _i, item in ipairs(type(root) == "table" and root or {}) do
        if type(item) == "table" and rawget(item, "_zen_settings_root") == key then
            return item, type(item.sub_item_table) == "table" and item.sub_item_table or nil
        end
    end
end

-- (a page's list can carry functions that build it again: changed again too)
local REFRESH = { "_zen_refresh", "refresh_func" }
local function withRefresh(list, post)
    if type(list) ~= "table" then return list end
    post(list)
    for _i, key in ipairs(REFRESH) do
        local f = rawget(list, key)
        if type(f) == "function" and not rawget(list, "_gz_tidy_" .. key) then
            list[key] = function(...) return withRefresh(f(...), post) end
            list["_gz_tidy_" .. key] = true
        end
    end
    return list
end

--- Runs `post(rows)` on `item`'s page: now when its rows are there, else each
--- time its page is built.
function M.onPage(item, post)
    if type(item) ~= "table" then return end
    if type(item.sub_item_table) == "table" then
        withRefresh(item.sub_item_table, post)
    elseif type(item.sub_item_table_func) == "function" then
        local f = item.sub_item_table_func
        item.sub_item_table_func = function(...)
            local list = f(...)
            if type(list) == "table" then withRefresh(list, post) end
            return list
        end
    end
end

--- A row's own rows, built if it builds them when opened ({} when none).
function M.rowsOf(item, ...)
    if type(item) ~= "table" then return {} end
    if type(item.sub_item_table) == "table" then return item.sub_item_table end
    if type(item.sub_item_table_func) == "function" then
        local ok, list = pcall(item.sub_item_table_func, ...)
        if ok and type(list) == "table" then return list end
    end
    return {}
end

--- Opens Settings at `texts` (the rows' labels, from the first page).
function M.open(texts)
    local ok, zen = pcall(function() return require("gzreader_tabs").zen() end)
    if not (ok and zen) then return nil end
    local path = {}
    for i, text in ipairs(texts) do path[i] = { key = "text", value = text } end
    local okp, page = pcall(function() return require("modules/settings/zen_settings_page").show(zen, { path = path }) end)
    return okp and page or nil
end

---------------------------------------------------------------- one place for each thing

--- Sleep and wallpaper's "Pictures from Immich" was Accounts and services →
--- Photos again: the wallpaper's and Home background's own choices pick
--- Immich pictures, and the connection is Photos.
function M.noImmichCopy(root)
    local _sec, rows = M.section(root, "sleep")
    M.take(rows, gettext()("Pictures from Immich"))
end

--- Notes → Handwriting to text had the whole AI page again (AI key and
--- service): now one row saying which service, that opens Accounts and
--- services → AI, the one place it's set.
function M.aiOnce(root)
    local _ = gettext()
    local _sec, rows = M.section(root, "accounts")
    local notes = M.find(rows, _("Notes"))
    M.onPage(notes, function(list)
        local hw = M.find(list, function(it) return M.startsWith(it, _("Handwriting to text")) end)
        M.onPage(hw, function(sub)
            local copy, at = M.find(sub, function(it) return M.startsWith(it, _("AI key and service")) end)
            if not at then return end
            sub[at] = M.aiLink(copy)
        end)
    end)
end

--- The row standing in for the AI page: the service in use, and a tap opens
--- Accounts and services → AI.
function M.aiLink(copy)
    local _ = gettext()
    return {
        text_func = function()
            local name = (M.label(copy) or ""):match(":%s*(.-)%s*$")
            return require("ffi/util").template(_("AI service: %1"), name or "")
        end,
        help_text = _("Set in Settings → Accounts and services → AI: one key for everything that uses an AI service. Tap to go there."),
        separator = copy.separator,
        keep_menu_open = true,
        callback = function() M.open({ _("Accounts and services"), _("AI") }) end,
    }
end

---------------------------------------------------------------- fewer taps

--- Sleep and wallpaper → Sleep was a page of its own for most of the section:
--- its rows (wallpaper, its options, the sleep message, automatic suspend…)
--- now are Sleep and wallpaper's own, the Home background after them. On a
--- device without a sleep screen, only the Home background.
function M.flatSleep(root)
    local _ = gettext()
    local sec, rows = M.section(root, "sleep")
    local sleep, at = M.find(rows, _("Sleep"))
    if not at then return end
    table.remove(rows, at)
    local rest = rows
    sec.sub_item_table = nil
    sec.sub_item_table_func = function(...)
        local list = {}
        local on = type(sleep.enabled_func) ~= "function" or sleep.enabled_func()
        if on and sleep.enabled ~= false then
            for _i, it in ipairs(M.rowsOf(sleep, ...)) do list[#list + 1] = it end
        end
        if list[#list] then list[#list].separator = true end
        for _i, it in ipairs(rest) do list[#list + 1] = it end
        if list[#list] then list[#list].separator = nil end
        return list
    end
end

--- Display and light's Font and "Size of menus and text" are one row, Menu
--- text: the size of everything first, then the font and its own size.
function M.menuText(root)
    local _ = gettext()
    local _sec, rows = M.section(root, "display")
    local font = M.find(rows, _("Font"))
    local size = M.take(rows, function(it) return M.startsWith(it, _("Size of menus and text")) end)
    if not (font and size) then
        -- (one of them alone: put back as it was)
        if size and rows then rows[#rows + 1] = size end
        return
    end
    local font_rows = font.sub_item_table
    local font_func = font.sub_item_table_func
    font.text, font.text_func = _("Menu text"), nil
    font.help_text = _("The type of menus, lists and GZreader's own pages: how big everything is (the screen is laid out again for it), then the font and its size.")
    font.sub_item_table, font.sub_item_table_func = nil, function(...)
        local list = { size }
        size.separator = true
        local inner = type(font_rows) == "table" and font_rows or (type(font_func) == "function" and font_func(...)) or {}
        for _i, it in ipairs(inner) do list[#list + 1] = it end
        return list
    end
end

---------------------------------------------------------------- rows where they belong

--- Is this a Kindle with a pen (the Scribe)?
function M.penDevice()
    local ok, pen = pcall(function() return require("gzreader_sketch").penDevice(require("device")) end)
    return ok and pen == true
end

-- the rows of Notes that are the pen's (a Kindle with a pen: General → Pen)
local function penRow(it)
    local _ = gettext()
    return M.startsWith(it, _("Pen's shortcut button")) or M.startsWith(it, _("Handwriting to text"))
end
local function eraserRow(it) return M.startsWith(it, gettext()("Pen's eraser removes highlights")) end

--- On a Kindle with a pen, General has a Pen row (as an iPad has Apple
--- Pencil): the pen's shortcut button and Handwriting to text (with the
--- keyboard's ✍ key in it), out of Notes. Notes' "Pen's eraser removes
--- highlights" acts in books: it goes to Reader → Highlight / Lookup.
function M.penPage(root, opts)
    local _ = gettext()
    local _acc, accounts = M.section(root, "accounts")
    local notes = M.find(accounts, _("Notes"))
    if not notes then return end
    local pen = (opts and opts.pen) ~= nil and opts.pen or M.penDevice()
    -- (Notes as it was, to take the rows from)
    local notes_rows = notes.sub_item_table_func
    local function fromNotes(match, ...)
        local list = type(notes_rows) == "function" and notes_rows(...) or notes.sub_item_table or {}
        local out = {}
        for _i, it in ipairs(type(list) == "table" and list or {}) do
            if type(it) == "table" and match(it) then out[#out + 1] = it end
        end
        return out
    end
    M.onPage(notes, function(list)
        for i = #list, 1, -1 do
            if (pen and penRow(list[i])) or eraserRow(list[i]) then table.remove(list, i) end
        end
        if list[#list] then list[#list].separator = nil end
    end)
    if pen then
        local _gen, general = M.section(root, "general")
        if general then
            local _t, at = M.find(general, _("Transfer"))
            local row = M.icon({
                text = _("Pen"),
                help_text = _("The pen: what its shortcut button does while drawing, and how handwriting becomes typed text (also the keyboard's ✍ key)."),
                sub_item_table_func = function(...)
                    local list = fromNotes(penRow, ...)
                    if list[#list] then list[#list].separator = nil end
                    return list
                end,
            }, "edit")
            table.insert(general, at or (#general + 1), row)
        end
    end
    local _r, reader = M.section(root, "reader")
    local hl = M.find(reader, function(it) return M.startsWith(it, _("Highlight")) end)
    M.onPage(hl, function(list)
        if M.find(list, eraserRow) then return end
        local got = fromNotes(eraserRow)
        if got[1] and list[#list] then list[#list].separator = true end
        for _i, it in ipairs(got) do list[#list + 1] = it end
    end)
end

--- A row with ZenOS's icon `glyph` (as the tree gives its rows).
function M.icon(item, glyph)
    local okI, IconItem = pcall(require, "common/ui/icon_menu_item")
    local okc, icons = pcall(require, "common/inline_icon_map")
    if okI and okc and type(icons) == "table" and icons[glyph] then return IconItem.decorate(item, icons[glyph]) end
    return item
end

--- General → Transfer is "Transfer or reset", with Reset GZreader last (as
--- an iPhone's General → Transfer or Reset). Privacy and diagnostics →
--- Advanced keeps what's seldom needed: Performance (from General), the
--- Notifications switches (from Display and light → Screen), KOReader
--- settings.
function M.transferOrReset(root)
    local _ = gettext()
    local _g, general = M.section(root, "general")
    local _p, privacy = M.section(root, "privacy")
    local advanced = M.find(privacy, _("Advanced"))
    local adv = advanced and type(advanced.sub_item_table) == "table" and advanced.sub_item_table or nil
    local transfer = M.find(general, _("Transfer"))
    local reset = adv and M.take(adv, _("Reset GZreader"))
    if transfer and reset and type(transfer.sub_item_table) == "table" then
        transfer.text = _("Transfer or reset")
        transfer.help_text = _("Copy your connections to or from another GZreader, sync through a computer instead of Wi-Fi, or reset GZreader.")
        local list = transfer.sub_item_table
        if list[#list] then list[#list].separator = true end
        list[#list + 1] = reset
    elseif reset and adv then
        adv[#adv + 1] = reset -- (no Transfer to put it in: where it was)
    end
    if not adv then return end
    if adv[#adv] then adv[#adv].separator = nil end
    local first = {}
    local perf = M.take(general, _("Performance"))
    if perf then first[#first + 1] = perf end
    -- the Notifications switches, out of Screen (built when it opens)
    local _d, display = M.section(root, "display")
    local screen = M.find(display, _("Screen"))
    local screen_func = screen and screen.sub_item_table_func
    if type(screen_func) == "function" then
        M.onPage(screen, function(list) M.take(list, _("Notifications")) end)
        first[#first + 1] = M.icon({
            text = _("Notifications"),
            help_text = _("Which of KOReader's short messages show (from the bottom menu, gestures and the rest), and the ones shown before."),
            sub_item_table_func = function(...)
                local ok, list = pcall(screen_func, ...)
                local n = ok and M.find(list, _("Notifications"))
                return M.rowsOf(n, ...)
            end,
        }, "settings_advanced")
    end
    if #first > 0 then first[#first].separator = true end
    for i = #first, 1, -1 do table.insert(adv, 1, first[i]) end
end

--- The daily paper has no account and is read on Home: Home and tabs → Daily
--- paper (after Home), not Accounts and services.
function M.dailyPaperHome(root)
    local _ = gettext()
    local _a, accounts = M.section(root, "accounts")
    local _h, home = M.section(root, "home")
    if not (accounts and home) then return end
    local paper = M.take(accounts, _("Daily paper"))
    if not paper then return end
    local _x, at = M.find(home, _("Home"))
    table.insert(home, (at or 0) + 1, paper)
    if accounts[#accounts] then accounts[#accounts].separator = nil end
end

---------------------------------------------------------------- all of it

--- Settings' first page (gz_settings_tree.build's) made simpler. `opts`:
--- { gzreader = function() → GZreader's plugin or nil, pen = a Kindle with a pen
--- (nil: asked of the device) }.
function M.apply(root, opts)
    opts = opts or {}
    for _i, step in ipairs({ M.noImmichCopy, M.aiOnce, M.flatSleep, M.menuText, M.penPage, M.transferOrReset, M.dailyPaperHome }) do
        local ok, err = pcall(step, root, opts)
        if not ok then
            pcall(function() require("logger").warn("GZreader settings: a tidying step failed:", tostring(err)) end)
        end
    end
    return root
end

return M
