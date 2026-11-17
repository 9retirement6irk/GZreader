-- Mark up a PDF (gzreader_pdfmarkup.lua): the pages asked for, each PDF
-- page as a drawing page's background (a locked picture, as Memos keeps
-- one), smaller when its picture is too big, and the drawing screen taking
-- such pages.
--   luajit pdfmarkup_test.lua <gzreader.koplugin> <tests lib> <koreader base> <work dir>
local PLUGIN, LIB, KOROOT, WORK = arg[1], arg[2], arg[3], arg[4]
package.path = PLUGIN .. "/?.lua;" .. LIB .. "/?.lua;" .. KOROOT .. "/?.lua;" .. package.path
os.execute("mkdir -p '" .. WORK .. "'")

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

local dkjson = require("dkjson")
package.preload["json"] = function()
    return { decode = function(s) local v, _, err = dkjson.decode(s); if err then error(err) end; return v end,
        encode = function(v) return dkjson.encode(v) end }
end
package.preload["gettext"] = package.preload["gettext"] or function() return function(t) return t end end
package.preload["libs/libkoreader-lfs"] = package.preload["libs/libkoreader-lfs"] or function()
    return { attributes = function() return nil end, dir = function() return function() end end }
end

local PdfMarkup = require("gzreader_pdfmarkup")
local Notepaper = require("gzreader_notepaper")
local Sketch = require("gzreader_sketch")
local Drawing = require("gzreader_drawing")

local function readAll(p) local f = io.open(p, "rb"); if not f then return nil end; local d = f:read("*a"); f:close(); return d end
local function exists(p) local f = io.open(p, "rb"); if f then f:close() end; return f ~= nil end

print("== which attachments are PDFs")
;(function()
    check(PdfMarkup.isPdf({ type = "application/pdf", filename = "x" }) and PdfMarkup.isPdf({ filename = "Report.PDF" })
        and not PdfMarkup.isPdf({ type = "image/png", filename = "a.png" }) and not PdfMarkup.isPdf(nil),
        "a PDF by its type or its file name; a picture isn't one")
end)()

print("== the pages asked for")
;(function()
    local function pages(t, n, max) local l, why = PdfMarkup.parsePages(t, n, max); return l and table.concat(l, ",") or why end
    check(pages("3", 10) == "3" and pages("1-4", 10) == "1,2,3,4" and pages(" 2, 5 - 7 ", 10) == "2,5,6,7",
        "one page, a run, several (spaces allowed)")
    check(pages("2\u{2013}3", 5) == "2,3" and pages("4-2", 5) == "4,3,2" and pages("1,1,2-3,2", 5) == "1,2,3",
        "an en dash, a run backwards, each page once")
    check(pages("", 5) == "empty" and pages(" , ", 5) == "empty", "nothing typed: asks again")
    check(pages("0", 5) == "range" and pages("6", 5) == "range" and pages("2-9", 5) == "range" and pages("two", 5) == "range",
        "a page the PDF hasn't, or not a number: refused")
    check(pages("1-11", 20) == "many" and pages("1-10", 20) == "1,2,3,4,5,6,7,8,9,10" and pages("1-3", 20, 2) == "many",
        "at most " .. PdfMarkup.MAX_PAGES .. " pages at a time")
    check(PdfMarkup.suggest(1) == "1" and PdfMarkup.suggest(3) == "1-3" and PdfMarkup.suggest(40) == "1",
        "offered first: every page of a short PDF, else page 1")
end)()

print("== the page's picture size")
;(function()
    local z, w, h = PdfMarkup.fit(612, 792)
    check(math.abs(z - 1440 / 792) < 1e-9 and h == 1440 and w == 1113, "a letter page: 1113 x 1440, as the notepapers")
    local lw, lh = select(2, PdfMarkup.fit(842, 595, 1000))
    check(lw == 1000 and lh == 707, "a landscape page fits its long side")
end)()

