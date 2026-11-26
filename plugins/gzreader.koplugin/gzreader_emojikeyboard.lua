--[[--
Emoji on the on-screen keyboard. A ☺ key sits beside Shift (the two share
Shift's old width, so the space bar keeps its size). A tap on ☺ turns the
keyboard itself into emoji, as Shift turns it to capitals:

  😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃      three rows of emoji (a page of a kind)
  😉 😊 😇 🥰 😍 🤩 😘 😗 😚 😙
  😋 😛 😜 🤪 😝 🤑 🤗 🤭 🤫 🤔
  🕘 •😀 👋 🐶 🍎 🚗 ⚽ 💡 ❤      the kinds (Recent when there are any)
  ABC  ◀  ▶  [ Smileys 1/3 ]  ⌫  ⮠

A tap types an emoji and the emoji stay up for more; ◀ ▶ turn the page (on
into the next kind at the end); ABC goes back to the letters. The ones used
are kept as Recent (`RECENT_MAX`, the latest first). The editor's Done
closes the keyboard as always.

Emoji show in OpenMoji's black font everywhere and in colour on a colour
Kindle (frontend/gzcoloremoji.lua), as in notes. Kindles with a keyboard
have no on-screen keyboard: their Sym key's symbols are as before.

How: GZreader wraps KOReader's VirtualKeyboard.addKeys. On the letters it
lays out a copy of the keys with ☺ after Shift (`withKey`); in emoji mode
(`kb.gz_emoji`) the keys are `Emoji.layout`'s, laid out as the symbols'
page is (layer 3) so ZenOS's letter-page changes leave them alone.
]]

local Log = require("gzreader_log")
local _ = require("gettext")

local Emoji = {
    KEY = "☺",
    SETTING_RECENT = "gzreader_emoji_recent",
    RECENT_MAX = 30,
    ABC = "ABC",
    BACKSPACE = "", -- KOReader's ⌫ (its own key: hold for the start of the line)
    -- each kind's key on the kinds row
    ICONS = { recent = "🕘", smileys = "😀", people = "👋", nature = "🐶", food = "🍎",
        travel = "🚗", activities = "⚽", objects = "💡", symbols = "❤" },
}

--- The emoji, by kind: { { id, name, list } }. Single codepoints and the
--- usual sequences OpenMoji draws.
Emoji.GROUPS = {
    { id = "smileys", name = _("Smileys"), list = {
        "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "🙃", "😉", "😊", "😇", "🥰", "😍", "🤩", "😘", "😗", "😚", "😙",
        "😋", "😛", "😜", "🤪", "😝", "🤑", "🤗", "🤭", "🤫", "🤔", "🤐", "🤨", "😐", "😑", "😶", "😏", "😒", "🙄", "😬", "😌",
        "😔", "😪", "🤤", "😴", "😷", "🤒", "🤕", "🤢", "🤮", "🤧", "🥵", "🥶", "🥴", "😵", "🤯", "🤠", "🥳", "😎", "🤓", "🧐",
        "😕", "😟", "🙁", "😮", "😯", "😲", "😳", "🥺", "😦", "😧", "😨", "😰", "😥", "😢", "😭", "😱", "😖", "😣", "😞", "😓",
        "😩", "😫", "🥱", "😤", "😡", "😠", "🤬", "😈", "👿", "💀", "💩", "🤡", "👻", "👽", "🤖", "😺", "😸", "😹", "😻", "😿",
    } },
    { id = "people", name = _("People"), list = {
        "👋", "🤚", "✋", "🖖", "👌", "🤏", "✌️", "🤞", "🤟", "🤘", "🤙", "👈", "👉", "👆", "👇", "☝️", "👍", "👎", "✊", "👊",
        "👏", "🙌", "👐", "🤲", "🤝", "🙏", "✍️", "💪", "🧠", "👀", "👁️", "👂", "👃", "👄", "👶", "🧒", "👦", "👧", "🧑", "👩",
        "👨", "🧓", "👴", "👵", "🙋", "🙇", "🤷", "🤦", "💁", "🙆", "🙅", "🧑‍🎓", "🧑‍🏫", "🧑‍💻", "🧑‍🍳", "🧑‍🔬", "🧑‍🎨", "👮", "🕵️", "💂",
        "👷", "🤴", "👸", "🦸", "🦹", "🧙", "🧚", "🧛", "🧜", "🧝", "🏃", "🚶", "💃", "🕺", "👪", "💑", "💏", "❤️‍🔥", "🫶", "🫡",
    } },
    { id = "nature", name = _("Animals and nature"), list = {
        "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🐤", "🦆",
        "🦅", "🦉", "🦇", "🐺", "🐗", "🐴", "🦄", "🐝", "🐛", "🦋", "🐌", "🐞", "🐜", "🕷️", "🐢", "🐍", "🦎", "🐙", "🦑", "🦀",
        "🐠", "🐟", "🐬", "🐳", "🐋", "🦈", "🐊", "🐅", "🐆", "🦓", "🦍", "🐘", "🦒", "🐪", "🐄", "🐑", "🐐", "🦌", "🐕", "🐈",
        "🌵", "🎄", "🌲", "🌳", "🌴", "🌱", "🌿", "☘️", "🍀", "🍁", "🍂", "🍃", "🌷", "🌹", "🌺", "🌸", "🌼", "🌻", "🌞", "🌝",
        "🌛", "🌜", "🌚", "🌕", "🌙", "⭐", "🌟", "✨", "⚡", "🔥", "🌈", "☀️", "⛅", "☁️", "🌧️", "⛈️", "❄️", "☃️", "💧", "🌊",
    } },
    { id = "food", name = _("Food"), list = {
        "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🍆", "🥑",
        "🥦", "🥬", "🥒", "🌶️", "🌽", "🥕", "🧄", "🧅", "🥔", "🍠", "🥐", "🍞", "🥖", "🥨", "🧀", "🥚", "🍳", "🥞", "🧇", "🥓",
        "🍗", "🍖", "🌭", "🍔", "🍟", "🍕", "🥪", "🌮", "🌯", "🥗", "🍝", "🍜", "🍲", "🍛", "🍣", "🍱", "🥟", "🍤", "🍙", "🍚",
        "🍰", "🎂", "🧁", "🥧", "🍫", "🍬", "🍭", "🍮", "🍯", "🍩", "🍪", "☕", "🍵", "🧃", "🥤", "🍺", "🍷", "🥂", "🍸", "🍹",
    } },
    { id = "travel", name = _("Travel and places"), list = {
        "🚗", "🚕", "🚙", "🚌", "🚎", "🏎️", "🚓", "🚑", "🚒", "🚐", "🚚", "🚜", "🚲", "🛴", "🏍️", "🚨", "🚔", "🚖", "🚡", "🚟",
        "🚃", "🚋", "🚝", "🚄", "🚅", "🚈", "🚂", "🚆", "🚇", "✈️", "🛫", "🛬", "🚀", "🛸", "🚁", "⛵", "🚤", "🛳️", "⚓", "⛽",
        "🗺️", "🗽", "🗼", "🏰", "🏯", "🏟️", "🎡", "🎢", "🎠", "⛲", "🏖️", "🏝️", "🏜️", "🌋", "⛰️", "🏔️", "🗻", "🏕️", "🏠", "🏡",
        "🏢", "🏬", "🏣", "🏥", "🏦", "🏨", "🏪", "🏫", "🏛️", "⛪", "🕌", "🕍", "🌁", "🌃", "🏙️", "🌄", "🌅", "🌆", "🌇", "🌉",
    } },
    { id = "activities", name = _("Activities"), list = {
        "⚽", "🏀", "🏈", "⚾", "🥎", "🎾", "🏐", "🏉", "🎱", "🏓", "🏸", "🥅", "🏒", "🏑", "🏏", "⛳", "🏹", "🎣", "🥊", "🥋",
        "⛸️", "🎿", "🛷", "🏂", "🏋️", "🤸", "🤺", "🏊", "🚴", "🧗", "🏆", "🥇", "🥈", "🥉", "🏅", "🎖️", "🎗️", "🎫", "🎟️", "🎪",
        "🎭", "🎨", "🎬", "🎤", "🎧", "🎼", "🎹", "🥁", "🎷", "🎺", "🎸", "🎻", "🎲", "♟️", "🎯", "🎳", "🎮", "🧩", "🎉", "🎊",
    } },
    { id = "objects", name = _("Objects"), list = {
        "⌚", "📱", "💻", "⌨️", "🖥️", "🖨️", "🖱️", "💾", "💿", "📷", "📹", "🎥", "📺", "📻", "⏰", "⏳", "🔋", "🔌", "💡", "🔦",
        "🕯️", "💸", "💵", "💳", "💎", "⚖️", "🔧", "🔨", "🛠️", "⚙️", "🔩", "🧲", "🔫", "💣", "🔪", "🛡️", "🔮", "💊", "💉", "🧬",
        "🔬", "🔭", "🧹", "🧺", "🧻", "🧼", "🛁", "🔑", "🗝️", "🚪", "🛋️", "🛏️", "🧸", "🎁", "🎈", "✉️", "📩", "📦", "📫", "📮",
        "📜", "📄", "📑", "📊", "📈", "📉", "📅", "📆", "📇", "📋", "📁", "📂", "📰", "📓", "📔", "📒", "📕", "📗", "📘", "📙",
        "📚", "📖", "🔖", "🔗", "📎", "📐", "📏", "📌", "📍", "✂️", "🖊️", "🖋️", "✒️", "🖌️", "🖍️", "📝", "✏️", "🔍", "🔒", "🔓",
    } },
    { id = "symbols", name = _("Symbols"), list = {
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "☮️",
        "✝️", "☪️", "🕉️", "☸️", "✡️", "☯️", "♈", "♉", "♊", "♋", "♌", "♍", "♎", "♏", "♐", "♑", "♒", "♓", "⛎", "🔀",
        "✅", "☑️", "✔️", "❌", "❎", "➕", "➖", "➗", "✖️", "♾️", "‼️", "⁉️", "❓", "❔", "❕", "❗", "〰️", "💱", "💲", "⚠️",
        "🚫", "⛔", "📛", "🔞", "💯", "🔅", "🔆", "🔱", "⚜️", "🔰", "♻️", "🆗", "🆕", "🆒", "🆓", "🆙", "🔝", "🔜", "🔙", "🔚",
        "➡️", "⬅️", "⬆️", "⬇️", "↗️", "↘️", "↙️", "↖️", "↕️", "↔️", "🔄", "🎵", "🎶", "💤", "💬", "💭", "🗯️", "♠️", "♥️", "♦️",
    } },
}

--- The used ones, the latest first (at most RECENT_MAX).
function Emoji.recent(settings)
    settings = settings or G_reader_settings
    local list = settings:readSetting(Emoji.SETTING_RECENT)
    return type(list) == "table" and list or {}
end

--- `e` put first in Recent (once). Returns the list.
function Emoji.used(e, settings)
    settings = settings or G_reader_settings
    local out = { e }
    for _i, x in ipairs(Emoji.recent(settings)) do
        if x ~= e and #out < Emoji.RECENT_MAX then out[#out + 1] = x end
    end
    settings:saveSetting(Emoji.SETTING_RECENT, out)
    return out
end

--- The picker's kinds: Recent first when there are any, then GROUPS.
function Emoji.kinds(settings)
    local out = {}
    local rec = Emoji.recent(settings)
    if #rec > 0 then out[1] = { id = "recent", name = _("Recent"), list = rec } end
    for _i, g in ipairs(Emoji.GROUPS) do out[#out + 1] = g end
    return out
end

--- Page `page` of `list` (`per` at a time) and how many pages. Pure.
function Emoji.page(list, page, per)
    per = math.max(1, tonumber(per) or 30)
    local pages = math.max(1, math.ceil(#list / per))
    page = math.max(1, math.min(pages, page or 1))
    local out = {}
    for i = (page - 1) * per + 1, math.min(#list, page * per) do out[#out + 1] = list[i] end
    return out, page, pages
end

--- A key for every layer of the keyboard (KOReader reads key[layer]).
local function key(label, value, width, extra)
    local k = { label = label, width = width }
    for l = 1, 12 do k[l] = value end
    for n, v in pairs(extra or {}) do k[n] = v end
    return k
end

local function copyRow(row)
    local out = {}
    for c, k in ipairs(row) do out[c] = k end
    return out
end

--- `keys` (a layout's KEYS) with the ☺ key: after Shift (a label in
--- `shift_labels`), the two sharing Shift's width, when Shift is wide enough;
--- otherwise before the last row's space bar, which gives it one unit. A copy
--- (only the changed row is new); nil when there's no room. Pure.
function Emoji.withKey(keys, shift_labels)
    if type(keys) ~= "table" or #keys == 0 then return nil end
    local function copyWith(r, row)
        local copy = {}
        for i, rr in ipairs(keys) do copy[i] = rr end
        copy[r] = row
        return copy
    end
    for r, row in ipairs(keys) do
        for j, k in ipairs(type(row) == "table" and row or {}) do
            local w = type(k) == "table" and (tonumber(k.width) or 1) or 0
            if type(k) == "table" and shift_labels and k.label and shift_labels[k.label] and w >= 1.4 then
                local out = copyRow(row)
                local shift = {}
                for n, v in pairs(k) do shift[n] = v end
                shift.width = w / 2
                out[j] = shift
                table.insert(out, j + 1, { label = Emoji.KEY, width = w / 2, gz_emoji_key = true })
                return copyWith(r, out)
            end
        end
    end
    local last = keys[#keys]
    for j, k in ipairs(type(last) == "table" and last or {}) do
        if type(k) == "table" and k.label == "_" and (tonumber(k.width) or 1) >= 2 then
            local out = copyRow(last)
            local space = {}
            for n, v in pairs(k) do space[n] = v end
            space.width = (tonumber(k.width) or 1) - 1
            out[j] = space
            table.insert(out, j, { label = Emoji.KEY, gz_emoji_key = true })
            return copyWith(#keys, out)
        end
    end
    return nil
end

--- Where the emoji keyboard is: the kind shown (its id) and the page.
function Emoji.state(kb, settings)
    if type(kb.gz_emoji) ~= "table" then
        kb.gz_emoji = { kind = #Emoji.recent(settings) > 0 and "recent" or "smileys", page = 1 }
    end
    return kb.gz_emoji
end

--- The emoji keyboard's keys: `nrows` rows (as the letters have, so the
--- keyboard keeps its height) of `cols` units: emoji, the kinds, then ABC,
--- ◀, ▶, the space bar (the kind and page on it), ⌫, ⮠. Each key's `gz`
--- says what it does. Pure (but for Recent, read from `settings`).
function Emoji.layout(state, cols, nrows, settings)
    cols, nrows = math.max(6, cols or 10), math.max(3, nrows or 5)
    local kinds = Emoji.kinds(settings)
    local ki = 1
    for i, k in ipairs(kinds) do if k.id == state.kind then ki = i end end
    local kind = kinds[ki]
    state.kind = kind.id
    local grid = nrows - 2
    local list, page, pages = Emoji.page(kind.list, state.page, grid * cols)
    state.page = page
    local rows = {}
    for r = 1, grid do
        local row = {}
        for c = 1, cols do
            local e = list[(r - 1) * cols + c]
            row[c] = e and key(e, e, 1, { gz = { emoji = e } }) or key(" ", "", 1, { gz = { blank = true } })
        end
        rows[r] = row
    end
    local tabs = {}
    for i, k in ipairs(kinds) do
        local icon = Emoji.ICONS[k.id] or k.name
        tabs[i] = key((i == ki and "•" or "") .. icon, "", cols / #kinds, { gz = { kind = k.id } })
    end
    rows[grid + 1] = tabs
    local u = cols / 10
    rows[grid + 2] = {
        key(Emoji.ABC, "", 1.5 * u, { gz = { abc = true }, bold = true }),
        key("◀", "", 1 * u, { gz = { turn = -1 } }),
        key("▶", "", 1 * u, { gz = { turn = 1 } }),
        key(string.format("%s %d/%d", kind.name, page, pages), " ", 3 * u, { gz = { space = true } }),
        key(Emoji.BACKSPACE, "", 1.5 * u, { gz = { back = true } }),
        key("⮠", "\n", 2 * u, { gz = { enter = true } }),
    }
    return rows, kind, page, pages
end

--- A page turned: `step` (-1, 1) from `state`, on into the kind before or
--- after at either end. Pure (but for Recent, read from `settings`).
function Emoji.turn(state, step, settings)
    local kinds = Emoji.kinds(settings)
    local ki = 1
    for i, k in ipairs(kinds) do if k.id == state.kind then ki = i end end
    local _, page, pages = Emoji.page(kinds[ki].list, state.page, state.per or 30)
    if step > 0 and page < pages then state.page = page + 1
    elseif step < 0 and page > 1 then state.page = page - 1
    elseif step > 0 then state.kind, state.page = kinds[ki % #kinds + 1].id, 1
    else
        local prev = kinds[(ki - 2) % #kinds + 1]
        state.kind = prev.id
        state.page = select(3, Emoji.page(prev.list, 1, state.per or 30))
    end
    return state
end

--- `e` typed into keyboard `kb`'s box (and kept as Recent).
function Emoji.type(kb, e)
    local box = kb and kb.inputbox
    if box and box.addChars then box:addChars(e) end
    pcall(Emoji.used, e)
end

--- The keyboard laid out again (emoji or letters) and redrawn.
function Emoji.redraw(kb)
    kb:addKeys()
    if kb._refresh then kb:_refresh(false) end
end

--- What a key of the emoji keyboard does, from its `gz`.
function Emoji.press(kb, gz)
    local state = Emoji.state(kb)
    if gz.emoji then Emoji.type(kb, gz.emoji)
    elseif gz.kind then state.kind, state.page = gz.kind, 1; Emoji.redraw(kb)
    elseif gz.turn then Emoji.turn(state, gz.turn); Emoji.redraw(kb)
    elseif gz.abc then kb.gz_emoji_on = false; Emoji.redraw(kb); Log.info("keyboard: back to the letters")
    elseif gz.space then kb:addChar(" ")
    elseif gz.enter then kb:addChar("\n")
    elseif gz.back then kb:delChar()
    end
end

--- The emoji keyboard shown on `kb` (from the ☺ key).
function Emoji.open(kb)
    kb.gz_emoji_on = true
    Emoji.state(kb)
    Emoji.redraw(kb)
    Log.info("keyboard: the emoji keys shown")
end

local function plain(k)
    k.hold_callback, k.swipe_callback, k.key_chars = nil, nil, nil
end

function Emoji.install()
    local ok, VirtualKeyboard = pcall(require, "ui/widget/virtualkeyboard")
    if not ok or VirtualKeyboard._gz_emoji then return false end
    local Device = require("device")
    if not (Device.isTouchDevice and Device:isTouchDevice()) then return false end
    VirtualKeyboard._gz_emoji = true
    local orig = VirtualKeyboard.addKeys
    function VirtualKeyboard:addKeys(...)
        local keys, layer = self.KEYS, self.keyboard_layer
        local kb = self
        local emoji, with
        if self.gz_emoji_on and type(keys) == "table" and type(keys[1]) == "table" then
            local state = Emoji.state(self)
            state.per = (#keys - 2) * #keys[1]
            emoji = Emoji.layout(state, #keys[1], #keys)
            self.KEYS, self.keyboard_layer = emoji, 3
        elseif (tonumber(layer) or 1) <= 2 then
            -- the letters only: the symbols' pages are ZenOS's own (responsive_keyboard.lua)
            with = Emoji.withKey(keys, self.shiftmode_keys)
            if with then self.KEYS = with end
        end
        local res = { pcall(orig, self, ...) }
        self.KEYS, self.keyboard_layer = keys, layer
        if not res[1] then error(res[2]) end
        local shown = emoji or with
        for r, row in ipairs(self.layout or {}) do
            for c, vkey in ipairs(row) do
                local def = shown and shown[r] and shown[r][c]
                if emoji and type(def) == "table" and def.gz then
                    local gz = def.gz
                    -- (⌫ stays KOReader's own: hold for the start of the line)
                    if gz.blank then
                        vkey.callback = function() end; plain(vkey)
                    elseif not gz.back then
                        vkey.callback = function() Emoji.press(kb, gz) end; plain(vkey)
                    end
                elseif vkey.label == Emoji.KEY then
                    vkey.callback = function() Emoji.open(kb) end; plain(vkey)
                end
            end
        end
        return unpack(res, 2)
    end
    return true
end

return Emoji
