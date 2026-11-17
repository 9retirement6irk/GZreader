-- Photos from Immich in a note and in a drawing (gzreader_immichpick.lua),
-- through the Memos fork's own Immich connection (its /api/immich proxy):
-- the note editor's "+ Photos" chip → albums → a grid of thumbnails → two
-- photos picked → Add → "2 photos" → Save: the note in Memos with the two
-- as JPEG attachments. Then a drawing's ⋮ → Picture from Immich… → a photo
-- placed in the middle of the page → Done: the drawing's scene has it.
--   python3 -I demo/mock_memos.py 18390 --immich &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh notes_immich_photos.lua <out>
-- Checks go to <out>/notes-immich-photos-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function mid(d) return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) } end
local function find(test) local st = UIM()._window_stack; for i = #st, 1, -1 do if test(st[i].widget) then return st[i].widget end end end
local function editor() return find(function(w) return w.sheetStrip and w.on_save end) end
local function grid() return find(function(w) return w.name == "gz_immich_grid" end) end
local function albums() return find(function(w) return w.name == "gz_immich_albums" end) end
local function drawing() return find(function(w) return w.sketch and w.pages end) end
local SERVER = "http://127.0.0.1:18390"
local note_text = "Garden visit " .. os.time()
local done_pages

add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = SERVER, token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    p.store.immich = nil -- (only the fork's connection)
    local Pick = require("gzreader_immichpick")
    check(#Pick.sources(p) == 1 and Pick.sources(p)[1].kind == "memos", "the Memos fork's Immich: a way in")
    require("gzreader_notes").edit(p, nil)
end, after = 4 })
add({ shot = "1-editor", after = 0.5 })
add({ fn = function(E)
    local e = editor()
    check(e and e.strip and e.strip.photos == "+ Photos", "the note editor: \"+ Photos\" beside Draw")
    E.tap("+ Photos")
end, after = 6 })
add({ shot = "2-albums", after = 0.5 })
add({ fn = function(E)
    check(albums() ~= nil, "a tap: Immich's albums (All photos, Garden, Kids)")
    E.tap("Garden")
end, after = 8 })
add({ shot = "3-grid", after = 0.5 })
add({ fn = function(E)
    local g = grid()
    check(g and #g.cells == g.cols * g.rows and g.thumbs[g.cells[1].photo.id], "Garden: a page of thumbnails (" .. tostring(g and #g.cells) .. ")")
    E.tap(mid(g.cells[2].w.dimen))
end, after = 2 })
add({ fn = function(E)
    local g = grid()
    E.tap(mid(g.cells[1].w.dimen))
end, after = 2 })
add({ shot = "4-picked", after = 0.5 })
add({ fn = function(E)
    local g = grid()
    check(#g.picked == 2 and g.picked[1] == g.cells[2].photo.id and g.picked[2] == g.cells[1].photo.id, "two picked, in the order tapped")
    E.tap("Add (2)")
end, after = 8 })
add({ shot = "5-two-photos", after = 0.5 })
add({ fn = function(E)
    local e = editor()
    check(grid() == nil and albums() == nil and e and #(e.photos or {}) == 2 and e.strip.photos == "2 photos"
        and e.photos[1].filename == "IMG_0002.jpg", "Add: back in the note, \"2 photos\" in the chip (IMG_0002 first)")
    if e.rich_input then e.rich_input:addChars(note_text) elseif e.input then e.input:addChars(note_text) end
    e:save()
end, after = 10 })
add({ fn = function(E)
    local Memos = require("gzreader_memos")
    local c = Memos:new(plugin().store.memos)
    local page = c:list()
    local found
    for _i, m in ipairs(page and page.memos or {}) do if (m.content or ""):find(note_text, 1, true) then found = m end end
    local a = found and found.attachments or {}
    local names = {}
    for _i, x in ipairs(a) do names[#names + 1] = tostring(x.filename) .. ":" .. tostring(x.type) end
    check(#a == 2 and table.concat(names, ","):find("IMG_0002.jpg:image/jpeg", 1, true) and table.concat(names, ","):find("IMG_0001.jpg:image/jpeg", 1, true),
        "Save: the note in Memos with both photos, as JPEGs (" .. table.concat(names, ",") .. ")")
    -- a drawing
    require("gzreader_drawscreen").show{ pages = {}, immich = plugin(), on_done = function(res) done_pages = res end }
end, after = 4 })
add({ fn = function(E)
    local d = drawing()
    d:use({ id = "options" })
end, after = 2 })
add({ shot = "6-drawing-menu", after = 0.5 })
add({ fn = function(E)
    local row
    for _i, b in ipairs(drawing().buttons or {}) do if b.tool and b.tool.id == "immich" then row = b end end
    check(row and row.tool.label == "Picture from Immich…", "the drawing's ⋮: Picture from Immich…")
    if row then E.tap(mid(row.rect)) end
end, after = 6 })
add({ fn = function(E) E.tap("All photos") end, after = 8 })
add({ fn = function(E)
    local g = grid()
    if g then E.tap(mid(g.cells[3].w.dimen)) end
end, after = 2 })
add({ fn = function(E) E.tap("Add (1)") end, after = 8 })
add({ shot = "7-picture-placed", after = 0.5 })
add({ fn = function(E)
    local d = drawing()
    local pic
    for _i, el in ipairs(d and d.sketch.locked or {}) do if el.type == "image" then pic = el end end
    local f = pic and d.sketch.base.files[pic.fileId]
    check(pic and f and tostring(f.dataURL):match("^data:image/jpeg;base64,") and f.mimeType == "image/jpeg",
        "a picture on the page: an image element, its JPEG in the drawing")
    local c = d.canvas
    local cx, cy = d.sketch:toCanvas(pic.x + pic.width / 2, pic.y + pic.height / 2)
    check(math.abs(cx - c.w / 2) < 3 and math.abs(cy - c.h / 2) < 3, "…in the middle of the page shown")
    d:use({ id = "undo" })
end, after = 2 })
add({ fn = function(E)
    local d = drawing()
    local n = 0
    for _i, el in ipairs(d.sketch.locked) do if el.type == "image" then n = n + 1 end end
    check(n == 0, "Undo: the picture off")
    d:use({ id = "redo" })
end, after = 2 })
add({ fn = function(E)
    local d = drawing()
    d:done()
end, after = 4 })
add({ fn = function(E)
    local Drawing = require("gzreader_drawing")
    local p1 = done_pages and done_pages[1]
    local scene = p1 and p1.path and Drawing.readFile(p1.path)
    local img
    for _i, el in ipairs(scene and scene.elements or {}) do if el.type == "image" then img = el end end
    check(img and scene.files[img.fileId] and tostring(scene.files[img.fileId].dataURL):match("^data:image/jpeg"),
        "Redo, Done: the drawing's file has the picture (memos shows it, can move it)")
    local f = io.open(E.out .. "/notes-immich-photos-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
