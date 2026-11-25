--[[--
Handwriting to text: pen strokes read as words, on the Kindle or online.

Two ways to read (Settings → Notes → Handwriting to text):

- **On the Kindle** (the default; no Wi-Fi, nothing leaves the Kindle): Ink
  Away's reader (gzreader_hwr.lua, its small character model and English
  word list, see data/handwriting/NOTICE.md). It reads printed writing best:
  letters apart, English words and digits.
- **With AI**, through GZreader's AI connection (gzreader_ai.lua; Settings →
  Accounts and services → AI): Claude, or any service that takes pictures
  through OpenAI's Chat Completions API. Only the writing being read is sent,
  as a black-on-white picture: never the page, its pictures or other notes.
  Much better with joined-up writing. Off until the connection has a key and
  this is chosen.

Used by the drawing screen: the lasso's **To text** (the chosen writing,
checked before it becomes a text box) and the text tool's **Write** (a text
box you write into with the pen, each word turned into typed text a moment
after the pen lifts, as on the Apple Newton).

  store.handwriting = { engine = "kindle" | "ai" }
  (the AI connection's keys are kept beside it: gzreader_ai.lua)
]]

local Log = require("gzreader_log")

local Hw = {
    PAUSE = 1.0, -- (s) the pen lifted this long: what was written is read (the Write box)
    TIMEOUT = 60, -- (s) an online reading at most
    MAX_SIDE = 1600, -- (px) the picture sent, at most this wide or high
    PAD = 24, -- (px) white round the writing in the picture
    PROMPT = "Transcribe the handwriting in this image exactly as written. Reply with only the text: no quotes, "
        .. "no explanations, no formatting. Keep its line breaks where the writer started a new line. "
        .. "If nothing in it can be read, reply with nothing.",
}

-- -------------------------------------------------------------- settings

local function AI() return require("gzreader_ai") end

