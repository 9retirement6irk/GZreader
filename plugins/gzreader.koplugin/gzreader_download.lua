--[[--
Background book download with a progress bar.

The transfer runs in a forked subprocess (KOReader's ffiutil.runInSubProcess)
so the UI never freezes: the parent polls the growing ".part" file once a
second to drive the progress bar, and can kill the child at any time.

* Press any key (or tap) on the progress dialog for: Stop download,
  Continue in background, Keep watching.
* A transfer that makes no progress for STALL_SECONDS is stopped.
* The login token is refreshed in the parent before forking: refresh tokens
  rotate, and a rotation done inside the child would be lost when it exits.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local Awake = require("gzreader_awake")
local ProgressbarDialog = require("gzreader_progress")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = ffiutil.template

local STALL_SECONDS = 90 -- overridable via Download.STALL_SECONDS (tests)
local POLL_SECONDS = 1

local Download = {
    active = nil, -- one transfer at a time (the Kindle 3's Wi-Fi and CPU are slow)
    queue = {},   -- waiting: { plugin, book, dest_path, on_done }
    background = false, -- the user sent the downloads to the background
}

local function queuedIds()
    local ids = {}
    if Download.active and Download.active.book_id then ids[Download.active.book_id] = true end
    for _i, q in ipairs(Download.queue) do ids[tostring(q.book.id)] = true end
    return ids
end

--- Is this Grimmory book downloading or waiting to?
function Download.isQueued(book_id) return queuedIds()[tostring(book_id)] == true end

local function startNext()
    if Download.active then return end
    pcall(function() require("gzreader_tasks").changed() end)
    local q = table.remove(Download.queue, 1)
    if not q then
        Download.background = false
        require("gzreader_net").release("download")
        return
    end
    Download.start(q.plugin, q.book, q.dest_path, q.on_done, true)
end

local function mb(bytes)
    return string.format("%.1f MB", (bytes or 0) / (1024 * 1024))
end

--- Start downloading `book` to `dest_path`.
--- on_done(ok, err, opened_by_user) is called on the UI thread when finished.
function Download.start(plugin, book, dest_path, on_done, from_queue, token_ready)
    if not token_ready and Download.isQueued(book.id) and not from_queue then
        UIManager:show(InfoMessage:new{ text = _("This book is already downloading or in the download queue."), timeout = 3 })
        return
    end
    pcall(require("gzreader_recovery").bookStarted, plugin, book, dest_path) -- picked up after a restart
    if Download.active and not token_ready then
        table.insert(Download.queue, { plugin = plugin, book = book, dest_path = dest_path, on_done = on_done })
        Log.info("download queued", "book=" .. tostring(book.id), "#" .. #Download.queue)
        pcall(function() require("gzreader_tasks").changed() end)
        UIManager:show(InfoMessage:new{
            text = T(_("Added to the download queue (%1 waiting). It starts when the current download finishes."), #Download.queue),
            timeout = 3 })
        return "queued"
    end
    local api = plugin.api
    if not token_ready then
        -- refresh the login in the background if it's due (never on the screen's thread)
        Download.active = { book_id = tostring(book.id), title = book.title, refreshing = true }
        return require("gzreader_async").ensureToken(api, function(ok, err)
            Download.active = nil
            if not ok then
                on_done(false, err, false, { queued = from_queue })
                UIManager:nextTick(startNext)
                return
            end
            Download.start(plugin, book, dest_path, on_done, from_queue, true)
        end)
    end

    local title = type(book.title) == "string" and book.title or dest_path:match("[^/]+$")
    local part = dest_path .. ".part"
    -- a part left by an interrupted download is continued (Range request)
    local resume_from = lfs.attributes(part, "size") or 0
    local expected = tonumber(book.fileSizeKb) and tonumber(book.fileSizeKb) * 1024 or nil
    if expected and expected <= 0 then expected = nil end

    Log.info("download start", "book=" .. tostring(book.id), "expected=" .. tostring(expected), "->", dest_path,
        resume_from > 0 and ("continuing after " .. mb(resume_from)) or "")

    local pid, read_fd = ffiutil.runInSubProcess(function(_child_pid, write_fd)
        -- Child: never refresh or persist tokens here (see header).
        api.no_refresh = true
        local dl_ok, dl_err = api:downloadToFile(book.id, part, true)
        local sub = ""
        if dl_ok then
            -- the subtitle ("Diary of a Wimpy Kid: Old School") isn't in the app API's lists
            local okb, full = pcall(api.getBook, api, book.id)
            local m = okb and type(full) == "table" and full.metadata
            if type(m) == "table" and type(m.subtitle) == "string" then sub = m.subtitle:gsub("[\r\n]", " ") end
        end
        ffiutil.writeToFD(write_fd, dl_ok and ("ok\n" .. sub) or ("err " .. tostring(dl_err)), true)
    end, true)
    if not pid then
        Log.err("download: could not start subprocess:", read_fd)
        on_done(false, tostring(read_fd), false, { queued = from_queue })
        UIManager:nextTick(startNext)
        return
    end

    local job = {
        pid = pid, read_fd = read_fd, started = os.time(), book_id = tostring(book.id),
        title = title, expected = expected,
        last_size = resume_from, last_change = os.time(),
        watching = not from_queue and not Download.background,
        show_dialog = not Download.background,
    }
    Download.active = job
    pcall(function() require("gzreader_tasks").changed() end)
    Awake.hold(job) -- no sleeping (screensaver or autosuspend) mid-download
    require("gzreader_net").hold("download") -- keep Wi-Fi up until the queue is done

    local dialog
    local function closeDialog()
        if dialog then
            dialog.dismiss_callback = nil
            UIManager:close(dialog)
            dialog = nil
        end
    end

    local function reap()
        -- collect the (killed) child and close our end of the pipe
        if ffiutil.isSubProcessDone(job.pid) then
            if job.read_fd then ffiutil.readAllFromFD(job.read_fd); job.read_fd = nil end
        else
            UIManager:scheduleIn(0.5, reap)
        end
    end

    local function finish(result_ok, result_err, subtitle)
        if job.finished then return end
        job.finished = true
        Download.active = nil
        Awake.release(job)
        UIManager:unschedule(job.poll)
        closeDialog()
        local secs = os.time() - job.started
        if result_ok or result_err == "cancelled" or tostring(result_err):match("^http_4") then
            pcall(require("gzreader_recovery").bookDone, plugin, book.id) -- else: offered after a restart
        end
        if result_ok then
            os.remove(dest_path)
            local renamed, rerr = os.rename(part, dest_path)
            if not renamed then
                Log.err("download rename failed:", rerr)
                return on_done(false, rerr)
            end
            Log.info("download done", "book=" .. tostring(book.id), mb(lfs.attributes(dest_path, "size")), secs .. "s")
        else
            if result_err == "cancelled" or tostring(result_err):match("^http_4") then os.remove(part) end
            Log.warn("download failed", "book=" .. tostring(book.id), tostring(result_err), "after " .. secs .. "s",
                "received " .. mb(job.last_size))
        end
        if job.watching and #Download.queue > 0 then
            Download.background = true -- the book opens now; the rest download quietly
        end
        on_done(result_ok, result_err, job.watching, { subtitle = subtitle ~= "" and subtitle or nil,
            queued = from_queue, left = #Download.queue })
        UIManager:nextTick(startNext)
    end

    local function stop(reason)
        Log.info("download stopped:", reason)
        ffiutil.terminateSubProcess(job.pid)
        reap()
        finish(false, reason)
    end
    job.stop = stop

    local function showOptions()
        local options
        options = ButtonDialog:new{
            title = T(_("Downloading “%1”"), title),
            buttons = {
                {{ text = _("Stop download"), callback = function()
                    UIManager:close(options)
                    stop("cancelled")
                end }},
                {{ text = _("Continue in background"), callback = function()
                    UIManager:close(options)
                    job.watching = false
                    Download.background = true -- queued downloads follow without a dialog
                    closeDialog()
                    UIManager:show(InfoMessage:new{ text = _("Downloading in the background. You'll be told when it's ready."), timeout = 3 })
                end }},
                {{ text = _("Keep watching"), callback = function() UIManager:close(options) end }},
                #Download.queue > 0 and {{ text = T(_("Empty the queue (%1 waiting)"), #Download.queue), callback = function()
                    UIManager:close(options)
                    Log.info("download queue emptied:", #Download.queue)
                    for _i, q in ipairs(Download.queue) do pcall(require("gzreader_recovery").bookDone, q.plugin, q.book.id) end
                    Download.queue = {}
                end }} or nil,
            },
        }
        UIManager:show(options)
    end

    --- (Re)open the progress dialog (also from the Downloads screen).
    local function openDialog()
        if dialog or job.finished then return end
        local waiting = #Download.queue
        dialog = ProgressbarDialog:new{
            title = T(_("Downloading “%1”"), title) .. (waiting > 0 and T(_(" (+%1 queued)"), waiting) or ""),
            subtitle = _("Press any key for options. The Kindle stays awake until it's done."),
            progress_max = expected,
            refresh_time_seconds = 2,
        }
        -- any key / tap opens our options instead of closing the dialog
        dialog.onDismiss = function() showOptions() return true end
        dialog.onAnyKeyPressed = dialog.onDismiss
        dialog.onTapClose = dialog.onDismiss
        dialog:show()
        dialog:reportProgress(expected and math.min(job.last_size, expected) or job.last_size)
    end
    job.open_dialog = openDialog
    if job.show_dialog then openDialog() end

    job.poll = function()
        if job.finished then return end
        local size = lfs.attributes(part, "size") or 0
        if size ~= job.last_size then
            job.last_size, job.last_change = size, os.time()
        end
        if dialog then
            dialog:reportProgress(expected and math.min(size, expected) or size)
        end
        if ffiutil.isSubProcessDone(job.pid) then
            local out = job.read_fd and ffiutil.readAllFromFD(job.read_fd) or ""
            job.read_fd = nil
            local okd, sub = out:match("^(ok)\n?(.*)$")
            if okd then
                finish(true, nil, sub)
            else
                finish(false, out:match("^err (.*)$") or "download process ended unexpectedly")
            end
            return
        end
        if os.time() - job.last_change >= (Download.STALL_SECONDS or STALL_SECONDS) then
            stop(T("stalled: no data for %1 s", Download.STALL_SECONDS or STALL_SECONDS))
            return
        end
        UIManager:scheduleIn(POLL_SECONDS, job.poll)
    end
    UIManager:scheduleIn(POLL_SECONDS, job.poll)
end

--- Take a waiting book out of the queue.
function Download.unqueue(book_id)
    for i, q in ipairs(Download.queue) do
        if tostring(q.book.id) == tostring(book_id) then
            table.remove(Download.queue, i)
            pcall(require("gzreader_recovery").bookDone, q.plugin, book_id)
            Log.info("download unqueued", "book=" .. tostring(book_id))
            pcall(function() require("gzreader_tasks").changed() end)
            return true
        end
    end
end

--- Stop any running download and empty the queue (e.g. on exit).
function Download.cancelActive(reason)
    Download.queue = {}
    if Download.active and Download.active.stop then
        Download.active.stop(reason or "cancelled")
    end
end

return Download
