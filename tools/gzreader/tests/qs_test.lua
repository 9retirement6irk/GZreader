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
local function build(paired, backend, source)
    local grimmory = { api = { isPaired = function() return paired end }, store = { username = "will", book_source = source },
        backend = function() return backend or "grimmory" end, save = function() SAVES = (SAVES or 0) + 1 end,
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
check(pages[1].title == "How will you use GZreader?", "the setup guide starts by asking how GZreader will be used")
check(pages[2].title == "Set up from your browser", "then Set up from your browser (the book server, Notes, Calendar, books)")
check(pages[3].title == "Welcome to GZreader", "GZreader welcome follows")
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
local function idsOf(pg) local ids = {} for _, c in ipairs(pg.choices) do ids[#ids + 1] = c.id .. (c.checked and "*" or "") end return table.concat(ids, ",") end
-- the first question: Grimmory, BookOrbit, or on its own
local how, connect = pages[1], pages[2]
check(how.choice_type == "radio" and idsOf(how) == "grimmory*,bookorbit,local", "how: Grimmory (the default), BookOrbit, or on its own with books from a browser")
check(idsOf(connect) == "qr*,type,gz_copy,skip" and connect.description:match("connect Grimmory"), "Grimmory, not connected: QR (default), type, copy from another GZreader, skip")
BROADCAST = nil; connect.on_apply({ qr = true });   check(BROADCAST == "GrimmoryPair", "QR choice -> GrimmoryPair event")
BROADCAST = nil; connect.on_apply({ type = true }); check(BROADCAST == "GrimmoryKeyboardLogin", "type choice -> keyboard login event")
BROADCAST = nil; connect.on_apply({ skip = true }); check(BROADCAST == nil, "skip -> nothing")
BROADCAST = nil; connect.on_apply({ gz_copy = true }); check(BROADCAST == "GzCopyReceive", "copy choice -> GzCopyReceive event")
connect.reset_selection = nil; SAVES = 0
how.on_apply({ grimmory = true })
check(connect.reset_selection == nil and SAVES == 1, "answering Grimmory: the next page stays as it is; the answer is saved")
how.on_apply({ grimmory = true })
check(SAVES == 1, "the same answer again isn't saved twice")
how.on_apply({ bookorbit = true })
check(idsOf(connect) == "bo_qr*,bo_type,skip" and connect.reset_selection == true and connect.description:match("connect BookOrbit")
    and connect.description:match("KOReader sync user name") and connect.choices[2].text == "Type my BookOrbit login here",
    "answering BookOrbit: the next page is BookOrbit's (which sign-in it wants), its defaults again")
BROADCAST = nil; connect.on_apply({ bo_qr = true });   check(BROADCAST == "BookOrbitPair", "BookOrbit, from a browser -> BookOrbitPair event")
BROADCAST = nil; connect.on_apply({ bo_type = true }); check(BROADCAST == "BookOrbitKeyboardLogin", "BookOrbit, typed -> its keyboard login event")
how.on_apply({ ["local"] = true })
check(idsOf(connect) == "books*,gz_copy,skip" and connect.title == "Send books from your browser" and connect.description:match("drop your books"),
    "answering on its own: the next page is sending books from a browser")
BROADCAST = nil; connect.on_apply({ books = true }); check(BROADCAST == "GzSendBooksPage", "show the QR code -> the setup page at Send books")
check(SAVES == 3, "each new answer is saved")
local function syncPage(pgs) for _, pg in ipairs(pgs) do if pg.gz_sync_page then return pg end end end
check(syncPage(pages).title == "Your books" and syncPage(pages).description:match("kept on this Kindle"), "on its own: the guide's sync page says the books stay on the Kindle")
how.on_apply({ bookorbit = true })
check(syncPage(pages).title == "Books from BookOrbit" and syncPage(pages).description:match("browse and download your books"), "BookOrbit: it says what works (gzreader_bookorbit's note, when it loads)")
how.on_apply({ grimmory = true })
check(syncPage(pages).title == "Synced with Grimmory" and syncPage(pages).description:match("in sync with Grimmory"), "Grimmory again: as before")
-- what was answered before, and what this Kindle is signed in to
local again = build(false, nil, "local")
check(syncPage(again).title == "Your books", "…and the sync page fits it from the start")
check(idsOf(again[1]) == "grimmory,bookorbit,local*" and again[2].title == "Send books from your browser", "the guide again: the earlier answer is the default")
pages = build(true)
how, connect = pages[1], pages[2]
check(idsOf(how) == "grimmory*,bookorbit,local" and idsOf(connect) == "keep*,qr,type,gz_copy,gz_send,skip" and connect.choices[1].text:match("will"),
    "connected to Grimmory: keep (default) shows the account; send to another GZreader offered")
BROADCAST = nil; connect.on_apply({ gz_send = true }); check(BROADCAST == "GzCopySend", "send choice -> GzCopySend event")
BROADCAST = nil; connect.on_apply({ keep = true }); check(BROADCAST == nil, "keep -> nothing")
how.on_apply({ bookorbit = true })
check(idsOf(connect) == "bo_qr*,bo_type,gz_send,skip", "connected to Grimmory, answering BookOrbit: no \"keep\" (it's the other server's)")
local orbit = build(true, "bookorbit", "grimmory")
check(idsOf(orbit[1]) == "grimmory,bookorbit*,local" and idsOf(orbit[2]) == "keep*,bo_qr,bo_type,gz_send,skip",
    "connected to BookOrbit: that's the default (whatever was answered before), and its connection can be kept")
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
    check(order == "home,books,ct_grimmory,ct_notes,ct_calendar,continue,favorites,ct_music,ct_audiobooks,ct_house,ct_recipes,history", "setup tabs: a tab turned on is added to the list (" .. order .. ")")
    local house_tab
    for _, t in ipairs(defaults.navbar.custom_tabs) do if t.id == "ct_house" then house_tab = t end end
    check(house_tab and house_tab.action.gzreader_house and house_tab.icon == "tab_house" and house_tab.label == "House"
        and defaults.navbar.show_tabs.ct_house == false, "the House tab (Home Assistant): defined, off by default")
    local recipes_tab
    for _, t in ipairs(defaults.navbar.custom_tabs) do if t.id == "ct_recipes" then recipes_tab = t end end
    local icon_f = io.open(ZEN .. "/icons/tab_recipes.svg", "rb")
    check(recipes_tab and recipes_tab.action.gzreader_recipes and recipes_tab.icon == "tab_recipes" and recipes_tab.label == "Recipes"
        and defaults.navbar.show_tabs.ct_recipes == false and icon_f ~= nil, "the Recipes tab (Mealie): defined, off by default, with its icon")
    if icon_f then icon_f:close() end
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
