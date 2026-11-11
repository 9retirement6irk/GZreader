-- The symbols popup on the Kindles with a keyboard (frontend/gzsymbols.lua)
-- and the lone Sym press in a text box that opens it
-- (frontend/ui/widget/inputtext.lua, InputText:onKeyPress).
--   luajit symbols_test.lua <repo>
local REPO = arg[1]
local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

local function magic()
    local m
    m = setmetatable({}, { __index = function() return function() return m end end, __call = function() return m end })
    return m
end

-- KOReader's widgets, stood in for: enough to build the popup and follow
-- what it shows, closes and types.
local ui = { shown = {}, closed = {}, dirty = 0 }
local function class()
    local C = {}
    C.__index = C
    function C:extend(o) o = o or {}; o.__index = o; return setmetatable(o, self) end
    function C:new(o) o = o or {}; setmetatable(o, self); if o.init then o:init() end; return o end
    return C
end
local Widget = class()
function Widget:getSize() return { w = self.w or 10, h = self.h or 10 } end
local Button = Widget:extend{ w = 40, h = 30 }
function Button:handleEvent(ev) self.focused = (ev.name == "Focus") end
local Group = Widget:extend{}
function Group:getSize()
    local w, h = 0, 0
    for _i, c in ipairs(self) do
        local s = c:getSize()
        if self.vertical then w = math.max(w, s.w); h = h + s.h else w = w + s.w; h = math.max(h, s.h) end
    end
    return { w = w, h = h }
end
local VGroup = Group:extend{ vertical = true }
local Frame = Widget:extend{}
function Frame:getSize() local s = self[1]:getSize(); return { w = s.w + 20, h = s.h + 20 } end
local FocusManager = Widget:extend{}
FocusManager.FOCUS_ONLY_ON_NT = 0
function FocusManager:new(o)
    o = o or {}; setmetatable(o, self)
    o.key_events = {}
    o.selected = { x = 1, y = 1 }
    if o.init then o:init() end
    return o
end
function FocusManager:moveFocusTo(x, y)
    for _y, row in ipairs(self.layout) do for _x, b in ipairs(row) do b.focused = false end end
    self.selected = { x = x, y = y }
    self.layout[y][x].focused = true
end
function FocusManager:onKeyPress(key)
    local d = ({ Up = { 0, -1 }, Down = { 0, 1 }, Left = { -1, 0 }, Right = { 1, 0 } })[key.key]
    if d then
        local x, y = self.selected.x + d[1], self.selected.y + d[2]
        if self.layout[y] and self.layout[y][x] then self:moveFocusTo(x, y) end
        return true
    end
    if key.key == "Press" then
        self.layout[self.selected.y][self.selected.x].callback()
        return true
    end
end
local screen = { getWidth = function() return 600 end, getHeight = function() return 800 end,
    scaleBySize = function(_s, px) return px end }
local stubs = {
    ["ui/uimanager"] = {
        show = function(_s, w) ui.shown[#ui.shown + 1] = w; if w.onShow then w:onShow() end end,
        close = function(_s, w) ui.closed[#ui.closed + 1] = w; if w.onCloseWidget then w:onCloseWidget() end end,
        setDirty = function() ui.dirty = ui.dirty + 1 end,
    },
    ["ui/widget/button"] = Button,
    ["ui/widget/focusmanager"] = FocusManager,
    ["ui/widget/container/framecontainer"] = Frame,
    ["ui/widget/container/centercontainer"] = Widget:extend{},
    ["ui/widget/horizontalgroup"] = Group,
    ["ui/widget/verticalgroup"] = VGroup,
    ["ui/widget/verticalspan"] = Widget:extend{ h = 4 },
    ["ui/widget/textwidget"] = Widget:extend{ w = 300, h = 20 },
    ["ui/geometry"] = { new = function(_s, o) return o end },
    ["ui/size"] = magic(),
    ["ui/font"] = magic(),
    ["ffi/blitbuffer"] = magic(),
    ["gettext"] = function(s) return s end,
    ["device"] = { screen = screen },
}
for n, v in pairs(stubs) do package.preload[n] = function() return v end end
package.path = REPO .. "/frontend/?.lua;" .. package.path
-- (ui/size's numbers: magic() would give tables; the module adds them up)
stubs["ui/size"] = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return 2 end }) end })
package.preload["ui/size"] = function() return stubs["ui/size"] end
local S = require("gzsymbols")

local function device(keyboard, sym)
    return { hasKeyboard = function() return keyboard end, hasSymKey = function() return sym end }
end
local function key(name, mods)
    local k = { key = name, modifiers = mods or {} }
    k[name] = true
    for m, on in pairs(k.modifiers) do if on then k[m] = true end end
    return k
end

