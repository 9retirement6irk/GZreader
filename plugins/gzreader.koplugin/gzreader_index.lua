--[[--
Local index of the readable books in Grimmory: authors, series and per-library
counts, built from the book list filtered to formats the Kindle can open.

Why: Grimmory's author/series endpoints include audiobook-only authors and
series (which then open to nothing), and each list request takes seconds on
a Kindle 3. The index is built in a forked subprocess (UI stays responsive),
saved to settings/gzreader_index.json, and refreshed when older than a day.
]]

local DataStorage = require("datastorage")
local JSON = require("json")
local ProgressbarDialog = require("ui/widget/progressbardialog")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local Log = require("gzreader_log")
local _ = require("gettext")

local MAX_AGE = 24 * 3600
local PAGE = 50

local Index = {
    data = nil,      -- { built_at, server, user, authors = {name=count}, series = {name={count, authors}}, libraries = {id=count}, total }
    building = nil,
}

local function path() return DataStorage:getSettingsDir() .. "/gzreader_index.json" end
local function progressPath() return DataStorage:getSettingsDir() .. "/gzreader_index.progress" end

function Index.load(store)
    if Index.data and Index.data.server == store.server and Index.data.user == store.username then
        return Index.data
    end
    local f = io.open(path(), "rb")
    if not f then return nil end
    local ok, data = pcall(JSON.decode, f:read("*a"))
    f:close()
    if ok and type(data) == "table" and data.server == store.server and data.user == store.username then
        Index.data = data
        return data
    end
end

function Index.isStale(data)
    return not data or type(data.built_at) ~= "number" or os.time() - data.built_at > MAX_AGE
        or data.built_at > os.time() + 3600 -- clock went backwards a lot
        or data.subtitles == nil -- built before GZreader 1.0.19 (no subtitles yet)
end

--- Child process: page through readable books and aggregate.
local function collect(api, report)
    local authors, series, libraries, files, total = {}, {}, {}, {}, 0
    local page, pages = 0, 1
    while page < pages do
        local data, err = api:listBooks{ page = page, size = PAGE, sort = "title", dir = "asc",
            fileType = api.READABLE_TYPES }
        if not data then return nil, err end
        pages = tonumber(data.totalPages) or 1
        for _, b in ipairs(type(data.content) == "table" and data.content or {}) do
            local ftype = type(b.primaryFileType) == "string" and b.primaryFileType:upper() or ""
            if type(b) == "table" and b.isPhysical ~= true and ftype ~= "" and ftype ~= "AUDIOBOOK" then
                total = total + 1
                local book_authors = type(b.authors) == "table" and b.authors or {}
                for _, a in ipairs(book_authors) do
                    if type(a) == "string" and a ~= "" then authors[a] = (authors[a] or 0) + 1 end
                end
                if type(b.seriesName) == "string" and b.seriesName ~= "" then
                    local s = series[b.seriesName] or { count = 0, authors = {} }
                    s.count = s.count + 1
                    for _, a in ipairs(book_authors) do
                        if type(a) == "string" and #s.authors < 3 then
                            local seen = false
                            for _, x in ipairs(s.authors) do if x == a then seen = true end end
                            if not seen then s.authors[#s.authors + 1] = a end
                        end
                    end
                    series[b.seriesName] = s
                end
                if type(b.primaryFileName) == "string" and b.primaryFileName ~= "" then
                    -- for relinking books already on the Kindle (file name -> book)
                    files[b.primaryFileName:match("[^/\\]+$")] = { b.id, b.primaryFileId, ftype, b.title }
                end
                if b.libraryId then
                    local k = tostring(b.libraryId)
                    libraries[k] = (libraries[k] or 0) + 1
                end
            end
        end
        page = page + 1
        report(page, pages)
    end
    -- Subtitles: only Grimmory's web book list has them. Optional (older
    -- servers may not have /books/page); failures just leave them out.
    local subtitles = {}
    local wpage, wpages = 0, 1
    while wpage < wpages and wpage < 500 do
        local data = api:listWebBooks(wpage, 100)
        if not data or type(data.content) ~= "table" then break end
        local meta = type(data.page) == "table" and data.page or data
        wpages = tonumber(meta.totalPages) or 1
        for _, b in ipairs(data.content) do
            local m = type(b) == "table" and b.metadata
            local sub = type(m) == "table" and m.subtitle
            if type(sub) == "string" and sub ~= "" and b.id then subtitles[tostring(b.id)] = sub end
        end
        wpage = wpage + 1
    end
    return { authors = authors, series = series, libraries = libraries, files = files, total = total, subtitles = subtitles }
