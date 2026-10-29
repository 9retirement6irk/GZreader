--[[--
gunzip for Grimmory's JSON replies.

Grimmory compresses JSON (Spring's server.compression) when asked with
Accept-Encoding: gzip. Book lists and the library index shrink 5–10x, which
on a Kindle 3 means less to receive over Wi-Fi and less to decrypt (TLS is
expensive on its CPU). zlib is part of KOReader; only its whole-buffer
functions are declared there, so inflate is declared here.
]]

local ffi = require("ffi")

local Gzip = {}

local ok_cdef = pcall(ffi.cdef, [[
typedef struct gz_z_stream_s {
    const unsigned char *next_in; unsigned int avail_in; unsigned long total_in;
    unsigned char *next_out; unsigned int avail_out; unsigned long total_out;
    const char *msg; void *state;
    void *zalloc; void *zfree; void *opaque;
    int data_type; unsigned long adler; unsigned long reserved;
} gz_z_stream;
int inflateInit2_(gz_z_stream *strm, int windowBits, const char *version, int stream_size);
int inflate(gz_z_stream *strm, int flush);
int inflateEnd(gz_z_stream *strm);
const char *zlibVersion(void);
]])

local libz
local function lib()
    if libz ~= nil then return libz or nil end
    libz = false
    if not ok_cdef then return nil end
    local tries = {
        function() return ffi.loadlib("z", 1) end,
        function() return ffi.load("libs/libz.so.1") end,
        function() return ffi.load("z") end,
        function() return ffi.load("libz.so.1") end,
    }
    for _i, t in ipairs(tries) do
        local ok, l = pcall(t)
        if ok and l and pcall(function() return l.inflateInit2_ end) then libz = l; return l end
    end
    return nil
end

function Gzip.available() return lib() ~= nil end

--- Decompress gzip data; nil, err on failure.
function Gzip.inflate(data)
    local z = lib()
    if not z then return nil, "no zlib" end
    local strm = ffi.new("gz_z_stream")
    strm.next_in = ffi.cast("const unsigned char *", data)
    strm.avail_in = #data
    if z.inflateInit2_(strm, 15 + 32, z.zlibVersion(), ffi.sizeof("gz_z_stream")) ~= 0 then
        return nil, "inflateInit failed"
    end
    local chunk = math.max(65536, #data * 4)
    local buf = ffi.new("unsigned char[?]", chunk)
    local parts = {}
    local ret
    repeat
        strm.next_out = buf
        strm.avail_out = chunk
        ret = z.inflate(strm, 0)
        if ret ~= 0 and ret ~= 1 then
            z.inflateEnd(strm)
            return nil, "inflate error " .. tostring(ret)
        end
        parts[#parts + 1] = ffi.string(buf, chunk - strm.avail_out)
    until ret == 1 or (strm.avail_in == 0 and strm.avail_out ~= 0)
    z.inflateEnd(strm)
    return table.concat(parts)
end

return Gzip
