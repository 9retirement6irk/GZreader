--[[--
Getting past Cloudflare (or another proxy in front of your servers): GZreader
can send a secret header on every request to your own servers, for a rule
that lets GZreader through without the bot checks a Kindle can't pass:

  X-GZreader-Key: <a random key GZreader makes>

and, for servers behind Cloudflare Access (Zero Trust), a service token:

  CF-Access-Client-Id / CF-Access-Client-Secret

Which servers: Grimmory's, Memos', the CalDAV account's (as connected), and
any other host names added (each also covers its subdomains). Never to
anything else (calendar links on other sites, plex.tv, GitHub). Set on the
phone page (Access tab). The key and token are kept like passwords: never
written to the log.

store.access = { enabled, key, hosts = "photos.example.com …", cf_id, cf_secret }
]]

local Access = { HEADER = "X-GZreader-Key", cfg = nil, plugin = nil }

local function hostOf(url) return url and tostring(url):match("^%a+://([^/:?#]+)") end

--- The host names the header goes to (lower case).
function Access.hosts(plugin)
    plugin = plugin or Access.plugin
    local out, seen = {}, {}
    local function add(h)
        h = h and h:lower():gsub("^%*%.", "")
        if h and h ~= "" and not seen[h] then seen[h] = true; out[#out + 1] = h end
    end
    if plugin then
        local s = plugin.store
        add(hostOf(s.server))
        add(hostOf((s.memos or {}).server))
        add(hostOf((s.caldav or {}).server))
        local cfg = s.access or {}
        for h in tostring(cfg.hosts or ""):gmatch("[^%s,;]+") do add(hostOf(h) or h) end
    end
    return out
end

--- Is `url`'s host one of them (or a subdomain of one)?
function Access.covers(url, plugin)
    local host = hostOf(url)
    if not host then return false end
    host = host:lower()
    for _i, h in ipairs(Access.hosts(plugin)) do
        if host == h or host:sub(-(#h + 1)) == "." .. h then return true end
    end
    return false
end

--- The headers for a request to `url` (nil if none).
function Access.headersFor(url)
    local plugin = Access.plugin
    local cfg = plugin and plugin.store.access
    if not (cfg and (cfg.enabled or cfg.cf_id)) then return nil end
    if not Access.covers(url, plugin) then return nil end
    local h = {}
    if cfg.enabled and cfg.key then h[Access.HEADER] = cfg.key end
    if cfg.cf_id and cfg.cf_secret then
        h["CF-Access-Client-Id"] = cfg.cf_id
        h["CF-Access-Client-Secret"] = cfg.cf_secret
    end
    return next(h) and h or nil
end

--- A new key (when there's none, or asked for).
function Access.newKey(plugin)
    plugin.store.access = plugin.store.access or {}
    plugin.store.access.key = require("gzreader_pairserver").randomToken(16)
    return plugin.store.access.key
end

--- The Cloudflare rule to paste (its expression).
function Access.ruleExpression(plugin)
    local cfg = plugin.store.access or {}
    local hosts = {}
    for _i, h in ipairs(Access.hosts(plugin)) do hosts[#hosts + 1] = string.format("%q", h) end
    return string.format('(http.host in {%s}) and any(http.request.headers["%s"][*] eq "%s")',
        table.concat(hosts, " "), Access.HEADER:lower(), cfg.key or "")
end

function Access.install(plugin)
    Access.plugin = plugin
    require("gzreader_api").extra_headers = Access.headersFor
end

return Access
