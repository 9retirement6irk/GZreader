--[[--
Colour screens (the Kindle Colorsoft and Scribe Colorsoft, and any other
device KOReader shows colour on): which picture to draw.

A picture that has a colour version keeps it in a `colour` folder next to it,
under the same name: icons/shelf/ornament-photo-jug-01.png (greys, for the
16-grey screens) and icons/shelf/colour/ornament-photo-jug-01.png;
icons/shelf/walkman.svg and icons/shelf/colour/walkman.svg. `variant(path)`
gives the colour one on a colour screen, the path itself everywhere else.
]]

local Colour = {}

--- Is this screen showing colour now (a colour screen, and KOReader's
--- "Color rendering" not switched off)?
function Colour.enabled()
    local ok, on = pcall(function()
        local Screen = require("device").screen
        return Screen.isColorEnabled and Screen:isColorEnabled() or false
    end)
    return ok and on == true
end

local known = {}

--- `path`, or its colour version on a colour screen when there is one.
function Colour.variant(path)
    if type(path) ~= "string" or not Colour.enabled() then return path end
    local have = known[path]
    if have == nil then
        local dir, name = path:match("^(.*)/([^/]+)$")
        local try = dir and (dir .. "/colour/" .. name)
        local f = try and io.open(try, "rb")
        if f then f:close() end
        have = f and try or false
        known[path] = have
    end
    return have or path
end

return Colour
