-- Update download dialog: keys must not close it or act behind it.
-- (The download itself is stubbed to a 40 s wait.)
return {
    start = 12,
    { key = "Back", after = 4 },
    { fn = function(E)
        local U = require("gzreader_update")
        U.get = function() os.execute("sleep 40"); return 500 end
        U.download({ version = "9.9.9", url = "http://127.0.0.1:18082/u.zip", size = 400 * 1024 })
    end, after = 6 },
    { shot = "dl" },
    { key = "Back", after = 2 }, { key = "Home", after = 2 }, { key = "Menu", after = 2 },
    { combo = { "Alt", "Q" }, after = 2 }, { combo = { "Alt", "W" }, after = 2 }, { key = "Press", after = 2 },
    { fn = function(E) print("[emu] windows after keys: " .. E.top()) end, after = 1 },
    { shot = "dl-after" },
}
