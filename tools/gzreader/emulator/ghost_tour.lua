-- E-ink ghosting audit: common moves on a Kindle 3 (GZ_EMU_GHOST=1; demo Grimmory on 18200).
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function key(k, name, after) add({ key = k, after = after or 4 }); shot(name) end
local home = "/mnt/us/GZreader"
add({ fn = function(E)
    local UI = require("ui/uimanager")
    for i = #UI._window_stack, 1, -1 do
        local w = UI._window_stack[i].widget
        if w.name ~= "filemanager" and not w._zen_home_focus_targets and i > 1 then UI:close(w) end
    end
    os.execute("mkdir -p " .. home)
    local f = io.open("/root/work/demo/lib/library.json"); local txt = f:read("*a"); f:close()
    local lib = require("json").decode(txt)
    local RH = require("readhistory")
    local now = os.time()
    for i, b in ipairs(lib) do
        if i > 8 then break end
        local dest = home .. "/" .. (b.title:gsub("[/:]", " ")) .. ".epub"
        os.execute(string.format("cp '/root/work/demo/lib/%d.epub' %q", b.id, dest))
        RH:addItem(dest, now - i * 60)
        pcall(function() require("bookinfomanager"):extractBookInfo(dest, { max_cover_w = 600, max_cover_h = 800 }) end)
    end
    local fm = require("apps/filemanager/filemanager").instance
    local HP = require("common/shared_state").get(fm.zenos, "home")
    for _i, b in ipairs(RH.hist) do HP.invalidateBookCache(b.file, true) end
    HP.invalidateLibraryCache()
    E.say("login", tostring(fm.gzreader.api:login("http://127.0.0.1:18200", "reader", "demo")))
end, after = 20 })
key("Z", "g01-home", 8)
key("X", "g02-downloads", 6)
key("C", "g03-grimmory", 10)
key("V", "g04-notes", 6)
key("B", "g05-calendar", 6)
key("Z", "g06-home-again", 6)
key("Menu", "g07-menu", 4)
key("Back", "g08-menu-closed", 4)
key("Right", "g09-focus-move", 3)
key("Right", "g10-focus-move2", 3)
add({ fn = function() require("apps/reader/readerui"):showReader(require("readhistory").hist[1].file) end, after = 16 })
shot("g11-book-open")
for i = 1, 6 do key("RPgFwd", string.format("g%02d-page%d", 11 + i, i), 3) end
key("Menu", "g18-reader-menu", 4)
key("Back", "g19-reader-menu-closed", 4)
key("Back", "g20-back-home", 10)
return s
