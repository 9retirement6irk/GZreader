--[[--
JSON for GZreader: KOReader's C library (rapidjson, in common/) when it
loads, its Lua one (require("json"): LuaJSON) otherwise.

LuaJSON is Lua with LPeg: on Grimmory-sized book lists it decodes 5–7 times
and encodes 8–10 times slower than a C library (the performance review,
2026-11). That was the library index, a page's books, the library copy on
Kindles without Wi-Fi, the outbox, each background request's result…

What stays the same for the code that uses it:
- JSON null decodes to nil (rapidjson gives a placeholder value; LuaJSON a
  callable one, which gzreader_annosync.lua also accepts);
- a list that must stay a list when it's empty is marked in its metatable
  for both libraries: Json.list(t) (`__jsontype = "array"` for rapidjson,
  `__is_luajson_array` for LuaJSON). An empty table without the mark is {}
  with either library.
- anything rapidjson won't take (text that isn't JSON, a value it can't
  encode) goes to LuaJSON, so errors are LuaJSON's as before.
]]

local LuaJSON = require("json")

local Json = {}

local ok_rj, RJ = pcall(require, "rapidjson")
if ok_rj and type(RJ) == "table" and type(RJ.decode) == "function" and type(RJ.encode) == "function" then
    Json.rapidjson = RJ
end
Json.fast = Json.rapidjson ~= nil

local LIST_MT = { __jsontype = "array", __is_luajson_array = true }

--- `t` (a new table when nil) marked as a list: [] when empty, with either library.
function Json.list(t)
    return setmetatable(t or {}, LIST_MT)
end

local function stripNulls(t, null, depth)
    if depth > 200 then return t end
    for k, v in next, t do
        if v == null then
            t[k] = nil
        elseif type(v) == "table" then
            stripNulls(v, null, depth + 1)
        end
    end
    return t
end

--- The Lua value for JSON text `s`. Raises (as LuaJSON does) when `s` isn't JSON.
function Json.decode(s)
    local RJ_ = Json.rapidjson
    if RJ_ and type(s) == "string" then
        local ok, v = pcall(RJ_.decode, s)
        if ok and v ~= nil then
            if v == RJ_.null then return nil end
            if type(v) == "table" then stripNulls(v, RJ_.null, 0) end
            return v
        end
    end
    return LuaJSON.decode(s)
end

--- JSON text for `v`.
function Json.encode(v)
    local RJ_ = Json.rapidjson
    if RJ_ then
        local ok, s = pcall(RJ_.encode, v)
        if ok and type(s) == "string" then return s end
    end
    return LuaJSON.encode(v)
end

return Json
