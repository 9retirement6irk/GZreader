-- Handwriting to text (gzreader_handwriting.lua): read on the Kindle (Ink
-- Away's reader, on real pen strokes), the picture sent online, the requests
-- to Claude and to an OpenAI-style service and their answers, the settings,
-- and the keys kept with the other sign-ins (never in the log).
--   luajit handwriting_test.lua <gzreader.koplugin> <tests lib> <koreader base>
table.pack = table.pack or function(...) return { n = select("#", ...), ... } end
local PLUGIN, LIB, KOROOT = arg[1], arg[2], arg[3]
local HERE = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
package.path = PLUGIN .. "/?.lua;" .. LIB .. "/?.lua;" .. KOROOT .. "/frontend/?.lua;" .. KOROOT .. "/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

local logged = {}
package.preload["gzreader_log"] = function()
    local function keep(...) logged[#logged + 1] = table.concat((function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end return t end)(...), " ") end
    return { info = keep, warn = keep }
end
local dkjson = require("dkjson")
package.preload["gzreader_json"] = function()
    return { encode = function(v) return dkjson.encode(v) end,
        decode = function(s) local v, _p, err = dkjson.decode(s); if err then error(err) end; return v end }
end

local Hw = require("gzreader_handwriting")

print("== read on the Kindle")
do
    local writers = dofile(HERE .. "/hwr/hwr_writers.lua")
    local name = next(writers)
    local w = writers[name]
    -- "hello world" in one test writer's own letters, on a line
    local strokes = dofile(HERE .. "/hwr_write.lua")(w, "hello world", 60)
    -- (as the drawing screen has them: { points = { {x, y}, … } })
    local sk = {}
    for i, f in ipairs(strokes) do
        local pts = {}
        for j = 1, #f - 1, 2 do pts[#pts + 1] = { f[j], f[j + 1] } end
        sk[i] = { points = pts }
    end
    local flat = Hw.flat(sk)
    check(#flat == #strokes and #flat[1] == 2 * #sk[1].points, "the drawing's strokes, flat, in the order written")
    local t0 = os.clock()
    local text, err = Hw.readHere(flat)
    check(text and text:lower() == "hello world", "\"hello world\" in a writer's own letters reads " .. tostring(text or err)
        .. string.format(" (%.0f ms)", (os.clock() - t0) * 1000))
    local got
    Hw.read(nil, flat, function(t) got = t end)
    check(got == text, "no settings: read on the Kindle, at once")
end

print("== the picture sent")
do
    local mem, w, h = Hw.picture({ { 0, 0, 100, 0 }, { 0, 50, 100, 50 } }, 3)
    local black, white = 0, 0
    for i = 0, w * h - 1 do if mem[i] == 0 then black = black + 1 elseif mem[i] == 255 then white = white + 1 end end
    check(w == 100 + 2 * Hw.PAD and h == 50 + 2 * Hw.PAD and black > 0 and black + white == w * h,
        "the writing black on white, " .. Hw.PAD .. " px round it (" .. w .. "×" .. h .. ")")
    local _m, bw, bh = Hw.picture({ { 0, 0, 10000, 3000 } }, 3)
    check(math.max(bw, bh) <= Hw.MAX_SIDE, "…never more than " .. Hw.MAX_SIDE .. " px a side (" .. bw .. "×" .. bh .. ")")
    check(Hw.base64("") == "" and Hw.base64("f") == "Zg==" and Hw.base64("fo") == "Zm8=" and Hw.base64("foobar") == "Zm9vYmFy",
        "base64 as RFC 4648's examples")
end

print("== online: the requests and the answers")
do
    local url, h, body = Hw.claudeRequest({ key = "sk-ant-test-key" }, "QUJD")
    local b = dkjson.decode(body)
    local c = b.messages[1].content
    check(url == "https://api.anthropic.com/v1/messages" and h["x-api-key"] == "sk-ant-test-key" and h["anthropic-version"] == "2023-06-01"
        and b.model == require("gzreader_ai").CLAUDE_MODEL and c[1].type == "image" and c[1].source.media_type == "image/png" and c[1].source.data == "QUJD"
        and c[2].type == "text" and c[2].text:find("Transcribe", 1, true),
        "Claude: the Messages API, the key in x-api-key, the picture then what to do with it (" .. b.model .. ")")
    local _u2, _h2, body2 = Hw.claudeRequest({ key = "k", model = "claude-sonnet-5-5" }, "QUJD")
    check(dkjson.decode(body2).model == "claude-sonnet-5-5", "…another model when one is set")
    local ou, oh, obody = Hw.openaiRequest({ url = "https://llm.example.com/v1/", key = "sk-test", model = "vision-1" }, "QUJD")
    local ob = dkjson.decode(obody)
    check(ou == "https://llm.example.com/v1/chat/completions" and oh["Authorization"] == "Bearer sk-test" and ob.model == "vision-1"
        and ob.messages[1].content[2].image_url.url == "data:image/png;base64,QUJD",
        "an OpenAI-style service: /chat/completions, a bearer key, the picture as a data URL")
    check(Hw.openaiRequest({ url = "https://x.example.com/v1/chat/completions", key = "k", model = "m" }, "") == "https://x.example.com/v1/chat/completions",
        "…its full /chat/completions address as given")
    check(Hw.answerText("claude", 200, dkjson.encode({ content = { { type = "text", text = "  Speaking of work\n" } } })) == "Speaking of work",
        "Claude's answer: its text")
    check(Hw.answerText("openai", 200, dkjson.encode({ choices = { { message = { content = "\"hello world\"" } } } })) == "hello world",
        "an OpenAI-style answer: its message, quotes taken off")
    check(Hw.answerText("claude", 200, dkjson.encode({ content = { { type = "text", text = "```\nline one\nline two\n```" } } })) == "line one\nline two",
        "…a code fence taken off, its lines kept")
    local t1, w1 = Hw.answerText("claude", 401, dkjson.encode({ error = { message = "invalid x-api-key" } }))
    local t2, w2 = Hw.answerText("openai", 404, "")
    local t3, w3 = Hw.answerText("claude", 529, dkjson.encode({ error = { message = "Overloaded" } }))
    check(not t1 and w1:find("refused") and not t2 and w2:find("404") and not t3 and w3:find("529", 1, true) and w3:find("Overloaded", 1, true),
        "errors in words: a refused key, no such model, the service's own message (" .. w3 .. ")")
    check(Hw.safeUrl("https://api.anthropic.com/v1") and Hw.safeUrl("http://192.168.1.20:8080/v1") and Hw.safeUrl("http://localhost:11434/v1")
        and not Hw.safeUrl("http://llm.example.com/v1") and not Hw.safeUrl("ftp://x") and not Hw.safeUrl(nil),
        "a key goes over HTTPS only (plain HTTP only to this network)")
end

print("== settings and keys")
do
    local plugin = { store = {} }
    check(Hw.engine(plugin) == "kindle" and plugin.store.handwriting.engine == "kindle", "on the Kindle until a service is set up")
    local s = Hw.settings(plugin)
    local AI = require("gzreader_ai")
    s.engine = "ai"
    check(Hw.engine(plugin) == "kindle", "AI chosen without a key: still on the Kindle")
    s.openai.key = "sk-openai-secret"
    check(Hw.engine(plugin) == "kindle", "an OpenAI-style service without a model: on the Kindle")
    s.openai.model = "vision-1"
    check(Hw.engine(plugin) == "openai", "…with its model: the service")
    s.claude.key = "sk-ant-secret-key"
    AI.setProvider(plugin, "claude")
    check(Hw.engine(plugin) == "claude", "the AI connection set to Claude: Claude")
    s.engine = "claude"
    check(Hw.settings(plugin).engine == "ai" and Hw.engine(plugin) == "claude", "anything but \"kindle\" kept as the choice means the AI connection")
    AI.setProvider(plugin, "openai")
    check(Hw.engine(plugin) == "openai", "handwriting follows the service the AI connection uses")
    local src = io.open(PLUGIN .. "/gzreader_secrets.lua"):read("*a")
    check(src:find('{ "handwriting", "claude", "key" }, { "handwriting", "openai", "key" }', 1, true) ~= nil,
        "the keys are kept with the other sign-ins, off the USB drive (gzreader_secrets.lua)")
    local leaked = false
    for _i, l in ipairs(logged) do if l:find("secret", 1, true) or l:find("sk-", 1, true) then leaked = true end end
    local hsrc = io.open(PLUGIN .. "/gzreader_handwriting.lua"):read("*a")
    check(not leaked and not hsrc:find("Log%.%a+%([^\n]*key") and not hsrc:find("Log%.%a+%([^\n]*headers"),
        "no key in the log, and no log line with a key or the headers in it")
end

print(string.format("handwriting: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
