-- Emoji on the on-screen keyboard (plugins/gzreader.koplugin/gzreader_emojikeyboard.lua):
-- the ☺ key beside the space bar, the picker's kinds and pages, Recent, typing.
--   luajit emoji_keyboard_test.lua <repo>
local REPO = arg[1]
package.path = REPO .. "/plugins/gzreader.koplugin/?.lua;" .. package.path
local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
package.loaded["gettext"] = function(s) return s end
package.loaded["gzreader_log"] = { info = function() end, warn = function() end }
local store = {}
local settings = { readSetting = function(_s, k) return store[k] end, saveSetting = function(_s, k, v) store[k] = v end }
_G.G_reader_settings = settings
local E = require("gzreader_emojikeyboard")

print("== the ☺ key")
local SHIFT, BACK = "\u{ED35}", "\u{E76D}"
local function layout()
    return {
        { { "1" }, { "2" }, { "3" }, { "4" }, { "5" }, { "6" }, { "7" }, { "8" }, { "9" }, { "0" } },
        { { label = SHIFT, width = 1.5 }, { "Z", "z" }, { "X", { "x", alt_label = "Σ" } }, { "c" }, { "v" }, { "b" }, { "n" }, { "m" }, { label = BACK, width = 1.5 } },
        { { label = "⌥", width = 1.5 }, { label = "🌐" }, { "." }, { label = "_", " ", width = 3.0 },
            { label = "←" }, { label = "→" }, { label = "⮠", width = 1.5 } },
    }
