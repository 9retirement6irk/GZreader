-- The Recipes tab in the Bookshelf view (gzreader_recipebox.lua): the recipe
-- box, with demo/mock_mealie.py on 127.0.0.1:18096. Its dividers, a category
-- chosen from one, the next page of cards, a search, the same box on a colour
-- screen, and the list again in another view.
--   python3 -I demo/mock_mealie.py 18096 &
--   GZ_EMU_TREE=<tree>/koreader ./run.sh recipe_box.lua <out>
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
local function Recipes() return require("gzreader_recipes") end
local function tab() return Recipes().instance end
local function box() return tab() and tab().menu and tab().menu._gz_box end
local function places()
    local t = {}
    for _i, pl in ipairs(box() and box().places or {}) do
        t[#t + 1] = pl.kind .. (pl.letter and (":" .. pl.letter) or "") .. (pl.kind == "tab" and ("=" .. pl.label .. (pl.chosen and "*" or "")) or "")
    end
    return table.concat(t, " ")
end
local function tap(kind, label)
    for _i, pl in ipairs(box() and box().places or {}) do
        if pl.kind == kind and (not label or pl.label == label) and pl.hot then return pl.hot:onTapShop() end
    end
end
add({ fn = function(E)
    local ok, err = require("gzreader_mealie").connect(plugin(), "127.0.0.1:18096", "mealie-test-token")
    E.say("connect ->", tostring(ok), tostring(err))
    Recipes().setTabShown(true)
    require("common/gz_view").set("bookshelf")
end, after = 8 })
add({ fn = function() Recipes().show(plugin()) end, after = 12 })
add({ shot = "box-1-all" })
add({ fn = function(E)
    E.say("box:", box() and "yes" or "NO", "pages", tostring(tab().menu.page_num), "places", places())
    tap("tab", "Baking")
end, after = 10 })
add({ shot = "box-2-baking" })
add({ fn = function(E)
    E.say("baking:", places())
    tap("tab", "All")
end, after = 10 })
add({ fn = function() tab().menu:onNextPage() end, after = 6 })
add({ shot = "box-3-next-page" })
add({ fn = function(E)
    E.say("page", tostring(tab().menu.page), "of", tostring(tab().menu.page_num))
    tab():setFilter({ search = "banana" })
end, after = 10 })
add({ shot = "box-4-search" })
add({ fn = function(E)
    E.say("search:", places())
    tab():setFilter({ search = false })
end, after = 10 })
-- a colour screen (Colorsoft): the same page drawn into a colour canvas
add({ fn = function(E)
    local Blitbuffer = require("ffi/blitbuffer")
    local Screen = require("device").screen
    local was = Screen.isColorEnabled
    Screen.isColorEnabled = function() return true end
    local m = tab().menu
    m:updateItems()
    local out = Blitbuffer.new(Screen:getWidth(), Screen:getHeight(), Blitbuffer.TYPE_BBRGB32)
    out:fill(Blitbuffer.COLOR_WHITE)
    m:paintTo(out, 0, 0)
    local n = 0
    for y = 0, out:getHeight() - 1, 3 do
        for x = 0, out:getWidth() - 1, 3 do
            local c = out:getPixel(x, y):getColorRGB32()
            if math.abs(c.r - c.g) > 12 or math.abs(c.g - c.b) > 12 then n = n + 1 end
        end
    end
    out:writePNG(E.out .. "/box-5-colour.png")
    out:free()
    Screen.isColorEnabled = was
    m:updateItems()
    E.say("colour screen: coloured pixels sampled:", tostring(n))
end, after = 6 })
add({ fn = function(E)
    require("common/gz_view").set("mosaic_image")
    local UIManager = require("ui/uimanager")
    UIManager:close(tab().menu)
    Recipes().show(plugin())
end, after = 10 })
add({ shot = "box-6-list-in-another-view" })
add({ fn = function(E)
    E.say("another view: the list:", tostring(box() == nil))
    require("common/gz_view").set("bookshelf")
end, after = 2 })
return s
