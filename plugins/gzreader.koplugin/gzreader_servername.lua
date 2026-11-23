--[[--
The book server's own words, for texts shown on screen.

GZreader's Catalog was written for Grimmory, and many of its texts say so.
Signed in to BookOrbit they should name BookOrbit, and BookOrbit calls its
shelves collections and its smart shelves SmartScopes. Rather than a second
copy of every text, a text passes through Name.fix on its way to the screen.
]]

local _ = require("gettext")

local Name = {}

--- "bookorbit" or "grimmory": the server this Kindle's books come from.
function Name.server()
    local get = rawget(_G, "__GZ_BOOK_SERVER")
    local ok, name = pcall(function() return get and get() end)
    return ok and name == "bookorbit" and "bookorbit" or "grimmory"
end

function Name.orbit() return Name.server() == "bookorbit" end

--- The server's name.
function Name.get() return Name.orbit() and "BookOrbit" or "Grimmory" end

--- A text that names Grimmory, naming the server signed in to instead.
function Name.fix(text)
    if type(text) ~= "string" or not Name.orbit() then return text end
    return (text:gsub("Grimmory", "BookOrbit"))
end

--- What the server calls a list you put books on: Shelves (Grimmory), Collections (BookOrbit).
function Name.shelves() return Name.orbit() and _("Collections") or _("Shelves") end

--- …and one that fills itself by rules.
function Name.smart() return Name.orbit() and _("SmartScope") or _("smart shelf") end

return Name
