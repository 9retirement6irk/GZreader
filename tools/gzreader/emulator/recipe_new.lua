-- A new recipe from the Recipes tab, with demo/mock_mealie.py on
-- 127.0.0.1:18096: New card on the recipe box's front, the two ways, the
-- three boxes to type in, and the recipe once Mealie has it.
--   python3 -I demo/mock_mealie.py 18096 &
--   GZ_EMU_TREE=<tree>/koreader ./run.sh recipe_new.lua <out>
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local UIManager = require("ui/uimanager")
add({ fn = function()
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 4 })
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function Recipes() return require("gzreader_recipes") end
local function tab() return Recipes().instance end
local function closeTop()
    local stack = UIManager._window_stack
    local top = stack[#stack]
    if top and tab() and top.widget ~= tab().menu then UIManager:close(top.widget) end
end
add({ fn = function(E)
    local ok, err = require("gzreader_mealie").connect(plugin(), "127.0.0.1:18096", "mealie-test-token")
    E.say("connect ->", tostring(ok), tostring(err))
    require("common/gz_view").set("bookshelf")
    Recipes().show(plugin())
end, after = 12 })
add({ shot = "new-1-box" })
add({ fn = function(E)
    local t = {}
    for _i, pl in ipairs(tab().menu._gz_box and tab().menu._gz_box.places or {}) do
        if pl.kind == "order" or pl.kind == "new" or pl.kind == "more" then t[#t + 1] = pl.kind .. "=" .. pl.label .. (pl.letter and (":" .. pl.letter) or "") end
    end
    E.say("box: tags:", table.concat(t, " | "))
    tab():newRecipe()
end, after = 6 })
add({ shot = "new-2-ways" })
add({ fn = function() closeTop(); tab():writeRecipe({ name = "Plum cake" }, 1) end, after = 8 })
add({ shot = "new-3-name" })
add({ fn = function()
    closeTop()
    tab():writeRecipe({ name = "Plum cake", ingredients = "Batter:\n200 g flour\n3 eggs\nTop:\n10 plums, halved" }, 2)
end, after = 8 })
add({ shot = "new-4-ingredients" })
add({ fn = function() closeTop(); tab():writeRecipe({ name = "Plum cake" }, 2) end, after = 8 })
add({ shot = "new-5-ingredients-empty" })
add({ fn = function(E)
    closeTop()
    tab():saveRecipe({ name = "Plum cake", ingredients = "Batter:\n200 g flour\n3 eggs\nTop:\n10 plums, halved",
        steps = "Whisk the batter.\nLay the plums on top and bake 40 minutes." })
end, after = 14 })
add({ shot = "new-6-saved" })
add({ fn = function(E)
    local top = UIManager._window_stack[#UIManager._window_stack].widget
    E.say("saved: the recipe is open:", tostring(top.recipe and top.recipe.name), "kept:", tostring(require("gzreader_mealie").loadRecipe("plum-cake") ~= nil))
    closeTop()
    tab():importRecipe("https://recipes.example.com/leek-soup")
end, after = 8 })
add({ shot = "new-7-web-address" })
add({ fn = closeTop, after = 2 })
return s
