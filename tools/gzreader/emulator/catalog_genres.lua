-- The Catalog's Genres (demo/demo_grimmory.py on 127.0.0.1:18080, a library made
-- by demo/make_library.py with audio.json; a touch model, e.g. GZ_EMU_MODEL=pw3):
-- signed in, the Books page (Genres on the last shelf, where the server's card was),
-- its Genres list and one genre's books; then the Audiobooks page (Genres in place of
-- the account card), its Genres and one genre. Prints each list.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function UIM() return require("ui/uimanager") end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function browser() return require("gzreader_browser").current end
local function listTop(E, what)
    local w = top()
    local out = {}
    for i, it in ipairs(w and w.item_table or {}) do
        if i > 14 then break end
        out[#out + 1] = tostring(it.text or (it.text_func and it.text_func()) or "?")
    end
    E.say(what, tostring(w and (w.name or w.title)), table.concat(out, " | "))
end
local function closeGuides()
    local st = UIM()._window_stack
    for i = #st, 1, -1 do
        local w = st[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end
local function open(pat)
    return function(E)
        for _i, it in ipairs(top() and top().item_table or {}) do
            local t = tostring(it.text or (it.text_func and it.text_func()) or "")
            if t:match(pat) and it.callback then E.say("open:", t); it.callback(); return end
        end
        E.say("not found:", pat)
    end
end

add({ fn = closeGuides, after = 6 })
add({ fn = function(E) E.say("login", tostring(plugin().api:login("http://127.0.0.1:18080", "reader", "demo"))) end, after = 4 })
add({ fn = function() plugin():onShowGrimmoryLibrary() end, after = 16 })
add({ fn = function(E) listTop(E, "books page") end })
add({ shot = "genres-1-books-page" })
add({ fn = function() browser():openGenres() end, after = 14 })
add({ fn = function(E) listTop(E, "genres") end })
add({ shot = "genres-2-list" })
add({ fn = open("^Mystery"), after = 10 })
add({ fn = function(E) listTop(E, "mystery") end })
add({ shot = "genres-3-mystery" })
add({ fn = function() browser():openSection("audiobooks") end, after = 14 })
add({ fn = function(E) listTop(E, "audiobooks page") end })
add({ shot = "genres-4-audiobooks-page" })
add({ fn = function() browser():openAudioGenres() end, after = 12 })
add({ fn = function(E) listTop(E, "audiobook genres") end })
add({ shot = "genres-5-audio-list" })
return s
