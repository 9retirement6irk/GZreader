-- CoverBrowser's book info database is set up once, not at every start
-- (GZreader's change to BookInfoManager:createDB): a database already at the
-- current version is only asked its version; a new or older one is set up as
-- before.
--   luajit coverdb_test.lua <coverbrowser.koplugin>
local DIR = arg[1] or "../../../plugins/coverbrowser.koplugin"
local f = assert(io.open(DIR .. "/bookinfomanager.lua"))
local src = f:read("*a")
f:close()
local pass, fail = 0, 0
local function check(ok, what)
    if ok then pass = pass + 1; print("  ok   " .. what) else fail = fail + 1; print("  FAIL " .. what) end
end
local a = assert(src:find("function BookInfoManager:createDB()", 1, true))
local b = assert(src:find("function BookInfoManager:openDbConnection()", 1, true))
local version = tonumber(src:match("local BOOKINFO_DB_VERSION = (%d+)"))

local function run(stored_version)
    local log = {}
    local conn = {
        exec = function(_s, sql) log[#log + 1] = "exec " .. sql:sub(1, 40):gsub("%s+", " ") end,
        rowexec = function(_s, sql) log[#log + 1] = "rowexec " .. sql; return stored_version end,
        close = function() log[#log + 1] = "close" end,
    }
    local B = { db_location = "x", settings = {}, loadSettings = function() end, saveSetting = function() end }
    local env = setmetatable({
        BookInfoManager = B, BOOKINFO_DB_VERSION = version, BOOKINFO_DB_SCHEMA = "CREATE TABLE IF NOT EXISTS bookinfo",
        SQ3 = { open = function() log[#log + 1] = "open"; return conn end },
        Device = { canUseWAL = function() return false end },
        logger = { warn = function() end }, UIManager = { show = function() end },
        InfoMessage = { new = function() return {} end }, _ = function(t) return t end,
        os = { remove = function() log[#log + 1] = "remove" end },
    }, { __index = _G })
    local chunk = assert(load(src:sub(a, b - 1), "createDB", "t", env))
    chunk()
    B:createDB()
    return table.concat(log, " | "), B
end

local log, B = run(version)
check(log == "open | rowexec PRAGMA user_version; | close" and B.db_created == true,
    "a database at the current version: its version is read, nothing is set up again (" .. log .. ")")
log, B = run(0)
check(log:find("exec PRAGMA journal_mode", 1, true) and log:find("exec CREATE TABLE", 1, true) and log:find("remove", 1, true)
    and log:find("exec PRAGMA user_version=" .. version, 1, true) and B.db_created == true,
    "a new database: journal mode, the tables, the version, as before")
log = run(version - 1)
check(log:find("remove", 1, true) and log:find("exec PRAGMA user_version=" .. version, 1, true),
    "an older version: made again, as before")
print(("cover database: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
