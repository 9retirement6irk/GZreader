--[[
Wi-Fi network names out of text that leaves the Kindle (GZreader's log,
crash.log's end in a debug report or a saved log). KOReader puts the name
in its messages ("Connecting to network <name>…", "Connected to network
<name>") and in its own debug lines ("lease_ssid set to <name>"); each
becomes "<network>".

No dependencies: the watchdog (its own process) loads it with dofile.

  local hide = require("gzreader_netname")
  hide("Connecting to network Example Net…") --> "Connecting to network <network>…"
]]

-- what comes just before a name (Lua patterns)
local BEFORE = {
    "[Tt]o network%s+", "[Pp]referred network%s+", "[Cc]urrent network:%s+",
    "ssid:%s+", "lease_ssid set to%s+", "lease_ssid=%s*", "[Ee]?ssid=%s*",
}
-- what ends one (plain text); otherwise the end of the line
local AFTER = { "…", "...", " (after", " ; last", "; last", "), ", " ), " }

local function line(s)
    for _i, p in ipairs(BEFORE) do
        local a, b = s:find(p)
        if a and s:sub(b + 1, b + 1) ~= "<" then
            local rest = s:sub(b + 1)
            local cut = #rest + 1
            for _j, e in ipairs(AFTER) do
                local k = rest:find(e, 1, true)
                if k and k < cut then cut = k end
            end
            local name, stop = rest:sub(1, cut - 1), ""
            -- "Already connected to network <name>."
            if cut > #rest and name:sub(-1) == "." then name, stop = name:sub(1, -2), "." end
            if name:match("%S") then s = s:sub(1, b) .. "<network>" .. stop .. rest:sub(cut) end
        end
    end
    return s
end

return function(s)
    s = tostring(s)
    -- (most text has neither word: one quick look first)
    if not s:find("etwork", 1, true) and not s:find("ssid", 1, true) then return s end
    return (s:gsub("[^\n]+", function(l)
        if l:find("etwork", 1, true) or l:find("ssid", 1, true) then return line(l) end
    end))
end
