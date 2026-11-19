-- gzreader_saving.lua's drafts: kept, read back, offered only when they
-- differ, let go when old, and written whole (beside, then moved over).
--   luajit saving_test.lua <plugin dir> <koreader base (common/)> <work dir>
local PLUGIN, KOROOT, WORK = arg[1], arg[2], arg[3] or "/tmp/gz-saving-test"
package.path = PLUGIN .. "/?.lua;" .. KOROOT .. "/common/?.lua;" .. package.path
-- (the plugin's JSON: LuaJSON stood in for by dkjson, as json_test.lua does)
local dkjson = require("dkjson")
package.preload["json"] = function()
    return { decode = function(s) local v, _, err = dkjson.decode(s); if err then error(err) end; return v end,
        encode = function(v) return dkjson.encode(v) end }
end
local Saving = require("gzreader_saving")
os.execute("rm -rf '" .. WORK .. "' && mkdir -p '" .. WORK .. "'")
Saving._dir = WORK .. "/gzreader-drafts"
local pass, fail = 0, 0
local function check(ok, what) if ok then pass = pass + 1 else fail = fail + 1; print("FAIL " .. what) end end

check(Saving.keyOf(nil) == "new" and Saving.keyOf({ name = "memos/abc" }) == "memos/abc", "a draft's key: the note's name, or new")
check(Saving.draftPath("memos/abc"):match("/memos_abc%.json$") and Saving.draftPath("../x"):match("/___x%.json$"),
    "its file: the key with anything but letters, digits, - and _ made safe (no way out of the folder)")
check(Saving.readDraft("memos/abc") == nil, "no draft yet: none")
check(Saving.writeDraft("memos/abc", { text = "Milk\n- [ ] eggs", visibility = "PROTECTED" }, 1000), "a draft written")
local d = Saving.readDraft("memos/abc", 1000 + 60)
check(d and d.text == "Milk\n- [ ] eggs" and d.visibility == "PROTECTED" and d.at == 1000, "…read back: the words, who can see it, when")
check(io.open(Saving.draftPath("memos/abc") .. ".tmp") == nil, "…written beside it then moved over (nothing left half-written)")
check(Saving.differs(d, "Milk") and not Saving.differs(d, "Milk\n- [ ] eggs\n") and not Saving.differs({ text = "  \n" }, "x")
    and not Saving.differs(nil, "x"), "offered only when it has words and they aren't the note's (trailing space aside)")
check(Saving.readDraft("memos/abc", 1000 + 15 * 86400) == nil and io.open(Saving.draftPath("memos/abc")) == nil,
    "a draft older than two weeks is let go")
Saving.writeDraft("new", { text = "a new one" }, 5)
Saving.dropDraft("new")
check(Saving.readDraft("new", 6) == nil, "dropped: gone")
local f = io.open(Saving.draftPath("broken"), "w"); f:write("{not json"); f:close()
check(Saving.readDraft("broken") == nil, "an unreadable draft: none (no error)")

print(string.format("saving: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