-- a stand-in for MuPDF: pages of 612 x 792 points; writePNG copies a real PNG
local FIXTURE = LIB .. "/../media/memos-drawing.canvas.png" -- (a PNG that isn't a notepaper)
local BIG = WORK .. "/big.png"
do -- a "PNG" over the size limit (a real header, padding after it)
    local f = io.open(BIG, "wb")
    f:write(readAll(FIXTURE)); f:write(string.rep("\0", PdfMarkup.MAX_BYTES + 10)); f:close()
end
local log = { sides = {}, closed = 0, pages_closed = 0 }
local function fakeMupdf(opts)
    opts = opts or {}
    package.loaded["ffi/mupdf"] = {
        openDocument = function(path)
            if opts.fail_open then error("cannot open") end
            log.opened = path
            return {
                needsPassword = function() return opts.password == true end,
                getPages = function() return opts.count or 3 end,
                openPage = function(_d, n)
                    if opts.bad_page == n then error("cannot open page") end
                    return {
                        getSize = function(_p, dc) return 612 * dc.zoom, 792 * dc.zoom end,
                        draw_new = function(_p, dc, w, h)
                            log.sides[#log.sides + 1] = math.max(w, h)
                            log.zoom = dc.zoom
                            return { writePNG = function(_b, out_path)
                                local src = (opts.big_until and #log.sides <= opts.big_until) and BIG or FIXTURE
                                local f = io.open(out_path, "wb"); f:write(readAll(src)); f:close()
                            end, free = function() end }
                        end,
                        close = function() log.pages_closed = log.pages_closed + 1 end,
                    }
                end,
                close = function() log.closed = log.closed + 1 end,
            }
        end,
    }
    package.loaded["ffi/drawcontext"] = { new = function()
        return { zoom = 1, setZoom = function(self, z) self.zoom = z end }
    end }
end

print("== the PDF's pages as drawing pages")
;(function()
    fakeMupdf()
    local doc = PdfMarkup.open("/x/a.pdf")
    check(doc and doc.count == 3 and log.opened == "/x/a.pdf", "opened: its page count")
    doc.close()
    log.sides, log.closed = {}, 0
    local pages = PdfMarkup.pages("/x/a.pdf", { 3, 1 }, WORK)
    check(pages and #pages == 2 and pages[1].pdf_page == 3 and pages[2].pdf_page == 1 and pages[1].new and pages[1].modified,
        "each page asked for, in that order, as a new page to draw on")
    check(log.sides[1] == 1440 and math.abs(log.zoom - 1440 / 792) < 1e-9 and log.closed == 1 and log.pages_closed >= 2,
        "rendered at Memos' picture size (1440 on the long side); the PDF and its pages closed")
    check(not exists(WORK .. "/pdf-page-3.png") and not exists(WORK .. "/pdf-page-1.png"), "the pictures made on the way are gone")
    local scene = pages[1].scene
    local bg = scene.elements[1]
    check(#scene.elements == 1 and bg.type == "image" and bg.locked == true and bg.x == 0 and bg.y == 0
        and bg.width == 1113 and bg.height == 1440, "the page: a locked picture at (0, 0) at its size (a background, as Memos keeps one)")
    local file = scene.files[bg.fileId]
    check(file and file.mimeType == "image/png" and file.dataURL == "data:image/png;base64,"
        .. require("ffi/sha2").bin_to_base64(readAll(FIXTURE)), "its pixels in the drawing's files, as a data URL")
    check(Notepaper.isBackground(scene, bg) and Notepaper.background(scene) == bg, "…read as the page's background")
    local canvas = { x = 0, y = 52, w = 1072, h = 1396 }
    local sk = Sketch.fromScene(scene, { canvas = canvas, per_unit = 1 })
    local r = sk:pageRect()
    check(sk:isEmpty() and r and r.w <= canvas.w and r.h <= canvas.h and r.h > canvas.h * 0.9,
        "on the drawing screen: the page fills the screen, nothing drawn yet (left blank: not kept)")
    check(sk:paper() == "other", "…and it's not one of the notepapers")
    -- a stroke over it: kept, with the PDF's page still under it
    local t = 0
    for _i, f in ipairs({ { slot = 0, id = 10, x = 200, y = 300, tool = 0 }, { slot = 0, id = 10, x = 260, y = 340, tool = 0 },
        { slot = 0, id = 10, x = 320, y = 400, tool = 0 }, { slot = 0, id = -1, x = 0, y = 0, tool = 0 } }) do
        sk:frame({ f }, t); t = t + 0.02
    end
    check(not sk:isEmpty(), "drawn on: kept")
    local out = sk:scene()
    local kinds = {}
    for _i, el in ipairs(out.elements) do kinds[#kinds + 1] = el.type end
    check(table.concat(kinds, ",") == "image,freedraw" and out.files[bg.fileId] ~= nil
        and Drawing.decode(Drawing.encode(out)).files[bg.fileId].dataURL == file.dataURL,
        "the drawing saved: the PDF's page under the ink, its pixels kept")
end)()

print("== a page too big, a PDF that can't be used")
;(function()
    fakeMupdf({ big_until = 2 })
    log.sides = {}
    local pages = PdfMarkup.pages("/x/scan.pdf", { 1 }, WORK)
    check(pages and #pages == 1 and #log.sides == 3 and log.sides[2] < log.sides[1] and log.sides[3] < log.sides[2]
        and pages[1].size <= PdfMarkup.MAX_BYTES, "a picture over the limit: rendered smaller until it fits")
    fakeMupdf({ password = true })
    local p, why = PdfMarkup.pages("/x/locked.pdf", { 1 }, WORK)
    check(p == nil and why == "password" and PdfMarkup.message(why):find("password") ~= nil, "a PDF with a password: said so")
    fakeMupdf({ fail_open = true })
    p, why = PdfMarkup.pages("/x/broken.pdf", { 1 }, WORK)
    check(p == nil and why == "open", "a file MuPDF can't open: said so")
    fakeMupdf({ bad_page = 2 })
    log.closed = 0
    p, why = PdfMarkup.pages("/x/a.pdf", { 1, 2 }, WORK)
    check(p == nil and why == "render" and log.closed == 1 and not exists(WORK .. "/pdf-page-2.png"),
        "a page that can't be drawn: nothing kept, the PDF closed")
    fakeMupdf({ count = 0 })
    p, why = PdfMarkup.open("/x/empty.pdf")
    check(p == nil and why == "empty", "a PDF without pages: said so")
end)()

print("== the drawing screen and the editor take such pages")
;(function()
    local dsrc = readAll(PLUGIN .. "/gzreader_drawscreen.lua")
    check(dsrc:find("if p.scene then\n        -- (a page made ready elsewhere: a PDF's page to mark up)\n        p.sketch = self:newSketch(p.scene)", 1, true) ~= nil
        and dsrc:find("new = p.scene and true or nil, scene = p.scene, modified = p.scene and true or nil }", 1, true) ~= nil,
        "the drawing screen opens a page made ready (a PDF's page) as a new, changed page")
    local esrc = readAll(PLUGIN .. "/gzreader_noteeditor.lua")
    check(esrc:find("drawing_atts = atts, extra_pages = opts.extra_pages }", 1, true) ~= nil
        and esrc:find("page = page or (#list + 1)", 1, true) ~= nil
        and esrc:find("if extra and not self:changed() then return UIManager:close(self, \"full\") end", 1, true) ~= nil,
        "the editor puts them after the note's drawings, shows the first; Cancel at once leaves the note as it was")
end)()

print(string.format("pdf markup: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
