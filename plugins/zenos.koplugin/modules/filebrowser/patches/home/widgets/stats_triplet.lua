local Background = require("common/ui/background")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LineWidget = require("ui/widget/linewidget")
local TextWidget = require("ui/widget/textwidget")
local IconWidget = require("ui/widget/iconwidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Device = require("device")
local Font = require("ui/font")
local utils = require("common/utils")
local WidgetResources = require("common/widget_resources")
local _ = require("gettext")

local _icons_dir
do
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) == "@" then
        local root = src:sub(2):match("^(.*)/modules/")
        if root then _icons_dir = root .. "/icons/" end
    end
end

local calendar_icon_path = utils.resolveLocalIcon(_icons_dir, "calendar")
local stat_icon_paths = {
    book_days = calendar_icon_path,
    book_duration = utils.resolveLocalIcon(_icons_dir, "tab_to_be_read"),
    book_page_minutes = utils.resolveLocalIcon(
        require("libs/libkoreader-lfs").currentdir() .. "/resources/icons/mdlight/", "book.opened")
        or utils.resolveLocalIcon(_icons_dir, "book_open"),
    book_daily_minutes = calendar_icon_path,
    streak = utils.resolveLocalIcon(_icons_dir, "flame"),
}
local MIN_FONT_SIZE = 8
local MAX_FONT_SIZE = 64
local DEFAULT_FONT_SIZE = 16
local DEFAULT_MAX_FONT_SIZE = 18

local function time_unit(unit)
    if type(_) == "table" and type(_.pgettext) == "function" then
        return _.pgettext("Time", unit)
    end
    return _(unit)
end

local function fmt_time(secs)
    secs = math.floor(secs or 0)
    if secs <= 0 then return "0" .. time_unit("m") end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then
        return h .. time_unit("h") .. " " .. m .. time_unit("m")
    end
    return m .. time_unit("m")
end

local FIELD_MAP = {
    book_days = { id = "book_days", label = _("Days"), get = function(s) return s.book_days or "—" end },
    book_duration = { id = "book_duration", label = _("Total time"), get = function(s) return s.book_duration or "—" end },
    book_page_minutes = { id = "book_page_minutes", label = _("Per page"), get = function(s) return s.book_page_minutes or "—" end },
    book_daily_minutes = { id = "book_daily_minutes", label = _("Per day"), get = function(s) return s.book_daily_minutes or "—" end },
    today_pages = { id = "today_pages", label = _("Pages today"), get = function(s) return tostring(s.today_pages or 0) end },
    today_duration = { id = "today_duration", label = _("Read today"), get = function(s) return fmt_time(s.today_duration or 0) end },
    streak = { id = "streak", label = _("Day streak"), get = function(s) return tostring(s.streak or 0) end },
    week_pages = { id = "week_pages", label = _("Pages this week"), get = function(s) return tostring(s.week_pages or 0) end },
    week_duration = { id = "week_duration", label = _("Time this week"), get = function(s) return fmt_time(s.week_duration or 0) end },
}

local function metric_content(width, height, value_widget, label_widget, shift_state)
    local value_size = value_widget:getSize()
    local label_size = label_widget:getSize()
    local value_h = value_size.h or 1
    local label_h = label_size.h or 1
    local overlap = math.floor(value_h * 0.18)
    local gap = 1
    local content_h = value_h - overlap + gap + label_h
    local top = math.floor(math.max(0, height - content_h) / 2)

    local content = WidgetResources.managedPaintWidget{
        dimen = Geom:new{ w = width, h = height },
        resources = { value_widget, label_widget },
        paintTo = function(_self, bb, x, y)
            local value_x = x + math.floor((width - (value_size.w or 0)) / 2)
            local value_y = y + top + shift_state.value
            local label_x = x + math.floor((width - (label_size.w or 0)) / 2)
            local label_y = value_y + value_h - overlap + gap
            value_widget:paintTo(bb, value_x, value_y)
            label_widget:paintTo(bb, label_x, label_y)
        end,
        free = function()
            value_widget = nil
            label_widget = nil
        end,
    }
    return content, top, content_h
