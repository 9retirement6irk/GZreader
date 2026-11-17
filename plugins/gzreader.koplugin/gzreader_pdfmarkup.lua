--[[--
Mark up a PDF (the Notes tab): a note's PDF attachment, a few of its pages
drawn on. Each page you pick becomes a page of the drawing screen with the
PDF's page as its background, the way a notepaper is one (a locked picture
under everything, as Memos keeps a background); what you draw goes over it.
Done goes back to the note's text, and Save sends the pages you drew on as
drawings of the same note, so Memos shows them, and opens them in its
drawing editor, with the PDF's page under your ink. The PDF itself isn't
changed.

- Pages are rendered with MuPDF (`ffi/mupdf`) at Memos' picture size (at
  most 1440 px on the longest side) as PNGs, then kept in the drawing: in
  colour when the page has any (the Kindle's screen shows it grey, Memos in
  its colours), grey when it hasn't (a smaller picture).
- At most `MAX_PAGES` at a time: each page is a picture in memory while the
  drawing screen is open.
- A page left blank isn't kept (as an empty drawing page isn't).
]]

local Drawing = require("gzreader_drawing")
local _ = require("gettext")

local PdfMarkup = {}

PdfMarkup.MAX_PAGES = 10
PdfMarkup.MAX_SIDE = 1440 -- Memos keeps pictures at most this long
PdfMarkup.MAX_BYTES = 1536 * 1024 -- a page's picture: rendered smaller when bigger
PdfMarkup.MAX_BYTES_COLOR = 3072 * 1024 -- (in colour: three times the data, so more room before it's made smaller)
PdfMarkup.COLOR_MIN = 12 -- how far a pixel's red, green and blue must differ to count as colour (not a scan's faint tint)

--- A PDF attachment (by its type, else its file name).
function PdfMarkup.isPdf(att)
    if type(att) ~= "table" then return false end
    if tostring(att.type or ""):lower() == "application/pdf" then return true end
    return tostring(att.filename or ""):lower():match("%.pdf$") ~= nil
end

