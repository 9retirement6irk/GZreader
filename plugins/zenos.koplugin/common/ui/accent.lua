local M = {}
local cached_hex, cached_opacity, cached_night_mode, cached_color

local function get_config(config)
    local plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    local manager = package.loaded["config/manager"]
    return config or plugin and plugin.config or manager and manager.get and manager.get()
end

function M.isSupported()
    local Screen = require("device").screen
    return Screen.isColorScreen and Screen:isColorScreen() or false
end

function M.hex(config)
    config = get_config(config)
    local hex = config and config.accent_color
    return type(hex) == "string" and hex:match("^#%x%x%x%x%x%x$")
        and hex:upper() or "#000000"
end

function M.opacity(config)
    config = get_config(config)
    local opacity = tonumber(config and config.accent_opacity) or 100
    return math.max(0, math.min(100, math.floor(opacity + 0.5)))
end

function M.isEnabled(config)
    if not M.isSupported() then return false end
    config = get_config(config)
    return not (config and config.accent_enabled == false)
        and (M.hex(config) ~= "#000000" or M.opacity(config) < 100)
end

function M.color(config)
    local Blitbuffer = require("ffi/blitbuffer")
    if not M.isEnabled(config) then return Blitbuffer.COLOR_BLACK end
    local hex = M.hex(config)
    local opacity = M.opacity(config)
    local night_mode = require("device").screen.night_mode
    if hex ~= cached_hex or opacity ~= cached_opacity or night_mode ~= cached_night_mode then
        cached_hex, cached_opacity, cached_night_mode = hex, opacity, night_mode
        cached_color = Blitbuffer.ColorRGB32(tonumber(hex:sub(2, 3), 16),
            tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16), 255)
        -- Keep the chosen hue when KOReader inverts the screen at night.
        if night_mode and hex ~= "#000000" then cached_color = cached_color:invert() end
        if opacity < 100 then
            local background = Blitbuffer.COLOR_WHITE:getColorRGB32()
            background:blend(cached_color, math.floor(opacity * 255 / 100 + 0.5))
            cached_color = background
        end
    end
    return cached_color
end

function M.foreground(config)
    local Blitbuffer = require("ffi/blitbuffer")
    if not M.isEnabled(config) then return Blitbuffer.COLOR_WHITE end
    local function linear(value)
        value = value / 255
        return value <= 0.04045 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
    end
    local color = M.color(config):getColorRGB32()
    local luminance = 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    return luminance > 0.179 and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
end

function M.navbarColor(config, key, default)
    local navbar = config.navbar or {}
    local c = type(navbar[key]) == "table" and navbar[key] or default
    if key ~= "filled_outline_color" and navbar.active_tab_use_accent ~= false
            and config.accent_enabled ~= false and M.isSupported() then
        local color = M.color(config)
        if require("device").screen.night_mode and M.isEnabled(config) then color = color:invert() end
        return { color:getR(), color:getG(), color:getB() }
    end
    return c
end

function M.styleIcon(icon, active)
    local Blitbuffer = require("ffi/blitbuffer")
    icon.alpha = true
    if active and M.foreground() == Blitbuffer.COLOR_WHITE then
        icon:_render()
        if icon._bb then
            icon._bb = icon._bb:copy()
            icon._bb_disposable = true
            local bb = icon._bb
            if icon._is_straight_alpha then
                bb:invertRect(0, 0, bb:getWidth(), bb:getHeight())
            else
                -- MuPDF stores premultiplied RGB, so inversion must preserve alpha.
                for y = 0, bb:getHeight() - 1 do
                    for x = 0, bb:getWidth() - 1 do
                        local c = bb:getPixel(x, y):getColorRGB32()
                        bb:setPixel(x, y, Blitbuffer.ColorRGB32(
                            c.alpha - c.r, c.alpha - c.g, c.alpha - c.b, c.alpha))
                    end
                end
            end
        end
    end
end

return M
