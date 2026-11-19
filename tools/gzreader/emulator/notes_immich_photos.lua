-- Photos from Immich in a note and in a drawing (gzreader_immichpick.lua),
-- through the Memos fork's own Immich connection (its /api/immich proxy):
-- the note editor's top-bar picture (Photos, beside ✎ Draw) → albums → a grid of thumbnails → two
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
local inline_text = "Kids at the pond " .. os.time()
local done_pages
local function client() return require("gzreader_memos"):new(plugin().store.memos) end
local function memoWith(text)
    local page = client():list()
    for _i, m in ipairs(page and page.memos or {}) do if (m.content or ""):find(text, 1, true) then return m end end
end
local function view() return find(function(w) return w.memo and w.picks end) end
local function strip_thumbs() local e = editor(); return e and e.strip and e.strip.photo_thumbs end

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
    local b = e and e.bar_buttons
    check(b and b.photos and b.draw and b.photos.dimen and b.draw.dimen and b.photos.dimen.x > b.draw.dimen.x
        and e.strip and e.strip.photos == nil and e.strip.thumbs == 0,
        "the note editor: Photos in the top bar beside ✎ Draw (as on the drawing screen and an opened note), not in the row under it")
    if b and b.photos then E.tap(mid(b.photos.dimen)) end
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
add({ shot = "4b-where", after = 0.5 })
add({ fn = function(E)
    check(E.findText("In the text, at the cursor") and E.findText("With the note, as attachments"), "Add: asked where they go (in the text, or attached)")
    E.tap("With the note, as attachments")
end, after = 3 })
add({ shot = "5-two-photos", after = 0.5 })
add({ fn = function(E)
    local e = editor()
    check(grid() == nil and albums() == nil and e and #(e.photos or {}) == 2 and strip_thumbs() == 2
        and e.photos[1].filename == "IMG_0002.jpg", "attached: back in the note, the two as small pictures under the top bar (IMG_0002 first)")
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
    -- its page: the photos as a gallery of pictures, not file names
    require("gzreader_notes").showNote(plugin(), found)
end, after = 8 })
add({ shot = "5b-gallery", after = 0.5 })
add({ fn = function(E)
    local v = view()
    local pics = 0
    local function walk(w)
        if type(w) ~= "table" then return end
        if w.image and w.dimen and w.dimen.w > 20 then pics = pics + 1 end
        for _i, k in ipairs(w) do walk(k) end
    end
    walk(v and v[1])
    check(v and pics == 2 and not E.findText("IMG_0002.jpg"), "the note's page: its two photos as pictures, no file-name rows (" .. pics .. ")")
    UIM():close(v)
    -- a new note, a photo in its text
    require("gzreader_notes").edit(plugin(), nil)
end, after = 4 })
add({ fn = function(E) local e = editor(); if e and e.bar_buttons.photos then E.tap(mid(e.bar_buttons.photos.dimen)) end end, after = 6 })
add({ fn = function(E) E.tap("Kids") end, after = 6 })
add({ fn = function(E) local g = grid(); if g then E.tap(mid(g.cells[1].w.dimen)) end end, after = 2 })
add({ fn = function(E) E.tap("Add (1)") end, after = 6 })
add({ fn = function(E) E.tap("In the text, at the cursor") end, after = 6 })
add({ shot = "5c-in-text", after = 0.5 })
add({ fn = function(E)
    local e = editor()
    local text = e and e:text() or ""
    check(text:match("!%[IMG_0101%]%(/file/attachments/[%w%-]+/IMG_0101%.jpg%)") and strip_thumbs() == 1 and #(e.sent or {}) == 1,
        "In the text: sent at once, its picture line at the cursor, shown as a small picture")
    local shown
    for _i, l in ipairs(e.rich_input and e.rich_input.lines or {}) do if l.picture then shown = l end end
    check(shown and shown.picture.w > 20, "…and the editor shows it as the picture, not its Markdown")
    if e.rich_input then e.rich_input.cur = { b = e.doc.blocks[1], i = 1 }; e.rich_input:addChars(inline_text .. "\n") end
    e:save()
end, after = 10 })
add({ fn = function(E)
    local m = memoWith(inline_text)
    local a = m and m.attachments or {}
    local uid = a[1] and tostring(a[1].name):match("attachments/(.+)$")
    check(m and #a == 1 and uid and m.content:find("/file/attachments/" .. uid, 1, true),
        "Save: the new note made with the photo, its text showing it (the fork accepts it)")
    -- its page: the photo where the text has it, not again in a gallery under it (as Memos)
    if m then require("gzreader_notes").showNote(plugin(), m) end
end, after = 6 })
add({ shot = "5c2-in-text-page", after = 0.5 })
add({ fn = function(E)
    local v = view()
    local pics = 0
    local function walk(w)
        if type(w) ~= "table" then return end
        if w.image and w.dimen and w.dimen.w > 20 then pics = pics + 1 end
        for _i, k in ipairs(w) do walk(k) end
    end
    walk(v and v[1])
    check(v and pics == 1, "its page: the photo in the text once, not again under it (" .. pics .. " pictures)")
    if v then UIM():close(v) end
    -- editing the first note: its photos in the editor
    require("gzreader_notes").edit(plugin(), memoWith(note_text))
end, after = 6 })
add({ shot = "5d-editing", after = 0.5 })
add({ fn = function(E)
    local e = editor()
    check(e and strip_thumbs() == 2, "editing a note: its two attached photos as small pictures")
    e:photoActions(e:photoList()[1])
end, after = 2 })
add({ fn = function(E)
    check(E.findText("Put it in the text, at the cursor") and E.findText("Remove it from the note"), "a tap on one: Put it in the text, Remove it from the note…")
    E.tap("Put it in the text, at the cursor")
end, after = 3 })
add({ fn = function(E)
    local e = editor()
    e:photoActions(e:photoList()[2])
end, after = 2 })
add({ fn = function(E) E.tap("Remove it from the note") end, after = 2 })
add({ fn = function(E) E.tap("Remove") end, after = 2 })
add({ fn = function(E)
    local e = editor()
    check(#e:photoList() == 1 and e:photoList()[1].in_text, "one in the text now, the other removed")
    e:save()
end, after = 10 })
add({ fn = function(E)
    local m = memoWith(note_text)
    local a = m and m.attachments or {}
    local uid = a[1] and tostring(a[1].name):match("attachments/(.+)$")
    check(m and #a == 1 and uid and m.content:find("/file/attachments/" .. uid, 1, true),
        "Save: in Memos one photo left, shown in the text; the removed one deleted")
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
    local sel = d.sketch.selection
    check(d.tool == "lasso" and sel and sel.pictures and sel.pictures[1] == pic and d.sketch:selectionBox() ~= nil,
        "…chosen with the lasso, a frame with handles round it (to move and size it)")
    d:use({ id = "undo" })
end, after = 2 })
add({ fn = function(E)
    local d = drawing()
    local n = 0
    for _i, el in ipairs(d.sketch.locked) do if el.type == "image" then n = n + 1 end end
    check(n == 0, "Undo: the picture off")
    d:use({ id = "redo" })
end, after = 2 })
-- chosen again with the lasso: dragged from inside it, then by its bottom right handle
local moved = {}
local function drawn(E, pts)
    if os.getenv("GZ_EMU_MODEL") == "scribe" then E.pen(pts, 0.6) else E.finger(pts, 0.6) end
end
add({ fn = function(E)
    local d = drawing()
    local pic
    for _i, el in ipairs(d.sketch.locked) do if el.type == "image" and not el.locked then pic = el end end
    d:use({ id = "lasso" })
    d.sketch:selectPictures({ pic })
    d:layoutBar(); d:redrawAll()
    moved.pic, moved.x, moved.w = pic, pic.x, pic.width
    local c = d.canvas
    local b = d.sketch:pictureBox(pic)
    local x, y = c.x + (b.x0 + b.x1) / 2, c.y + (b.y0 + b.y1) / 2
    drawn(E, { { x, y }, { x - 40, y + 20 }, { x - 80, y + 40 }, { x - 120, y + 60 } })
end, after = 4 })
add({ shot = "7b-picture-moved", after = 0.5 })
add({ fn = function(E)
    local d = drawing()
    local pic = moved.pic
    check(pic.x < moved.x - 10 and math.abs(pic.width - moved.w) < 1e-6, "dragged from inside its frame: the picture moved, its size as it was")
    moved.x2, moved.y2 = pic.x, pic.y
    local c = d.canvas
    local pad = d.sketch.lasso_pad or 0
    local b = d.sketch:selectionBox()
    local x, y = c.x + b.x1 - pad, c.y + b.y1 - pad
    drawn(E, { { x, y }, { x + 30, y + 10 }, { x + 70, y + 20 }, { x + 100, y + 30 } })
end, after = 4 })
add({ shot = "7c-picture-bigger", after = 0.5 })
add({ fn = function(E)
    local pic = moved.pic
    check(pic.width > moved.w * 1.2 and math.abs(pic.x - moved.x2) < 1e-6 and math.abs(pic.y - moved.y2) < 1e-6,
        "its bottom right handle dragged out: bigger, its top left corner where it was (" .. math.floor(moved.w) .. " → " .. math.floor(pic.width) .. ")")
    moved.final_x, moved.final_w = pic.x, pic.width
    drawing():done()
end, after = 4 })
add({ fn = function(E)
    local Drawing = require("gzreader_drawing")
    local p1 = done_pages and done_pages[1]
    local scene = p1 and p1.path and Drawing.readFile(p1.path)
    local img
    for _i, el in ipairs(scene and scene.elements or {}) do if el.type == "image" then img = el end end
    check(img and scene.files[img.fileId] and tostring(scene.files[img.fileId].dataURL):match("^data:image/jpeg"),
        "Redo, Done: the drawing's file has the picture (memos shows it, can move it)")
    check(img and math.abs(img.x - moved.final_x) < 0.5 and math.abs(img.width - moved.final_w) < 0.5,
        "…where it was moved to, at the size it was given")
    local f = io.open(E.out .. "/notes-immich-photos-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
