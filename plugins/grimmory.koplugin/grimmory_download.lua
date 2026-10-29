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
local Awake = require("grimmory_awake")
local ProgressbarDialog = require("grimmory_progress")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local Log = require("grimmory_log")
local _ = require("gettext")
local T = ffiutil.template

local STALL_SECONDS = 90 -- overridable via Download.STALL_SECONDS (tests)
local POLL_SECONDS = 1

local Download = {
    active = nil, -- one download at a time
}

local function mb(bytes)
    return string.format("%.1f MB", (bytes or 0) / (1024 * 1024))
end

--- Start downloading `book` to `dest_path`.
--- on_done(ok, err, opened_by_user) is called on the UI thread when finished.
function Download.start(plugin, book, dest_path, on_done)
    if Download.active then
        UIManager:show(InfoMessage:new{ text = _("Another download is still running."), timeout = 3 })
        return
    end
    local api = plugin.api
    local ok, err = api:ensureToken()
    if not ok then return on_done(false, err) end

    local title = type(book.title) == "string" and book.title or dest_path:match("[^/]+$")
    local part = dest_path .. ".part"
    os.remove(part)
    local expected = tonumber(book.fileSizeKb) and tonumber(book.fileSizeKb) * 1024 or nil
    if expected and expected <= 0 then expected = nil end

    Log.info("download start", "book=" .. tostring(book.id), "expected=" .. tostring(expected), "->", dest_path)

    local pid, read_fd = ffiutil.runInSubProcess(function(_child_pid, write_fd)
        -- Child: never refresh or persist tokens here (see header).
        api.no_refresh = true
        local dl_ok, dl_err = api:downloadToFile(book.id, part)
        ffiutil.writeToFD(write_fd, dl_ok and "ok" or ("err " .. tostring(dl_err)), true)
    end, true)
    if not pid then
        Log.err("download: could not start subprocess:", read_fd)
        return on_done(false, tostring(read_fd))
    end

    local job = {
        pid = pid, read_fd = read_fd, started = os.time(),
        last_size = 0, last_change = os.time(), watching = true,
    }
    Download.active = job
    Awake.hold(job) -- no sleeping (screensaver or autosuspend) mid-download

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

    local function finish(result_ok, result_err)
        if job.finished then return end
        job.finished = true
        Download.active = nil
        Awake.release(job)
        UIManager:unschedule(job.poll)
        closeDialog()
        local secs = os.time() - job.started
        if result_ok then
            os.remove(dest_path)
            local renamed, rerr = os.rename(part, dest_path)
            if not renamed then
                Log.err("download rename failed:", rerr)
                return on_done(false, rerr)
            end
            Log.info("download done", "book=" .. tostring(book.id), mb(lfs.attributes(dest_path, "size")), secs .. "s")
        else
            os.remove(part)
            Log.warn("download failed", "book=" .. tostring(book.id), tostring(result_err), "after " .. secs .. "s",
                "received " .. mb(job.last_size))
        end
        on_done(result_ok, result_err, job.watching)
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
                    closeDialog()
                    UIManager:show(InfoMessage:new{ text = _("Downloading in the background. You'll be told when it's ready."), timeout = 3 })
                end }},
                {{ text = _("Keep watching"), callback = function() UIManager:close(options) end }},
            },
        }
        UIManager:show(options)
    end

    dialog = ProgressbarDialog:new{
        title = T(_("Downloading “%1”"), title),
        subtitle = _("Press any key for options. The Kindle stays awake until it's done."),
        progress_max = expected,
        refresh_time_seconds = 2,
    }
    -- any key / tap opens our options instead of closing the dialog
    dialog.onDismiss = function() showOptions() return true end
    dialog.onAnyKeyPressed = dialog.onDismiss
    dialog.onTapClose = dialog.onDismiss
    dialog:show()

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
            if out == "ok" then
                finish(true)
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

--- Stop any running download (e.g. on exit).
function Download.cancelActive(reason)
    if Download.active and Download.active.stop then
        Download.active.stop(reason or "cancelled")
    end
end

return Download
