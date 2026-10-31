-- A configured install for start-up timings (startup.lua): the setup guide
-- with QR sign-in (demo/demo_grimmory.py on 127.0.0.1:18080), then four
-- books opened so Home has Recent books. Ends at Home.
local readme = dofile("/root/work/koreader/tools/gzreader/emulator/readme_shots.lua")
local s = { start = readme.start }
for _i, step in ipairs(readme) do
    s[#s + 1] = step
    if step.shot == "home-empty" then break end
end
local function add(t) s[#s + 1] = t end
for i, b in ipairs({ "9", "10", "11", "12" }) do
    add({ fn = function()
        os.execute("mkdir -p /mnt/us/GZreader && cp /root/work/demo/lib/" .. b .. ".epub /mnt/us/GZreader/book" .. i .. ".epub")
        require("apps/reader/readerui"):showReader("/mnt/us/GZreader/book" .. i .. ".epub")
    end, after = 14 })
    add({ key = "RPgFwd", after = 3 })
    add({ key = "Back", after = 10 })
end
add({ wait = 10 })
return s
