-- Mark up a PDF, on a touch Kindle: a note with a PDF attached, Mark up
-- pages, pages 1-2, the drawing screen on the PDF's pages (rendered by the
-- Kindle's MuPDF), a stroke on page 1, Done, Save, sent to Memos
-- (demo/mock_memos.py on 18090) as a drawing with the PDF's page under it.
--   python3 -I demo/mock_memos.py 18090 &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh pdf_markup.lua <out>
-- Checks go to <out>/pdf-markup-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function fm() return require("apps/filemanager/filemanager").instance end
local function plugin() return fm() and fm().gzreader end
local function find(name) for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == name then return w.widget end end end
local function editor() for _i, w in ipairs(UIM()._window_stack) do if w.widget.input and w.widget.on_save then return w.widget end end end
local function screen() return find("gz_drawscreen") end
local W, H
local function pt(fx, fy) return { math.floor(W * fx), math.floor(H * fy) } end
local function wave(fx0, fy, fx1)
    local out = {}
    for i = 0, 12 do out[#out + 1] = pt(fx0 + (fx1 - fx0) * i / 12, fy + 0.03 * math.sin(i / 2)) end
    return out
end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
    end
end

-- a small PDF of two pages (letter, then A4 sideways): text and a box
local function writePdf(path)
    local content = "BT /F1 36 Tf 72 700 Td (Chapter 3 questions) Tj ET 72 72 468 300 re S 0.85 0.1 0.1 rg 100 420 200 120 re f"
    local objs = {
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        "<< /Length " .. #content .. " >>\nstream\n" .. content .. "\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 842 595] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    }
    local out, offs = { "%PDF-1.4\n" }, {}
    local len = #out[1]
    for i, o in ipairs(objs) do
        offs[i] = len
        local chunk = i .. " 0 obj\n" .. o .. "\nendobj\n"
        out[#out + 1] = chunk
        len = len + #chunk
    end
    local xref = { "xref\n0 " .. (#objs + 1) .. "\n0000000000 65535 f \n" }
    for _i, o in ipairs(offs) do xref[#xref + 1] = string.format("%010d 00000 n \n", o) end
    out[#out + 1] = table.concat(xref)
    out[#out + 1] = "trailer\n<< /Size " .. (#objs + 1) .. " /Root 1 0 R >>\nstartxref\n" .. len .. "\n%%EOF\n"
    local f = io.open(path, "wb")
    f:write(table.concat(out))
    f:close()
end

local memo
add({ fn = function(E)
    local Device = require("device")
    W, H = Device.screen:getWidth(), Device.screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    local Memos = require("gzreader_memos")
    local Notes = require("gzreader_notes")
    local client = Memos:new(p.store.memos)
    memo = client:create("Homework: mark up the PDF", "PRIVATE")
    check(memo and memo.name, "a note in Memos (" .. tostring(memo and memo.name) .. ")")
    local att = { name = "attachments/pdf-markup-test", filename = "chapter3.pdf", type = "application/pdf" }
    memo.attachments = { att }
    local path = Memos.filePath(att)
    os.execute("mkdir -p '" .. path:match("^(.*)/[^/]*$") .. "'")
    writePdf(path)
    check(Notes.canMarkUp(p, memo, att), "a PDF on a note can be marked up here")
    local dlg = Notes.tapAttachment(p, memo, att)
    check(dlg and dlg.title == "chapter3.pdf", "a tap on it asks Open or Mark up pages")
    E.memo_att = att
end, after = 1.5 })
add({ shot = "1-open-or-mark-up", after = 0.5 })
add({ fn = function(E) E.tap("Mark up pages") end, after = 2 })
add({ shot = "2-which-pages", after = 0.5 })
add({ fn = function(E)
    local d = require("gzreader_notes").markup_dialog
    check(d ~= nil, "Mark up pages: which pages")
    d:setInputText("1-2")
    for _i, row in ipairs(d.buttons or {}) do
        for _j, b in ipairs(row) do if b.text == "Mark up" then b.callback() end end
    end
end, after = 4 })
add({ shot = "3-pdf-page", after = 1 })
add({ fn = function(E)
    local d = screen()
    local r = d and d.sketch:pageRect()
    check(d and #d.pages == 2 and d.index == 1 and r and r.h > (H - 52) * 0.8,
        "the drawing screen on the PDF's two pages, the first filling the screen")
    check(d and d.color_bb ~= nil, "…the PDF's page drawn under the page (" .. tostring(r and (math.floor(r.w) .. "x" .. math.floor(r.h))) .. ")")
    E.finger(wave(0.2, 0.3, 0.8), 0.4)
end, after = 2 })
add({ fn = function(E)
    check(screen() and #screen().sketch:live() == 1, "a stroke over the PDF's page")
    screen():showPage(2)
end, after = 2 })
add({ shot = "4-pdf-page-2-landscape", after = 0.5 })
add({ fn = function(E) E.tap(button("done")) end, after = 4 })
add({ fn = function(E)
    local e = editor()
    local changes = e and e:drawingChanges() or {}
    local Drawing = require("gzreader_drawing")
    local scene = changes[1] and Drawing.readFile(changes[1].path)
    local kinds = {}
    for _i, el in ipairs(scene and scene.elements or {}) do kinds[#kinds + 1] = el.type end
    check(screen() == nil and #changes == 1, "Done: back at the note, only the page drawn on kept (" .. #changes .. ")")
    check(table.concat(kinds, ",") == "image,freedraw" and scene.elements[1].locked == true,
        "the drawing: the PDF's page (locked, underneath) and the stroke (" .. table.concat(kinds, ",") .. ")")
    -- a colour PDF stays in colour: the red box, in the page kept in the drawing and in the picture sent
    local function redAt(path)
        local ok, res = pcall(function()
            local okd, img = require("ffi/png").decodeFromFile(path, 3)
            if not okd or not img then return nil end
            local d = require("ffi").cast("uint8_t*", img.data)
            local n = 0
            for i = 0, img.width * img.height - 1 do
                if d[i * 3] > 150 and d[i * 3 + 1] < 90 and d[i * 3 + 2] < 90 then n = n + 1 end
            end
            return n
        end)
        return ok and res or nil
    end
    local sent_red = changes[1] and redAt(changes[1].path)
    check(sent_red and sent_red > 2000, "the picture for Memos: the PDF's red box is red (" .. tostring(sent_red) .. " red pixels; it was grey)")
    if changes[1] then os.execute("cp '" .. changes[1].path .. "' '" .. E.out .. "/markup-sent.canvas.png'") end
    e:save()
end, after = 1 })
add({ wait_for = function()
    local q = plugin().store.memos.queue
    return q and #q == 0
end, timeout = 25 })
add({ fn = function(E)
    local q = plugin().store.memos.queue or {}
    check(#q == 0, "sent to Memos (queue empty: " .. #q .. ")")
    local Memos = require("gzreader_memos")
    local client = Memos:new(plugin().store.memos)
    local list = client:list(nil, nil, 20)
    local found
    for _i, m in ipairs(list and list.memos or {}) do if m.name == memo.name then found = m end end
    local drawing
    for _i, a in ipairs(found and found.attachments or {}) do
        if tostring(a.filename):match("%.canvas%.png$") then drawing = a end
    end
    check(drawing ~= nil, "in Memos: the marked-up page on the note")
    local f = io.open(E.out .. "/pdf-markup-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
