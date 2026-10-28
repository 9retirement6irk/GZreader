local applied = false

local function preserve_screen(Screen, root)
    if not Screen.data or not Screen.fb_size then return end
    local ffi = require("ffi")
    require("ffi/posix_h")
    local template = ffi.new("char[?]", 64, "/tmp/zenos-restore-XXXXXX")
    assert(ffi.C.mkdtemp(template) ~= nil, "Could not create restore screen directory")
    local directory = ffi.string(template)
    local blank
    local ok, err = pcall(function()
        blank = (Screen.full_bb or Screen.bb):copy()
        blank:fill(require("ffi/blitbuffer").COLOR_WHITE)
        for name, data in pairs({
            screen = ffi.string(Screen.data, Screen.fb_size),
            blank = ffi.string(blank.data, Screen.fb_size),
        }) do
            local file = assert(io.open(directory .. "/" .. name, "wb"))
            local written, write_err = file:write(data)
            local closed, close_err = file:close()
            assert(written and closed, write_err or close_err)
        end
        local util = require("util")
        local command = util.shell_escape({ "sh", root .. "/modules/global/kindle_restore_screen.sh",
            directory, tostring(Screen.fb_size), Screen.device_node,
            require("libs/libkoreader-lfs").currentdir() .. "/fbink" })
        assert(os.execute(command .. " >>crash.log 2>&1 &") == 0, "Could not start restore screen helper")
    end)
    if blank then blank:free() end
    if not ok then
        os.remove(directory .. "/screen")
        os.remove(directory .. "/blank")
        os.remove(directory)
        error(err)
    end
end

return function()
    if applied then return end
    local Device = require("device")
    if not (Device.isKindle and Device:isKindle()) then return end

    local UIManager = require("ui/uimanager")
    local logger = require("common/zen_logger").new("kindle_exit_message")
    local restoring = false
    local orig_exit = Device.exit
    local orig_close = Device.screen.close
    Device.screen.close = function(Screen, reinit, ...)
        if restoring and not reinit then
            restoring = false
            -- Kindle restores screensaver services and display modes before closing the framebuffer.
            local ok, err = pcall(function()
                local width, height = Screen:getWidth(), Screen:getHeight()
                local margin = Screen:scaleBySize(20)
                local root = require("common/plugin_root")
                local _ = require("gettext")
                local message = require("ui/widget/textboxwidget"):new{
                    text = _("Restoring Kindle GUI…"),
                    face = require("ui/font"):getFace("cfont", 22),
                    width = width - 2 * margin,
                    alignment = "center",
                }
                Screen.night_mode = false
                Screen:beforePaint()
                Screen:clear()
                local logo_size = math.floor(math.min(width * 0.4, height * 0.3))
                local logo = require("ui/widget/imagewidget"):new{
                    file = require("common/utils").resolveLocalIcon(root .. "/icons/", "zen_ui"),
                    width = logo_size,
                    height = logo_size,
                    is_icon = true,
                }
                local top = math.floor((height - logo_size - margin - message:getSize().h) / 2)
                logo:paintTo(Screen.bb, math.floor((width - logo_size) / 2), top)
                message:paintTo(Screen.bb, margin, top + logo_size + margin)
                Screen:refreshFull(0, 0, width, height)
                Screen:refreshWaitForLast()
                Screen:afterPaint()
                message:free()
                logo:free()
                preserve_screen(Screen, root)
            end)
            if not ok then logger.warn("Could not show Kindle restore message:", err) end
        end
        return orig_close(Screen, reinit, ...)
    end
    Device.exit = function(self, ...)
        restoring = os.getenv("STOP_FRAMEWORK") == "yes" and (UIManager._exit_code or 0) == 0
            and not UIManager._entered_poweroff_stage
        return orig_exit(self, ...)
    end
    applied = true
end
