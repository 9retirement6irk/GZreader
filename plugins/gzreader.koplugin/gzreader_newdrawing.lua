--[[--
The New drawing window: after **Done** on a new drawing (the Notes tab's
**Draw**), a title and tags, then Save, instead of the whole note editor
(the owner, 2026-11-16).

- **Title** (optional): the note's heading (`# Title`), as the Notes tab
  shows a drawing note's heading over its drawing.
- **# Tag**: your most used tags (up to 9) and **New tag…**; a tag chosen
  again is taken off. The chosen tags show under the title.
- **Save** sends the note (private, as a new note is) with its drawings.
- **Back to drawing** goes back to the drawing screen, on the last page.

`NewDrawing.content(title, tags)` is the note's text (tested on its own);
`NewDrawing.show(opts)` the window: opts.tags ({ { tag, count } }: yours,
most used first), on_save(text), on_back(), keyboard_aside(dialog) (the
editor's: a dialog shown while the keyboard is up goes under it).
]]

local UIManager = require("ui/uimanager")
local _ = require("gettext")

local NewDrawing = { MAX_TAGS_OFFERED = 9 }

local function clean(tag) return require("gzreader_noteeditor").cleanTag(tag) end

--- The note's text: `# title` (when there is one), then the tags on a line.
function NewDrawing.content(title, tags)
    local parts = {}
    title = tostring(title or ""):gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if title ~= "" then parts[#parts + 1] = "# " .. title end
    local line, seen = {}, {}
    for _i, t in ipairs(tags or {}) do
        t = clean(t)
        if t ~= "" and not seen[t] then seen[t] = true; line[#line + 1] = "#" .. t end
    end
    if #line > 0 then parts[#parts + 1] = table.concat(line, " ") end
    return table.concat(parts, "\n\n")
end

--- `tags` with `tag` added, or taken off when it's there (a new list).
function NewDrawing.toggle(tags, tag)
    tag = clean(tag)
    local out, had = {}, false
    for _i, t in ipairs(tags or {}) do
        if t == tag then had = true else out[#out + 1] = t end
    end
    if not had and tag ~= "" then out[#out + 1] = tag end
    return out
end

--- The line under the title: the chosen tags, or how to add some.
function NewDrawing.tagLine(tags)
    if not tags or #tags == 0 then return _("No tags yet: # Tag adds one.") end
    local out = {}
    for i, t in ipairs(tags) do out[i] = "#" .. t end
    return _("Tags:") .. " " .. table.concat(out, " ")
end

function NewDrawing.show(opts)
    local state = { title = opts.title or "", tags = {} }
    local dialog
    local function aside(d)
        if opts.keyboard_aside then opts.keyboard_aside(d) end
    end
    local open
    local function reopen()
        if dialog then state.title = dialog:getInputText() or state.title; UIManager:close(dialog) end
        open()
    end
    local function pickTag()
        state.title = dialog:getInputText() or state.title
        UIManager:close(dialog)
        local ButtonDialog = require("ui/widget/buttondialog")
        local picker
        local rows = {}
        local chosen = {}
        for _i, t in ipairs(state.tags) do chosen[t] = true end
        for i, t in ipairs(opts.tags or {}) do
            if i > NewDrawing.MAX_TAGS_OFFERED then break end
            rows[#rows + 1] = { { text = "#" .. t.tag .. (chosen[clean(t.tag)] and "  \u{2713}" or ""), align = "left", callback = function()
                UIManager:close(picker)
                state.tags = NewDrawing.toggle(state.tags, t.tag)
                open()
            end } }
        end
        rows[#rows + 1] = { { text = _("New tag…"), align = "left", callback = function()
            UIManager:close(picker)
            local InputDialog = require("ui/widget/inputdialog")
            local d
            d = InputDialog:new{ title = _("New tag"), input = "", input_hint = _("e.g. travel or books/to-read"),
                buttons = { { { text = _("Cancel"), id = "close", callback = function() UIManager:close(d); open() end },
                    { text = _("Add"), is_enter_default = true, callback = function()
                        local v = d:getInputText()
                        UIManager:close(d)
                        if clean(v) ~= "" then state.tags = NewDrawing.toggle(state.tags, v) end
                        open()
                    end } } } }
            UIManager:show(d)
            d:onShowKeyboard()
            NewDrawing.current = d
        end } }
        picker = ButtonDialog:new{ title = _("Add a tag"), buttons = rows, tap_close_callback = function() open() end }
        local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
        if add then pcall(add, picker) end
        UIManager:show(picker)
        NewDrawing.current = picker
    end
    open = function()
        local InputDialog = require("ui/widget/inputdialog")
        dialog = InputDialog:new{
            title = _("New drawing"),
            input = state.title,
            input_hint = _("Title (optional)"),
            description = NewDrawing.tagLine(state.tags),
            buttons = { {
                { text = _("Back to drawing"), callback = function()
                    state.title = dialog:getInputText() or state.title
                    UIManager:close(dialog)
                    if opts.on_back then opts.on_back() end
                end },
                { text = "# " .. _("Tag"), callback = pickTag },
                { text = _("Save"), is_enter_default = true, callback = function()
                    state.title = dialog:getInputText() or state.title
                    UIManager:close(dialog)
                    opts.on_save(NewDrawing.content(state.title, state.tags), state)
                end },
            } },
        }
        aside(dialog)
        UIManager:show(dialog)
        dialog:onShowKeyboard()
        NewDrawing.current = dialog
    end
    open()
    NewDrawing._reopen = reopen -- (tests)
    return dialog
end

return NewDrawing
