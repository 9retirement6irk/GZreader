--[[--
Downloads screen and download status in the Home title bar.

Everything GZreader is fetching or preparing in one place: the book being
downloaded and the ones waiting in the queue, audiobook downloads and the
audiobook "preparing" step. From the GZreader menu (Menu key on Home),
the Home or Reading menu → Downloads (while something downloads): reopen a progress
bar, stop the current download, take a book out of the queue, empty the
queue.

The status bar (ZenOS's title bar on Home and in the library) shows a
download icon with the current percentage and how many are waiting,
updated every 10 seconds while something downloads, and nothing otherwise.
]]

local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local _ = require("gettext")
local T = require("ffi/util").template

local Tasks = { REFRESH = 10 }

local ICON = "\xEF\x80\x99" -- Nerd Fonts / Font Awesome "download"

local function Download() return package.loaded["gzreader_download"] end
local function Audiobook() return package.loaded["gzreader_audiobook"] end

local function pct(done, total)
    if total and total > 0 then return math.floor(math.min(done or 0, total) * 100 / total) end
end

--- Current work: { kind, title, done, total, open, stop, book_id }.
function Tasks.list()
    local out = {}
    local D = Download()
    if D and D.active then
        local j = D.active
        out[#out + 1] = { kind = "book", title = j.title, done = j.last_size or 0, total = j.expected,
            open = j.open_dialog, stop = j.stop and function() j.stop("cancelled") end, book_id = j.book_id }
    end
    local A = Audiobook()
    if A and A.active_download then
        local s = A.active_download
        out[#out + 1] = { kind = "audiobook", title = s.title, done = s.done, total = s.total, open = s.open_dialog }
    end
    if A and A.active_prepare then
        local s = A.active_prepare
        out[#out + 1] = { kind = "prepare", title = s.title, done = s.done, total = s.total, open = s.open_dialog }
    end
    if D then
        for _i, q in ipairs(D.queue) do
            out[#out + 1] = { kind = "queued", title = q.book.title, book_id = q.book.id }
        end
    end
    return out
end

function Tasks.count() return #Tasks.list() end

--- Status bar item: icon, label.
function Tasks.status()
    local list = Tasks.list()
    if #list == 0 then return nil end
    local first, waiting = nil, 0
    for _i, t in ipairs(list) do
        if t.kind == "queued" then waiting = waiting + 1 elseif not first then first = t end
    end
    local label = ""
    if first then
        local p = pct(first.done, first.total)
        label = p and (p .. "%") or (first.kind == "prepare" and _("preparing") or _("downloading"))
    end
    if waiting > 0 then label = label .. (label ~= "" and " " or "") .. "+" .. waiting end
    return ICON, " " .. label
end

local ticking
local function tick()
    ticking = nil
    UIManager:broadcastEvent(Event:new("GzDownloadsChanged"))
    if Tasks.count() > 0 then
        ticking = tick
        UIManager:scheduleIn(Tasks.REFRESH, tick)
    end
end

--- Something started, finished or changed: refresh the status bar now and
--- keep refreshing while anything is going on.
function Tasks.changed()
    if ticking then UIManager:unschedule(ticking); ticking = nil end
    UIManager:nextTick(tick)
end

function Tasks.installStatusBar()
    local register = rawget(_G, "__ZEN_UI_REGISTER_STATUS_ITEM")
    if type(register) == "function" then
        register("gz_downloads", Tasks.status, { label = _("GZreader downloads"), side = "left" })
    end
end

local function line(t)
    local Progress = require("gzreader_progress")
    local name = t.title or "?"
    if t.kind == "queued" then return T(_("Waiting: %1"), name) end
    local what = t.kind == "prepare" and _("Preparing") or _("Downloading")
    return T("%1: %2", what, name), Progress.status(t.done or 0, t.total)
end

--- The Downloads screen.
function Tasks.show()
    local Menu = require("ui/widget/menu")
    local ButtonDialog = require("ui/widget/buttondialog")
    local InfoMessage = require("ui/widget/infomessage")
    local menu
    local function items()
        local list, out = Tasks.list(), {}
        for _i, t in ipairs(list) do
            local text, status = line(t)
            out[#out + 1] = {
                text = text, mandatory = status,
                callback = function()
                    local buttons = {}
                    if t.open then
                        buttons[#buttons + 1] = {{ text = _("Show progress"), callback = function()
                            UIManager:close(menu._gz_options); UIManager:close(menu); t.open()
                        end }}
                    end
                    if t.stop then
                        buttons[#buttons + 1] = {{ text = _("Stop this download"), callback = function()
                            UIManager:close(menu._gz_options); t.stop(); menu:switchItemTable(nil, items())
                        end }}
                    end
                    if t.kind == "queued" then
                        buttons[#buttons + 1] = {{ text = _("Take it out of the queue"), callback = function()
                            UIManager:close(menu._gz_options); Download().unqueue(t.book_id); menu:switchItemTable(nil, items())
                        end }}
                    end
                    buttons[#buttons + 1] = {{ text = _("Close"), callback = function() UIManager:close(menu._gz_options) end }}
                    menu._gz_options = ButtonDialog:new{ title = t.title or "", buttons = buttons }
                    UIManager:show(menu._gz_options)
                end,
            }
        end
        local D = Download()
        if D and #D.queue > 1 then
            out[#out + 1] = { text = T(_("Empty the queue (%1 waiting)"), #D.queue), callback = function()
                D.queue = {}
                Tasks.changed()
                menu:switchItemTable(nil, items())
            end }
        end
        if #out == 0 then out[1] = { text = _("Nothing is downloading."), select_enabled = false } end
        return out
    end
    menu = Menu:new{
        title = _("Downloads"), item_table = items(),
        is_borderless = true, is_popout = false, covers_fullscreen = true, title_bar_fm_style = true,
    }
    -- keep the percentages current while it's open
    local function refresh()
        if not menu._gz_open then return end
        menu:switchItemTable(nil, items())
        UIManager:scheduleIn(5, refresh)
    end
    menu._gz_open = true
    local orig = menu.onCloseWidget
    menu.onCloseWidget = function(m, ...)
        m._gz_open = false
        UIManager:unschedule(refresh)
        if orig then return orig(m, ...) end
    end
    UIManager:show(menu, "full")
    UIManager:scheduleIn(5, refresh)
    if Tasks.count() == 0 then
        UIManager:show(InfoMessage:new{ text = _("Nothing is downloading."), timeout = 2 })
    end
end

--- Menu entry (shown only while something is going on).
function Tasks.menuItem()
    return {
        text_func = function()
            local n = Tasks.count()
            return n > 0 and T(_("Downloads (%1)"), n) or _("Downloads")
        end,
        callback = function(touchmenu)
            if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
            Tasks.show()
        end,
    }
end

return Tasks
