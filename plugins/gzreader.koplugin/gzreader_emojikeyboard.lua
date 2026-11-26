--[[--
Emoji on the on-screen keyboard: a ☺ key on the bottom row, beside the
space bar (which gives up a little of its width), opens the emoji picker:
the emoji by kind (Recent first, then Smileys, People, Animals and nature,
Food, Travel and places, Activities, Objects, Symbols), a page at a time.
A tap types one into the box and the picker stays up for more; Done (or
Back) closes it. The ones used are kept as Recent (`RECENT_MAX`, the
latest first).

Emoji show in OpenMoji's black font everywhere and in colour on a colour
Kindle (frontend/gzcoloremoji.lua), as in notes. Kindles with a keyboard
have no on-screen keyboard: their Sym key's symbols are as before.

How: GZreader wraps KOReader's VirtualKeyboard.addKeys (the last row's
space bar, `_`, loses one unit of width to the ☺ key), as the handwriting
key does (gzreader_hwkeyboard.lua); the two don't touch the same key.
]]

local Log = require("gzreader_log")
local _ = require("gettext")

local Emoji = {
    KEY = "☺",
    SETTING_RECENT = "gzreader_emoji_recent",
    RECENT_MAX = 24,
    COLS = 8,
    ROWS = 5,
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

--- Page `page` of `list` (COLS × ROWS at a time) and how many pages. Pure.
function Emoji.page(list, page)
    local per = Emoji.COLS * Emoji.ROWS
    local pages = math.max(1, math.ceil(#list / per))
    page = math.max(1, math.min(pages, page or 1))
    local out = {}
    for i = (page - 1) * per + 1, math.min(#list, page * per) do out[#out + 1] = list[i] end
    return out, page, pages
end

--- `keys` (a layout's KEYS) with the ☺ key before the last row's space bar,
--- which gives it one unit of width (a copy); nil when there's no space bar
--- wide enough. Pure.
function Emoji.withKey(keys)
    if type(keys) ~= "table" or #keys == 0 then return nil end
    local last = keys[#keys]
    for j, k in ipairs(type(last) == "table" and last or {}) do
        if type(k) == "table" and k.label == "_" and (tonumber(k.width) or 1) >= 2 then
            local copy = {}
            for r, rr in ipairs(keys) do copy[r] = rr end
            local row = {}
            for c, kk in ipairs(last) do row[c] = kk end
            local space = {}
            for kk, v in pairs(k) do space[kk] = v end
            space.width = (tonumber(k.width) or 1) - 1
            row[j] = space
            table.insert(row, j, { label = Emoji.KEY, gz_emoji_key = true })
            copy[#keys] = row
            return copy
        end
    end
    return nil
end

--- The emoji picker over keyboard `kb`: a tap types into its box.
function Emoji.show(kb)
    local UIManager = require("ui/uimanager")
    local Screen = require("device").screen
    local ButtonTable = require("ui/widget/buttontable")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local Geom = require("ui/geometry")
    local Blitbuffer = require("ffi/blitbuffer")
    local Device = require("device")
    local kinds = Emoji.kinds()
    local state = { kind = 1, page = 1 }
    local picker
    local width = Screen:getWidth()
    local Picker = InputContainer:extend{ name = "gz_emoji_picker", covers_fullscreen = false }
    function Picker:init()
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        self:build()
    end
    function Picker:build()
        local kind = kinds[state.kind]
        local list, page, pages = Emoji.page(kind.list, state.page)
        state.page = page
        local rows = {}
        -- the kinds (two rows of tabs, the one shown marked)
        local tabs = {}
        for i, k in ipairs(kinds) do
            tabs[#tabs + 1] = { text = (i == state.kind and "● " or "") .. k.name, callback = function()
                state.kind, state.page = i, 1
                self:rebuild()
            end }
        end
        local half = math.ceil(#tabs / 2)
        local r1, r2 = {}, {}
        for i, t in ipairs(tabs) do if i <= half then r1[#r1 + 1] = t else r2[#r2 + 1] = t end end
        rows[#rows + 1] = r1
        rows[#rows + 1] = r2
        for r = 1, Emoji.ROWS do
            local row = {}
            for c = 1, Emoji.COLS do
                local e = list[(r - 1) * Emoji.COLS + c]
                row[#row + 1] = e and { text = e, font_size = 26, callback = function() Emoji.type(kb, e) end }
                    or { text = " ", enabled = false, callback = function() end }
            end
            rows[#rows + 1] = row
        end
        rows[#rows + 1] = {
            { text = "◀", enabled = page > 1, callback = function() state.page = page - 1; self:rebuild() end },
            { text = string.format("%d / %d", page, pages), enabled = false, callback = function() end },
            { text = "▶", enabled = page < pages, callback = function() state.page = page + 1; self:rebuild() end },
            { text = _("Done"), callback = function() UIManager:close(self) end },
        }
        local bt = ButtonTable:new{ width = width - Screen:scaleBySize(16), buttons = rows, zero_sep = true, show_parent = self }
        local frame = FrameContainer:new{ background = Blitbuffer.COLOR_WHITE, bordersize = Screen:scaleBySize(1), padding = Screen:scaleBySize(4),
            radius = 0, VerticalGroup:new{ align = "center", bt } }
        local kb_h = (kb and kb.dimen and kb.dimen.h) or 0
        self.dimen = Geom:new{ x = 0, y = 0, w = width, h = Screen:getHeight() - kb_h }
        self[1] = BottomContainer:new{ dimen = self.dimen, CenterContainer:new{ dimen = Geom:new{ w = width, h = frame:getSize().h }, frame } }
    end
    function Picker:rebuild()
        self:build()
        UIManager:setDirty(self, "ui")
    end
    function Picker:onClose() UIManager:close(self); return true end
    picker = Picker:new{}
    UIManager:show(picker)
    Log.info("keyboard: the emoji picker opened")
    return picker
end

--- `e` typed into keyboard `kb`'s box (and kept as Recent).
function Emoji.type(kb, e)
    local box = kb and kb.inputbox
    if box and box.addChars then box:addChars(e) end
    pcall(Emoji.used, e)
end

function Emoji.install()
    local ok, VirtualKeyboard = pcall(require, "ui/widget/virtualkeyboard")
    if not ok or VirtualKeyboard._gz_emoji then return false end
    local Device = require("device")
    if not (Device.isTouchDevice and Device:isTouchDevice()) then return false end
    VirtualKeyboard._gz_emoji = true
    local orig = VirtualKeyboard.addKeys
    function VirtualKeyboard:addKeys(...)
        local keys = self.KEYS
        local with = Emoji.withKey(keys)
        if with then self.KEYS = with end
        local res = { pcall(orig, self, ...) }
        self.KEYS = keys
        if not res[1] then error(res[2]) end
        local kb = self
        for _r, row in ipairs(self.layout or {}) do
            for _c, key in ipairs(row) do
                if key.label == Emoji.KEY then
                    key.callback = function() Emoji.show(kb) end
                    key.hold_callback, key.swipe_callback, key.key_chars = nil, nil, nil
                end
            end
        end
        return unpack(res, 2)
    end
    return true
end

return Emoji
