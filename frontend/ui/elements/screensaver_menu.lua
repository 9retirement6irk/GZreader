local Device = require("device")
local Screensaver = require("ui/screensaver")
local _ = require("gettext")
local T = require("ffi/util").template

local is_touch_device = Device:isTouchDevice() or nil
local ui = require("apps/reader/readerui").instance or require("apps/filemanager/filemanager").instance

-- (GZreader: which sleep screens can be chosen now is gzreader_sleeppreview.lua's)

local function genMenuItem(text, setting, value, enabled_func, separator, help_text)
    return {
        text = text,
        help_text = help_text,
        enabled_func = enabled_func,
        checked_func = function()
            -- (GZreader's automatic sleep screen, when on, is the one chosen)
            if setting == "screensaver_type" and G_reader_settings:nilOrTrue("gzreader_sleep_auto") then return false end
            return G_reader_settings:readSetting(setting) == value
        end,
        callback = function()
            G_reader_settings:saveSetting(setting, value)
            -- GZreader: choosing a sleep screen here replaces GZreader's automatic one
            if setting == "screensaver_type" then G_reader_settings:makeFalse("gzreader_sleep_auto") end
        end,
        radio = true,
        separator = separator,
    }
end

local exit_help_text = _("The 'Exit sleep screen' action is located in the Device group of the Taps and gestures settings")

local sub_item_table = {
    {
        -- GZreader: the choices are tiles, each a preview of what it shows
        -- (gzreader_sleeppreview.lua); their other settings are under
        -- Wallpaper options. No custom image (nothing to choose it with).
        text = _("Wallpaper"),
        help_text = _("Shows each sleep screen as a small preview; tap or press one to use it."),
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local ok, Preview = pcall(require, "gzreader_sleeppreview")
            if ok then Preview.show(function()
                if touchmenu_instance and touchmenu_instance.updateItems then touchmenu_instance:updateItems() end
            end) end
        end,
    },
    {
        text = _("Wallpaper options"),
        sub_item_table = {
            {
                text = _("Ignore book cover"),
                help_text = _("Choose when to ignore showing book covers on the sleep screen."),
                enabled_func = function()
                    return G_reader_settings:readSetting("screensaver_type") == "cover"
                end,
                checked_func = function()
                    return G_reader_settings:isTrue("screensaver_hide_cover_in_filemanager")
                            or G_reader_settings:isTrue("screensaver_exclude_finished_books")
                            or G_reader_settings:isTrue("screensaver_exclude_on_hold_books")
                end,
                sub_item_table = {
                    {
                        text = _("For books on hold"),
                        help_text = _("When the device is locked and the current book has been marked as on hold, both the cover and sleep screen message of the book will not be shown."),
                        checked_func = function()
                            return G_reader_settings:isTrue("screensaver_exclude_on_hold_books")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("screensaver_exclude_on_hold_books")
                        end,
                    },
                    {
                        text = _("For finished books"),
                        help_text = _("When the device is locked and the current book has been marked as finished, both the cover and sleep screen message of the book will not be shown."),
                        checked_func = function()
                            return G_reader_settings:isTrue("screensaver_exclude_finished_books")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("screensaver_exclude_finished_books")
                        end,
                    },
                    {
                        text = _("When in file browser"),
                        help_text = _("When the device is locked from the file browser, both the cover and sleep screen message of the last opened book will not be shown."),
                        checked_func = function()
                            return G_reader_settings:isTrue("screensaver_hide_cover_in_filemanager")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("screensaver_hide_cover_in_filemanager")
                        end,
                    },
                },
                separator = true,
            },
            {
                text = _("Border fill, rotation, and fit"),
                enabled_func = function()
                    local screensaver_type = G_reader_settings:readSetting("screensaver_type")
                    return G_reader_settings:nilOrTrue("gzreader_sleep_auto") -- (GZreader's: a cover or a picture)
                        or screensaver_type == "cover" or screensaver_type == "document_cover" or screensaver_type == "random_image"
                end,
                sub_item_table = {
                    genMenuItem(_("Black fill"), "screensaver_img_background", "black"),
                    genMenuItem(_("White fill"), "screensaver_img_background", "white"),
                    genMenuItem(_("No fill"), "screensaver_img_background", "none", nil, true),
                    -- separator
                    {
                        text_func = function()
                            local percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage")
                            if G_reader_settings:isTrue("screensaver_stretch_images") and percentage then
                                return T(_("Stretch to fit screen (with limit: %1 %)"), percentage)
                            end
                            return _("Stretch cover to fit screen")
                        end,
                        enabled_func = function() -- (GZreader: not with Scale cover to fill screen)
                            return not require("gzsleepfit").on(G_reader_settings)
                        end,
                        checked_func = function()
                            return G_reader_settings:isTrue("screensaver_stretch_images")
                        end,
                        callback = function(touchmenu_instance)
                            Screensaver:setStretchLimit(touchmenu_instance)
                        end,
                    },
                    {
                        -- GZreader: proportions kept, edges cut off (gzsleepfit.lua)
                        text = _("Scale cover to fill screen"),
                        help_text = _("Scales the book cover or picture up until it covers the whole screen, keeping its proportions. No bars at the edges; the parts that don't fit are cut off."),
                        checked_func = function()
                            return require("gzsleepfit").on(G_reader_settings)
                        end,
                        callback = function()
                            local Fit = require("gzsleepfit")
                            G_reader_settings:flipNilOrFalse(Fit.SETTING)
                            if Fit.on(G_reader_settings) then
                                G_reader_settings:makeFalse("screensaver_stretch_images")
                            end
                        end,
                    },
                    {
                        text = _("Rotate cover for best fit"),
                        checked_func = function()
                            return G_reader_settings:isTrue("screensaver_rotate_auto_for_best_fit")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("screensaver_rotate_auto_for_best_fit")
                        end,
                    }
                },
            },
            {
                text = _("Postpone screen update after wake-up"),
                sub_item_table = {
                    genMenuItem(_("Never"), "screensaver_delay", "disable"),
                    genMenuItem(_("1 second"), "screensaver_delay", "1"),
                    genMenuItem(_("3 seconds"), "screensaver_delay", "3"),
                    genMenuItem(_("5 seconds"), "screensaver_delay", "5"),
                    genMenuItem(is_touch_device and _("Until a tap") or _("Until a key press"), "screensaver_delay", "tap"),
                    is_touch_device and genMenuItem(_("Until 'Exit sleep screen' gesture"), "screensaver_delay", "gesture",
                        nil, true, exit_help_text),
                    is_touch_device and {
                        text = _("Show 'Exit sleep screen' message"),
                        enabled_func = function()
                            return G_reader_settings:readSetting("screensaver_delay") == "gesture"
                        end,
                        checked_func = function()
                            return G_reader_settings:hasNot("screensaver_show_exit_message") -- save 'false' only
                        end,
                        callback = function()
                            G_reader_settings:flipFalse("screensaver_show_exit_message")
                        end,
                    },
                    is_touch_device and {
                        text = _("Edit 'Exit sleep screen' message"),
                        enabled_func = function()
                            return G_reader_settings:readSetting("screensaver_delay") == "gesture"
                                and G_reader_settings:hasNot("screensaver_show_exit_message")
                        end,
                        keep_menu_open = true,
                        callback = function()
                            Screensaver:setMessage(true)
                        end,
                    },
                },
            },
        },
    },
    {
        text = _("Sleep screen message"),
        sub_item_table = {
            {
                text = _("Add custom message to sleep screen"),
                checked_func = function()
                    return G_reader_settings:isTrue("screensaver_show_message")
                end,
                callback = function()
                    G_reader_settings:toggle("screensaver_show_message")
                end,
                separator = true,
            },
            {
                text = _("Edit sleep screen message"),
                enabled_func = function()
                    return G_reader_settings:isTrue("screensaver_show_message")
                end,
                keep_menu_open = true,
                callback = function()
                    Screensaver:setMessage()
                end,
            },
            {
                text = _("Container and position"),
                enabled_func = function()
                    return G_reader_settings:isTrue("screensaver_show_message")
                end,
                sub_item_table = {
                    genMenuItem(_("Banner"), "screensaver_message_container", "banner"),
                    genMenuItem(_("Box"), "screensaver_message_container", "box", nil, true),
                    {
                        text_func = function()
                            local percent = G_reader_settings:readSetting("screensaver_message_vertical_position")
                            local value
                            if percent == 100 then
                                value = _("top")
                            elseif percent == 50 then
                                value = _("middle")
                            elseif percent == 0 then
                                value = _("bottom")
                            else
                                value = percent .. "\xE2\x80\xAF%" -- narrow no-break space
                            end
                            return T(_("Vertical position: %1"), value)
                        end,
                        help_text = _("Set a custom vertical position for the sleep screen message."),
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            Screensaver:setCustomPosition(touchmenu_instance)
                        end,
                    },
                    {
                        text_func = function()
                            local alpha = G_reader_settings:readSetting("screensaver_message_alpha", 100)
                            return T(_("Message opacity: %1"), alpha) .. "\xE2\x80\xAF%"
                        end,
                        help_text = _("Set the opacity level of the sleep screen message."),
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            Screensaver:setMessageOpacity(touchmenu_instance)
                        end,
                    },
                },
            },
            {
                text = _("Background fill"),
                help_text = _("This option will only become available, if you have selected 'Leave screen as-is' as wallpaper and have 'Sleep screen message' on."),
                enabled_func = function()
                    return G_reader_settings:readSetting("screensaver_type") == "disable" and G_reader_settings:isTrue("screensaver_show_message")
                end,
                sub_item_table = {
                    genMenuItem(_("Black fill"), "screensaver_msg_background", "black"),
                    genMenuItem(_("White fill"), "screensaver_msg_background", "white"),
                    genMenuItem(_("No fill"), "screensaver_msg_background", "none"),
                },
            },
            (Device:canReboot() and Device:canPowerOff()) and {
                text = _("Hide reboot/poweroff message"),
                checked_func = function()
                    return G_reader_settings:isTrue("screensaver_hide_fallback_msg")
                end,
                callback = function()
                    G_reader_settings:toggle("screensaver_hide_fallback_msg")
                end,
            } or nil,
        },
    },
}

if ui.document then
    table.insert(sub_item_table, {
        text = _("Do not show this book cover on sleep screen"),
        enabled_func = function()
            local screensaver_type = G_reader_settings:readSetting("screensaver_type")
            return screensaver_type == "cover" or screensaver_type == "disable"
        end,
        checked_func = function()
            return ui.doc_settings:isTrue("exclude_screensaver")
        end,
        callback = function()
            ui.doc_settings:flipNilOrFalse("exclude_screensaver")
        end,
    })
end

return sub_item_table