end

--- Build (or rebuild) the index. `show` = show a progress dialog.
--- on_done(data_or_nil, err) runs on the UI thread.
function Index.build(plugin, show, on_done)
    if Index.building then
        if on_done then table.insert(Index.building.waiters, on_done) end
        return
    end
    local api = plugin.api
    local ok, err = api:ensureToken() -- refresh in the parent only (see gzreader_download)
    if not ok then if on_done then on_done(nil, err) end return end
    local store = plugin.store
    local out, prog = path() .. ".tmp", progressPath()
    os.remove(out); os.remove(prog)
    local started = os.time()
    Log.info("index build start")

    local pid, read_fd = ffiutil.runInSubProcess(function(_pid, write_fd)
        api.no_refresh = true
        local data, cerr = collect(api, function(page, pages)
            local f = io.open(prog, "wb")
            if f then f:write(page, " ", pages); f:close() end
        end)
        if data then
            data.built_at = os.time()
            data.server, data.user = store.server, store.username
            local f = io.open(out, "wb")
            if f then f:write(JSON.encode(data)); f:close() end
        end
        ffiutil.writeToFD(write_fd, data and "ok" or ("err " .. tostring(cerr)), true)
    end, true)
    if not pid then
        if on_done then on_done(nil, tostring(read_fd)) end
        return
    end

    local job = { waiters = { on_done } }
    Index.building = job
    require("gzreader_net").hold("index")
    local dialog
    if show then
        dialog = ProgressbarDialog:new{
            title = _("Indexing your Grimmory library…"),
            subtitle = _("Only needed once a day. Press any key to hide."),
            progress_max = 100,
            refresh_time_seconds = 2,
        }
        dialog.dismiss_callback = function() dialog = nil end
        dialog:show()
    end

    local function finish(data, ferr)
        Index.building = nil
        require("gzreader_net").release("index")
        if dialog then dialog.dismiss_callback = nil; UIManager:close(dialog); dialog = nil end
        os.remove(prog)
        Log.info("index build", data and "done" or ("failed: " .. tostring(ferr)),
            data and (tostring(data.total) .. " books") or "", (os.time() - started) .. "s")
        for _, cb in ipairs(job.waiters) do if cb then cb(data, ferr) end end
    end

    local function poll()
        local f = io.open(prog, "rb")
        if f and dialog then
            local page, pages = (f:read("*a") or ""):match("(%d+) (%d+)")
            if page then dialog:reportProgress(math.floor(tonumber(page) / math.max(tonumber(pages), 1) * 100)) end
        end
        if f then f:close() end
        if ffiutil.isSubProcessDone(pid) then
            local result = ffiutil.readAllFromFD(read_fd)
            if result == "ok" then
                os.remove(path())
                os.rename(out, path())
                Index.data = nil
                finish(Index.load(store))
            else
                os.remove(out)
                finish(nil, result:match("^err (.*)$") or "index process ended unexpectedly")
            end
            return
        end
        UIManager:scheduleIn(1, poll)
    end
    UIManager:scheduleIn(1, poll)
end

--- Get an index, building it if missing; refresh in the background if stale.
function Index.get(plugin, on_ready)
    local data = Index.load(plugin.store)
    if data then
        if Index.isStale(data) and not Index.building then
            Index.build(plugin, false, nil) -- quietly refresh for next time
        end
        return on_ready(data)
    end
    Index.build(plugin, true, function(built, err)
        if built then on_ready(built) else plugin:showError(err) end
    end)
end

return Index
