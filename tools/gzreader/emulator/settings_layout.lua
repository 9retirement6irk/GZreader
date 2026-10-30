-- Settings sections with GZreader's entries, and the read-aloud volume
-- buttons (Louder pressed twice with the 5-way must go up by 2).
local s = { start = 12, { key = "Back", after = 4 } }
local function key(k, after) s[#s + 1] = { key = k, after = after or 3 } end
local function shot(n) s[#s + 1] = { shot = n } end
local function section(letter, name)
    key(letter, 4); shot(name); key("RPgFwd", 3); shot(name .. "-2"); key("Back", 3)
end
key("Menu", 4); shot("homemenu")
key("I", 6); shot("settings")
section("E", "reader")
section("R", "interface")
section("Y", "general")
section("U", "grimmory")
key("Back", 3)
s[#s + 1] = { fn = function(E)
    G_reader_settings:saveSetting("gzreader_tts_volume", 10)
    require("apps/filemanager/filemanager").instance.gzreader:showTtsSettings()
end, after = 4 }
shot("tts-0")
key("Right", 1.5); key("Right", 1.5)
key("Press", 3); key("Press", 3)
s[#s + 1] = { fn = function(E)
    print("[emu] volume after Louder twice: " .. tostring(G_reader_settings:readSetting("gzreader_tts_volume")))
end, after = 1 }
shot("tts-1")
return s
