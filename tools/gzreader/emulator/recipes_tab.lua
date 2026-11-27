-- The Recipes tab (Mealie), with demo/mock_mealie.py on 127.0.0.1:18096:
-- connected with an API token, the tab turned on in the tab bar, the list, a
-- category, a recipe's page, and Settings → Accounts and services → Recipes.
--   python3 -I demo/mock_mealie.py 18096 &
--   GZ_EMU_TREE=<tree>/koreader ./run.sh recipes_tab.lua <out>
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function tab() return require("gzreader_recipes").instance end
-- (closes what's open above the tab: a touch model has no Back key)
local function closeTop()
    local UIManager = require("ui/uimanager")
    local stack = UIManager._window_stack
    local top = stack[#stack]
    if top and tab() and top.widget ~= tab().menu then UIManager:close(top.widget) end
end
local function rowsText()
    local t = {}
    for _i, r in ipairs(tab() and tab().menu.item_table or {}) do t[#t + 1] = tostring(r.text) .. (r.mandatory and (" = " .. r.mandatory) or "") end
    return table.concat(t, " | ")
end
-- past the setup guide, to Home
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 4 })
add({ fn = function(E)
    local ok, err = require("gzreader_mealie").connect(plugin(), "127.0.0.1:18096", "mealie-test-token")
    E.say("connect ->", tostring(ok), tostring(err))
    E.say("tab on ->", tostring(require("gzreader_recipes").setTabShown(true)))
end, after = 8 })
add({ shot = "recipes-0-tabbar" })
add({ fn = function() require("gzreader_recipes").show(plugin()) end, after = 12 })
add({ shot = "recipes-1-list" })
add({ fn = function(E)
    E.say("rows:", rowsText():sub(1, 400))
    tab():askCategory()
end, after = 8 })
add({ shot = "recipes-2-categories" })
add({ fn = closeTop, after = 4 })
add({ fn = function() tab():setFilter({ category = { id = "baking", name = "Baking" } }) end, after = 8 })
add({ shot = "recipes-3-baking" })
add({ fn = function(E)
    E.say("baking:", rowsText())
    for _i, r in ipairs(tab().menu.item_table) do if r.gz_recipe == "apple-pie" then r.callback() end end
end, after = 10 })
add({ shot = "recipes-4-recipe" })
add({ fn = closeTop, after = 4 })
add({ fn = function(E)
    E.say("kept on the Kindle:", tostring(require("gzreader_mealie").loadRecipe("apple-pie") ~= nil))
    tab():askSearch()
end, after = 6 })
add({ shot = "recipes-5-search" })
add({ fn = closeTop, after = 4 })
add({ fn = function()
    local UIManager = require("ui/uimanager")
    if tab() then UIManager:close(tab().menu) end
    require("modules/settings/zen_settings_page").closeActive()
    require("modules/settings/zen_settings_page").show(require("gzreader_tabs").zen(), { path = {
        { key = "text", value = "Accounts and services" }, { key = "text", value = "Recipes" } } })
end, after = 10 })
add({ shot = "recipes-6-settings" })
return s