--- The pages asked for: "3", "1-4", "2, 5-7" (spaces and "–" allowed) in a
--- PDF of `count` pages; each once, in the order typed. Returns the list, or
--- nil and why: "empty", "range" (a page that isn't in the PDF, or not a
--- page number), "many" (more than `max`).
function PdfMarkup.parsePages(text, count, max)
    max = max or PdfMarkup.MAX_PAGES
    text = tostring(text or ""):gsub("\u{2013}", "-"):gsub("\u{2014}", "-")
    local out, seen = {}, {}
    for part in text:gmatch("[^,;]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" then
            local a, b = part:match("^(%d+)%s*%-%s*(%d+)$")
            if not a then a = part:match("^(%d+)$"); b = a end
            a, b = tonumber(a), tonumber(b)
            if not a or a < 1 or b < 1 or a > count or b > count then return nil, "range" end
            local step = a <= b and 1 or -1
            for n = a, b, step do
                if not seen[n] then
                    seen[n] = true
                    out[#out + 1] = n
                    if #out > max then return nil, "many" end
                end
            end
        end
    end
    if #out == 0 then return nil, "empty" end
    return out
end

--- What the page box offers first: every page when there are few, else the first.
function PdfMarkup.suggest(count)
    if count <= 1 then return "1" end
    if count <= 3 then return "1-" .. count end
    return "1"
end

--- The zoom that fits a `w` × `h` page (points) into `max_side` on its
--- longest side, and the picture's size at it.
function PdfMarkup.fit(w, h, max_side)
    max_side = max_side or PdfMarkup.MAX_SIDE
    w, h = math.max(1, tonumber(w) or 1), math.max(1, tonumber(h) or 1)
    local zoom = max_side / math.max(w, h)
    return zoom, math.max(1, math.floor(w * zoom + 0.5)), math.max(1, math.floor(h * zoom + 0.5))
end

--- A PNG's width, height and size in bytes (nil when it isn't one).
function PdfMarkup.pngInfo(path)
    return require("gzreader_notepaper").pngSize(path)
end

--- A drawing scene with the PNG at `path` (w × h) as its background: a
--- locked picture at (0, 0) under everything, as Memos keeps one.
function PdfMarkup.scene(path, w, h, now)
    local f = io.open(path, "rb")
    if not f then return nil, "no-file" end
    local data = f:read("*a")
    f:close()
    local scene = Drawing.newScene()
    local file_id = Drawing.randomId()
    scene.elements[1] = {
        id = Drawing.randomId(), type = "image", x = 0, y = 0, width = w, height = h,
        angle = 0, strokeColor = "#1e1e1e", backgroundColor = "transparent", strokeWidth = 2, opacity = 100,
        isDeleted = false, groupIds = Drawing.list(), boundElements = Drawing.list(),
        seed = Drawing.randomSeed(), locked = true, fileId = file_id, scale = Drawing.list({ 1, 1 }),
    }
    scene.files[file_id] = { mimeType = "image/png", created = now or (os.time() * 1000),
        dataURL = "data:image/png;base64," .. require("ffi/sha2").bin_to_base64(data) }
    return scene
end

--- Writes the page's picture `bb` (as MuPDF drew it) to `png_path`. Drawn in
--- colour (RGB32), it's kept in colour when the page has any, and written as
--- a grey picture when it hasn't. Returns true when it's in colour.
--- (Pages were always drawn grey; a colour PDF marked up was grey in Memos.
--- The owner, 2026-11-17.)
function PdfMarkup.writePage(bb, png_path, bgr)
    local ok, colour = pcall(function()
        local Blitbuffer = require("ffi/blitbuffer")
        if bb:getType() ~= Blitbuffer.TYPE_BBRGB32 then return nil end
        local ffi = require("ffi")
        local w, h, stride = bb:getWidth(), bb:getHeight(), bb.stride
        local src = ffi.cast("uint8_t*", bb.data)
        local min = PdfMarkup.COLOR_MIN
        local coloured = false
        for y = 0, h - 1 do
            local row = src + y * stride
            for x = 0, w - 1 do
                local r, g, b = row[x * 4], row[x * 4 + 1], row[x * 4 + 2]
                if r - g > min or g - r > min or g - b > min or b - g > min or r - b > min or b - r > min then coloured = true; break end
            end
            if coloured then break end
        end
        local n = coloured and 3 or 1
        local mem = ffi.new("uint8_t[?]", w * h * n)
        local ri, bi = bgr and 2 or 0, bgr and 0 or 2
        local i = 0
        for y = 0, h - 1 do
            local row = src + y * stride
            for x = 0, w - 1 do
                local r, g, b = row[x * 4 + ri], row[x * 4 + 1], row[x * 4 + bi]
                if coloured then
                    mem[i], mem[i + 1], mem[i + 2] = r, g, b
                    i = i + 3
                else
                    mem[i] = (r * 77 + g * 151 + b * 28) / 256
                    i = i + 1
                end
            end
        end
        if require("ffi/png").encodeToFile(png_path, mem, w, h, n) == false then return nil end
        return coloured
    end)
    if ok and colour ~= nil then return colour end
    bb:writePNG(png_path) -- (a grey buffer, or the above couldn't: as it's always been written)
    return false
end

--- Opens the PDF at `path`: { count, render(n, png_path, max_side) → w, h, colour | nil, err; close() },
--- or nil and why ("open", "password", "empty").
function PdfMarkup.open(path)
    local ok, mupdf = pcall(require, "ffi/mupdf")
    if not ok or not mupdf then return nil, "open" end
    local okd, doc = pcall(mupdf.openDocument, path)
    if not okd or not doc then return nil, "open" end
    local okp, needs = pcall(function() return doc:needsPassword() end)
    if okp and needs then pcall(doc.close, doc); return nil, "password" end
    local okc, count = pcall(function() return doc:getPages() end)
    if not okc or not count or count < 1 then pcall(doc.close, doc); return nil, "empty" end
    -- (in colour: MuPDF draws grey unless asked; see writePage)
    pcall(function() if doc.setColorRendering then doc:setColorRendering(true) else doc.color = true end end)
    local DrawContext = require("ffi/drawcontext")
    local h = { count = count }
    function h.render(n, png_path, max_side)
        local okr, w, ht, colour = pcall(function()
            local page = doc:openPage(n)
            local pw, ph = page:getSize(DrawContext.new())
            local zoom, w, ht = PdfMarkup.fit(pw, ph, max_side)
            local dc = DrawContext.new()
            dc:setZoom(zoom)
            local bb = page:draw_new(dc, w, ht, 0, 0)
            page:close()
            local colour = PdfMarkup.writePage(bb, png_path, mupdf.bgr)
            bb:free()
            return w, ht, colour
        end)
        if not okr then return nil, tostring(w) end
        return w, ht, colour
    end
    function h.close() pcall(doc.close, doc) end
    return h
end

--- Pages `list` of the PDF at `path` as drawing screen pages: { new,
--- modified, scene, label }. `dir`: where the pictures are made (removed
--- after). Returns the pages, or nil and why.
function PdfMarkup.pages(path, list, dir)
    local doc, err = PdfMarkup.open(path)
    if not doc then return nil, err end
    local out = {}
    for _i, n in ipairs(list) do
        local png = dir .. "/pdf-page-" .. n .. ".png"
        local side, w, h, why, size, colour = PdfMarkup.MAX_SIDE, nil, nil, nil, nil, nil
        -- (a busy page, a scan: smaller until it's a size Memos and the Kindle handle well)
        for _try = 1, 3 do
            w, h, colour = doc.render(n, png, side)
            if not w then why = h; break end
            size = select(3, PdfMarkup.pngInfo(png)) or 0
            if size <= (colour and PdfMarkup.MAX_BYTES_COLOR or PdfMarkup.MAX_BYTES) then break end
            side = math.floor(side * 0.7)
        end
        if not w then
            doc.close()
            os.remove(png)
            return nil, "render", why
        end
        local scene = PdfMarkup.scene(png, w, h)
        os.remove(png)
        if not scene then doc.close(); return nil, "render" end
        out[#out + 1] = { new = true, modified = true, scene = scene, pdf_page = n, size = size, colour = colour == true }
    end
    doc.close()
    return out
end

--- What to tell the user when the pages couldn't be made.
function PdfMarkup.message(err)
    if err == "password" then return _("This PDF has a password, so its pages can't be marked up here.") end
    if err == "empty" then return _("This PDF has no pages.") end
    if err == "open" then return _("Couldn't open this PDF.") end
    return _("Couldn't prepare the PDF's pages.")
end

return PdfMarkup
