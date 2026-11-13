--[[--
Notepaper for drawings: a page's background, as Memos keeps one. In Memos'
drawing editor a background picture is an image element at (0, 0), at the
picture's stored size, below everything and locked (drawing over it never
moves it); its pixels are in the scene's `files` as a data URL.

The papers here (`notepaper/*.png`) are letter pages at Memos' stored size
(1113 × 1440: it keeps pictures at most 1440 px on their longest side).
]]

local Drawing = require("gzreader_drawing")
local _ = require("gettext")

local Notepaper = {}

Notepaper.DIR = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or ".") .. "/notepaper"
Notepaper.W, Notepaper.H = 1113, 1440

--- The papers, in the order the Paper button lists them.
Notepaper.LIST = {
    { id = "blank", label = _("Blank") },
    { id = "college", label = _("College ruled"), file = "college.png" },
    { id = "wide", label = _("Wide ruled"), file = "wide.png" },
    { id = "gregg", label = _("Gregg ruled"), file = "gregg.png" },
    { id = "dots", label = _("Dot grid"), file = "dots.png" },
    { id = "graph", label = _("Graph"), file = "graph.png" },
}

function Notepaper.get(id)
    for _i, p in ipairs(Notepaper.LIST) do if p.id == id then return p end end
end

local cache = {}
--- Paper `id`'s picture as a data URL (nil for blank, or a paper that's missing).
function Notepaper.dataURL(id)
    local p = Notepaper.get(id)
    if not (p and p.file) then return nil end
    if cache[id] then return cache[id] end
    local f = io.open(Notepaper.DIR .. "/" .. p.file, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    cache[id] = "data:image/png;base64," .. require("ffi/sha2").bin_to_base64(data)
    return cache[id]
end

--- Paper `id` as Memos keeps a background: the image element and its file
--- (nil for blank). `now`: milliseconds (the file's `created`).
function Notepaper.element(id, now)
    local url = Notepaper.dataURL(id)
    if not url then return nil end
    local file_id = Drawing.randomId()
    local el = {
        id = Drawing.randomId(), type = "image", x = 0, y = 0, width = Notepaper.W, height = Notepaper.H,
        angle = 0, strokeColor = "#1e1e1e", backgroundColor = "transparent", strokeWidth = 2, opacity = 100,
        isDeleted = false, groupIds = Drawing.list(), boundElements = Drawing.list(),
        seed = Drawing.randomSeed(), locked = true, fileId = file_id, scale = Drawing.list({ 1, 1 }),
    }
    local file = { mimeType = "image/png", dataURL = url, created = now or (os.time() * 1000) }
    return el, file_id, file
end

--- A new page's scene on paper `id` (a plain new scene for blank).
function Notepaper.scene(id)
    local scene = Drawing.newScene()
    local el, file_id, file = Notepaper.element(id)
    if el then
        scene.elements[1] = el
        scene.files[file_id] = file
    end
    return scene
end

--- True for a scene's background: a locked picture under everything (as
--- Memos makes one), or one of these papers.
function Notepaper.isBackground(scene, el)
    if type(el) ~= "table" or el.type ~= "image" or el.isDeleted then return false end
    if el.locked == true then
        for _i, x in ipairs(scene and scene.elements or {}) do
            if not x.isDeleted then return x == el end
        end
    end
    return Notepaper.idOf(scene, el) ~= nil
end

--- Which of these papers picture `el` is (its pixels), or nil.
function Notepaper.idOf(scene, el)
    local f = type(scene) == "table" and type(scene.files) == "table" and el and scene.files[el.fileId]
    local url = type(f) == "table" and f.dataURL
    if type(url) ~= "string" then return nil end
    for _i, p in ipairs(Notepaper.LIST) do
        if p.file and Notepaper.dataURL(p.id) == url then return p.id end
    end
end

--- The scene's background element, or nil.
function Notepaper.background(scene)
    for _i, el in ipairs(scene and scene.elements or {}) do
        if Notepaper.isBackground(scene, el) then return el end
    end
end

return Notepaper
