-- The AI connection (gzreader_ai.lua): Settings → Accounts and services, the AI
-- page, and Notes → Handwriting to text with a key set (an example key; nothing is asked).
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader ./run.sh ai_connection.lua <out>
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
add({ fn = function()
    local UIM = require("ui/uimanager")
    for i = #UIM._window_stack, 1, -1 do
        local w = UIM._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM:close(w) end
    end
end, after = 6 })
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function zen() return require("apps/filemanager/filemanager").instance.zenos end
local function open(path)
    local Page = require("modules/settings/zen_settings_page")
    pcall(Page.closeActive)
    local p = {}
    for _i, t in ipairs(path) do p[#p + 1] = { key = "text", value = t } end
    Page.show(zen(), { path = p })
end
add({ fn = function() open({ "Accounts and services" }) end, after = 8 })
add({ shot = "ai-1-accounts" })
add({ fn = function(E)
    local AI = require("gzreader_ai")
    local st = AI.settings(plugin())
    st.claude.key = "sk-ant-example-not-a-key"
    E.say("provider: " .. tostring(AI.provider(plugin())))
    open({ "Accounts and services", "AI" })
end, after = 8 })
add({ shot = "ai-2-page" })
add({ fn = function()
    require("gzreader_handwriting").settings(plugin()).engine = "ai"
    open({ "Accounts and services", "Notes" })
end, after = 8 })
add({ shot = "ai-3-notes" })
add({ fn = function(E)
    local AI = require("gzreader_ai")
    AI.clear(plugin())
    require("gzreader_handwriting").settings(plugin()).engine = "kindle"
    E.say("cleared: " .. tostring(AI.provider(plugin())))
end, after = 2 })
return s
