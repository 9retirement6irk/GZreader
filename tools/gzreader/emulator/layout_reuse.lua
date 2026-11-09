-- A book laid out in the background (gzreader_layout.lua) opens without
-- being laid out again: the reader finds the layout the background process
-- wrote. Opens one copy laid out first and one that wasn't, and compares the
-- time crengine's render took in each.
--   GZ_EMU_BIG=<big.epub> GZ_EMU_TREE=<tree>/koreader ./run.sh layout_reuse.lua <out>
-- Writes <out>/layout_reuse.txt.
local s = { start = 12, { key = "Back", after = 4 } }
local lines = {}
local function say(t) lines[#lines + 1] = t end
local st = {}
local function renders()
    local CreDocument = require("document/credocument")
    if CreDocument._gz_timed then return end
    CreDocument._gz_timed = true
    local orig = CreDocument.render
    CreDocument.render = function(doc, ...)
        local t = require("ui/time").now()
        local r = { orig(doc, ...) }
        st.render_s = (st.render_s or 0) + require("ui/time").to_s(require("ui/time").now() - t)
        st.renders = (st.renders or 0) + 1
        return unpack(r)
    end
end
local dir = "/mnt/us/GZreader"
s[#s + 1] = { fn = function()
    os.execute("mkdir -p " .. dir .. " && cp '" .. os.getenv("GZ_EMU_BIG") .. "' " .. dir .. "/laidout.epub && cp '"
        .. os.getenv("GZ_EMU_BIG") .. "' " .. dir .. "/fresh.epub")
    local plugin = require("apps/filemanager/filemanager").instance.gzreader
    st.entry = { path = dir .. "/laidout.epub" }
    st.started = require("gzreader_layout").start(plugin, "check", st.entry, function(ok, line) st.done = { ok = ok, line = line } end, true)
end, after = 1 }
s[#s + 1] = { wait_for = function() return st.done ~= nil end, timeout = 300 }
s[#s + 1] = { fn = function()
    say("background layout: " .. tostring(st.done and st.done.line))
    renders()
    st.render_s, st.renders = 0, 0
    require("apps/reader/readerui"):showReader(dir .. "/laidout.epub")
end, after = 60 }
s[#s + 1] = { fn = function()
    st.laid = { s = st.render_s, n = st.renders }
    st.render_s, st.renders = 0, 0
    require("apps/reader/readerui").instance:switchDocument(dir .. "/fresh.epub")
end, after = 90 }
s[#s + 1] = { fn = function(E)
    local fresh = { s = st.render_s, n = st.renders }
    say(string.format("laid out in the background: render %.1f s (%d calls)", st.laid.s, st.laid.n))
    say(string.format("never laid out:            render %.1f s (%d calls)", fresh.s, fresh.n))
    say((st.laid.s < fresh.s / 3 and "ok   " or "FAIL ") .. "the background layout was used when the book opened")
    local f = io.open(E.out .. "/layout_reuse.txt", "w")
    if f then f:write(table.concat(lines, "\n"), "\n"); f:close() end
end, after = 1 }
return s
