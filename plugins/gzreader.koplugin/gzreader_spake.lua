--[[--
A PIN-protected secure channel between two GZreader devices (copying
connections, gzreader_copy.lua): SPAKE2 with a 6-digit PIN, then AES-256-GCM.

Why SPAKE2: someone on the same Wi-Fi who watches (or even sits in the
middle of) the exchange learns nothing they can test PIN guesses against
offline; each wrong guess costs them one try on the sending device, which
gives up after a few. A plain "encrypt with a key made from the PIN" would
fall to a million guesses in a second.

Group: RFC 3526's 2048-bit MODP group (a safe prime p, g = 2, which
generates the subgroup of order q = (p - 1) / 2). M and N are hashed into
that subgroup (nobody knows their discrete logarithms). Receiver ("A"):
X = g^x · M^w; sender ("B"): Y = g^y · N^w; both get Z = g^(2xy) (squared:
clears the cofactor 2); w = SHA-256 of the PIN. Keys come from SHA-256 of the
whole transcript; each side proves it has them (key confirmation) before
anything secret is sent. Arithmetic, hashes, random numbers and AES-GCM are
the device's libcrypto (LibreSSL in KOReader's Kindle builds).
]]

local ffi = require("ffi")

local DECLS = {
    "typedef struct bignum_st BIGNUM;",
    "typedef struct bignum_ctx BN_CTX;",
    "typedef struct engine_st ENGINE;",
    "typedef struct evp_cipher_st EVP_CIPHER;",
    "typedef struct evp_cipher_ctx_st EVP_CIPHER_CTX;",
    "typedef struct env_md_st EVP_MD;",
    "BIGNUM *BN_new(void);",
    "void BN_clear_free(BIGNUM *a);",
    "BN_CTX *BN_CTX_new(void);",
    "void BN_CTX_free(BN_CTX *c);",
    "BIGNUM *BN_bin2bn(const unsigned char *s, int len, BIGNUM *ret);",
    "int BN_bn2bin(const BIGNUM *a, unsigned char *to);",
    "int BN_num_bits(const BIGNUM *a);",
    "int BN_cmp(const BIGNUM *a, const BIGNUM *b);",
    "int BN_mod_exp(BIGNUM *r, const BIGNUM *a, const BIGNUM *p, const BIGNUM *m, BN_CTX *ctx);",
    "int BN_mod_mul(BIGNUM *r, const BIGNUM *a, const BIGNUM *b, const BIGNUM *m, BN_CTX *ctx);",
    "BIGNUM *BN_mod_inverse(BIGNUM *ret, const BIGNUM *a, const BIGNUM *n, BN_CTX *ctx);",
    "int BN_nnmod(BIGNUM *r, const BIGNUM *m, const BIGNUM *d, BN_CTX *ctx);",
    "int RAND_bytes(unsigned char *buf, int num);",
    "const EVP_MD *EVP_sha256(void);",
    "unsigned char *SHA256(const unsigned char *d, size_t n, unsigned char *md);",
    "unsigned char *HMAC(const EVP_MD *evp_md, const void *key, int key_len, const unsigned char *d, size_t n, unsigned char *md, unsigned int *md_len);",
    "EVP_CIPHER_CTX *EVP_CIPHER_CTX_new(void);",
    "void EVP_CIPHER_CTX_free(EVP_CIPHER_CTX *);",
    "int EVP_CIPHER_CTX_ctrl(EVP_CIPHER_CTX *ctx, int type, int arg, void *ptr);",
    "const EVP_CIPHER *EVP_aes_256_gcm(void);",
    "int EVP_EncryptInit_ex(EVP_CIPHER_CTX *, const EVP_CIPHER *, ENGINE *, const unsigned char *, const unsigned char *);",
    "int EVP_EncryptUpdate(EVP_CIPHER_CTX *, unsigned char *, int *, const unsigned char *, int);",
    "int EVP_EncryptFinal_ex(EVP_CIPHER_CTX *, unsigned char *, int *);",
    "int EVP_DecryptInit_ex(EVP_CIPHER_CTX *, const EVP_CIPHER *, ENGINE *, const unsigned char *, const unsigned char *);",
    "int EVP_DecryptUpdate(EVP_CIPHER_CTX *, unsigned char *, int *, const unsigned char *, int);",
    "int EVP_DecryptFinal_ex(EVP_CIPHER_CTX *, unsigned char *, int *);",
}
for _i, d in ipairs(DECLS) do pcall(ffi.cdef, d) end -- (some are KOReader's ffi/crypto_h already)

local EVP_CTRL_GCM_SET_IVLEN, EVP_CTRL_GCM_GET_TAG, EVP_CTRL_GCM_SET_TAG = 0x9, 0x10, 0x11

local C
local function lib()
    if C then return C end
    local tries = {}
    if ffi.loadlib then tries[#tries + 1] = function() return ffi.loadlib("crypto", "57") end end
    for _i, name in ipairs({ "libs/libcrypto.so.57", "libcrypto.so.57", "libcrypto.so.3", "libcrypto.so.1.1", "crypto" }) do
        tries[#tries + 1] = function() return ffi.load(name) end
    end
    for _i, try in ipairs(tries) do
        local ok, l = pcall(try)
        if ok and l and pcall(function() return l.BN_mod_exp end) then C = l; return C end
    end
    error("libcrypto not found")
end

local S = { ELEMENT = 256 } -- bytes in a group element (2048 bits)

S.P_HEX = "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DD"
    .. "EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED"
    .. "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F"
    .. "83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B"
    .. "E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA0510"
    .. "15728E5A8AACAA68FFFFFFFFFFFFFFFF"

---------------------------------------------------------------- bytes

function S.hex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
function S.unhex(h)
    if type(h) ~= "string" or #h % 2 ~= 0 or h:find("[^%x]") then return nil end
    return (h:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end))
end

function S.random(n)
    local buf = ffi.new("unsigned char[?]", n)
    if lib().RAND_bytes(buf, n) ~= 1 then error("no random numbers") end
    return ffi.string(buf, n)
end

function S.sha256(s)
    local out = ffi.new("unsigned char[32]")
    lib().SHA256(s, #s, out)
    return ffi.string(out, 32)
end

function S.hmac(key, msg)
    local out = ffi.new("unsigned char[32]")
    local len = ffi.new("unsigned int[1]")
    lib().HMAC(lib().EVP_sha256(), key, #key, msg, #msg, out, len)
    return ffi.string(out, len[0])
end

--- Compare without stopping at the first difference.
function S.equal(a, b)
    if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then return false end
    local d = 0
    for i = 1, #a do d = bit.bor(d, bit.bxor(a:byte(i), b:byte(i))) end
    return d == 0
end

local function lp(s) -- length-prefixed (4 bytes, big-endian)
    local n = #s
    return string.char(bit.band(bit.rshift(n, 24), 255), bit.band(bit.rshift(n, 16), 255),
        bit.band(bit.rshift(n, 8), 255), bit.band(n, 255)) .. s
end

---------------------------------------------------------------- numbers

local function bn(bytes)
    local b = lib().BN_bin2bn(bytes, #bytes, nil)
    return ffi.gc(b, lib().BN_clear_free)
end
local function new() return ffi.gc(lib().BN_new(), lib().BN_clear_free) end
local function bytesOf(b, width)
    local n = math.floor((lib().BN_num_bits(b) + 7) / 8)
    local buf = ffi.new("unsigned char[?]", math.max(n, 1))
    lib().BN_bn2bin(b, buf)
    local s = ffi.string(buf, n)
    if width and #s < width then s = string.rep("\0", width - #s) .. s end
    return s
end

local G -- the group: { p, q, g, M, N, p_minus_1, one, ctx }
local function group()
    if G then return G end
    local ctx = ffi.gc(lib().BN_CTX_new(), lib().BN_CTX_free)
    local p = bn(S.unhex(S.P_HEX))
    local function hashToGroup(label)
        local t = {}
        for i = 1, 8 do t[i] = S.sha256("GZreader SPAKE2 " .. label .. " " .. i) end -- 256 bytes
        local e, r = bn(table.concat(t)), new()
        lib().BN_nnmod(r, e, p, ctx)
        local sq = new()
        lib().BN_mod_mul(sq, r, r, p, ctx) -- a square: in the order-q subgroup
        return sq
    end
    local pm1 = bn(S.unhex(S.P_HEX:sub(1, -2) .. "E"))
    G = { p = p, g = bn("\2"), M = hashToGroup("M"), N = hashToGroup("N"), pm1 = pm1, one = bn("\1"), ctx = ctx }
    return G
end

local function modexp(a, e)
    local r = new()
    assert(lib().BN_mod_exp(r, a, e, group().p, group().ctx) == 1)
    return r
end
local function modmul(a, b)
    local r = new()
    assert(lib().BN_mod_mul(r, a, b, group().p, group().ctx) == 1)
    return r
end
local function inverse(a)
    local r = new()
    assert(lib().BN_mod_inverse(r, a, group().p, group().ctx) ~= nil)
    return r
end

--- w: the PIN as a number (256 bits, below q).
local function pinScalar(pin)
    return bn(S.sha256("GZreader copy PIN v1|" .. tostring(pin)))
end

---------------------------------------------------------------- the exchange

local Session = {}
Session.__index = Session

--- role "A" (the receiving device) or "B" (the sending one).
function S.new(role, pin)
    local g = group()
    local self = setmetatable({ role = role, pin = tostring(pin) }, Session)
    self.w = pinScalar(self.pin)
    self.x = bn(S.random(40)) -- 320 bits: 160-bit security in a 2048-bit group's ~112
    local mask = modexp(role == "A" and g.M or g.N, self.w)
    self.mine = bytesOf(modmul(modexp(g.g, self.x), mask), S.ELEMENT)
    return self
end

--- This side's message (hex).
function Session:message() return S.hex(self.mine) end

--- Take the other side's message (hex): true, or nil, why. Then the keys
--- and confirmations are ready.
function Session:finish(peer_hex)
    local g = group()
    local peer = S.unhex(peer_hex or "")
    if not peer or #peer ~= S.ELEMENT then return nil, "bad message" end
    local E = bn(peer)
    -- 1 < E < p - 1 (and so neither of the elements of order 1 or 2)
    if lib().BN_cmp(E, g.one) <= 0 or lib().BN_cmp(E, g.pm1) >= 0 then return nil, "bad message" end
    local unmask = inverse(modexp(self.role == "A" and g.N or g.M, self.w))
    local base = modmul(E, unmask)
    local Z = modexp(modexp(base, self.x), bn("\2"))
    local X, Y
    if self.role == "A" then X, Y = self.mine, peer else X, Y = peer, self.mine end
    local tt = lp("GZreader copy v1") .. lp("receiver") .. lp("sender") .. lp(X) .. lp(Y)
        .. lp(bytesOf(Z, S.ELEMENT)) .. lp(bytesOf(self.w, 32))
    local K = S.sha256(tt)
    self.key = S.hmac(K, "encrypt")
    self.confirm_A = S.hmac(S.hmac(K, "confirm receiver"), K)
    self.confirm_B = S.hmac(S.hmac(K, "confirm sender"), K)
    self.x = nil -- (gc frees it)
    return true
end

--- What this side sends to prove it has the keys, and the check of the other's.
function Session:confirmation() return S.hex(self.role == "A" and self.confirm_A or self.confirm_B) end
function Session:checkConfirmation(hex)
    return S.equal(S.unhex(hex or "") or "", self.role == "A" and self.confirm_B or self.confirm_A)
end

---------------------------------------------------------------- sealing

--- AES-256-GCM: hex(nonce .. ciphertext .. tag). `label` says which way it goes.
function S.seal(key, plain, label)
    local L = lib()
    local nonce = S.random(12)
    local ctx = L.EVP_CIPHER_CTX_new()
    local out = ffi.new("unsigned char[?]", #plain + 16)
    local n, fin = ffi.new("int[1]"), ffi.new("int[1]")
    local tag = ffi.new("unsigned char[16]")
    local ok = L.EVP_EncryptInit_ex(ctx, L.EVP_aes_256_gcm(), nil, nil, nil) == 1
        and L.EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, nil) == 1
        and L.EVP_EncryptInit_ex(ctx, nil, nil, key, nonce) == 1
        and L.EVP_EncryptUpdate(ctx, nil, n, label, #label) == 1
        and L.EVP_EncryptUpdate(ctx, out, n, plain, #plain) == 1
    local len = ok and n[0] or 0
    ok = ok and L.EVP_EncryptFinal_ex(ctx, out + len, fin) == 1
        and L.EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag) == 1
    L.EVP_CIPHER_CTX_free(ctx)
    if not ok then error("encryption failed") end
    return S.hex(nonce .. ffi.string(out, len + fin[0]) .. ffi.string(tag, 16))
end

--- The plain text, or nil if it was changed (or isn't for `label`/`key`).
function S.open(key, hex, label)
    local L = lib()
    local raw = S.unhex(hex or "")
    if not raw or #raw < 28 then return nil end
    local nonce, body, tag = raw:sub(1, 12), raw:sub(13, -17), raw:sub(-16)
    local ctx = L.EVP_CIPHER_CTX_new()
    local out = ffi.new("unsigned char[?]", #body + 16)
    local n, fin = ffi.new("int[1]"), ffi.new("int[1]")
    local tagbuf = ffi.new("unsigned char[16]")
    ffi.copy(tagbuf, tag, 16)
    local ok = L.EVP_DecryptInit_ex(ctx, L.EVP_aes_256_gcm(), nil, nil, nil) == 1
        and L.EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, nil) == 1
        and L.EVP_DecryptInit_ex(ctx, nil, nil, key, nonce) == 1
        and L.EVP_DecryptUpdate(ctx, nil, n, label, #label) == 1
        and L.EVP_DecryptUpdate(ctx, out, n, body, #body) == 1
    local len = ok and n[0] or 0
    ok = ok and L.EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16, tagbuf) == 1
        and L.EVP_DecryptFinal_ex(ctx, out + len, fin) == 1
    L.EVP_CIPHER_CTX_free(ctx)
    if not ok then return nil end
    return ffi.string(out, len + fin[0])
end

--- A 6-digit PIN (uniform: random bytes, rejecting the uneven top).
function S.pin()
    while true do
        local b = S.random(4)
        local n = ((b:byte(1) * 256 + b:byte(2)) * 256 + b:byte(3)) * 256 + b:byte(4)
        if n < 4294000000 then return string.format("%06d", n % 1000000) end
    end
end

--- Is the crypto library there?
function S.available() return (pcall(lib)) end

return S
