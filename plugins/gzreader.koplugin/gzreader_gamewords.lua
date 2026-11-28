--[[--
The game board's own themes (gzreader_gameboard.lua): words for the seasons
and for categories, each with a short crossword clue. Plain A–Z words of 3
to 10 letters (the word search takes those of 8 or fewer, the scramble 4 to
9). English, as the puzzles' own list is.

THEMES = { { id, title, season = true (a season's), months = { … }, words = {
{ "WORD", "clue" }, … } }, … }.
]]

local _ = require("gettext")

local W = {}

W.THEMES = {
    ---------------------------------------------------------------- seasons
    { id = "winter", title = _("Winter"), season = true, months = { 1, 2 }, words = {
        { "SNOWMAN", "Built in the yard with a carrot nose" }, { "MITTEN", "A glove without fingers" },
        { "ICICLE", "A spike of frozen drips under the eaves" }, { "SLEDGE", "Ride it down a snowy hill" },
        { "FROST", "White crystals on a cold morning" }, { "BLIZZARD", "A storm of wind and snow" },
        { "SCARF", "Wound round the neck against the cold" }, { "COCOA", "A hot chocolate drink" },
        { "FIRESIDE", "Where to sit warm on a winter night" }, { "SKATES", "Boots with blades for the ice" },
        { "IGLOO", "A house of snow blocks" }, { "FLURRY", "A light, brief fall of snow" },
        { "PENGUIN", "A bird in a dinner suit that can't fly" }, { "THAW", "When the ice begins to melt" },
    } },
    { id = "spring", title = _("Spring"), season = true, months = { 3, 4, 5 }, words = {
        { "BLOSSOM", "Flowers on a fruit tree" }, { "TULIP", "A cup-shaped flower from a bulb" },
        { "DAFFODIL", "A yellow trumpet of a flower" }, { "LAMB", "A young sheep" },
        { "RAINBOW", "An arc of colours after rain" }, { "PUDDLE", "Jump in it in your boots" },
        { "NEST", "Where birds lay their eggs" }, { "SEEDLING", "A young plant just sprouted" },
        { "BUTTERFLY", "It was a caterpillar once" }, { "BREEZE", "A gentle wind" },
        { "MEADOW", "A field of grass and wild flowers" }, { "SHOWER", "A short fall of rain" },
        { "TADPOLE", "A frog when it's young" }, { "BUD", "A flower before it opens" },
    } },
    { id = "summer", title = _("Summer"), season = true, months = { 6, 7, 8 }, words = {
        { "BEACH", "Sand by the sea" }, { "PICNIC", "A meal on a blanket outdoors" },
        { "SUNHAT", "Keeps the sun off your head" }, { "SANDAL", "An open shoe for hot days" },
        { "LEMONADE", "A cool drink of lemons and sugar" }, { "SEASHELL", "Found on the shore; hold it to your ear" },
        { "HOLIDAY", "Time away from work or school" }, { "BARBECUE", "Cooking over coals outdoors" },
        { "SUNSET", "When the sun goes down" }, { "CAMPING", "Sleeping in a tent" },
        { "FIREFLY", "An insect that glows at dusk" }, { "MELON", "A big, juicy fruit" },
        { "SURF", "Ride the waves on a board" }, { "HAMMOCK", "A swinging bed hung between trees" },
    } },
    { id = "autumn", title = _("Autumn"), season = true, months = { 9 }, words = {
        { "ACORN", "An oak tree's nut" }, { "HARVEST", "Gathering in the crops" },
        { "MAPLE", "A tree whose leaves turn red" }, { "SWEATER", "A warm knitted top" },
        { "CONKER", "A horse chestnut on a string" }, { "ORCHARD", "A field of fruit trees" },
        { "SQUIRREL", "It buries nuts for later" }, { "RAKE", "Gathers up fallen leaves" },
        { "CIDER", "A drink made from apples" }, { "FOGGY", "Misty and hard to see through" },
        { "BONFIRE", "A big fire outdoors" }, { "CHESTNUT", "Roasted on an open fire" },
        { "LEAVES", "They turn gold and fall" }, { "TWILIGHT", "The dim light after sunset" },
    } },
    { id = "halloween", title = _("Halloween"), season = true, months = { 10 }, words = {
        { "PUMPKIN", "Carved into a lantern" }, { "GHOST", "A spirit in a white sheet" },
        { "WITCH", "She flies on a broomstick" }, { "COSTUME", "What you dress up in" },
        { "CANDY", "Sweets for trick-or-treaters" }, { "SPIDER", "Eight legs and a web" },
        { "CAULDRON", "A witch's big pot" }, { "BROOM", "Sweeps the floor, or flies" },
        { "MUMMY", "Wrapped in bandages in a tomb" }, { "LANTERN", "A light to carry" },
        { "SKELETON", "All the bones of a body" }, { "OWL", "It hoots at night" },
        { "SPOOKY", "Eerie and a little frightening" }, { "BAT", "It hangs upside down to sleep" },
    } },
    { id = "harvest", title = _("Harvest and Thanksgiving"), season = true, months = { 11 }, words = {
        { "TURKEY", "The big bird at the feast" }, { "GRAVY", "Sauce made from the roast's juices" },
        { "PIE", "Pastry with a filling" }, { "CORN", "Yellow kernels on a cob" },
        { "GRATEFUL", "Thankful" }, { "STUFFING", "Bread and herbs cooked in the bird" },
        { "FEAST", "A grand meal" }, { "CRANBERRY", "A tart red berry, made into sauce" },
        { "FAMILY", "Who comes home for the holiday" }, { "GOURD", "A hard-skinned fruit of the squash family" },
        { "PILGRIM", "A traveller on a long journey" }, { "POTATO", "Mashed, roasted or baked" },
        { "WREATH", "A ring of leaves on the door" }, { "HAYRIDE", "A trip on a wagon of straw" },
    } },
    { id = "holidays", title = _("Winter holidays"), season = true, months = { 12 }, words = {
        { "SNOWFLAKE", "No two are the same" }, { "REINDEER", "They pull the sleigh" },
        { "CANDLE", "A wax light with a wick" }, { "PRESENT", "A gift, wrapped" },
        { "TINSEL", "Glittering strands on the tree" }, { "CAROL", "A song sung at the door" },
        { "STOCKING", "Hung up to be filled" }, { "SLEIGH", "A sledge pulled by animals" },
        { "COOKIE", "Left out with a glass of milk" }, { "LIGHTS", "Strung along the eaves" },
        { "ORNAMENT", "Hung on the branches" }, { "GINGER", "The spice in the biscuit men" },
        { "MISTLETOE", "Kiss beneath it" }, { "MITTENS", "Gloves without fingers" },
    } },
    ---------------------------------------------------------------- categories
    { id = "animals", title = _("Animals"), words = {
        { "GIRAFFE", "The tallest animal" }, { "ELEPHANT", "It never forgets, they say" },
        { "PANDA", "A black and white bear that eats bamboo" }, { "TIGER", "A big striped cat" },
        { "KANGAROO", "It carries its young in a pouch" }, { "OTTER", "It floats on its back holding hands" },
        { "BADGER", "A striped digger of setts" }, { "HEDGEHOG", "It rolls into a prickly ball" },
        { "ZEBRA", "A striped horse of Africa" }, { "MONKEY", "It swings through the trees" },
        { "CAMEL", "It crosses the desert with a hump" }, { "BEAVER", "It builds dams" },
        { "RABBIT", "Long ears and a fluffy tail" }, { "WOLF", "It howls at the moon" },
    } },
    { id = "food", title = _("Food and cooking"), words = {
        { "PANCAKE", "Flipped in the pan" }, { "NOODLE", "A long strip of pasta" },
        { "CHEESE", "Made from milk; cheddar is one" }, { "BREAD", "Baked from flour and yeast" },
        { "OMELETTE", "Eggs beaten and folded in the pan" }, { "PIZZA", "A flat bread with toppings" },
        { "SOUP", "Eaten with a spoon from a bowl" }, { "MUFFIN", "A small cake baked in a cup" },
        { "CURRY", "A spiced dish, often with rice" }, { "WAFFLE", "A batter cake with a grid" },
        { "SALAD", "Leaves and vegetables, raw" }, { "BUTTER", "Spread on toast" },
        { "GARLIC", "A bulb that keeps vampires away" }, { "HONEY", "Made by bees" },
    } },
    { id = "space", title = _("Space"), words = {
        { "PLANET", "Earth is one" }, { "COMET", "An icy visitor with a tail" },
        { "GALAXY", "The Milky Way is one" }, { "ROCKET", "It launches to orbit" },
        { "ORBIT", "The path round a planet or star" }, { "ASTEROID", "A rocky body; many lie between Mars and Jupiter" },
        { "SATURN", "The planet with the famous rings" }, { "NEBULA", "A cloud of gas and dust in space" },
        { "ECLIPSE", "When the Moon hides the Sun" }, { "METEOR", "A shooting star" },
        { "LUNAR", "Of the Moon" }, { "ASTRONAUT", "A traveller in space" },
        { "CRATER", "A hollow left by an impact" }, { "TELESCOPE", "It brings the stars closer" },
    } },
    { id = "ocean", title = _("The ocean"), words = {
        { "DOLPHIN", "A clever, playful sea mammal" }, { "CORAL", "Reefs are built of it" },
        { "WHALE", "The largest animal there has been" }, { "OCTOPUS", "Eight arms and three hearts" },
        { "SEAWEED", "Plants that grow in the sea" }, { "TIDE", "The sea's rise and fall" },
        { "SHARK", "A fish with rows of teeth" }, { "STARFISH", "A star-shaped creature of the shore" },
        { "LIGHTHOUSE", "Its beam warns ships of rocks" }, { "OYSTER", "It may hold a pearl" },
        { "ANCHOR", "It holds a ship in place" }, { "JELLYFISH", "It drifts and stings" },
        { "CRAB", "It walks sideways" }, { "WAVE", "It breaks on the shore" },
    } },
    { id = "weather", title = _("Weather"), words = {
        { "THUNDER", "The rumble after lightning" }, { "RAINBOW", "Colours across the sky after rain" },
        { "DRIZZLE", "Light, fine rain" }, { "TORNADO", "A spinning funnel of wind" },
        { "SUNSHINE", "Light from a clear sky" }, { "HAIL", "Balls of ice from the sky" },
        { "CLOUDY", "Grey overhead" }, { "BREEZE", "A gentle wind" },
        { "FORECAST", "What the weather will do" }, { "MONSOON", "A season of heavy rain" },
        { "FOG", "A cloud at ground level" }, { "HUMID", "Damp and close" },
        { "SLEET", "Rain and snow together" }, { "GALE", "A very strong wind" },
    } },
    { id = "garden", title = _("The garden"), words = {
        { "TROWEL", "A small spade for planting" }, { "COMPOST", "Old peelings turned to soil" },
        { "ROSE", "A flower with thorns" }, { "HEDGE", "A wall of bushes" },
        { "SHED", "Where the tools are kept" }, { "WORM", "It turns the soil" },
        { "DAISY", "A small white flower with a yellow eye" }, { "SPADE", "For digging" },
        { "SUNFLOWER", "It turns to face the sun" }, { "LAVENDER", "A purple, scented herb" },
        { "BEETLE", "An insect with hard wing cases" }, { "POND", "Frogs live in it" },
        { "BIRDBATH", "A bowl of water for birds" }, { "WEEDS", "Plants where you don't want them" },
    } },
    { id = "music", title = _("Music"), words = {
        { "PIANO", "Black and white keys" }, { "GUITAR", "Strummed, six strings" },
        { "VIOLIN", "Played with a bow under the chin" }, { "DRUMS", "Beaten to keep the rhythm" },
        { "MELODY", "A tune" }, { "CHORUS", "The part that's sung again" },
        { "TRUMPET", "A brass horn with three valves" }, { "RHYTHM", "The beat of a piece" },
        { "ORCHESTRA", "A large group of players" }, { "HARMONY", "Notes sung together that sound well" },
        { "FLUTE", "Played sideways, by blowing across it" }, { "LYRICS", "The words of a song" },
        { "TEMPO", "How fast the music goes" }, { "CELLO", "A large string instrument played seated" },
    } },
    { id = "sports", title = _("Sports and games"), words = {
        { "TENNIS", "Played with rackets over a net" }, { "SOCCER", "Football, to some" },
        { "CHESS", "A game of kings and pawns" }, { "GOAL", "Score one" },
        { "MARATHON", "A run of about 26 miles" }, { "REFEREE", "Blows the whistle" },
        { "CRICKET", "A game with bats, wickets and a ball" }, { "SKIING", "Down the slopes on two boards" },
        { "HOCKEY", "Played with sticks, on ice or grass" }, { "MEDAL", "Won for first, second or third" },
        { "GOLF", "A ball, a club and eighteen holes" }, { "CYCLING", "Racing on two wheels" },
        { "ROWING", "Oars on the water" }, { "TROPHY", "A cup for the winner" },
    } },
    { id = "travel", title = _("Travel"), words = {
        { "PASSPORT", "Shown at the border" }, { "SUITCASE", "Packed for a trip" },
        { "TICKET", "Your seat on the train" }, { "AIRPORT", "Where planes take off" },
        { "MAP", "Shows you the way" }, { "COMPASS", "Its needle points north" },
        { "JOURNEY", "A trip from one place to another" }, { "HOTEL", "Rooms for travellers" },
        { "POSTCARD", "Sent home with a picture" }, { "VOYAGE", "A long journey by sea" },
        { "RAILWAY", "Tracks for trains" }, { "CAMERA", "For holiday pictures" },
        { "LUGGAGE", "Bags for a journey" }, { "SOUVENIR", "Something brought back to remember" },
    } },
    { id = "words", title = _("Books and reading"), words = {
        { "NOVEL", "A long story in a book" }, { "CHAPTER", "A part of a book" },
        { "AUTHOR", "Who wrote it" }, { "LIBRARY", "Where to borrow books" },
        { "POETRY", "Verse" }, { "BOOKMARK", "Keeps your place" },
        { "HERO", "The story's brave one" }, { "VILLAIN", "The story's bad one" },
        { "MYSTERY", "A whodunnit" }, { "SEQUEL", "The next book in the story" },
        { "FABLE", "A short tale with a moral" }, { "PLOT", "What happens in the story" },
        { "LEGEND", "An old story, perhaps true" }, { "SHELF", "Where the books stand" },
    } },
}

--- A theme by its id.
function W.byId(id)
    for _i, t in ipairs(W.THEMES) do if t.id == id then return t end end
end

--- The season's theme for a month (1–12).
function W.season(month)
    for _i, t in ipairs(W.THEMES) do
        if t.season then
            for _j, m in ipairs(t.months) do if m == month then return t end end
        end
    end
end

--- The themes that aren't seasons.
function W.categories()
    local out = {}
    for _i, t in ipairs(W.THEMES) do if not t.season then out[#out + 1] = t end end
    return out
end

--- A theme's words as entries: { { word, clue } }.
function W.entries(theme)
    local out, has = {}, {}
    for _i, pair in ipairs(theme and theme.words or {}) do
        if not has[pair[1]] then
            has[pair[1]] = true
            out[#out + 1] = { word = pair[1], clue = pair[2] }
        end
    end
    return out
end

return W
