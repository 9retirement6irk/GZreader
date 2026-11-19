--[[--
A drawing kept as it's drawn, so a drawing that was never saved comes back.

Until 1.34 a drawing was only written to the Kindle by Save (or Done, or ←
back to a journal entry). When GZreader ended before that (it stopped
answering, the battery ran out, it crashed), everything drawn since was
lost. Now the drawing screen writes every page it has, as Memos' scene
text, to a file of its own (`gzreader-drawings/unsaved-<id>.json`):

- after a pause in the drawing (`PAUSE` seconds without a new stroke), at
  most every `EVERY` seconds, and at once when the Kindle goes to sleep;
- never while the pen is on the page or has moved in the last `QUIET`
  seconds, and in a background process (Draft.writeLater): written on the
  screen's thread, a page of handwriting took a second or more on a Kindle,
  and the pen put down in that time froze and its stroke came out wrong
  (the owner, 2026-11-18). Going to sleep and leaving the drawing still
  write at once (Draft.write);
- crossed off when the drawing is saved or left on purpose (Discard).

A journal entry's drawing goes on being kept, with the entry's mood, tags
and words, after ← back to the entry, until the entry is saved or closed.

The next time GZreader starts it asks: Open it (the journal entry again,
with its drawing; or a new drawing note with the pages), Later (asked
again at the next start), or Delete.

  { v = 1, at, kind = "journal" | "note", title, pages = { scene, … },
    journal = { state = { valence, feelings, impacts, activities, kind, body, prompt, prompt_i, goals } } }
]]

local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local Draft = {
    PAUSE = 3, -- (s) without a new stroke: the drawing kept
    EVERY = 30, -- (s) at most this often
    LONGEST = 90, -- (s) drawing without a pause: kept anyway (between strokes)
    QUIET = 1.5, -- (s) since the pen (or a finger) last moved, hovering too
    RETRY = 1, -- (s) not quiet yet, or a background job busy: looked at again
    gen = {}, -- id → how many times written or crossed off (a later one wins)
    cleared = {}, -- id → crossed off: a background copy still on its way is dropped
    DELAY = 7, -- (s) after GZreader starts: asked about one left from before
    PREFIX = "unsaved-",
    asked = false,
}

--- A new drawing's id: when it was started, and a few letters (two in one second).
function Draft.newId()
    return os.date("%Y%m%d-%H%M%S") .. "-" .. require("gzreader_drawing").randomId(4)
end

