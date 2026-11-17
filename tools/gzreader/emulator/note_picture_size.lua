-- A picture's size in a note, as Memos' web editor sets it (`![alt|320](…)`,
-- `![alt|center|320](…)`): the note's page shows it that share of the page
-- and in its place; in the note editor (the formatted page) it shows as the
-- picture, a tap picks it (a frame and a pull tab on each side), and
-- dragging a tab sizes it; Save sends it, written as the web editor writes it.
--   python3 -I demo/mock_memos.py 18090 &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh note_picture_size.lua <out>
-- Checks go to <out>/note-picture-size-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local PHOTO = here .. "/../tests/media/cover.jpg"
local note, c
local function find(test) for _i, w in ipairs(UIM()._window_stack) do if test(w.widget) then return w.widget end end end
local function view() return find(function(w) return w.memo and w.picks end) end
local function editor() return find(function(w) return w.rich_input end) end
-- the picture on the note's page: its box
local function pictureBox()
    local v = view()
    local found
    local function walk(w)
        if type(w) ~= "table" or found then return end
        if w.image and w.dimen then found = w; return end
        for _i, k in ipairs(w) do walk(k) end
    end
    walk(v and v[1])
    return found
end
local function pageInner() return require("device").screen:getWidth() - 2 * require("device").screen:scaleBySize(24) end
local function picLine(r) for _i, l in ipairs(r.lines) do if l.picture then return l end end end
-- a point of the formatted page (widget coordinates) on the screen
local function onScreen(r, x, y) return { r.dimen.x + x, r.dimen.y + y } end

add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    local Memos = require("gzreader_memos")
    c = Memos:new(p.store.memos)
    note = c:create("# Beach day\nThe sea was calm.", "PRIVATE")
    local a = note and c:uploadAttachment(PHOTO, "beach.jpg", note.name)
    local uid = a and tostring(a.name):match("attachments/(.+)$")
    check(uid ~= nil, "a note with a photo in Memos")
    note = c:update(note.name, "# Beach day\n![The sea|center|320](/file/attachments/" .. tostring(uid) .. "/beach.jpg)\nThe sea was calm.")
    check(note and note.content:match("|center|320%]"), "its photo sized in Memos' web editor: centred, 320 wide")
    require("gzreader_notes").show(p)
end, after = 6 })
add({ fn = function(E)
    local Notes = require("gzreader_notes")
    local m
    for _i, n in ipairs(Notes.notes or {}) do if n.name == note.name then m = n end end
    check(m ~= nil, "the note is on the board")
    Notes.showNote(plugin(), m)
end, after = 6 })
add({ shot = "1-page-medium-centred", after = 1 })
add({ fn = function(E)
    local box = pictureBox()
    local inner = pageInner()
    local want = math.floor(320 * inner / 640 + 0.5)
    local w = box and box.dimen.w
    check(w and math.abs(w - want) <= 3, "the note's page: half the page wide (" .. tostring(w) .. " for " .. want .. ")")
    local left = box and box.dimen.x - require("device").screen:scaleBySize(24)
    check(left and math.abs(left - math.floor((inner - w) / 2)) <= 3, "…and centred (" .. tostring(left) .. " from the margin)")
    local v = view()
    local n_pic = 0
    for _i, pk in ipairs(v.picks or {}) do if pk.picture then n_pic = n_pic + 1 end end
    check(n_pic == 0, "the picture isn't sized on the note's page (only in the editor)")
    v:onEdit()
end, after = 6 })
add({ shot = "2-editor", after = 1 })
add({ fn = function(E)
    local e = editor()
    local r = e and e.rich_input
    local l = r and picLine(r)
    local want = l and math.floor(320 * r.width / 640 + 0.5)
    check(l and math.abs(l.picture.w - want) <= 1, "the editor shows the picture, half its page wide (" .. tostring(l and l.picture.w) .. ")")
    check(l and math.abs(l.picture.x - math.floor((r.width - l.picture.w) / 2)) <= 1, "…centred")
    if l then
        local p = onScreen(r, l.picture.x + math.floor(l.picture.w / 2), l.y - r.top + math.floor(math.min(l.h, r.height - (l.y - r.top)) / 2))
        E.tap(p)
    end
end, after = 3 })
add({ shot = "3-picked", after = 1 })
add({ fn = function(E)
    local r = editor().rich_input
    local t = r:tabs()
    check(r.picked ~= nil and t ~= nil, "a tap picks it: its frame and pull tabs")
    -- drag the right tab out by a sixth of the page, slowly (a pan)
    local x0, y0 = t.right.x + math.floor(t.right.w / 2), t.right.y + math.floor(t.right.h / 2)
    local pts = {}
    local dx = math.floor(r.width / 6)
    for k = 0, 6 do pts[#pts + 1] = onScreen(r, x0 + math.floor(dx * k / 6), y0) end
    E.say("drag", x0, y0, dx)
    E.finger(pts, 1.5)
end, after = 4 })
add({ shot = "4-dragged", after = 1 })
add({ fn = function(E)
    local e = editor()
    local r = e.rich_input
    local txt = r:getText()
    local w = tonumber(txt:match("!%[The sea|center|(%d+)%]"))
    E.say("after drag", txt)
    -- (out by a sixth on the right, centred: a third wider, 320 → about 533)
    check(w and w > 450 and w < 600, "the tab dragged out: wider, written as Memos does (|center|" .. tostring(w) .. ")")
    local l = picLine(r)
    check(l and w and math.abs(l.picture.w - math.floor(w * r.width / 640 + 0.5)) <= 2, "…and shown at that width")
    e:save()
end, after = 6 })
add({ fn = function(E)
    local now = c:get(note.name)
    local w = now and tonumber(now.content:match("!%[The sea|center|(%d+)%]"))
    check(w and w > 450 and now.content:match("^# Beach day\n") and now.content:match("The sea was calm%.$"),
        "Save: the note in Memos has the new size, the rest as it was")
end, after = 0.5 })
add({ shot = "5-page-after", after = 1 })
add({ fn = function(E)
    local f = io.open(E.out .. "/note-picture-size-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
