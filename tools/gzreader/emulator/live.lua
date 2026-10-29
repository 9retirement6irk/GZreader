-- Live mode: someone drives the Kindle from outside.
-- Commands are files in <outdir>/cmd/ (processed in name order), one per line:
--   key <Name>     a Kindle 3 key (Up Down Left Right Press Back Menu Home
--                  LPgFwd LPgBack RPgFwd RPgBack Del AA Sym Space Shift Alt
--                  Period, or a letter A-Z)
--   type <text>    text into the focused field (as a keyboard would)
-- After the panel changes and settles, <outdir>/screen.png and
-- <outdir>/state.json are rewritten.
return {
    start = 2,
    { fn = function(E)
        local UIManager = require("ui/uimanager")
        local Event = require("ui/event")
        local lfs = require("libs/libkoreader-lfs")
        local BB = require("ffi/blitbuffer")
        local dir = E.out .. "/cmd"
        lfs.mkdir(dir)
        local queue = {}
        local next_at = 0
        local poll
        local function step()
            if #queue == 0 then
                local names = {}
                for name in lfs.dir(dir) do if name:match("%.txt$") then names[#names + 1] = name end end
                table.sort(names)
                for _i, name in ipairs(names) do
                    local f = io.open(dir .. "/" .. name, "rb")
                    if f then
                        for line in f:lines() do if line ~= "" then queue[#queue + 1] = line end end
                        f:close()
                    end
                    os.remove(dir .. "/" .. name)
                end
            end
            local now = E.now()
            if #queue > 0 and now >= next_at then
                local line = table.remove(queue, 1)
                local verb, rest = line:match("^(%S+)%s*(.*)$")
                E.say("live:", line:sub(1, 1) == "t" and "type (" .. #rest .. " chars)" or line)
                local ok, err = pcall(function()
                    if verb == "key" then
                        E.key(rest)
                    elseif verb == "type" then
                        UIManager:sendEvent(Event:new("TextInput", rest))
                    end
                end)
                if not ok then E.say("live: bad command", tostring(err)) end
                E.last_cmd_at = now
                next_at = now + 0.3
            end
            -- the panel: write it once it has settled
            if E.refreshes ~= E.written and now - (E.last_refresh_t or 0) > 0.35 then
                E.written = E.refreshes
                local g = BB.new(E.display:getWidth(), E.display:getHeight(), BB.TYPE_BB8)
                g:blitFrom(E.display, 0, 0, 0, 0, E.display:getWidth(), E.display:getHeight())
                pcall(function() g:writePNG(E.out .. "/screen.png.tmp") end)
                g:free()
                os.rename(E.out .. "/screen.png.tmp", E.out .. "/screen.png")
                local f = io.open(E.out .. "/state.json.tmp", "wb")
                if f then
                    f:write(require("json").encode({ seq = E.refreshes, at = now, windows = E.top() }))
                    f:close()
                    os.rename(E.out .. "/state.json.tmp", E.out .. "/state.json")
                end
            end
        end
        poll = function()
            local ok, err = pcall(step)
            if not ok then E.say("live: error", tostring(err)) end
            UIManager:scheduleIn(0.1, poll)
        end
        poll()
        E.say("live mode ready")
    end, after = 1 },
    { wait = 7 * 24 * 3600 },
}
