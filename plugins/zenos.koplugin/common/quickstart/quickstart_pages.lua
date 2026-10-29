-- Quickstart slideshow page definitions.
-- build_install_pages(ctx): called on first install with { plugin, config }.
-- build_update_pages(version): returns release pages for an update.
-- UPDATE_PAGES: static pages keyed by version string.
-- Each page: { title = string, image = string|nil, description = string }
-- Interactive pages also have: choice_type, choices, on_apply.

local M = {}

local _ = require("gettext")
local T = require("ffi/util").template
local icons = require("common/inline_icon_map")
local ConfigManager = require("config/manager")
local CoverUtils = require("common/cover_utils")
local paths = require("common/paths")
local PresetStore = require("config/preset_store")
local ReaderDefaults = require("common/reader_defaults")
local Accent = require("common/ui/accent")

local _plugin_root = require("common/plugin_root") or ""

local function img(rel)
    return _plugin_root .. "/images/quickstart/" .. rel
end

-- Load up to `n` book covers. ReadHistory first, then home-dir scan to fill.
-- Returns array of { bb, w, h, progress, status } -- caller owns the blitbuffer copies.
local function loadQuickstartCovers(n)
    local ok, BIM = pcall(require, "bookinfomanager")
    if not ok or type(BIM) ~= "table" or type(BIM.getBookInfo) ~= "function" then
        return {}
    end
    local lfs    = require("libs/libkoreader-lfs")
    local ok_ds, DocSettings = pcall(require, "docsettings")
    local covers = {}
    local seen   = {}

    local function try_add(path)
        if #covers >= n or not path or seen[path] then return end
        seen[path] = true
        if lfs.attributes(path, "mode") ~= "file" then return end
        local info = BIM:getBookInfo(path, true)
        if info and info.has_cover and info.cover_bb
                and info.cover_fetched and not info.ignore_cover then
            local progress, status = nil, nil
            if ok_ds then
                pcall(function()
                    local ds = DocSettings:open(path)
                    progress = ds:readSetting("percent_finished")
                    local summary = ds:readSetting("summary")
                    status = summary and summary.status
                end)
            end
            table.insert(covers, { bb = info.cover_bb:copy(), w = info.cover_w, h = info.cover_h, progress = progress, status = status, title = info.title, authors = info.authors, pages = info.pages })
        end
    end

    local rh_ok, ReadHistory = pcall(require, "readhistory")
    if rh_ok and ReadHistory and ReadHistory.hist then
        for _i, entry in ipairs(ReadHistory.hist) do
            if #covers >= n then break end
            try_add(entry.file)
        end
    end

    if #covers < n then
        local home = paths.getHomeDir()
        if home and lfs.attributes(home, "mode") == "directory" then
            local file_list = {}
            for fname in lfs.dir(home) do
                if fname ~= "." and fname ~= ".." then
                    local fpath = home .. "/" .. fname
                    if lfs.attributes(fpath, "mode") == "file" then
                        table.insert(file_list, fpath)
                    end
                end
            end
            table.sort(file_list)
            for _i, path in ipairs(file_list) do
                if #covers >= n then break end
                try_add(path)
            end
        end
    end

    return covers
end

-- Downward-pointing pentagon badge shape (matches browser_cover_badges).
local function paintPentagon(bb, bx, by, bw, bh, color)
    local rect_h = math.floor(bh * 30 / 42)
    local tip_h  = bh - rect_h
    bb:paintRect(bx, by, bw, rect_h, color)
    for row = 0, tip_h - 1 do
        local frac = (row + 1) / tip_h
        local rw   = math.max(2, math.floor(bw * (1 - frac)))
        local rx   = bx + math.floor((bw - rw) / 2)
        bb:paintRect(rx, by + rect_h + row, rw, 1, color)
    end
end

-- Checkmark drawn as two diagonal line segments.
local function paintCheck(bb, bx, by, bw, bh, color)
    local tk = math.max(2, math.floor(math.min(bw, bh) / 8))
    local function drawLine(x0, y0, x1, y1)
        local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
        if steps == 0 then steps = 1 end
        for i = 0, steps do
            local t = i / steps
            bb:paintRect(math.floor(x0 + t*(x1-x0)), math.floor(y0 + t*(y1-y0)), tk, tk, color)
        end
    end
    drawLine(bx+math.floor(bw*0.08), by+math.floor(bh*0.62), bx+math.floor(bw*0.30), by+math.floor(bh*0.82))
    drawLine(bx+math.floor(bw*0.30), by+math.floor(bh*0.82), bx+math.floor(bw*0.82), by+math.floor(bh*0.18))
end

