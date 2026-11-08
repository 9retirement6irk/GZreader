-- The statistics plugin (GZreader's copy): its database lookups wait until a
-- book's first page is on screen, with the totals kept with the book
-- meanwhile (plugins/statistics.koplugin/main.lua, initData).
--   luajit statistics_test.lua <koreader repo>
local REPO = arg[1]
local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

local function magic()
    local m
    m = setmetatable({}, { __index = function() return function() return m end end, __call = function() return m end })
    return m
end
local ticks = {}
local stubs = {
    ["ui/uimanager"] = { tickAfterNext = function(_, f) ticks[#ticks + 1] = f end, nextTick = function(_, f) f() end,
        scheduleIn = function() end, show = function() end },
    ["ui/widget/widget"] = { extend = function(_, o) o = o or {}; o.__index = o; return o end },
    ["logger"] = { dbg = function() end, info = function() end, warn = function() end, err = function() end },
    ["gettext"] = setmetatable({ pgettext = function(_, s) return s end, ngettext = function(s) return s end },
        { __call = function(_, s) return s end }),
    ["datastorage"] = { getDataDir = function() return "/tmp" end, getSettingsDir = function() return "/tmp" end },
    ["ffi/util"] = { template = function(s) return s end },
}
for _i, n in ipairs({ "ui/bidi", "ui/widget/buttondialog", "ui/widget/confirmbox", "device", "dispatcher", "docsettings",
        "ui/widget/infomessage", "ui/widget/keyvaluepage", "optmath", "readerprogress", "readhistory",
        "lua-ljsqlite3/init", "datetime", "libs/libkoreader-lfs", "util" }) do
    stubs[n] = magic()
end
for n, v in pairs(stubs) do package.preload[n] = function() return v end end
local Stats = dofile(REPO .. "/plugins/statistics.koplugin/main.lua")

local function book(data)
    local db = { lookups = 0, totals = 0 }
    local footer = { updates = 0 }
    function footer.maybeUpdateFooter() footer.updates = footer.updates + 1 end
    local doc = { getPageCount = function() return 300 end }
    local s = setmetatable({
        settings = { is_enabled = true, max_sec = 120, freeze_finished_books = false },
        data = data, document = doc, view = { footer = footer },
        ui = { document = doc, doc_props = { display_title = "Book", authors = "Someone" },
            doc_settings = { readSetting = function() return { status = "reading" } end },
            annotation = { getNumberOfHighlightsAndNotes = function() return 0, 0 end } },
    }, { __index = Stats })
    s.getIdBookDB = function() db.lookups = db.lookups + 1; return 7 end
    s.getPageTimeTotalStats = function(_, id) db.totals = db.totals + 1; db.id = id; return 40, 2400 end
    return s, db, footer
end

print("a book opened before (totals kept with it)")
ticks = {}
local s, db, footer = book({ gz_read_pages = 20, gz_read_time = 1000 })
s:initData()
check(db.lookups == 0 and db.totals == 0, "no database work before the first page")
check(s.avg_time == 50 and s.is_doc_not_frozen == true and s.data.pages == 300, "the kept totals give 50 s a page; pages counted")
check(s.id_curr_book == nil and #ticks == 1, "the lookups wait for the tick after the first page")
ticks[1]()
check(db.lookups == 1 and db.totals == 1 and db.id == 7 and s.id_curr_book == 7, "then: the book's row and its totals")
check(s.avg_time == 60 and s.data.gz_read_pages == 40 and s.data.gz_read_time == 2400, "the database's totals used, and kept for next time")
check(footer.updates == 1, "the footer updated once (its time-left estimate changed)")

print("a book never opened with GZreader's statistics")
ticks = {}
s, db, footer = book({})
s:initData()
check(s.avg_time == nil and db.lookups == 0, "no estimate yet, no database work")
ticks[1]()
check(s.avg_time == 60 and s.data.gz_read_pages == 40, "after the first page: the estimate, kept with the book")

print("closed, or initialised again, before the tick")
ticks = {}
s, db = book({})
s:initData()
s.document = nil
ticks[1]()
check(db.lookups == 0, "the book closed: nothing looked up")
ticks = {}
s, db = book({})
s:initData()
s:initData()
for _i, f in ipairs(ticks) do f() end
check(db.lookups == 1, "initData twice (statistics turned on again): looked up once")

print("insertDB keeps the totals with the book")
local src = io.open(REPO .. "/plugins/statistics.koplugin/main.lua"):read("*a")
check(src:find("self.avg_time = self.book_read_time / self.book_read_pages\n    -- GZreader: kept with the book", 1, true) ~= nil,
    "insertDB stores gz_read_pages / gz_read_time")

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
