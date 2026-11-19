--[[--
Text a server will store: valid UTF-8 without NUL bytes.

Debug reports carry the ends of log files, and a log cut short (a crash, the
battery running out) can end in NUL bytes, or a part can start in the middle
of a multi-byte letter. The report feed (Tianji) keeps reports in PostgreSQL,
whose text can't hold a NUL: such a report was refused with HTTP 500 every
time it was sent. No dependencies: the watchdog (its own process) loads it
with dofile.

  require("gzreader_textclean")("a\0b\255c") --> "ab?c"
]]

local function clean(s)
    if type(s) ~= "string" then return s end
    if not s:find("[%z\128-\255]") then return s end -- (plain ASCII: as it is)
    s = s:gsub("%z", "")
    if not s:find("[\128-\255]") then return s end
    local out, i, n = {}, 1, #s
    while i <= n do
        local c = s:byte(i)
        local len = c < 0x80 and 1 or (c >= 0xC2 and c <= 0xDF) and 2 or (c >= 0xE0 and c <= 0xEF) and 3
            or (c >= 0xF0 and c <= 0xF4) and 4 or 0
        local ok = len > 0 and i + len - 1 <= n
        for j = 1, ok and len - 1 or 0 do
            local b = s:byte(i + j)
            if b < 0x80 or b > 0xBF then ok = false; break end
        end
        if ok then
            out[#out + 1] = s:sub(i, i + len - 1)
            i = i + len
        else
            out[#out + 1] = "?" -- a stray byte (a letter cut in two)
            i = i + 1
        end
    end
    return table.concat(out)
end

return clean