--- { engine = "kindle" | "ai", claude, openai }: the table kept (the AI
--- connection's keys live in it too: gzreader_ai.lua).
function Hw.settings(plugin)
    local store = plugin and plugin.store
    if not store then return { engine = "kindle", claude = {}, openai = {} } end
    AI().settings(plugin)
    local s = store.handwriting
    -- (anything but "on the Kindle" is the AI connection)
    s.engine = (s.engine == nil or s.engine == "kindle") and "kindle" or "ai"
    return s
end

--- The way writing is read now: "kindle", or the AI connection's service
--- ("claude" / "openai") when AI is chosen and the connection is set up.
function Hw.engine(plugin)
    local s = Hw.settings(plugin)
    if s.engine == "ai" then return AI().provider(plugin) or "kindle" end
    return "kindle"
end

function Hw.safeUrl(url) return AI().safeUrl(url) end

-- -------------------------------------------------------------- strokes

--- The drawing's strokes (gzreader_sketch: { points = { {x, y, …}, … } }, in
--- the order they were written) as the reader takes them: flat {x, y, x, y, …} lists.
function Hw.flat(strokes)
    local out = {}
    for _i, st in ipairs(strokes or {}) do
        local f = {}
        for _j, p in ipairs(st.points or {}) do f[#f + 1] = p[1]; f[#f + 1] = p[2] end
        if #f >= 2 then out[#out + 1] = f end
    end
    return out
end

--- The box round flat strokes: x0, y0, x1, y1 (nil when there are none).
function Hw.box(flat)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _i, s in ipairs(flat) do
        for i = 1, #s - 1, 2 do
            local x, y = s[i], s[i + 1]
            if x < x0 then x0 = x end
            if x > x1 then x1 = x end
            if y < y0 then y0 = y end
            if y > y1 then y1 = y end
        end
    end
    if x0 > x1 then return nil end
    return x0, y0, x1, y1
end

-- -------------------------------------------------------------- on the Kindle

local function pluginDir()
    local src = debug.getinfo(1, "S").source or ""
    return (src:gsub("^@", ""):match("^(.*)/[^/]*$")) or "."
end

--- The model and the word list, loaded once (about 0.5 MB). nil, why when they can't be.
function Hw.models()
    if Hw._net and Hw._words then return Hw._net, Hw._words end
    local dir = pluginDir() .. "/data/handwriting/"
    local net, err = require("gzreader_hwrnet").load(dir .. "hwr_en.bin")
    if not net then return nil, "model: " .. tostring(err) end
    local words, werr = require("gzreader_hwrwords").load(dir .. "hwr_words_en.txt", net.classes)
    if not words then return nil, "words: " .. tostring(werr) end
    Hw._net, Hw._words = net, words
    return net, words
end

--- The words in `flat`, read on the Kindle: text (lines joined by new lines), or nil, why.
function Hw.readHere(flat)
    local net, words = Hw.models()
    if not net then return nil, words end
    local ok, text = pcall(require("gzreader_hwr").read, flat, net, words)
    if not ok then return nil, tostring(text) end
    return text
end

-- -------------------------------------------------------------- the picture sent

--- The writing as a grey picture, black on white, at most MAX_SIDE wide or
--- high, PAD round it: mem (a uint8_t[w*h]), w, h. `radius`: the line's (px).
function Hw.picture(flat, radius)
    local ffi = require("ffi")
    local x0, y0, x1, y1 = Hw.box(flat)
    if not x0 then return nil end
    local scale = math.min(1, (Hw.MAX_SIDE - 2 * Hw.PAD) / math.max(1, x1 - x0, y1 - y0))
    local w = math.max(1, math.floor((x1 - x0) * scale + 2 * Hw.PAD + 0.5))
    local h = math.max(1, math.floor((y1 - y0) * scale + 2 * Hw.PAD + 0.5))
    local mem = ffi.new("uint8_t[?]", w * h)
    ffi.fill(mem, w * h, 255)
    local r = math.max(1, math.floor((radius or 3) * math.max(scale, 0.5) + 0.5))
    local function dot(cx, cy)
        for dy = -r, r do
            local yy = cy + dy
            if yy >= 0 and yy < h then
                local span = math.floor(math.sqrt(r * r - dy * dy) + 0.5)
                local row = yy * w
                for xx = math.max(0, cx - span), math.min(w - 1, cx + span) do mem[row + xx] = 0 end
            end
        end
    end
    local function at(x, y) return math.floor((x - x0) * scale + Hw.PAD + 0.5), math.floor((y - y0) * scale + Hw.PAD + 0.5) end
    for _i, s in ipairs(flat) do
        local px, py = at(s[1], s[2])
        dot(px, py)
        for i = 3, #s - 1, 2 do
            local qx, qy = at(s[i], s[i + 1])
            local n = math.max(1, math.ceil(math.max(math.abs(qx - px), math.abs(qy - py)) / math.max(1, r / 2)))
            for k = 1, n do dot(math.floor(px + (qx - px) * k / n + 0.5), math.floor(py + (qy - py) * k / n + 0.5)) end
            px, py = qx, qy
        end
    end
    return mem, w, h
end

--- The picture as PNG bytes (KOReader's lodepng), or nil, why.
function Hw.png(flat, radius, tmp)
    local mem, w, h = Hw.picture(flat, radius)
    if not mem then return nil, "nothing written" end
    tmp = tmp or (os.tmpname and os.tmpname() or "/tmp/gz-handwriting") .. ".png"
    local ok, err = require("ffi/png").encodeToFile(tmp, mem, w, h, 1)
    if ok == false then os.remove(tmp); return nil, tostring(err or "png") end
    local f = io.open(tmp, "rb")
    local bytes = f and f:read("*a")
    if f then f:close() end
    os.remove(tmp)
    if not bytes or #bytes == 0 then return nil, "png" end
    return bytes, w, h
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function Hw.base64(s)
    local ok, mime = pcall(require, "mime")
    if ok and type(mime) == "table" and mime.b64 then
        local a, b = mime.b64(s)
        return (a or "") .. (b or "")
    end
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1, c2 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64
        local c3, c4 = math.floor(n / 64) % 64, n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

-- -------------------------------------------------------------- online

--- Claude: url, headers, body (JSON) for reading the picture `b64` (a PNG's base64).
function Hw.claudeRequest(cfg, b64)
    return AI().request("claude", cfg, { text = Hw.PROMPT, png = b64, max_tokens = 1024 })
end

--- An OpenAI-style service (Chat Completions with a picture): url, headers, body.
function Hw.openaiRequest(cfg, b64)
    return AI().request("openai", cfg, { text = Hw.PROMPT, png = b64, max_tokens = 1024 })
end

--- The text in a service's answer (`code`, `body`), or nil and a reason a person can read.
function Hw.answerText(engine, code, body) return AI().answerText(engine, code, body) end

--- POST `body` to `url` (in the background process): code, body or nil, why.
function Hw.post(url, headers, body) return AI().post(url, headers, body, Hw.TIMEOUT) end

--- Reads `flat` online (the engine chosen): on_done(text) or on_done(nil, why). In the background.
function Hw.readOnline(plugin, flat, on_done, radius)
    local engine = Hw.engine(plugin)
    local cfg = AI().settings(plugin)[engine]
    if not cfg then return on_done(nil, "no AI key") end
    local png, err = Hw.png(flat, radius)
    if not png then return on_done(nil, err) end
    local url, headers, body
    if engine == "claude" then url, headers, body = Hw.claudeRequest(cfg, Hw.base64(png))
    else url, headers, body = Hw.openaiRequest(cfg, Hw.base64(png)) end
    if not Hw.safeUrl(url) then return on_done(nil, "the address must start with https://") end
    -- (the log says where to and how big, never the key)
    Log.info(string.format("handwriting: reading %d strokes with %s (%s), a %d KB picture", #flat, engine,
        url:match("^https?://([^/]+)") or "?", math.floor(#png / 1024)))
    local t0 = os.time()
    require("gzreader_net").run(function()
        require("gzreader_async").background(function() return Hw.post(url, headers, body) end, function(code, rbody)
            if not code then
                Log.warn("handwriting: online reading failed:", tostring(rbody))
                return on_done(nil, rbody == "timeout" and "it took too long" or "no answer (" .. tostring(rbody) .. ")")
            end
            local text, why = Hw.answerText(engine, code, rbody)
            Log.info("handwriting: answered", code, "in", os.time() - t0, "s", text and (#text .. " characters") or why)
            on_done(text, why)
        end, "handwriting", { timeout = Hw.TIMEOUT + 10 })
    end, { reason = "handwriting to text" })
end

--- Reads `flat`: on_done(text) or on_done(nil, why). Online when that's set up
--- (and `opts.here` isn't asked for), else on the Kindle (at once).
function Hw.read(plugin, flat, on_done, opts)
    opts = opts or {}
    if #flat == 0 then return on_done("") end
    if not opts.here and Hw.engine(plugin) ~= "kindle" then return Hw.readOnline(plugin, flat, on_done, opts.radius) end
    local t0 = os.clock()
    local text, err = Hw.readHere(flat)
    Log.info(string.format("handwriting: %d strokes read on the Kindle in %.2f s", #flat, os.clock() - t0))
    on_done(text, err)
end

return Hw
