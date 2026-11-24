local ZEN = arg[1]
package.path = ZEN .. "/?.lua;" .. package.path
if arg[2] then package.path = arg[2] .. "/?.lua;" .. package.path end -- (GZreader's plugin: gzreader_setupdevice)
local function magic()
    local m
    m = setmetatable({}, { __index = function() return function() return m end end, __call = function() return m end })
    return m
end
-- anything ZenOS needs that we don't provide becomes a harmless stub
table.insert(package.loaders, 2, function(name)
    if name == "gettext" then return function() return function(s) return s end end end
    if name == "ffi/util" then return function() return { template = function(f, ...) local a = { ... }; return (f:gsub("%%(%d)", function(i) return tostring(a[tonumber(i)]) end)) end } end end
    if name:match("^common/quickstart/") or name == "common/quickstart_pages" or name == "common/gz_server_recent" or name == "gzreader_setupdevice" then return nil end
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
    local built = M.build_install_pages({ plugin = { ui = { gzreader = grimmory } },
        config = { navbar = { show_tabs = {} }, _meta = {}, features = {} } })
    built.gz_store = grimmory.store
    return built
end
local ok_count, fail = 0, 0
local function check(c, n) if c then ok_count = ok_count + 1 print("  ok   " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

HOME_SET = 0
local pages = build(false)
local has_folder_page = false
for _, pg in ipairs(pages) do if pg.title == "Home Folder" then has_folder_page = true end end
check(not has_folder_page, "no 'Home Folder' question in the guide")
check(HOME_SET == 1, "guide sets the home folder to the Grimmory folder instead")
check(pages[1].title == "Set up GZreader", "the setup guide starts by asking how to set up: with a phone or on this device")
check(pages[2].title == "Set up with your phone", "then what the answer leads to (the phone, to start with)")
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
-- the first question: with my phone, or on this device
local function finale(pgs) return pgs[#pgs] end
local function syncPage(pgs) for _, pg in ipairs(pgs) do if pg.gz_sync_page then return pg end end end
local function tabsPage(pgs) for _, pg in ipairs(pgs) do if pg.title == "Navbar Tabs" then return pg end end end
local how, connect = pages[1], pages[2]
check(how.choice_type == "radio" and idsOf(how) == "phone*,device,skip", "how: with my phone (the default), on this device, or skip")
check(not connect.choices and connect.description:match("QR code shows") and connect.description:match("Notes, Calendar"),
    "with my phone: the next page says the QR code comes when the guide ends (nothing to choose)")
BROADCAST = nil; connect.on_apply({}); check(BROADCAST == nil, "…nothing opens in the middle of the guide")
finale(pages).on_apply({}); check(BROADCAST == "GrimmoryPair", "…the guide's last page: the setup page's QR code")
BROADCAST = nil; finale(pages).on_apply({}); check(BROADCAST == nil, "…once")
-- on this device: which services
connect.reset_selection = nil
how.on_apply({ device = true })
check(connect.title == "What do you want to set up?" and connect.choice_type == "checkbox" and connect.reset_selection == true
    and idsOf(connect) == "grimmory,bookorbit,memos,house,immich,mealie,calendar" and connect.description:match("tick one"),
    "on this device: tick boxes for Grimmory, BookOrbit, Memos, Home Assistant, Immich, Mealie, Calendar (Plex only where audio plays) " .. idsOf(connect))
check(connect.choices[1].text:match("^Grimmory: ") and connect.choices[4].text:match("^Home Assistant: "), "…each says what it gives")
local sel = connect.on_toggle({ grimmory = true, memos = true }, "grimmory")
check(sel.grimmory and sel.memos, "ticking Grimmory: ticked")
sel = connect.on_toggle({ grimmory = true, bookorbit = true, memos = true }, "bookorbit")
check(sel.bookorbit and sel.grimmory == nil and sel.memos, "ticking BookOrbit unticks Grimmory (one book server), the rest as it was")
sel = connect.on_toggle({ grimmory = true, bookorbit = true }, "grimmory")
check(sel.grimmory and sel.bookorbit == nil, "…and the other way round")
sel = connect.on_toggle({ bookorbit = true }, "memos")
check(sel.bookorbit and not sel.memos, "unticking another box changes nothing else")
local store = pages.gz_store
SAVES = 0; BROADCAST = nil
connect.on_apply({ bookorbit = true, calendar = true })
check(store.book_source == "bookorbit" and table.concat(store.setup_services, ",") == "bookorbit,calendar" and SAVES == 1 and BROADCAST == nil,
    "Next: the book server and the services ticked are remembered; nothing opens yet")
local tp = tabsPage(pages)
local tab = {} for _, c in ipairs(tp.choices) do tab[c.id] = c.checked end
check(tab.ct_calendar == true and tab.ct_notes == false and tp.reset_selection == true and tab.home == true,
    "…the Navbar Tabs page follows: Calendar ticked, Notes (Memos, not ticked) unticked, the other tabs as they were")
check(syncPage(pages).title == "Books from BookOrbit", "…the guide's sync page is BookOrbit's")
finale(pages).on_apply({}); check(BROADCAST == "GzSetupOnDevice", "…the guide's last page: the list of the ticked services, to connect by typing")
BROADCAST = nil
connect.on_apply({ memos = true })
check(store.book_source == "local" and syncPage(pages).title == "Your books", "no book server ticked: books sent from a browser (the sync page says so)")
connect.on_apply({})
finale(pages).on_apply({}); check(BROADCAST == nil and #store.setup_services == 0, "nothing ticked: nothing opens")
connect.on_apply({ grimmory = true })
check(syncPage(pages).title == "Synced with Grimmory", "Grimmory ticked: as before")
-- skip, and back to the phone
how.on_apply({ skip = true })
check(connect.title == "Set up later" and not connect.choices and connect.description:match("Accounts and services"), "skip: where to set up later")
BROADCAST = nil; connect.on_apply({ grimmory = true }); finale(pages).on_apply({})
check(BROADCAST == nil, "…and nothing opens (ticks left from before don't count)")
how.on_apply({ phone = true }); connect.on_apply({}); finale(pages).on_apply({})
check(BROADCAST == "GrimmoryPair", "back to the phone: the QR code at the end")
-- what was answered before, and what this Kindle is signed in to
local again = build(false, nil, "local")
check(syncPage(again).title == "Your books", "an earlier answer (no book server): the sync page fits it from the start")
BROADCAST = nil; again[2].on_apply({}); finale(again).on_apply({})
check(BROADCAST == "GzSendBooksPage", "…and the phone's page opens at Send books")
local orbit_first = build(false, nil, "bookorbit")
BROADCAST = nil; orbit_first[2].on_apply({}); finale(orbit_first).on_apply({})
check(BROADCAST == "BookOrbitPair", "an earlier answer of BookOrbit: the phone's page with BookOrbit picked")
pages = build(true)
how, connect = pages[1], pages[2]
check(idsOf(how) == "keep*,phone,device,skip" and how.choices[1].text:match("will") and connect.title == "Already connected" and connect.description:match("will"),
    "connected already: keep (default) shows the account")
BROADCAST = nil; connect.on_apply({}); finale(pages).on_apply({}); check(BROADCAST == nil, "keep -> nothing opens")
how.on_apply({ device = true })
check(idsOf(connect):match("^grimmory%*,bookorbit,"), "…on this device: what's connected is ticked to start with")
local orbit = build(true, "bookorbit", "grimmory")
orbit[1].on_apply({ device = true })
check(idsOf(orbit[2]):match("^grimmory,bookorbit%*,"), "connected to BookOrbit: that box is the one ticked")
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
-- Home's "Recently read on every device": asked after Library View, fitted to the answer
do
    local none_titles = {}
    for _, pg in ipairs(build(false)) do none_titles[#none_titles + 1] = pg.title end
    check(not table.concat(none_titles, "|"):match("Recently read on every device"), "without GZreader's hook: no recently read page")
    local was_on, set_to = false, nil
    rawset(_G, "__GZ_SERVER_RECENT", { on = function() return was_on end, set = function(v) set_to = v end, name = function() return "Grimmory" end })
    local rp = build(false, nil, "grimmory")
    local at, lib_at, rpage
    for i, pg in ipairs(rp) do
        if pg.title == "Recently read on every device" then at, rpage = i, pg end
        if pg.title == "Library View" then lib_at = i end
    end
    check(rpage and at == lib_at + 1, "recently read on every device: asked right after Library View")
    check(rpage and rpage.description:match("from Grimmory") and idsOf(rpage) == "recent_on*,recent_off" and rpage.description:match("arrow")
        and rpage.description:match("Wi‑Fi"), "with Grimmory: yes picked, it names Grimmory and says what it shows")
    rpage.on_apply({ recent_on = true })
    check(set_to == true, "yes turns the option on (through GZreader)")
    rpage.on_apply({ recent_off = true })
    check(set_to == false, "only this Kindle turns it off")
    -- the services ticked (set up on this device) change it
    rp[1].on_apply({ device = true })
    rp[2].on_apply({ bookorbit = true })
    check(rpage.description:match("from BookOrbit") and rpage.reset_selection, "BookOrbit ticked: it names BookOrbit")
    rp[2].on_apply({ memos = true })
    check(idsOf(rpage) == "recent_off*,recent_on" and rpage.description:match("when this Kindle is connected to a book server"),
        "on its own: not now picked, it says it comes with a book server")
    local bo = build(false, nil, "bookorbit")
    for _, pg in ipairs(bo) do if pg.title == "Recently read on every device" then rpage = pg end end
    check(rpage.description:match("from BookOrbit"), "a BookOrbit setup: asked too, naming BookOrbit")
    rawset(_G, "__GZ_SERVER_RECENT", nil)
end
print(ok_count .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
