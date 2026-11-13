--[[--
Home Assistant (https://www.home-assistant.io) client for the House tab
(gzreader_house.lua): what's in each room, and switching things.

It talks to Home Assistant's REST API directly (no browser: KOReader has
none, and Home Assistant's own pages need a modern one):

- Sign-in: a long-lived access token (Home Assistant → your profile →
  Security → Long-lived access tokens), sent as "Authorization: Bearer". It's
  kept in GZreader's settings like the Memos token and never written to the
  log.
- What's there: one POST /api/template that renders a small JSON list of
  rooms (Home Assistant's areas) and the devices in them that the tab can show
  or switch (TEMPLATE), instead of GET /api/states, which on a big setup is
  hundreds of KB. Rendering templates needs an administrator's token; with
  another one the tab falls back to /api/states, grouped by kind (Lights,
  Switches…) instead of by room.
- Switching: POST /api/services/<domain>/<service> {entity_id, …}, which
  answers with the states it changed (put straight into the list).

Nothing here touches the screen: gzreader_house.lua draws, and runs these in
the background (gzreader_async.lua).
]]

local DataStorage = require("datastorage")
local JSON = require("gzreader_json")
local _ = require("gettext")
local T = require("ffi/util").template

local HA = {
    PORT = 8123,
    -- what the tab shows: switchable kinds, and a few sensors worth a glance
    CONTROL = { light = true, switch = true, fan = true, input_boolean = true, climate = true,
        lock = true, cover = true, script = true, scene = true },
    SENSOR_CLASSES = { temperature = true, humidity = true },
    BINARY_CLASSES = { door = true, window = true, garage_door = true, opening = true, lock = true },
    TOGGLE = { light = true, switch = true, fan = true, input_boolean = true },
    -- covers that open into the house (asked before opening, like unlocking)
    GUARDED_COVERS = { garage = true, gate = true, door = true },
    -- the fallback's groups (no rooms: a token that can't render templates)
    KINDS = {
        { "light", _("Lights") }, { "switch", _("Switches") }, { "fan", _("Fans") },
        { "input_boolean", _("Helpers") }, { "climate", _("Climate") }, { "lock", _("Locks") },
        { "cover", _("Covers") }, { "binary_sensor", _("Doors and windows") }, { "sensor", _("Sensors") },
        { "script", _("Scripts") }, { "scene", _("Scenes") },
    },
}
HA.__index = HA

--- The template (Home Assistant's Jinja): rooms with their devices, the
--- switchable ones in no room ("other") and every scene. One object per
--- device: i(d), s(tate), n(ame), b(rightness 0–255), d(immable),
--- u(nit), c (device class), t (current temperature), g (target),
--- a (heating/cooling now), lo/hi (target range), st (target step),
--- p (cover position). The first line marks it for the test server.
HA.TEMPLATE = [==[
{#- gzreader-house-v1 -#}
{%- set C = ['light','switch','fan','input_boolean','climate','lock','cover','script'] -%}
{%- set SC = ['temperature','humidity'] -%}
{%- set BC = ['door','window','garage_door','opening','lock'] -%}
{%- macro e(s) -%}
{{ {'i': s.entity_id, 's': s.state, 'n': s.name,
 'b': s.attributes.get('brightness'),
 'd': ((s.attributes.get('supported_color_modes') or []) | reject('in', ['onoff', 'unknown']) | list | count) > 0,
 'u': s.attributes.get('unit_of_measurement'), 'c': s.attributes.get('device_class'),
 't': s.attributes.get('current_temperature'), 'g': s.attributes.get('temperature'),
 'a': s.attributes.get('hvac_action'), 'lo': s.attributes.get('min_temp'), 'hi': s.attributes.get('max_temp'),
 'st': s.attributes.get('target_temp_step'), 'p': s.attributes.get('current_position')} | to_json }}
{%- endmacro -%}
{"v":1,"rooms":[
{%- for a in areas() -%}
{%- if not loop.first %},{% endif -%}
{"id":{{ a | to_json }},"name":{{ area_name(a) | to_json }},"e":[
{%- for s in expand(area_entities(a)) if (s.domain in C or (s.domain == 'sensor' and s.attributes.get('device_class') in SC) or (s.domain == 'binary_sensor' and s.attributes.get('device_class') in BC)) and not is_hidden_entity(s.entity_id) -%}
{%- if not loop.first %},{% endif %}{{ e(s) }}
{%- endfor -%}
]}
{%- endfor -%}
],"other":[
{%- for s in states if s.domain in C and s.domain != 'script' and not area_id(s.entity_id) and not is_hidden_entity(s.entity_id) -%}
{%- if not loop.first %},{% endif %}{{ e(s) }}
{%- endfor -%}
],"scenes":[
{%- for s in states.scene if not is_hidden_entity(s.entity_id) -%}
{%- if not loop.first %},{% endif %}{{ e(s) }}
{%- endfor -%}
]}]==]

--- `store` is plugin.store.homeassistant (server, token, name, version, unit,
--- no_template).
function HA:new(store)
    return setmetatable({ store = store or {} }, self)
end

function HA:isConnected()
    return self.store.server ~= nil and self.store.token ~= nil
end

--- The address typed or pasted: "homeassistant.local" → http://homeassistant.local:8123
--- (Home Assistant's own port, plain HTTP on the home network); an address
--- with https:// or a port is kept; the page's path (/lovelace/0, /api) dropped.
function HA.normalizeServer(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    local scheme = s:match("^(%a+)://")
    if scheme and scheme:lower() ~= "http" and scheme:lower() ~= "https" then return nil end
    if not scheme then s = "http://" .. s end
    -- (the page's path, query and anchor are dropped)
    local base = s:match("^(%a+://[^/?#]+)")
    if not base then return nil end
    local hostport = base:match("://(.+)$")
    if hostport:find("[%s@]") then return nil end
    -- no port and no scheme typed: Home Assistant's port
    if not scheme and not hostport:match(":%d+$") and not hostport:match("^%[.*%]$") then
        base = base .. ":" .. HA.PORT
    end
    return base
end

--- One request. Returns code, data, err: "unreachable", "unauthorized"
--- (401/403), "not_found", "http_<code>".
function HA:request(method, path, body, opts)
    opts = opts or {}
    if not self:isConnected() then return nil, nil, "not_connected" end
    local Api = require("gzreader_api")
    local code, data = Api.rawRequest(method, self.store.server .. path, {
        headers = { ["Authorization"] = "Bearer " .. self.store.token },
        body = body,
        timeouts = opts.timeouts or { 8, 20 },
    })
    if not code then return nil, nil, "unreachable" end
    if code == 401 or code == 403 then return code, data, "unauthorized" end
    if code == 404 then return code, data, "not_found" end
    if code >= 400 then return code, data, "http_" .. code end
    return code, data
end

--- Whether the address is a Home Assistant that takes the token: its name,
--- version and temperature unit ({ name, version, unit }), or nil, err.
function HA:check()
    local _, data, err = self:request("GET", "/api/")
    if err then return nil, err end
    if type(data) ~= "table" or type(data.message) ~= "string" then return nil, "not_ha" end
    local info = { name = nil, version = nil, unit = nil }
    local _, cfg = self:request("GET", "/api/config")
    if type(cfg) == "table" then
        info.name = type(cfg.location_name) == "string" and cfg.location_name or nil
        info.version = type(cfg.version) == "string" and cfg.version or nil
        local us = type(cfg.unit_system) == "table" and cfg.unit_system or {}
        info.unit = type(us.temperature) == "string" and us.temperature or nil
    end
    return info
end

---------------------------------------------------------------- what's there

local function num(x)
    x = tonumber(x)
    if x and x == x and x ~= math.huge and x ~= -math.huge then return x end
end

local function str(x) return type(x) == "string" and x ~= "" and x or nil end

--- One device from the template's object (see TEMPLATE).
function HA.entity(o)
    if type(o) ~= "table" or type(o.i) ~= "string" then return nil end
    local domain = o.i:match("^([%w_]+)%.")
    if not domain then return nil end
    local b = num(o.b)
    return {
        id = o.i, domain = domain, state = str(o.s) or "unknown", name = str(o.n) or o.i,
        bri = b and math.max(0, math.min(100, math.floor(b * 100 / 255 + 0.5))) or nil,
        dim = o.d == true or (domain == "light" and b ~= nil) or nil,
        unit = str(o.u), dc = str(o.c), cur = num(o.t), target = num(o.g), action = str(o.a),
        min = num(o.lo), max = num(o.hi), step = num(o.st), pos = num(o.p),
    }
end

--- One device from /api/states' answer ({ entity_id, state, attributes }).
function HA.entityFromState(st)
    if type(st) ~= "table" then return nil end
    local a = type(st.attributes) == "table" and st.attributes or {}
    local dim = false
    for _i, m in ipairs(type(a.supported_color_modes) == "table" and a.supported_color_modes or {}) do
        if m ~= "onoff" and m ~= "unknown" then dim = true end
    end
    return HA.entity({ i = st.entity_id, s = st.state, n = a.friendly_name, b = a.brightness, d = dim,
        u = a.unit_of_measurement, c = a.device_class, t = a.current_temperature, g = a.temperature,
        a = a.hvac_action, lo = a.min_temp, hi = a.max_temp, st = a.target_temp_step, p = a.current_position })
end

--- Whether the tab shows this device at all.
function HA.wanted(e)
    if not e then return false end
    if HA.CONTROL[e.domain] then return true end
    if e.domain == "sensor" then return HA.SENSOR_CLASSES[e.dc or ""] == true end
    if e.domain == "binary_sensor" then return HA.BINARY_CLASSES[e.dc or ""] == true end
    return false
end

local function byName(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end

--- The template's answer as the tab's list: { rooms = { { id, name,
--- entities } }, by_kind = false }. Empty rooms are left out; a device that
--- shows twice (a group in a room expands to its members) once.
function HA.fromTemplate(data)
    if type(data) ~= "table" or type(data.rooms) ~= "table" then return nil end
    local out = { rooms = {}, by_kind = false }
    local function group(id, name, list, sort)
        local seen, ents = {}, {}
        for _i, o in ipairs(type(list) == "table" and list or {}) do
            local e = HA.entity(o)
            if e and not seen[e.id] and HA.wanted(e) then
                seen[e.id] = true
                ents[#ents + 1] = e
            end
        end
        if sort then table.sort(ents, byName) end
        if #ents > 0 then out.rooms[#out.rooms + 1] = { id = id, name = name, entities = ents } end
    end
    for _i, r in ipairs(data.rooms) do
        if type(r) == "table" and type(r.id) == "string" then
            group(r.id, str(r.name) or r.id, r.e, false)
        end
    end
    group("_other", _("Other"), data.other, true)
    group("_scenes", _("Scenes"), data.scenes, true)
    return out
end

--- /api/states' answer grouped by kind (no rooms without the template).
function HA.fromStates(list)
    if type(list) ~= "table" then return nil end
    local by = {}
    for _i, st in ipairs(list) do
        local e = HA.entityFromState(st)
        if HA.wanted(e) then
            by[e.domain] = by[e.domain] or {}
            table.insert(by[e.domain], e)
        end
    end
    local out = { rooms = {}, by_kind = true }
    for _i, k in ipairs(HA.KINDS) do
        local ents = by[k[1]]
        if ents then
            table.sort(ents, byName)
            out.rooms[#out.rooms + 1] = { id = "_" .. k[1], name = k[2], entities = ents }
        end
    end
    return out
end

--- Everything the tab shows, or nil, err. The template first (rooms); with
--- a token that may not render templates (not an administrator's), the
--- states, remembered so the template isn't tried again until reconnecting.
function HA:fetch()
    if not self.store.no_template then
        local code, data, err = self:request("POST", "/api/template", { template = HA.TEMPLATE })
        if not err then
            local house = HA.fromTemplate(data)
            if house then return house end
            require("gzreader_log").warn("house: the template's answer wasn't the list (", type(data), ")")
            return nil, "bad_answer"
        end
        if err ~= "unauthorized" and code ~= 400 then return nil, err end
        -- (401: not an administrator; 400: the template isn't understood, an old Home Assistant)
        require("gzreader_log").info("house: no rooms (template:", tostring(code), "); kinds from /api/states")
        self.store.no_template = true
    end
    local _, list, err = self:request("GET", "/api/states", nil, { timeouts = { 8, 40 } })
    if err then return nil, err end
    local house = HA.fromStates(list)
    if not house then return nil, "bad_answer" end
    return house
end

--- Call a service ("light", "turn_on", { entity_id = …, brightness_pct = … }):
--- the states it changed (a list from /api/states' shape), or nil, err.
function HA:call(domain, service, data)
    if not (tostring(domain):match("^[%w_]+$") and tostring(service):match("^[%w_]+$")) then return nil, "bad_service" end
    local _, changed, err = self:request("POST", "/api/services/" .. domain .. "/" .. service, data or {})
    if err then return nil, err end
    return type(changed) == "table" and changed or {}
end

--- Put the states a service call changed into `house`; true if any was there.
function HA.applyChanged(house, changed)
    if type(house) ~= "table" or type(changed) ~= "table" then return false end
    local fresh = {}
    for _i, st in ipairs(changed) do
        local e = HA.entityFromState(st)
        if e then fresh[e.id] = e end
    end
    local any = false
    for _i, r in ipairs(house.rooms or {}) do
        for j, e in ipairs(r.entities or {}) do
            local n = fresh[e.id]
            if n then
                -- (an answer without a friendly name keeps the one we have)
                if n.name == n.id then n.name = e.name end
                r.entities[j] = n
                any = true
            end
        end
    end
    return any
end

--- One device by id, and its room.
function HA.find(house, id)
    for _i, r in ipairs(type(house) == "table" and house.rooms or {}) do
        for _j, e in ipairs(r.entities or {}) do
            if e.id == id then return e, r end
        end
    end
end

---------------------------------------------------------------- what a row says

--- 21 → "21", 20.5 → "20.5", 20.04 → "20".
function HA.fmt(x)
    x = num(x)
    if not x then return "?" end
    local r = math.floor(x * 10 + 0.5) / 10
    if r == math.floor(r) then return string.format("%d", r) end
    return string.format("%.1f", r)
end

local UNAVAILABLE = { unavailable = true, unknown = true }

--- What a device's row says on the right ("On · 80%", "20.5° → 21°", "Locked").
function HA.stateText(e)
    if not e then return nil end
    local s, d = e.state, e.domain
    if d == "scene" or d == "script" then return nil end
    if UNAVAILABLE[s] then return _("Unavailable") end
    if HA.TOGGLE[d] then
        if s == "on" then
            if d == "light" and e.bri then return T(_("On · %1%"), e.bri) end
            return _("On")
        end
        if s == "off" then return _("Off") end
        return s
    end
    if d == "climate" then
        local now = e.cur and (HA.fmt(e.cur) .. "°") or nil
        if s == "off" then return now and T(_("Off · %1"), now) or _("Off") end
        if now and e.target then return T(_("%1 → %2"), now, HA.fmt(e.target) .. "°") end
        if e.target then return T(_("to %1"), HA.fmt(e.target) .. "°") end
        return now or s
    end
    if d == "lock" then
        local words = { locked = _("Locked"), unlocked = _("Unlocked"), jammed = _("Jammed"), open = _("Open"),
            locking = _("Locking…"), unlocking = _("Unlocking…"), opening = _("Opening…") }
        return words[s] or s
    end
    if d == "cover" then
        if s == "open" and e.pos and e.pos > 0 and e.pos < 100 then return T(_("Open · %1%"), HA.fmt(e.pos)) end
        local words = { open = _("Open"), closed = _("Closed"), opening = _("Opening…"), closing = _("Closing…") }
        return words[s] or s
    end
    if d == "binary_sensor" then
        if e.dc == "lock" then return s == "on" and _("Unlocked") or _("Locked") end
        return s == "on" and _("Open") or _("Closed")
    end
    if d == "sensor" then
        local v = num(s)
        local u = e.unit or ""
        if v then
            if u == "°C" or u == "°F" then return HA.fmt(v) .. "°" end
            return HA.fmt(v) .. (u ~= "" and ((u == "%" and "" or " ") .. u) or "")
        end
        return s
    end
    return s
end

--- A device's name without its room's in front ("Living room Ceiling light"
--- in the Living room → "Ceiling light").
function HA.shortName(name, room)
    name = tostring(name or "")
    room = tostring(room or "")
    if room == "" or #name <= #room + 1 then return name end
    if name:sub(1, #room):lower() == room:lower() and name:sub(#room + 1, #room + 1):match("[%s%-:·]") then
        local rest = name:sub(#room + 2):gsub("^[%s%-:·]+", "")
        if rest ~= "" then return (rest:gsub("^%l", string.upper)) end
    end
    return name
end

--- What tapping a device does: "toggle", "light" (the dimmer), "climate"
--- (the target), "lock", "unlock", "open", "close", "scene", "script", or
--- nil (sensors, unavailable).
function HA.action(e)
    if not e or UNAVAILABLE[e.state] then return nil end
    local d = e.domain
    if d == "light" then return e.dim and "light" or "toggle" end
    if HA.TOGGLE[d] then return "toggle" end
    if d == "climate" then return "climate" end
    if d == "lock" then return e.state == "locked" and "unlock" or "lock" end
    if d == "cover" then return (e.state == "open" or e.state == "opening") and "close" or "open" end
    if d == "scene" then return "scene" end
    if d == "script" then return "script" end
    return nil
end

--- Whether `what` on `e` asks first ("Ask before unlocking or opening").
function HA.guarded(e, what)
    if not e then return false end
    if what == "unlock" then return true end
    if what == "open" and e.domain == "cover" then return HA.GUARDED_COVERS[e.dc or ""] == true end
    return false
end

--- The service for `what` on `e`: domain, service, data. `arg`: the
--- brightness in % ("brightness") or the target temperature ("target").
function HA.service(e, what, arg)
    local data = { entity_id = e.id }
    if what == "toggle" then return e.domain, e.state == "on" and "turn_off" or "turn_on", data end
    if what == "on" then return e.domain, "turn_on", data end
    if what == "off" then return e.domain, "turn_off", data end
    if what == "brightness" then
        data.brightness_pct = math.max(1, math.min(100, math.floor((tonumber(arg) or 100) + 0.5)))
        return "light", "turn_on", data
    end
    if what == "target" then
        data.temperature = tonumber(arg)
        return "climate", "set_temperature", data
    end
    if what == "lock" then return "lock", "lock", data end
    if what == "unlock" then return "lock", "unlock", data end
    if what == "open" then return "cover", "open_cover", data end
    if what == "close" then return "cover", "close_cover", data end
    if what == "scene" then return "scene", "turn_on", data end
    if what == "script" then return "script", "turn_on", data end
end

--- A thermostat's next target, one step up (dir 1) or down (-1), kept in its range.
function HA.nextTarget(e, dir, unit)
    local step = e.step or ((unit == "°F") and 1 or 0.5)
    local t = (e.target or e.cur or ((unit == "°F") and 68 or 20)) + dir * step
    t = math.floor(t / step + 0.5) * step
    if e.min then t = math.max(e.min, t) end
    if e.max then t = math.min(e.max, t) end
    return t
end

--- The icon file for a device's row (icons/house/…).
local here = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$") or "plugins/gzreader.koplugin"
function HA.iconFile(e)
    local d, name = e and e.domain, "switch"
    if d == "light" then name = "light"
    elseif d == "fan" then name = "fan"
    elseif d == "climate" then name = "thermostat"
    elseif d == "lock" then name = e.state == "locked" and "lock" or "unlock"
    elseif d == "cover" then name = HA.GUARDED_COVERS[e.dc or ""] and "garage" or "blinds"
    elseif d == "scene" then name = "scene"
    elseif d == "script" then name = "script"
    elseif d == "sensor" then name = e.dc == "humidity" and "humidity" or "sensor"
    elseif d == "binary_sensor" then name = (e.dc == "window") and "window" or (e.dc == "lock" and "lock") or "door"
    end
    return here .. "/icons/house/" .. name .. ".svg"
end
HA.ROOM_ICON = here .. "/icons/house/room.svg"

---------------------------------------------------------------- kept on the Kindle

--- The last list, shown at once when the tab opens (then refreshed).
function HA.cachePath()
    return DataStorage:getDataDir() .. "/cache/gzreader-house.json"
end

function HA.saveCache(house)
    if type(house) ~= "table" then return end
    pcall(function()
        local lfs = require("libs/libkoreader-lfs")
        local dir = HA.cachePath():match("^(.*)/[^/]+$")
        if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
        local f = io.open(HA.cachePath(), "wb")
        if not f then return end
        f:write(JSON.encode({ v = 1, at = house.at, by_kind = house.by_kind, rooms = house.rooms }))
        f:close()
    end)
end

function HA.loadCache()
    local f = io.open(HA.cachePath(), "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    local ok, data = pcall(JSON.decode, s)
    if not ok or type(data) ~= "table" or data.v ~= 1 or type(data.rooms) ~= "table" then return nil end
    return { at = tonumber(data.at), by_kind = data.by_kind == true, rooms = data.rooms }
end

function HA.clearCache() os.remove(HA.cachePath()) end

---------------------------------------------------------------- connecting

local WHY = {
    unreachable = _("Couldn't reach Home Assistant at that address. Is it on this Wi-Fi?"),
    unauthorized = _("Home Assistant didn't accept that token."),
    not_found = _("That doesn't look like Home Assistant (no API there)."),
    not_ha = _("That doesn't look like Home Assistant."),
    not_connected = _("Connect to Home Assistant first."),
    bad_answer = _("Home Assistant's answer wasn't what GZreader expected."),
}
function HA.why(err)
    return WHY[err] or T(_("Home Assistant: %1"), tostring(err))
end

--- Check the address and token and keep them (plugin.store.homeassistant):
--- true, or false and why (to show).
function HA.connect(plugin, server_input, token)
    local server = HA.normalizeServer(server_input)
    token = tostring(token or ""):gsub("%s+", "")
    if not server then return false, _("That address doesn't look right.") end
    if token == "" then return false, _("Paste a long-lived access token from Home Assistant (your profile → Security).") end
    local info, err = HA:new({ server = server, token = token }):check()
    if not info and err == "unreachable" and server:match("^http://") and not tostring(server_input):match("^%s*http://") then
        -- (no scheme typed: Home Assistant behind HTTPS, e.g. Nabu Casa's address)
        local tls = server:gsub("^http://", "https://"):gsub(":" .. HA.PORT .. "$", "")
        local t2 = HA:new({ server = tls, token = token })
        local i2, e2 = t2:check()
        if i2 or e2 ~= "unreachable" then info, err, server = i2, e2, tls end
    end
    require("gzreader_log").info("house: connecting to", server, info and "ok" or ("failed: " .. tostring(err)))
    if not info then return false, HA.why(err) end
    local old = plugin.store.homeassistant or {}
    local same = old.server == server
    plugin.store.homeassistant = { server = server, token = token, name = info.name, version = info.version,
        unit = info.unit, hidden = same and old.hidden or nil, hidden_rooms = same and old.hidden_rooms or nil,
        ask = old.ask }
    plugin:save()
    if not same then HA.clearCache() end
    return true
end

--- Forget the address and token (and the kept list).
function HA.disconnect(plugin)
    local old = plugin.store.homeassistant or {}
    plugin.store.homeassistant = { ask = old.ask }
    plugin:save()
    HA.clearCache()
    require("gzreader_log").info("house: disconnected from Home Assistant")
end

return HA
