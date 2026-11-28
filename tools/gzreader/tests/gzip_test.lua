-- gunzip (plugins/gzreader.koplugin/gzreader_gzip.lua) beside another plugin
-- that declares zlib its own way (a ZenPM plugin did: every compressed reply
-- failed with "cannot convert 'struct gz_z_stream_s' to 'struct z_stream_s *'").
--   luajit gzip_test.lua <gzreader.koplugin>
local PLUGIN = arg[1]
package.path = PLUGIN .. "/?.lua;" .. package.path
local ffi = require("ffi")
local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
-- (the host's zlib, as the Kindle's libs/libz.so.1)
ffi.loadlib = function(name) return ffi.load(name) end

-- another plugin first: zlib's own names, with its own z_stream
ffi.cdef[[
typedef struct z_stream_s {
    const unsigned char *next_in; unsigned int avail_in; unsigned long total_in;
    unsigned char *next_out; unsigned int avail_out; unsigned long total_out;
    const char *msg; void *state; void *zalloc; void *zfree; void *opaque;
    int data_type; unsigned long adler; unsigned long reserved;
} z_stream;
int inflateInit2_(z_stream *strm, int windowBits, const char *version, int stream_size);
int inflate(z_stream *strm, int flush);
int inflateEnd(z_stream *strm);
const char *zlibVersion(void);
]]

local function run(cmd) local p = io.popen(cmd); local s = p:read("*a"); p:close(); return s end
local text = string.rep('{"books":[{"id":1,"title":"Example"}]}', 200)
local tmp = os.tmpname()
local f = io.open(tmp, "w"); f:write(text); f:close()
local gz = run("gzip -c '" .. tmp .. "'")
local raw = run("python3 -I -c \"import zlib,sys; c=zlib.compressobj(9, zlib.DEFLATED, -15); d=open(sys.argv[1],'rb').read(); sys.stdout.buffer.write(c.compress(d)+c.flush())\" '" .. tmp .. "'")
os.remove(tmp)

print("== gunzip beside another plugin's zlib")
local Gzip = require("gzreader_gzip")
check(Gzip.available(), "zlib found")
local out, err = Gzip.inflate(gz)
check(out == text, "a gzip reply, after another plugin declared inflateInit2_ & co. with its own z_stream (" .. tostring(err) .. ")")
check(Gzip.inflateRaw(raw) == text, "…a zip entry's bare deflate too")
check(select(2, Gzip.inflate(gz, 100)) == "too big", "…a size limit still holds")
-- the other plugin still has zlib its way
local z = ffi.load("z")
local strm = ffi.new("z_stream")
strm.next_in = ffi.cast("const unsigned char *", gz); strm.avail_in = #gz
check(z.inflateInit2_(strm, 15 + 32, z.zlibVersion(), ffi.sizeof("z_stream")) == 0, "…and the other plugin's own declarations still work")
z.inflateEnd(strm)
local src = io.open(PLUGIN .. "/gzreader_gzip.lua"):read("*a")
check(src:find('__asm__("inflateInit2_")', 1, true) and not src:find("%f[%w_]z%.inflateInit2_%(") and not src:find("%f[%w_]z%.inflate%("),
    "GZreader calls zlib only by its own names")

print(string.format("gzip: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