-- Paint a progress/status badge (pentagon, matches browser_cover_badges) at the top-right
-- of a cover cell in a canvas. NOT pre-inverted -- night mode inverts it once naturally.
local function paintCoverBadge(canvas, Blitbuffer, Font, TextWidget, Screen,
                               cell_x, cell_y, cell_w, progress, status)
    local do_check = (status == "complete") or (progress and progress >= 1.0)
    local do_tbr = not do_check and (status == "tbr")
    local do_pause = not do_check and (status == "abandoned")
    local do_pct   = not do_check and not do_tbr and not do_pause and (progress and progress > 0)
    if not (do_check or do_tbr or do_pause or do_pct) then return end
    local badge_size = math.max(Screen:scaleBySize(16), math.floor(cell_w * 0.14))
    local bw = math.floor(badge_size * 1.2)
    local bh = math.floor(badge_size * 1.1)
    local bdg_x = cell_x + cell_w - bw - math.floor(bw * 0.25)
    local bdg_y = cell_y + 2
    paintPentagon(canvas, bdg_x - 2, bdg_y - 2, bw + 4, bh + 4, Blitbuffer.COLOR_BLACK)
    paintPentagon(canvas, bdg_x, bdg_y, bw, bh, Blitbuffer.COLOR_LIGHT_GRAY)
    local rect_h = math.floor(bh * 30 / 42)
    local pad_x  = math.floor(bw * 0.12)
    local pad_y  = math.floor(rect_h * 0.15)
    local icon_w = bw - 2 * pad_x
    local icon_h = rect_h - 2 * pad_y
    if do_check then
        local sq   = math.min(icon_w, icon_h)
        paintCheck(canvas,
            bdg_x + pad_x + math.floor((icon_w - sq) / 2),
            bdg_y + pad_y + math.floor((icon_h - sq) / 2),
            sq, sq, Blitbuffer.COLOR_BLACK)
    elseif Font and TextWidget then
        local font_sz = (do_tbr or do_pause)
            and math.max(7, math.floor(badge_size * 0.40))
            or  math.max(7, math.floor(badge_size * 0.24))
        local tw = TextWidget:new{
            text    = do_tbr and "\u{F0150}"
                or (do_pause and "\u{F03E4}" or (math.floor(100 * progress) .. "%")),
            face    = Font:getFace("cfont", font_sz),
            bold    = not do_tbr and not do_pause,
            fgcolor = Blitbuffer.COLOR_BLACK,
            padding = 0,
        }
        local tw_sz = tw:getSize()
        tw:paintTo(canvas,
            bdg_x + math.floor((bw     - tw_sz.w) / 2),
            bdg_y + math.floor((rect_h - tw_sz.h) / 2))
        tw:free()
    end
end

-- Render the library icon (circle border + library icon) centered on a white canvas.
-- Mirrors buildZenButtonBB sizing so the Home Folder page looks consistent.
local function buildHomeIconBB(avail_w)
    local ok_bb,  Blitbuffer = pcall(require, "ffi/blitbuffer")
    local ok_iw,  IconWidget = pcall(require, "ui/widget/iconwidget")
    local ok_dev, Device     = pcall(require, "device")
    if not (ok_bb and ok_iw and ok_dev) then return nil end
    local ok_u, utils = pcall(require, "common/utils")
    local Screen   = Device.screen
    local BTN_SZ   = Screen:scaleBySize(160)
    local BORDER   = Screen:scaleBySize(3)
    local ICO_SZ   = math.floor(BTN_SZ * 0.52)
    local canvas_h = BTN_SZ + Screen:scaleBySize(40)
    local canvas   = Blitbuffer.new(avail_w, canvas_h, Blitbuffer.TYPE_BB8)
    canvas:fill(Blitbuffer.COLOR_WHITE)
    local r  = math.floor(BTN_SZ / 2)
    local cx = math.floor(avail_w / 2)
    local cy = math.floor(canvas_h / 2)
    for dy = -r, r do
        local hw = math.floor(math.sqrt(r*r - dy*dy) + 0.5)
        if hw > 0 then canvas:paintRect(cx - hw, cy + dy, hw*2, 1, Blitbuffer.COLOR_BLACK) end
    end
    local ir = r - BORDER
    for dy = -ir, ir do
        local hw = math.floor(math.sqrt(ir*ir - dy*dy) + 0.5)
        if hw > 0 then canvas:paintRect(cx - hw, cy + dy, hw*2, 1, Blitbuffer.COLOR_WHITE) end
    end
    local icon_path = ok_u and utils.resolveIcon(_plugin_root .. "/icons/", "library")
    pcall(function()
        local ico = IconWidget:new{
            file   = icon_path or nil,
            icon   = icon_path and nil or "library",
            width  = ICO_SZ,
            height = ICO_SZ,
        }
        local isz = ico:getSize()
        ico:paintTo(canvas, cx - math.floor(isz.w / 2), cy - math.floor(isz.h / 2))
        ico:free()
    end)
    return canvas
end

