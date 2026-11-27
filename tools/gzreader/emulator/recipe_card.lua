-- A recipe in the Bookshelf view (gzreader_recipecard.lua): the index card,
-- with demo/mock_mealie.py on 127.0.0.1:18096. Its first card, an ingredient
-- crossed off, the card turned, the same card on a colour screen, and the
-- page of text again in another view.
--   python3 -I demo/mock_mealie.py 18096 &
--   GZ_EMU_TREE=<tree>/koreader ./run.sh recipe_card.lua <out>
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 4 })
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local Mealie = function() return require("gzreader_mealie") end
local card
add({ fn = function(E)
    local ok, err = Mealie().connect(plugin(), "127.0.0.1:18096", "mealie-test-token")
    E.say("connect ->", tostring(ok), tostring(err))
    require("common/gz_view").set("bookshelf")
    local r = Mealie():new(plugin().store.mealie):fetchRecipe("apple-pie")
    card = require("gzreader_recipes").showRecipe(r)
end, after = 10 })
add({ shot = "card-1-first" })
add({ fn = function(E)
    E.say("card: is a card:", tostring(card.cards ~= nil), "cards", tostring(card.cards and #card.cards), "lines", tostring(card.rows and #card.rows))
    card:cross(2)
    card:cross(4)
end, after = 6 })
add({ shot = "card-2-crossed" })
add({ fn = function() card:turn(1) end, after = 6 })
add({ shot = "card-3-turned" })
add({ fn = function(E)
    E.say("card: page", tostring(card.page), "of", tostring(#card.cards))
    card:turn(-1)
    local Blitbuffer = require("ffi/blitbuffer")
    local Screen = require("device").screen
    local was = Screen.isColorEnabled
    Screen.isColorEnabled = function() return true end
    local c2 = require("gzreader_recipecard").Page:new{ recipe = card.recipe }
    local out = Blitbuffer.new(Screen:getWidth(), Screen:getHeight(), Blitbuffer.TYPE_BBRGB32)
    c2:paintTo(out, 0, 0)
    local n = 0
    for y = 0, out:getHeight() - 1, 3 do
        for x = 0, out:getWidth() - 1, 3 do
            local c = out:getPixel(x, y):getColorRGB32()
            if math.abs(c.r - c.g) > 12 or math.abs(c.g - c.b) > 12 then n = n + 1 end
        end
    end
    out:writePNG(E.out .. "/card-4-colour.png")
    out:free()
    Screen.isColorEnabled = was
    E.say("colour screen: coloured pixels sampled:", tostring(n))
    card:onGzClose()
end, after = 6 })
add({ fn = function(E)
    require("common/gz_view").set("mosaic_image")
    local v = require("gzreader_recipes").showRecipe(card.recipe)
    E.say("another view: the page of text:", tostring(v.cards == nil))
end, after = 8 })
add({ shot = "card-5-text-in-another-view" })
add({ fn = function() require("common/gz_view").set("bookshelf") end, after = 2 })
return s
