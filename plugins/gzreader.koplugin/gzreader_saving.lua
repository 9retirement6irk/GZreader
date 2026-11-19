--[[--
Saving a note or a drawing, so the Kindle never looks frozen, and nothing
typed is lost:

- `Saving.show(text)`: a small "Saving…" box in the middle of the screen,
  on the screen at once (before the slow part starts: a drawing's pages
  made into pictures, the Notes tab drawn again). `Saving.close(box)`.
- Drafts: what's being written in the note editor, kept on the Kindle
  every few seconds (`Saving.writeDraft`), so a crash, a flat battery or a
  restart doesn't lose it; the next time that note (or a new note) is
  opened, it's offered back (`Saving.readDraft`). Saved or thrown away:
  the draft goes (`Saving.dropDraft`).

A draft is { text, visibility, at }, in <settings>/gzreader-drafts/<key>.json;
the key is the note's name in Memos ("memos/abc"), or "new" for a new note.
Drafts aren't sent anywhere.
]]

local Saving = {}

Saving.DRAFT_EVERY = 5 -- seconds between looks at what's typed (written only when it changed)
Saving.DRAFT_DAYS = 14 -- a draft older than this is let go
Saving.MIN_SHOWN = 0.6 -- seconds "Saving…" stays after a note is handed over (what's under it is drawn again meanwhile)

-- ------------------------------------------------------------------ drafts

function Saving.dir()
    if Saving._dir then return Saving._dir end
    local ok, DataStorage = pcall(require, "datastorage")
    local base = ok and DataStorage:getSettingsDir() or "."
    return base .. "/gzreader-drafts"
end

--- The file for note `key` (its name in Memos, or "new"): only letters, digits, - and _ in it.
function Saving.draftPath(key)
    local k = tostring(key or "new"):gsub("[^%w%-_]", "_")
    return Saving.dir() .. "/" .. k .. ".json"
end

function Saving.keyOf(memo) return (memo and memo.name) or "new" end

--- Keeps `draft` ({ text, visibility }) for `key`. True when written.
function Saving.writeDraft(key, draft, now)
    local dir = Saving.dir()
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok_lfs and lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    if not ok_lfs then os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "'") end
    local Json = require("gzreader_json")
    local body = Json.encode({ text = draft.text or "", visibility = draft.visibility, at = now or os.time() })
    local path = Saving.draftPath(key)
    -- (written beside it, then moved over it: a crash mid-write leaves the old one whole)
    local f = io.open(path .. ".tmp", "w")
    if not f then return false end
    f:write(body)
    f:close()
    return os.rename(path .. ".tmp", path) ~= nil
end

--- The draft kept for `key`, or nil (none, unreadable, or older than DRAFT_DAYS).
function Saving.readDraft(key, now)
    local f = io.open(Saving.draftPath(key), "r")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    local ok, d = pcall(require("gzreader_json").decode, body)
    if not ok or type(d) ~= "table" or type(d.text) ~= "string" then return nil end
    if tonumber(d.at) and (now or os.time()) - tonumber(d.at) > Saving.DRAFT_DAYS * 86400 then
        Saving.dropDraft(key)
        return nil
    end
    return d
end

function Saving.dropDraft(key) os.remove(Saving.draftPath(key)) end

--- Whether `draft` is worth offering against what the note has now
--- (`text`): something in it, and not the same.
function Saving.differs(draft, text)
    if not draft then return false end
    local a = (draft.text or ""):gsub("%s+$", "")
    local b = (text or ""):gsub("%s+$", "")
    return a ~= "" and a ~= b
end

-- -------------------------------------------------------------- the box

--- "Saving…" (or `text`) in a small box in the middle, on the screen now.
function Saving.show(text)
    local UIManager = require("ui/uimanager")
    local ok, InfoMessage = pcall(require, "ui/widget/infomessage")
    if not ok then return nil end
    local _ = require("gettext")
    local box = InfoMessage:new{ text = text or _("Saving…"), show_icon = false, dismissable = false,
        name = "gz_saving" }
    UIManager:show(box, "ui")
    -- (painted before the slow part: without this, the screen shows nothing until it's done)
    UIManager:forceRePaint()
    Saving.shown = (Saving.shown or 0) + 1
    return box
end

function Saving.close(box)
    if not box then return end
    local UIManager = require("ui/uimanager")
    UIManager:close(box, "ui")
end

return Saving