end

local function configured_font_size(ctx)
    local module_cfg = type(ctx.module_cfg) == "table" and ctx.module_cfg or {}
    return math.max(MIN_FONT_SIZE, math.min(MAX_FONT_SIZE,
        tonumber(module_cfg.font_size) or DEFAULT_FONT_SIZE))
end

local function configured_max_font_size(ctx)
    local module_cfg = type(ctx.module_cfg) == "table" and ctx.module_cfg or {}
    return math.max(MIN_FONT_SIZE, math.min(MAX_FONT_SIZE,
        tonumber(module_cfg.max_font_size) or DEFAULT_MAX_FONT_SIZE))
end

local function font_size_fits(candidate, fields, stats, inner_w, inner_h, show_icons)
    local value_face = Font:getFace("smallinfofont", candidate)
    local label_face = Font:getFace("smallinfofont",
        math.max(1, math.floor(candidate * 0.8)))
    for _i, field in ipairs(fields) do
        local value_probe = TextWidget:new{
            text = field.get(stats),
            face = value_face,
            bold = true,
        }
        local label_probe = TextWidget:new{ text = field.label, face = label_face }
        local value_size = value_probe:getSize()
        local label_size = label_probe:getSize()
        local value_w = value_size.w or 0
        local value_h = value_size.h or 1
        if show_icons and stat_icon_paths[field.icon or field.id] then
            value_w = value_w + math.max(8, math.floor(value_h * 0.62)) + 3
        end
        local content_h = value_h - math.floor(value_h * 0.18)
            + 1 + (label_size.h or 1)
        local fits = value_w <= inner_w and (label_size.w or 0) <= inner_w
            and content_h <= inner_h
        WidgetResources.free(value_probe)
        WidgetResources.free(label_probe)
        if not fits then return false end
    end
    return true
end

local function fitting_font_size(fields, stats, inner_w, inner_h, max_font_size, show_icons)
    local low, high = 1, max_font_size
    local best = 1
    while low <= high do
        local candidate = math.floor((low + high) / 2)
        if font_size_fits(candidate, fields, stats, inner_w, inner_h, show_icons) then
            best = candidate
            low = candidate + 1
        else
            high = candidate - 1
        end
    end
    return best
end

local function preferred_height(ctx)
    ctx = type(ctx) == "table" and ctx or {}
    local module_cfg = type(ctx.module_cfg) == "table" and ctx.module_cfg or {}
    local font_size = module_cfg.automatic_font_size ~= false
        and configured_max_font_size(ctx) or configured_font_size(ctx)
    local value_probe = TextWidget:new{
        text = "A",
        face = Font:getFace("smallinfofont", font_size),
        bold = true,
    }
    local label_probe = TextWidget:new{
        text = "A",
        face = Font:getFace("smallinfofont",
            math.max(module_cfg.automatic_font_size ~= false and 1 or 6, math.floor(font_size * 0.8))),
    }
    local value_h = value_probe:getSize().h or 1
    local label_h = label_probe:getSize().h or 1
    WidgetResources.free(value_probe)
    WidgetResources.free(label_probe)
    local content_h = value_h - math.floor(value_h * 0.18) + 1 + label_h
    local border_size = ctx.module_cfg and ctx.module_cfg.stat_style == "outline" and 2 or 0
    if module_cfg.stat_style == "notebook" then return Device.screen:scaleBySize(112) end -- GZreader
    return math.max(20, content_h + 12 + border_size * 2)
end

