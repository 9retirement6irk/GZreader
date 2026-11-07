-- The DX's shelves (GZ_EMU_MODEL=dx): Home with two shelves of recent books,
-- the Downloads tab with four shelves to a page (six before). Books: the
-- EPUBs in GZ_EMU_BOOKS (a folder, e.g. the demo library's), copied into the
-- GZreader folder and put in the history. Prints the shelves counted.
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 4 })
add({ fn = function(E)
    local src = os.getenv("GZ_EMU_BOOKS") or "/tmp/demo-lib"
    local plugin = require("apps/filemanager/filemanager").instance.gzreader
    local dir = plugin:libraryDir()
    os.execute("cp " .. src .. "/*.epub " .. dir .. "/")
    local ReadHistory = require("readhistory")
    local lfs = require("libs/libkoreader-lfs")
    local n, t, first = 0, os.time() - 1000, nil
    for f in lfs.dir(dir) do
        if f:match("%.epub$") then
            n = n + 1
            first = first or (dir .. "/" .. f)
            ReadHistory:addItem(dir .. "/" .. f, t + n)
            -- (Home's shelf counts books that have been opened: a sidecar)
            local ds = require("docsettings"):open(dir .. "/" .. f)
            ds:saveSetting("percent_finished", 0.1)
            ds:flush()
        end
    end
    ReadHistory:_flush()
    E.say("books:", n)
    -- a book opened and closed: Home gathers its shelf again
    require("apps/reader/readerui"):showReader(first)
end, after = 20 })
add({ key = "Back", after = 12 })
add({ key = "X", after = 10 })  -- Downloads
add({ fn = function(E)
    local fc = require("apps/filemanager/filemanager").instance.file_chooser
    E.say("downloads shelves:", tostring(fc._gz_rows), "per page:", tostring(fc.perpage), "row height:", tostring(fc._gz_row_h))
end })
add({ shot = "dx-downloads" })
add({ key = "Z", after = 12 })  -- Home
add({ shot = "dx-home" })
local function homeFocus(E, what)
    local fm = require("apps/filemanager/filemanager").instance
    local UIManager = require("ui/uimanager")
    local id
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        id = id or w._zen_home_focus_id
    end
    E.say(what, "home focus:", tostring(id or (fm and fm._zen_home_focus_id)))
end
for i = 1, 4 do
    add({ key = "Down", after = 3 })
    add({ fn = function(E) homeFocus(E, "down " .. i) end })
end
add({ shot = "dx-home-down" })
return s
