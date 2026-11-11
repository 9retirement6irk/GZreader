#!/usr/bin/env luajit
--[[
A release's notes (Markdown) from GZreader's changelog: every version newer
than the previous release, up to this one (an untagged version in between,
e.g. 1.26.6 released with 1.26.7, comes along), newest first, then which
package to download.

    luajit tools/gzreader/release-notes.lua <gzreader_changelog.lua> <version> [<release tag>...]

The release tags (v1.26.5, …) say which versions were released before; the
newest one older than <version> is where the notes start. Without tags, only
<version>'s own entry. The release workflow puts this in a release that has
no notes of its own (GitHub otherwise shows the tagged commit's message, its
first line cut off at about 70 characters).
]]

local function parts(v)
    local t = {}
    for n in tostring(v):gsub("^v", ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t
end

local function compare(a, b)
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

local function notes(changelog, version, tags)
    local previous
    for _i, tag in ipairs(tags or {}) do
        if tag:match("^v?%d+%.%d+") and compare(tag, version) < 0
                and (not previous or compare(tag, previous) > 0) then
            previous = tag
        end
    end
    local out = {}
    local entries = {}
    for _i, entry in ipairs(changelog) do
        local v = entry.version
        if type(v) == "string" and v:match("^%d") and compare(v, version) <= 0
                and (previous and compare(v, previous) > 0 or not previous and compare(v, version) == 0) then
            entries[#entries + 1] = entry
        end
    end
    table.sort(entries, function(a, b) return compare(a.version, b.version) > 0 end)
    if #entries == 0 then
        out[#out + 1] = "GZreader " .. version .. "."
    end
    for i, entry in ipairs(entries) do
        if #entries > 1 then
            if i > 1 then out[#out + 1] = "" end
            out[#out + 1] = "### " .. entry.version
            out[#out + 1] = ""
        end
        for _j, change in ipairs(entry.changes or {}) do
            -- (a line is a string, or { short = …, text = … }: the full text here)
            if type(change) == "table" then change = change.text or change[1] or change.short or "" end
            out[#out + 1] = "- " .. tostring(change):gsub("\n", " ")
        end
    end
    if previous then
        out[#out + 1] = ""
        out[#out + 1] = "Changes since " .. previous .. (#entries > 1 and " (versions in between weren't released on their own)." or ".")
    end
    out[#out + 1] = ""
    out[#out + 1] = "### Download"
    out[#out + 1] = ""
    out[#out + 1] = "Already on GZreader: Settings → Updates (Kindles without Wi‑Fi: the sync page). To install: https://github.com/9retirement6irk/GZreader/wiki/Installing"
    out[#out + 1] = ""
    out[#out + 1] = "- `gzreader-kindle-legacy-" .. version .. ".zip`: Kindle 2, DX, Kindle Keyboard"
    out[#out + 1] = "- `gzreader-kindle-" .. version .. ".zip`: Kindle 4, Kindle Touch"
    out[#out + 1] = "- `gzreader-kindlepw2-" .. version .. ".zip`: touch Kindles on firmware 5.6.1 – 5.16.2"
    out[#out + 1] = "- `gzreader-kindlehf-" .. version .. ".zip`: touch Kindles on firmware 5.16.3 and later"
    out[#out + 1] = "- `gzreader-nook-1st-edition-" .. version .. ".zip`: Nook 1st Edition (test build)"
    out[#out + 1] = "- `gzreader-nook-" .. version .. ".zip`: Nook Simple Touch (test build)"
    return table.concat(out, "\n") .. "\n"
end

if arg and arg[0] and arg[0]:match("release%-notes%.lua$") then
    local path, version = arg[1], arg[2]
    if not path or not version then
        io.stderr:write("usage: release-notes.lua <gzreader_changelog.lua> <version> [<release tag>...]\n")
        os.exit(2)
    end
    local tags = {}
    for i = 3, #arg do tags[#tags + 1] = arg[i] end
    io.write(notes(dofile(path), (version:gsub("^v", "")), tags))
end

return { notes = notes, compare = compare }
