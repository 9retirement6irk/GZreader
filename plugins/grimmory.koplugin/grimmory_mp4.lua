--[[--
M4B / M4A (MP4 with AAC audio) to ADTS AAC, in plain Lua.

The Kindle 3 has a hardware AAC decoder for GStreamer (mfw_aacdecoder) but no
MP4 demuxer (no qtdemux). ADTS AAC is a plain stream of frames the decoder
takes directly, so an audiobook is converted once after download: each AAC
frame from the MP4 sample table gets a 7-byte ADTS header. The output is
split into chunk files of ~15 seconds (c0.aac, c1.aac, …), so playback can
start at any chunk: that is how GZreader resumes and seeks.
]]

local ffi = require("ffi")
local bit = require("bit")

local Mp4 = { CHUNK_SECONDS = 15 }

local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end
local function u64(s, i) return u32(s, i) * 4294967296 + u32(s, i + 4) end

local CONTAINERS = { moov = true, trak = true, mdia = true, minf = true, stbl = true, udta = false }

--- Read the box tree we need: for the first sound track, its timescale,
--- sample table (stts, stsc, stsz, stco/co64) and the AAC config (esds).
function Mp4.parse(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local size = f:seek("end")
    local tracks, cur = {}, nil

    local function readAt(pos, n) f:seek("set", pos); return f:read(n) or "" end

    local function walk(start, stop, depth)
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
                walk(body, body_end, depth + 1)
            elseif CONTAINERS[btype] then
                walk(body, body_end, depth + 1)
            elseif cur then
                if btype == "hdlr" then
                    cur.handler = readAt(body + 8, 4)
                elseif btype == "mdhd" then
                    local d = readAt(body, 32)
                    if d:byte(1) == 1 then cur.timescale, cur.duration = u32(d, 21), u64(d, 25)
                    else cur.timescale, cur.duration = u32(d, 13), u32(d, 17) end
                elseif btype == "stsd" then
                    -- entry: [size type] 6 reserved, 2 ref idx, 8 reserved, 2 channels, 2 bits, 4, 4 rate -> children
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
                    local d = readAt(body, bsize - hlen)
                    local n = u32(d, 5)
                    cur.stts = {}
                    for k = 0, n - 1 do cur.stts[#cur.stts + 1] = { u32(d, 9 + k * 8), u32(d, 13 + k * 8) } end
                elseif btype == "stsc" then
                    local d = readAt(body, bsize - hlen)
                    local n = u32(d, 5)
                    cur.stsc = {}
                    for k = 0, n - 1 do cur.stsc[#cur.stsc + 1] = { u32(d, 9 + k * 12), u32(d, 13 + k * 12) } end
                elseif btype == "stsz" then
                    local d = readAt(body, 12)
                    local fixed, n = u32(d, 5), u32(d, 9)
                    cur.count = n
                    cur.fixed_size = fixed > 0 and fixed or nil
                    if fixed == 0 then
                        local raw = readAt(body + 12, n * 4)
                        local sizes = ffi.new("uint32_t[?]", n)
                        for k = 0, n - 1 do sizes[k] = u32(raw, 1 + k * 4) end
                        cur.sizes = sizes
                    end
                elseif btype == "stco" or btype == "co64" then
                    local d = readAt(body, bsize - hlen)
                    local n = u32(d, 5)
                    local offs = ffi.new("double[?]", n)
                    for k = 0, n - 1 do
                        offs[k] = btype == "stco" and u32(d, 9 + k * 4) or u64(d, 9 + k * 8)
                    end
                    cur.chunks, cur.chunk_count = offs, n
                end
            end
            pos = body_end
        end
    end
    walk(0, size, 0)
    f:close()
    for _i, t in ipairs(tracks) do
        if t.handler == "soun" and t.codec == "mp4a" and t.asc and t.count and t.chunks then return t end
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
--- progress(done_bytes) is called now and then. Returns
--- { starts = { ms… }, durationMs, count } or nil, err.
function Mp4.convert(path, out_dir, progress)
    local t, err = Mp4.parse(path)
    if not t then return nil, err end
    local ot, sfi, ch = Mp4.config(t.asc)
    local inp = io.open(path, "rb")
    if not inp then return nil, "cannot open " .. path end
    local chunk_len = Mp4.CHUNK_SECONDS * t.timescale
    -- per-sample duration from stts
    local stts_i, stts_left = 1, t.stts and t.stts[1] and t.stts[1][1] or 0
    local function nextDuration()
        while t.stts[stts_i] and stts_left == 0 do
            stts_i = stts_i + 1
            stts_left = t.stts[stts_i] and t.stts[stts_i][1] or 0
        end
        local e = t.stts[stts_i]
        if not e then return 1024 end
        stts_left = stts_left - 1
        return e[2]
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
    if not openChunk() then inp:close(); return nil, "cannot write to " .. out_dir end
    local stsc_i = 1
    for c = 0, t.chunk_count - 1 do
        -- samples per chunk from stsc (first_chunk is 1-based)
        while t.stsc[stsc_i + 1] and t.stsc[stsc_i + 1][1] <= c + 1 do stsc_i = stsc_i + 1 end
        local n = t.stsc[stsc_i][2]
        local total = 0
        for k = 0, n - 1 do
            if sample + k >= t.count then break end
            total = total + (t.fixed_size or t.sizes[sample + k])
        end
        inp:seek("set", t.chunks[c])
        local data = inp:read(total) or ""
        local pos = 1
        for k = 0, n - 1 do
            if sample >= t.count then break end
            local sz = t.fixed_size or t.sizes[sample]
            if time >= (out_n + 1) * chunk_len then
                if not openChunk() then inp:close(); return nil, "cannot write chunk" end
            end
            out:write(Mp4.adtsHeader(ot, sfi, ch, sz), data:sub(pos, pos + sz - 1))
            pos = pos + sz
            time = time + nextDuration()
            sample = sample + 1
        end
        done = done + total
        if progress and c % 200 == 0 then progress(done) end
    end
    if out then out:close() end
    inp:close()
    return { starts = starts, durationMs = math.floor(time * 1000 / t.timescale), count = out_n + 1 }
end

return Mp4
