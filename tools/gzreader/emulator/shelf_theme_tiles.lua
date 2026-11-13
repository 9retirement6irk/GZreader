-- The Bookshelf theme screen and Which ornaments (gzreader_shelfpreview.lua):
-- screenshots, and taps on a touch model or the 5-way on one with keys.
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader ./run.sh shelf_theme_tiles.lua <out>
--   GZ_EMU_MODEL=k3  (the same with the 5-way)
-- Checks in <out>/shelf_theme_tiles.txt ("ok" / "FAIL" lines).
local s = { start = 14 }
local lines, st = {}, {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UI() return require("ui/uimanager") end
local function top() local ws = UI()._window_stack; return ws[#ws].widget end
local function Th() return require("gzreader_shelftheme") end
local touch = require("device"):isTouchDevice()
local function spot(label)
    for _i, p in ipairs(top().spots or {}) do if p.spot.label == label then return p.spot end end
end
local function choose(label, keys)
    if touch then
        return { fn = function(E)
            local sp = spot(label)
            if not sp then return check(false, "no " .. label) end
            E.tap({ sp.dimen.x + math.floor(sp.dimen.w / 2), sp.dimen.y + math.floor(sp.dimen.h / 2) })
        end, after = 8 }
    end
    -- (keys: the 5-way's moves from the first chip, then Press)
    return { fn = function(E)
        top():moveFocusTo(1, 1)
        for _i, k in ipairs(keys) do E.key(k) end
        E.key("Press")
    end, after = 10 }
end
s[#s + 1] = { fn = function()
    for i = #UI()._window_stack, 1, -1 do
        local w = UI()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UI():close(w) end
    end
end, after = 4 }
s[#s + 1] = { fn = function() require("gzreader_shelfpreview").show() end, after = 15 }
s[#s + 1] = { fn = function() check(top().name == "gzreader bookshelf theme" and Th().deferred == "held", "the theme screen is open") end }
s[#s + 1] = { shot = "theme-1" }
s[#s + 1] = choose("Walnut", { "Down", "Right" })
s[#s + 1] = { fn = function() check(Th().get() == "walnut" and spot("Walnut").on and Th().deferred == "pending", "Walnut chosen and marked; the shelves wait") end }
s[#s + 1] = choose("On every page", { "Down", "Down", "Right", "Right" })
s[#s + 1] = { fn = function() check(Th().ornaments() == "always", "On every page chosen") end }
s[#s + 1] = { shot = "theme-2-walnut-every-page" }
s[#s + 1] = choose("Which ornaments", { "Down", "Down", "Down", "Down", "Down" })
s[#s + 1] = { fn = function() check(top().name == "gzreader which ornaments", "Which ornaments opens") end }
s[#s + 1] = { shot = "theme-3-which" }
s[#s + 1] = { fn = function(E)
    local first = top().spots[1].spot
    local e = first.entry
    local was = Th().isOn(e)
    if touch then E.tap({ first.dimen.x + 20, first.dimen.y + 20 }) else top():moveFocusTo(1, 1); E.key("Press") end
    st.first, st.was = e, was
end, after = 8 }
s[#s + 1] = { fn = function()
    check(st.first and Th().isOn(st.first) == not st.was and top().shown == st.first, "a tap puts an ornament on the shelves or takes it off, and shows it")
    Th().setOn(st.first, st.was)
end }
s[#s + 1] = { shot = "theme-4-which-tapped" }
s[#s + 1] = { fn = function() UI():close(top()) end, after = 6 }
s[#s + 1] = { fn = function() UI():close(top()) end, after = 10 }
s[#s + 1] = { fn = function(E)
    check(Th().deferred == nil and top().name ~= "gzreader bookshelf theme", "closed: the shelves drawn again")
    Th().set("oak"); Th().setOrnaments("room")
    local f = io.open(E.out .. "/shelf_theme_tiles.txt", "w")
    if f then f:write(table.concat(lines, "\n"), "\n"); f:close() end
end }
return s
