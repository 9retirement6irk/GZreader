--[[--
The on-screen keyboard while writing a note (the note editor, its formatted
page, a quick note, a journal entry): a slim bar on top of the keyboard with
# (Memos makes a #word a tag) and the arrow keys, and a comma on the letters
page.

  [  #  ][  ←  ][  ↑  ][  ↓  ][  →  ]     the bar, on every page of the keyboard
  q  w  e  r  t  y  u  i  o  p
   a  s  d  f  g  h  j  k  l
  ⇧  z  x  c  v  b  n  m  ⌫
  ⌥  🌐  ,  .  [   space   ]  ⮠      the letters' bottom row

The arrows move up to the bar, so the bottom row has room for the comma
(ZenOS takes it off the third row) and a wider space bar. A box that wants
all this sets `gz_hash_key = true`; ZenOS's keyboard patch
(`responsive_keyboard.lua`) asks `HashKey.row` for the letters' bottom row
and `HashKey.addBar` once the keys are laid out.
]]

local HashKey = {}

HashKey.BAR = { "#", "←", "↑", "↓", "→" }
HashKey.BAR_SHARE = 0.6 -- the bar's height, as a share of a key's
HashKey.COMMA = { ",", ",", ",", ",", label = "," } -- (when KOReader's own comma key isn't to hand)

--- Whether the keyboard's input box is a note's: the box, or the window it's in.
function HashKey.wants(inputbox)
    if type(inputbox) ~= "table" then return false end
    if inputbox.gz_hash_key == true then return true end
    local parent = rawget(inputbox, "parent")
    return type(parent) == "table" and rawget(parent, "gz_hash_key") == true
end

--- The letters' bottom row for a note (a new list): ⌥, 🌐, the comma, the
--- full stop, the space bar, Enter; ← → are on the bar. `row` is KOReader's
--- (⌥, 🌐, the full stop, the space bar, ←, →, Enter); `comma`, KOReader's
--- comma key (the one ZenOS takes off the third row). nil when the row isn't
--- that one. The space bar's own width is put back by `HashKey.restore`.
function HashKey.row(row, comma)
    if type(row) ~= "table" or #row ~= 7 then return nil end
    local space = row[4]
    if type(space) ~= "table" or space[2] ~= " " then return nil end
    local saved = space.width
    -- (← and → were a key each; the comma takes one of them)
    space.width = (tonumber(saved) or 3) + 1
    return { row[1], row[2], comma or HashKey.COMMA, row[3], row[4], row[7] }, saved
end

function HashKey.restore(row, saved)
    if type(row) == "table" and type(row[4]) == "table" then row[4].width = saved end
end

--- The bar's height for a keyboard whose keys are `key_h` high, at least `min_h`.
function HashKey.barHeight(key_h, min_h)
    return math.max(min_h or 0, math.floor(key_h * HashKey.BAR_SHARE))
end

--- Puts the bar on top of `kb` (a VirtualKeyboard, its keys just laid out by
--- KOReader's addKeys). `VirtualKey` is KOReader's key class (its arrows
--- already move the cursor; # types itself). The keyboard grows by the bar;
--- its own `height` (which addKeys shares out among the rows) is left alone.
function HashKey.addBar(kb, VirtualKey)
    local bottom = kb[1]
    local frame = bottom and bottom[1]
    local center = frame and frame[1]
    local rows = center and center[1]
    if not (rows and center.dimen and VirtualKey) then return false end
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Screen = require("device").screen
    local pad = kb.key_padding or 0
    local n_rows = #(kb.KEYS or {})
    local key_h = math.floor((kb.height - (n_rows + 1) * pad - 2 * (kb.padding or 0)) / math.max(1, n_rows))
    local bar_h = HashKey.barHeight(key_h, Screen:scaleBySize(30))
    local inner_w = center.dimen.w
    local n = #HashKey.BAR
    local key_w = math.floor((inner_w - (n - 1) * pad) / n)
    local bar = HorizontalGroup:new{ allow_mirroring = false }
    local line = {}
    for i, label in ipairs(HashKey.BAR) do
        local k = VirtualKey:new{ key = label, label = label, keyboard = kb, width = key_w, height = bar_h }
        k.gz_bar = true
        bar[#bar + 1] = k
        line[#line + 1] = k
        if i < n then bar[#bar + 1] = HorizontalSpan:new{ width = pad } end
    end
    table.insert(rows, 1, VerticalSpan:new{ width = pad })
    table.insert(rows, 1, bar)
    if type(kb.layout) == "table" then table.insert(kb.layout, 1, line) end -- (the 5-way reaches it too)
    center.dimen.h = center.dimen.h + bar_h + pad
    if rows.resetLayout then rows:resetLayout() end
    frame.dimen = frame:getSize()
    kb.dimen = frame.dimen
    kb.gz_bar_h = bar_h + pad
    return true
end

return HashKey
