--[[--
M4B / M4A (MP4 with AAC audio) to ADTS AAC, in plain Lua.

The Kindle 3 has a hardware AAC decoder for GStreamer (mfw_aacdecoder) but no
MP4 demuxer (no qtdemux). ADTS AAC is a plain stream of frames the decoder
takes directly, so an audiobook is converted once after download: each AAC
frame from the MP4 sample table gets a 7-byte ADTS header. The output is
split into chunk files of ~15 seconds (c0.aac, c1.aac, …), so playback can
start at any chunk: that is how GZreader resumes and seeks.

Memory: the sample-size and chunk-offset tables of a long book are millions
of entries, so they're read from the file in small blocks as the conversion
goes, never loaded whole. Output is written one MP4 chunk at a time.

Run it as its own process (that's how GZreader uses it, at low priority):
    luajit gzreader_mp4.lua <in.m4b> <out-dir> <progress-file>
It writes "<done-bytes> <total-bytes>" to the progress file as it goes, and
<out-dir>/index.json at the end. A fresh small process instead of a fork of
KOReader: a forked copy would duplicate KOReader's whole memory as the
garbage collector touches it, which ran the Kindle 3 out of memory.
]]

local ffi = require("ffi")
local bit = require("bit")

local Mp4 = { CHUNK_SECONDS = 15, BLOCK = 65536 }

local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end
local function u64(s, i) return u32(s, i) * 4294967296 + u32(s, i + 4) end

local CONTAINERS = { moov = true, trak = true, mdia = true, minf = true, stbl = true }

--- Sequential reader of a table of `width`-byte big-endian entries starting
--- at file offset `base`, through its own file handle and a small buffer.
local function tableReader(path, base, width)
    local f = assert(io.open(path, "rb"))
    local buf, buf_first, buf_n = "", 0, 0 -- entries [buf_first, buf_first + buf_n)
    local per = math.floor(Mp4.BLOCK / width)
    local r = {}
    function r.get(i) -- 0-based
        if i < buf_first or i >= buf_first + buf_n then
            buf_first = i
            f:seek("set", base + i * width)
            buf = f:read(per * width) or ""
            buf_n = math.floor(#buf / width)
            if buf_n == 0 then return nil end
        end
        local o = (i - buf_first) * width + 1
        if width == 8 then return u64(buf, o) end
        return u32(buf, o)
    end
    function r.close() f:close() end
    return r
end

--- Read the box tree we need: for the first sound track, its timescale,
--- where its sample tables are, and the AAC config (esds).
function Mp4.parse(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local size = f:seek("end")
    local tracks, cur = {}, nil

    local function readAt(pos, n) f:seek("set", pos); return f:read(n) or "" end
    local function readTable(body, entry_words) -- small tables (stts, stsc): into ffi arrays
        local d = readAt(body, 8)
        local n = u32(d, 5)
        local arr = ffi.new("uint32_t[?]", math.max(1, n * entry_words))
        local rd = tableReader(path, body + 8, 4)
        for k = 0, n * entry_words - 1 do arr[k] = rd.get(k) or 0 end
        rd.close()
        return arr, n
    end

    local function walk(start, stop)
        local pos = start
        while pos + 8 <= stop do
            local hdr = readAt(pos, 16)
            if #hdr < 8 then break end
            local bsize, btype = u32(hdr, 1), hdr:sub(5, 8)
            local hlen = 8
            if bsize == 1 then bsize, hlen = u64(hdr, 9), 16
            elseif bsize == 0 then bsize = stop - pos end
            if bsize < hlen then break end
            local body, body_end = pos + hlen, pos + bsize
            if btype == "trak" then
                cur = {}
                tracks[#tracks + 1] = cur
                walk(body, body_end)
            elseif CONTAINERS[btype] then
                walk(body, body_end)
            elseif cur then
                if btype == "hdlr" then
                    cur.handler = readAt(body + 8, 4)
                elseif btype == "mdhd" then
                    local d = readAt(body, 32)
                    if d:byte(1) == 1 then cur.timescale, cur.duration = u32(d, 21), u64(d, 25)
                    else cur.timescale, cur.duration = u32(d, 13), u32(d, 17) end
                elseif btype == "stsd" then
                    local d = readAt(body, math.min(bsize - hlen, 4096))
                    cur.codec = d:sub(13, 16)
                    local esds = d:find("esds", 1, true)
                    if esds then
                        -- descriptors: find DecoderSpecificInfo (tag 5)
                        local i = esds + 8 -- after "esds" + version/flags
                        while i <= #d do
                            local tag = d:byte(i); i = i + 1
                            local len = 0
                            for _k = 1, 4 do
                                local b = d:byte(i); i = i + 1
                                if not b then break end
                                len = len * 128 + bit.band(b, 0x7F)
                                if b < 0x80 then break end
                            end
                            if tag == 0x03 then i = i + 3          -- ES_ID, flags (no optional fields)
                            elseif tag == 0x04 then i = i + 13     -- DecoderConfig fixed part
                            elseif tag == 0x05 then cur.asc = d:sub(i, i + len - 1); break
                            else i = i + len end
                        end
                    end
                elseif btype == "stts" then
                    cur.stts, cur.stts_n = readTable(body, 2)
                elseif btype == "stsc" then
                    cur.stsc, cur.stsc_n = readTable(body, 3)
                elseif btype == "stsz" then
                    local d = readAt(body, 12)
                    local fixed, n = u32(d, 5), u32(d, 9)
                    cur.count = n
                    cur.fixed_size = fixed > 0 and fixed or nil
                    cur.stsz_at = body + 12
                elseif btype == "stco" or btype == "co64" then
                    local d = readAt(body, 8)
                    cur.chunk_count = u32(d, 5)
                    cur.stco_at, cur.stco_w = body + 8, btype == "stco" and 4 or 8
                end
            end
            pos = body_end
        end
    end
    walk(0, size)
    f:close()
    for _i, t in ipairs(tracks) do
        if t.handler == "soun" and t.codec == "mp4a" and t.asc and t.count and t.stco_at and t.stsc and t.stts then
            t.path, t.file_size = path, size
            return t
        end
    end
    return nil, "no AAC audio track found"
end

--- AudioSpecificConfig -> object type, sampling frequency index, channels.
function Mp4.config(asc)
    local b0, b1 = asc:byte(1), asc:byte(2) or 0
    local ot = bit.rshift(b0, 3)
    local sfi = bit.bor(bit.lshift(bit.band(b0, 7), 1), bit.rshift(b1, 7))
    local ch = bit.band(bit.rshift(b1, 3), 0xF)
    if ot == 5 or ot == 29 then ot = 2 end -- HE-AAC: the core is AAC-LC
    return ot, sfi, ch
end

function Mp4.adtsHeader(ot, sfi, ch, payload_len)
    local len = payload_len + 7
    return string.char(
        0xFF, 0xF1,
        bit.bor(bit.lshift(bit.band(ot - 1, 3), 6), bit.lshift(bit.band(sfi, 0xF), 2), bit.band(bit.rshift(ch, 2), 1)),
        bit.bor(bit.lshift(bit.band(ch, 3), 6), bit.band(bit.rshift(len, 11), 3)),
        bit.band(bit.rshift(len, 3), 0xFF),
        bit.bor(bit.lshift(bit.band(len, 7), 5), 0x1F),
        0xFC)
end

--- Convert `path` into ADTS chunk files out_dir/c0.aac, c1.aac, …
--- progress(done_bytes, total_bytes) is called now and then. Returns
--- { starts = { ms… }, durationMs, count } or nil, err.
function Mp4.convert(path, out_dir, progress)
    local t, err = Mp4.parse(path)
    if not t then return nil, err end
    local ot, sfi, ch = Mp4.config(t.asc)
    local inp = io.open(path, "rb")
    if not inp then return nil, "cannot open " .. path end
    local sizes = not t.fixed_size and tableReader(path, t.stsz_at, 4) or nil
    local offsets = tableReader(path, t.stco_at, t.stco_w)
    local chunk_len = Mp4.CHUNK_SECONDS * t.timescale
    -- per-sample duration from stts
    local stts_i, stts_left = 0, t.stts_n > 0 and t.stts[0] or 0
    local function nextDuration()
        while stts_i < t.stts_n and stts_left == 0 do
            stts_i = stts_i + 1
            stts_left = stts_i < t.stts_n and t.stts[stts_i * 2] or 0
        end
        if stts_i >= t.stts_n then return 1024 end
        stts_left = stts_left - 1
        return t.stts[stts_i * 2 + 1]
    end
    local starts, out, out_n = {}, nil, -1
    local time, sample, done = 0, 0, 0
    local function openChunk()
        if out then out:close() end
        out_n = out_n + 1
        starts[#starts + 1] = math.floor(time * 1000 / t.timescale)
        out = io.open(out_dir .. "/c" .. out_n .. ".aac", "wb")
        return out ~= nil
    end
    local function fail(msg)
        if out then out:close() end
        inp:close(); offsets.close(); if sizes then sizes.close() end
        return nil, msg
    end
    if not openChunk() then return fail("cannot write to " .. out_dir) end
    local stsc_i = 0
    local next_report = 0
    for c = 0, t.chunk_count - 1 do
        -- samples per chunk from stsc (first_chunk is 1-based)
        while stsc_i + 1 < t.stsc_n and t.stsc[(stsc_i + 1) * 3] <= c + 1 do stsc_i = stsc_i + 1 end
        local n = t.stsc[stsc_i * 3 + 1]
        local chunk_sizes, total = {}, 0
        for k = 0, n - 1 do
            if sample + k >= t.count then break end
            local sz = t.fixed_size or sizes.get(sample + k) or 0
            chunk_sizes[#chunk_sizes + 1] = sz
            total = total + sz
        end
        local off = offsets.get(c)
        if not off then break end
        inp:seek("set", off)
        local data = inp:read(total) or ""
        local pos, pieces = 1, {}
        for k = 1, #chunk_sizes do
            local sz = chunk_sizes[k]
            if time >= (out_n + 1) * chunk_len then
                if #pieces > 0 then out:write(table.concat(pieces)); pieces = {} end
                if not openChunk() then return fail("cannot write chunk") end
            end
            pieces[#pieces + 1] = Mp4.adtsHeader(ot, sfi, ch, sz)
            pieces[#pieces + 1] = data:sub(pos, pos + sz - 1)
            pos = pos + sz
            time = time + nextDuration()
            sample = sample + 1
        end
        if #pieces > 0 and not out:write(table.concat(pieces)) then return fail("disk full?") end
        done = done + total
        if progress and done >= next_report then
            progress(done, t.file_size)
            next_report = done + math.max(256 * 1024, math.floor(t.file_size / 200))
        end
    end
    if out then out:close() end
    inp:close(); offsets.close(); if sizes then sizes.close() end
    if progress then progress(t.file_size, t.file_size) end
    return { starts = starts, durationMs = math.floor(time * 1000 / t.timescale), count = out_n + 1 }
end

--- index.json for a conversion result (no JSON library needed here).
function Mp4.indexJson(res)
    local s = {}
    for i, v in ipairs(res.starts) do s[i] = string.format("%d", v) end
    return string.format('{"starts":[%s],"durationMs":%d,"count":%d}', table.concat(s, ","), res.durationMs, res.count)
end

-- Command line: luajit gzreader_mp4.lua <in> <out-dir> <progress-file>
if type(arg) == "table" and type(arg[0]) == "string" and arg[0]:match("gzreader_mp4%.lua$") and arg[1] then
    local input, out_dir, prog = arg[1], arg[2], arg[3]
    local function report(text)
        if not prog then return end
        local f = io.open(prog .. ".tmp", "wb")
        if f then f:write(text, "\n"); f:close(); os.rename(prog .. ".tmp", prog) end
    end
    local ok, res, cerr = pcall(Mp4.convert, input, out_dir, function(d, t) report(d .. " " .. t) end)
    if not ok or not res then
        report("error " .. tostring(ok and cerr or res))
        os.exit(1)
    end
    local f = io.open(out_dir .. "/index.json.tmp", "wb")
    if not f then report("error cannot write index"); os.exit(1) end
    f:write(Mp4.indexJson(res)); f:close()
    os.rename(out_dir .. "/index.json.tmp", out_dir .. "/index.json")
    report("done " .. res.count)
    os.exit(0)
end

return Mp4
