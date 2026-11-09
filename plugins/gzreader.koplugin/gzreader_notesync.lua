--[[--
Notes (a highlight's note on the Kindle) <-> Grimmory's notes (the Notes tab
of its web reader: /api/v2/book-notes, one note per CFI range).

Grimmory keeps a highlight's note in the highlight too (gzreader_annosync
sends it), but its web reader never shows that field: what it shows as notes
are these separate records. So every note on the Kindle is also kept as one
of them, at the highlight's own CFI, and notes made in the web reader come to
the Kindle (on the highlight at that place, or as a highlight of their own,
`grimmory_note_only`, which isn't sent to Grimmory as a highlight).

Everything is matched by CFI. A three-way merge against the state both had
after the last clean pass (`entry.note_shadow` = { [cfi] = { id, note } }):
changed on one side -> copied to the other; changed on both -> a conflict,
left alone on both until one side matches again. Deleting a highlight with a
note on the Kindle deletes its Grimmory note.

The plan and the merge are plain functions (tested on their own); the
requests run in gzreader_annotations' background job.
]]

local NS = {}

local function s(v) return type(v) == "string" and v or nil end
local function text(v) local t = s(v); return t ~= "" and t or nil end
NS.text = text

--- Remote notes -> { [cfi] = { id, note, text, chapter, color } } (first of a CFI wins).
function NS.byCfi(remote)
    local out = {}
    for _i, r in ipairs(type(remote) == "table" and remote or {}) do
        local cfi = type(r) == "table" and s(r.cfi)
        if cfi and r.id ~= nil and type(r.id) ~= "function" and not out[cfi] then
            out[cfi] = { id = r.id, note = text(r.noteContent), text = s(r.selectedText),
                chapter = s(r.chapterTitle), color = s(r.color) }
        end
    end
    return out
end

--- locals = { [cfi] = { note = string|nil, text, chapter, color } } (the Kindle's
--- highlights with their CFI; note nil = no note). remote = NS.byCfi(list).
--- shadow = entry.note_shadow. Returns { creates, updates, deletes, pulls, conflicts }.
function NS.plan(locals, remote, shadow)
    shadow = type(shadow) == "table" and shadow or {}
    local plan = { creates = {}, updates = {}, deletes = {}, conflicts = {} }
    local cfis, seen = {}, {}
    for _i, t in ipairs({ locals, remote, shadow }) do
        for cfi in pairs(t) do if not seen[cfi] then seen[cfi] = true; cfis[#cfis + 1] = cfi end end
    end
    table.sort(cfis)
    for _i, cfi in ipairs(cfis) do
        local l, r, b = locals[cfi], remote[cfi], shadow[cfi]
        local ln, rn = l and l.note, r and r.note
        local bn = type(b) == "table" and text(b.note) or nil
        if ln ~= rn then
            local here_changed = (b == nil) or ln ~= bn
            local there_changed = (b ~= nil) and rn ~= bn
            if b == nil and rn and not ln then here_changed = false end -- only on Grimmory: comes here
            if here_changed and there_changed then
                plan.conflicts[cfi] = true
            elseif here_changed then
                if ln and r then
                    plan.updates[#plan.updates + 1] = { id = r.id, cfi = cfi, body = { noteContent = ln } }
                elseif ln then
                    plan.creates[#plan.creates + 1] = { cfi = cfi, body = { cfi = cfi, noteContent = ln,
                        selectedText = l.text, chapterTitle = l.chapter, color = l.color } }
                elseif r then
                    plan.deletes[#plan.deletes + 1] = { id = r.id, cfi = cfi }
                end
            end
            -- changed only on Grimmory: NS.merge brings it here
        end
    end
    return plan
end

--- The state to keep after a pass: Grimmory's final notes, except conflicts.
function NS.shadowFor(remote, old, conflicts)
    local out = {}
    for cfi, r in pairs(remote) do out[cfi] = { id = r.id, note = r.note } end
    for cfi in pairs(conflicts or {}) do out[cfi] = type(old) == "table" and old[cfi] or nil end
    return out
end

--- Bring Grimmory's final notes into the open book's list (changed in place).
--- cfi_of(item) -> the CFI of a highlight here (or nil); to_xp(cfi) -> pos0,
--- pos1 (or nil, err). Returns changed (bool), errors (list).
function NS.merge(list, remote, shadow, conflicts, cfi_of, to_xp)
    shadow, conflicts = shadow or {}, conflicts or {}
    local changed, errors, here = false, {}, {}
    for i = #list, 1, -1 do
        local a = list[i]
        if type(a) == "table" and a.pos0 ~= nil and a.pos1 ~= nil then
            local cfi = cfi_of(a)
            if cfi and not conflicts[cfi] then
                local r = remote[cfi]
                local b = shadow[cfi]
                if r then
                    if a.note ~= r.note then a.note = r.note; changed = true end
                    here[cfi] = true
                elseif b ~= nil and a.note == text(b.note) then
                    -- deleted on Grimmory (and not changed here since)
                    if a.grimmory_note_only then table.remove(list, i)
                    else a.note = nil end
                    changed = true
                elseif a.grimmory_note_only and not a.note then
                    -- its note deleted here, the highlight kept: an ordinary highlight now
                    a.grimmory_note_only, a.grimmory_note_cfi = nil, nil
                    changed = true
                end
            elseif cfi then
                here[cfi] = true
            end
        end
    end
    -- made in the web reader where the Kindle has no highlight: a highlight of its own
    local cfis = {}
    for cfi in pairs(remote) do if not here[cfi] and not conflicts[cfi] then cfis[#cfis + 1] = cfi end end
    table.sort(cfis)
    for _i, cfi in ipairs(cfis) do
        local r = remote[cfi]
        if r.note then
            local p0, p1, err = to_xp(cfi)
            if p0 and p1 then
                list[#list + 1] = { page = p0, pos0 = p0, pos1 = p1, drawer = "lighten", color = "yellow",
                    text = r.text, chapter = r.chapter, note = r.note,
                    grimmory_note_only = true, grimmory_note_cfi = cfi,
                    datetime = os.date("%Y-%m-%d %H:%M:%S") }
                changed = true
            else
                errors[#errors + 1] = tostring(err or "not converted")
            end
        end
    end
    return changed, errors
end

return NS