end
local function labels(r) local t = {} for _i, k in ipairs(r) do t[#t + 1] = k.label or (type(k[2]) == "table" and k[2][1]) or k[2] or k[1] end return table.concat(t, " ") end
local function units(r) local n = 0 for _i, k in ipairs(r) do n = n + (k.width or 1) end return n end
local keys = layout()
local with = E.withKey(keys, { [SHIFT] = true })
local row = with and with[2]
check(row and labels(row):find("^" .. SHIFT .. " ☺ z x c") and row[1].width == 0.75 and row[2].width == 0.75 and units(row) == units(keys[2]),
    "☺ right after Shift, the two sharing Shift's width (0.75 each): " .. (row and labels(row) or "?"))
check(with[3] == keys[3] and keys[3][4].width == 3.0 and #keys[3] == 7, "…the space bar keeps its size: the bottom row is the layout's own (7 keys)")
check(keys[2][1].width == 1.5 and #keys[2] == 9 and with[1] == keys[1], "…the layout itself untouched (a copy), the other rows shared")
local nos = E.withKey(layout(), {})
check(nos and #nos[3] == 8 and nos[3][4].label == E.KEY and nos[3][5].width == 2.0, "no Shift known: ☺ before the space bar, which gives it a unit")
check(E.withKey({ { { "a" } }, { { label = "_", " " } } }, {}) == nil and E.withKey({}) == nil, "no Shift or space bar wide enough: no ☺ key")
local src = io.open(REPO .. "/plugins/gzreader.koplugin/gzreader_emojikeyboard.lua"):read("*a")
check(src:find("if not (Device.isTouchDevice and Device:isTouchDevice()) then return false end", 1, true), "only on touch Kindles (keyboard Kindles have no on-screen keyboard)")
local main = io.open(REPO .. "/plugins/gzreader.koplugin/main.lua"):read("*a")
check(main:find('pcall(function() require("gzreader_emojikeyboard").install() end)', 1, true), "installed when GZreader starts")
local zen = io.open(REPO .. "/plugins/zenos.koplugin/modules/global/patches/responsive_keyboard.lua"):read("*a")
check(zen:find('k[2][1] == "x" then x_at = index break end', 1, true) and zen:find("keys[4][x_at] = clean_x_key", 1, true) and not zen:find("keys[4][3] = ", 1, true),
    "ZenOS finds the x key by its letter (☺ sits before it), so its Σ is still taken off")

print("== the emoji keys")
local state = E.state({}, settings)
check(state.kind == "smileys" and state.page == 1, "no Recent yet: Smileys first")
local rows, kind, page, pages = E.layout(state, 10, 5, settings)
check(#rows == 5 and #rows[1] == 10 and #rows[3] == 10 and rows[1][1].gz.emoji == E.GROUPS[1].list[1] and rows[1][1].label == E.GROUPS[1].list[1],
    "as many rows as the letters (the keyboard keeps its height): three rows of ten emoji")
check(rows[1][1][1] == rows[1][1].label and rows[1][1][12] == rows[1][1].label, "…a key for every layer of the keyboard")
check(#rows[4] == #E.GROUPS and rows[4][1].label == "•😀" and rows[4][2].label == "👋" and math.abs(units(rows[4]) - 10) < 1e-9, "the kinds, one key each, the one shown marked: " .. labels(rows[4]))
check(labels(rows[5]) == "ABC ◀ ▶ Smileys 1/" .. pages .. " " .. BACK .. " ⮠" and math.abs(units(rows[5]) - 10) < 1e-9 and rows[5][4].width == 3,
    "then ABC, ◀ ▶, the space bar (the kind and page on it), ⌫, ⮠: " .. labels(rows[5]))
check(#rows[5] ~= 7 and not (#rows[4] == 9 and #rows[5] == 7), "…not the standard layout's shape (ZenOS's symbol pages leave it alone)")
check(kind.id == "smileys" and page == 1 and pages == math.ceil(#E.GROUPS[1].list / 30), "a page is 30")
state.per = 30
E.turn(state, 1, settings); check(state.kind == "smileys" and state.page == 2, "▶: the next page")
state.page = pages; E.turn(state, 1, settings); check(state.kind == "people" and state.page == 1, "▶ on the last page: on to the next kind")
E.turn(state, -1, settings); check(state.kind == "smileys" and state.page == pages, "◀ on the first page: the kind before's last page")
state.kind, state.page = "smileys", 1
E.turn(state, -1, settings); check(state.kind == "symbols", "…round from the first kind to the last")
-- typed, and kept as Recent (the latest first, once)
local typed, redrawn, added, deleted = {}, 0, {}, 0
local kb = { inputbox = { addChars = function(_b, s) typed[#typed + 1] = s end },
    addKeys = function() redrawn = redrawn + 1 end, _refresh = function() end,
    addChar = function(_k, c) added[#added + 1] = c end, delChar = function() deleted = deleted + 1 end }
E.open(kb)
check(kb.gz_emoji_on and redrawn == 1 and kb.gz_emoji.kind == "smileys", "☺: the keyboard laid out again as emoji")
E.press(kb, { emoji = "😀" }); E.press(kb, { emoji = "🐶" }); E.press(kb, { emoji = "😀" })
check(table.concat(typed) == "😀🐶😀" and redrawn == 1, "a tap types the emoji (the emoji stay up; nothing laid out again)")
check(table.concat(E.recent(settings), ",") == "😀,🐶" and E.kinds(settings)[1].id == "recent", "…kept as Recent, the latest first, once; Recent is the first kind")
check(E.state({}, settings).kind == "recent", "…and the one shown first next time")
E.press(kb, { kind = "food" }); check(kb.gz_emoji.kind == "food" and kb.gz_emoji.page == 1 and redrawn == 2, "a kind's key: its first page")
E.press(kb, { space = true }); E.press(kb, { enter = true })
check(table.concat(added, "|") == " |\n", "space and Enter type as on the letters")
E.press(kb, { abc = true }); check(kb.gz_emoji_on == false and redrawn == 3 and kb.gz_emoji.kind == "food", "ABC: back to the letters (the kind kept for next time)")
for i = 1, 40 do E.used("x" .. i, settings) end
check(#E.recent(settings) == E.RECENT_MAX and E.recent(settings)[1] == "x40", "Recent keeps the latest " .. E.RECENT_MAX)
-- every emoji is text (no empty entries)
local bad = 0
for _i, g in ipairs(E.GROUPS) do for _j, e in ipairs(g.list) do if type(e) ~= "string" or e == "" then bad = bad + 1 end end end
check(bad == 0, "every entry is an emoji")
for _i, g in ipairs(E.GROUPS) do bad = bad + (E.ICONS[g.id] and 0 or 1) end
check(bad == 0 and E.ICONS.recent, "every kind has its key")

print("== on KOReader's keyboard")
local VK = { keyboard_layer = 2, shiftmode_keys = { [SHIFT] = true } }
VK.__index = VK
local seen
function VK:addKeys()
    seen = { keys = self.KEYS, layer = self.keyboard_layer }
    self.layout = {}
    for r, rr in ipairs(self.KEYS) do
        self.layout[r] = {}
        for c, k in ipairs(rr) do
            self.layout[r][c] = { label = k.label or k[self.keyboard_layer] or k[1], hold_callback = function() end, callback = function() end }
        end
    end
end
package.loaded["ui/widget/virtualkeyboard"] = VK
package.loaded["device"] = { isTouchDevice = function() return true end }
check(E.install() and not E.install(), "installed once")
local vk = setmetatable({ KEYS = layout(), inputbox = kb.inputbox, addChar = kb.addChar, delChar = kb.delChar, _refresh = function() end }, VK)
local orig_keys = vk.KEYS
vk:addKeys()
check(#seen.keys[2] == 10 and seen.keys[2][2].label == E.KEY and vk.KEYS == orig_keys, "the letters: laid out with ☺ after Shift; the keyboard's own keys put back")
local fn = vk.layout[2][2].callback
fn()
check(vk.gz_emoji_on and #seen.keys == 3 and seen.layer == 3 and seen.keys[#seen.keys][1].label == "ABC" and vk.keyboard_layer == 2,
    "a tap on ☺: the emoji keys laid out (as the symbols' page is), the letters' layer kept")
check(vk.layout[1][1].hold_callback == nil, "…an emoji key has no hold popup")
local n0 = #typed
vk.layout[1][1].callback()
check(#typed == n0 + 1, "…a tap on one types it")
local last = vk.layout[#vk.layout]
check(last[5].callback and last[5].hold_callback, "…⌫ is KOReader's own (hold: to the start of the line)")
last[1].callback()
check(not vk.gz_emoji_on and seen.keys[2][2].label == E.KEY, "ABC: the letters again, ☺ beside Shift")
vk.keyboard_layer = 4; vk:addKeys()
check(seen.keys == orig_keys, "the symbols' pages: the keyboard's own keys (ZenOS's)")

print(string.format("emoji keyboard: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