print("the symbols: the Kindle 3's own, 4 rows of 12")
check(#S.ROWS == 4, "4 rows")
local all, seen, dup = 0, {}, false
for _y, row in ipairs(S.ROWS) do
    all = all + #row
    for _x, c in ipairs(row) do if seen[c] then dup = true end; seen[c] = true end
end
check(all == 48 and not dup, "48 symbols, none twice")
for _i, c in ipairs({ "@", "#", "$", "%", "&", "*", "(", ")", "\\", "|", "€", "£", "¿", "0", "9", "=", "\"" }) do
    check(seen[c], "has " .. c)
end
check(S.ROWS[1][1] == ":" and S.ROWS[2][2] == "," and S.ROWS[4][12] == "=", "in the Kindle's order")

print("which Kindles get it")
check(S.wanted(device(true, true)) == true, "a Kindle with a keyboard (Kindle 2, 3, DX): yes")
check(S.wanted(device(false, false)) == false, "the Kindle 4 (ScreenKB, no keyboard): no")
check(S.wanted(device(false, true)) == false, "a Sym key without a keyboard: no")
check(S.wanted(nil) == false, "no device: no")

print("where it goes")
check(S.placeY(800, 300, { y = 600, h = 40 }, 6) == 294, "a text box low on the screen: just above it")
check(S.placeY(800, 300, { y = 100, h = 40 }, 6) == 146, "a text box high on the screen: just below it")
check(S.placeY(800, 300, { y = 420, h = 40 }, 6) == 114, "below the middle: above it")
check(S.placeY(800, 300, { y = 200, h = 500 }, 6) == 6, "no room above or below: at the top")
check(S.placeY(800, 300, { y = 380, h = 40 }, 6) == 426, "above the middle with room below: below it")
check(S.placeY(800, 300, nil) == 250, "text box not drawn yet: in the middle")

print("keys while it's open")
check(S.keyAction(key("SymPress")) == "close", "Sym closes")
check(S.keyAction(key("Back")) == "close", "Back closes")
check(S.keyAction(key("A")) == "type", "a letter: typed, the popup stays")
check(S.keyAction(key("G", { Sym = true })) == "type", "Sym + a letter: typed, the popup stays")
check(S.keyAction(key("Del")) == "type", "Del: deletes, the popup stays")
check(S.keyAction(key("Up")) == nil and S.keyAction(key("Press")) == nil, "the 5-way is the popup's own")

print("the popup")
local typed, forwarded = {}, {}
local input = { dimen = { x = 20, y = 600, w = 560, h = 40 },
    addChars = function(_s, c) typed[#typed + 1] = c end,
    onKeyPress = function(_s, k) forwarded[#forwarded + 1] = k.key; return true end }
local p = S.show(input)
check(ui.shown[1] == p and ui.dirty >= 1, "shown, and its area refreshed")
check(#p.layout == 4 and #p.layout[1] == 12, "a 4 × 12 grid the 5-way moves through")
check(p.layout[1][1].focused and p.layout[1][1].text == ":", "the first symbol has the focus")
check(p.dimen.y + p.dimen.h <= input.dimen.y, "above the text box (low on the screen)")
check(p.dimen.x >= 0 and p.dimen.x + p.dimen.w <= 600, "inside the screen")
p:onKeyPress(key("Down")); p:onKeyPress(key("Right"))
check(p.layout[2][2].focused, "Down, Right: on the comma")
p:onKeyPress(key("Press"))
check(typed[1] == "," and #ui.closed == 0, "Press: the comma typed, the popup stays up")
p:onKeyPress(key("Right")); p:onKeyPress(key("Press")); p:onKeyPress(key("Press"))
check(table.concat(typed) == ",.." and #ui.closed == 0 and p.layout[2][3].focused,
    "more symbols in a row (Right, Press, Press: two dots), still up, focus kept")
check(p:onKeyPress(key("H")) and forwarded[1] == "H" and #ui.closed == 0, "a letter goes to the text box, still up")
check(p:onKeyPress(key("Home")) == true and #ui.closed == 0, "other keys are kept while it's open")
check(p:onKeyPress(key("SymPress")) and ui.closed[1] == p and #typed == 3, "Sym closes it, nothing more typed")
local p2 = S.show(input)
check(p2.layout[2][3].focused, "opens again where it was left")
check(p2:onKeyPress(key("Back")) and ui.closed[2] == p2 and #typed == 3, "Back closes it too, nothing typed")
S.last = { x = 99, y = 99 }
local p6 = S.show({ addChars = function() end })
check(p6.layout[1][1].focused, "a remembered place that doesn't exist: the first symbol")
check(p6.dimen.y == math.floor((800 - p6.dimen.h) / 2), "a text box not drawn yet: in the middle")

print("a lone Sym in a text box (InputText:onKeyPress)")
local src = io.open(REPO .. "/frontend/ui/widget/inputtext.lua"):read("*a")
local fn = src:match("\n(function InputText:onKeyPress%(key%).-\nend)\n")
check(fn ~= nil, "InputText:onKeyPress found")
local function try(dev, opts)
    local popups, toggles = 0, 0
    local env = setmetatable({
        InputText = {},
        Device = dev,
        require = function(n)
            if n == "gzsymbols" then
                return { wanted = S.wanted, show = function() popups = popups + 1 end }
            end
            return require(n)
        end,
    }, { __index = _G })
    assert(load(fn, "onKeyPress", "t", env))()
    local box = setmetatable({ focused = true, keyboard = opts.keyboard ~= false and {} or nil,
        isKeyboardVisible = function() return opts.visible or false end,
        toggleKeyboard = function() toggles = toggles + 1 end }, { __index = env.InputText })
    local handled = box:onKeyPress(key(opts.key or "SymPress"))
    return popups, toggles, handled
end
local k3 = device(true, true)
k3.hasScreenKB = function() return false end
local k4 = device(false, false)
k4.hasScreenKB = function() return true end
local a, b, h = try(k3, {})
check(a == 1 and b == 0 and h == true, "Kindle 3: the symbols popup, not the whole keyboard")
a, b = try(k3, { visible = true })
check(a == 0 and b == 1, "Kindle 3 with the whole keyboard showing: Sym hides it, as before")
local a3, _, h3 = try(k3, { keyboard = false })
check(a3 == 0 and h3 == false, "a read-only text box: nothing (the key goes on)")
a, b = try(k4, { key = "ScreenKBPress" })
check(a == 0 and b == 1, "Kindle 4: its keyboard key still shows the whole keyboard")
check(src:find("GZreader: on the Kindles with a keyboard, a lone Sym", 1, true) ~= nil, "the change is marked as GZreader's")

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
