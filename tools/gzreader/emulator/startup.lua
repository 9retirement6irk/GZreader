-- How long GZreader takes to start: from the program starting to Home on
-- the screen (and the first refresh after it), CPU time, Lua memory and
-- modules loaded. Run it on a configured install (run.sh with GZ_EMU_KEEP=1
-- after any script that finishes the setup guide), a few times.
local s = { start = 0.05 }
s[1] = { fn = function(E)
    local UIManager = require("ui/uimanager")
    local function homeShown()
        for _i, w in ipairs(UIManager._window_stack) do
            if w.widget and w.widget._zen_home_focus_targets then return true end
        end
        return false
    end
    local function poll()
        if homeShown() and E.last_refresh_t then
            local wall = E.last_refresh_t - E.start
            local cpu = os.clock() - E.clock0
            local n = 0
            for _k in pairs(package.loaded) do n = n + 1 end
            E.say(string.format("STARTUP Home on screen after %.2f s (CPU %.2f s), modules loaded %d", wall, cpu, n))
            UIManager:scheduleIn(20, function()
                collectgarbage(); collectgarbage()
                local m = 0
                for _k in pairs(package.loaded) do m = m + 1 end
                E.say(string.format("STARTUP after 20 s more: CPU %.2f s, Lua memory %.1f MB, modules loaded %d",
                    os.clock() - E.clock0, collectgarbage("count") / 1024, m))
            end)
            return
        end
        UIManager:scheduleIn(0.1, poll)
    end
    poll()
end, after = 26 }
return s
