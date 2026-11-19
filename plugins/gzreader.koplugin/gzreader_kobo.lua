--[[--
GZreader on a Kobo: its own words.

GZreader's messages were written for Kindles: "this Kindle", "the Kindle's
drive", "Exit to Kindle". On a Kobo they read "this Kobo", "the Kobo's
drive", "Exit to Kobo" (gettext.lua's GZreader hook rewrites each message
once, as it shows). Names of Kindle models and things only a Kindle has stay
as they are: "Kindle 2", "Kindle Paperwhite", "Kindles", "Kindle voice"…

  require("gzreader_kobo").install()    -- (main.lua, as GZreader loads)
  Kobo.words("Delete it from this Kindle?") --> "Delete it from this Kobo?"
]]

local Kobo = {}

-- "Kindle" followed by one of these stays: a model, the family, a Kindle-only thing
local KEEP_AFTER = {
    "s", "%-", " %d", " Keyboard", " Touch", " DX", " Paperwhite", " Scribe", " Oasis", " Voyage", " Basic",
    " Colorsoft", " voice", " bookmark", " pen", " Unlimited", " Store",
}

local function kept(rest)
    for _i, p in ipairs(KEEP_AFTER) do
        if rest:find("^" .. p) then return true end
    end
    return false
end

--- A message in a Kobo's words.
function Kobo.words(s)
    if type(s) ~= "string" or not s:find("Kindle", 1, true) then return s end
    local out, i = {}, 1
    while true do
        local a, b = s:find("Kindle", i, true)
        if not a then
            out[#out + 1] = s:sub(i)
            break
        end
        out[#out + 1] = s:sub(i, a - 1)
        out[#out + 1] = kept(s:sub(b + 1, b + 16)) and "Kindle" or "Kobo"
        i = b + 1
    end
    return table.concat(out)
end

--- Why there's no sound on a Kobo (audiobooks, music, read aloud), or nil elsewhere.
function Kobo.noAudio()
    if not Kobo.isKobo() then return nil end
    local _ = require("gettext")
    return _("GZreader can't play sound on a Kobo: Kobos have no speaker or headphone jack, and the ones with Bluetooth play audiobooks only in Kobo's own software, which GZreader can't use.")
end

--- Is this a Kobo? (a test replaces it)
function Kobo.isKobo()
    local ok, Device = pcall(require, "device")
    return ok and type(Device) == "table" and Device.isKobo ~= nil and Device:isKobo() == true
end

--- On a Kobo: GZreader's messages in its words from now on.
function Kobo.install()
    if Kobo.installed or not Kobo.isKobo() then return false end
    local ok, gettext = pcall(require, "gettext")
    if not ok or type(gettext) ~= "table" or type(gettext.gzSetRewrite) ~= "function" then return false end
    gettext.gzSetRewrite(Kobo.words)
    Kobo.installed = true
    return true
end

return Kobo
