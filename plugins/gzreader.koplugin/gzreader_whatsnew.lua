--[[--
The "What's new" screen after an update: GZreader's version and short points
from its changelog (gzreader_changelog.lua).

ZenOS shows this screen when its own version changes, with ZenOS's version
and ZenOS's list (features of touch devices, OPDS…). In GZreader it's shown
when GZreader's version changes, for every update, with GZreader's points;
ZenOS's main.lua asks `WhatsNew.pending()`.

A changelog line is either a string (the long text; the screen shows its
first sentence) or `{ short = "…", text = "…" }`: `short` on the screen,
`text` in Settings → Updates → Changelog and the release notes.
]]

local WhatsNew = {}

WhatsNew.SEEN = "gzreader_whats_new_seen"
WhatsNew.MAX_ITEMS = 15
WhatsNew.MAX_LEN = 120

local function compare(a, b)
    return require("gzreader_update").compare(a, b)
end

local function base(v)
    return type(v) == "string" and v:match("^v?(%d[%d%.]*%d)") or nil
end

--- The first sentence of a long text, at most MAX_LEN characters.
function WhatsNew.firstSentence(s)
    s = tostring(s or ""):gsub("%s+", " "):gsub("^ ", "")
    local first = s:match("^(.-[%.!?])%s") or s
    if #first > WhatsNew.MAX_LEN then
        local cut = first:sub(1, WhatsNew.MAX_LEN - 1)
        cut = cut:match("^(.*)%s") or cut
        first = cut:gsub("[%s,;:]+$", "") .. "…"
    end
    return first
end

--- A changelog line's short point.
function WhatsNew.short(change)
    if type(change) == "table" then
        if type(change.short) == "string" and change.short ~= "" then return change.short end
        return WhatsNew.firstSentence(change.text or change[1])
    end
    return WhatsNew.firstSentence(change)
end

--- A changelog line's long text.
function WhatsNew.text(change)
    if type(change) == "table" then return tostring(change.text or change[1] or change.short or "") end
    return tostring(change or "")
end

--- The short points for an update to `current` from `seen` (the version
--- last shown; nil: unknown, then only `current`'s own entry). A test build
--- (1.26.7-beta.abc1234) also gets the "next" entry: what it brings.
function WhatsNew.items(changelog, current, seen)
    local cur = base(current)
    if not cur then return {} end
    local test_build = tostring(current):gsub("^v", "") ~= cur
    local from = base(seen)
    local entries = {}
    for _i, entry in ipairs(type(changelog) == "table" and changelog or {}) do
        local v = entry.version
        local take
        if v == "next" then
            take = test_build
        elseif base(v) then
            take = compare(v, cur) <= 0
                and (from and compare(v, from) > 0 or (not from and compare(v, cur) == 0))
        end
        if take then entries[#entries + 1] = entry end
    end
    local out = {}
    for _i, entry in ipairs(entries) do
        for _j, change in ipairs(entry.changes or {}) do
            if #out >= WhatsNew.MAX_ITEMS then return out end
            local s = WhatsNew.short(change)
            if s ~= "" then out[#out + 1] = s end
        end
    end
    return out
end

function WhatsNew.current()
    return require("gzreader_update").currentVersion()
end

function WhatsNew.markSeen(version)
    G_reader_settings:saveSetting(WhatsNew.SEEN, version or WhatsNew.current())
end

--- `{ version = …, items = {…} }` when an update's screen is due (and marks
--- it seen), else nil. A version with nothing to say is marked seen quietly.
function WhatsNew.pending()
    local current = WhatsNew.current()
    if current == "0.0.0" then return nil end -- (a tree without a version: development)
    local seen = G_reader_settings:readSetting(WhatsNew.SEEN)
    if seen == current then return nil end
    local ok, changelog = pcall(require, "gzreader_changelog")
    local items = WhatsNew.items(ok and changelog or {}, current, seen)
    WhatsNew.markSeen(current)
    if #items == 0 then return nil end
    return { version = current, items = items }
end

return WhatsNew
