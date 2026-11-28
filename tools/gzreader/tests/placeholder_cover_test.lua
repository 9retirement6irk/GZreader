-- The placeholder cover's frame (ZenOS cover_utils.lua's ornate_background) is
-- kept on disk per size (GZreader's change): a start draws the SVG only when
-- that size isn't kept yet.
--   luajit placeholder_cover_test.lua <zenos.koplugin>
local DIR = arg[1] or "../../../plugins/zenos.koplugin"
local f = assert(io.open(DIR .. "/common/cover_utils.lua"))
local src = f:read("*a")
f:close()
local pass, fail = 0, 0
local function check(ok, what)
    if ok then pass = pass + 1; print("  ok   " .. what) else fail = fail + 1; print("  FAIL " .. what) end
end
local a = assert(src:find("local function ornate_background(width, height, paper)", 1, true))
local b = assert(src:find("local function placeholder_cache_key(", 1, true))

local WHITE = { "white" }
local function make(disk, frame_path)
    local log, mem = {}, {}
    local function bb(name)
        return { name = name, paintRect = function() end, alphablitFrom = function() end, pmulalphablitFrom = function() end,
            scale = function(s) return s end, free = function() end }
    end
    local env = setmetatable({
        ORNATE_FRAME_PATH = frame_path, ORNATE_FRAME_CACHE_KEY = "k",
        RenderCache = {
            get = function(_s, _k, w, h) return mem[w .. "x" .. h] end,
            put = function(_s, _k, w, h, v) mem[w .. "x" .. h] = v; log[#log + 1] = "mem put" end,
        },
        Blitbuffer = { TYPE_BBRGB32 = 5, COLOR_WHITE = WHITE, new = function() log[#log + 1] = "new"; return bb("drawn") end },
        require = function(name)
            if name == "ui/renderimage" then
                return { renderSVGImageFile = function() log[#log + 1] = "svg"; return bb("svg"), true end }
            elseif name == "common/cover_disk_cache" then
                if not disk then error("no disk cache") end
                return {
                    load = function(p, w, h) log[#log + 1] = "disk load"; return disk[p .. w .. "x" .. h] end,
                    save = function(p, w, h, v) log[#log + 1] = "disk save"; disk[p .. w .. "x" .. h] = v end,
                }
            end
            return require(name)
        end,
    }, { __index = _G })
    local fn = assert(load(src:sub(a, b - 1) .. "\nreturn ornate_background", "ornate", "t", env))()
    return fn, log
end

local disk = {}
local fn, log = make(disk, "/frame.svg")
local first = fn(100, 150, WHITE)
check(table.concat(log, ",") == "disk load,new,svg,disk save,mem put" and first.name == "drawn",
    "a size not kept yet: drawn from the SVG, then kept on disk and in memory (" .. table.concat(log, ",") .. ")")
local n = #log
check(fn(100, 150, WHITE) == first and #log == n, "again in the same run: from memory, nothing read or drawn")
fn, log = make(disk, "/frame.svg") -- (a new start: memory is empty, the disk isn't)
local again = fn(100, 150, WHITE)
check(table.concat(log, ",") == "disk load,mem put" and again == first, "the next start: read from disk, no SVG drawn (" .. table.concat(log, ",") .. ")")
fn(60, 90, WHITE)
check(table.concat(log, ","):find("svg", 1, true) ~= nil, "another size: drawn once more")
fn, log = make(disk, "/frame.svg")
fn(100, 150, { "cream" })
check(table.concat(log, ",") == "new,svg,mem put", "another paper colour isn't kept on disk (only the white one is)")
fn, log = make(nil, "/frame.svg")
check(fn(100, 150, WHITE) ~= nil and table.concat(log, ",") == "new,svg,mem put", "no disk cache module: drawn as before")
fn, log = make(disk, nil)
check(fn(100, 150, WHITE) ~= nil and table.concat(log, ",") == "new,mem put", "no frame file: a plain page, nothing kept on disk")
print(("placeholder cover: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
