-- A note's page in the note editor's font (KOReader's, as gzreader_richedit
-- uses), the Notes tab's sticky notes in the handwriting font: a note opened
-- on its own (no Memos needed), its text, heading, task and tags; then a
-- sticky note drawn as the Notes tab draws it.
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh note_font.lua <out>
-- Checks go to <out>/note-font-checks.txt.
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function fm() return require("apps/filemanager/filemanager").instance end
-- every text face in a widget tree: { [font file name] = count }
local function faces(w)
    local seen, out = {}, {}
    local function walk(x, depth)
        if type(x) ~= "table" or seen[x] or depth > 40 then return end
        seen[x] = true
        local f = rawget(x, "face")
        if type(f) == "table" and (rawget(x, "text") or rawget(x, "charlist")) then
            local name = tostring(f.realname or f.orig_font or "?"):match("[^/]+$") or "?"
            out[name] = (out[name] or 0) + 1
        end
        for k, v in pairs(x) do
            if type(v) == "table" and k ~= "parent" and k ~= "show_parent" and k ~= "plugin" and k ~= "memo" and k ~= "menu" then
                walk(v, depth + 1)
            end
        end
    end
    walk(w, 0)
    return out
end
local function list(t) local o = {}; for k, n in pairs(t) do o[#o + 1] = k .. "×" .. n end; table.sort(o); return table.concat(o, ", ") end

local memo = { name = "memos/font", created = os.time(), content = "# Weekend plan\n\nPack the tent and the maps.\n\n- [ ] stove\n\n#trip", tags = { "trip" } }
add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    E.view = require("gzreader_notes").showNote(fm().gzreader, memo)
end, after = 3 })
add({ shot = "1-note-page", after = 0.5 })
add({ fn = function(E)
    local Sticky = require("gzreader_sticky")
    local hand = tostring(Sticky.fontName() or "PatrickHand"):match("[^/]+$")
    local f = faces(E.view)
    E.say("note page faces", list(f))
    check(not f[hand], "the note's page: no handwriting font (" .. list(f) .. ")")
    -- (the editor's face: RichEdit.face, KOReader's cfont — ZenOS's Hyperreadable — and Noto Sans Bold)
    local RE = require("gzreader_richedit")
    local body = tostring(RE.face(RE.TEXT_SIZE).realname or ""):match("[^/]+$") or "?"
    local bold = tostring(RE.face(RE.HEADING_SIZE[1], true).realname or ""):match("[^/]+$") or "?"
    check((f[body] or 0) >= 2 and (f[bold] or 0) >= 2,
        "…its text and task in the editor's font (" .. body .. "), the heading and tags in its bold (" .. bold .. ")")
    UIM():close(E.view)
    -- a sticky note as the Notes tab draws it
    local Notes = require("gzreader_notes")
    local item = Notes._StickyItem:new{ entry = { memo = memo, text = memo.content }, menu = { plugin = fm().gzreader, _gz_keyed = {} },
        look = require("gzreader_sticky").look(1), dimen = require("ui/geometry"):new{ w = 300, h = 300 } }
    -- (a sticky note is drawn into a picture: its frame, as it's built)
    local frame = item:compactNote(memo, 300, 300)
    local cf = faces(frame)
    E.say("sticky note faces", list(cf))
    check((cf[hand] or 0) >= 1, "a sticky note on the Notes tab: still the handwriting font (" .. list(cf) .. ")")
    local fh = io.open(E.out .. "/note-font-checks.txt", "w")
    if fh then fh:write(table.concat(lines, "\n") .. "\n"); fh:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
