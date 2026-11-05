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
check(tl:match("Your keyboard") and tl:match("Synced with Grimmory") and tl:match("While reading"), "GZreader pages: keyboard, sync, reading")
check(not tl:match("Context Menu") and not tl:match("Quick Settings") and not tl:match("Page Browser"), "touch-only pages removed")
local sleep for _, pg in ipairs(pages) do if pg.title == "Sleep Screen" then sleep = pg end end
check(sleep and sleep.choices[1].id == "gz_auto" and sleep.choices[1].checked, "sleep screen: cover while reading / screensavers folder otherwise is the default")
local SAVED = {} G_reader_settings.makeTrue = function(_, k) SAVED[k] = true end G_reader_settings.makeFalse = function(_, k) SAVED[k] = false end
sleep.on_apply({ gz_auto = true }) check(SAVED.gzreader_sleep_auto == true, "choosing it turns GZreader sleep mode on")
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
    check(kb and kb.description:match("^Z, X, C, V, B: switch the bottom tabs"), "setup guide: the keyboard page names Z, X, C, V, B")
    check(pg.max_selections == 5, "setup tabs: room left for Downloads and Grimmory (7 in all)")
    local sel = { home = true, continue = true, favorites = true, history = true }
    pg.on_apply(sel)
    local order = table.concat(cfg.navbar.tab_order, ",")
    check(cfg.navbar.show_tabs.favorites == true and cfg.navbar.show_tabs.ct_notes == false and cfg.navbar.show_tabs.ct_grimmory == true,
        "setup tabs: Favorites on, Notes off, Grimmory untouched")
    check(order == "home,books,ct_grimmory,ct_notes,ct_calendar,continue,favorites,ct_music,history", "setup tabs: a tab turned on is added to the list (" .. order .. ")")
    check(cfg.navbar.show_tabs.ct_calendar == false and cfg.navbar.show_tabs.continue == true, "setup tabs: Calendar off and Continue on when chosen so")
end
print(ok_count .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
