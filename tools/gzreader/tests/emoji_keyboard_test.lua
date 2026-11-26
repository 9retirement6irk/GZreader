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
local function layout()
    return { { { "q" }, { "w" } }, { { label = "⌥", width = 1.5 }, { label = "🌐" }, { "." }, { label = "_", " ", width = 3.0 },
        { label = "←" }, { label = "⮠", width = 1.5 } } }
end
local keys = layout()
local with = E.withKey(keys)
local row = with and with[2]
local function labels(r) local t = {} for _i, k in ipairs(r) do t[#t + 1] = k.label or k[1] end return table.concat(t, " ") end
check(row and labels(row) == "⌥ 🌐 . ☺ _ ← ⮠" and row[5].width == 2.0 and row[5][1] == " ", "☺ before the space bar, which gives it one unit of width: " .. (row and labels(row) or "?"))
check(keys[2][4].width == 3.0 and #keys[2] == 6 and with[1] == keys[1], "…the layout itself untouched (a copy), the other rows shared")
check(E.withKey({ { { "a" } }, { { label = "_", " " } } }) == nil and E.withKey({}) == nil, "no space bar wide enough: no ☺ key")
local src = io.open(REPO .. "/plugins/gzreader.koplugin/gzreader_emojikeyboard.lua"):read("*a")
check(src:find("key.callback = function() Emoji.show(kb) end", 1, true) and src:find("if not (Device.isTouchDevice and Device:isTouchDevice()) then return false end", 1, true),
    "a tap on ☺ opens the picker; only on touch Kindles (keyboard Kindles have no on-screen keyboard)")
local main = io.open(REPO .. "/plugins/gzreader.koplugin/main.lua"):read("*a")
check(main:find('pcall(function() require("gzreader_emojikeyboard").install() end)', 1, true), "installed when GZreader starts")

print("== the picker")
local kinds = E.kinds(settings)
check(#kinds == #E.GROUPS and kinds[1].id == "smileys" and #kinds[1].list >= 80, "no Recent yet: the kinds, Smileys first")
local n = 0
for _i, g in ipairs(E.GROUPS) do n = n + #g.list end
check(n >= 500, n .. " emoji in " .. #E.GROUPS .. " kinds")
local list, page, pages = E.page(kinds[1].list, 1)
check(#list == E.COLS * E.ROWS and page == 1 and pages == math.ceil(#kinds[1].list / (E.COLS * E.ROWS)), "a page at a time (" .. E.COLS .. " × " .. E.ROWS .. ")")
local p2 = select(2, E.page(kinds[1].list, 99))
check(p2 == pages and select(2, E.page({}, 3)) == 1, "…never past the last page or the first")
-- typed, and kept as Recent (the latest first, once)
local typed = {}
local kb = { inputbox = { addChars = function(_b, s) typed[#typed + 1] = s end } }
E.type(kb, "😀"); E.type(kb, "🐶"); E.type(kb, "😀")
check(table.concat(typed) == "😀🐶😀", "a tap types the emoji into the box")
check(table.concat(E.recent(settings), ",") == "😀,🐶" and E.kinds(settings)[1].id == "recent", "…kept as Recent, the latest first, once; Recent is the picker's first kind")
for i = 1, 40 do E.used("x" .. i, settings) end
check(#E.recent(settings) == E.RECENT_MAX and E.recent(settings)[1] == "x40", "Recent keeps the latest " .. E.RECENT_MAX)
-- every emoji is text (no empty entries)
local bad = 0
for _i, g in ipairs(E.GROUPS) do for _j, e in ipairs(g.list) do if type(e) ~= "string" or e == "" then bad = bad + 1 end end end
check(bad == 0, "every entry is an emoji")

print(string.format("emoji keyboard: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
