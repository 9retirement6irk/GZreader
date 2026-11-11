-- gzreader_json.lua: KOReader's rapidjson when it loads, LuaJSON otherwise,
-- with the same results for GZreader's code (null is nil, marked lists stay
-- lists). The real rapidjson (ARM) is checked in the emulator (keeps.lua);
-- here a stand-in with its behaviour (a null placeholder, __jsontype).
--   luajit json_test.lua <gzreader.koplugin> <koreader base (common/)>
local PLUGIN, KOROOT = arg[1], arg[2]
package.path = PLUGIN .. "/?.lua;" .. KOROOT .. "/common/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

local dkjson = require("dkjson")
-- LuaJSON stand-in (the tests' usual "json"): dkjson, null as nil, its own list mark
local lua_calls = 0
package.preload["json"] = function()
    return {
        decode = function(s) lua_calls = lua_calls + 1; local v, _, err = dkjson.decode(s); if err then error(err) end; return v end,
        encode = function(v) lua_calls = lua_calls + 1; return dkjson.encode(v) end,
    }
end

--- A rapidjson stand-in: null is a placeholder (lightuserdata there; a table
--- here), an empty table is {} unless its metatable says __jsontype = "array",
--- invalid text gives nil + an error, and it refuses functions.
local NULL = setmetatable({}, { __tostring = function() return "rapidjson.null" end })
local function rjEncodeCheck(v)
    if type(v) == "function" then error("unsupported type function") end
    if type(v) == "table" then for _k, x in pairs(v) do rjEncodeCheck(x) end end
end
local rj_calls = 0
local RJ = {
    null = NULL,
    decode = function(s)
        rj_calls = rj_calls + 1
        local v, _, err = dkjson.decode(s, 1, NULL)
        if err then return nil, err end
        return v
    end,
    encode = function(v)
        rj_calls = rj_calls + 1
        rjEncodeCheck(v)
        local function conv(x)
            if type(x) ~= "table" then return x end
            local mt = getmetatable(x)
            local out = {}
            for k, y in pairs(x) do out[k] = conv(y) end
            if next(x) == nil then
                return setmetatable(out, { __jsontype = (mt and mt.__jsontype == "array") and "array" or "object" })
            end
            return out
        end
        return dkjson.encode(conv(v))
    end,
}

print("with rapidjson")
package.loaded["gzreader_json"] = nil
package.preload["rapidjson"] = function() return RJ end
local Json = require("gzreader_json")
check(Json.fast, "rapidjson found: used")
local d = Json.decode('{"a":null,"b":[1,null,3],"c":{"d":null,"e":"x"},"n":5,"f":0.42}')
check(d.a == nil and d.c.d == nil and d.c.e == "x" and d.b[1] == 1 and d.b[2] == nil and d.b[3] == 3,
    "null is nil, also in lists and nested objects (as the tests' dkjson gives)")
check(d.n == 5 and d.f == 0.42, "numbers")
check(Json.decode("null") == nil, "null itself: nil")
check(Json.decode("[]") ~= nil and next(Json.decode("[]")) == nil, "an empty list: an empty table")
local before = lua_calls
check(not pcall(Json.decode, "not json") and lua_calls == before + 1, "not JSON: LuaJSON tries too, and raises")
check(Json.encode({ x = Json.list() }) == '{"x":[]}', "Json.list(): [] when empty")
check(Json.encode({}) == "{}", "an unmarked empty table: {}")
check(Json.encode(Json.list({ 1, 2 })) == "[1,2]", "a marked list with items")
local mt = getmetatable(Json.list())
check(mt.__jsontype == "array" and mt.__is_luajson_array == true, "the list mark works for both libraries")
before = lua_calls
pcall(Json.encode, { f = function() end })
check(lua_calls == before + 1, "a value rapidjson refuses: LuaJSON gets it (and its error, as before)")
local rt = Json.decode(Json.encode({ id = 12, title = "Été", tags = Json.list({ "a" }) }))
check(rt.id == 12 and rt.title == "Été" and rt.tags[1] == "a", "a round trip")
before = rj_calls
Json.decode('{"a":1}'); Json.encode({ a = 1 })
check(rj_calls == before + 2, "everyday decode and encode go to rapidjson")

print("without rapidjson")
package.loaded["gzreader_json"] = nil
package.preload["rapidjson"] = function() error("module 'rapidjson' not found") end
package.loaded["rapidjson"] = nil
Json = require("gzreader_json")
check(not Json.fast, "no rapidjson: LuaJSON")
before = lua_calls
check(Json.decode('{"a":1}').a == 1 and Json.encode({ a = 1 }) == '{"a":1}' and lua_calls == before + 2, "decode and encode by LuaJSON")
check(Json.encode({ x = Json.list() }) == '{"x":[]}', "lists still []")

print("GZreader's code")
local function lines(cmd)
    local p = io.popen(cmd)
    local out = {}
    for l in p:lines() do out[#out + 1] = l end
    p:close()
    return out
end
local direct = lines("grep -ln 'require(\"json\")' '" .. PLUGIN .. "'/*.lua | grep -v '/gzreader_json.lua$'")
check(#direct == 0, "every GZreader module uses gzreader_json, not require(\"json\") (" .. table.concat(direct, ", ") .. ")")
local marks = lines("grep -n '__is_luajson_array' '" .. PLUGIN .. "'/*.lua | grep -v '/gzreader_json.lua:' | grep -v '__jsontype'")
check(#marks == 0, "a LuaJSON list mark always comes with rapidjson's __jsontype (or use Json.list): " .. table.concat(marks, " | "))

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
