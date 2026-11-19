-- `text` written in one UJI test writer's hand (tests/hwr/hwr_writers.lua): letters
-- side by side on a baseline, small letters `xh` tall, capitals and ascenders
-- taller, descenders below; a space is 0.9 of xh. As Ink Away's tests/hwr.lua
-- lays them out (MIT, see tests/hwr/README.md). Returns flat {x, y, …}
-- strokes from (0, 0) and the width written.
--   local write = dofile(".../hwr_write.lua"); write(writers.UJI_W12, "hello world", 60)
local ASC, DESC, CAP = "bdfhklt", "gjpqy", "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function box(strokes)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, s in ipairs(strokes) do
        for i = 1, #s - 1, 2 do
            x0, x1 = math.min(x0, s[i]), math.max(x1, s[i])
            y0, y1 = math.min(y0, s[i + 1]), math.max(y1, s[i + 1])
        end
    end
    return x0, y0, x1, y1
end

return function(hand, text, xh)
    xh = xh or 300
    local strokes, x, base = {}, 0, 1.6 * xh
    for ch in text:gmatch(".") do
        if ch == " " then
            x = x + 0.9 * xh
        else
            local src = hand[ch]
            local x0, y0, x1, y1 = box(src)
            local tall = CAP:find(ch, 1, true) or ASC:find(ch, 1, true)
            local h = tall and 1.6 * xh or xh
            if ch == "i" or ch == "j" then h = 1.4 * xh end
            local s = h / math.max(y1 - y0, 1)
            local bottom = base + (DESC:find(ch, 1, true) and 0.5 * xh or 0)
            if DESC:find(ch, 1, true) then s = 1.5 * xh / math.max(y1 - y0, 1) end
            for _, st in ipairs(src) do
                local t = {}
                for i = 1, #st - 1, 2 do
                    t[#t + 1] = x + (st[i] - x0) * s
                    t[#t + 1] = bottom - (y1 - st[i + 1]) * s
                end
                strokes[#strokes + 1] = t
            end
            x = x + (x1 - x0) * s + 0.3 * xh
        end
    end
    return strokes, x
end
