local ZEN = arg[1]
package.path = ZEN .. "/?.lua;" .. package.path
local function magic()
    local m
    m = setmetatable({}, { __index = function() return function() return m end end, __call = function() return m end })
    return m
end
-- anything ZenOS needs that we don't provide becomes a harmless stub
table.insert(package.loaders, 2, function(name)
    if name == "gettext" then return function() return function(s) return s end end end
    if name == "ffi/util" then return function() return { template = function(f, ...) local a = { ... }; return (f:gsub("%%(%d)", function(i) return tostring(a[tonumber(i)]) end)) end } end end
    if name:match("^common/quickstart/") or name == "common/quickstart_pages" then return nil end
    if name == "ui/event" then return function() return { new = function(_, n) return { name = n } end } end end
    if name == "ui/uimanager" then return function() return { scheduleIn = function(_, _, f) f() end, broadcastEvent = function(_, ev) BROADCAST = ev.name end } end end
    if name == "common/plugin_root" then return function() return "" end end
    return function() return magic() end
end)
G_reader_settings = { readSetting = function() end }
local M = dofile(ZEN .. "/common/quickstart/quickstart_pages.lua")
local function build(paired)
    local grimmory = { api = { isPaired = function() return paired end }, store = { username = "will" },
        useLibraryAsHome = function() HOME_SET = (HOME_SET or 0) + 1 end }
    return M.build_install_pages({ plugin = { ui = { gzreader = grimmory } },
        config = { navbar = { show_tabs = {} }, _meta = {}, features = {} } })
