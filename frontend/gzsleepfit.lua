-- GZreader: "Scale cover to fill screen" (Settings → General → Sleep →
-- Wallpaper options). The sleep screen's cover or picture is scaled up,
-- keeping its proportions, until it covers the whole screen; ImageWidget
-- then shows its middle and cuts off what sticks out (no bars, no
-- stretching). Used by frontend/ui/screensaver.lua and the settings menu.
local M = {}

M.SETTING = "gzreader_sleep_fill"

function M.on(settings)
    return settings ~= nil and settings:isTrue(M.SETTING)
end

--- The scale factor that makes an iw × ih picture, turned by `angle`
--- degrees, cover a w × h screen. 0 (ImageWidget's "best fit") when a size
--- is unknown.
function M.factor(iw, ih, w, h, angle)
    if not (iw and ih and w and h) or iw <= 0 or ih <= 0 or w <= 0 or h <= 0 then
        return 0
    end
    if angle and angle % 180 ~= 0 then iw, ih = ih, iw end
    local f = math.max(w / iw, h / ih)
    -- ImageWidget floors the scaled size: never let that leave a 1-px bar
    if math.floor(iw * f) < w or math.floor(ih * f) < h then f = f * (1 + 1e-6) end
    return f
end

return M
