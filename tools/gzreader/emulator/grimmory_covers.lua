-- Grimmory tab with covers (demo/demo_grimmory.py on 127.0.0.1:18080):
-- All books as a list with details, then Menu → Display → Tiles and
-- Simple list. Covers are fetched for the page on screen.
local readme = dofile("/root/work/koreader/tools/gzreader/emulator/readme_shots.lua")
local s = { start = readme.start }
-- readme_shots up to and including "home-empty" (sign-in and setup guide)
for _i, step in ipairs(readme) do
    s[#s + 1] = step
    if step.shot == "home-empty" then break end
end
local function add(t) s[#s + 1] = t end
add({ fn = function() require("gzreader_homemenu").setDisplayMode("list_image_meta") end, after = 1 })
add({ combo = { "Alt", "R" }, after = 8 })
add({ key = "E", after = 6 }) -- All books
add({ shot = "list-0" })
add({ wait = 12 })
add({ fn = function(E)
    local lfs = require("libs/libkoreader-lfs")
    local n = 0
    for f in lfs.dir(require("datastorage"):getDataDir() .. "/cache/gzreader-covers") do
        if f:match("%.jpg$") then n = n + 1 end
    end
    print("[emu] covers on the Kindle: " .. n)
end, after = 1 })
add({ shot = "list" })
add({ key = "Menu", after = 4 }) -- the Home menu
add({ key = "T", after = 4 })    -- Display
add({ shot = "display" })
add({ key = "E", after = 14 })   -- Tiles
add({ shot = "tiles" })
add({ key = "RPgFwd", after = 14 })
add({ shot = "tiles-2" })
add({ key = "Menu", after = 4 })
add({ key = "T", after = 4 })
add({ key = "W", after = 6 }) -- Simple list
add({ shot = "simple" })
return s
