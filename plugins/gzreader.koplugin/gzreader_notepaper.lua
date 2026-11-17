--[[--
Notepaper for drawings: a page's background, as Memos keeps one. In Memos'
drawing editor a background picture is an image element at (0, 0), at the
picture's stored size, below everything and locked (drawing over it never
moves it); its pixels are in the scene's `files` as a data URL.

The papers here (`notepaper/*.png`) are letter pages at Memos' stored size
(1113 × 1440: it keeps pictures at most 1440 px on their longest side).
Your own: PNG files in `settings/gzreader-notepaper/` (at most 1440 px on
their longest side and 600 KB), listed after these by their file names.
]]

local Drawing = require("gzreader_drawing")
local _ = require("gettext")

local Notepaper = {}

Notepaper.DIR = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or ".") .. "/notepaper"
Notepaper.W, Notepaper.H = 1113, 1440

--- The papers, in the order the chooser lists them: the Kindle Scribe's
--- notebook templates (the owner, 2026-11-16). Made by
--- tools/gzreader/make_notepaper.py (graph, dots and checklist: earlier).
Notepaper.LIST = {
    { id = "blank", label = _("Blank") },
    { id = "ruled-medium", label = _("Medium ruled"), file = "ruled-medium.png" },
    { id = "ruled-medium-margin", label = _("Medium ruled with margin"), file = "ruled-medium-margin.png" },
    { id = "ruled-wide", label = _("Wide ruled"), file = "ruled-wide.png" },
    { id = "ruled-wide-margin", label = _("Wide ruled with margin"), file = "ruled-wide-margin.png" },
    { id = "ruled-narrow", label = _("Narrow ruled"), file = "ruled-narrow.png" },
    { id = "ruled-narrow-margin", label = _("Narrow ruled with margin"), file = "ruled-narrow-margin.png" },
    { id = "vertical", label = _("Vertical ruled"), file = "vertical.png" },
    { id = "vertical-margin", label = _("Vertical ruled with margin"), file = "vertical-margin.png" },
    { id = "graph", label = _("Graph"), file = "graph.png" },
    { id = "dots", label = _("Dotted"), file = "dots.png" },
    { id = "checklist", label = _("Checklist"), file = "checklist.png" },
    { id = "daily", label = _("Daily planner"), file = "daily.png" },
    { id = "weekly", label = _("Weekly planner"), file = "weekly.png" },
    { id = "monthly", label = _("Monthly planner"), file = "monthly.png" },
    { id = "habit", label = _("Habit tracker"), file = "habit.png" },
    { id = "storyboard", label = _("Storyboard"), file = "storyboard.png" },
    { id = "music", label = _("Music"), file = "music.png" },
}

--- The papers GZreader offered before these: no longer in the chooser, but
--- a page drawn on one is still known as it (and stays on it).
Notepaper.EARLIER = {
    { id = "college", label = _("College ruled"), file = "college.png" },
    { id = "wide", label = _("Wide ruled (punched)"), file = "wide.png" },
    { id = "gregg", label = _("Gregg ruled"), file = "gregg.png" },
    { id = "cornell", label = _("Cornell notes"), file = "cornell.png" },
}

Notepaper.MAX_SIDE, Notepaper.MAX_BYTES = 1440, 600 * 1024

--- Where your own papers go (nil when there's no settings folder: tests).
function Notepaper.ownDir()
    local ok, DataStorage = pcall(require, "datastorage")
    if not ok or not DataStorage then return nil end
    return DataStorage:getSettingsDir() .. "/gzreader-notepaper"
end

--- A PNG's width and height from its header (nil when it isn't one).
function Notepaper.pngSize(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local head = f:read(24)
    local size = f:seek("end")
    f:close()
    if not head or #head < 24 or head:sub(1, 8) ~= "\137PNG\r\n\26\n" then return nil end
    local function be(i) local a, b, c, d = head:byte(i, i + 3); return ((a * 256 + b) * 256 + c) * 256 + d end
    return be(17), be(21), size
end

--- Your own papers: { id = "own:<file>", label, path, w, h }, by name.
function Notepaper.own()
    local dir = Notepaper.ownDir()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not (dir and ok and lfs and lfs.attributes(dir, "mode") == "directory") then return {} end
    local out = {}
    for name in lfs.dir(dir) do
        if name:lower():match("%.png$") then
            local w, h, size = Notepaper.pngSize(dir .. "/" .. name)
            if w and w > 0 and h > 0 and math.max(w, h) <= Notepaper.MAX_SIDE and size <= Notepaper.MAX_BYTES then
                out[#out + 1] = { id = "own:" .. name, label = (name:gsub("%.[Pp][Nn][Gg]$", "")), path = dir .. "/" .. name,
                    w = w, h = h, own = true }
            end
        end
    end
    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
    return out
end

--- Every paper: Blank, the ones that come with GZreader, then your own.
function Notepaper.all()
    local out = {}
    for _i, p in ipairs(Notepaper.LIST) do out[#out + 1] = p end
    for _i, p in ipairs(Notepaper.own()) do out[#out + 1] = p end
    return out
end

function Notepaper.get(id)
    for _i, p in ipairs(Notepaper.LIST) do if p.id == id then return p end end
    for _i, p in ipairs(Notepaper.EARLIER) do if p.id == id then return p end end
    if type(id) == "string" and id:sub(1, 4) == "own:" then
        for _i, p in ipairs(Notepaper.own()) do if p.id == id then return p end end
    end
end

--- Paper `p`'s picture file (nil for blank).
function Notepaper.path(p)
    if not p then return nil end
    return p.path or (p.file and (Notepaper.DIR .. "/" .. p.file)) or nil
end

--- The small square picture the chooser shows for paper `p` (a corner of
--- the page, its lines darkened): nil for blank and for your own papers.
function Notepaper.tile(p)
    if not (p and p.file) then return nil end
    return Notepaper.DIR .. "/tiles/" .. p.file
end

local cache = {}
--- Paper `id`'s picture as a data URL (nil for blank, or a paper that's missing).
function Notepaper.dataURL(id)
    local p = Notepaper.get(id)
    local path = Notepaper.path(p)
    if not path then return nil end
    if cache[id] then return cache[id] end
    local f = io.open(path, "rb")
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
    local p = Notepaper.get(id)
    local el = {
        id = Drawing.randomId(), type = "image", x = 0, y = 0, width = p.w or Notepaper.W, height = p.h or Notepaper.H,
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
    for _i, p in ipairs(Notepaper.EARLIER) do
        if Notepaper.dataURL(p.id) == url then return p.id end
    end
    for _i, p in ipairs(Notepaper.own()) do
        if Notepaper.dataURL(p.id) == url then return p.id end
    end
end

--- The scene's background element, or nil.
function Notepaper.background(scene)
    for _i, el in ipairs(scene and scene.elements or {}) do
        if Notepaper.isBackground(scene, el) then return el end
    end
end

return Notepaper
