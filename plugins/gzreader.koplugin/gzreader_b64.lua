--[[--
Base64, quickly.

KOReader's own (ffi/sha2's bin_to_base64 and base64_to_bin) is written in
Lua and takes seconds for a megabyte: on the Scribe model a 1.95 MB photo in
a drawing took 3.2 s to decode, 95% of the 3.4 s the page took to draw, and
that was paid again each time the page's pictures were forgotten. LuaSocket's
mime.b64 / mime.unb64 are C and take a few milliseconds for the same. They
come with KOReader (socket.http needs them); where they can't be loaded,
KOReader's own are used.

    local B64 = require("gzreader_b64")
    local text = B64.encode(bytes)    -- no line breaks, padded
    local bytes = B64.decode(text)    -- nil when it isn't base64
]]

local B64 = {}

local function mime()
    if B64._mime == nil then
        local ok, m = pcall(require, "mime")
        B64._mime = ok and type(m) == "table" and type(m.b64) == "function" and type(m.unb64) == "function" and m or false
    end
    return B64._mime or nil
end

function B64.encode(bytes)
    bytes = tostring(bytes or "")
    local m = mime()
    if m then
        local ok, out = pcall(m.b64, bytes)
        if ok and type(out) == "string" then return out end
    end
    return require("ffi/sha2").bin_to_base64(bytes)
end

function B64.decode(text)
    if type(text) ~= "string" then return nil end
    local m = mime()
    if m then
        local ok, out = pcall(m.unb64, text)
        if ok and type(out) == "string" and (out ~= "" or text == "") then return out end
    end
    local ok, out = pcall(require("ffi/sha2").base64_to_bin, text)
    return ok and out or nil
end

return B64
