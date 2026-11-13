-- How long the Notes tab takes to open, and where the time goes: board draws,
-- the sticky notes' tilt (Sticky.rotate), pictures (Sticky.picture), text.
-- With demo/mock_memos.py --sample on 127.0.0.1:18090. Any model (pw3 is the
-- owner's report: the Notes tab slow where Downloads and Catalog aren't).
-- Writes <out>/notes-speed.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local lines = {}
local T = { draws = 0, rotate = 0, rotate_n = 0, image = 0, picture = 0, picture_n = 0, measure = 0 }

local function wrap(mod, name, key, count)
    local orig = mod[name]
    mod[name] = function(...)
        local t0 = os.clock()
        local r = { orig(...) }
        T[key] = T[key] + os.clock() - t0
        if count then T[count] = T[count] + 1 end
        return unpack(r)
    end
end

add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    local Notes = require("gzreader_notes")
    local Sticky = require("gzreader_sticky")
    wrap(Sticky, "rotate", "rotate", "rotate_n")
    wrap(Sticky, "image", "image")
    wrap(Sticky, "picture", "picture", "picture_n")
    local orig = Notes.Board.updateItems
    Notes.Board.updateItems = function(m, ...)
        if not m._gz_hold_draw then T.draws = T.draws + 1 end
        return orig(m, ...)
    end
    E.say("connect ->", tostring(Notes.connect(plugin(), "127.0.0.1:18090", "memos-test-token")))
    if Notes.connect_menu then require("ui/uimanager"):close(Notes.connect_menu, "full"); Notes.connect_menu = nil end
    Notes.show(plugin())
end, after = 20 })

local function open(label, cold)
    add({ fn = function()
        local Notes = require("gzreader_notes")
        if Notes.board then require("ui/uimanager"):close(Notes.board) end
    end, after = 4 })
    add({ fn = function(E)
        local UIManager = require("ui/uimanager")
        for k in pairs(T) do T[k] = 0 end
        local Notes = require("gzreader_notes")
        if cold and Notes.dropImages then Notes.dropImages(true) end -- (nothing kept: as after a restart)
        local c0, w0 = os.clock(), E.now()
        Notes.show(plugin())
        local c1 = os.clock()
        UIManager:forceRePaint()
        -- the tab bar comes on the next tick: measure up to the screen after it
        UIManager:nextTick(function()
            UIManager:nextTick(function()
                UIManager:forceRePaint()
                local line = string.format("%s: show %.2f s CPU, to the screen %.2f s CPU (%.2f s wall); board draws %d; "
                    .. "tilt %.2f s (%d notes), sticky images %.2f s, pictures %.2f s (%d)",
                    label, c1 - c0, os.clock() - c0, E.now() - w0, T.draws, T.rotate, T.rotate_n, T.image,
                    T.picture, T.picture_n)
                lines[#lines + 1] = line
                E.say(line)
            end)
        end)
    end, after = 12 })
end
open("cold open 1", true)
open("cold open 2", true)
open("open again 1")
open("open again 2")
add({ fn = function() require("gzreader_notes").board:onNextPage() end, after = 8 })
add({ shot = "notes-speed-page2" })
add({ fn = function() require("gzreader_notes").board:onPrevPage() end, after = 8 })
add({ shot = "notes-speed-page1" })
add({ fn = function(E)
    local f = io.open(E.out .. "/notes-speed.txt", "w")
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
end, after = 1 })
return s
