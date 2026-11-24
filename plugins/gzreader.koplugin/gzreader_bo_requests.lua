--[[--
Book requests (BookOrbit): ask the server for a book or audiobook it doesn't
have, and see what became of what you asked for.

BookOrbit keeps requests on its main API (POST / GET /api/v1/book-requests,
POST :id/cancel), so they need its API key, with the "Request books"
permission. The rows are in the Catalog's BookOrbit card (gzreader_browser.lua).
Nothing is kept on the Kindle: the list is BookOrbit's each time.
]]

local _ = require("gettext")
local T = require("ffi/util").template

local Requests = {}

--- BookOrbit's request states, as shown.
local STATUS = {
    pending = _("Waiting for approval"),
    approved = _("Approved"),
    rejected = _("Declined"),
    cancelled = _("Cancelled"),
    searching = _("Searching"),
    grabbed = _("Downloading"),
    downloading = _("Downloading"),
    importing = _("Being added to the library"),
    needs_review = _("Needs a look in BookOrbit"),
    available = _("In the library"),
    failed = _("Failed"),
}
-- (states a request can still be cancelled in)
local OPEN = { pending = true, approved = true, searching = true, grabbed = true, downloading = true, needs_review = true, failed = true }

function Requests.statusText(status)
    return STATUS[status] or (type(status) == "string" and status ~= "" and status or _("Unknown"))
end

function Requests.cancellable(status) return OPEN[status] == true end

--- Can this Kindle ask for books (BookOrbit, signed in, API key saved)?
function Requests.can(plugin)
    local api = type(plugin) == "table" and plugin.api
    return type(api) == "table" and type(api.canRequestBooks) == "function" and api:isPaired() and api:canRequestBooks() == true
end

local function show(text, timeout)
    local UIManager = require("ui/uimanager")
    UIManager:show(require("ui/widget/infomessage"):new{ text = text, timeout = timeout })
end

local function needKey()
    show(_("Requesting books needs BookOrbit's API key, with “Request books” ticked: Settings → Accounts and services → Books → Connected to BookOrbit as … → BookOrbit API key."))
end

--- A row's right-hand text and the line under a request's title.
function Requests.line(r)
    local who = type(r.authors) == "table" and table.concat(r.authors, ", ") or ""
    local kind = r.kind == "audiobook" and _("audiobook") or _("book")
    return who ~= "" and T(_("%1 · %2"), who, kind) or kind
end

--- What a tap on a request shows.
function Requests.detail(r)
    local lines = { r.title or "?", Requests.line(r), "", T(_("Status: %1"), Requests.statusText(r.status)) }
    if r.reason and r.reason ~= "" then lines[#lines + 1] = r.reason end
    if r.note and r.note ~= "" then lines[#lines + 1] = T(_("Note from BookOrbit: %1"), r.note) end
    if r.status == "available" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = r.kind == "audiobook" and _("It's in the Catalog's Audiobooks page now.") or _("It's in the Catalog now.")
    end
    return table.concat(lines, "\n")
end

--- Send a request. `kind`: "ebook" or "audiobook". on_done(ok) afterwards.
function Requests.send(plugin, title, author, kind, on_done)
    title = type(title) == "string" and title:gsub("^%s+", ""):gsub("%s+$", "") or ""
    author = type(author) == "string" and author:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if title == "" then
        show(_("Enter the book's title."), 3)
        return on_done and on_done(false)
    end
    require("gzreader_net").run(function()
        local res, err = plugin.api:requestBook(title, author ~= "" and { author } or nil, kind)
        if not res then
            show(plugin:describeError(err))
            return on_done and on_done(false)
        end
        local what = kind == "audiobook" and _("audiobook") or _("book")
        if res.status == "available" then
            show(T(_("BookOrbit already has “%1”. Look for it in the Catalog."), res.title or title))
        elseif res.joined then
            show(T(_("Someone already asked for “%1” (%2): you'll be counted in. Status: %3."), res.title or title, what, Requests.statusText(res.status)))
        else
            show(T(_("Asked BookOrbit for “%1” (%2). Status: %3."), res.title or title, what, Requests.statusText(res.status)), 5)
        end
        require("gzreader_log").info("book requests: one sent,", kind, "status", tostring(res.status))
        if on_done then on_done(true) end
    end, { reason = "requesting a book" })
end

--- The form: title and author, then Book or Audiobook.
function Requests.ask(plugin, on_done, title)
    if not Requests.can(plugin) then return needKey() end
    local UIManager = require("ui/uimanager")
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local d
    local function go(kind)
        local f = d:getFields()
        UIManager:close(d)
        Requests.send(plugin, f[1], f[2], kind, on_done)
    end
    d = MultiInputDialog:new{
        title = _("Request a book"),
        fields = {
            { description = _("Title"), text = title or "" },
            { description = _("Author (optional)"), text = "" },
        },
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Audiobook"), callback = function() go("audiobook") end },
            { text = _("Book"), is_enter_default = true, callback = function() go("ebook") end },
        } },
    }
    Requests.dialog = d
    UIManager:show(d)
    d:onShowKeyboard()
end

--- The rows of "My requests": a way to ask, then what you asked for, newest first.
function Requests.rows(plugin, list, reopen)
    local UIManager = require("ui/uimanager")
    local items = { { text = _("Request a book…"), gz_action = "request", callback = function() Requests.ask(plugin, reopen) end } }
    for _i, r in ipairs(list) do
        items[#items + 1] = {
            text = r.title or "?", mandatory = Requests.statusText(r.status), gz_request = r.id, keep_menu_open = true,
            callback = function()
                if not Requests.cancellable(r.status) then return show(Requests.detail(r)) end
                UIManager:show(require("ui/widget/confirmbox"):new{
                    text = Requests.detail(r),
                    ok_text = _("Cancel this request"), cancel_text = _("Close"),
                    ok_callback = function()
                        require("gzreader_net").run(function()
                            local ok, err = plugin.api:cancelRequest(r.id)
                            if not ok then return show(plugin:describeError(err)) end
                            show(T(_("The request for “%1” was cancelled."), r.title or "?"), 3)
                            if reopen then reopen() end
                        end, { reason = "cancelling a book request" })
                    end,
                })
            end,
        }
    end
    if #list == 0 then
        items[#items + 1] = { text = _("You haven't asked for anything yet."), select_enabled = false }
    end
    return items
end

--- "My requests" in the Catalog (`browser`: gzreader_browser.lua's). `replace`: over the list that's open.
function Requests.open(browser, replace)
    local plugin = browser.plugin
    if not Requests.can(plugin) then return needKey() end
    require("gzreader_net").run(function()
        local list, err = plugin.api:listRequests()
        if not list then return show(plugin:describeError(err)) end
        local items = Requests.rows(plugin, list, function() Requests.open(browser, true) end)
        if replace then browser:replace(_("Book requests"), items) else browser:push(_("Book requests"), items) end
    end, { reason = "book requests" })
end

return Requests
