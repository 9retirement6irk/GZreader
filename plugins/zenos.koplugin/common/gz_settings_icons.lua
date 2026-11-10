-- GZreader: an icon for every Settings row. ZenOS gives its own sections'
-- rows icons, but most entries further in (choices, KOReader's own menus,
-- the rows GZreader adds) have none and showed an empty space. A row without
-- an icon gets one here: by what its text is about, else by what kind of row
-- it is (a submenu, a switch, a choice, an action, a line of information).
-- Used by common/ui/icon_menu_item.lua for Settings rows only.
local M = {}

-- (the start of a word in the row's text, lower case) → key in
-- common/inline_icon_map.lua; the first match wins, so the more specific
-- words come first
M.RULES = {
    { "read aloud", "settings_reader" }, { "audio", "settings_reader" }, { "sound", "settings_reader" },
    { "volume", "settings_reader" }, { "headphone", "settings_reader" }, { "music", "settings_reader" },
    { "plex", "settings_reader" }, { "keyword", "keywords" }, { "tag", "keywords" },
    { "table of contents", "view_list" }, { "contents", "view_list" },
    { "grimmory", "settings_library" }, { "shelf", "settings_library" }, { "librar", "settings_library" },
    { "download", "download" }, { "upload", "send" }, { "sync", "sync" },
    { "send", "send" }, { "share", "send" }, { "qr code", "send" },
    { "save", "save" }, { "export", "save" }, { "backup", "save" }, { "archive", "archive" },
    { "delete", "delete" }, { "remove", "delete" }, { "clear", "clear" }, { "reset", "refresh" },
    { "update", "upgrade" }, { "version", "details" }, { "restart", "restart" }, { "quit", "restart" }, { "exit", "restart" },
    { "bug", "settings_bug" }, { "diagnostic", "settings_bug" }, { "log", "settings_bug" }, { "debug", "settings_bug" },
    { "statistic", "settings_stats" }, { "progress", "settings_stats" }, { "goal", "settings_stats" }, { "streak", "settings_stats" },
    { "wi-fi", "wifi_on" }, { "wifi", "wifi_on" }, { "network", "wifi_on" }, { "proxy", "connect" },
    { "connect", "connect" }, { "bluetooth", "bluetooth_on" }, { "incognito", "incognito" },
    { "battery", "battery" }, { "storage", "settings_storage" }, { "disk", "settings_storage" }, { "space", "settings_storage" },
    { "ram", "settings_ram" }, { "memory", "settings_ram" }, { "cpu", "settings_cpu" }, { "device", "settings_device" },
    { "sleep", "settings_sleep" }, { "suspend", "settings_sleep" }, { "standby", "settings_sleep" }, { "shutdown", "settings_sleep" },
    { "wallpaper", "wallpaper" }, { "screensaver", "wallpaper" }, { "picture", "wallpaper" }, { "image", "wallpaper" },
    { "cover", "settings_covers" }, { "thumbnail", "settings_covers" },
    { "warmth", "schedule_warmth" }, { "brightness", "schedule_brightness" }, { "frontlight", "schedule_brightness" },
    { "light", "schedule_brightness" }, { "night", "schedule_night" }, { "dark", "schedule_night" },
    { "time zone", "calendar" }, { "calendar", "calendar" }, { "date", "calendar" }, { "time", "tbr" },
    { "clock", "tbr" }, { "schedule", "tbr" }, { "duration", "tbr" }, { "interval", "tbr" }, { "timeout", "tbr" },
    { "minute", "tbr" }, { "second", "tbr" }, { "delay", "tbr" }, { "postpone", "tbr" },
    { "accent", "settings_accent" }, { "colo", "settings_accent" }, { "theme", "reader_themes" }, { "contrast", "settings_accent" },
    { "font", "font" }, { "bold", "font" }, { "text", "font" }, { "typograph", "font" }, { "hyphen", "font" },
    { "language", "language" }, { "dictionar", "language" }, { "wikipedia", "language" }, { "translat", "language" },
    { "keyboard", "keyboard" }, { "key", "keyboard" }, { "button", "keyboard" },
    { "gesture", "double_tap" }, { "tap", "double_tap" }, { "swipe", "bottom_swipe" }, { "touch", "double_tap" },
    { "drag", "double_tap" }, { "hold", "double_tap" },
    { "rotat", "flip_lh_rh" }, { "orientation", "flip_lh_rh" }, { "mirror", "flip_lh_rh" }, { "invert", "flip_lh_rh" },
    { "refresh", "refresh" }, { "flash", "refresh" }, { "e-ink", "refresh" }, { "ghost", "refresh" },
    { "screen", "display" }, { "display", "display" }, { "dpi", "display" }, { "fullscreen", "display" },
    { "status bar", "settings_status" }, { "header", "settings_status" }, { "footer", "settings_status" },
    { "navbar", "settings_navbar" }, { "tab", "navbar_tabs" },
    { "widget", "widgets" }, { "home", "settings_home" }, { "end of book", "end_book" },
    { "chapter", "chapter_time_format" }, { "page browser", "page_browser" }, { "page", "page_browser" },
    { "bookmark", "favorite" }, { "favorite", "favorite" }, { "highlight", "edit" }, { "note", "edit" },
    { "annotation", "edit" }, { "edit", "edit" }, { "rename", "rename" }, { "label", "label" }, { "title", "title" },
    { "author", "authors" }, { "series", "series" },
    { "metadata", "details" }, { "book", "reading" }, { "document", "reading" }, { "read", "reading" },
    { "history", "history" }, { "recent", "history" },
    { "sort", "sort" }, { "order", "sort" }, { "arrange", "sort" }, { "filter", "filter" }, { "status", "status" },
    { "search", "search" }, { "find", "search" }, { "lookup", "search" },
    { "folder", "folder_open" }, { "file", "filename" }, { "path", "folder_open" },
    { "layout", "settings_layout" }, { "margin", "settings_layout" }, { "align", "settings_layout" },
    { "size", "settings_layout" }, { "spacing", "settings_layout" }, { "width", "settings_layout" }, { "height", "settings_layout" },
    { "border", "divider" }, { "separator", "divider" }, { "line", "divider" }, { "underline", "settings_underline" },
    { "scroll", "settings_scroll" }, { "background", "settings_background" }, { "blur", "settings_menu_blur" },
    { "icon", "custom_icons" }, { "preset", "save" }, { "plugin", "plugin" }, { "guide", "settings_setup" },
    { "help", "details" }, { "about", "details" }, { "info", "details" },
    { "memos", "edit" }, { "caldav", "calendar" }, { "sso", "connect" }, { "sign", "connect" }, { "pin", "label" },
    { "navigation", "go" }, { "advanced", "settings_advanced" }, { "option", "settings" }, { "setting", "settings" }, { "menu", "open_menu" },
}

-- by the kind of row, when its text names nothing above
M.KIND = { submenu = "settings", switch = "check", choice = "select", action = "go", info = "details" }

local function text_of(item)
    local s = item._zen_display_text or item.text
    if s == nil and type(item.text_func) == "function" then
        local ok, v = pcall(item.text_func)
        s = ok and v or nil
    end
    return type(s) == "string" and s or ""
end

--- What kind of row `item` is: "submenu", "switch", "choice", "action" or "info".
function M.kind(item)
    if item.sub_item_table or item.sub_item_table_func or item._zen_settings_submenu then return "submenu" end
    if item.radio then return "choice" end
    if item.checked_func or item.checked ~= nil then return "switch" end
    if item.callback or item.hold_callback then return "action" end
    return "info"
end

--- The inline_icon_map key for a row without an icon of its own.
function M.keyFor(item)
    if type(item) ~= "table" then return nil end
    local text = " " .. text_of(item):lower()
    for _i, rule in ipairs(M.RULES) do
        -- (at a word's start: "ram" is RAM, not "program"; "tap" not "stop")
        if text:find("%f[%w]" .. rule[1]:gsub("%p", "%%%0")) then return rule[2] end
    end
    return M.KIND[M.kind(item)]
end

--- The glyph for a row without an icon of its own (nil if it has one).
function M.glyphFor(item)
    if type(item) ~= "table" or item.icon_glyph or item.icon_file or item.icon_name then return nil end
    local key = M.keyFor(item)
    return key and require("common/inline_icon_map")[key] or nil
end

return M
