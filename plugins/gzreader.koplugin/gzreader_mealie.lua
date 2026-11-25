--[[--
Mealie (https://mealie.io) client for the Recipes tab (gzreader_recipes.lua):
your recipes, to read from the Kindle.

It talks to Mealie's REST API directly:

- Sign-in, one of two ways. Either way the Kindle keeps an API token (sent
  as "Authorization: Bearer"), never a password, and never writes it to the
  log.
  - An API token you make in Mealie (your profile → API tokens).
  - Single sign-on, when Mealie has it (OIDC): from the setup page in a
    browser (gzreader_phone.lua). Mealie's sign-on for apps
    (/api/auth/oauth/native/config and …/token: the app sends the browser to
    the identity provider itself, with PKCE, and hands Mealie the code)
    answers with a session token that lasts a day or two; with it GZreader
    asks Mealie for an API token of its own ("GZreader", listed in your
    profile, where it can be deleted) and keeps only that.
- Recipes: GET /api/recipes (a page at a time; search, one category),
  GET /api/organizers/categories, GET /api/recipes/<slug> (ingredients,
  steps, notes).

Nothing here touches the screen: gzreader_recipes.lua draws, and runs these
in the background (gzreader_async.lua).
]]

local DataStorage = require("datastorage")
local JSON = require("gzreader_json")
local _ = require("gettext")
local T = require("ffi/util").template

local Mealie = {
    PER_PAGE = 50,
    TOKEN_NAME = "GZreader", -- (the API token made after single sign-on, as Mealie lists it)
}
Mealie.__index = Mealie

--- `store` is plugin.store.mealie (server, token, name, version, sso,
--- token_id).
function Mealie:new(store)
    return setmetatable({ store = store or {} }, self)
end

function Mealie:isConnected()
    return self.store.server ~= nil and self.store.token ~= nil
end

local function str(x) return type(x) == "string" and x ~= "" and x or nil end

local function num(x)
    x = tonumber(x)
    if x and x == x and x ~= math.huge and x ~= -math.huge then return x end
end

---------------------------------------------------------------- addresses

--- The address typed or pasted, without the page's path ("/g/home",
--- "/login", "/api"): scheme://host[:port], or nil. With no scheme typed,
--- https:// (candidates() says what else to try).
function Mealie.normalizeServer(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    local scheme = s:match("^(%a[%w+.-]*)://")
    if scheme and scheme:lower() ~= "http" and scheme:lower() ~= "https" then return nil end
    if not scheme then s = "https://" .. s end
    local base = s:match("^(%a+://[^/?#]+)")
    if not base then return nil end
    local hostport = base:match("://(.+)$")
    if hostport:find("[%s@]") then return nil end
    return base
end

--- The addresses to try for what was typed, in order. A scheme typed: that
--- one. None typed: on the home network plain HTTP first (Mealie's own
--- port), then HTTPS; an address on the internet HTTPS only (a token isn't
--- sent over plain HTTP unless http:// is typed).
function Mealie.candidates(server_input)
    local base = Mealie.normalizeServer(server_input)
    if not base then return nil end
    if tostring(server_input):match("^%s*%a[%w+.-]*://") then return { base }, false end
    if require("gzreader_lan").isPrivate(base) then
        return { (base:gsub("^https://", "http://")), base }, true
    end
    return { base }, true
end

---------------------------------------------------------------- requests

--- One request. Returns code, data, err: "unreachable", "unauthorized"
--- (401/403), "not_found", "http_<code>". opts.token: instead of the kept
--- one (single sign-on's session token); opts.public: no token at all;
--- opts.log_path: what the log shows as the path instead.
function Mealie:request(method, path, body, opts)
    opts = opts or {}
    local token = opts.token or self.store.token
    if not self.store.server or not (token or opts.public) then return nil, nil, "not_connected" end
    local Api = require("gzreader_api")
    local code, data = Api.rawRequest(method, self.store.server .. path, {
        headers = token and not opts.public and { ["Authorization"] = "Bearer " .. token } or nil,
        body = body,
        timeouts = opts.timeouts or { 8, 25 },
        expected = opts.expected,
        -- (what was searched for stays out of the log)
        log_url = opts.log_path and (self.store.server .. opts.log_path) or nil,
    })
    if not code then return nil, nil, "unreachable" end
    if code == 401 or code == 403 then return code, data, "unauthorized" end
    if code == 404 then return code, data, "not_found" end
    if code >= 400 then return code, data, "http_" .. code end
    return code, data
end

--- The same, without the status code: data, err.
function Mealie:ask(method, path, body, opts)
    return select(2, self:request(method, path, body, opts))
end

--- What the server says about itself (no sign-in needed): { version, oidc,
--- provider, password }, or nil, err ("not_mealie": something else answered).
function Mealie:about()
    local data, err = self:ask("GET", "/api/app/about", nil, { public = true })
    -- (Mealie answers this without a sign-in: a server that wants one, or has no such page, is something else)
    if err == "not_found" or err == "unauthorized" then return nil, "not_mealie" end
    if err then return nil, err end
    if type(data) ~= "table" or type(data.version) ~= "string" then return nil, "not_mealie" end
    return {
        version = data.version,
        oidc = data.enableOidc == true,
        provider = str(data.oidcProviderName),
        password = data.allowPasswordLogin ~= false,
    }
end

--- Who the token is: { name, username }, or nil, err.
function Mealie:whoami(opts)
    local data, err = self:ask("GET", "/api/users/self", nil, opts)
    if err then return nil, err end
    if type(data) ~= "table" or not (str(data.username) or str(data.email)) then return nil, "bad_answer" end
    return { name = str(data.fullName) or str(data.username) or str(data.email), username = str(data.username) }
end

---------------------------------------------------------------- recipes

--- "PT15M", "15 minutes", "1 hour 5 minutes" as Mealie gives a time: shown
--- as it is, an ISO duration ("PT1H5M") as "1 h 5 min".
function Mealie.timeText(v)
    v = str(v)
    if not v then return nil end
    local iso = v:match("^PT(.+)$")
    if not iso then return v end
    local h, m = tonumber(iso:match("(%d+)H")), tonumber(iso:match("(%d+)M"))
    local parts = {}
    if h and h > 0 then parts[#parts + 1] = T(_("%1 h"), h) end
    if m and m > 0 then parts[#parts + 1] = T(_("%1 min"), m) end
    return #parts > 0 and table.concat(parts, " ") or nil
end

--- 4 → "4", 2.5 → "2.5".
function Mealie.fmt(x)
    x = num(x)
    if not x then return nil end
    local r = math.floor(x * 100 + 0.5) / 100
    if r == math.floor(r) then return string.format("%d", r) end
    return (string.format("%.2f", r):gsub("0+$", ""))
end

--- How many it makes ("4 servings", "12 cookies"), or nil.
function Mealie.yieldText(o)
    if type(o) ~= "table" then return nil end
    local q = num(o.recipeYieldQuantity)
    local unit = str(o.recipeYield)
    if q and q > 0 and unit then return Mealie.fmt(q) .. " " .. unit end
    local s = num(o.recipeServings)
    if s and s > 0 then return T(_("Serves %1"), Mealie.fmt(s)) end
    if unit then return unit end
    return nil
end

--- A recipe as the list keeps it: { id, slug, name, desc, time, yield,
--- rating, cats = { names } }, or nil.
function Mealie.summary(o)
    if type(o) ~= "table" or not str(o.slug) then return nil end
    local cats = {}
    for _i, c in ipairs(type(o.recipeCategory) == "table" and o.recipeCategory or {}) do
        if type(c) == "table" and str(c.name) then cats[#cats + 1] = c.name end
    end
    return {
        id = str(o.id), slug = o.slug, name = str(o.name) or o.slug, desc = str(o.description),
        time = Mealie.timeText(o.totalTime), yield = Mealie.yieldText(o), rating = num(o.rating),
        cats = #cats > 0 and cats or nil,
    }
end

local function escape(s) return require("socket.url").escape(tostring(s)) end

--- One page of recipes, by name: { items, page, pages, total }, or nil, err.
--- opts.search (words), opts.category (a category's id), opts.newest (the
--- latest added first).
function Mealie:recipes(page, opts)
    opts = opts or {}
    local q = { "page=" .. (tonumber(page) or 1), "perPage=" .. Mealie.PER_PAGE }
    if opts.newest then
        q[#q + 1] = "orderBy=created_at"
        q[#q + 1] = "orderDirection=desc"
    else
        q[#q + 1] = "orderBy=name"
        q[#q + 1] = "orderDirection=asc"
    end
    if str(opts.category) then q[#q + 1] = "categories=" .. escape(opts.category) end
    local shown = "/api/recipes?" .. table.concat(q, "&")
    if str(opts.search) then
        q[#q + 1] = "search=" .. escape(opts.search)
        shown = shown .. "&search=…"
    end
    local data, err = self:ask("GET", "/api/recipes?" .. table.concat(q, "&"), nil, { log_path = shown })
    if err then return nil, err end
    if type(data) ~= "table" or type(data.items) ~= "table" then return nil, "bad_answer" end
    local items = {}
    for _i, o in ipairs(data.items) do
        local r = Mealie.summary(o)
        if r then items[#items + 1] = r end
    end
    return {
        items = items, page = num(data.page) or tonumber(page) or 1,
        pages = num(data.total_pages) or num(data.totalPages) or 1, total = num(data.total) or #items,
    }
end

--- Every category that has a name: { { id, name } }, by name; or nil, err.
function Mealie:categories()
    local data, err = self:ask("GET", "/api/organizers/categories?page=1&perPage=-1&orderBy=name&orderDirection=asc")
    if err then return nil, err end
    if type(data) ~= "table" or type(data.items) ~= "table" then return nil, "bad_answer" end
    local out = {}
    for _i, c in ipairs(data.items) do
        if type(c) == "table" and str(c.id) and str(c.name) then out[#out + 1] = { id = c.id, name = c.name } end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

--- Text as a line of the page: Mealie's Markdown marks and HTML tags
--- (its fractions: <sup>1</sup>⁄<sub>2</sub>) taken out, spaces tidied.
function Mealie.plain(s)
    s = str(s)
    if not s then return nil end
    s = s:gsub("</sup>%s*⁄%s*<sub>", "/"):gsub("</sup>%s*/?%s*<sub>", "/")
    s = s:gsub("<br%s*/?>", "\n"):gsub("<[^>]+>", "")
    s = s:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&nbsp;", " "):gsub("&quot;", '"'):gsub("&#39;", "'")
    s = s:gsub("%*%*(.-)%*%*", "%1"):gsub("__(.-)__", "%1")
    s = s:gsub("%[([^%]]+)%]%(([^%)]+)%)", "%1") -- [words](link) → words
    s = s:gsub("\r\n?", "\n")
    local lines = {}
    for line in (s .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("^%s*#+%s*", ""):gsub("[ \t]+", " "):gsub("^ ", ""):gsub(" $", "")
        lines[#lines + 1] = line
    end
    s = table.concat(lines, "\n"):gsub("\n\n\n+", "\n\n"):gsub("^\n+", ""):gsub("\n+$", "")
    return s ~= "" and s or nil
end

--- One ingredient's line ("2 cups flour, sifted"): what Mealie shows, else
--- put together from its amount, unit, food and note.
function Mealie.ingredientText(o)
    if type(o) ~= "table" then return nil end
    local shown = Mealie.plain(o.display)
    if shown then return shown end
    local parts = {}
    local q = num(o.quantity)
    if q and q > 0 then parts[#parts + 1] = Mealie.fmt(q) end
    local unit = type(o.unit) == "table" and o.unit or nil
    if unit then
        local name = (unit.useAbbreviation and str(unit.abbreviation)) or (q and q > 1 and str(unit.pluralName)) or str(unit.name)
        if name then parts[#parts + 1] = name end
    end
    local food = type(o.food) == "table" and o.food or nil
    if food then
        local name = (q and q > 1 and not unit and str(food.pluralName)) or str(food.name)
        if name then parts[#parts + 1] = name end
    end
    local line = table.concat(parts, " ")
    local note = Mealie.plain(o.note)
    if note then line = line ~= "" and (line .. ", " .. note) or note end
    if line == "" then line = Mealie.plain(o.originalText) or "" end
    return line ~= "" and line or nil
end

--- A recipe as its page shows it: { slug, name, desc, facts = { "Serves 4",
--- "Total 45 minutes" … }, ingredients = { { title = … } | { text = … } },
--- steps = { { title = … } | { text = … } }, notes = { { title, text } },
--- source }, or nil.
function Mealie.recipe(o)
    if type(o) ~= "table" or not str(o.slug) then return nil end
    local r = { slug = o.slug, name = str(o.name) or o.slug, desc = Mealie.plain(o.description), facts = {},
        ingredients = {}, steps = {}, notes = {}, source = str(o.orgURL) }
    local y = Mealie.yieldText(o)
    if y then r.facts[#r.facts + 1] = y end
    for _i, f in ipairs({ { "totalTime", _("Total %1") }, { "prepTime", _("Prep %1") }, { "performTime", _("Cook %1") } }) do
        local t = Mealie.timeText(o[f[1]])
        if t then r.facts[#r.facts + 1] = T(f[2], t) end
    end
    for _i, ing in ipairs(type(o.recipeIngredient) == "table" and o.recipeIngredient or {}) do
        if type(ing) == "table" then
            local title = Mealie.plain(ing.title)
            if title then r.ingredients[#r.ingredients + 1] = { title = title } end
            local text = Mealie.ingredientText(ing)
            if text then r.ingredients[#r.ingredients + 1] = { text = text } end
        end
    end
    for _i, st in ipairs(type(o.recipeInstructions) == "table" and o.recipeInstructions or {}) do
        if type(st) == "table" then
            local title = Mealie.plain(st.title)
            if title then r.steps[#r.steps + 1] = { title = title } end
            local text = Mealie.plain(st.text)
            if text then r.steps[#r.steps + 1] = { text = text } end
        end
    end
    for _i, n in ipairs(type(o.notes) == "table" and o.notes or {}) do
        if type(n) == "table" then
            local text = Mealie.plain(n.text)
            if text then r.notes[#r.notes + 1] = { title = Mealie.plain(n.title), text = text } end
        end
    end
    return r
end

--- A recipe's page as text: what it makes and how long, the ingredients,
--- the steps numbered (from 1 again in each section), the notes.
function Mealie.pageText(r)
    if type(r) ~= "table" then return "" end
    local out = {}
    local function add(s) out[#out + 1] = s end
    if r.desc then add(r.desc); add("") end
    if #(r.facts or {}) > 0 then add(table.concat(r.facts, "  ·  ")); add("") end
    if #(r.ingredients or {}) > 0 then
        add(_("INGREDIENTS"))
        for _i, ing in ipairs(r.ingredients) do
            if ing.title then add(""); add(ing.title .. ":") else add("•  " .. ing.text) end
        end
        add("")
    end
    if #(r.steps or {}) > 0 then
        add(_("STEPS"))
        local n = 0
        for _i, st in ipairs(r.steps) do
            if st.title then
                add(""); add(st.title .. ":")
                n = 0
            else
                n = n + 1
                add("")
                add(n .. ".  " .. st.text)
            end
        end
        add("")
    end
    if #(r.notes or {}) > 0 then
        add(_("NOTES"))
        for _i, nt in ipairs(r.notes) do
            add("")
            if nt.title then add(nt.title .. ":") end
            add(nt.text)
        end
        add("")
    end
    if #out == 0 then return _("This recipe has no ingredients or steps yet.") end
    while out[#out] == "" do out[#out] = nil end
    return table.concat(out, "\n")
end

--- One recipe with its ingredients and steps (Mealie.recipe), or nil, err.
function Mealie:fetchRecipe(slug)
    local data, err = self:ask("GET", "/api/recipes/" .. escape(slug), nil, { timeouts = { 8, 30 } })
    if err then return nil, err end
    local r = Mealie.recipe(data)
    if not r then return nil, "bad_answer" end
    return r
end

---------------------------------------------------------------- kept on the Kindle

-- The list as last fetched (its first page), and each recipe opened: shown
-- at once the next time, and readable with Wi-Fi off (the kitchen).

function Mealie.cacheDir() return DataStorage:getDataDir() .. "/cache/gzreader-recipes" end

local function ensureDir()
    local lfs = require("libs/libkoreader-lfs")
    local dir = Mealie.cacheDir()
    local parent = dir:match("^(.*)/[^/]+$")
    if lfs.attributes(parent, "mode") ~= "directory" then lfs.mkdir(parent) end
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    return dir
end

local function writeJson(path, t)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(JSON.encode(t))
    f:close()
    return true
end

local function readJson(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    local ok, data = pcall(JSON.decode, s)
    return ok and type(data) == "table" and data or nil
end

function Mealie.saveList(list)
    if type(list) ~= "table" or type(list.items) ~= "table" then return end
    pcall(function()
        writeJson(ensureDir() .. "/list.json", { v = 1, at = list.at, total = list.total, pages = list.pages,
            items = JSON.list(list.items), cats = type(list.cats) == "table" and JSON.list(list.cats) or nil })
    end)
end

function Mealie.loadList()
    local data = readJson(Mealie.cacheDir() .. "/list.json")
    if not data or data.v ~= 1 or type(data.items) ~= "table" then return nil end
    return { at = tonumber(data.at), total = tonumber(data.total), pages = tonumber(data.pages) or 1, page = 1, items = data.items,
        cats = type(data.cats) == "table" and data.cats or nil }
end

--- A recipe's file name: its slug, when that is a plain one (Mealie's are).
local function recipeFile(slug)
    slug = tostring(slug or "")
    if not slug:match("^[%w][%w%-_]*$") or #slug > 150 then return nil end
    return Mealie.cacheDir() .. "/r-" .. slug .. ".json"
end

function Mealie.saveRecipe(r)
    local path = type(r) == "table" and recipeFile(r.slug)
    if not path then return end
    pcall(function()
        ensureDir()
        writeJson(path, { v = 1, at = os.time(), recipe = r })
    end)
end

function Mealie.loadRecipe(slug)
    local path = recipeFile(slug)
    local data = path and readJson(path)
    if not data or data.v ~= 1 or type(data.recipe) ~= "table" then return nil end
    return data.recipe, tonumber(data.at)
end

function Mealie.clearCache()
    local lfs = require("libs/libkoreader-lfs")
    local dir = Mealie.cacheDir()
    if lfs.attributes(dir, "mode") ~= "directory" then return end
    for name in lfs.dir(dir) do
        if name:match("%.json$") then os.remove(dir .. "/" .. name) end
    end
end

---------------------------------------------------------------- connecting

local WHY = {
    unreachable = _("Couldn't reach Mealie at that address."),
    unauthorized = _("Mealie didn't accept that token."),
    not_found = _("Mealie doesn't have that (it may have been deleted)."),
    not_mealie = _("That doesn't look like Mealie."),
    not_connected = _("Connect to Mealie first."),
    bad_answer = _("Mealie's answer wasn't what GZreader expected."),
}
function Mealie.why(err)
    local busy = tostring(err):match("^http_(5%d%d)$")
    if busy then return T(_("Mealie couldn't answer just now (error %1). Try again in a moment."), busy) end
    return WHY[err] or T(_("Mealie: %1"), tostring(err))
end

--- The first of the addresses for what was typed where a Mealie answers:
--- base, about; or nil, why (to show).
function Mealie.findServer(server_input)
    local list, bare = Mealie.candidates(server_input)
    if not list then return nil, _("That address doesn't look right.") end
    local last
    for _i, base in ipairs(list) do
        local about, err = Mealie:new({ server = base }):about()
        if about then return base, about end
        last = err
        if err ~= "unreachable" then break end
    end
    local Lan = require("gzreader_lan")
    if last == "unreachable" and bare and #list == 1 and not Lan.isPrivate(list[1]) then return nil, Lan.noHttpsText() end
    return nil, Mealie.why(last)
end

local function keep(plugin, base, about, token, who, extra)
    local old = plugin.store.mealie or {}
    local same = old.server == base and old.username == who.username
    plugin.store.mealie = { server = base, token = token, name = who.name, username = who.username,
        version = about and about.version or nil, sso = extra and extra.sso or nil, token_id = extra and extra.token_id or nil }
    plugin:save()
    if not same then Mealie.clearCache() end
end

--- Check the address and API token and keep them (plugin.store.mealie):
--- true, or false and why (to show).
function Mealie.connect(plugin, server_input, token)
    token = tostring(token or ""):gsub("%s+", "")
    if not Mealie.normalizeServer(server_input) then return false, _("That address doesn't look right.") end
    if token == "" then return false, _("Paste an API token from Mealie (your profile → API tokens).") end
    local Log = require("gzreader_log")
    local base, about = Mealie.findServer(server_input)
    if not base then
        Log.info("recipes: connecting failed: no Mealie at the address")
        return false, about
    end
    local who, err = Mealie:new({ server = base, token = token }):whoami()
    Log.info("recipes: connecting to", base, who and "ok" or ("failed: " .. tostring(err)))
    if not who then return false, Mealie.why(err) end
    keep(plugin, base, about, token, who)
    return true
end

--- Forget the address and token. A token GZreader made itself (single
--- sign-on) is deleted in Mealie too when it can be reached (`revoke`:
--- false to leave it; the answer isn't waited for).
function Mealie.disconnect(plugin, revoke)
    local old = plugin.store.mealie or {}
    plugin.store.mealie = {}
    plugin:save()
    Mealie.clearCache()
    require("gzreader_log").info("recipes: disconnected from Mealie")
    if revoke ~= false and old.server and old.token and tonumber(old.token_id) then
        local client = Mealie:new({ server = old.server, token = old.token })
        pcall(function()
            require("gzreader_async").run(nil, function()
                local err = select(2, client:ask("DELETE", "/api/users/api-tokens/" .. tonumber(old.token_id), nil, { timeouts = { 5, 10 } }))
                return err == nil
            end, function(ok)
                require("gzreader_log").info("recipes: the token GZreader made in Mealie", ok and "deleted" or "not deleted (delete it in Mealie: your profile → API tokens)")
            end, "recipes revoke")
        end)
    end
end

---------------------------------------------------------------- single sign-on

--- Start single sign-on for the Mealie at `server_input`: what the browser
--- needs ({ base, about, authorization_endpoint, client_id, scope }), or
--- nil, why (to show).
function Mealie.ssoStart(server_input)
    local base, about = Mealie.findServer(server_input)
    if not base then return nil, about end
    if not about.oidc then return nil, _("Single sign-on isn't turned on for this Mealie. Use an API token instead.") end
    local cfg, err = Mealie:new({ server = base }):ask("GET", "/api/auth/oauth/native/config", nil,
        { public = true, expected = { [404] = true } })
    if err == "not_found" then
        return nil, _("This Mealie is too old for single sign-on from another app (it needs Mealie's sign-on for apps). Update Mealie, or use an API token instead.")
    end
    if err then return nil, Mealie.why(err) end
    if type(cfg) ~= "table" or not str(cfg.authorization_endpoint) or not str(cfg.client_id) then
        return nil, Mealie.why("bad_answer")
    end
    if not cfg.authorization_endpoint:match("^https?://") then return nil, Mealie.why("bad_answer") end
    return { base = base, about = about, authorization_endpoint = cfg.authorization_endpoint, client_id = cfg.client_id,
        scope = str(cfg.scope) or "openid email profile" }
end

--- Finish single sign-on: hand Mealie the provider's code, and with the
--- session token it answers with, make GZreader's own API token and keep
--- that (the session token is dropped). `session`: { base, about, verifier,
--- redirect_uri, nonce }. True, or false and why (to show).
function Mealie.ssoFinish(plugin, session, code)
    local Log = require("gzreader_log")
    local client = Mealie:new({ server = session.base })
    local data, err = client:ask("POST", "/api/auth/oauth/native/token", {
        code = code, code_verifier = session.verifier, redirect_uri = session.redirect_uri, nonce = session.nonce,
    }, { public = true, timeouts = { 15, 30 } })
    local access = not err and type(data) == "table" and str(data.access_token) or nil
    if not access then
        Log.warn("recipes: single sign-on: Mealie didn't take the code:", tostring(err or "no token in its answer"))
        if err == "unauthorized" then
            return false, _("Mealie didn't accept the sign-in. Is this address allowed as a redirect for Mealie at your identity provider, and may your account use Mealie?")
        end
        return false, Mealie.why(err or "bad_answer")
    end
    local who, werr = client:whoami({ token = access })
    if not who then return false, Mealie.why(werr) end
    local made, terr = client:ask("POST", "/api/users/api-tokens", { name = Mealie.TOKEN_NAME }, { token = access })
    local token = not terr and type(made) == "table" and str(made.token) or nil
    if not token then
        Log.warn("recipes: single sign-on: no API token made:", tostring(terr or "none in the answer"))
        return false, _("Signed in, but Mealie didn't make an API token for GZreader. Make one in Mealie (your profile → API tokens) and paste it instead.")
    end
    keep(plugin, session.base, session.about, token, who, { sso = true, token_id = tonumber(made.id) })
    Log.info("recipes: signed in through single sign-on; GZreader's own API token kept")
    return true
end

return Mealie
