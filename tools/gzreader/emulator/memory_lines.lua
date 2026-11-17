-- A book opened, Home, the book again, several times over (what a slip of the
-- Home key costs on a Kindle with little memory): the three memory lines of
-- gzreader_opentiming.lua are in gzreader.log each time, forced onto the
-- storage (the emulator is made to count as a low-memory Kindle), and how
-- GZreader's memory moves from one round to the next is written down.
--   GZ_EMU_BOOK=<an EPUB> GZ_EMU_MODEL=dxg run.sh memory_lines.lua <out>
-- GZ_EMU_ROUNDS: how many times (default 4). Writes <out>/memory_lines.txt:
-- its checks, then a table (round, GZreader MB, Lua MB as it is, Lua MB
-- after a full collection).
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines, rows = {}, {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local ROUNDS = tonumber(os.getenv("GZ_EMU_ROUNDS")) or 4
local BOOK = "/mnt/us/GZreader/memory.epub"

local function reader() return require("apps/reader/readerui").instance end
local function bookOpen()
    local r = reader()
    return r and r.document and r.document.file == BOOK and package.loaded["gzreader_opentiming"].cur == nil
end
local function atHome()
    return reader() == nil and require("gzreader_opentiming").windowIs(UIM()._window_stack) == "Home"
end
local function measure(round, where)
    local OT = require("gzreader_opentiming")
    local m = OT.memoryNow()
    local raw = m.lua_mb
    collectgarbage(); collectgarbage()
    rows[#rows + 1] = string.format("%d\t%s\t%s\t%.1f\t%.1f\t%s", round, where, tostring(m.rss), raw,
        collectgarbage("count") / 1024, tostring(OT.memoryNow().rss))
end

add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 6 })
add({ fn = function()
    -- (the emulator reads the host's /proc/meminfo: count it as a Kindle with 128 MB)
    require("gzreader_opentiming").SYNC_BELOW_KB = math.huge
    require("gzreader_log").synced = 0
    os.execute("mkdir -p /mnt/us/GZreader && cp '" .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. "' " .. BOOK)
end, after = 1 })
for round = 1, ROUNDS do
    add({ fn = function() require("apps/reader/readerui"):showReader(BOOK) end, after = 2 })
    add({ wait_for = bookOpen, timeout = 240, label = "book open " .. round, after = 3 })
    add({ fn = function() measure(round, "book") end, after = 1 })
    add({ fn = function() if reader() then reader():onHome() end end, after = 2 })
    add({ wait_for = atHome, timeout = 60, label = "Home " .. round, after = 4 })
    add({ fn = function() measure(round, "Home") end, after = 1 })
end
add({ shot = "memory-home" })
add({ fn = function(E)
    local Log = require("gzreader_log")
    Log.flush()
    local f = io.open(Log.path, "rb")
    local text = f and f:read("*a") or ""
    if f then f:close() end
    local function count(pat) return select(2, text:gsub(pat, "")) end
    local mem = "free memory %d+ MB %(%+ %d+ MB cache%), GZreader %d+ MB %(Lua [%d.]+ MB%)"
    check(count("%] book open starting: memory%.epub | " .. mem) == ROUNDS,
        "a line as each open starts: " .. count("%] book open starting: memory%.epub | " .. mem) .. " of " .. ROUNDS)
    check(count("%] book closed | " .. mem) == ROUNDS, "a line as each book closes: " .. count("%] book closed | " .. mem) .. " of " .. ROUNDS)
    check(count("%] Home on screen [%d.]+ s after the book closed | " .. mem) == ROUNDS,
        "a line with Home back on screen: " .. count("%] Home on screen [%d.]+ s after the book closed | " .. mem) .. " of " .. ROUNDS)
    check(count("%] book open: ") == ROUNDS, "the timing line of each open is still there")
    check((Log.synced or 0) == 3 * ROUNDS, "each of them forced onto the storage (fsync): " .. tostring(Log.synced) .. " of " .. 3 * ROUNDS)
    -- the order within a round: starting, the timing line, closed, Home
    local a = text:find("book open starting: memory%.epub")
    local b = a and text:find("%] book open: ", a)
    local c = b and text:find("%] book closed |", b)
    local d = c and text:find("%] Home on screen", c)
    check(a and b and c and d, "in order: starting, opened, closed, Home")
    local out = io.open(E.out .. "/memory_lines.txt", "w")
    if out then
        out:write(table.concat(lines, "\n"), "\n\nround\twhere\tGZreader MB\tLua MB\tLua MB collected\tGZreader MB after\n",
            table.concat(rows, "\n"), "\n")
        out:close()
    end
    for _i, l in ipairs(lines) do print("[emu] " .. l) end
end, after = 1 })
return s