-- GZreader: the stats handwritten on a notebook page taped up (like the
-- Notes tab's sticky notes): ruled lines, a margin line, two strips of tape,
-- a small tilt; a streak of up to 10 days as tally marks.
local function hand_face(size)
    local ok, Sticky = pcall(require, "gzreader_sticky")
    if ok and Sticky and Sticky.hand then return Sticky.hand(size) end
    return Font:getFace("cfont", size)
end

local function paint_tally(bb, x, y, n, h)
    local S = function(px) return Device.screen:scaleBySize(px) end
    local w, gap = math.max(2, S(3)), S(6)
    local px = x
    for i = 1, n do
        bb:paintRect(px, y + ((i % 2 == 0) and 1 or 0), w, h - ((i % 3 == 0) and 2 or 0), Blitbuffer.COLOR_BLACK)
        if i % 5 == 0 then
            -- the fifth stroke across the four before it
            local x0 = px - 4 * gap - S(2)
            local span = px + w - x0
            for k = 0, span - 1 do
                bb:paintRect(x0 + k, y + h - 4 - math.floor(k * (h - 8) / span), 1, math.max(2, S(3)), Blitbuffer.COLOR_BLACK)
            end
            px = px + gap + S(4)
        else
            px = px + gap
        end
    end
    return px - x
end

local function tally_width(n)
    local S = function(px) return Device.screen:scaleBySize(px) end
    return n * S(6) + math.floor(n / 5) * S(4)
end

local function notebook(ctx, fields, stats)
    local S = function(px) return Device.screen:scaleBySize(px) end
    local outer_w, height = ctx.width, ctx.height
    local m = S(12)
    local w = math.max(S(120), outer_w - S(60))
    local h = math.max(S(40), math.min(height - S(14), S(90)))
    local tilt = not rawequal(Background.tile_bg(Blitbuffer.COLOR_WHITE), nil) -- (over a background picture: no tilt, no white corners)
    local value_face = hand_face(math.max(14, math.min(36, math.floor(h * 0.40))))
    local label_face = hand_face(math.max(10, math.min(18, math.floor(h * 0.20))))
    local function draw()
        local canvas = Blitbuffer.new(w + 2 * m, h + 2 * m, Blitbuffer.TYPE_BB8)
        canvas:fill(Blitbuffer.COLOR_WHITE)
        canvas:paintRect(m + S(4), m + S(4), w, h, Blitbuffer.gray(0.30)) -- shadow
        canvas:paintRect(m, m, w, h, Blitbuffer.COLOR_WHITE)
        local pitch = S(24)
        local ly = S(18)
        while ly < h - 2 do
            canvas:paintRect(m + 1, m + ly, w - 2, 1, Blitbuffer.gray(0.18))
            ly = ly + pitch
        end
        canvas:paintRect(m + S(44), m + 1, 1, h - 2, Blitbuffer.gray(0.40)) -- the margin
        canvas:paintBorder(m, m, w, h, 1, Blitbuffer.gray(0.50))
        local cell_w = math.floor(w / 3)
        for i, field in ipairs(fields) do
            local cx = m + (i - 1) * cell_w
            local label = TextWidget:new{ text = tostring(field.label):lower(), face = label_face,
                fgcolor = Blitbuffer.gray(0.80), max_width = cell_w - S(8) }
            local ls = label:getSize()
            local streak = (field.tally or field.id == "streak") and tonumber(stats[field.tally or "streak"] or 0) or nil
            if streak and streak >= 1 and streak <= 10 then
                local th = math.floor(h * 0.36)
                local tw = tally_width(streak)
                local top = m + math.floor((h - th - ls.h - S(4)) / 2)
                paint_tally(canvas, cx + math.floor((cell_w - tw) / 2), top, streak, th)
                label:paintTo(canvas, cx + math.floor((cell_w - ls.w) / 2), top + th + S(4))
            else
                local value = TextWidget:new{ text = field.get(stats), face = value_face, max_width = cell_w - S(8) }
                local vs = value:getSize()
                local top = m + math.floor((h - vs.h - ls.h + S(6)) / 2)
                value:paintTo(canvas, cx + math.floor((cell_w - vs.w) / 2), top)
                label:paintTo(canvas, cx + math.floor((cell_w - ls.w) / 2), top + vs.h - S(6))
                value:free()
            end
            label:free()
        end
        -- two strips of tape over the top edge
        local tw, th = S(62), S(18)
        canvas:paintRect(m + S(22), m - math.floor(th / 2), tw, th, Blitbuffer.gray(0.24))
        canvas:paintRect(m + w - S(22) - tw, m - math.floor(th / 2) + S(1), tw, th, Blitbuffer.gray(0.24))
        if not tilt then return canvas end
        local ok, Sticky = pcall(require, "gzreader_sticky")
        if not (ok and Sticky and Sticky.rotate) then return canvas end
        local turned = Sticky.rotate(canvas, -0.8)
        canvas:free()
        return turned
    end
    local img
    local widget = WidgetResources.managedPaintWidget{
        dimen = Geom:new{ w = outer_w, h = height },
        paintTo = function(_self, bb, x, y)
            if not img then img = draw() end
            local iw, ih = img:getWidth(), img:getHeight()
            bb:blitFrom(img, x + math.floor((outer_w - iw) / 2), y + math.floor((height - ih) / 2), 0, 0, iw, ih)
        end,
        free = function() if img then img:free(); img = nil end end,
    }
    if type(ctx.setContentBounds) == "function" then
        ctx.setContentBounds{ top = 0, bottom = height, min_shift = 0, max_shift = 0, set_shift = function() end }
    end
    return FrameContainer:new{
        width = outer_w, height = height, padding = 0, bordersize = 0,
        background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
        widget,
    }
end

-- GZreader: the same widget for other stats (spec: id, label, fields
-- { id = { id, label, get(stats), icon, tally } }, config_key, defaults,
-- stats(ctx)); Grimmory's reading stats use it (grimmory_stats.lua).
local function build_stats(ctx, spec)
        local field_map = spec.fields
        local outer_width = ctx.width
        local height = ctx.height
        local stats = spec.stats(ctx) or {}
        local module_cfg = ctx.module_cfg or {}
        local show_icons = module_cfg.show_icons ~= false
        local stat_style = module_cfg.stat_style == "outline" and "outline"
            or module_cfg.stat_style == "none" and "none"
            or "divider"
        local horizontal_padding = stat_style == "outline"
            and Device.screen:scaleBySize(8) or 0
        local width = math.max(1, outer_width - horizontal_padding * 2)

        local config = ctx.config[spec.config_key] or spec.defaults
        local fields = {}
        for _i, fid in ipairs(config) do
            local entry = field_map[fid] or field_map[spec.defaults[1]]
            table.insert(fields, entry)
            if #fields >= 3 then break end
        end
        while #fields < 3 do
            table.insert(fields, field_map[spec.defaults[#fields + 1]])
        end
        if module_cfg.stat_style == "notebook" then return notebook(ctx, fields, stats) end

        local gap_w = stat_style == "outline" and math.max(10, math.floor(width * 0.045))
            or stat_style == "divider" and 8
            or 6
        local cell_w = math.max(20, math.floor((width - gap_w * 2) / 3))
        local card_h = math.max(20, height)
        local border_size = stat_style == "outline" and 2 or 0
        local inner_w = math.max(1, cell_w - border_size * 2)
        local inner_h = math.max(1, card_h - border_size * 2)
        local Screen = Device.screen
        local shift_state = { value = 0 }
        local font_size = module_cfg.automatic_font_size ~= false
            and fitting_font_size(fields, stats, inner_w, inner_h,
                configured_max_font_size(ctx), show_icons)
            or configured_font_size(ctx)
        local value_face = Font:getFace("smallinfofont", font_size)
        local label_face = Font:getFace("smallinfofont",
            math.max(module_cfg.automatic_font_size ~= false and 1 or 6, math.floor(font_size * 0.8)))
        local row = HorizontalGroup:new{ align = "center" }
        local visual_top
        local visual_bottom
        local divider_visual_top
        local divider_visual_bottom

        for _i, field in ipairs(fields) do
            local value_widget = TextWidget:new{
                text = field.get(stats),
                face = value_face,
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
            if show_icons and stat_icon_paths[field.icon or field.id] then
                local value_size = value_widget:getSize()
                local icon_size = math.max(8, math.floor((value_size.h or 12) * 0.62))
                value_widget = HorizontalGroup:new{
                    align = "center",
                    IconWidget:new{
                        file = stat_icon_paths[field.icon or field.id],
                        width = icon_size,
                        height = icon_size,
                        alpha = true,
                    },
                    HorizontalSpan:new{ width = 3 },
                    value_widget,
                }
            end
            local content, metric_top, metric_h = metric_content(
                inner_w, inner_h, value_widget,
                TextWidget:new{ text = field.label, face = label_face, fgcolor = Blitbuffer.COLOR_BLACK },
                shift_state)
            visual_top = math.min(visual_top or metric_top, metric_top)
            visual_bottom = math.max(visual_bottom or metric_top + metric_h,
                metric_top + metric_h)
            local card = FrameContainer:new{
                width = cell_w,
                height = card_h,
                padding = 0,
                bordersize = border_size,
                color = Blitbuffer.COLOR_DARK_GRAY,
                radius = stat_style == "outline" and 8 or 0,
                background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
                CenterContainer:new{
                    dimen = Geom:new{ w = inner_w, h = inner_h },
                    content,
                },
            }
            table.insert(row, card)
            if _i < 3 then
                if stat_style == "outline" then
                    table.insert(row, HorizontalSpan:new{ width = gap_w })
                elseif stat_style == "divider" then
                    local divider_trim = math.min(
                        math.max(0, metric_h - 1),
                        math.max(1, Screen:scaleBySize(4))
                    )
                    local divider_h = math.min(card_h, math.max(1, metric_h - divider_trim))
                    local divider_bottom = metric_top + metric_h
                    local divider_top = divider_bottom - divider_h
                    divider_visual_top = math.min(
                        divider_visual_top or divider_top, divider_top)
                    divider_visual_bottom = math.max(
                        divider_visual_bottom or divider_bottom, divider_bottom)
                    local divider_shift = divider_top - math.floor((card_h - divider_h) / 2)
                    local divider_container = CenterContainer:new{
                        dimen = Geom:new{ w = gap_w, h = card_h },
                        LineWidget:new{
                            dimen = Geom:new{ w = 2, h = divider_h },
                            background = Blitbuffer.COLOR_DARK_GRAY,
                        },
                    }
                    local original_divider_paint = divider_container.paintTo
                    divider_container.paintTo = function(self, bb, x, y)
                        return original_divider_paint(
                            self, bb, x, y + divider_shift + shift_state.value)
                    end
                    table.insert(row, divider_container)
                else
                    table.insert(row, HorizontalSpan:new{ width = gap_w })
                end
            end
        end

        local row_container = CenterContainer:new{
            dimen = Geom:new{ w = outer_width, h = height },
            row,
        }
        if type(ctx.setContentBounds) == "function" then
            local fixed = stat_style == "outline"
            local top = fixed and 0 or divider_visual_top or visual_top or 0
            local bottom = fixed and height or divider_visual_bottom or visual_bottom or height
            ctx.setContentBounds{
                top = top,
                bottom = bottom,
                min_shift = fixed and 0 or -top,
                max_shift = fixed and 0 or height - bottom,
                set_shift = function(shift)
                    if not fixed then shift_state.value = shift end
                end,
            }
        end

        return FrameContainer:new{
            width = outer_width,
            height = height,
            padding = 0,
            bordersize = 0,
            background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
            row_container,
        }
end

local function make(spec)
    return {
        id = spec.id,
        label = spec.label,
        size = "xs",
        preferredHeight = preferred_height,
        build = function(ctx) return build_stats(ctx, spec) end,
        make = make,
        fmt_time = fmt_time,
    }
end

return make{
    id = "stats_triplet",
    label = _("Local reading stats"), -- GZreader: Grimmory's are the other ones
    fields = FIELD_MAP,
    config_key = "middle_stats_triplet",
    defaults = { "today_pages", "today_duration", "streak" },
    stats = function(ctx) return ctx.data.stats end,
}