-- Render a visual replica of the context menu dialog (ButtonDialog with cover header +
-- the real file-action buttons). cover_info is an optional entry from loadQuickstartCovers.
-- Returns a Blitbuffer (caller owns) or nil on error.
-- slot_w/slot_h are the QuickstartScreen image zone dimensions; canvas fills it 1:1.
local function buildContextMenuBB(slot_w, slot_h, cover_info)
    local ok_bb,  Blitbuffer  = pcall(require, "ffi/blitbuffer")
    local ok_dev, Device      = pcall(require, "device")
    local ok_bd,  ButtonDialog = pcall(require, "ui/widget/buttondialog")
    if not (ok_bb and ok_dev and ok_bd) then return nil end

    local Screen = Device.screen
    local _      = require("gettext")

    -- Dialog at 85% of slot width; canvas is the full slot so scale_factor=0 renders 1:1.
    local dlg_w = math.floor(slot_w * 0.85)

    -- Build the cover+title header (mirrors context_menu.lua's makeSideBySide).
    local header_widget
    pcall(function()
        local SizeR           = require("ui/size")
        local Font            = require("ui/font")
        local Geom            = require("ui/geometry")
        local FrameContainer  = require("ui/widget/container/framecontainer")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local HorizontalSpan  = require("ui/widget/horizontalspan")
        local LeftContainer   = require("ui/widget/container/leftcontainer")
        local TextWidget      = require("ui/widget/textwidget")
        local VerticalGroup   = require("ui/widget/verticalgroup")
        local VerticalSpan    = require("ui/widget/verticalspan")
        local Widget          = require("ui/widget/widget")

        local border      = CoverUtils.BORDER_SIZE
        local gap         = Screen:scaleBySize(8)
        local avail_inner = dlg_w
            - 2 * (SizeR.border.window + SizeR.padding.button)
            - 2 * (SizeR.padding.default + SizeR.margin.default)
        local cover_max_w = Screen:scaleBySize(90)
        local cover_max_h = Screen:scaleBySize(140)
        local text_col_w  = math.max(avail_inner - cover_max_w - 2 * border - gap,
                                     Screen:scaleBySize(60))

        local cover_frame
        if cover_info then
            local ok_iw,  ImageWidget     = pcall(require, "ui/widget/imagewidget")
            local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
            if ok_iw and ok_bim then
                local _, _, sf = BookInfoManager.getCachedCoverSize(
                    cover_info.w, cover_info.h, cover_max_w, cover_max_h)
                cover_frame = FrameContainer:new{
                    padding    = 0,
                    bordersize = border,
                    ImageWidget:new{
                        image            = cover_info.bb,
                        image_disposable = false,
                        scale_factor     = sf,
                    },
                }
            end
        end
        if not cover_frame then
            cover_frame = FrameContainer:new{
                padding    = 0,
                bordersize = border,
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                Widget:new{ dimen = Geom:new{ w = cover_max_w, h = cover_max_h } },
            }
        end

        local vstack = VerticalGroup:new{ align = "left" }
        table.insert(vstack, TextWidget:new{
            text      = (cover_info and cover_info.title) or _("Book Title"),
            face      = Font:getFace("cfont", 20),
            bold      = true,
            max_width = text_col_w,
        })
        if cover_info and cover_info.authors then
            table.insert(vstack, VerticalSpan:new{ width = Screen:scaleBySize(2) })
            table.insert(vstack, TextWidget:new{
                text      = cover_info.authors,
                face      = Font:getFace("cfont", 17),
                max_width = text_col_w,
            })
        end

        local framed_h = cover_max_h + 2 * border
        header_widget = LeftContainer:new{
            dimen = Geom:new{ w = avail_inner, h = framed_h },
            HorizontalGroup:new{
                align = "center",
                cover_frame,
                HorizontalSpan:new{ width = gap },
                vstack,
            },
        }
    end)

    local buttons = {
        {{ text = "\u{F02FD}  " .. _("Details"),                              align = "left", callback = function() end }},
        {{ text = "\u{F01BE}  " .. _("Move"),                                 align = "left", callback = function() end }},
        {{ text = "\u{F04CE}  " .. _("Add to collection") .. "  " .. icons.arrow_right, align = "left", callback = function() end }},
        {{ text = "\u{F0B64}  " .. _("Read status") .. "  " .. icons.arrow_right,       align = "left", callback = function() end }},
        {{ text = "\u{F090C}  " .. _("Edit") .. "  " .. icons.arrow_right,              align = "left", callback = function() end }},
    }

    local dialog = ButtonDialog:new{
        buttons        = buttons,
        width          = dlg_w,
        dismissable    = false,
        _added_widgets = header_widget and { header_widget } or nil,
    }

    local sz = dialog:getSize()
    local canvas = Blitbuffer.new(slot_w, slot_h, Blitbuffer.TYPE_BB8)
    canvas:fill(Blitbuffer.COLOR_WHITE)
    -- Center dialog horizontally; leave equal top/bottom breathing room.
    local dx = math.floor((slot_w - sz.w) / 2)
    local dy = math.floor((slot_h - sz.h) / 2)
    pcall(function()
        dialog:paintTo(canvas, dx, dy)
    end)
    return canvas
end

local function buildQuickSettingsBB(slot_w, slot_h)
    local ok_bb, Blitbuffer = pcall(require, "ffi/blitbuffer")
    if not ok_bb then return nil end

    local build_preview = rawget(_G, "__ZEN_UI_BUILD_QUICK_SETTINGS_PREVIEW")
    if type(build_preview) ~= "function" then return nil end

    local ok_panel, panel = pcall(build_preview, slot_w)
    if not ok_panel or not panel then return nil end

    local ok_size, sz = pcall(function() return panel:getSize() end)
    if not ok_size or not sz then return nil end

    local canvas = Blitbuffer.new(slot_w, slot_h, Blitbuffer.TYPE_BB8)
    canvas:fill(Blitbuffer.COLOR_WHITE)
    local dx = math.max(0, math.floor((slot_w - sz.w) / 2))
    local dy = math.max(0, math.floor((slot_h - sz.h) / 2))
    pcall(function()
        panel:paintTo(canvas, dx, dy)
    end)
    return canvas
end

local function buildPageBrowserBB(slot_w, slot_h)
    local build_preview = rawget(_G, "__ZEN_UI_BUILD_PAGE_BROWSER_PREVIEW")
    if type(build_preview) ~= "function" then return nil end
    local ok, bb = pcall(build_preview, slot_w, slot_h)
    return ok and bb or nil
end

-- Render the zen-mode quicksettings button (circle border + quick_zen icon) centered
-- on a white canvas. Returns a Blitbuffer (caller owns) or nil on error.
local function buildZenButtonBB(avail_w)
    local ok_bb,  Blitbuffer = pcall(require, "ffi/blitbuffer")
    local ok_iw,  IconWidget = pcall(require, "ui/widget/iconwidget")
    local ok_dev, Device     = pcall(require, "device")
    if not (ok_bb and ok_iw and ok_dev) then return nil end
    local ok_u, utils = pcall(require, "common/utils")
    local Screen   = Device.screen
    local BTN_SZ   = Screen:scaleBySize(160)
    local BORDER   = Screen:scaleBySize(3)
    local ICO_SZ   = math.floor(BTN_SZ * 0.52)
    local canvas_h = BTN_SZ + Screen:scaleBySize(40)
    local canvas   = Blitbuffer.new(avail_w, canvas_h, Blitbuffer.TYPE_BB8)
    canvas:fill(Blitbuffer.COLOR_WHITE)
    local r  = math.floor(BTN_SZ / 2)
    local cx = math.floor(avail_w / 2)
    local cy = math.floor(canvas_h / 2)
    -- Circle border
    for dy = -r, r do
        local hw = math.floor(math.sqrt(r*r - dy*dy) + 0.5)
        if hw > 0 then canvas:paintRect(cx - hw, cy + dy, hw*2, 1, Blitbuffer.COLOR_BLACK) end
    end
    -- White interior
    local ir = r - BORDER
    for dy = -ir, ir do
        local hw = math.floor(math.sqrt(ir*ir - dy*dy) + 0.5)
        if hw > 0 then canvas:paintRect(cx - hw, cy + dy, hw*2, 1, Blitbuffer.COLOR_WHITE) end
    end
    local icon_path = ok_u and utils.resolveIcon(_plugin_root .. "/icons/", "quick_zen")
    pcall(function()
        local ico = IconWidget:new{
            file   = icon_path or nil,
            icon   = icon_path and nil or "quick_zen",
            width  = ICO_SZ,
            height = ICO_SZ,
        }
        local isz = ico:getSize()
        ico:paintTo(canvas, cx - math.floor(isz.w / 2), cy - math.floor(isz.h / 2))
        ico:free()
    end)
    return canvas
end

-- Compose a 1x3 horizontal strip of portrait covers.
-- Returns a Blitbuffer (caller owns) or nil on error.
local function buildMosaicBB(covers, avail_w)
    local ok_bb,  Blitbuffer  = pcall(require, "ffi/blitbuffer")
    local ok_iw,  ImageWidget = pcall(require, "ui/widget/imagewidget")
    local ok_dev, Device      = pcall(require, "device")
    if not (ok_bb and ok_dev) then return nil end
    local ok_font, Font       = pcall(require, "ui/font")
    local ok_tw,  TextWidget  = pcall(require, "ui/widget/textwidget")
    local Screen = Device.screen
    local night  = Screen.night_mode
    local PAD    = Screen:scaleBySize(8)
    local GAP    = Screen:scaleBySize(6)
    local cell_w = math.floor((avail_w - 2 * PAD - 2 * GAP) / 3)
    local cell_h = math.floor(cell_w * 3 / 2)
    local canvas = Blitbuffer.new(avail_w, cell_h + 2 * PAD, Blitbuffer.TYPE_BB8)
    canvas:fill(Blitbuffer.COLOR_WHITE)
    for i = 0, 2 do
        local cx = PAD + i * (cell_w + GAP)
        canvas:paintRect(cx, PAD, cell_w, cell_h, Blitbuffer.COLOR_GRAY_4)
        local c = covers[i + 1]
        if c and ok_iw then
            pcall(function()
                local iw = ImageWidget:new{
                    image                 = c.bb,
                    width                 = cell_w,
                    height                = cell_h,
                    scale_factor          = 0,
                    image_disposable      = false,
                    original_in_nightmode = false,
                }
                local isz = iw:getSize()
                iw:paintTo(canvas,
                    cx  + math.floor((cell_w - isz.w) / 2),
                    PAD + math.floor((cell_h - isz.h) / 2))
                iw:free()
            end)
            -- Pre-invert the cover cell; display's night-mode inversion restores original colors.
            if night then canvas:invertRect(cx, PAD, cell_w, cell_h) end
            -- Badge painted after inversion: display inverts it once, matching browser_cover_badges behavior.
            pcall(paintCoverBadge, canvas, Blitbuffer,
                ok_font and Font or nil, ok_tw and TextWidget or nil,
                Screen, cx, PAD, cell_w, c.progress, c.status)
        end
    end
    return canvas
end

-- Compose 2 list rows: cover thumbnail left + actual book details right.
-- Returns a Blitbuffer (caller owns) or nil on error.
local function buildListBB(covers, avail_w)
    local ok_bb,  Blitbuffer  = pcall(require, "ffi/blitbuffer")
    local ok_iw,  ImageWidget = pcall(require, "ui/widget/imagewidget")
    local ok_dev, Device      = pcall(require, "device")
    if not (ok_bb and ok_dev) then return nil end
    local ok_font, Font       = pcall(require, "ui/font")
    local ok_tw,  TextWidget  = pcall(require, "ui/widget/textwidget")
    local Screen    = Device.screen
    local night     = Screen.night_mode
    local PAD       = Screen:scaleBySize(8)
    local GAP       = Screen:scaleBySize(8)
    local INNER_GAP = Screen:scaleBySize(10)
    local thumb_w   = math.floor(avail_w * 0.28)
    local thumb_h   = math.floor(thumb_w * 3 / 2)
    local total_h   = 2 * thumb_h + GAP + 2 * PAD
    local canvas    = Blitbuffer.new(avail_w, total_h, Blitbuffer.TYPE_BB8)
    canvas:fill(Blitbuffer.COLOR_WHITE)
    local text_x = PAD + thumb_w + INNER_GAP
    local text_w = avail_w - text_x - PAD
    for i = 0, 1 do
        local ry = PAD + i * (thumb_h + GAP)
        canvas:paintRect(PAD, ry, thumb_w, thumb_h, Blitbuffer.COLOR_GRAY_4)
        local c = covers[i + 1]
        if c and ok_iw then
            pcall(function()
                local iw = ImageWidget:new{
                    image                 = c.bb,
                    width                 = thumb_w,
                    height                = thumb_h,
                    scale_factor          = 0,
                    image_disposable      = false,
                    original_in_nightmode = false,
                }
                local isz = iw:getSize()
                iw:paintTo(canvas,
                    PAD + math.floor((thumb_w - isz.w) / 2),
                    ry  + math.floor((thumb_h - isz.h) / 2))
                iw:free()
            end)
            if night then canvas:invertRect(PAD, ry, thumb_w, thumb_h) end
        end
        if ok_font and ok_tw then
            local ty = ry + Screen:scaleBySize(8)
            -- Title
            local title_str = (c and c.title and c.title ~= "") and c.title or "Unknown Title"
            local t_tw = TextWidget:new{
                text    = title_str,
                face    = Font:getFace("cfont", 17),
                bold    = true,
                width   = text_w,
                padding = 0,
            }
            t_tw:paintTo(canvas, text_x, ty)
            ty = ty + t_tw:getSize().h + Screen:scaleBySize(4)
            t_tw:free()
            -- Author
            local auth_str = (c and c.authors and c.authors ~= "") and c.authors or ""
            if auth_str ~= "" then
                local a_tw = TextWidget:new{
                    text    = auth_str,
                    face    = Font:getFace("cfont", 15),
                    width   = text_w,
                    padding = 0,
                }
                a_tw:paintTo(canvas, text_x, ty)
                ty = ty + a_tw:getSize().h + Screen:scaleBySize(4)
                a_tw:free()
            end
            -- Pages
            if c and c.pages and c.pages > 0 then
                local m_tw = TextWidget:new{
                    text    = c.pages .. " pages",
                    face    = Font:getFace("cfont", 14),
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    width   = text_w,
                    padding = 0,
                }
                m_tw:paintTo(canvas, text_x, ty)
                m_tw:free()
            end
        else
            -- Fallback: gray placeholder bars
            canvas:paintRect(text_x, ry + math.floor(thumb_h * 0.25),
                math.floor(text_w * 0.55), Screen:scaleBySize(10), Blitbuffer.COLOR_LIGHT_GRAY)
            canvas:paintRect(text_x, ry + math.floor(thumb_h * 0.25) + Screen:scaleBySize(18),
                math.floor(text_w * 0.35), Screen:scaleBySize(8), Blitbuffer.COLOR_LIGHT_GRAY)
        end
        if i < 1 then
            canvas:paintRect(PAD, ry + thumb_h + math.floor(GAP / 2),
                avail_w - 2 * PAD, 1, Blitbuffer.COLOR_LIGHT_GRAY)
        end
    end
    return canvas
end

-- ---------------------------------------------------------------------------
-- ctx = { plugin = <ZenOS plugin>, config = <config table> }
-- ---------------------------------------------------------------------------

function M.build_accent_page(ctx)
    if not Accent.isSupported() then return nil end
    local config = ctx.config
    local hex = Accent.hex(config)
    local picker = {
        hex = hex == "#000000" and "#3399FF" or hex,
        opacity = Accent.opacity(config),
    }
    picker.callback = function(color, opacity)
        picker.hex, picker.opacity = color, opacity
        config.accent_enabled = true
        config.accent_color = color
        config.accent_opacity = opacity
        ConfigManager.save(config)
        local settings_apply = require("modules/settings/zen_settings_apply")
        settings_apply.refresh_navbar_on_menu_close()
        local home = require("common/shared_state").get(ctx.plugin, "home")
        if home and home.rebuildActive then
            settings_apply.defer_until_settings_close("home_rebuild", home.rebuildActive)
        end
        local UIManager = require("ui/uimanager")
        UIManager:setDirty("all", require("common/ui/refresh")())
    end
    return {
        title = _("Accent color"),
        description = _("Choose an accent color for buttons, sliders, and navigation."),
        color_picker = picker,
    }
end

-- Grimmory build: first setup page connects the Kindle to Grimmory.
-- The choice runs when the user presses Next; the pairing screen opens on top
-- of the guide and the guide continues once pairing finishes or is cancelled.
local function grimmoryPlugin(ctx)
    local ui = ctx and ctx.plugin and ctx.plugin.ui
    local g = ui and ui.grimmory
    if type(g) ~= "table" then
        local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok and type(FileManager) == "table" and FileManager.instance
        g = type(fm) == "table" and fm.grimmory or nil
    end
    return type(g) == "table" and g or nil
end

local function grimmoryState(ctx)
    -- Pages are built during ZenOS's init, before FileManager.instance is set;
    -- the UI under construction (ctx.plugin.ui) already has grimmory registered
    -- because plugins load in path order and "grimmory" sorts before "zenos".
    local ui = ctx and ctx.plugin and ctx.plugin.ui
    local g = ui and ui.grimmory
    if type(g) ~= "table" then
        local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok and type(FileManager) == "table" and FileManager.instance
        g = type(fm) == "table" and fm.grimmory or nil
    end
    if type(g) ~= "table" or type(g.api) ~= "table" then return nil end
    if not g then return nil end
    local paired = g.api and g.api:isPaired()
    return { paired = paired, username = g.store and g.store.username }
end

local function sendGrimmoryEvent(name)
    local UIManager = require("ui/uimanager")
    local Event = require("ui/event")
    UIManager:scheduleIn(0.4, function()
        UIManager:broadcastEvent(Event:new(name))
    end)
end

local function buildGrimmoryPage(ctx)
    local state = grimmoryState(ctx)
    if not state then return nil end
    local choices = {}
    if state.paired then
        choices[#choices + 1] = { id = "keep", text = T(_("Keep connection (%1)"), state.username or "?"), checked = true }
    end
    choices[#choices + 1] = { id = "qr",   text = _("Scan a QR code with my phone"), checked = not state.paired }
    choices[#choices + 1] = { id = "type", text = _("Type my login on this Kindle"),   checked = false }
    choices[#choices + 1] = { id = "skip", text = _("Skip for now"),                   checked = false }
    return {
        title       = _("Connect to Grimmory"),
        description = _("Sign in to your Grimmory library to download books and keep your reading progress in sync.\nYou can do this later from the Grimmory tab."),
        choice_type = "radio",
        choices     = choices,
        on_apply    = function(sel)
            if sel["qr"] then
                sendGrimmoryEvent("GrimmoryPair")
            elseif sel["type"] then
                sendGrimmoryEvent("GrimmoryKeyboardLogin")
            end
        end,
    }
end

function M.build_install_pages(ctx)
    local config = ctx.config
    local plugin = ctx.plugin

    local function save_zen_config()
        ConfigManager.save(config)
    end

    local function save_and_apply(feature)
        save_zen_config()
        local ok, apply_mod = pcall(require, "modules/settings/zen_settings_apply")
        if ok and type(apply_mod.apply_feature_toggle) == "function" then
            apply_mod.apply_feature_toggle(plugin, feature, config.features[feature] == true)
        end
    end

    -- Load screensaver presets once
    local builtin_presets = {}
    pcall(function()
        local bp_mod = require("config/screensaver_presets")
        if type(bp_mod.get) == "function" then
            builtin_presets = bp_mod.get(_plugin_root .. "/icons/")
        end
    end)

    -- -----------------------------------------------------------------------
    -- Setting appliers
    -- -----------------------------------------------------------------------

    local function apply_screensaver_preset(preset)
        if type(preset) ~= "table" then return end
        local simple_keys = {
            "screensaver_type",
            "screensaver_img_background",
            "screensaver_document_cover",
            "screensaver_stretch_limit_percentage",
        }
        for _i, k in ipairs(simple_keys) do
            if preset[k] ~= nil then
                G_reader_settings:saveSetting(k, preset[k])
            end
        end
        -- "cover" uses the last book's cover; stale document_cover paths are irrelevant
        -- and confusing, so clear the setting when switching to this type.
        if preset.screensaver_type == "cover" then
            G_reader_settings:delSetting("screensaver_document_cover")
        end
        if preset.screensaver_show_message ~= nil then
            if preset.screensaver_show_message then
                G_reader_settings:makeTrue("screensaver_show_message")
            else
                G_reader_settings:makeFalse("screensaver_show_message")
            end
        end
        if preset.screensaver_stretch_images ~= nil then
            if preset.screensaver_stretch_images then
                G_reader_settings:makeTrue("screensaver_stretch_images")
            else
                G_reader_settings:makeFalse("screensaver_stretch_images")
            end
        end
    end

    local function apply_display_mode(mode)
        local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok_fm and FileManager and FileManager.instance
        if fm and type(fm.onSetDisplayMode) == "function" then
            pcall(fm.onSetDisplayMode, fm, mode)
        else
            local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
            if ok_bim then
                pcall(BookInfoManager.saveSetting, BookInfoManager,
                    "filemanager_display_mode", mode)
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Choice defaults (read current config so defaults feel intentional)
    -- -----------------------------------------------------------------------

    local show_tabs = (type(config.navbar) == "table" and type(config.navbar.show_tabs) == "table")
        and config.navbar.show_tabs or {}
    local quickstart_completed = type(config._meta) == "table"
        and config._meta.quickstart_completed == true

    local is_12h = true
    local raw_12h = G_reader_settings:readSetting("twelve_hour_clock")
    if raw_12h ~= nil then
        is_12h = raw_12h ~= false
    end

    -- -----------------------------------------------------------------------
    -- Page table
    -- -----------------------------------------------------------------------

    local pages = {
        -- 1. Welcome (static)
        {
            title       = "Welcome to GZreader",
            icon        = "_zen_quickstart",
            description = "Grimmory + ZenOS + KOReader.\n\n" .. _("Your Grimmory library on your Kindle: download books, read them, and keep your place and bookmarks in sync.") .. "\n\n"
                .. _("Use the 5-way to choose and press it to continue."),
        },

        -- 2. Library View (INTERACTIVE — radio)
        {
            title       = _("Library View"),
            choice_type = "radio",
            choices     = {
                { id = "mosaic", text = _("Mosaic - large cover thumbnails"),     checked = true  },
                { id = "list",   text = _("List - detailed titles and metadata"), checked = false },
            },
            on_apply = function(sel)
                if     sel["mosaic"] then apply_display_mode("mosaic_image")
                elseif sel["list"]   then apply_display_mode("list_image_meta")
                end
            end,
        },

        -- 3. Navbar Tabs (INTERACTIVE — checkbox)
        {
            title          = _("Navbar Tabs"),
            description    = _("Choose which tabs appear in your navigation bar.\nYou can rearrange or adjust these anytime in Settings."),
            choice_type    = "checkbox",
            max_selections = 7,
            choices        = {
                { id = "home",        text = _("Home"),        checked = show_tabs["home"]        ~= false },
                { id = "continue",    text = _("Continue"),    checked = show_tabs["continue"]    == true },
                { id = "history",     text = _("History"),     checked = show_tabs["history"]     == true },
                { id = "favorites",   text = _("Favorites"),   checked = show_tabs["favorites"]   == true },
                { id = "collections", text = _("Collections"), checked = show_tabs["collections"] == true },
                { id = "authors",     text = _("Authors"),     checked = show_tabs["authors"]     == true },
                { id = "series",      text = _("Series"),      checked = show_tabs["series"]      == true },
                { id = "to_be_read",  text = _("To Be Read"),  checked = show_tabs["to_be_read"]  == true },
                { id = "search",      text = _("Search"),      checked = show_tabs["search"]      == true },
                { id = "stats",       text = _("Stats"),       checked = show_tabs["stats"]       == true },
            },
            on_apply = function(sel)
                if type(config.navbar) ~= "table" then config.navbar = {} end
                if type(config.navbar.show_tabs) ~= "table" then config.navbar.show_tabs = {} end
                local tabs = { "home", "continue", "history", "favorites", "collections",
                               "authors", "series", "to_be_read", "search", "stats" }
                for _i, id in ipairs(tabs) do
                    config.navbar.show_tabs[id] = sel[id] == true
                end
                save_and_apply("navbar")
            end,
        },

        -- 4. GZreader: keyboard (static)
        {
            title       = _("Your keyboard"),
            description = _("1 – 9: switch the bottom tabs, counted from the left (Home, Downloaded, Continue, Grimmory, …).") .. "\n"
                .. _("Q, W, E …: pick an item in a list (the letter is shown next to it).") .. "\n"
                .. _("Menu while reading: the Reading menu (contents, bookmarks, go to page, search, read aloud, fonts, sync). Hold Menu for the page browser.") .. "\n"
                .. _("Shift + Sym: read aloud / stop.") .. "\n"
                .. _("Back: return from a link, or go to the Home screen."),
        },

        -- 4b. GZreader: sync (static)
        {
            title       = _("Synced with Grimmory"),
            description = _("Books you download from the Grimmory tab keep your reading position and bookmarks in sync with Grimmory's web reader and your other devices.") .. "\n\n"
                .. _("No Wi-Fi? Your progress is saved on the Kindle and sent when you're back online."),
        },

        -- 5. Zen Mode (static)
        {
            title       = _("Zen Mode"),
            image       = img("onboarding/zen_mode.png"),
            description = _("Turn on Zen mode to strip KOReader down to its bare essentials.\n\nRemove visual clutter for a focused, distraction-free reading experience. Exit at anytime from Settings.") .. "\n\n"
                .. _("Disable zen mode to access default KOReader menus."),
        },

        -- 6. Sleep Screen (INTERACTIVE — radio)
        {
            title       = _("Sleep Screen"),
            description = _("What should your device show when it goes to sleep?"),
            choice_type = "radio",
            choices     = {
                { id = "gz_auto",       text = _("Book cover while reading; a picture from the \"screensavers\" folder on Home and menus"), checked = not quickstart_completed },
                { id = "keep",          text = _("Keep existing settings"),         checked = quickstart_completed },
                { id = "cover_black",   text = _("Always the last book's cover"), checked = false },
                { id = "zen_white",     text = _("Show Zen icon - white background"),   checked = false },
                { id = "zen_black",     text = _("Show Zen icon - black background"),   checked = false },
            },
            on_apply = function(sel)
                if sel["keep"] then return end
                if sel["gz_auto"] then
                    G_reader_settings:makeTrue("gzreader_sleep_auto")
                    pcall(function()
                        local lfs = require("libs/libkoreader-lfs")
                        if require("device"):isKindle() and not lfs.attributes("/mnt/us/screensavers", "mode") then
                            lfs.mkdir("/mnt/us/screensavers")
                        end
                    end)
                    return
                end
                G_reader_settings:makeFalse("gzreader_sleep_auto")
                local preset
                if     sel["cover_black"] then preset = builtin_presets[1]
                elseif sel["zen_white"]   then preset = builtin_presets[2]
                elseif sel["zen_black"]   then preset = builtin_presets[4]
                end
                if preset then
                    apply_screensaver_preset(preset)
                    PresetStore.saveSettings("screensaver", preset)
                    PresetStore.setActivePreset("screensaver", preset.name)
                end
            end,
        },

        -- 7. Time Format (INTERACTIVE — radio)
        {
            title       = _("Time Format"),
            description = _("Which time format do you prefer?"),
            choice_type = "radio",
            choices     = {
                { id = "12h", text = _("12-hour  (3:30 PM)"), checked = is_12h      },
                { id = "24h", text = _("24-hour  (15:30)"),   checked = not is_12h  },
            },
            on_apply = function(sel)
                if sel["12h"] then
                    G_reader_settings:makeTrue("twelve_hour_clock")
                elseif sel["24h"] then
                    G_reader_settings:makeFalse("twelve_hour_clock")
                end
                -- TimeFormatChanged is reader-only; file manager status bar needs a direct refresh.
                local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
                local fm = ok_fm and FileManager and FileManager.instance
                if fm and type(fm._updateStatusBar) == "function" then
                    fm:_updateStatusBar()
                end
            end,
        },

        -- 8. Reader (INTERACTIVE — radio)
        {
            title       = _("Reader"),
            description = _("Font, margins, contrast, line spacing etc - tested together for the best reading experience"),
            choice_type = "radio",
            choices     = {
                { id = "keep", text = _("Keep existing settings"), checked = quickstart_completed },
                { id = "zen",  text = _("ZenOS defaults"), checked = not quickstart_completed },
            },
            on_apply = function(sel)
                if type(config._meta) ~= "table" then config._meta = {} end
                if sel["keep"] then
                    config._meta.reader_defaults_apply_on_next_open = false
                    save_zen_config()
                    return
                end
                local applied = ReaderDefaults.apply(G_reader_settings, config)
                config._meta.reader_defaults_apply_on_next_open = applied ~= true
                save_and_apply("reader_top_status_bar")
            end,
        },

        -- 9. Reading (static)
        {
            title       = _("While reading"),
            description = _("Press Menu for the Reading menu. Every entry has a letter key next to it.") .. "\n\n"
                .. _("Read aloud: press Shift + Sym. The sentence being read is highlighted and pages turn by themselves. The first time, GZreader finds the Kindle's voice with a short test.") .. "\n\n"
                .. _("Press AA for fonts and layout. Hold Menu for the page browser."),
        },

        -- 10. Settings & Updates (static)
        {
            title       = _("Settings & Updates"),
            icon        = "_zen_quickstart_update",
            icon_size   = 120,
            description = _("All settings are in one unified tab. This icon with the dot indicates an update is available.") .. "\n\n"
                .. _("GZreader checks for updates once a day (github.com/9retirement6irk/GZreader). Updating keeps your books, settings and reading progress."),
        },

        -- 11. Finale
        {
            title       = _("You're All Set"),
            icon        = "_zen_quickstart",
            finale      = true,
            description = _("The best interface is the one you forget is there.\nNow go get lost in a good book."),
        },
    }

    local accent_page = M.build_accent_page(ctx)
    if accent_page then table.insert(pages, 3, accent_page) end

    -- Grimmory build: no "Home Folder" question. The home folder is the
    -- Grimmory folder the plugin creates (downloads land there).
    pcall(function()
        local g = grimmoryPlugin(ctx)
        if g and type(g.useLibraryAsHome) == "function" then g:useLibraryAsHome() end
    end)

    local ok_gp, grimmory_page = pcall(buildGrimmoryPage, ctx)
    if not ok_gp then grimmory_page = nil end
    if grimmory_page then table.insert(pages, 1, grimmory_page) end

    -- Inject real cover art and rendered icons into preview pages.
    local ok_inject, err_inject = pcall(function()
        local covers  = loadQuickstartCovers(3)
        local Device  = require("device")
        local scr_w   = Device.screen:getWidth()
        local scr_h   = Device.screen:getHeight()
        local avail_w = scr_w - Device.screen:scaleBySize(80)
        -- Mirror QuickstartScreen's image slot dimensions so the canvas fills it at 1:1.
        local qs_pad  = Device.screen:scaleBySize(20)
        local img_h   = scr_h - Device.screen:scaleBySize(60) - 1 - math.floor(scr_h * 0.40)
        local slot_w  = scr_w - qs_pad * 2
        local slot_h  = img_h - Device.screen:scaleBySize(8)
        local mosaic_bb       = buildMosaicBB(covers, avail_w)
        local list_bb         = buildListBB(covers, avail_w)
        local context_menu_bb = buildContextMenuBB(slot_w, slot_h, covers[1])
        local quicksettings_bb = buildQuickSettingsBB(slot_w, slot_h)
        local page_browser_bb = buildPageBrowserBB(slot_w, slot_h)
        local zen_bb          = buildZenButtonBB(avail_w)
        local home_bb         = buildHomeIconBB(avail_w)
        for _i, c in ipairs(covers) do c.bb:free() end
        for _i, page in ipairs(pages) do
            if page.title == _("Context Menu") and context_menu_bb then
                page.image_bb, page.image = context_menu_bb, nil
            elseif page.title == _("Zen Mode") and zen_bb then
                page.image_bb, page.image = zen_bb, nil
            elseif page.title == _("Home Folder") and home_bb then
                page.image_bb, page.image = home_bb, nil
            elseif page.title == _("Quick Settings") and quicksettings_bb then
                page.image_bb, page.image = quicksettings_bb, nil
            elseif page.title == _("Page Browser") and page_browser_bb then
                page.image_bb, page.image = page_browser_bb, nil
            end
            if page.choices then
                for _j, choice in ipairs(page.choices) do
                    if choice.id == "mosaic" and mosaic_bb then
                        choice.image_bb, choice.image = mosaic_bb, nil
                    elseif choice.id == "list" and list_bb then
                        choice.image_bb, choice.image = list_bb, nil
                    end
                end
            end
        end
    end)
    if not ok_inject then
        local logger = require("common/zen_logger").new("quickstart_pages")
        logger.warn("cover injection failed:", err_inject)
    end

    return pages
end

-- ---------------------------------------------------------------------------

M.UPDATE_PAGES = {
    -- Add per-version pages when releasing updates. Example:
    -- ["0.1.0"] = {
    --     { title = "What's New in 0.1.0", image = img("0.1.0/feature.png"), description = "..." },
    -- },
}

function M.build_update_pages(version)
    local pages = {}
    for _i, page in ipairs(M.UPDATE_PAGES[version] or {}) do
        pages[#pages + 1] = page
    end
    return pages
end

-- Bullet list shown on the post-update splash screen (ZenScreen).
local ok_cl, changelog = pcall(require, "config/changelog")
M.CHANGELOGS = ok_cl and type(changelog) == "table" and changelog or {}

return M