--- Where drawings wait to go to Memos (gzreader_drawscreen's dir; not loaded for this at start).
function Draft.dir()
    -- (beside the drawings waiting to go to Memos: GZreader/notes/drawings; before 1.35 the app's settings)
    local dir = require("gzreader_places").notes("drawings", require("datastorage"):getSettingsDir() .. "/gzreader-drawings")
    lfs.mkdir(dir)
    return dir
end

function Draft.path(id)
    return Draft.dir() .. "/" .. Draft.PREFIX .. tostring(id):gsub("[^%w%-]", "") .. ".json"
end

--- The ids of the drawings left unsaved, oldest first.
function Draft.list()
    local dir = Draft.dir()
    local ids = {}
    for name in lfs.dir(dir) do
        local id = name:sub(1, #Draft.PREFIX) == Draft.PREFIX and name:sub(#Draft.PREFIX + 1):match("^([%w%-]+)%.json$")
        if id then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

--- The journal entry's state worth keeping (no widgets, no functions).
local STATE_FIELDS = { "valence", "feelings", "impacts", "activities", "kind", "body", "prompt", "prompt_i", "goals" }
function Draft.entryState(st)
    if type(st) ~= "table" then return nil end
    local out = {}
    for _i, k in ipairs(STATE_FIELDS) do
        local v = st[k]
        if type(v) ~= "function" and type(v) ~= "userdata" then out[k] = v end
    end
    return out
end

--- Writes `rec` ({ kind, title, pages = { scene, … }, journal }) as the
--- drawing left unsaved. Each page's scene is Memos' own scene text. true or nil, err.
function Draft.write(id, rec)
    Draft.gen[id] = (Draft.gen[id] or 0) + 1
    Draft.cleared[id] = nil
    return Draft.writeFile(id, rec, Draft.path(id) .. ".tmp", true)
end

--- The file itself: `rec` as text in `tmp`, then moved over the draft (`rename`).
function Draft.writeFile(id, rec, tmp, rename)
    local Drawing = require("gzreader_drawing")
    local Json = require("gzreader_json")
    local parts = {}
    for i, scene in ipairs(rec.pages or {}) do
        local ok, text = pcall(Drawing.encode, scene)
        if not ok then return nil, "page " .. i .. ": " .. tostring(text) end
        parts[#parts + 1] = text
    end
    if #parts == 0 then return nil, "no pages" end
    local head = Json.encode({ v = 1, at = rec.at or os.time(), kind = rec.kind or "note", title = rec.title,
        journal = rec.journal })
    -- (the pages as they are: Memos' scene text, put in as it is)
    local text = head:sub(1, -2) .. ',"pages":[' .. table.concat(parts, ",") .. "]}"
    local path = Draft.path(id)
    local f, err = io.open(tmp, "wb")
    if not f then return nil, err end
    local ok, werr = f:write(text)
    f:close()
    if not ok then os.remove(tmp); return nil, werr end
    if rename then
        local moved, merr = os.rename(tmp, path)
        if not moved then os.remove(tmp); return nil, merr end
    end
    return true, #text
end

--- Draft.write in a background process (gzreader_async): `make()` (run there,
--- on a copy of everything as it is now) returns the record. Moved over the
--- draft here once it's done, unless the draft was written since (that copy is
--- newer) or crossed off. on_done(ok, bytes_or_why, pages, seconds): why
--- "busy" (another background job: try again later), "stale" or an error.
function Draft.writeLater(id, make, on_done)
    on_done = on_done or function() end
    Draft.gen[id] = (Draft.gen[id] or 0) + 1
    local gen = Draft.gen[id]
    local tmp = Draft.path(id) .. ".bg"
    require("gzreader_async").background(function()
        local t0 = os.time()
        local rec = make()
        local ok, n = Draft.writeFile(id, rec, tmp, false)
        return ok or false, n, #(rec.pages or {}), os.time() - t0
    end, function(ok, n, pages, took)
        if not ok then
            os.remove(tmp)
            return on_done(nil, n)
        end
        if Draft.gen[id] ~= gen or Draft.cleared[id] then
            os.remove(tmp)
            return on_done(nil, "stale")
        end
        local moved, merr = os.rename(tmp, Draft.path(id))
        if not moved then os.remove(tmp); return on_done(nil, merr) end
        on_done(true, n, pages, took)
    end, "keep a drawing", { timeout = 120 })
end

--- The drawing left unsaved: { at, kind, title, pages = { scene, … }, journal }, or nil.
function Draft.read(id)
    local f = io.open(Draft.path(id), "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    local ok, rec = pcall(require("gzreader_json").decode, text)
    if not ok or type(rec) ~= "table" or type(rec.pages) ~= "table" then return nil, "unreadable" end
    -- (each page checked as Memos checks a scene)
    local Drawing = require("gzreader_drawing")
    local pages = {}
    for _i, scene in ipairs(rec.pages) do
        local back = Drawing.checked(scene)
        if back then pages[#pages + 1] = back end
    end
    if #pages == 0 then return nil, "no pages" end
    rec.pages = pages
    return rec
end

function Draft.exists(id)
    return id ~= nil and lfs.attributes(Draft.path(id), "mode") == "file"
end

function Draft.clear(id, why)
    if id ~= nil then
        Draft.gen[id] = (Draft.gen[id] or 0) + 1
        Draft.cleared[id] = true
        os.remove(Draft.path(id) .. ".bg")
    end
    if Draft.exists(id) then
        os.remove(Draft.path(id))
        Log.info("drawing: the copy kept as it was drawn crossed off (" .. tostring(why or "saved") .. ")")
    end
end

-- -------------------------------------------------------------- after a restart

--- How the question reads: when it was drawn, and what.
function Draft.describe(rec)
    local when = os.date("%H:%M", rec.at or 0)
    if os.date("%Y-%m-%d", rec.at or 0) ~= os.date("%Y-%m-%d") then
        when = os.date("%b %d, %H:%M", rec.at or 0):gsub(" 0", " ")
    end
    local n = #rec.pages
    local pages = n == 1 and _("1 page") or T(_("%1 pages"), n)
    if rec.kind == "journal" then
        return T(_("A journal entry's drawing from %1 wasn't saved (%2). GZreader kept it."), when, pages)
    end
    return T(_("A drawing from %1 wasn't saved (%2). GZreader kept it."), when, pages)
end

--- Opens it again: the journal entry (its mood, tags, words and drawing, the
--- drawing on the screen), or a new drawing note with its pages. It stays
--- kept (under the same id) until that's saved or left.
function Draft.open(plugin, id, rec)
    local pages = {}
    for _i, scene in ipairs(rec.pages) do pages[#pages + 1] = { new = true, modified = true, scene = scene } end
    if rec.kind == "journal" then
        local j = require("gzreader_notes").journal(plugin)
        if type(j) ~= "table" or not j.state then return end
        local st = rec.journal and rec.journal.state
        if type(st) == "table" then
            for k, v in pairs(Draft.entryState(st) or {}) do j.state[k] = v end
        end
        j.pages, j.draft_id = pages, id
        j:rebuild() -- (the words' box made again with the words: drawing keeps what's in it)
        Log.info("drawing: an unsaved journal drawing opened again,", #pages, "page(s)")
        j:startDrawing()
        return j
    end
    Log.info("drawing: an unsaved drawing opened again as a new note,", #pages, "page(s)")
    -- (a new drawing note: its pages ready to draw on, named and tagged after Done)
    Draft.reopened = id
    return require("gzreader_notes").edit(plugin, nil, { draw = true, markup_pages = pages })
end

--- Ask about the drawings `ids`, one after another.
function Draft.ask(plugin, ids, i)
    i = i or 1
    local id = ids[i]
    if not id then return end
    local function nextOne() UIManager:nextTick(function() Draft.ask(plugin, ids, i + 1) end) end
    local rec, err = Draft.read(id)
    if not rec then
        Log.warn("drawing: a copy kept as it was drawn can't be read (" .. tostring(err) .. "): kept aside as .bad")
        os.rename(Draft.path(id), Draft.path(id) .. ".bad")
        return nextOne()
    end
    Log.info("drawing: an unsaved", rec.kind, "drawing from before,", #rec.pages, "page(s)")
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    dialog = ButtonDialog:new{
        title = Draft.describe(rec),
        buttons = {
            {{ text = _("Open it"), callback = function()
                UIManager:close(dialog)
                Draft.open(plugin, id, rec)
            end }},
            {{ text = _("Later"), callback = function() UIManager:close(dialog); nextOne() end }},
            {{ text = _("Delete it"), callback = function()
                UIManager:close(dialog)
                UIManager:show(require("ui/widget/confirmbox"):new{
                    text = _("Delete the drawing that wasn't saved? It can't be brought back."),
                    ok_text = _("Delete"),
                    ok_callback = function() Draft.clear(id, "deleted"); nextOne() end,
                    cancel_callback = nextOne,
                })
            end }},
        },
    }
    Draft.dialog = dialog
    UIManager:show(dialog)
end

--- Once a run, a few seconds after GZreader starts: drawings left unsaved? Ask.
function Draft.check(plugin)
    if Draft.asked then return end
    Draft.asked = true
    local ids = Draft.list()
    if #ids == 0 then return end
    Draft.ask(plugin, ids)
end

function Draft.schedule(plugin)
    if Draft.asked or Draft.pending then return end
    if #Draft.list() == 0 then Draft.asked = true; return end
    Draft.pending = true
    UIManager:scheduleIn(Draft.DELAY, function()
        Draft.pending = nil
        pcall(Draft.check, plugin)
    end)
end

return Draft