end
local ok_count, fail = 0, 0
local function check(c, n) if c then ok_count = ok_count + 1 print("  ok   " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

HOME_SET = 0
local pages = build(false)
local has_folder_page = false
for _, pg in ipairs(pages) do if pg.title == "Home Folder" then has_folder_page = true end end
check(not has_folder_page, "no 'Home Folder' question in the guide")
check(HOME_SET == 1, "guide sets the home folder to the Grimmory folder instead")
check(pages[1].title == "Set up from your browser", "setup guide starts with Set up from your browser (Grimmory, Notes, Calendar, books)")
check(pages[2].title == "Welcome to GZreader", "GZreader welcome follows")
local titles = {} for _, pg in ipairs(pages) do titles[#titles + 1] = pg.title end
local tl = table.concat(titles, "|")
check(tl:match("Your keyboard") and tl:match("Synced with Grimmory"), "GZreader pages: keyboard, sync")
check(not tl:match("Zen Mode") and not tl:match("|Reader|") and not tl:match("While reading") and not tl:match("Settings & Updates"),
    "setup guide 1.23.13: no Zen mode, Reader, While reading or Settings & Updates pages")
check(titles[#titles] == "You're All Set" and titles[#titles - 1] == "Debug Reports" and not tl:match("Usage Statistics"),
    "debug reports just before the end (no usage statistics page)")
local dbg = pages[#pages - 1]
check(dbg.choices[1].id == "on" and dbg.choices[2].id == "off" and dbg.choices[2].checked and not dbg.choices[1].checked
    and dbg.description:match("freeze") and dbg.description:match("Never passwords"),
    "debug reports: send automatically or not, off unless chosen; says what a report has")
package.loaded["gzreader_remote"] = { setSetting = function(v) DEBUG_SET = v end }
dbg.on_apply({ on = true })
local first = DEBUG_SET
dbg.on_apply({ off = true })
package.loaded["gzreader_remote"] = nil
check(first == true and DEBUG_SET == false, "the choice is saved through gzreader_remote (starts or stops them at once)")
local kbp, syncp for _, pg in ipairs(pages) do if pg.title == "Your keyboard" then kbp = pg elseif pg.title == "Synced with Grimmory" then syncp = pg end end
check(kbp.icon_file:match("keyboard%.svg$") and syncp.icon_file:match("library%.svg$"), "keyboard and Grimmory icons")
-- a Kindle without Wi-Fi (Kindle 2, DX): how to sync with a computer instead
package.loaded["gzreader_net"] = { usb = true }
local usb_pages = build(false)
package.loaded["gzreader_net"] = nil
local usb_titles = {} for _, pg in ipairs(usb_pages) do usb_titles[#usb_titles + 1] = pg.title end
check(not table.concat(usb_titles, "|"):match("Debug Reports"), "no Wi-Fi: no debug reports page (it couldn't send them)")
check(usb_pages[1].title == "Sync with a computer" and usb_pages[1].description:match("GZreader/sync")
    and not usb_pages[1].choices and usb_pages[1].icon_file:match("usb%.svg$"),
    "no Wi-Fi: the guide starts with syncing through a computer (the page's address)")
local lib for _, pg in ipairs(pages) do if pg.title == "Library View" then lib = pg end end
check(lib.choices[1].id == "bookshelf", "library view: bookshelf first (with its own preview)")
-- the finale applies the reading defaults the Reader page used to
local fin = pages[#pages]
check(type(fin.on_apply) == "function", "the finale applies the reading defaults on a first setup")
check(not tl:match("Context Menu") and not tl:match("Quick Settings") and not tl:match("Page Browser"), "touch-only pages removed")
local sleep for _, pg in ipairs(pages) do if pg.title == "Sleep Screen" then sleep = pg end end
check(sleep and sleep.choices[1].id == "gz_auto" and sleep.choices[1].checked, "sleep screen: cover while reading / screensavers folder otherwise is the default")
check(sleep.choice_layout == "tiles" and #sleep.choices == 4 and sleep.choices[3].preview == "zen_white",
    "sleep screen: tiles with previews (no 'Keep current' on a first setup)")
local SAVED = {} G_reader_settings.makeTrue = function(_, k) SAVED[k] = true end G_reader_settings.makeFalse = function(_, k) SAVED[k] = false end
sleep.on_apply({ gz_auto = true }) check(SAVED.gzreader_sleep_auto == true and SAVED.screensaver_show_message == false,
    "choosing it turns GZreader sleep mode on (no message over it)")
local ids = {} for _, c in ipairs(pages[1].choices) do ids[#ids + 1] = c.id .. (c.checked and "*" or "") end
check(table.concat(ids, ",") == "qr*,type,gz_copy,skip", "not connected: QR (default), type, copy from another GZreader, skip")
BROADCAST = nil; pages[1].on_apply({ qr = true });   check(BROADCAST == "GrimmoryPair", "QR choice -> GrimmoryPair event")
BROADCAST = nil; pages[1].on_apply({ type = true }); check(BROADCAST == "GrimmoryKeyboardLogin", "type choice -> keyboard login event")
BROADCAST = nil; pages[1].on_apply({ skip = true }); check(BROADCAST == nil, "skip -> nothing")
BROADCAST = nil; pages[1].on_apply({ gz_copy = true }); check(BROADCAST == "GzCopyReceive", "copy choice -> GzCopyReceive event")
pages = build(true)
ids = {} for _, c in ipairs(pages[1].choices) do ids[#ids + 1] = c.id .. (c.checked and "*" or "") end
check(table.concat(ids, ",") == "keep*,qr,type,gz_copy,gz_send,skip" and pages[1].choices[1].text:match("will"), "already connected: keep (default) shows account; send to another GZreader offered")
BROADCAST = nil; pages[1].on_apply({ gz_send = true }); check(BROADCAST == "GzCopySend", "send choice -> GzCopySend event")
BROADCAST = nil; pages[1].on_apply({ keep = true }); check(BROADCAST == nil, "keep -> nothing")
local np = M.build_install_pages({ plugin = { ui = {} }, config = { navbar = { show_tabs = {} }, _meta = {}, features = {} } })
check(np[1].title == "Welcome to GZreader", "no Grimmory plugin -> starts with the welcome")

-- Navbar Tabs page: Notes on by default, Favorites offered (off)
do
    local defaults = dofile(ZEN .. "/config/defaults.lua")
    local function copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end
    local cfg = { navbar = copy(defaults.navbar), _meta = {}, features = {} }
    local pg
    for _, p in ipairs(M.build_install_pages({ plugin = { ui = {} }, config = cfg })) do if p.title == "Navbar Tabs" then pg = p end end
    local state = {}
    for _, c in ipairs(pg and pg.choices or {}) do state[c.id] = c.checked end
    check(state.ct_notes == true and state.ct_calendar == true and state.continue == false and state.favorites == false and state.home == true,
        "setup tabs: Notes and Calendar on; Continue and Favorites offered but off")
    local kb
    for _, p in ipairs(M.build_install_pages({ plugin = { ui = {} }, config = cfg })) do if p.title == "Your keyboard" then kb = p end end
    check(kb and kb.description:match("^Z X C V B: the tabs"), "setup guide: the keyboard page names Z X C V B")
    check(pg.max_selections == 5, "setup tabs: room left for Downloads and Grimmory (7 in all)")
    local sel = { home = true, continue = true, favorites = true, history = true }
    pg.on_apply(sel)
    local order = table.concat(cfg.navbar.tab_order, ",")
    check(cfg.navbar.show_tabs.favorites == true and cfg.navbar.show_tabs.ct_notes == false and cfg.navbar.show_tabs.ct_grimmory == true,
        "setup tabs: Favorites on, Notes off, Grimmory untouched")
    check(order == "home,books,ct_grimmory,ct_notes,ct_calendar,continue,favorites,ct_music,ct_audiobooks,ct_house,history", "setup tabs: a tab turned on is added to the list (" .. order .. ")")
    local house_tab
    for _, t in ipairs(defaults.navbar.custom_tabs) do if t.id == "ct_house" then house_tab = t end end
    check(house_tab and house_tab.action.gzreader_house and house_tab.icon == "tab_house" and house_tab.label == "House"
        and defaults.navbar.show_tabs.ct_house == false, "the House tab (Home Assistant): defined, off by default")
    local ab_tab
    for _, t in ipairs(defaults.navbar.custom_tabs) do if t.id == "ct_audiobooks" then ab_tab = t end end
    check(ab_tab and ab_tab.action.gzreader_audiobooks and ab_tab.icon == "tab_audiobooks" and defaults.navbar.show_tabs.ct_audiobooks == false
        and (state.ct_audiobooks == nil or state.ct_audiobooks == false),
        "the Audiobooks tab: defined, off by default (offered on Kindles with audio)")
    local catalog_tab
    for _, t in ipairs(defaults.navbar.custom_tabs) do if t.id == "ct_grimmory" then catalog_tab = t end end
    check(catalog_tab and catalog_tab.label == "Catalog", "the Grimmory tab is labelled Catalog")
    check(cfg.navbar.show_tabs.ct_calendar == false and cfg.navbar.show_tabs.continue == true, "setup tabs: Calendar off and Continue on when chosen so")
end
print(ok_count .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
