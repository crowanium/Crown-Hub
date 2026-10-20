--[[
	Crown Hub — full UI port (inline)
	local CrownUI holds the library. No external links required.
	Toggle: RightShift (configurable in Settings).
]]

local CrownUI
do
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

--// Environment ----------------------------------------------------------------

-- Executor APIs are looked up through the environment table so the script runs
-- untouched in Studio (where they simply don't exist) without unknown-global lints.
local globals = _G
if type(getfenv) == "function" then
    local ok, value = pcall(getfenv)
    if ok and type(value) == "table" then globals = value end
end
local ENV = _G
do
    local candidate = globals.getgenv or _G.getgenv
    if type(candidate) == "function" then
        local ok, value = pcall(candidate)
        if ok and type(value) == "table" then ENV = value end
    end
end
local function envFunction(name)
    for _, source in ipairs({globals, ENV, _G}) do
        local ok, value = pcall(function() return source[name] end)
        if ok and type(value) == "function" then return value end
    end
end
local function namespaceFunction(namespace, name)
    for _, source in ipairs({globals, ENV, _G}) do
        local ok, value = pcall(function()
            local group = source[namespace]
            return group and group[name]
        end)
        if ok and type(value) == "function" then return value end
    end
end
local function requestFunction()
    return envFunction("request") or envFunction("http_request") or envFunction("httprequest")
        or namespaceFunction("http", "request") or namespaceFunction("syn", "request")
end
if type(ENV.CROWN_UNLOAD) == "function" then
	pcall(ENV.CROWN_UNLOAD)
end

local FS = {
	isfolder = envFunction("isfolder"),
	makefolder = envFunction("makefolder"),
	isfile = envFunction("isfile"),
	readfile = envFunction("readfile"),
	writefile = envFunction("writefile"),
	listfiles = envFunction("listfiles"),
	delfile = envFunction("delfile"),
}
FS.available = FS.isfolder and FS.makefolder and FS.readfile and FS.writefile and FS.isfile and true or false
function FS.exists(path)
    if not FS.isfile then return false end
    local ok, exists = pcall(FS.isfile, path)
    return ok and exists == true
end

--// Design tokens --------------------------------------------------------------

-- Layers, darkest first: window/sidebar (Background) → content panel (Sidebar) → cards
-- (Surface) → controls (Elevated) → hovered controls (Hover). The steps are small and even,
-- so the layers read as one family. These are the neutral values; themes rebuild them
-- (see buildTheme), tinting every layer with the theme's hue.
local Theme = {
	Background = Color3.fromRGB(11, 11, 12),
	Sidebar = Color3.fromRGB(14, 14, 16),
	Surface = Color3.fromRGB(20, 20, 22),
	Elevated = Color3.fromRGB(29, 29, 32),
	Hover = Color3.fromRGB(38, 38, 42),
	Stroke = Color3.fromRGB(45, 45, 50),
	StrokeSoft = Color3.fromRGB(28, 28, 31),
	Text = Color3.fromRGB(250, 250, 251),
	SubText = Color3.fromRGB(222, 222, 226),
	Muted = Color3.fromRGB(161, 161, 168),
	Accent = Color3.fromRGB(245, 245, 247),
	AccentHover = Color3.fromRGB(222, 222, 226),
	OnAccent = Color3.fromRGB(12, 12, 13),
}

local function fontFace(weight)
	return Font.new("rbxasset://fonts/families/BuilderSans.json", weight, Enum.FontStyle.Normal)
end

local Fonts = {
	-- Roblox rasterises text with greyscale anti-aliasing only, so thin strokes at small sizes
	-- read as blurry. Measured in-game: text only looks solid from SemiBold and ~14px up,
	-- so every role is two weights heavier than its name suggests.
	Regular = fontFace(Enum.FontWeight.SemiBold),
	Medium = fontFace(Enum.FontWeight.Bold),
	SemiBold = fontFace(Enum.FontWeight.Bold),
	Bold = fontFace(Enum.FontWeight.ExtraBold),
}

local WINDOW_SIZE = Vector2.new(840, 540)
local SIDEBAR_WIDTH = 212
local BRAND_HEIGHT = 72
local FOOTER_HEIGHT = 70
local PANEL_INSET = 8 -- gap around the content panel (top, right, bottom)
local PANEL_WIDTH = WINDOW_SIZE.X - SIDEBAR_WIDTH - PANEL_INSET
local TOPBAR_HEIGHT = 58
local PAGE_MARGIN = 14
local COLUMN_GAP = 12
-- Whole-pixel column width. Scale-based halves of an odd content width put the right
-- column on x.5, which renders its text blurry.
local COLUMN_WIDTH = math.floor((PANEL_WIDTH - PAGE_MARGIN * 2 - COLUMN_GAP) / 2)
-- CreateWindow({ Compact = true }) swaps in the compact layout: an icon rail instead of the
-- sidebar, sub-tabs as chips in the header and denser elements. Set before any element is built.
local COMPACT = false

-- Lucide glyphs from public 48px spritesheets: { assetId, rectX, rectY }.
local Icons = {
	["activity"] = { 16898612629, 514, 771 },
	["bell"] = { 16898612819, 820, 257 },
	["bolt"] = { 16898612819, 306, 820 },
	["box"] = { 16898612819, 771, 196 },
	["camera"] = { 16898612819, 967, 563 },
	["check"] = { 16898612819, 710, 869 },
	["chevron-down"] = { 16898612819, 196, 918 },
	["chevron-right"] = { 16898612819, 869, 759 },
	["circle-check"] = { 16898612819, 869, 955 },
	["circle-x"] = { 16898613044, 820, 306 },
	["component"] = { 16898613044, 967, 49 },
	["cpu"] = { 16898613044, 196, 869 },
	["crosshair"] = { 16898613044, 453, 869 },
	["download"] = { 16898613044, 820, 906 },
	["eye"] = { 16898613353, 771, 563 },
	["flame"] = { 16898613353, 967, 306 },
	["folder"] = { 16898613353, 404, 967 },
	["gamepad-2"] = { 16898613353, 710, 967 },
	["gauge"] = { 16898613353, 771, 955 },
	["hand"] = { 16898613509, 563, 820 },
	["hash"] = { 16898613509, 147, 771 },
	["info"] = { 16898613509, 612, 869 },
	["joystick"] = { 16898613509, 196, 820 },
	["keyboard"] = { 16898613509, 453, 820 },
	["layers"] = { 16898613509, 98, 967 },
	["layout-dashboard"] = { 16898613509, 967, 355 },
	["lightbulb"] = { 16898613509, 918, 196 },
	["list"] = { 16898613509, 869, 808 },
	["log-out"] = { 16898613509, 820, 955 },
	["minus"] = { 16898613613, 771, 196 },
	["monitor"] = { 16898613613, 404, 820 },
	["moon"] = { 16898613613, 306, 918 },
	["mouse-pointer-2"] = { 16898613613, 820, 661 },
	["move"] = { 16898613613, 453, 820 },
	["package"] = { 16898613613, 918, 196 },
	["paintbrush"] = { 16898613613, 918, 453 },
	["palette"] = { 16898613613, 453, 918 },
	["person-standing"] = { 16898613699, 563, 771 },
	["play"] = { 16898613699, 918, 257 },
	["plus"] = { 16898613699, 257, 918 },
	["power"] = { 16898613699, 820, 147 },
	["puzzle"] = { 16898613699, 49, 918 },
	["refresh-cw"] = { 16898613699, 404, 869 },
	["rocket"] = { 16898613699, 918, 147 },
	["save"] = { 16898613699, 918, 453 },
	["search"] = { 16898613699, 918, 857 },
	["settings"] = { 16898613777, 771, 257 },
	["shield"] = { 16898613777, 869, 0 },
	["signal"] = { 16898613777, 918, 0 },
	["sliders-horizontal"] = { 16898613777, 820, 355 },
	["sparkles"] = { 16898613777, 918, 49 },
	["star"] = { 16898613777, 967, 147 },
	["sun"] = { 16898613777, 967, 453 },
	["target"] = { 16898613869, 514, 771 },
	["timer"] = { 16898613869, 918, 0 },
	["toggle-right"] = { 16898613869, 820, 98 },
	["trash-2"] = { 16898613869, 257, 918 },
	["triangle-alert"] = { 16898613869, 967, 0 },
	["upload"] = { 16898613869, 612, 869 },
	["user"] = { 16898613869, 661, 869 },
	["wand-sparkles"] = { 16898613869, 453, 918 },
	["wifi"] = { 16898613869, 869, 808 },
	["wrench"] = { 16898613869, 820, 906 },
	["x"] = { 16898613869, 869, 906 },
	["zap"] = { 16898613869, 918, 906 },
	["key"] = { 16898613509, 869, 404 },
	["key-round"] = { 16898613509, 967, 306 },
	["lock"] = { 16898613509, 918, 857 },
	["lock-open"] = { 16898613509, 967, 808 },
	["copy"] = { 16898613044, 918, 612 },
	["clipboard"] = { 16898613044, 49, 869 },
	["link"] = { 16898613509, 918, 453 },
	["external-link"] = { 16898613353, 257, 820 },
	["shield-check"] = { 16898613777, 820, 257 },
	["arrow-right"] = { 16898612629, 453, 820 },
	["loader-circle"] = { 16898613509, 771, 906 },
}

-- Nebula Icon Library / Lucide: https://github.com/Nebula-Softworks/Nebula-Icon-Library
-- Catalog adapted from LucideIcons.luau; CC BY-NC 4.0 (see Nebula-Icons.LICENSE).
-- Keep existing sprite glyphs stable; additional glyphs use individual image assets.
local NebulaLucide = {
	["a-arrow-down"] = 85758889687786,
	["a-arrow-up"] = 102165397775777,
	["a-large-small"] = 120435565718499,
	accessibility = 134709504811618,
	activity = 116785635688905,
	["air-vent"] = 128830959442416,
	airplay = 120532433393858,
	["alarm-clock"] = 135676792539632,
	["alarm-clock-check"] = 127147726542044,
	["alarm-clock-minus"] = 95643155997004,
	["alarm-clock-off"] = 137565311508297,
	["alarm-clock-plus"] = 120411905187238,
	["alarm-smoke"] = 132790621765466,
	album = 127392884430355,
	["align-center"] = 96679836838314,
	["align-center-horizontal"] = 81234251374424,
	["align-center-vertical"] = 123778475388904,
	["align-end-horizontal"] = 81993664554439,
	["align-end-vertical"] = 99312370694107,
	["align-horizontal-distribute-center"] = 118173212655147,
	["align-horizontal-distribute-end"] = 119611041085513,
	["align-horizontal-distribute-start"] = 121542670969125,
	["align-horizontal-justify-center"] = 129528110611234,
	["align-horizontal-justify-end"] = 84954252650701,
	["align-horizontal-justify-start"] = 94264399395941,
	["align-horizontal-space-around"] = 103744081790884,
	["align-horizontal-space-between"] = 101251856513947,
	["align-justify"] = 132508901949872,
	["align-left"] = 73665096529381,
	["align-right"] = 119992416120405,
	["align-start-horizontal"] = 92574847248087,
	["align-start-vertical"] = 96167730292932,
	["align-vertical-distribute-center"] = 100557171686579,
	["align-vertical-distribute-end"] = 140244274635306,
	["align-vertical-distribute-start"] = 104366918572697,
	["align-vertical-justify-center"] = 125823633272170,
	["align-vertical-justify-end"] = 101012057660025,
	["align-vertical-justify-start"] = 127756811142477,
	["align-vertical-space-around"] = 80630398253986,
	["align-vertical-space-between"] = 99587234432478,
	ambulance = 87996833293600,
	ampersand = 76003774257181,
	ampersands = 122865331745636,
	amphora = 85710574172044,
	anchor = 117368273793473,
	angry = 131535996678230,
	annoyed = 89651894120317,
	antenna = 105556767656262,
	anvil = 100535116378267,
	aperture = 88920539534875,
	["app-window"] = 128524598896661,
	["app-window-mac"] = 84920671926321,
	apple = 82452145861900,
	archive = 96979844504359,
	["archive-restore"] = 130207139403143,
	["archive-x"] = 125724859663305,
	armchair = 92951944347771,
	["arrow-big-down"] = 87872502681784,
	["arrow-big-down-dash"] = 80956925610434,
	["arrow-big-left"] = 76008736050357,
	["arrow-big-left-dash"] = 80166004308034,
	["arrow-big-right"] = 81390374011332,
	["arrow-big-right-dash"] = 125910019327152,
	["arrow-big-up"] = 118315457005585,
	["arrow-big-up-dash"] = 139174253931992,
	["arrow-down"] = 111101849488750,
	["arrow-down-0-1"] = 134662804888116,
	["arrow-down-1-0"] = 90807982982621,
	["arrow-down-a-z"] = 74563886614714,
	["arrow-down-from-line"] = 123039586915624,
	["arrow-down-left"] = 105470816142918,
	["arrow-down-narrow-wide"] = 104635517851768,
	["arrow-down-right"] = 104630792951402,
	["arrow-down-to-dot"] = 95176928712454,
	["arrow-down-to-line"] = 109729358294452,
	["arrow-down-up"] = 139238003599315,
	["arrow-down-wide-narrow"] = 88577562336410,
	["arrow-down-z-a"] = 90653871517145,
	["arrow-left"] = 86088091986547,
	["arrow-left-from-line"] = 88700685151310,
	["arrow-left-right"] = 94596049358882,
	["arrow-left-to-line"] = 116829154369215,
	["arrow-right"] = 81302631706885,
	["arrow-right-from-line"] = 132141803726901,
	["arrow-right-left"] = 108283385684703,
	["arrow-right-to-line"] = 114892398312410,
	["arrow-up"] = 79062740627249,
	["arrow-up-0-1"] = 114095112758791,
	["arrow-up-1-0"] = 115833544112532,
	["arrow-up-a-z"] = 130831349804002,
	["arrow-up-down"] = 102155677695268,
	["arrow-up-from-dot"] = 134959689985016,
	["arrow-up-from-line"] = 134860743051776,
	["arrow-up-left"] = 107477197303574,
	["arrow-up-narrow-wide"] = 101421168592063,
	["arrow-up-right"] = 103889806698388,
	["arrow-up-to-line"] = 131974361540264,
	["arrow-up-wide-narrow"] = 106886180124309,
	["arrow-up-z-a"] = 76578983028237,
	["arrows-up-from-line"] = 105423404426073,
	asterisk = 123815391218414,
	["at-sign"] = 104314582758551,
	atom = 120167347744561,
	["audio-lines"] = 138755914830486,
	["audio-waveform"] = 119789394178873,
	award = 89623672395278,
	axe = 95479937653376,
	["axis-3d"] = 92397422208087,
	baby = 134780923890658,
	backpack = 78993249203823,
	badge = 93861197775357,
	["badge-alert"] = 73521163893374,
	["badge-cent"] = 122278154144822,
	["badge-check"] = 102864233048311,
	["badge-dollar-sign"] = 99073011426006,
	["badge-euro"] = 129639299324055,
	["badge-indian-rupee"] = 87973104646655,
	["badge-info"] = 98821060789724,
	["badge-japanese-yen"] = 134928701899269,
	["badge-minus"] = 129618320064265,
	["badge-percent"] = 105307797413967,
	["badge-plus"] = 120096069624662,
	["badge-pound-sterling"] = 98623823861803,
	["badge-question-mark"] = 114663892643950,
	["badge-russian-ruble"] = 99522239121803,
	["badge-swiss-franc"] = 115747080056818,
	["badge-turkish-lira"] = 137289094254207,
	["badge-x"] = 127345048117218,
	["baggage-claim"] = 108988660196157,
	ban = 131594718784390,
	banana = 126474514866989,
	bandage = 102355944011166,
	banknote = 83624352345036,
	["banknote-arrow-down"] = 128101736029907,
	["banknote-arrow-up"] = 103476760707791,
	["banknote-x"] = 110844057471453,
	barcode = 129209916672607,
	barrel = 127931314050877,
	baseline = 137447148848893,
	bath = 111108655648642,
	battery = 81540661066811,
	["battery-charging"] = 126836500232390,
	["battery-full"] = 127212547690381,
	["battery-low"] = 87721404307217,
	["battery-medium"] = 114615415737248,
	["battery-plus"] = 76354196605526,
	["battery-warning"] = 136795384828263,
	beaker = 140429312347329,
	bean = 140548534094518,
	["bean-off"] = 87490357773352,
	bed = 103703460158347,
	["bed-double"] = 118545136165123,
	["bed-single"] = 117894740011786,
	beef = 95141393904694,
	bell = 111725241873349,
	["bell-dot"] = 102000063515653,
	["bell-electric"] = 130154093563594,
	["bell-minus"] = 134871560843826,
	["bell-off"] = 109403921599739,
	["bell-plus"] = 87193682465452,
	["bell-ring"] = 81911080119140,
	["between-horizontal-end"] = 105855324839543,
	["between-horizontal-start"] = 116266907424675,
	["between-vertical-end"] = 109243784030881,
	["between-vertical-start"] = 112708575033628,
	["biceps-flexed"] = 113573819070463,
	bike = 120355969619987,
	binary = 82905169249889,
	binoculars = 114841582615801,
	biohazard = 90593430701402,
	bird = 127082032570770,
	bitcoin = 120165823908407,
	blend = 106898143444225,
	blinds = 131748682748698,
	blocks = 99930206828481,
	bluetooth = 87938138872705,
	["bluetooth-connected"] = 93809243280097,
	["bluetooth-off"] = 92065127311527,
	["bluetooth-searching"] = 138407763527325,
	bold = 71230510917945,
	bolt = 72499878743015,
	bomb = 119539352578001,
	bone = 93032826374472,
	book = 136417435522797,
	["book-a"] = 138905558517206,
	["book-alert"] = 83126881397457,
	["book-audio"] = 130817325428812,
	["book-check"] = 101435243286406,
	["book-copy"] = 92171152631020,
	["book-dashed"] = 81283267299629,
	["book-down"] = 133514420249956,
	["book-headphones"] = 139523016403916,
	["book-heart"] = 122531870789237,
	["book-image"] = 137276864404721,
	["book-key"] = 139461027818572,
	["book-lock"] = 98420126712941,
	["book-marked"] = 108700129544150,
	["book-minus"] = 134429286820139,
	["book-open"] = 73094472868219,
	["book-open-check"] = 139564107496900,
	["book-open-text"] = 112163368354922,
	["book-plus"] = 86198588567912,
	["book-text"] = 92477178021408,
	["book-type"] = 140569336920621,
	["book-up"] = 129825144914500,
	["book-up-2"] = 138870529166566,
	["book-user"] = 78445558294223,
	["book-x"] = 117684589004730,
	bookmark = 96422374119496,
	["bookmark-check"] = 140385274312943,
	["bookmark-minus"] = 90761509653848,
	["bookmark-plus"] = 102716399992603,
	["bookmark-x"] = 83946741234593,
	["boom-box"] = 117773767367782,
	bot = 112973706230253,
	["bot-message-square"] = 127454915177046,
	["bot-off"] = 123215836836938,
	["bow-arrow"] = 82126194792160,
	box = 101391159909398,
	boxes = 129614835711516,
	braces = 74399703620454,
	brackets = 126480941270849,
	brain = 80449922621372,
	["brain-circuit"] = 122829293465734,
	["brain-cog"] = 133841445789468,
	["brick-wall"] = 88059137745523,
	["brick-wall-fire"] = 101508535298010,
	["brick-wall-shield"] = 122970924994177,
	briefcase = 79573382931819,
	["briefcase-business"] = 89024144265875,
	["briefcase-conveyor-belt"] = 80699894594034,
	["briefcase-medical"] = 88977669291957,
	["bring-to-front"] = 121372673068497,
	brush = 140399962450518,
	["brush-cleaning"] = 77081887717462,
	bubbles = 100951413779327,
	bug = 108064626456459,
	["bug-off"] = 115130754051050,
	["bug-play"] = 93005823489214,
	building = 115759871615135,
	["building-2"] = 113633264034729,
	bus = 70492885634507,
	["bus-front"] = 101442123728652,
	cable = 73929033306217,
	["cable-car"] = 103343370160284,
	cake = 94945328569141,
	["cake-slice"] = 134869363778873,
	calculator = 126294519603935,
	calendar = 95545489603627,
	["calendar-1"] = 111669544177893,
	["calendar-arrow-down"] = 98826297336095,
	["calendar-arrow-up"] = 101259481484784,
	["calendar-check"] = 128735293881337,
	["calendar-check-2"] = 134741295436727,
	["calendar-clock"] = 137989998809749,
	["calendar-cog"] = 81132100829120,
	["calendar-days"] = 74473866264642,
	["calendar-fold"] = 72800363993863,
	["calendar-heart"] = 140469143489469,
	["calendar-minus"] = 126947076491962,
	["calendar-minus-2"] = 114758284207771,
	["calendar-off"] = 83172321745470,
	["calendar-plus"] = 95864120179039,
	["calendar-plus-2"] = 110548362075353,
	["calendar-range"] = 137666557292561,
	["calendar-search"] = 77709463965815,
	["calendar-sync"] = 97624728588729,
	["calendar-x"] = 138974312970463,
	["calendar-x-2"] = 107515535887947,
	camera = 102911860111235,
	["camera-off"] = 99242316763000,
	candy = 121602796953412,
	["candy-cane"] = 112464754953529,
	["candy-off"] = 98908167238404,
	captions = 92247523675264,
	["captions-off"] = 117421756298550,
	car = 104209031513829,
	["car-front"] = 108397050137008,
	["car-taxi-front"] = 73584751879123,
	caravan = 127063101240586,
	["card-sim"] = 87568181073492,
	carrot = 121695263564136,
	["case-lower"] = 104147111219050,
	["case-sensitive"] = 80443686256687,
	["case-upper"] = 106568493343250,
	["cassette-tape"] = 85528666149718,
	cast = 106045389407030,
	castle = 137349466287423,
	cat = 132587012252853,
	cctv = 96089950910363,
	["chart-area"] = 83865456239149,
	["chart-bar"] = 78022204342641,
	["chart-bar-big"] = 77915167652266,
	["chart-bar-decreasing"] = 128999724972766,
	["chart-bar-increasing"] = 94790043521729,
	["chart-bar-stacked"] = 118586341637168,
	["chart-candlestick"] = 97939388409760,
	["chart-column"] = 90604892299985,
	["chart-column-big"] = 117124840997620,
	["chart-column-decreasing"] = 128154461153272,
	["chart-column-increasing"] = 110238053193715,
	["chart-column-stacked"] = 138210545678793,
	["chart-gantt"] = 105284278917364,
	["chart-line"] = 132073950959918,
	["chart-no-axes-column"] = 134593063392849,
	["chart-no-axes-column-decreasing"] = 117582413267339,
	["chart-no-axes-column-increasing"] = 107383929417521,
	["chart-no-axes-combined"] = 125766210212199,
	["chart-no-axes-gantt"] = 136683497999733,
	["chart-pie"] = 129237625973646,
	["chart-scatter"] = 109368208547302,
	["chart-spline"] = 128939166873577,
	check = 83827110621355,
	["check-check"] = 85764415779159,
	["check-line"] = 85776673122871,
	["chef-hat"] = 104351698660651,
	cherry = 130832753420629,
	["chevron-down"] = 95086910949405,
	["chevron-first"] = 130485497879762,
	["chevron-last"] = 127072220474704,
	["chevron-left"] = 83856486110301,
	["chevron-right"] = 126507964682213,
	["chevron-up"] = 124630674114245,
	["chevrons-down"] = 118746624854239,
	["chevrons-down-up"] = 122938925052724,
	["chevrons-left"] = 72622305378588,
	["chevrons-left-right"] = 100027150072609,
	["chevrons-left-right-ellipsis"] = 70758373090992,
	["chevrons-right"] = 115563110262022,
	["chevrons-right-left"] = 79674513843833,
	["chevrons-up"] = 115981451099607,
	["chevrons-up-down"] = 113432796824448,
	chrome = 73342145832786,
	church = 136057686683219,
	circle = 97474013459876,
	["circle-alert"] = 86075768491850,
	["circle-arrow-down"] = 98516510858394,
	["circle-arrow-left"] = 139149045348698,
	["circle-arrow-out-down-left"] = 140114130402613,
	["circle-arrow-out-down-right"] = 97306619688140,
	["circle-arrow-out-up-left"] = 133904465013804,
	["circle-arrow-out-up-right"] = 133791579853102,
	["circle-arrow-right"] = 132106229530514,
	["circle-arrow-up"] = 125630987618979,
	["circle-check"] = 122835208471730,
	["circle-check-big"] = 101462339244321,
	["circle-chevron-down"] = 125398962450772,
	["circle-chevron-left"] = 133979492199232,
	["circle-chevron-right"] = 130029053510525,
	["circle-chevron-up"] = 137057131849576,
	["circle-dashed"] = 97773019242734,
	["circle-divide"] = 75278590313141,
	["circle-dollar-sign"] = 103021845191343,
	["circle-dot"] = 73332621255981,
	["circle-dot-dashed"] = 121201310391755,
	["circle-ellipsis"] = 128894546879090,
	["circle-equal"] = 91854769894722,
	["circle-fading-arrow-up"] = 121178878326961,
	["circle-fading-plus"] = 95512963110153,
	["circle-gauge"] = 84688454826847,
	["circle-minus"] = 74458161947564,
	["circle-off"] = 80618483788295,
	["circle-parking"] = 121342131175144,
	["circle-parking-off"] = 115951067573453,
	["circle-pause"] = 75601858754638,
	["circle-percent"] = 89021739919224,
	["circle-play"] = 119442756895009,
	["circle-plus"] = 132023187288319,
	["circle-pound-sterling"] = 121749745341582,
	["circle-power"] = 131944289575262,
	["circle-question-mark"] = 98575632186975,
	["circle-slash"] = 86554477881978,
	["circle-slash-2"] = 93846864384983,
	["circle-small"] = 106775888594817,
	["circle-star"] = 108994144808450,
	["circle-stop"] = 122478988921288,
	["circle-user"] = 73363870264217,
	["circle-user-round"] = 103422319407938,
	["circle-x"] = 136096054247483,
	["circuit-board"] = 102649990533936,
	citrus = 104012894480157,
	clapperboard = 117040519290119,
	clipboard = 91839478896367,
	["clipboard-check"] = 119930716282333,
	["clipboard-clock"] = 81178312131599,
	["clipboard-copy"] = 116099874965891,
	["clipboard-list"] = 110095483413821,
	["clipboard-minus"] = 107683237596936,
	["clipboard-paste"] = 137750657442733,
	["clipboard-pen"] = 112275963070957,
	["clipboard-pen-line"] = 111346066067551,
	["clipboard-plus"] = 132362866476079,
	["clipboard-type"] = 106736512129205,
	["clipboard-x"] = 128986978015444,
	clock = 96835529467684,
	["clock-1"] = 98563563321460,
	["clock-10"] = 80443443598462,
	["clock-11"] = 82371834247998,
	["clock-12"] = 133877976025070,
	["clock-2"] = 72258367874092,
	["clock-3"] = 86319537133958,
	["clock-4"] = 111040057497751,
	["clock-5"] = 82455058311564,
	["clock-6"] = 110541146574832,
	["clock-7"] = 138423994726927,
	["clock-8"] = 98901513399369,
	["clock-9"] = 140464097226658,
	["clock-alert"] = 115862173875314,
	["clock-arrow-down"] = 95351498388159,
	["clock-arrow-up"] = 131512554213603,
	["clock-fading"] = 138812484601909,
	["clock-plus"] = 108994381956359,
	["closed-caption"] = 109168929168877,
	cloud = 76797375125469,
	["cloud-alert"] = 106567345820073,
	["cloud-check"] = 83689617445982,
	["cloud-cog"] = 99037393440946,
	["cloud-download"] = 134259137069761,
	["cloud-drizzle"] = 108966030756512,
	["cloud-fog"] = 116434374562091,
	["cloud-hail"] = 93896344446382,
	["cloud-lightning"] = 88393801019014,
	["cloud-moon"] = 92598532990542,
	["cloud-moon-rain"] = 102795706163713,
	["cloud-off"] = 132746052928464,
	["cloud-rain"] = 126682720368880,
	["cloud-rain-wind"] = 138531953575675,
	["cloud-snow"] = 83889452050491,
	["cloud-sun"] = 99857531021323,
	["cloud-sun-rain"] = 102969016910466,
	["cloud-upload"] = 85588611412306,
	cloudy = 72892691173430,
	clover = 73146836842348,
	club = 119692145642080,
	code = 102858857098762,
	["code-xml"] = 130876992978049,
	codepen = 121196034119960,
	codesandbox = 81104810964988,
	coffee = 75171771078867,
	cog = 134998527925514,
	coins = 128784569032326,
	["columns-2"] = 89175983308456,
	["columns-3"] = 109318054321048,
	["columns-3-cog"] = 138473447831624,
	["columns-4"] = 92778631374832,
	combine = 98228911815481,
	command = 129307680894782,
	compass = 117355392623233,
	component = 81317444646043,
	computer = 129323176739507,
	["concierge-bell"] = 126886445681359,
	cone = 74845976589938,
	construction = 115083821531795,
	contact = 83336471862351,
	["contact-round"] = 92207205844906,
	container = 116643588421234,
	contrast = 76959893700184,
	cookie = 139241068220893,
	["cooking-pot"] = 73135275032763,
	copy = 87942399647942,
	["copy-check"] = 99030373914807,
	["copy-minus"] = 73147465136627,
	["copy-plus"] = 124547842490145,
	["copy-slash"] = 73629354412770,
	["copy-x"] = 76935228109965,
	copyleft = 117008643514602,
	copyright = 116764791222062,
	["corner-down-left"] = 121810619354729,
	["corner-down-right"] = 94219370057308,
	["corner-left-down"] = 88518708580891,
	["corner-left-up"] = 80457911677892,
	["corner-right-down"] = 71667850048566,
	["corner-right-up"] = 116802297506682,
	["corner-up-left"] = 77719684055742,
	["corner-up-right"] = 101875782041114,
	cpu = 115781787166822,
	["creative-commons"] = 106945564709172,
	["credit-card"] = 135019527878105,
	croissant = 124064182582120,
	crop = 137832753521417,
	cross = 106039923010417,
	crosshair = 114929017287945,
	crown = 90472614287057,
	cuboid = 85125857520529,
	["cup-soda"] = 116064630908908,
	currency = 98741673384975,
	cylinder = 106008846957333,
	dam = 123638563636102,
	database = 122884003685338,
	["database-backup"] = 134263890065988,
	["database-zap"] = 94292145388316,
	["decimals-arrow-left"] = 83364854887027,
	["decimals-arrow-right"] = 89255202941321,
	delete = 120475342373468,
	dessert = 79122775950408,
	diameter = 103202047751161,
	diamond = 116224572544413,
	["diamond-minus"] = 98219591040851,
	["diamond-percent"] = 90953177250482,
	["diamond-plus"] = 81855866369969,
	["dice-1"] = 129785132691343,
	["dice-2"] = 101184428062194,
	["dice-3"] = 126124539917527,
	["dice-4"] = 136593201423203,
	["dice-5"] = 72548398039172,
	["dice-6"] = 107423423270100,
	dices = 117821030233748,
	diff = 89271474511472,
	disc = 139513828111819,
	["disc-2"] = 77624862049574,
	["disc-3"] = 101670496442540,
	["disc-album"] = 119925914044267,
	divide = 122092927804054,
	dna = 89745363802733,
	["dna-off"] = 138639847028076,
	dock = 132625251672190,
	dog = 111571812945872,
	["dollar-sign"] = 118972397587528,
	donut = 80434741396669,
	["door-closed"] = 89760328598955,
	["door-closed-locked"] = 72612456720492,
	["door-open"] = 133814065231262,
	dot = 97016002851923,
	download = 93868047445509,
	["drafting-compass"] = 132019045125555,
	drama = 140495061255070,
	dribbble = 85814569433570,
	drill = 102448607336819,
	drone = 87852662372231,
	droplet = 117947500824611,
	["droplet-off"] = 89562126293632,
	droplets = 91168064495352,
	drum = 85667754872431,
	drumstick = 75387497663037,
	dumbbell = 135834722331614,
	ear = 125040388889621,
	["ear-off"] = 77431400735000,
	earth = 80407859572555,
	["earth-lock"] = 82771383007037,
	eclipse = 124423514511474,
	egg = 73908680452587,
	["egg-fried"] = 88691210642745,
	["egg-off"] = 75945935080886,
	ellipsis = 95956203670622,
	["ellipsis-vertical"] = 93274856771582,
	equal = 81138954359025,
	["equal-approximately"] = 126766764416385,
	["equal-not"] = 110767672641130,
	eraser = 101514212866613,
	["ethernet-port"] = 107171703835846,
	euro = 105515269837621,
	expand = 135216706603096,
	["external-link"] = 88749979118129,
	eye = 139722329189430,
	["eye-closed"] = 85964738779718,
	["eye-off"] = 112375739491233,
	facebook = 126875779412726,
	factory = 124610887424481,
	fan = 99112617546784,
	["fast-forward"] = 86261062156594,
	feather = 72722125673150,
	fence = 136027177552403,
	["ferris-wheel"] = 94212033084546,
	figma = 78102137532795,
	file = 105710786731627,
	["file-archive"] = 121027564735426,
	["file-audio"] = 109136641816876,
	["file-audio-2"] = 71519060566551,
	["file-axis-3d"] = 120595284164307,
	["file-badge"] = 130908597463749,
	["file-badge-2"] = 117822997727543,
	["file-box"] = 78582029223846,
	["file-chart-column"] = 79314568863524,
	["file-chart-column-increasing"] = 113934830439854,
	["file-chart-line"] = 127333232922341,
	["file-chart-pie"] = 87366366651618,
	["file-check"] = 82422075525002,
	["file-check-2"] = 87216739205557,
	["file-clock"] = 73969155690610,
	["file-code"] = 92873308907212,
	["file-code-2"] = 115805780254840,
	["file-cog"] = 89816062085634,
	["file-diff"] = 123117415259557,
	["file-digit"] = 104037036187285,
	["file-down"] = 70441423818099,
	["file-heart"] = 90332007470916,
	["file-image"] = 80147266004613,
	["file-input"] = 126683034896557,
	["file-json"] = 76272094739618,
	["file-json-2"] = 117283373455325,
	["file-key"] = 85781683326011,
	["file-key-2"] = 104279126245073,
	["file-lock"] = 74414492225090,
	["file-lock-2"] = 129467818396353,
	["file-minus"] = 100049317730317,
	["file-minus-2"] = 99533501912168,
	["file-music"] = 87486385971490,
	["file-output"] = 117761656606452,
	["file-pen"] = 120012000577923,
	["file-pen-line"] = 77107867479655,
	["file-play"] = 122519637890628,
	["file-plus"] = 134349751246644,
	["file-plus-2"] = 98358464374463,
	["file-question-mark"] = 107111567783242,
	["file-scan"] = 116607859572941,
	["file-search"] = 87648314058326,
	["file-search-2"] = 97504576826222,
	["file-sliders"] = 87362735438576,
	["file-spreadsheet"] = 108378493201587,
	["file-stack"] = 119139237519469,
	["file-symlink"] = 125888988169632,
	["file-terminal"] = 114817439039127,
	["file-text"] = 77346633411296,
	["file-type"] = 91319647276184,
	["file-type-2"] = 102862931204754,
	["file-up"] = 77215633607245,
	["file-user"] = 125031706574705,
	["file-video-camera"] = 98825192269661,
	["file-volume"] = 84825655898765,
	["file-volume-2"] = 132074661677474,
	["file-warning"] = 131113901247439,
	["file-x"] = 134673190690961,
	["file-x-2"] = 75426786305569,
	files = 119868587246453,
	film = 115982940808785,
	fingerprint = 135337299493865,
	["fire-extinguisher"] = 106667025708329,
	fish = 107002260548857,
	["fish-off"] = 83515767284587,
	["fish-symbol"] = 112313456680575,
	flag = 80165228709790,
	["flag-off"] = 131374214560413,
	["flag-triangle-left"] = 100274047554673,
	["flag-triangle-right"] = 95559011206904,
	flame = 78769660969441,
	["flame-kindling"] = 125287652452426,
	flashlight = 114148297083785,
	["flashlight-off"] = 78806207489112,
	["flask-conical"] = 77588155748536,
	["flask-conical-off"] = 140153784540477,
	["flask-round"] = 125921380095942,
	["flip-horizontal"] = 104841355411279,
	["flip-horizontal-2"] = 75840761823703,
	["flip-vertical"] = 88010991372085,
	["flip-vertical-2"] = 115335841457244,
	flower = 125602823130456,
	["flower-2"] = 93937864318346,
	focus = 74209922635562,
	["fold-horizontal"] = 119215308506101,
	["fold-vertical"] = 89627287319601,
	folder = 94236858672537,
	["folder-archive"] = 85978040479686,
	["folder-check"] = 89058605827073,
	["folder-clock"] = 132379000568110,
	["folder-closed"] = 78087942744334,
	["folder-code"] = 79208102753918,
	["folder-cog"] = 125325854177187,
	["folder-dot"] = 135307937184362,
	["folder-down"] = 133724276147220,
	["folder-git"] = 129905012475725,
	["folder-git-2"] = 132556334850282,
	["folder-heart"] = 74682854132263,
	["folder-input"] = 89543549078565,
	["folder-kanban"] = 115692234423291,
	["folder-key"] = 134841972348783,
	["folder-lock"] = 129345483035475,
	["folder-minus"] = 96592440405999,
	["folder-open"] = 100030967746766,
	["folder-open-dot"] = 93584740507880,
	["folder-output"] = 79131635705997,
	["folder-pen"] = 95853187570930,
	["folder-plus"] = 133649526561782,
	["folder-root"] = 85546937479322,
	["folder-search"] = 85575256433549,
	["folder-search-2"] = 132801780326542,
	["folder-symlink"] = 82192734774481,
	["folder-sync"] = 80229070969489,
	["folder-tree"] = 137484935980485,
	["folder-up"] = 135876471645692,
	["folder-x"] = 98414588777713,
	folders = 129365910191151,
	footprints = 128293375583452,
	forklift = 121191524995774,
	forward = 85252404877367,
	frame = 91667256603587,
	framer = 105756021674631,
	frown = 136210266332024,
	fuel = 124477459297771,
	fullscreen = 75191423285573,
	funnel = 139525415522108,
	["funnel-plus"] = 85388798952525,
	["funnel-x"] = 118617352389010,
	["gallery-horizontal"] = 119833288662729,
	["gallery-horizontal-end"] = 110525792845537,
	["gallery-thumbnails"] = 104642411702006,
	["gallery-vertical"] = 73022710081053,
	["gallery-vertical-end"] = 81965622854313,
	gamepad = 98531369429309,
	["gamepad-2"] = 123513783706820,
	gauge = 112385371277348,
	gavel = 135735395765414,
	gem = 111750318675671,
	["georgian-lari"] = 83044477439865,
	ghost = 121912141443713,
	gift = 104098622197576,
	["git-branch"] = 137795533783771,
	["git-branch-plus"] = 140661560177072,
	["git-commit-horizontal"] = 70945132741002,
	["git-commit-vertical"] = 91329034046756,
	["git-compare"] = 115173556067875,
	["git-compare-arrows"] = 88221652268203,
	["git-fork"] = 99605451182076,
	["git-graph"] = 112496986736544,
	["git-merge"] = 136694613142223,
	["git-pull-request"] = 103161641898441,
	["git-pull-request-arrow"] = 135103379062990,
	["git-pull-request-closed"] = 132153092177959,
	["git-pull-request-create"] = 72404602418293,
	["git-pull-request-create-arrow"] = 78997835114389,
	["git-pull-request-draft"] = 109941927307148,
	github = 99911323926868,
	gitlab = 84697247849648,
	["glass-water"] = 88501428715818,
	glasses = 71294658108313,
	globe = 111578783307093,
	["globe-lock"] = 90505069766503,
	goal = 113884228231281,
	gpu = 94475400466478,
	["graduation-cap"] = 137048485405567,
	grape = 81297793587857,
	["grid-2x2"] = 74713443066181,
	["grid-2x2-check"] = 138646582122430,
	["grid-2x2-plus"] = 73772834594194,
	["grid-2x2-x"] = 70574771191740,
	["grid-3x2"] = 98309561243489,
	["grid-3x3"] = 71217273531422,
	grip = 85101746401400,
	["grip-horizontal"] = 87629819003793,
	["grip-vertical"] = 137774674680603,
	group = 137317722960946,
	guitar = 73621537334007,
	ham = 88694785814390,
	hamburger = 94625438561758,
	hammer = 118024154647073,
	hand = 135226632951455,
	["hand-coins"] = 83908670424159,
	["hand-fist"] = 107874697791879,
	["hand-grab"] = 123243858007453,
	["hand-heart"] = 112348965568014,
	["hand-helping"] = 125055501525649,
	["hand-metal"] = 79886749805841,
	["hand-platter"] = 107005076555892,
	handbag = 91595142847556,
	handshake = 119934900822508,
	["hard-drive"] = 78399523068992,
	["hard-drive-download"] = 126141378180246,
	["hard-drive-upload"] = 83678732882261,
	["hard-hat"] = 108269886668169,
	hash = 79281219073716,
	["hat-glasses"] = 88187986739237,
	haze = 71695050029489,
	["hdmi-port"] = 81667603031684,
	heading = 78795987652364,
	["heading-1"] = 139010744018776,
	["heading-2"] = 124511186941584,
	["heading-3"] = 93398585070111,
	["heading-4"] = 129752194457637,
	["heading-5"] = 91071250337131,
	["heading-6"] = 120942934503080,
	["headphone-off"] = 129718080175290,
	headphones = 77933962515384,
	headset = 78282688338634,
	heart = 111284155515598,
	["heart-crack"] = 127768416202523,
	["heart-handshake"] = 116921190920035,
	["heart-minus"] = 73753737435862,
	["heart-off"] = 77001527259120,
	["heart-plus"] = 136895624976238,
	["heart-pulse"] = 77506710442387,
	heater = 92597012287078,
	hexagon = 107545705237342,
	highlighter = 76647612275284,
	history = 87356875172942,
	hop = 107327941544346,
	["hop-off"] = 82070652552741,
	hospital = 136121422327167,
	hotel = 116521770015178,
	hourglass = 97354459771104,
	house = 127889862453151,
	["house-plug"] = 78286530988441,
	["house-plus"] = 86361930968044,
	["house-wifi"] = 81833657881659,
	["ice-cream-bowl"] = 132923169807183,
	["ice-cream-cone"] = 113398279002531,
	["id-card"] = 132284632593096,
	["id-card-lanyard"] = 109892675249866,
	image = 97933683823480,
	["image-down"] = 128149725849146,
	["image-minus"] = 133568289476916,
	["image-off"] = 99722939227313,
	["image-play"] = 73625941877084,
	["image-plus"] = 110592938693426,
	["image-up"] = 132790868440788,
	["image-upscale"] = 93091453446368,
	images = 100017582062659,
	import = 139415113590086,
	inbox = 117961494051741,
	["indent-decrease"] = 90925139615278,
	["indent-increase"] = 110694604864721,
	infinity = 71094877806551,
	info = 117194610053749,
	["inspection-panel"] = 140555328817154,
	instagram = 137841936676016,
	italic = 138130625449010,
	["iteration-ccw"] = 106807980654516,
	["iteration-cw"] = 117352992192290,
	["japanese-yen"] = 135085526808806,
	joystick = 126601646824958,
	kanban = 94237167428633,
	kayak = 114220085067472,
	key = 128426502701541,
	["key-round"] = 80439075172197,
	["key-square"] = 108847209577743,
	keyboard = 78021479821645,
	["keyboard-music"] = 96603074688320,
	["keyboard-off"] = 74463086557782,
	lamp = 106149598999550,
	["lamp-ceiling"] = 107373474068506,
	["lamp-desk"] = 119091300882668,
	["lamp-floor"] = 118721404002286,
	["lamp-wall-down"] = 131117332018010,
	["lamp-wall-up"] = 111944147622055,
	["land-plot"] = 117262165674351,
	landmark = 79297358121552,
	languages = 99917326264912,
	laptop = 88630921256285,
	["laptop-minimal"] = 91902636411470,
	["laptop-minimal-check"] = 98083699649871,
	lasso = 136407965747211,
	["lasso-select"] = 140206314736013,
	laugh = 88041268215527,
	layers = 92401939426051,
	["layers-2"] = 71032875043708,
	["layout-dashboard"] = 109242208940047,
	["layout-grid"] = 80776002921415,
	["layout-list"] = 114901096944423,
	["layout-panel-left"] = 114060619125104,
	["layout-panel-top"] = 140600115620376,
	["layout-template"] = 129513311046670,
	leaf = 114141473154636,
	["leafy-green"] = 75869853521394,
	lectern = 132546168528484,
	["letter-text"] = 127411184020577,
	library = 83641291044674,
	["library-big"] = 70943181021648,
	["life-buoy"] = 88251596523708,
	ligature = 108611580430117,
	lightbulb = 84480692719292,
	["lightbulb-off"] = 107872451939373,
	["line-squiggle"] = 109026309416970,
	link = 73034596791310,
	["link-2"] = 133396582932673,
	["link-2-off"] = 121617377271978,
	linkedin = 140464241694936,
	list = 114094290740453,
	["list-check"] = 127870753168379,
	["list-checks"] = 86457557777962,
	["list-collapse"] = 82013284474006,
	["list-end"] = 137196003577993,
	["list-filter"] = 93463268962238,
	["list-filter-plus"] = 82054172755080,
	["list-minus"] = 109578084629712,
	["list-music"] = 129462394886041,
	["list-ordered"] = 90091028350622,
	["list-plus"] = 132897130887667,
	["list-restart"] = 131578648989528,
	["list-start"] = 139157484305448,
	["list-todo"] = 80421543478674,
	["list-tree"] = 117981368838761,
	["list-video"] = 109079200359344,
	["list-x"] = 79967305528275,
	loader = 93092440305180,
	["loader-circle"] = 83085220798016,
	["loader-pinwheel"] = 80619164634690,
	locate = 76100135911825,
	["locate-fixed"] = 90537535083303,
	["locate-off"] = 130114126626523,
	lock = 71897067930472,
	["lock-keyhole"] = 82932539629673,
	["lock-keyhole-open"] = 126670774179963,
	["lock-open"] = 87192818819520,
	["log-in"] = 104921246880407,
	["log-out"] = 121452889215065,
	logs = 116413304493431,
	lollipop = 92370242563303,
	luggage = 109817666982832,
	magnet = 106378767543648,
	mail = 107247149114562,
	["mail-check"] = 102299214572170,
	["mail-minus"] = 137507529682313,
	["mail-open"] = 79957216174404,
	["mail-plus"] = 97392054041921,
	["mail-question-mark"] = 132294296415348,
	["mail-search"] = 132121654925757,
	["mail-warning"] = 85952461449135,
	["mail-x"] = 132599640757010,
	mailbox = 121433709442295,
	mails = 109802610456892,
	map = 108279805507438,
	["map-minus"] = 133117854348106,
	["map-pin"] = 125589857044225,
	["map-pin-check"] = 73433657551837,
	["map-pin-check-inside"] = 102543459974284,
	["map-pin-house"] = 128212288031307,
	["map-pin-minus"] = 120843698769560,
	["map-pin-minus-inside"] = 118797191517231,
	["map-pin-off"] = 83652562771070,
	["map-pin-pen"] = 102101538402375,
	["map-pin-plus"] = 90799053974278,
	["map-pin-plus-inside"] = 131853510003248,
	["map-pin-x"] = 129671310772849,
	["map-pin-x-inside"] = 90842207454692,
	["map-pinned"] = 113144984652101,
	["map-plus"] = 115814246160273,
	mars = 120237837691441,
	["mars-stroke"] = 78837613304628,
	martini = 131037926665327,
	maximize = 98630565368634,
	["maximize-2"] = 108777312690515,
	medal = 112779948066117,
	megaphone = 104747300280187,
	["megaphone-off"] = 77333538129191,
	meh = 95295284819943,
	["memory-stick"] = 136984029152121,
	menu = 88105946054940,
	merge = 101733452883797,
	["message-circle"] = 103253555420242,
	["message-circle-code"] = 96382573068905,
	["message-circle-dashed"] = 88932788490732,
	["message-circle-heart"] = 126027602940494,
	["message-circle-more"] = 101045229209246,
	["message-circle-off"] = 98784452586047,
	["message-circle-plus"] = 88173371208090,
	["message-circle-question-mark"] = 72740176528871,
	["message-circle-reply"] = 85158719896232,
	["message-circle-warning"] = 92512156177738,
	["message-circle-x"] = 138168651420422,
	["message-square"] = 101115671378532,
	["message-square-code"] = 87110566156463,
	["message-square-dashed"] = 114772668488726,
	["message-square-diff"] = 132647384859535,
	["message-square-dot"] = 95702767009418,
	["message-square-heart"] = 71034790619774,
	["message-square-lock"] = 138911497616369,
	["message-square-more"] = 76114133337761,
	["message-square-off"] = 72445971887595,
	["message-square-plus"] = 84876490293543,
	["message-square-quote"] = 101124360921783,
	["message-square-reply"] = 99682905593886,
	["message-square-share"] = 111163696139836,
	["message-square-text"] = 91402725252953,
	["message-square-warning"] = 133546627536577,
	["message-square-x"] = 91869532020383,
	["messages-square"] = 109110355978624,
	mic = 103948785438713,
	["mic-off"] = 79381540622986,
	["mic-vocal"] = 92319189653574,
	microchip = 114426363692876,
	microscope = 103981634776023,
	microwave = 75423014603555,
	milestone = 84696060292016,
	milk = 107378004547607,
	["milk-off"] = 81017198212200,
	minimize = 132292418800172,
	["minimize-2"] = 115725194133672,
	minus = 120931250449806,
	monitor = 73331152826648,
	["monitor-check"] = 108437497698621,
	["monitor-cog"] = 125290620584522,
	["monitor-dot"] = 86826823806038,
	["monitor-down"] = 80104156010991,
	["monitor-off"] = 107107538808355,
	["monitor-pause"] = 115791072190872,
	["monitor-play"] = 128624177550179,
	["monitor-smartphone"] = 124682793139873,
	["monitor-speaker"] = 105110083118826,
	["monitor-stop"] = 101211853475552,
	["monitor-up"] = 116088712099154,
	["monitor-x"] = 133534745521587,
	moon = 77588825794567,
	["moon-star"] = 98988085004726,
	mountain = 80263482644790,
	["mountain-snow"] = 104191181305826,
	mouse = 107043064551659,
	["mouse-off"] = 116655697625016,
	["mouse-pointer"] = 115752319794521,
	["mouse-pointer-2"] = 109904293129960,
	["mouse-pointer-ban"] = 137539892774993,
	["mouse-pointer-click"] = 107709798577185,
	move = 133600479817246,
	["move-3d"] = 81125830831808,
	["move-diagonal"] = 125202386581344,
	["move-diagonal-2"] = 81239271655220,
	["move-down"] = 125006021670342,
	["move-down-left"] = 76073036666591,
	["move-down-right"] = 129792477029045,
	["move-horizontal"] = 93208311061400,
	["move-left"] = 112800860992157,
	["move-right"] = 82428819089555,
	["move-up"] = 71652407503735,
	["move-up-left"] = 119494062849748,
	["move-up-right"] = 90419076834904,
	["move-vertical"] = 70761579193717,
	music = 93139938100228,
	["music-2"] = 113187037257153,
	["music-3"] = 81349478842651,
	["music-4"] = 96972456280656,
	navigation = 90646250576973,
	["navigation-2"] = 134503816311328,
	["navigation-2-off"] = 131174321328073,
	["navigation-off"] = 108454330041507,
	network = 126418990233987,
	newspaper = 135902869972441,
	nfc = 131962316674237,
	["non-binary"] = 105709493665133,
	notebook = 129243301519710,
	["notebook-pen"] = 91292009218546,
	["notebook-tabs"] = 123657464898215,
	["notebook-text"] = 133642544036180,
	["notepad-text"] = 92434105164050,
	["notepad-text-dashed"] = 136002331761132,
	nut = 81712991871726,
	["nut-off"] = 96078624970734,
	octagon = 134475998551461,
	["octagon-alert"] = 95722117767051,
	["octagon-minus"] = 115829204734243,
	["octagon-pause"] = 91912739903056,
	["octagon-x"] = 117018306251145,
	omega = 91642142247281,
	option = 109155681659629,
	orbit = 74587349912272,
	origami = 77425924575822,
	package = 132935702099654,
	["package-2"] = 91942377485714,
	["package-check"] = 101219557585600,
	["package-minus"] = 100080161784047,
	["package-open"] = 86330655620431,
	["package-plus"] = 83558395457935,
	["package-search"] = 94733344459732,
	["package-x"] = 131230547740708,
	["paint-bucket"] = 136313372531199,
	["paint-roller"] = 134288427758523,
	paintbrush = 131259265232881,
	["paintbrush-vertical"] = 102069363134766,
	palette = 72590019059979,
	panda = 94307958462865,
	["panel-bottom"] = 137958171526644,
	["panel-bottom-close"] = 129839176758045,
	["panel-bottom-dashed"] = 70933718377231,
	["panel-bottom-open"] = 121992330356041,
	["panel-left"] = 113565000264024,
	["panel-left-close"] = 74390600046658,
	["panel-left-dashed"] = 72672900085409,
	["panel-left-open"] = 83412022647633,
	["panel-right"] = 84244938232059,
	["panel-right-close"] = 110482031701194,
	["panel-right-dashed"] = 90286202042323,
	["panel-right-open"] = 97178553892975,
	["panel-top"] = 73398031615308,
	["panel-top-close"] = 96198752262708,
	["panel-top-dashed"] = 110503999562022,
	["panel-top-open"] = 97204124781562,
	["panels-left-bottom"] = 103748432439667,
	["panels-right-bottom"] = 126632243488487,
	["panels-top-left"] = 110293983641300,
	paperclip = 85348713089672,
	parentheses = 132664978899134,
	["parking-meter"] = 137810887120829,
	["party-popper"] = 109041559217985,
	pause = 103515787468348,
	["paw-print"] = 92297066485556,
	["pc-case"] = 128937361383812,
	pen = 116061195824555,
	["pen-line"] = 74845359608302,
	["pen-off"] = 87844360625113,
	["pen-tool"] = 133366920150012,
	pencil = 138696307419367,
	["pencil-line"] = 110410329363278,
	["pencil-off"] = 137726198263006,
	["pencil-ruler"] = 84544564987704,
	pentagon = 83842838413405,
	percent = 122952027760305,
	["person-standing"] = 88108597062307,
	["philippine-peso"] = 137021984302903,
	phone = 98258227445115,
	["phone-call"] = 110549742231723,
	["phone-forwarded"] = 101851668578549,
	["phone-incoming"] = 110075904144850,
	["phone-missed"] = 76822282444954,
	["phone-off"] = 96027672862323,
	["phone-outgoing"] = 136094637639849,
	pi = 76240757098861,
	piano = 99707908396210,
	pickaxe = 75482513098960,
	["picture-in-picture"] = 89952035422534,
	["picture-in-picture-2"] = 111681849788255,
	["piggy-bank"] = 90884658423229,
	pilcrow = 70649688801421,
	["pilcrow-left"] = 78150190347601,
	["pilcrow-right"] = 77497763828757,
	pill = 116144362117466,
	["pill-bottle"] = 135805261557990,
	pin = 91435057862637,
	["pin-off"] = 86227962812956,
	pipette = 71094894064846,
	pizza = 95650659741106,
	plane = 137398243053043,
	["plane-landing"] = 104010936460941,
	["plane-takeoff"] = 95605407118637,
	play = 80104466227462,
	plug = 127012265988191,
	["plug-2"] = 75875872308134,
	["plug-zap"] = 101683967511440,
	plus = 118563428285930,
	pocket = 113239264323778,
	["pocket-knife"] = 103757792000836,
	podcast = 96567592813667,
	pointer = 103954952458474,
	["pointer-off"] = 77566412863428,
	popcorn = 124139605746210,
	popsicle = 102234286085590,
	["pound-sterling"] = 126999093165604,
	power = 139821907770093,
	["power-off"] = 91025506233520,
	presentation = 126156401836303,
	printer = 138626675452013,
	["printer-check"] = 75685462628514,
	projector = 82137422954163,
	proportions = 95735787905869,
	puzzle = 94036333231756,
	pyramid = 134832369326112,
	["qr-code"] = 115947204757344,
	quote = 102055887623346,
	rabbit = 131189288131840,
	radar = 77840020129555,
	radiation = 100120053411692,
	radical = 83794585544135,
	radio = 96448232078753,
	["radio-receiver"] = 115849531523249,
	["radio-tower"] = 123806688762520,
	radius = 121971099119676,
	["rail-symbol"] = 114970540339018,
	rainbow = 93078612490453,
	rat = 79141000137786,
	ratio = 74750864366592,
	receipt = 76330670769012,
	["receipt-cent"] = 131615440184048,
	["receipt-euro"] = 70850947232799,
	["receipt-indian-rupee"] = 84786980270142,
	["receipt-japanese-yen"] = 82207509366200,
	["receipt-pound-sterling"] = 71719348386314,
	["receipt-russian-ruble"] = 81492439455331,
	["receipt-swiss-franc"] = 79810601551246,
	["receipt-text"] = 88438942017408,
	["receipt-turkish-lira"] = 86570860820726,
	["rectangle-circle"] = 85507321361461,
	["rectangle-ellipsis"] = 127439030387481,
	["rectangle-goggles"] = 118679920384510,
	["rectangle-horizontal"] = 71430723037696,
	["rectangle-vertical"] = 72311863384941,
	recycle = 113191864541329,
	redo = 121875341327093,
	["redo-2"] = 138576248818175,
	["redo-dot"] = 117514482954867,
	["refresh-ccw"] = 86267075959666,
	["refresh-ccw-dot"] = 119023527726959,
	["refresh-cw"] = 76845925482586,
	["refresh-cw-off"] = 129981583943775,
	refrigerator = 86690334895832,
	regex = 79467153526782,
	["remove-formatting"] = 100639728039833,
	["repeat"] = 140407645345286,
	["repeat-1"] = 138579844223208,
	["repeat-2"] = 81045504832502,
	replace = 90341483418707,
	["replace-all"] = 76323102138169,
	reply = 138678897436694,
	["reply-all"] = 118380589053924,
	rewind = 124642191767611,
	ribbon = 79206292377631,
	rocket = 79846157539863,
	["rocking-chair"] = 135381220274271,
	["roller-coaster"] = 135317411701728,
	["rotate-3d"] = 136846515530149,
	["rotate-ccw"] = 103593823592882,
	["rotate-ccw-key"] = 72108307437441,
	["rotate-ccw-square"] = 102805428127392,
	["rotate-cw"] = 92926614772014,
	["rotate-cw-square"] = 94393061569190,
	route = 90844221445155,
	["route-off"] = 85315637775689,
	router = 130572058656931,
	["rows-2"] = 140376315766404,
	["rows-3"] = 70922215029935,
	["rows-4"] = 82310713996487,
	rss = 74657652878902,
	ruler = 81932543667472,
	["ruler-dimension-line"] = 116926583536145,
	["russian-ruble"] = 108882947390227,
	sailboat = 138278085859398,
	salad = 97083943538056,
	sandwich = 84512118570250,
	satellite = 90379425147438,
	["satellite-dish"] = 139162594956306,
	["saudi-riyal"] = 111230712493826,
	save = 126786081818943,
	["save-all"] = 132114356737462,
	["save-off"] = 103052152978546,
	scale = 119160471592362,
	["scale-3d"] = 93309101177595,
	scaling = 72422884764012,
	scan = 85082632913446,
	["scan-barcode"] = 71220109533744,
	["scan-eye"] = 97734789454128,
	["scan-face"] = 112627054869699,
	["scan-heart"] = 126892182652292,
	["scan-line"] = 125356770699594,
	["scan-qr-code"] = 129609805395670,
	["scan-search"] = 123647342231468,
	["scan-text"] = 82686374141174,
	school = 82511976287252,
	scissors = 73848300538397,
	["scissors-line-dashed"] = 102508082248814,
	["screen-share"] = 106412780353220,
	["screen-share-off"] = 101801998485496,
	scroll = 125776467998184,
	["scroll-text"] = 86918746287564,
	search = 125618569555993,
	["search-check"] = 102448639481709,
	["search-code"] = 107490113587580,
	["search-slash"] = 140195845290995,
	["search-x"] = 76625315572908,
	section = 132412965594548,
	send = 120131238507529,
	["send-horizontal"] = 127567207232610,
	["send-to-back"] = 105100147812939,
	["separator-horizontal"] = 136326354982755,
	["separator-vertical"] = 81032704114272,
	server = 72203285684743,
	["server-cog"] = 80743099902491,
	["server-crash"] = 104218894040999,
	["server-off"] = 95557390125060,
	settings = 101463883805422,
	["settings-2"] = 75339943202126,
	shapes = 94522066975471,
	share = 117401968838172,
	["share-2"] = 128552309636290,
	sheet = 124970301577850,
	shell = 126582315829979,
	shield = 84528813312016,
	["shield-alert"] = 92505396627173,
	["shield-ban"] = 102215491431686,
	["shield-check"] = 83449656859552,
	["shield-ellipsis"] = 93186850567552,
	["shield-half"] = 127055700945681,
	["shield-minus"] = 130374791120900,
	["shield-off"] = 132566117165802,
	["shield-plus"] = 83455402777739,
	["shield-question-mark"] = 128418825650056,
	["shield-user"] = 99618574383264,
	["shield-x"] = 89958978888777,
	ship = 119708468740563,
	["ship-wheel"] = 100264434901423,
	shirt = 100263550622526,
	["shopping-bag"] = 128835919419658,
	["shopping-basket"] = 139164114183615,
	["shopping-cart"] = 74658309187754,
	shovel = 93002580942748,
	["shower-head"] = 73619400343212,
	shredder = 138895317439043,
	shrimp = 116646646308539,
	shrink = 88836419137438,
	shrub = 76988369043032,
	shuffle = 119271040819486,
	sigma = 95577381168467,
	signal = 86317434523846,
	["signal-high"] = 71259263664875,
	["signal-low"] = 131288244120038,
	["signal-medium"] = 100328562267364,
	["signal-zero"] = 129038651813632,
	signature = 109457267964186,
	signpost = 72013144690387,
	["signpost-big"] = 101768854635202,
	siren = 135315463281920,
	["skip-back"] = 100366953633482,
	["skip-forward"] = 96350165788710,
	skull = 89401908547230,
	slack = 103734185902703,
	slash = 80289381134111,
	slice = 110909868827850,
	["sliders-horizontal"] = 104021219611587,
	["sliders-vertical"] = 105544572196049,
	smartphone = 109476896891915,
	["smartphone-charging"] = 94398441643045,
	["smartphone-nfc"] = 108057157032168,
	smile = 72681486741811,
	["smile-plus"] = 74596726382029,
	snail = 112699295253268,
	snowflake = 82505048791925,
	["soap-dispenser-droplet"] = 117335418112713,
	sofa = 80126963498533,
	soup = 104459318914683,
	space = 124217116768896,
	spade = 76967916150583,
	sparkle = 126477294768200,
	sparkles = 130602425201313,
	speaker = 138304808385322,
	speech = 137983960166079,
	["spell-check"] = 78243940332032,
	["spell-check-2"] = 95385653254823,
	spline = 128106773633629,
	["spline-pointer"] = 123280676328314,
	split = 112314002585584,
	spool = 109278157412120,
	spotlight = 87670272614404,
	["spray-can"] = 121630219787799,
	sprout = 116761478445060,
	square = 96489726265199,
	["square-activity"] = 140333051781567,
	["square-arrow-down"] = 107014673922005,
	["square-arrow-down-left"] = 124277460165719,
	["square-arrow-down-right"] = 73561771563744,
	["square-arrow-left"] = 140645828577303,
	["square-arrow-out-down-left"] = 89110471358870,
	["square-arrow-out-down-right"] = 79224964686159,
	["square-arrow-out-up-left"] = 139915836525364,
	["square-arrow-out-up-right"] = 75394510228384,
	["square-arrow-right"] = 137883327825941,
	["square-arrow-up"] = 86704051916529,
	["square-arrow-up-left"] = 72035481166850,
	["square-arrow-up-right"] = 103199082180609,
	["square-asterisk"] = 91331591548413,
	["square-bottom-dashed-scissors"] = 72833822818441,
	["square-chart-gantt"] = 118014434980199,
	["square-check"] = 131281718379727,
	["square-check-big"] = 93336092924352,
	["square-chevron-down"] = 131902770547285,
	["square-chevron-left"] = 127087352857648,
	["square-chevron-right"] = 83652669185775,
	["square-chevron-up"] = 72583133755831,
	["square-code"] = 124986136764997,
	["square-dashed"] = 79183888005672,
	["square-dashed-bottom"] = 89157701577789,
	["square-dashed-bottom-code"] = 116292194698799,
	["square-dashed-kanban"] = 121007350604616,
	["square-dashed-mouse-pointer"] = 130924289391684,
	["square-dashed-top-solid"] = 124416825207572,
	["square-divide"] = 137218625315282,
	["square-dot"] = 117976103587060,
	["square-equal"] = 121507447179718,
	["square-function"] = 86203774968018,
	["square-kanban"] = 93286950307565,
	["square-library"] = 117062543132766,
	["square-m"] = 115722178058159,
	["square-menu"] = 81614384000771,
	["square-minus"] = 71839009603427,
	["square-mouse-pointer"] = 93614884809738,
	["square-parking"] = 129799277887252,
	["square-parking-off"] = 73561529934834,
	["square-pause"] = 126984552711307,
	["square-pen"] = 94523918453624,
	["square-percent"] = 127625721826020,
	["square-pi"] = 110661345713027,
	["square-pilcrow"] = 79387020279550,
	["square-play"] = 109792454183012,
	["square-plus"] = 73228825720276,
	["square-power"] = 110236577492349,
	["square-radical"] = 138382976817926,
	["square-round-corner"] = 117707560364355,
	["square-scissors"] = 75179246281400,
	["square-sigma"] = 131506090287142,
	["square-slash"] = 112196704068674,
	["square-split-horizontal"] = 97627785389902,
	["square-split-vertical"] = 106959144758418,
	["square-square"] = 80835095859324,
	["square-stack"] = 124304690179249,
	["square-star"] = 115056433115255,
	["square-stop"] = 111768891575856,
	["square-terminal"] = 93337999108432,
	["square-user"] = 72248743154708,
	["square-user-round"] = 135580858593151,
	["square-x"] = 107073482662073,
	["squares-exclude"] = 73691835285197,
	["squares-intersect"] = 96924928301087,
	["squares-subtract"] = 87554296790348,
	["squares-unite"] = 122198623051662,
	squircle = 82987060321691,
	["squircle-dashed"] = 118443285499033,
	squirrel = 73560557505029,
	stamp = 121319474186232,
	star = 127746172798481,
	["star-half"] = 131968454447228,
	["star-off"] = 72177495447859,
	["step-back"] = 85492554496339,
	["step-forward"] = 113928948415823,
	stethoscope = 105982582717298,
	sticker = 127276314334483,
	["sticky-note"] = 112097020099499,
	store = 133824185120097,
	["stretch-horizontal"] = 132144609663362,
	["stretch-vertical"] = 75386274307446,
	strikethrough = 83947301832572,
	subscript = 113391516050262,
	sun = 79901529465096,
	["sun-dim"] = 104619182730276,
	["sun-medium"] = 91618371923097,
	["sun-moon"] = 79929011380037,
	["sun-snow"] = 137414435824708,
	sunrise = 135585238325032,
	sunset = 73712698016360,
	superscript = 72669097231454,
	["swatch-book"] = 128454451162104,
	["swiss-franc"] = 136694453759982,
	["switch-camera"] = 140606464585502,
	sword = 75020726675544,
	swords = 89815227241465,
	syringe = 78733573607159,
	table = 86743029152675,
	["table-2"] = 124462232337013,
	["table-cells-merge"] = 103787916007071,
	["table-cells-split"] = 137584996978518,
	["table-columns-split"] = 112532547114237,
	["table-of-contents"] = 123289010637455,
	["table-properties"] = 106533508299112,
	["table-rows-split"] = 80913015124376,
	tablet = 98236546892857,
	["tablet-smartphone"] = 82512006965851,
	tablets = 118977326005264,
	tag = 103234399652910,
	tags = 102666304482309,
	["tally-1"] = 110936672654832,
	["tally-2"] = 94187147342756,
	["tally-3"] = 124913781937253,
	["tally-4"] = 92590022818947,
	["tally-5"] = 138114201809681,
	tangent = 115243287449073,
	target = 81035867308138,
	telescope = 111810481539512,
	tent = 135834669198083,
	["tent-tree"] = 78356729712249,
	terminal = 73413798937791,
	["test-tube"] = 108565640789121,
	["test-tube-diagonal"] = 111814426284329,
	["test-tubes"] = 84207634752507,
	text = 92542971051973,
	["text-cursor"] = 71303185547080,
	["text-cursor-input"] = 81578218115202,
	["text-quote"] = 103419429142075,
	["text-search"] = 119231709110976,
	["text-select"] = 107531686199786,
	theater = 83268813741529,
	thermometer = 105535887519165,
	["thermometer-snowflake"] = 129660993200918,
	["thermometer-sun"] = 72570194548829,
	["thumbs-down"] = 105602592815443,
	["thumbs-up"] = 72411375022432,
	ticket = 104336783939037,
	["ticket-check"] = 125662376066034,
	["ticket-minus"] = 125106761208017,
	["ticket-percent"] = 73387393631130,
	["ticket-plus"] = 91987299109025,
	["ticket-slash"] = 88947231854573,
	["ticket-x"] = 120285559163949,
	tickets = 128293616470608,
	["tickets-plane"] = 110636990485048,
	timer = 96119720980390,
	["timer-off"] = 73592886882763,
	["timer-reset"] = 115263131999748,
	["toggle-left"] = 126278872210073,
	["toggle-right"] = 135316241551499,
	toilet = 82858381666593,
	["tool-case"] = 133216548079593,
	tornado = 119132390241284,
	torus = 135140424211153,
	touchpad = 111708702894486,
	["touchpad-off"] = 111996914034893,
	["tower-control"] = 132285132951711,
	["toy-brick"] = 91649902772315,
	tractor = 97620732372191,
	["traffic-cone"] = 139621281679882,
	["train-front"] = 98677382842804,
	["train-front-tunnel"] = 114866528676443,
	["train-track"] = 120194201330757,
	["tram-front"] = 91307750164226,
	transgender = 111481765827654,
	trash = 116863849368916,
	["trash-2"] = 79564839810840,
	["tree-deciduous"] = 131205325166458,
	["tree-palm"] = 128164120447244,
	["tree-pine"] = 90774792597002,
	trees = 98571299046731,
	trello = 107898356259657,
	["trending-down"] = 117917602459815,
	["trending-up"] = 116886197130999,
	["trending-up-down"] = 103717610858616,
	triangle = 107100599170044,
	["triangle-alert"] = 76712741040235,
	["triangle-dashed"] = 84136951328014,
	["triangle-right"] = 97661263578338,
	trophy = 99468111768746,
	truck = 102380610139245,
	["truck-electric"] = 107501288276081,
	["turkish-lira"] = 98366519784263,
	turntable = 129425246442560,
	turtle = 124788802294981,
	tv = 91976706623107,
	["tv-minimal"] = 102675516773869,
	["tv-minimal-play"] = 133814752541561,
	twitch = 78418686039425,
	type = 123010942632689,
	["type-outline"] = 75596975306451,
	umbrella = 130176200284323,
	["umbrella-off"] = 123696654720209,
	underline = 86005310176484,
	undo = 98677000788509,
	["undo-2"] = 123288184651876,
	["undo-dot"] = 97048183118444,
	["unfold-horizontal"] = 102321820508665,
	["unfold-vertical"] = 110395906345252,
	ungroup = 116761886838866,
	university = 105398737245802,
	unlink = 114774779025598,
	["unlink-2"] = 84980216310960,
	unplug = 71213047838603,
	upload = 84448595764921,
	usb = 122244624865802,
	user = 81899856845503,
	["user-check"] = 124183127537182,
	["user-cog"] = 132530394308182,
	["user-lock"] = 102304427888373,
	["user-minus"] = 139212780407738,
	["user-pen"] = 109063575712204,
	["user-plus"] = 73169931625061,
	["user-round"] = 122472562648438,
	["user-round-check"] = 116820685971606,
	["user-round-cog"] = 81932262543896,
	["user-round-minus"] = 131104410574220,
	["user-round-pen"] = 88582957358214,
	["user-round-plus"] = 72756692986447,
	["user-round-search"] = 121920726195803,
	["user-round-x"] = 133496165281802,
	["user-search"] = 91526614931270,
	["user-star"] = 104674549336879,
	["user-x"] = 83017534068566,
	users = 109023655602096,
	["users-round"] = 73720692207232,
	utensils = 92328553872866,
	["utensils-crossed"] = 115379488607669,
	["utility-pole"] = 78544397723455,
	variable = 108495567404232,
	vault = 125730392773824,
	["vector-square"] = 120085753224630,
	vegan = 133693714976186,
	["venetian-mask"] = 73997918289433,
	venus = 77091339518872,
	["venus-and-mars"] = 85333806376716,
	vibrate = 94421703759873,
	["vibrate-off"] = 104055297186916,
	video = 120899025417114,
	["video-off"] = 98571437579498,
	videotape = 110595652490996,
	view = 96170375252355,
	voicemail = 129863571214632,
	volleyball = 79983513397509,
	volume = 136944486138432,
	["volume-1"] = 76450166585050,
	["volume-2"] = 127590428470553,
	["volume-off"] = 76437794585400,
	["volume-x"] = 102557100794756,
	vote = 111127508049086,
	wallet = 82693664006746,
	["wallet-cards"] = 131093307699863,
	["wallet-minimal"] = 104760648200766,
	wallpaper = 127531571966115,
	wand = 100247093544676,
	["wand-sparkles"] = 109636225248973,
	warehouse = 117043792208242,
	["washing-machine"] = 124299191442908,
	watch = 96632122742030,
	waves = 132537108109414,
	["waves-ladder"] = 130770635115623,
	waypoints = 89579429286632,
	webcam = 99543028331067,
	webhook = 127494549649286,
	["webhook-off"] = 94143246779298,
	weight = 70452176653194,
	wheat = 72827060603331,
	["wheat-off"] = 133950070398243,
	["whole-word"] = 83053413552620,
	wifi = 101360393607039,
	["wifi-cog"] = 86268760919032,
	["wifi-high"] = 139565602232260,
	["wifi-low"] = 129432377919005,
	["wifi-off"] = 128431848377922,
	["wifi-pen"] = 109435800293522,
	["wifi-sync"] = 134593311559828,
	["wifi-zero"] = 132143289837251,
	wind = 73952787381292,
	["wind-arrow-down"] = 107113727390188,
	workflow = 125401528378697,
	worm = 110566866003503,
	["wrap-text"] = 118921109568806,
	wrench = 108764185264619,
	x = 73070135088117,
	youtube = 100529433894693,
	zap = 99546940565021,
	["zap-off"] = 112636243101847,
	["zoom-in"] = 132256802524814,
	["zoom-out"] = 109610457179810,
	["beer-off"] = 138037951949066,
	["beer"] = 120586510698080,
	["bottle-wine"] = 93707442058849,
	["cannabis"] = 130136923421319,
	["chart-network"] = 116749958806877,
	["cigarrete-off"] = 85361164732665,
	["cigarette"] = 78543658965377,
	["indian-rupee"] = 139912038918762,
	["twitter"] = 83698772731875,
	["wine-off"] = 128440413658301,
	["wine"] = 73532622126175,
}
for name, assetId in pairs(NebulaLucide) do
    if not Icons[name] then Icons[name] = { assetId, 0, 0, 0 } end
end
local function resolveIcon(name)
    if type(name) ~= "string" then return nil end
    local key = name:lower():gsub("^lucide:", ""):gsub("^lucide%-", ""):gsub("_", "-")
    return Icons[key]
end

local FAST = TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SMOOTH = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local BOUNCE = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--// Utilities ------------------------------------------------------------------

local function Create(className, props, children)
	local instance = Instance.new(className)
	local parent
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			instance[key] = value
		end
	end
	-- Preserve authored UI text instead of applying experience translations.
	if instance:IsA("GuiBase2d") then instance.AutoLocalize = false end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function Corner(radius)
	return Create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function Stroke(color, transparency)
	return Create("UIStroke", {
		Color = color,
		Thickness = 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function Padding(top, right, bottom, left)
	return Create("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
	})
end

local function List(spacing, direction)
	return Create("UIListLayout", {
		Padding = UDim.new(0, spacing or 0),
		FillDirection = direction or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

local function Label(props)
	local label = Create("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = Fonts.Regular,
		TextSize = 15,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	for key, value in pairs(props) do
		label[key] = value
	end
	return label
end

local function Icon(name, props)
	local data = resolveIcon(name)
	local image = Create("ImageLabel", {
		BackgroundTransparency = 1,
		Image = data and ("rbxassetid://" .. data[1]) or (type(name) == "string" and name:find("^rbxasset") and name or ""),
		ImageRectSize = data and data[4] ~= 0 and Vector2.new(48, 48) or Vector2.zero,
		ImageRectOffset = data and Vector2.new(data[2], data[3]) or Vector2.zero,
		ScaleType = Enum.ScaleType.Fit,
	})
	for key, value in pairs(props or {}) do
		image[key] = value
	end
	return image
end

-- Brand marks ----------------------------------------------------------------------
-- Logos drawn from plain frames, so a hub gets a real mark without uploading an image.
-- A `Logo` naming a mark ("peak") draws it; any other string is shown as text.

local BrandMarks = {}

-- Peak: an "A" shaped like a summit, in a 120-unit box. Outer triangle apex (60,14) with
-- its base from 14 to 106 at y=104; a notch rises from the base (36..84) to (60,56); a
-- crossbar sits at y≈82.
-- Drawn on whole pixels so it stays sharp: one row per pixel, solid frames for the fully
-- covered pixels, and one extra edge pixel whose transparency matches how much of it the
-- shape covers — hand-made anti-aliasing, crisp edges without the staircase.
BrandMarks.peak = function(holder, color, zIndex, px)
	local k = px / 120
	local function cell(x, y, width, alpha)
		Create("Frame", {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(width, 1),
			BackgroundColor3 = color,
			BackgroundTransparency = 1 - alpha,
			BorderSizePixel = 0,
			ZIndex = zIndex,
			Parent = holder,
		})
	end
	-- one horizontal run from xl to xr (pixel units, fractional) on pixel row y
	local function span(xl, xr, y)
		if xr - xl <= 0.05 then
			return
		end
		local a, b = math.ceil(xl), math.floor(xr)
		if b < a then -- the whole run sits inside one pixel
			cell(math.floor(xl), y, 1, xr - xl)
			return
		end
		if b > a then
			cell(a, y, b - a, 1)
		end
		if a - xl > 0.02 then
			cell(a - 1, y, 1, a - xl)
		end
		if xr - b > 0.02 then
			cell(b, y, 1, xr - b)
		end
	end
	local top, bottom = math.floor(14 * k + 0.5), math.floor(104 * k + 0.5)
	local barTop, barBottom = math.floor(78.5 * k + 0.5), math.max(math.floor(85.5 * k + 0.5), math.floor(78.5 * k + 0.5) + 1)
	local cx = 60 * k
	for y = top, bottom - 1 do
		local v = (y + 0.5) / k -- row centre back in 120-unit space
		local outer = (v - 14) * 46 / 90 * k
		if y >= barTop and y < barBottom then
			span(cx - outer, cx + outer, y) -- the crossbar fills the notch on its rows
		elseif v > 56 then
			local inner = (v - 56) * 24 / 48 * k
			span(cx - outer, cx - inner, y)
			span(cx + inner, cx + outer, y)
		else
			span(cx - outer, cx + outer, y)
		end
	end
end

local function isBrandMark(logo)
	return type(logo) == "string" and BrandMarks[logo:lower()] ~= nil
end

-- Fills a logo tile: the named mark, or the logo text. `tile` is the tile's size in px.
-- `bare` drops the tile's own fill so only the mark shows (window brand, key screen).
-- Official Atlas PNGs. Keep original pixels and colors independent of UI themes.
local AtlasBrandAssets = {
    logo = { path = "ATLAS/brand/logo-a81f38a8516b.png" },
    minimized = { path = "ATLAS/brand/minimized-f72da9728242.png" },
}
local AtlasBrandResolved, AtlasBrandPending = {}, {}
local AtlasBrandDims = {}
-- Cache-only consumer: networking belongs exclusively to the loader.
local function AtlasBrandResolve(kind)
    if AtlasBrandResolved[kind] then return AtlasBrandResolved[kind] end
    local spec = AtlasBrandAssets[kind]
    local custom = envFunction("getcustomasset") or envFunction("getsynasset") or namespaceFunction("syn", "getcustomasset")
    local read, exists = envFunction("readfile"), envFunction("isfile")
    if not custom or not read or not exists then return nil end
    local ok, asset = pcall(function()
        local path = spec.path
        -- An older loader cached the same artwork under another file name: use any cached copy.
        local list = envFunction("listfiles")
        if not exists(path) and list then
            local prefix = "ATLAS/brand/" .. kind .. "-"
            for _, file in ipairs(list("ATLAS/brand")) do
                local normal = tostring(file):gsub("\\", "/")
                if normal:sub(-4) == ".png" and normal:find(prefix, 1, true) then path = file; break end
            end
        end
        assert(exists(path), "Run the Atlas hub loader to cache the brand images")
        assert(read(path):sub(1,8) == "\137PNG\r\n\26\n", "Invalid brand cache; run the loader again")
        local header = read(path):sub(1, 24)
        if #header >= 24 then
            local function be(i) return header:byte(i) * 16777216 + header:byte(i + 1) * 65536 + header:byte(i + 2) * 256 + header:byte(i + 3) end
            AtlasBrandDims[kind] = Vector2.new(be(17), be(21))
        end
        return custom(path)
    end)
    if ok then AtlasBrandResolved[kind] = asset; return asset end
    warn("[Atlas hub] Brand image unavailable: " .. tostring(asset))
end
local function AtlasBrandImage(parent, kind, zIndex)
    local image = Instance.new("ImageLabel")
    image.Name = kind == "minimized" and "AtlasMinimizedIcon" or "AtlasLogo"
    image.BackgroundTransparency = 1
    image.BorderSizePixel = 0
    if kind == "minimized" then
        -- The supplied PNG is RGB: its black outer corners are opaque.
        -- Mask the image itself, not its transparent button parent.
        local mask = Instance.new("UICorner")
        mask.Name = "AtlasIconMask"
        mask.CornerRadius = UDim.new(0.235, 0)
        mask:SetAttribute("NoTheme", true)
        mask:SetAttribute("NoGradient", true)
        mask.Parent = image
    end
    image.Size = UDim2.fromScale(1, 1)
    image.ImageColor3 = Color3.new(1, 1, 1)
    image.ScaleType = Enum.ScaleType.Fit
    image.ZIndex = zIndex or parent.ZIndex
    image:SetAttribute("NoTheme", true)
    image:SetAttribute("NoGradient", true)
    -- Roblox can downsample custom PNGs. Crop against the loaded texture size,
    
    local function fitTexture()
        -- ContentImageSize may require RobloxScript capability.
        -- Official cached PNGs are uploaded as 1024px textures.
        local ok, texture = pcall(function() return image.ContentImageSize end)
        if not ok or not texture or texture.X <= 0 or texture.Y <= 0 then
            -- Roblox shrinks anything above 1024px; use the PNG's real size from its header.
            local natural = AtlasBrandDims[kind]
            local capped = natural and math.min(1, 1024 / math.max(natural.X, natural.Y)) or 1
            texture = natural and Vector2.new(math.floor(natural.X * capped), math.floor(natural.Y * capped)) or Vector2.new(1024, 1024)
        end
        if texture.X <= 0 or texture.Y <= 0 then return end
        -- The official logo already fills its canvas; the minimized tile sits inside margins.
        if kind ~= "minimized" then
            image.ImageRectOffset = Vector2.new(0, 0)
            image.ImageRectSize = Vector2.new(0, 0)
            return
        end
        local start, extent = 226, 803
        image.ImageRectOffset = Vector2.new(math.floor(texture.X * start / 1254 + 0.5), math.floor(texture.Y * start / 1254 + 0.5))
        image.ImageRectSize = Vector2.new(math.floor(texture.X * extent / 1254 + 0.5), math.floor(texture.Y * extent / 1254 + 0.5))
    end
    image:GetPropertyChangedSignal("IsLoaded"):Connect(fitTexture)
    image.Parent = parent
    task.spawn(function()
        local deadline = os.clock() + 20
        while image.Parent and not image.IsLoaded and os.clock() < deadline do task.wait(0.05) end
        if image.Parent then fitTexture() end
    end)
    if AtlasBrandResolved[kind] then image.Image = AtlasBrandResolved[kind]; fitTexture(); return image end
    task.spawn(function()
        if AtlasBrandPending[kind] then
            repeat task.wait() until not AtlasBrandPending[kind]
        else
            AtlasBrandPending[kind] = true
            AtlasBrandResolve(kind)
            AtlasBrandPending[kind] = nil
        end
        if image.Parent and AtlasBrandResolved[kind] then image.Image = AtlasBrandResolved[kind]; fitTexture() end
    end)
    return image
end

local function Brand(parent, logo, tile, textSize, zIndex, bare)
    parent.BackgroundTransparency = 1
    parent:SetAttribute("NoGradient", true)
    -- Crown Hub custom icon
    local image = Instance.new("ImageLabel")
    image.Name = "BrandMark"
    image.BackgroundTransparency = 1
    image.Size = UDim2.fromScale(1, 1)
    image.Image = "rbxassetid://113737142720252"
    image.ScaleType = Enum.ScaleType.Fit
    image.ImageColor3 = Color3.new(1, 1, 1)
    image.ZIndex = zIndex or parent.ZIndex
    image:SetAttribute("NoTheme", true)
    image:SetAttribute("NoGradient", true)
    image.Parent = parent
    return image
end

local function Tween(object, info, goals)
	local tween = TweenService:Create(object, info, goals)
	tween:Play()
	return tween
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

-- One drag owns one InputObject. Other fingers never replace or finish it.
local capturedPointer
local function claimPointer(input)
	if not isPointer(input) or capturedPointer then return false end
	capturedPointer = input
	return true
end
local function movesPointer(owner, input)
	return owner ~= nil and capturedPointer == owner and
		(input == owner or (owner.UserInputType == Enum.UserInputType.MouseButton1
		and input.UserInputType == Enum.UserInputType.MouseMovement))
end
local function endsPointer(owner, input)
	if owner == nil or input ~= owner or capturedPointer ~= owner then return false end
	if capturedPointer == owner then capturedPointer = nil end
	return true
end
local function boundedCenter(point, size, vp, header)
	local half = size / 2
	-- Partial offscreen movement is intentional. Keep enough of a corner and its
	-- border visible to retrieve the window, even when the header is offscreen.
	local gripX = math.min(64, vp.X / 2, size.X / 2)
	local gripY = math.min(64, vp.Y / 2, size.Y / 2)
	return Vector2.new(
		math.clamp(point.X, gripX - half.X, vp.X - gripX + half.X),
		math.clamp(point.Y, gripY - half.Y, vp.Y - gripY + half.Y)
	)
end

local function round(value, step)
	return math.floor(value / step + 0.5) * step
end

local function formatNumber(value, step)
	local decimals = 0
	local s = tostring(step)
	local dot = s:find("%.")
	if dot then
		decimals = #s - dot
	end
	return string.format("%." .. decimals .. "f", value)
end

local function colorToHex(color)
	return string.format("%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function hexToColor(hex)
	hex = tostring(hex):gsub("#", ""):gsub("%s", "")
	if #hex == 3 then
		hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
	end
	if #hex ~= 6 or hex:find("[^%x]") then
		return nil
	end
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end

local KEY_ALIASES = {
	LeftShift = "LShift", RightShift = "RShift",
	LeftControl = "LCtrl", RightControl = "RCtrl",
	LeftAlt = "LAlt", RightAlt = "RAlt",
	LeftSuper = "LSuper", RightSuper = "RSuper",
	MouseButton1 = "MB1", MouseButton2 = "MB2", MouseButton3 = "MB3",
	Backquote = "`", Minus = "-", Equals = "=", LeftBracket = "[", RightBracket = "]",
	Semicolon = ";", Quote = "'", Comma = ",", Period = ".", Slash = "/", BackSlash = "\\",
	Return = "Enter", CapsLock = "Caps", PageUp = "PgUp", PageDown = "PgDn",
	Insert = "Ins", Delete = "Del",
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5",
	Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
}

local function keyName(key)
	if not key then
		return "None"
	end
	return KEY_ALIASES[key.Name] or key.Name
end

local function keyFromName(name)
	if type(name) ~= "string" or name == "None" then
		return nil
	end
	local ok, key = pcall(function()
		return Enum.KeyCode[name]
	end)
	if ok and key then
		return key
	end
	ok, key = pcall(function()
		return Enum.UserInputType[name]
	end)
	return ok and key or nil
end

--// Library --------------------------------------------------------------------

local Library = {
	Flags = {},
	Options = {},
	ToggleKey = Enum.KeyCode.RightShift,
	Open = true,
	Unloaded = false,
	NotificationsEnabled = true,
	UserScale = 1,
	Folder = "CrownHub",
	_connections = {},
	_unloadCallbacks = {},
	_binds = {},
	_listening = false,
	_order = 0,
}

-- Public icon discovery for scripts using the library.
function Library:HasIcon(name)
    return resolveIcon(name) ~= nil
end
function Library:GetIcon(name)
    local data = resolveIcon(name)
    if not data then return nil end
    return {
        Image = "rbxassetid://" .. data[1],
        ImageRectSize = data[4] == 0 and Vector2.zero or Vector2.new(48, 48),
        ImageRectOffset = Vector2.new(data[2], data[3]),
    }
end
function Library:GetIconNames(query)
    local names = {}
    local filter = type(query) == "string" and query:lower() or ""
    for name in pairs(Icons) do
        if filter == "" or name:find(filter, 1, true) then table.insert(names, name) end
    end
    table.sort(names)
    return names
end
Library.IconCount = #Library:GetIconNames()

local function Connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(Library._connections, connection)
	return connection
end

Connect(UserInputService.WindowFocusReleased, function()
	capturedPointer = nil
end)

local function nextOrder()
	Library._order += 1
	return Library._order
end

local function safeCall(callback, ...)
	if type(callback) ~= "function" then
		return
	end
	local args = table.pack(...)
	task.spawn(function()
		local ok, err = pcall(callback, table.unpack(args, 1, args.n))
		if not ok then
			warn("[CrownHub] callback error: " .. tostring(err))
		end
	end)
end

function Library:OnUnload(callback)
	table.insert(self._unloadCallbacks, callback)
end

-- Root ScreenGui ------------------------------------------------------------------

local ScreenGui = Create("ScreenGui", {
	Name = "CrownHub",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 2147483647,
})

do
	-- Event callbacks and native require() calls can have lower capabilities.
	-- Keep the entire UI tree accessible without Plugin/CoreGui privileges.
	ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end
Library.ScreenGui = ScreenGui
Library.AtlasBrandVersion = "png-rounded-v3"

--// Menu cursor ownership -------------------------------------------------------
-- While the panel or key prompt is open, free the cursor so the UI is clickable. The moment
-- it closes or minimizes, hand full control of the mouse back to the game (Shift Lock, camera).
local cursorSnapshot
local cursorBinding = "CrownHubCursor_" .. HttpService:GenerateGUID(false)
local function restoreMenuCursor()
    if not cursorSnapshot then return end
    local saved = cursorSnapshot
    cursorSnapshot = nil
    -- Roblox's Esc menu owns the cursor while it is open; leave it alone then.
    if game:GetService("GuiService").MenuIsOpen then return end
    -- IMPORTANT: do NOT write a saved MouseBehavior back. We only ever forced LockCenter→Default,
    -- so the cursor is already free (movable). Writing a stale saved behavior (typically a
    -- LockCenter captured when the panel opened) is exactly what left the mouse frozen at screen
    -- centre after closing/minimizing. We leave MouseBehavior as-is and let the game's camera
    -- reassert its own mode on the next frame (re-enabling Shift Lock when appropriate).
    if UserInputService.MouseIconEnabled ~= saved.icon then
        UserInputService.MouseIconEnabled = saved.icon
    end
end
function Library:_syncMenuCursor()
    local window = self.Window
    -- Own the cursor ONLY while the panel (or key prompt) is actually open. When minimized to the
    -- bubble, or closed, we release — so Shift Lock and camera control work again (the user plays
    -- with the UI tucked away and reopens with the toggle key).
    local panelVisible = self.Open and not self.Minimized and window and window.Frame and window.Frame.Visible
    local ownsInput = not self.Unloaded and ScreenGui.Enabled and (self._keyPromptActive or panelVisible)
    if ownsInput and UserInputService.MouseEnabled then
        if not cursorSnapshot then
            cursorSnapshot = {icon=UserInputService.MouseIconEnabled}
        end
        -- Only undo Shift Lock (LockCenter) so the free cursor can reach the panel. NEVER touch
        -- LockCurrentPosition: that is the game camera turning while the right mouse button is
        -- held. Forcing Default over it every frame is what made the camera stutter and refuse
        -- to turn while the UI was open.
        if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end
        -- Keep the cursor visible for clicking, but not mid camera-rotation.
        if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCurrentPosition
            and not UserInputService.MouseIconEnabled then
            UserInputService.MouseIconEnabled = true
        end
    else
        restoreMenuCursor()
    end
end
Connect(UserInputService:GetPropertyChangedSignal("MouseBehavior"), function()
    if not Library.Unloaded then Library:_syncMenuCursor() end
end)
Connect(UserInputService:GetPropertyChangedSignal("MouseIconEnabled"), function()
    if not Library.Unloaded then Library:_syncMenuCursor() end
end)
RunService:BindToRenderStep(cursorBinding, Enum.RenderPriority.Last.Value + 100, function()
    if Library.Unloaded then return end
    Library:_syncMenuCursor()
end)
Library:OnUnload(function()
    RunService:UnbindFromRenderStep(cursorBinding)
    restoreMenuCursor()
end)
--// End menu cursor ownership.

--// Wheel guard ----------------------------------------------------------------
-- The default camera zooms on any mouse wheel that no GUI consumed. Our scroll areas
-- use custom easing (native scrolling off), so while the cursor is over a registered
-- surface the camera's zoom range is pinned to its current distance, then restored.

do
	local surfaces = {}
	local saved -- { Min, Max } while pinned

	function Library:_blockWheel(gui)
		table.insert(surfaces, gui)
	end

	local function pointerOverSurface()
		local mouse = UserInputService:GetMouseLocation()
		local p = mouse - game:GetService("GuiService"):GetGuiInset() -- to AbsolutePosition space
		for index = #surfaces, 1, -1 do
			local gui = surfaces[index]
			if not gui.Parent then
				table.remove(surfaces, index)
			elseif gui.Visible and gui:IsDescendantOf(game) then
				local a, s = gui.AbsolutePosition, gui.AbsoluteSize
				if p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y then
					return true
				end
			end
		end
		return false
	end

	local function pin()
		local camera = Workspace.CurrentCamera
		if saved or not camera then
			return
		end
		saved = { Min = LocalPlayer.CameraMinZoomDistance, Max = LocalPlayer.CameraMaxZoomDistance }
		local distance = (camera.CFrame.Position - camera.Focus.Position).Magnitude
		distance = math.clamp(distance, saved.Min, saved.Max)
		LocalPlayer.CameraMaxZoomDistance = distance
		LocalPlayer.CameraMinZoomDistance = distance
	end

	local function release()
		if not saved then
			return
		end
		-- Order matters: raise the max before lowering the min so they never cross.
		LocalPlayer.CameraMaxZoomDistance = saved.Max
		LocalPlayer.CameraMinZoomDistance = saved.Min
		saved = nil
	end

	Connect(RunService.Heartbeat, function()
		if not UserInputService.MouseEnabled then
			return
		end
		if pointerOverSurface() then
			pin()
		else
			release()
		end
	end)
	Library:OnUnload(release)
	Library._releaseWheel = release
	-- Features that change the zoom range go through here so a pinned range isn't clobbered.
	function Library:SetMaxZoom(value)
		if saved then
			saved.Max = value
		else
			LocalPlayer.CameraMaxZoomDistance = value
		end
	end
end

--// Tooltip ------------------------------------------------------------------

do
	local tip = Create("Frame", {
		Name = "Tooltip",
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Elevated,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 60,
		Parent = ScreenGui,
	}, { Corner(6), Padding(0, 10, 0, 10) })
	local tipStroke = Stroke(Theme.Stroke, 1)
	tipStroke.Parent = tip
	local tipText = Label({
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 13,
		TextTransparency = 1,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = 61,
		Parent = tip,
	})

	local owner, token = nil, 0
	local function place()
		-- Mouse location is in full-screen space, which is exactly this gui's offset space.
		local mouse = UserInputService:GetMouseLocation()
		local size = tip.AbsoluteSize
		local vp = ScreenGui.AbsoluteSize -- IgnoreGuiInset: already the full screen
		local x = math.min(mouse.X + 14, vp.X - size.X - 8)
		local y = math.min(mouse.Y + 20, vp.Y - size.Y - 8)
		tip.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	end
	local function hide()
		token += 1
		owner = nil
		local mine = token
		Tween(tip, FAST, { BackgroundTransparency = 1 })
		Tween(tipText, FAST, { TextTransparency = 1 })
		Tween(tipStroke, FAST, { Transparency = 1 })
		task.delay(FAST.Time, function()
			if mine == token then
				tip.Visible = false
			end
		end)
	end

	function Library:_attachTooltip(gui, text)
		if type(text) ~= "string" or text == "" then
			return
		end
		gui.MouseEnter:Connect(function()
			token += 1
			local mine = token
			owner = gui
			task.delay(0.45, function()
				if mine ~= token or owner ~= gui or not gui.Visible then
					return
				end
				tipText.Text = text
				tip.Visible = true
				place()
				Tween(tip, FAST, { BackgroundTransparency = 0 })
				Tween(tipText, FAST, { TextTransparency = 0 })
				Tween(tipStroke, FAST, { Transparency = 0 })
			end)
		end)
		gui.MouseMoved:Connect(function()
			if owner == gui and tip.Visible then
				place()
			end
		end)
		gui.MouseLeave:Connect(function()
			if owner == gui then
				hide()
			end
		end)
	end
end

--// Notifications ------------------------------------------------------------

local NotifyHolder = Create("Frame", {
	Name = "Notifications",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.new(0, 310, 1, -32),
	BackgroundTransparency = 1,
	ZIndex = 50,
	Parent = ScreenGui,
}, {
	Create("UIListLayout", {
		Padding = UDim.new(0, 0), -- spacing lives inside each wrapper so it collapses smoothly
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
	}),
})

function Library:Notify(options)
	if type(options) == "string" then
		options = { Title = options }
	end
	options = options or {}
	if not self.NotificationsEnabled and not options.Force then
		return
	end
	local duration = options.Duration or 4

	local wrapper = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(),
		ZIndex = 50,
		Parent = NotifyHolder,
	}, { Create("UIPadding", { PaddingTop = UDim.new(0, 8) }) })

	local card = Create("Frame", {
		BackgroundColor3 = Theme.Surface,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(320, 0),
		ZIndex = 50,
		Parent = wrapper,
	}, {
		Corner(12),
		Stroke(Theme.Stroke),
	})
	-- Text lives in a padded body so the progress bar and hitbox can sit outside the list flow.
	local body = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 50,
		Parent = card,
	}, {
		Padding(14, 16, 20, 56),
		List(3),
	})

	-- Icon badge: explicit Icon wins, otherwise it follows the notification type.
	local TYPE_ICONS = { success = "circle-check", warning = "triangle-alert", error = "circle-x", info = "info" }
	local badge = Create("Frame", {
		Position = UDim2.fromOffset(14, 13),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Theme.Elevated,
		ZIndex = 51,
		Parent = card,
	}, { Corner(9), Stroke(Theme.Stroke, 0.4) })
	Icon(options.Icon or TYPE_ICONS[options.Type or "info"] or "bell", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		ImageColor3 = Theme.Text,
		ZIndex = 52,
		Parent = badge,
	})
	-- Badge pops in slightly after the card lands.
	local badgeScale = Create("UIScale", { Scale = 0.6, Parent = badge })
	task.delay(0.12, function()
		Tween(badgeScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	end)

	Label({
		Text = options.Title or "Notification",
		FontFace = Fonts.SemiBold,
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		ZIndex = 51,
		Parent = body,
	})

	if options.Content and options.Content ~= "" then
		Label({
			Text = options.Content,
			TextSize = 14,
			TextColor3 = Theme.SubText,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			ZIndex = 51,
			Parent = body,
		})
	end

	local track = Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -9),
		Size = UDim2.new(1, -32, 0, 3),
		BackgroundColor3 = Theme.Elevated,
		BorderSizePixel = 0,
		ZIndex = 51,
		Parent = card,
	}, { Corner(1) })
	local bar = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 52,
		Parent = track,
	}, { Corner(1) })

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		Tween(card, SMOOTH, { Position = UDim2.fromOffset(320, 0) })
		task.wait(0.22)
		local height = wrapper.AbsoluteSize.Y
		wrapper.AutomaticSize = Enum.AutomaticSize.None
		wrapper.Size = UDim2.new(1, 0, 0, height)
		wrapper.ClipsDescendants = true
		Tween(wrapper, SMOOTH, { Size = UDim2.new(1, 0, 0, 0) })
		task.wait(0.3)
		wrapper:Destroy()
	end

	local hit = Create("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 53,
		Parent = card,
	})
	hit.Activated:Connect(function()
		task.spawn(close)
	end)

	-- Countdown pauses while hovered so a notification can actually be read.
	local hovered = false
	hit.MouseEnter:Connect(function()
		hovered = true
	end)
	hit.MouseLeave:Connect(function()
		hovered = false
	end)
	local remaining = duration
	local timer
	timer = RunService.Heartbeat:Connect(function(dt)
		if closed or not wrapper.Parent then
			timer:Disconnect()
			return
		end
		if not hovered then
			remaining -= dt
			bar.Size = UDim2.fromScale(math.max(remaining / duration, 0), 1)
			if remaining <= 0 then
				timer:Disconnect()
				task.spawn(close)
			end
		end
	end)

	Tween(card, SMOOTH, { Position = UDim2.fromOffset(0, 0) })
end

--// Key system ------------------------------------------------------------------
-- Blocking gate shown before the window. Returns true once a key is accepted,
-- false if the user closes it. Accepts a static key list or a Validate function
-- (which may yield, e.g. for an HTTP check) returning ok[, message].

local KEY_FILE = Library.Folder .. "/key.txt"

function Library:KeySystem(options)
	options = options or {}
	local keys = options.Keys or {}
	local function validate(key)
		key = tostring(key or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if key == "" then
			return false, "Enter a key first"
		end
		if type(options.Validate) == "function" then
			local ok, result, message = pcall(options.Validate, key)
			if not ok then
				return false, "Couldn't verify right now"
			end
			return result == true, message
		end
		return table.find(keys, key) ~= nil, nil
	end

	-- A remembered key skips the screen entirely when it is still valid.
	local savedKeyExists = false
	if options.Remember ~= false and FS.available then
		local ok, exists = pcall(FS.isfile, KEY_FILE)
		savedKeyExists = ok and exists == true
	end
	if savedKeyExists then
		local okRead, saved = pcall(FS.readfile, KEY_FILE)
		if okRead and saved and validate(saved) then
			Library:Notify({ Title = "Welcome back", Content = "Your saved key is still valid.", Icon = "shield-check", Type = "success", Duration = 3 })
			return true
		end
	end

	self._keyPromptActive = true
	self:_syncMenuCursor()

	local TextService = game:GetService("TextService")
	local Lighting = game:GetService("Lighting")

	-- Neutral palette: greys and white; colour is reserved for state (error, success) and the
	-- small gold mark on the paid option.
	local P = {
		Card = Color3.fromRGB(11, 11, 12),
		Panel = Color3.fromRGB(17, 17, 19),
		Field = Color3.fromRGB(19, 19, 21),
		Raised = Color3.fromRGB(26, 26, 29),
		Line = Color3.fromRGB(36, 36, 40),
		LineSoft = Color3.fromRGB(28, 28, 31),
		Focus = Color3.fromRGB(92, 92, 100),
		Accent = typeof(options.Accent) == "Color3" and options.Accent or Color3.fromRGB(47, 107, 255),
		AccentHover = Color3.fromRGB(78, 132, 255),
		AccentSoft = Color3.fromRGB(150, 184, 255),
		Text = Color3.fromRGB(244, 244, 245),
		Sub = Color3.fromRGB(190, 190, 197),
		Muted = Color3.fromRGB(122, 122, 131),
		Ink = Color3.fromRGB(10, 10, 11),
		Button = Color3.fromRGB(244, 244, 245),
		ButtonHover = Color3.fromRGB(216, 216, 220),
		Gold = Color3.fromRGB(232, 190, 110),
		Error = Color3.fromRGB(242, 120, 120),
		Success = Color3.fromRGB(110, 214, 150),
	}

	local function viewportSize()
		local cam = Workspace.CurrentCamera
		local size = ScreenGui.AbsoluteSize
		if size.X < 1 then size = cam and cam.ViewportSize or Vector2.new(1280, 720) end
		return size
	end
	local NOTICE = (type(options.Requirement) == "string" and options.Requirement ~= "") and 34 or 0
	local WIDE = options.Layout ~= "compact" and viewportSize().X >= 760
	local SIDE = WIDE and 324 or 0 -- inset panel width (incl. its 8px margin)
	local CARD = Vector2.new(WIDE and 780 or 440, (WIDE and 446 or 522) + NOTICE)
	local FX = WIDE and SIDE + 40 or 36
	local FW = CARD.X - FX - (WIDE and 40 or 36)
	local TOP = WIDE and 0 or 76 -- room for the brand row in the single-column layout

	local done = Instance.new("BindableEvent")
	local result = false
	local closing = false
	local connections = {}
	local function bind(signal, fn)
		local c = signal:Connect(fn)
		table.insert(connections, c)
		return c
	end
	local function setIcon(image, name)
		local data = resolveIcon(name)
		if data then
			image.Image = "rbxassetid://" .. data[1]
			image.ImageRectOffset = Vector2.new(data[2], data[3])
			image.ImageRectSize = data[4] ~= 0 and Vector2.new(48, 48) or Vector2.zero
		end
	end
	local function ease(t, style, direction)
		return TweenInfo.new(t, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out)
	end

	-- Backdrop: the game stays visible but blurred and dimmed, like frosted glass.
	local root = Create("Frame", {
		Name = "KeySystem",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 70,
		Parent = ScreenGui,
	})
	local backdrop = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(6, 6, 7),
		BackgroundTransparency = 1,
		Active = true, -- swallow clicks meant for the game behind
		ZIndex = 70,
		Parent = root,
	})
	Library:_blockWheel(backdrop)
	local blur
	if options.Blur ~= false then
		pcall(function()
			blur = Instance.new("BlurEffect")
			blur.Name = "CrownKeyBlur"
			blur.Size = 0
			blur.Parent = Lighting
		end)
	end

	local viewport = Create("ScrollingFrame", {
		Name = "KeyViewport", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 1, -24),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.None,
		ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3,
		ScrollBarImageColor3 = P.Muted, Active = true, ZIndex = 71, Parent = root,
	})
	local holder = Create("Frame", {
		Name = "CardHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		BackgroundTransparency = 1,
		ZIndex = 71,
		Parent = viewport,
	})
	local cardScale = Create("UIScale", { Parent = holder })
	local shadow = Create("ImageLabel", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 12),
		Size = UDim2.new(1, 100, 1, 100),
		BackgroundTransparency = 1,
		Image = "rbxassetid://6014261993",
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(49, 49, 450, 450),
		ZIndex = 70,
		Parent = holder,
	})
	local card = Create("CanvasGroup", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = P.Card,
		GroupTransparency = 1,
		ZIndex = 71,
		Parent = holder,
	}, { Corner(18) })
	local cardStroke = Stroke(P.Line, 0)
	cardStroke.Parent = card

	local function text(props)
		props.ZIndex = props.ZIndex or 74
		props.Parent = props.Parent or card
		return Label(props)
	end
	local animated = {} -- rows that fade/rise in on entrance

	-- Brand logo: a 52px tile at ZIndex 72 (hosts may swap in their own logo image).
	local logo, logoScale, lockIcon
	local function buildLogo(parent, position)
		logo = Create("Frame", {
			Position = position,
			Size = UDim2.fromOffset(52, 52),
			BackgroundColor3 = P.Raised,
			ZIndex = 72,
			Parent = parent,
		}, { Corner(14) })
		logoScale = Create("UIScale", { Scale = 0.8, Parent = logo })
		local lockBadge = Create("Frame", {
			Position = UDim2.fromOffset(36, 36),
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = P.Raised,
			ZIndex = 74,
			Parent = logo,
		}, { Corner(12), Create("UIStroke", { Color = WIDE and P.Panel or P.Card, Thickness = 3 }) })
		lockIcon = Icon("lock", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(12, 12),
			ImageColor3 = P.Sub,
			ZIndex = 75,
			Parent = lockBadge,
		})
		Brand(logo, options.Logo or "N", 52, 24, 73, true)
	end

	-- Showcase panel (wide layout): an inset "bento" panel with the brand and what you get.
	local promoButton
	local showcase
	if WIDE then
		showcase = Create("Frame", {
			Name = "Showcase",
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(SIDE - 8, CARD.Y - 16),
			BackgroundColor3 = P.Panel,
			ZIndex = 72,
			Parent = card,
		}, { Corner(10), Stroke(P.LineSoft, 0) })
		-- one faint light from the top-left corner, nothing more
		Create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = P.Accent,
			BorderSizePixel = 0,
			ZIndex = 72,
			Parent = showcase,
		}, {
			Corner(10),
			Create("UIGradient", {
				Rotation = 50,
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.84), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1) }),
			}),
		})
		local inner = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 73, Parent = showcase })
		table.insert(animated, inner)
		buildLogo(inner, UDim2.fromOffset(26, 26))
		text({ Parent = inner, Text = options.Title or "Welcome to Crown Hub", FontFace = Fonts.Bold, TextSize = 17, Position = UDim2.fromOffset(90, 31), Size = UDim2.fromOffset(SIDE - 120, 20) })
		text({ Parent = inner, Text = options.Kicker or "Key system", TextSize = 13, TextColor3 = P.Muted, Position = UDim2.fromOffset(90, 52), Size = UDim2.fromOffset(SIDE - 120, 18) })

		local headline = options.Headline or "Unlock the\nfull experience."
		local first, second = headline:match("^(.-)\n(.*)$")
		local baseY = 190
		text({
			Parent = inner, Text = first or headline, FontFace = Fonts.Bold, TextSize = 28,
			Position = UDim2.fromOffset(26, baseY - 70), Size = UDim2.fromOffset(SIDE - 60, 34), TextTruncate = Enum.TextTruncate.None,
		})
		if second then
			text({
				Parent = inner, Text = second, FontFace = Fonts.Bold, TextSize = 28, TextColor3 = P.AccentSoft,
				Position = UDim2.fromOffset(26, baseY - 38), Size = UDim2.fromOffset(SIDE - 60, 34), TextTruncate = Enum.TextTruncate.None,
			})
		end
		local perks = type(options.Perks) == "table" and options.Perks or { "Checked in seconds", "Remembered on this device", "Works on PC and mobile" }
		for i, perk in ipairs(perks) do
			if i > 4 then break end
			local row = Create("Frame", {
				Position = UDim2.fromOffset(26, baseY + 22 + (i - 1) * 30),
				Size = UDim2.fromOffset(SIDE - 60, 22),
				BackgroundTransparency = 1,
				ZIndex = 74,
				Parent = inner,
			})
			local tick = Create("Frame", { Position = UDim2.fromOffset(0, 1), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = P.Accent, BackgroundTransparency = 0.82, ZIndex = 75, Parent = row }, { Corner(6) })

			Icon("check", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 12), ImageColor3 = P.AccentSoft, ZIndex = 76, Parent = tick })
			text({ Parent = row, Text = perk, TextSize = 14, TextColor3 = P.Sub, Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -30, 1, 0) })
		end
		-- Premium call-to-action (only when the host sells keys)
		if type(options.BuyLink) == "string" and options.BuyLink ~= "" then
			local promo = Create("TextButton", {
				Name = "Promo", Position = UDim2.new(0, 26, 1, -124), Size = UDim2.new(1, -52, 0, 52),
				BackgroundColor3 = P.Card, Text = "", AutoButtonColor = false, ZIndex = 75, Parent = inner,
			}, { Corner(10) })
			local promoStroke = Create("UIStroke", { Color = P.Gold, Transparency = 0.6, Parent = promo })
			Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.Gold, BorderSizePixel = 0, ZIndex = 75, Parent = promo }, {
				Corner(10),
				Create("UIGradient", { Rotation = 0, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.98) }) }),
			})
			local star = Create("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = P.Gold, BackgroundTransparency = 0.84, ZIndex = 76, Parent = promo }, { Corner(8) })
			local starIcon = Icon("sparkles", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(14, 14), ImageColor3 = P.Gold, ZIndex = 77, Parent = star })
			text({ Parent = promo, Text = options.PromoTitle or "Go Premium", FontFace = Fonts.Bold, TextSize = 14, Position = UDim2.fromOffset(50, 9), Size = UDim2.new(1, -140, 0, 16), ZIndex = 77 })
			text({ Parent = promo, Text = options.PromoText or options.BuyNote or "Skip every checkpoint", TextSize = 12, TextColor3 = P.Muted, Position = UDim2.fromOffset(50, 29), Size = UDim2.new(1, -140, 0, 14), ZIndex = 77 })
			local shopPill = Create("Frame", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(0, 26),
				AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = P.Gold, ZIndex = 77, Parent = promo,
			}, {
				Corner(13), Padding(0, 10, 0, 10),
				Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			Label({ Text = options.ShopButton or "Shop", FontFace = Fonts.Bold, TextSize = 12, TextColor3 = Color3.fromRGB(34, 23, 4), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, TextTruncate = Enum.TextTruncate.None, LayoutOrder = 1, ZIndex = 78, Parent = shopPill })
			local shopArrow = Icon("arrow-right", { Size = UDim2.fromOffset(12, 12), ImageColor3 = Color3.fromRGB(34, 23, 4), LayoutOrder = 2, ZIndex = 78, Parent = shopPill })
			local promoScale = Create("UIScale", { Parent = promo })
			local pillLayout = shopPill:FindFirstChildWhichIsA("UIListLayout")
			promo.MouseEnter:Connect(function()
				Tween(promoStroke, FAST, { Transparency = 0.2 })
				Tween(pillLayout, FAST, { Padding = UDim.new(0, 6) })
			end)
			promo.MouseLeave:Connect(function()
				Tween(promoStroke, FAST, { Transparency = 0.6 })
				Tween(pillLayout, FAST, { Padding = UDim.new(0, 4) })
				Tween(promoScale, FAST, { Scale = 1 })
			end)
			promo.MouseButton1Down:Connect(function() Tween(promoScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad), { Scale = 0.97 }) end)
			promo.MouseButton1Up:Connect(function() Tween(promoScale, BOUNCE, { Scale = 1 }) end)
			promoButton = promo
		end
		-- who is unlocking, pinned to the bottom
		Create("Frame", {
			Position = UDim2.new(0, 26, 1, -58), Size = UDim2.new(1, -52, 0, 1),
			BackgroundColor3 = P.Line, BorderSizePixel = 0, ZIndex = 74, Parent = inner,
		})
		local avatar = Create("ImageLabel", {
			Position = UDim2.new(0, 26, 1, -40), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = P.Raised, ZIndex = 75, Parent = inner,
		}, { Corner(11) })
		task.spawn(function()
			local ok, image = pcall(function()
				return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
			end)
			if ok and avatar.Parent then avatar.Image = image end
		end)
		text({
			Parent = inner, RichText = true, TextSize = 13,
			Text = '<font color="#7A7A83">Playing as</font> ' .. LocalPlayer.DisplayName,
			Position = UDim2.new(0, 56, 1, -41), Size = UDim2.new(1, -82, 0, 24),
		})
	end

	-- Form ------------------------------------------------------------------------------------
	local function y(offset) return offset + NOTICE + TOP end
	local function row(props) -- a positioned child of the card that animates in
		props.Parent = card
		props.ZIndex = props.ZIndex or 74
		local inst = Create(props.Class or "Frame", (function() props.Class = nil; return props end)())
		table.insert(animated, inst)
		return inst
	end

	local close = Create("TextButton", {
		Position = UDim2.fromOffset(CARD.X - 46, 14),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = P.Raised,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 76,
		Parent = card,
	}, { Corner(8) })
	local closeIcon = Icon("x", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(15, 15),
		ImageColor3 = P.Muted, ZIndex = 77, Parent = close,
	})
	close.MouseEnter:Connect(function()
		Tween(close, FAST, { BackgroundTransparency = 0 })
		Tween(closeIcon, FAST, { ImageColor3 = P.Text })
	end)
	close.MouseLeave:Connect(function()
		Tween(close, FAST, { BackgroundTransparency = 1 })
		Tween(closeIcon, FAST, { ImageColor3 = P.Muted })
	end)

	if not WIDE then
		local brandRow = row({ Position = UDim2.fromOffset(FX, 30), Size = UDim2.fromOffset(FW, 52), BackgroundTransparency = 1 })
		buildLogo(brandRow, UDim2.fromOffset(0, 0))
		text({ Parent = brandRow, Text = options.Title or "Welcome to Crown Hub", FontFace = Fonts.Bold, TextSize = 17, Position = UDim2.fromOffset(64, 6), Size = UDim2.fromOffset(FW - 100, 20) })
		text({ Parent = brandRow, Text = options.Kicker or "Key system", TextSize = 13, TextColor3 = P.Muted, Position = UDim2.fromOffset(64, 27), Size = UDim2.fromOffset(FW - 100, 18) })
	end

	-- Heading: title, then the game in one quiet line
	local heading = row({ Position = UDim2.fromOffset(FX, y(46)), Size = UDim2.fromOffset(FW, 60), BackgroundTransparency = 1 })
	text({ Parent = heading, Text = options.FormTitle or "Enter your key", FontFace = Fonts.Bold, TextSize = 24, Size = UDim2.fromOffset(FW - 40, 30) })
	local gameLine = Create("Frame", {
		Position = UDim2.fromOffset(0, 36), Size = UDim2.fromOffset(FW, 20), BackgroundTransparency = 1, ZIndex = 74, Parent = heading,
	}, { Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }) })
	Create("ImageLabel", {
		Size = UDim2.fromOffset(16, 16), BackgroundColor3 = P.Raised, LayoutOrder = 1, ZIndex = 75, Parent = gameLine,
		Image = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150",
	}, { Corner(5) })
	Label({
		Text = options.Subtitle or "This game", TextSize = 14, TextColor3 = P.Muted, Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X, TextTruncate = Enum.TextTruncate.None, LayoutOrder = 2, ZIndex = 75, Parent = gameLine,
	})

	if NOTICE > 0 then
		local badge = row({
			Name = "Requirement", Position = UDim2.fromOffset(FX, TOP + 116), Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = P.Raised,
		})
		Corner(12).Parent = badge
		Stroke(P.Line, 0).Parent = badge
		Padding(0, 10, 0, 8).Parent = badge
		Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = badge })
		Icon(options.RequirementIcon or "user", { Size = UDim2.fromOffset(13, 13), ImageColor3 = P.Sub, LayoutOrder = 1, ZIndex = 75, Parent = badge })
		Label({
			Text = options.Requirement, FontFace = Fonts.Medium, TextSize = 13, TextColor3 = P.Text,
			Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, TextTruncate = Enum.TextTruncate.None,
			LayoutOrder = 2, ZIndex = 75, Parent = badge,
		})
	end

	-- Key field
	local field = row({ Position = UDim2.fromOffset(FX, y(126)), Size = UDim2.fromOffset(FW, 48), BackgroundColor3 = P.Field })
	Corner(11).Parent = field
	local fieldStroke = Stroke(P.Line)
	fieldStroke.Parent = field
	local fieldIcon = Icon("key-round", { Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(16, 16), ImageColor3 = P.Muted, ZIndex = 75, Parent = field })

	local input = Create("TextBox", {
		Position = UDim2.fromOffset(44, 0),
		Size = UDim2.new(1, -56, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = options.Placeholder or "Paste your key here",
		PlaceholderColor3 = P.Muted,
		TextColor3 = P.Text,
		FontFace = Fonts.Medium,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ClearTextOnFocus = false,
		ZIndex = 75,
		Parent = field,
	})
	local getclipboard = envFunction("getclipboard") or envFunction("fromclipboard")
	if getclipboard then
		input.Size = UDim2.new(1, -122, 1, 0)
		local paste = Create("TextButton", {
			Position = UDim2.new(1, -74, 0, 9), Size = UDim2.fromOffset(64, 30), BackgroundColor3 = P.Raised,
			Text = "Paste", FontFace = Fonts.Medium, TextSize = 13, TextColor3 = P.Sub, AutoButtonColor = false, ZIndex = 75, Parent = field,
		}, { Corner(8) })
		paste.MouseEnter:Connect(function() Tween(paste, FAST, { BackgroundColor3 = P.Line, TextColor3 = P.Text }) end)
		paste.MouseLeave:Connect(function() Tween(paste, FAST, { BackgroundColor3 = P.Raised, TextColor3 = P.Sub }) end)
		paste.Activated:Connect(function()
			local ok, value = pcall(getclipboard)
			if ok and type(value) == "string" and value ~= "" then
				input.Text = value:gsub("^%s+", ""):gsub("%s+$", "")
			end
		end)
	end
	local progressTrack = Create("Frame", {
		Position = UDim2.new(0, 12, 1, -2), Size = UDim2.new(1, -24, 0, 1), BackgroundTransparency = 1,
		ClipsDescendants = true, ZIndex = 76, Parent = field,
	})
	local progressBar = Create("Frame", {
		Size = UDim2.fromScale(0.3, 1), Position = UDim2.fromScale(-0.3, 0), BackgroundColor3 = P.Accent,
		BorderSizePixel = 0, Visible = false, ZIndex = 77, Parent = progressTrack,
	})
	local progressRunning = false
	local function setProgress(running)
		progressRunning = running
		progressBar.Visible = running
		if running then
			task.spawn(function()
				while progressRunning and progressBar.Parent do
					progressBar.Position = UDim2.fromScale(-0.3, 0)
					Tween(progressBar, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Position = UDim2.fromScale(1, 0) }).Completed:Wait()
				end
			end)
		end
	end

	-- Primary button: solid light, dark text. The only bright surface on the card.
	local continueButton = row({
		Class = "TextButton", Position = UDim2.fromOffset(FX, y(184)), Size = UDim2.fromOffset(FW, 48),
		BackgroundColor3 = P.Accent, Text = "", AutoButtonColor = false, ZIndex = 75,
	})
	Corner(11).Parent = continueButton
	local continueScale = Create("UIScale", { Parent = continueButton })
	local continueContent = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 77, Parent = continueButton,
	})
	local continueLayout = Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = continueContent })
	local SUBMIT = options.SubmitButton or "Continue"
	local continueLabel = Label({
		Text = SUBMIT, FontFace = Fonts.Bold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, TextTruncate = Enum.TextTruncate.None,
		LayoutOrder = 1, ZIndex = 78, Parent = continueContent,
	})
	local continueGlyph = Icon("arrow-right", { Size = UDim2.fromOffset(16, 16), ImageColor3 = Color3.new(1, 1, 1), LayoutOrder = 2, ZIndex = 78, Parent = continueContent })
	-- a soft top highlight gives the button a little depth
	Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 76, Parent = continueButton }, {
		Corner(11),
		Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1) }) }),
	})
	continueButton.ClipsDescendants = true
	local busySweep = Create("Frame", {
		Position = UDim2.fromScale(-0.4, 0), Size = UDim2.fromScale(0.4, 1), BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.8, BorderSizePixel = 0, Visible = false, ZIndex = 77, Parent = continueButton,
	}, { Create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }) })
	local sweeping = false
	local function setSweep(on)
		sweeping = on
		busySweep.Visible = on
		if on then
			task.spawn(function()
				while sweeping and busySweep.Parent do
					busySweep.Position = UDim2.fromScale(-0.4, 0)
					Tween(busySweep, TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Position = UDim2.fromScale(1, 0) }).Completed:Wait()
				end
			end)
		end
	end
	continueButton.MouseEnter:Connect(function()
		Tween(continueButton, FAST, { BackgroundColor3 = P.AccentHover })
		Tween(continueLayout, FAST, { Padding = UDim.new(0, 12) })
	end)
	continueButton.MouseLeave:Connect(function()
		Tween(continueButton, FAST, { BackgroundColor3 = P.Accent })
		Tween(continueLayout, FAST, { Padding = UDim.new(0, 8) })
		Tween(continueScale, FAST, { Scale = 1 })
	end)
	continueButton.MouseButton1Down:Connect(function() Tween(continueScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad), { Scale = 0.97 }) end)
	continueButton.MouseButton1Up:Connect(function() Tween(continueScale, BOUNCE, { Scale = 1 }) end)

	-- Remember (left) + a short note (right); messages appear under the key field.
	local remember = options.Remember ~= false and FS.available
	local rememberRow = row({ Class = "TextButton", Position = UDim2.fromOffset(FX, y(244)), Size = UDim2.fromOffset(150, 20), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Visible = FS.available, ZIndex = 75 })
	local rememberBox = Create("Frame", { Position = UDim2.fromOffset(0, 2), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = P.Accent, ZIndex = 76, Parent = rememberRow }, { Corner(5) })
	local rememberStroke = Stroke(P.Accent)
	rememberStroke.Parent = rememberBox
	local rememberMark = Icon("check", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 12), ImageColor3 = Color3.new(1, 1, 1), ZIndex = 77, Parent = rememberBox })
	local rememberScale = Create("UIScale", { Parent = rememberMark })
	Label({ Text = "Remember my key", TextSize = 13, TextColor3 = P.Sub, Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -24, 1, 0), ZIndex = 76, Parent = rememberRow })
	local function paintRemember()
		Tween(rememberBox, FAST, { BackgroundColor3 = remember and P.Accent or P.Field })
		Tween(rememberStroke, FAST, { Color = remember and P.Accent or P.Line })
		Tween(rememberScale, remember and BOUNCE or FAST, { Scale = remember and 1 or 0 })
	end
	local rememberBoxScale = Create("UIScale", { Parent = rememberBox })
	rememberRow.Activated:Connect(function()
		remember = not remember
		paintRemember()
	end)
	paintRemember()

	local statusRow = row({
		Position = UDim2.fromOffset(FS.available and FX + 160 or FX, y(244)), Size = UDim2.fromOffset(FS.available and FW - 160 or FW, 20),
		BackgroundTransparency = 1, ZIndex = 75,
	})
	local statusContent = Create("Frame", {
		AnchorPoint = Vector2.new(FS.available and 1 or 0.5, 0), Position = UDim2.fromScale(FS.available and 1 or 0.5, 0),
		Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 75, Parent = statusRow,
	}, { Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local statusIcon = Icon("shield-check", { Size = UDim2.fromOffset(13, 13), ImageColor3 = P.Muted, LayoutOrder = 1, ZIndex = 76, Parent = statusContent })
	local statusText = Label({
		Text = options.Note or "Checked instantly", TextSize = 13, TextColor3 = P.Muted, Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X, TextTruncate = Enum.TextTruncate.None, LayoutOrder = 2, ZIndex = 76, Parent = statusContent,
	})
	-- Notifications: a small stack in the bottom-right corner of the screen, outside the card,
	-- so nothing inside the card ever moves or gets covered.
	local GuiService = game:GetService("GuiService")
	local okInset, inset = pcall(function() return GuiService:GetGuiInset().Y end)
	-- Bottom-right: the top-right corner belongs to Roblox's player list, which draws over us.
	local stack = Create("Frame", {
		Name = "KeyNotifications", AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(320, 420),
		BackgroundTransparency = 1, ZIndex = 90, Parent = root,
	}, { Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Bottom }) })
	local live, order, helperShown = {}, 0, nil
	local function dismiss(item)
		if item.gone then return end
		item.gone = true
		for i, other in ipairs(live) do
			if other == item then table.remove(live, i) break end
		end
		Tween(item.group, ease(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { GroupTransparency = 1, Position = UDim2.fromOffset(24, 0) })
		task.delay(0.18, function()
			Tween(item.wrap, ease(0.2), { Size = UDim2.fromOffset(320, 0) })
			task.delay(0.2, function() item.wrap:Destroy() end)
		end)
	end
	local function clearHelper()
		helperShown = nil
		for i = #live, 1, -1 do dismiss(live[i]) end
	end
	local function notify(title, body, icon, color, hold)
		order += 1 -- newest at the bottom, nearest the corner
		local bodyH = 0
		if body and body ~= "" then
			local ok, size = pcall(function() return TextService:GetTextSize(body, 13, Enum.Font.GothamMedium, Vector2.new(320 - 76, 200)) end)
			bodyH = math.min(ok and size.Y or 18, 54) + 2
		end
		local H = math.max(56, 16 + 18 + (bodyH > 0 and (2 + bodyH) or 0) + 16)
		local wrap = Create("Frame", { Size = UDim2.fromOffset(320, H), BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 90, Parent = stack })
		local group = Create("CanvasGroup", {
			Position = UDim2.fromOffset(28, 0), Size = UDim2.fromOffset(320, H), BackgroundColor3 = P.Panel,
			GroupTransparency = 1, ZIndex = 90, Parent = wrap,
		}, { Corner(12), Stroke(P.Line, 0) })
		local badge = Create("Frame", {
			Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = color,
			BackgroundTransparency = 0.86, ZIndex = 91, Parent = group,
		}, { Corner(9) })
		local glyph = Icon(icon, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), ImageColor3 = color, ZIndex = 92, Parent = badge })
		Label({ Text = title, FontFace = Fonts.Bold, TextSize = 14, TextColor3 = P.Text, Position = UDim2.fromOffset(58, 15), Size = UDim2.fromOffset(320 - 76, 18), ZIndex = 92, Parent = group })
		if bodyH > 0 then
			Label({
				Text = body, TextSize = 13, TextColor3 = P.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
				TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(58, 35), Size = UDim2.fromOffset(320 - 76, bodyH),
				ZIndex = 92, Parent = group,
			})
		end
		local bar = Create("Frame", { Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = color, BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 92, Parent = group })
		local hit = Create("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 93, Parent = group })
		local item = { wrap = wrap, group = group, color = color }
		table.insert(live, item)
		while #live > 3 do dismiss(live[1]) end
		hit.Activated:Connect(function() dismiss(item) end)
		for _, d in ipairs(wrap:GetDescendants()) do d:SetAttribute("NoTheme", true); d:SetAttribute("NoGradient", true) end
		Tween(group, ease(0.32), { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) })
		local duration = hold or 4.5
		Tween(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) })
		task.delay(duration, function()
			if not closing then dismiss(item) end
		end)
		return item
	end
	-- "Invalid key. Get a new one on the website." -> title "Invalid key" + the rest as the body.
	local function setStatus(message, icon, color, hold)
		if icon == "loader-circle" then return end -- the button already says "Checking…"
		message = tostring(message or "")
		color = color or P.Sub
		helperShown = color
		local title, body = message:match("^(.-)%.%s+(.+)$")
		if not title then title, body = message:gsub("%.$", ""), nil end
		if color == P.Sub then color = P.Accent end
		notify(title, body, icon, color, hold or (color == P.Error and 6 or nil))
	end

	-- "Don't have a key?" + the two ways to get one
	local dividerY = y(286)
	local dividerText = options.OptionsTitle or "Don't have a key?"
	local okWidth, measured = pcall(function() return TextService:GetTextSize(dividerText, 13, Enum.Font.GothamMedium, Vector2.new(400, 20)).X end)
	local gap = (okWidth and measured or 120) + 26
	local divider = row({ Position = UDim2.fromOffset(FX, dividerY), Size = UDim2.fromOffset(FW, 18), BackgroundTransparency = 1 })
	for side = 0, 1 do
		Create("Frame", {
			Position = UDim2.fromOffset(side == 0 and 0 or math.floor((FW + gap) / 2), 9),
			Size = UDim2.fromOffset(math.floor((FW - gap) / 2), 1),
			BackgroundColor3 = P.Line, BorderSizePixel = 0, ZIndex = 74, Parent = divider,
		})
	end
	text({ Parent = divider, Text = dividerText, TextSize = 13, TextColor3 = P.Muted, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) })

	local function optionTile(x, width, title, subtitle, icon, featured)
		local tile = row({
			Class = "TextButton", Position = UDim2.fromOffset(x, y(316)), Size = UDim2.fromOffset(width, 62),
			BackgroundColor3 = P.Field, Text = "", AutoButtonColor = false,
		})
		Corner(12).Parent = tile
		local tileStroke = Stroke(featured and P.Gold or P.Line, featured and 0.7 or 0)
		tileStroke.Parent = tile
		local pressScale = Create("UIScale", { Parent = tile })
		local badge = Create("Frame", {
			Position = UDim2.fromOffset(12, 13), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = P.Raised, ZIndex = 75, Parent = tile,
		}, { Corner(9) })
		local glyph = Icon(icon, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16),
			ImageColor3 = featured and P.Gold or P.Sub, ZIndex = 76, Parent = badge,
		})
		local badgeScale = Create("UIScale", { Parent = badge })
		Label({ Text = title, FontFace = Fonts.Bold, TextSize = 15, TextColor3 = P.Text, Position = UDim2.fromOffset(60, 12), Size = UDim2.fromOffset(width - 84, 20), ZIndex = 76, Parent = tile })
		Label({ Text = subtitle, TextSize = 13, TextColor3 = featured and P.Gold or P.Muted, Position = UDim2.fromOffset(60, 32), Size = UDim2.fromOffset(width - 84, 18), ZIndex = 76, Parent = tile })
		local arrow = Icon("arrow-up-right", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(14, 14),
			ImageColor3 = P.Muted, ZIndex = 76, Parent = tile,
		})
		if not resolveIcon("arrow-up-right") then setIcon(arrow, "external-link") end
		tile.MouseEnter:Connect(function()
			Tween(tile, FAST, { BackgroundColor3 = P.Raised })
			Tween(tileStroke, FAST, { Color = featured and P.Gold or P.Focus, Transparency = featured and 0.3 or 0 })
			Tween(arrow, FAST, { ImageColor3 = P.Text, Position = UDim2.new(1, -9, 0, 9) })
		end)
		tile.MouseLeave:Connect(function()
			Tween(tile, FAST, { BackgroundColor3 = P.Field })
			Tween(tileStroke, FAST, { Color = featured and P.Gold or P.Line, Transparency = featured and 0.7 or 0 })
			Tween(arrow, FAST, { ImageColor3 = P.Muted, Position = UDim2.new(1, -12, 0, 12) })
			Tween(pressScale, FAST, { Scale = 1 })
		end)
		tile.MouseButton1Down:Connect(function() Tween(pressScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad), { Scale = 0.97 }) end)
		tile.MouseButton1Up:Connect(function() Tween(pressScale, BOUNCE, { Scale = 1 }) end)
		return tile
	end
	local buyLink = type(options.BuyLink) == "string" and options.BuyLink ~= "" and options.BuyLink or nil
	local tileWidth = buyLink and math.floor((FW - 10) / 2) or FW
	local getButton = optionTile(FX, tileWidth, options.KeyButton or "Get key", options.KeyNote or "Free · 1 minute", "key-round", false)
	local buyButton = buyLink and optionTile(FX + tileWidth + 10, FW - tileWidth - 10, options.BuyButton or "Buy key", options.BuyNote or "Instant access", "sparkles", true)

	-- Footer
	local footer = row({ Position = UDim2.fromOffset(FX, CARD.Y - 44), Size = UDim2.fromOffset(FW, 20), BackgroundTransparency = 1 })
	text({ Parent = footer, Text = options.Footer or ((options.Title or "Crown Hub") .. " key system"), TextSize = 12, TextColor3 = P.Muted, Size = UDim2.new(1, -60, 1, 0) })
	text({ Parent = footer, Text = options.Version or "v1.0", TextSize = 12, TextColor3 = P.Muted, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromScale(1, 1) })

	-- Everything here uses its own palette: keep the theme engine's hands off.
	for _, d in ipairs(root:GetDescendants()) do
		d:SetAttribute("NoTheme", true)
		d:SetAttribute("NoGradient", true)
	end

	-- Fitting -----------------------------------------------------------------------------------
	local entrance
	local function place()
		if closing or not root.Parent then return end
		local vp = root.AbsoluteSize
		if vp.X < 1 or vp.Y < 1 then vp = viewportSize() end
		local width, height = math.max(1, vp.X - 24), math.max(1, vp.Y - 24)
		local fit = math.max(0.05, math.min(width / CARD.X, height / CARD.Y, 1))
		local visibleHeight = height
		pcall(function()
			if UserInputService.OnScreenKeyboardVisible then
				local top = UserInputService.OnScreenKeyboardPosition.Y
				if top <= 0 then top = vp.Y - UserInputService.OnScreenKeyboardSize.Y end
				visibleHeight = math.clamp(top - root.AbsolutePosition.Y - 24, 1, height)
			end
		end)
		if entrance then entrance:Cancel(); entrance = nil end
		holder:SetAttribute("Fit", fit)
		cardScale.Scale = fit
		viewport.Size = UDim2.fromOffset(width, visibleHeight)
		local contentHeight = math.ceil(CARD.Y * fit)
		viewport.CanvasSize = UDim2.fromOffset(0, math.max(contentHeight, visibleHeight))
		viewport.ScrollingEnabled = contentHeight > visibleHeight
		holder.Position = UDim2.fromOffset(math.floor(width / 2), math.max(0, math.floor((visibleHeight - contentHeight) / 2)))
		if contentHeight > visibleHeight then
			viewport.CanvasPosition = Vector2.new(0, math.clamp((126 + NOTICE + TOP) * fit - 16, 0, contentHeight - visibleHeight))
		else
			viewport.CanvasPosition = Vector2.new(0, 0)
		end
	end
	place()
	bind(root:GetPropertyChangedSignal("AbsoluteSize"), place)
	for _, property in ipairs({ "OnScreenKeyboardVisible", "OnScreenKeyboardPosition", "OnScreenKeyboardSize" }) do
		pcall(function() bind(UserInputService:GetPropertyChangedSignal(property), place) end)
	end

	-- Interaction ----------------------------------------------------------------------------
	local hadText = false
	input:GetPropertyChangedSignal("Text"):Connect(function()
		hadText = input.Text:match("%S") ~= nil
		if helperShown == P.Error then clearHelper() end
		if fieldStroke.Color == P.Error then
			Tween(fieldStroke, FAST, { Color = input:IsFocused() and P.Accent or P.Line })
		end
	end)
	input.Focused:Connect(function()
		Tween(fieldStroke, FAST, { Color = P.Accent })
		Tween(fieldIcon, FAST, { ImageColor3 = P.AccentSoft })
	end)
	input.FocusLost:Connect(function(enter)
		Tween(fieldStroke, FAST, { Color = P.Line })
		Tween(fieldIcon, FAST, { ImageColor3 = input.Text ~= "" and P.Sub or P.Muted })
		if enter and input.Text:match("%S") then
			task.spawn(function() continueButton:SetAttribute("Submit", os.clock()) end)
		end
	end)

	local function shake()
		local home = holder.Position
		for _, dx in ipairs({ -8, 7, -5, 3, -1, 0 }) do
			Tween(holder, TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Position = home + UDim2.fromOffset(dx, 0) })
			task.wait(0.05)
		end
		holder.Position = home
	end

	-- Closing: the card dissolves (it is a CanvasGroup, so everything fades together) while it
	-- sinks and shrinks a touch; on success it lifts and grows instead. Blur and dim follow.
	local function finish(accepted)
		if closing then return end
		closing = true
		if entrance then entrance:Cancel(); entrance = nil end
		input:ReleaseFocus()
		result = accepted
		for _, c in ipairs(connections) do c:Disconnect() end
		clearHelper()
		local fit = holder:GetAttribute("Fit") or 1
		local home = holder.Position
		local t = accepted and 0.38 or 0.3
		local style = accepted and Enum.EasingStyle.Quint or Enum.EasingStyle.Quad
		Tween(card, ease(t, style, Enum.EasingDirection.In), { GroupTransparency = 1 })
		Tween(shadow, ease(t * 0.8), { ImageTransparency = 1 })
		Tween(cardScale, ease(t, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Scale = fit * (accepted and 1.04 or 0.94) })
		Tween(holder, ease(t, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = home + UDim2.fromOffset(0, accepted and -10 or 14) })
		task.delay(t * 0.45, function()
			Tween(backdrop, ease(0.36, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 })
			if blur then Tween(blur, ease(0.4, Enum.EasingStyle.Quad), { Size = 0 }) end
		end)
		task.delay(t * 0.45 + 0.42, function()
			if blur then blur:Destroy() end
			root:Destroy()
			done:Fire()
		end)
	end

	local busy, failures = false, 0
	local function submit()
		if busy or closing then return end
		if not input.Text:match("%S") then
			setStatus("Paste your key first", "info", P.Sub, 3)
			return
		end
		busy = true
		setProgress(true)
		setSweep(true)
		continueLabel.Text = "Checking…"
		setIcon(continueGlyph, "loader-circle")
		local spinning = true
		task.spawn(function()
			while spinning and continueGlyph.Parent do
				continueGlyph.Rotation = (continueGlyph.Rotation + 10) % 360
				RunService.RenderStepped:Wait()
			end
			continueGlyph.Rotation = 0
		end)
		setStatus("Verifying your key…", "loader-circle")
		task.wait(0.35) -- a beat of feedback even for instant local checks
		local key = input.Text
		local ok, message = validate(key)
		if closing then spinning = false; return end
		spinning = false
		setProgress(false)
		setSweep(false)
		if ok then
			if remember and FS.writefile then
				pcall(function()
					if not FS.isfolder(Library.Folder) then FS.makefolder(Library.Folder) end
					FS.writefile(KEY_FILE, (key:gsub("^%s+", ""):gsub("%s+$", "")))
				end)
			end
			continueLabel.Text = "Unlocked"
			setIcon(continueGlyph, "check")
			setIcon(lockIcon, "lock-open")
			Tween(fieldStroke, FAST, { Color = P.Success })
			Tween(continueButton, FAST, { BackgroundColor3 = Color3.fromRGB(34, 160, 92) })
			local popScale = Create("UIScale", { Scale = 0.5, Parent = continueGlyph })
			Tween(popScale, BOUNCE, { Scale = 1 })
			logoScale.Scale = 0.9
			Tween(logoScale, BOUNCE, { Scale = 1 })
			setStatus("Key accepted", "shield-check", P.Success)
			task.wait(0.7)
			finish(true)
		else
			continueLabel.Text = SUBMIT
			setIcon(continueGlyph, "arrow-right")
			setStatus(message or "That key isn't valid", "circle-x", P.Error)
			Tween(fieldStroke, FAST, { Color = P.Error })
			shake()
			failures += 1
			if failures >= 3 then
				failures = 0
				for remaining = 5, 1, -1 do
					continueLabel.Text = string.format("Wait %ds", remaining)
					task.wait(1)
				end
				continueLabel.Text = SUBMIT
			end
			busy = false
		end
	end

	continueButton.Activated:Connect(function() task.spawn(submit) end)
	continueButton:GetAttributeChangedSignal("Submit"):Connect(function() task.spawn(submit) end)
	local function shareLink(link, copiedText)
		local setclipboard = envFunction("setclipboard") or envFunction("toclipboard")
		if setclipboard and pcall(setclipboard, link) then
			setStatus(copiedText, "copy", P.Sub, 5)
		else
			setStatus(link, "external-link", P.Sub, 8)
		end
	end
	getButton.Activated:Connect(function()
		shareLink(options.KeyLink or "https://example.com/get-key", options.LinkCopied or "Link copied. Open it in your browser.")
	end)
	if promoButton then
		promoButton.Activated:Connect(function()
			if type(options.OnBuy) == "function" then pcall(options.OnBuy) end
			shareLink(buyLink, options.BuyCopied or "Shop link copied. Open it in your browser.")
		end)
	end
	if buyButton then
		buyButton.Activated:Connect(function()
			if type(options.OnBuy) == "function" then pcall(options.OnBuy) end
			shareLink(buyLink, options.BuyCopied or "Shop link copied. Open it in your browser.")
		end)
	end
	close.Activated:Connect(function() finish(false) end)

	-- Entrance: dim + blur ease in, the card fades up into place, rows follow in sequence.
	local fit = holder:GetAttribute("Fit") or 1
	local home = holder.Position
	cardScale.Scale = fit * 0.96
	holder.Position = home + UDim2.fromOffset(0, 12)
	Tween(backdrop, ease(0.4, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.25 })
	if blur then Tween(blur, ease(0.45, Enum.EasingStyle.Quad), { Size = 18 }) end
	Tween(card, ease(0.4, Enum.EasingStyle.Quad), { GroupTransparency = 0 })
	Tween(shadow, ease(0.5, Enum.EasingStyle.Quad), { ImageTransparency = 0.4 })
	Tween(holder, ease(0.55), { Position = home })
	entrance = Tween(cardScale, ease(0.55), { Scale = fit })
	entrance.Completed:Connect(function()
		cardScale.Scale = holder:GetAttribute("Fit") or fit -- exact scale keeps text crisp
	end)
	for i, item in ipairs(animated) do
		local home = item.Position
		item.Position = home + UDim2.fromOffset(0, 6)
		task.delay(0.08 + math.min(i, 12) * 0.025, function()
			if item.Parent and not closing then Tween(item, ease(0.45), { Position = home }) end
		end)
	end
	task.delay(0.15, function() Tween(logoScale, BOUNCE, { Scale = 1 }) end)
	task.delay(0.45, function()
		if input.Parent and not closing and not UserInputService.TouchEnabled then input:CaptureFocus() end
	end)

	done.Event:Wait()
	done:Destroy()
	self._keyPromptActive = false
	self:_syncMenuCursor()
	return result
end

--// Window ----------------------------------------------------------------------

function Library:CreateWindow(config)
	config = config or {}
	local Window = { Tabs = {} }

	-- Layout: Compact = true (or Style = "Compact") builds the dense variant.
	COMPACT = config.Compact == true or tostring(config.Style or config.Layout or ""):lower() == "compact"
	Window.Compact = COMPACT
	if COMPACT then
		WINDOW_SIZE = Vector2.new(620, 410)
		SIDEBAR_WIDTH = 60
		BRAND_HEIGHT = 58
		FOOTER_HEIGHT = 62
		PANEL_INSET = 7
		TOPBAR_HEIGHT = 46
		PAGE_MARGIN = 10
		COLUMN_GAP = 8
	else
		WINDOW_SIZE = Vector2.new(840, 540)
		SIDEBAR_WIDTH = 212
		BRAND_HEIGHT = 72
		FOOTER_HEIGHT = 70
		PANEL_INSET = 8
		TOPBAR_HEIGHT = 58
		PAGE_MARGIN = 14
		COLUMN_GAP = 12
	end
	PANEL_WIDTH = WINDOW_SIZE.X - SIDEBAR_WIDTH - PANEL_INSET
	COLUMN_WIDTH = math.floor((PANEL_WIDTH - PAGE_MARGIN * 2 - COLUMN_GAP) / 2)

	-- Window ----------------------------------------------------------------------
	-- Layout: the sidebar sits straight on the window background; the pages live in a rounded
	-- panel inset on the right, with the page header built into its top.
	local main = Create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Theme.Background,
		Parent = ScreenGui,
	}, {
		Corner(COMPACT and 12 or 14),
		Stroke(Theme.Stroke),
	})
	local scale = Create("UIScale", { Parent = main })
	-- Active marks every click on the window as GUI-processed, so it never reaches the game
	-- (tools, attacks, click detectors) behind it.
	main.Active = true
	Library:_blockWheel(main)
	Window.Frame = main
	Window.Scale = scale

	Create("ImageLabel", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 8),
		Size = UDim2.new(1, 80, 1, 80),
		BackgroundTransparency = 1,
		Image = "rbxassetid://6014261993",
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.35,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(49, 49, 450, 450),
		ZIndex = 0,
		Parent = main,
	})

	-- Backdrop: a wash of a lighter layer from the top edge that fades out toward the middle.
	-- It gives the dark window depth and carries the theme's hue. "Solid" hides it.
	local function backdrop(parent, color, strength, reach, radius)
		local frame = Create("Frame", {
			Name = "Backdrop",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Visible = Library.Backdrop ~= "Solid",
			ZIndex = 0,
			Parent = parent,
		}, {
			Corner(radius),
			Create("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1 - strength),
					NumberSequenceKeypoint.new(reach, 1),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
		frame:SetAttribute("NoGradient", true)
		table.insert(Library._backdrops, frame)
		return frame
	end
	-- The drop shadow's centre would otherwise darken the window itself: an opaque base sits
	-- above it, so the sidebar shows the exact Background colour.
	local base = Create("Frame", {
		Name = "Base",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		ZIndex = 1,
		Parent = main,
	}, { Corner(COMPACT and 12 or 14) })
	backdrop(base, Theme.Hover, 0.28, 0.7, COMPACT and 12 or 14)

	-- Sidebar ------------------------------------------------------------------
	local sidebar = Create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = main,
	})

	local brand = Create("Frame", {
		Name = "Brand",
		Size = UDim2.new(1, 0, 0, BRAND_HEIGHT),
		BackgroundTransparency = 1,
		Active = true,
		Parent = sidebar,
	})
	local logo = Create("Frame", {
		AnchorPoint = COMPACT and Vector2.new(0.5, 0.5) or Vector2.new(0, 0.5),
		Position = COMPACT and UDim2.new(0.5, 0, 0.5, 3) or UDim2.new(0, 16, 0.5, 2),
		Size = COMPACT and UDim2.fromOffset(32, 32) or UDim2.fromOffset(38, 38),
		BackgroundColor3 = Theme.Accent,
		Parent = brand,
	}, { Corner(10) })
	Brand(logo, config.Logo or "N", 30, 18, nil, true)
	if COMPACT then
		-- The rail has no room for text: the hub name lives in the header instead.
		Library:_attachTooltip(logo, (config.Title or "Crown Hub") .. " · " .. (config.Subtitle or "v1.0"))
		Create("Frame", {
			Name = "Rule",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.fromOffset(22, 1),
			BackgroundColor3 = Theme.Stroke,
			BorderSizePixel = 0,
			Parent = brand,
		})
	else
		Label({
			Text = config.Title or "Crown Hub",
			FontFace = Fonts.Bold,
			TextSize = 17,
			Position = UDim2.fromOffset(64, 17),
			Size = UDim2.new(1, -76, 0, 19),
			Parent = brand,
		})
		Label({
			Text = config.Subtitle or "v1.0",
			TextSize = 13,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(64, 37),
			Size = UDim2.new(1, -76, 0, 14),
			Parent = brand,
		})
	end

	local tabList = Create("ScrollingFrame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(0, BRAND_HEIGHT + 4),
		Size = UDim2.new(1, 0, 1, -BRAND_HEIGHT - 4 - FOOTER_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = sidebar,
	}, {
		List(COMPACT and 4 or 2),
		COMPACT and Padding(6, 10, 6, 10) or Padding(0, 10, 10, 10),
	})

	-- Profile card: avatar, names and a live ping chip.
	local footer = Create("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT),
		BackgroundTransparency = 1,
		Parent = sidebar,
	})
	local avatar, pingIcon, pingLabel
	if COMPACT then
		-- Rail footer: the avatar with its presence dot over a tiny live ping readout.
		avatar = Create("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = Theme.Elevated,
			Image = "",
			Parent = footer,
		}, { Corner(15), Stroke(Theme.Stroke, 0.2) })
		Create("Frame", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 1, 1, 1),
			Size = UDim2.fromOffset(9, 9),
			BackgroundColor3 = Theme.Accent,
			ZIndex = 2,
			Parent = avatar,
		}, { Corner(5), Create("UIStroke", { Color = Theme.Background, Thickness = 2 }) })
		Library:_attachTooltip(avatar, LocalPlayer.DisplayName .. "  @" .. LocalPlayer.Name)
		pingLabel = Label({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 40),
			Size = UDim2.new(1, -8, 0, 12),
			Text = "—",
			FontFace = Fonts.Medium,
			TextSize = 12,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = footer,
		})
		pingIcon = pingLabel
	end
	if not COMPACT then
		local profile = Create("Frame", {
			Name = "Profile",
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.new(1, -20, 1, -14),
			BackgroundColor3 = Theme.Surface,
			Parent = footer,
		}, { Corner(11), Stroke(Theme.StrokeSoft) })
		avatar = Create("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 9, 0.5, 0),
			Size = UDim2.fromOffset(32, 32),
			BackgroundColor3 = Theme.Elevated,
			Image = "",
			Parent = profile,
		}, { Corner(16) })
		Create("Frame", { -- presence dot
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 1, 1, 1),
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = Theme.Accent,
			ZIndex = 2,
			Parent = avatar,
		}, { Corner(5), Create("UIStroke", { Color = Theme.Surface, Thickness = 2 }) })
		Label({
			Text = LocalPlayer.DisplayName,
			FontFace = Fonts.SemiBold,
			TextSize = 14,
			Position = UDim2.fromOffset(50, 9),
			Size = UDim2.new(1, -112, 0, 16),
			Parent = profile,
		})
		Label({
			Text = "@" .. LocalPlayer.Name,
			TextSize = 13,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(50, 26),
			Size = UDim2.new(1, -112, 0, 14),
			Parent = profile,
		})
		-- Live connection readout: signal glyph + ping, refreshed once a second.
		local pingChip = Create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(54, 22),
			BackgroundColor3 = Theme.Elevated,
			Parent = profile,
		}, { Corner(7) })
		pingIcon = Icon("wifi", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			ImageColor3 = Theme.Muted,
			Parent = pingChip,
		})
		pingLabel = Label({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(32, 14),
			Text = "—",
			FontFace = Fonts.Medium,
			TextSize = 12,
			TextColor3 = Theme.SubText,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = pingChip,
		})
	end
	local pingClock = 0
	Connect(RunService.Heartbeat, function(dt)
		pingClock += dt
		if pingClock < 1 then
			return
		end
		pingClock = 0
		local ok, ping = pcall(function()
			return LocalPlayer:GetNetworkPing() * 1000
		end)
		if ok then
			pingLabel.Text = string.format("%dms", ping + 0.5)
			if COMPACT then
				pingLabel.TextColor3 = ping < 120 and Theme.SubText or Theme.Muted
			else
				pingIcon.ImageColor3 = ping < 120 and Theme.SubText or Theme.Muted
			end
		end
	end)
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and image and avatar.Parent then
			avatar.Image = image
		end
	end)

	-- Content panel ----------------------------------------------------------------
	local content = Create("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(SIDEBAR_WIDTH, PANEL_INSET),
		Size = UDim2.new(1, -SIDEBAR_WIDTH - PANEL_INSET, 1, -PANEL_INSET * 2),
		BackgroundColor3 = Theme.Sidebar,
		ZIndex = 2,
		Parent = main,
	}, { Corner(COMPACT and 10 or 12), Stroke(Theme.StrokeSoft) })
	backdrop(content, Theme.Elevated, 0.32, 0.5, COMPACT and 10 or 12)

	local topbar = Create("Frame", {
		Name = "Topbar",
		Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT),
		BackgroundTransparency = 1,
		Active = true, -- required so transparent topbar receives mouse/touch drag
		Parent = content,
	})
	Create("Frame", {
		Name = "Rule",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, COMPACT and 12 or 16, 1, 0),
		Size = UDim2.new(1, COMPACT and -24 or -32, 0, 1),
		BackgroundColor3 = Theme.StrokeSoft,
		BorderSizePixel = 0,
		Parent = topbar,
	})
	-- Page header: the tab's glyph in a tile, then a breadcrumb (Parent › Sub) over the description.
	local headerGlyph = Create("Frame", {
		Name = "Glyph",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Theme.Elevated,
		Visible = false,
		Parent = topbar,
	}, { Corner(10), Stroke(Theme.Stroke, 0.4) })
	local headerGlyphScale = Create("UIScale", { Parent = headerGlyph })
	local headerGlyphImage = Icon("", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(17, 17),
		ImageColor3 = Theme.Text,
		Parent = headerGlyph,
	})
	local titleRow = Create("Frame", {
		Name = "Title",
		Position = UDim2.fromOffset(18, 10),
		Size = UDim2.new(1, -160, 0, 20),
		BackgroundTransparency = 1,
		Parent = topbar,
	})
	local titleList = List(7, Enum.FillDirection.Horizontal)
	titleList.VerticalAlignment = Enum.VerticalAlignment.Center
	titleList.Parent = titleRow
	local crumbLabel = Label({
		Text = "",
		FontFace = Fonts.SemiBold,
		TextSize = 17,
		TextColor3 = Theme.Muted,
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None,
		Visible = false,
		LayoutOrder = 1,
		Parent = titleRow,
	})
	local crumbSeparator = Icon("chevron-right", {
		Size = UDim2.fromOffset(14, 14),
		ImageColor3 = Theme.Muted,
		Visible = false,
		LayoutOrder = 2,
		Parent = titleRow,
	})
	local pageTitle = Label({
		Text = "",
		FontFace = Fonts.Bold,
		TextSize = 17,
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None,
		LayoutOrder = 3,
		Parent = titleRow,
	})
	local pageDescription = Label({
		Text = "",
		TextSize = 14,
		TextColor3 = Theme.Muted,
		Position = UDim2.fromOffset(18, 32),
		Size = UDim2.new(1, -160, 0, 15),
		Parent = topbar,
	})

	-- Compact header: one row holding the title block, then the open branch's sub-tab chips.
	local compactTitle, chipHost, chipDivider
	if COMPACT then
		headerGlyph.Visible = false
		titleRow.Visible = false
		pageDescription.Visible = false
		local headerRow = Create("Frame", {
			Name = "HeaderRow",
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -14 - 76, 1, 0),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Parent = topbar,
		})
		local rowList = List(14, Enum.FillDirection.Horizontal)
		rowList.VerticalAlignment = Enum.VerticalAlignment.Center
		rowList.Parent = headerRow
		local titleBlock = Create("Frame", {
			Name = "TitleBlock",
			Size = UDim2.fromOffset(0, 36),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Parent = headerRow,
		})
		compactTitle = Label({
			Text = "",
			FontFace = Fonts.Bold,
			TextSize = 17,
			Size = UDim2.fromOffset(0, 20),
			AutomaticSize = Enum.AutomaticSize.X,
			TextTruncate = Enum.TextTruncate.None,
			Parent = titleBlock,
		})
		Label({
			Text = string.upper(config.Title or "Crown Hub") .. "  ·  " .. (config.Subtitle or "v1.0"),
			FontFace = Fonts.Medium,
			TextSize = 12,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(0, 21),
			Size = UDim2.fromOffset(0, 14),
			AutomaticSize = Enum.AutomaticSize.X,
			TextTruncate = Enum.TextTruncate.None,
			Parent = titleBlock,
		})
		-- Hairline between the title block and the chips.
		chipDivider = Create("Frame", {
			Name = "Divider",
			Size = UDim2.fromOffset(1, 20),
			BackgroundColor3 = Theme.Stroke,
			BorderSizePixel = 0,
			LayoutOrder = 2,
			Parent = headerRow,
		})
		chipHost = Create("Frame", {
			Name = "Chips",
			Size = UDim2.fromOffset(0, 28),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = 3,
			Parent = headerRow,
		})
	end

	-- Window buttons: rounded squares that fill in on hover.
	local BUTTON = COMPACT and 26 or 30
	local function windowButton(name, x)
		local button = Create("TextButton", {
			Name = name,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, x, 0.5, 0),
			Size = UDim2.fromOffset(BUTTON, BUTTON),
			BackgroundColor3 = Theme.Elevated,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Parent = topbar,
		}, { Corner(COMPACT and 8 or 9) })
		return button
	end

	-- Close button (drawn X)
	local closeButton = windowButton("Close", COMPACT and -10 or -14)
	local crossLines = {}
	for _, rotation in ipairs({ 45, -45 }) do
		table.insert(crossLines, Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(12, 1.5),
			Rotation = rotation,
			BackgroundColor3 = Theme.SubText,
			BorderSizePixel = 0,
			Parent = closeButton,
		}))
	end
	closeButton.MouseEnter:Connect(function()
		Tween(closeButton, FAST, { BackgroundTransparency = 0 })
		for _, line in ipairs(crossLines) do
			Tween(line, FAST, { BackgroundColor3 = Theme.Text })
		end
	end)
	closeButton.MouseLeave:Connect(function()
		Tween(closeButton, FAST, { BackgroundTransparency = 1 })
		for _, line in ipairs(crossLines) do
			Tween(line, FAST, { BackgroundColor3 = Theme.SubText })
		end
	end)

	-- Minimize button: folds the window into a floating logo bubble.
	local minimizeButton = windowButton("Minimize", COMPACT and -40 or -48)
	local minimizeIcon = Icon("minus", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		ImageColor3 = Theme.SubText,
		Parent = minimizeButton,
	})
	minimizeButton.MouseEnter:Connect(function()
		Tween(minimizeButton, FAST, { BackgroundTransparency = 0 })
		Tween(minimizeIcon, FAST, { ImageColor3 = Theme.Text })
	end)
	minimizeButton.MouseLeave:Connect(function()
		Tween(minimizeButton, FAST, { BackgroundTransparency = 1 })
		Tween(minimizeIcon, FAST, { ImageColor3 = Theme.SubText })
	end)
	Library:_attachTooltip(minimizeButton, "Minimize")
	Library:_attachTooltip(closeButton, "Hide (" .. keyName(Library.ToggleKey) .. ")")

	-- Search was removed from the UI; keep a stand-in so filtering code stays inert.
	local searchBox = { Text = "" }

	local pages = Create("Frame", {
		Name = "Pages",
		Position = UDim2.fromOffset(0, TOPBAR_HEIGHT),
		-- stops short of the panel's rounded bottom edge so scrolled cards never poke past it
		Size = UDim2.new(1, 0, 1, -TOPBAR_HEIGHT - 6),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = content,
	})

	-- Scaling & dragging ---------------------------------------------------------
	local function viewport()
		local size = ScreenGui.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			-- The gui can report 0x0 on its first frame (common in Studio); fall back to the camera.
			local camera = Workspace.CurrentCamera
			size = camera and camera.ViewportSize or Vector2.new(1280, 720)
		end
		return size
	end

	local function effectiveScale()
		local vp = viewport()
		local fit = math.min((vp.X - 24) / WINDOW_SIZE.X, (vp.Y - 24) / WINDOW_SIZE.Y)
		if UserInputService.TouchEnabled then
			return math.max(0.05, math.min(fit, math.clamp(fit, 0.45, 1) * Library.UserScale))
		end
		return math.clamp(fit, 0.45, 1) * Library.UserScale
	end

	local position = viewport() / 2
	local target = position

	-- Touch dragging is unrestricted; desktop keeps a reachable border.
	local function clampPosition(point)
		if UserInputService.TouchEnabled then return point end
		return boundedCenter(point, WINDOW_SIZE * effectiveScale(), viewport(), TOPBAR_HEIGHT * effectiveScale())
	end

	-- Text blurs whenever it lands on a half pixel, so the window's top-left corner is
	-- always snapped to whole pixels (an odd viewport height puts the raw centre at .5).
	local function applyPosition()
		local half = WINDOW_SIZE * scale.Scale / 2
		local left = math.floor(position.X - half.X + 0.5)
		local top = math.floor(position.Y - half.Y + 0.5)
		main.Position = UDim2.fromOffset(left + half.X, top + half.Y)
	end

	function Window:UpdateScale()
		scale.Scale = effectiveScale()
		target = clampPosition(target)
		position = target
		applyPosition()
	end
	Window:UpdateScale()
	local hasRealViewport = ScreenGui.AbsoluteSize.X > 0
	Connect(ScreenGui:GetPropertyChangedSignal("AbsoluteSize"), function()
		if not hasRealViewport and ScreenGui.AbsoluteSize.X > 0 then
			hasRealViewport = true
			target = viewport() / 2 -- first real measurement: centre properly
		end
		Window:UpdateScale()
	end)

	local dragging, dragStart, startTarget = nil, nil, nil
	local function beginDrag(input)
		if not isPointer(input) or not Library.Open or Library.Minimized then
			return
		end
		local p = Vector2.new(input.Position.X, input.Position.Y)
		-- Don't start a drag when pressing the window control buttons
		local sp, ss = minimizeButton.AbsolutePosition, minimizeButton.AbsoluteSize
		local cp, cs = closeButton.AbsolutePosition, closeButton.AbsoluteSize
		if (p.X >= sp.X and p.X <= sp.X + ss.X and p.Y >= sp.Y and p.Y <= sp.Y + ss.Y)
			or (p.X >= cp.X and p.X <= cp.X + cs.X and p.Y >= cp.Y and p.Y <= cp.Y + cs.Y) then
			return
		end
		if not claimPointer(input) then return end
		dragging, dragStart, startTarget = input, p, target
	end
	Connect(topbar.InputBegan, beginDrag)
	Connect(brand.InputBegan, beginDrag)
	-- Also allow dragging from the main window chrome (title area / empty header)
	if main then
		-- thin invisible strip along the very top of the outer frame for easier grab
		local grabBar = Create("Frame", {
			Name = "DragGrab",
			Size = UDim2.new(1, 0, 0, 12),
			BackgroundTransparency = 1,
			Active = true,
			ZIndex = 100,
			Parent = main,
		})
		Connect(grabBar.InputBegan, beginDrag)
	end
	-- Invisible handles on all four borders (mouse + touch) so the window can be dragged from edges
	do
		local edges = {}
		for _, name in ipairs({ "Left", "Right", "Top", "Bottom" }) do
			local edge = Create("Frame", {
				Name = "DragEdge" .. name,
				BackgroundTransparency = 1,
				Active = true,
				ZIndex = 90,
				Parent = main,
			})
			edges[name] = edge
			Connect(edge.InputBegan, beginDrag)
		end
		local function sizeEdges()
			local s = math.max(scale.Scale, 0.01)
			local outside, inside = 18 / s, 10 / s
			local width = outside + inside
			edges.Left.Position = UDim2.fromOffset(-outside, -outside)
			edges.Left.Size = UDim2.new(0, width, 1, outside * 2)
			edges.Right.Position = UDim2.new(1, -inside, 0, -outside)
			edges.Right.Size = UDim2.new(0, width, 1, outside * 2)
			edges.Top.Position = UDim2.fromOffset(0, -outside)
			edges.Top.Size = UDim2.new(1, 0, 0, width)
			edges.Bottom.Position = UDim2.new(0, 0, 1, -inside)
			edges.Bottom.Size = UDim2.new(1, 0, 0, width)
		end
		Connect(scale:GetPropertyChangedSignal("Scale"), sizeEdges)
		sizeEdges()
	end
	Connect(UserInputService.InputChanged, function(input)
		if movesPointer(dragging, input) then
			local p = Vector2.new(input.Position.X, input.Position.Y)
			target = clampPosition(startTarget + (p - dragStart))
			-- Snap immediately for both mouse and touch (smooth lerp still runs on RenderStepped)
			position = target
			applyPosition()
		end
	end)
	Connect(UserInputService.InputEnded, function(input)
		if endsPointer(dragging, input) then
			dragging = nil
		end
	end)
	Connect(RunService.RenderStepped, function(dt)
		if Library.Open and (target - position).Magnitude > 0.05 then
			position = position:Lerp(target, 1 - math.exp(-dt * 22))
			applyPosition()
		end
	end)

	-- Visibility -----------------------------------------------------------------
	-- Without CanvasGroup (it blurs text) the window can't fade as a whole, so a
	-- background-coloured veil sits on top and fades instead: content appears to dissolve in.
	local veil = Create("Frame", {
		Name = "Veil",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 100,
		Parent = main,
	}, { Corner(10) })
	local veilTween
	local function fadeVeil(from, to, info, hideAfter)
		if veilTween then
			veilTween:Cancel()
		end
		veil.Visible = true
		veil.BackgroundTransparency = from
		veilTween = Tween(veil, info, { BackgroundTransparency = to })
		if hideAfter then
			local mine = veilTween
			mine.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					veil.Visible = false
				end
			end)
		end
	end

	local visibilityTween
	function Library:SetOpen(open)
		if self.Unloaded then
			return
		end
		-- The floating mobile toggle can retrieve a window dragged entirely away.
		if open and not self.Open and UserInputService.TouchEnabled then
			local half = WINDOW_SIZE * effectiveScale() / 2
			local vp = viewport()
			if target.X + half.X <= 0 or target.X - half.X >= vp.X
				or target.Y + half.Y <= 0 or target.Y - half.Y >= vp.Y then
				target = vp / 2
			end
		end
		self.Open = open
		self:_syncMenuCursor()
		if dragging then
			endsPointer(dragging, dragging)
			dragging = nil
		end
		target = clampPosition(target)
		position = target
		applyPosition()
		if visibilityTween then
			visibilityTween:Cancel()
		end
		local base = effectiveScale()
		if open then
			main.Visible = true
			scale.Scale = base * 0.94
			fadeVeil(0, 1, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), true)
			main.Shadow.ImageTransparency = 1
			Tween(main.Shadow, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = 0.45 })
			visibilityTween = Tween(scale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0), { Scale = base })
			-- Any scale other than the exact target resamples every glyph, so snap on finish.
			visibilityTween.Completed:Connect(function()
				if Library.Open then
					scale.Scale = effectiveScale()
					applyPosition()
				end
			end)
		else
			fadeVeil(1, 0, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), false)
			Tween(main.Shadow, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { ImageTransparency = 1 })
			visibilityTween = Tween(scale, TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Scale = base * 0.95 })
			local tween = visibilityTween
			tween.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed and not Library.Open then
					main.Visible = false
				end
			end)
		end
	end

	-- Minimized bubble: floating square with theme-colored background
	local BUBBLE = 64
	local bubble = Create("TextButton", {
		Name = "MinimizedBubble",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(BUBBLE, BUBBLE),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 45,
		Parent = ScreenGui,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 14) }),
	})
	local bubbleStroke = Create("UIStroke", {
		Color = Theme.Accent,
		Thickness = 1.5,
		Transparency = 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = bubble,
	})

	local bubbleIcon = Create("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(36, 36),
		BackgroundTransparency = 1,
		Image = "rbxassetid://113737142720252",
		ScaleType = Enum.ScaleType.Fit,
		ImageColor3 = Color3.new(1, 1, 1),
		ZIndex = 46,
		Parent = bubble,
	})
	bubbleIcon:SetAttribute("NoTheme", true)
	bubbleIcon:SetAttribute("NoGradient", true)

	local bubbleShadow = Create("ImageLabel", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(BUBBLE + 28, BUBBLE + 28),
		BackgroundTransparency = 1,
		Image = "rbxassetid://5028857084",
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.5,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(24, 24, 276, 276),
		ZIndex = 44,
		Parent = bubble,
	})
	bubbleShadow:SetAttribute("NoTheme", true)

	-- Keep bubble colors in sync with the active theme
	local function paintBubble()
		bubble.BackgroundColor3 = Theme.Surface
		bubble.BackgroundTransparency = 0.08
		bubbleStroke.Color = Theme.Accent
		bubbleStroke.Transparency = 0.15
	end
	paintBubble()
	Library:OnThemeChanged(function()
		paintBubble()
	end)

	local bubbleScale = Create("UIScale", { Scale = 0, Parent = bubble })
	Library:_blockWheel(bubble)
	Library:_attachTooltip(bubble, "Click to open · drag to move")
	local bubbleMoved = false
	local bubbleTween
	local bubbleFloatConn
	local bubbleDragged = false

	-- Soft continuous "bloat / float" pulse while minimized
	local function startBubbleFloat()
		if bubbleFloatConn then bubbleFloatConn:Disconnect() end
		local t0 = os.clock()
		bubbleFloatConn = RunService.RenderStepped:Connect(function()
			if not Library.Minimized or not bubble.Visible then return end
			local t = os.clock() - t0
			-- gentle scale breath + tiny vertical bob
			local breath = 1 + math.sin(t * 2.1) * 0.035
			local bob = math.sin(t * 1.7) * 3
			if not bubbleDragged then
				bubbleScale.Scale = breath
			end
			-- bob only the visual offset via a tiny position nudge is expensive; keep it simple with scale
		end)
	end
	local function stopBubbleFloat()
		if bubbleFloatConn then
			bubbleFloatConn:Disconnect()
			bubbleFloatConn = nil
		end
	end

	Library.Minimized = false
	function Library:SetMinimized(value)
		if self.Unloaded or value == self.Minimized then
			return
		end
		self.Minimized = value
		if bubbleTween then bubbleTween:Cancel(); bubbleTween = nil end

		if value then
			-- Position bubble near the window's top-left corner the first time
			if not bubbleMoved then
				local corner = main.AbsolutePosition
				local vp = viewport()
				local localCorner = corner - ScreenGui.AbsolutePosition
				local bx = math.clamp(localCorner.X + 32, 40, math.max(40, vp.X - 40))
				local by = math.clamp(localCorner.Y + 32, 40, math.max(40, vp.Y - 40))
				bubble.Position = UDim2.fromOffset(bx, by)
			end

			-- Collapse animation: shrink + fade the main window like the close anim, then pop the bubble
			local base = effectiveScale()
			if visibilityTween then visibilityTween:Cancel() end
			fadeVeil(1, 0, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), false)
			Tween(main.Shadow, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { ImageTransparency = 1 })
			visibilityTween = Tween(scale, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Scale = base * 0.72 })
			local collapse = visibilityTween
			collapse.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed and Library.Minimized then
					main.Visible = false
					scale.Scale = base
					-- Bubble entrance: overshoot bounce
					bubble.Visible = true
					bubbleScale.Scale = 0.35
					bubbleTween = Tween(bubbleScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
					startBubbleFloat()
				end
			end)
			self.Open = false
			self:_syncMenuCursor()
		else
			-- Restore: bubble shrinks with a quick ease, then window opens with the normal open anim
			stopBubbleFloat()
			if bubbleTween then bubbleTween:Cancel() end
			bubbleTween = Tween(bubbleScale, TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Scale = 0.4 })
			local hide = bubbleTween
			hide.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					bubble.Visible = false
					bubbleScale.Scale = 1
				end
			end)
			-- Slight delay so the bubble starts collapsing first, then the window blooms open
			task.delay(0.08, function()
				if not Library.Minimized then
					self:SetOpen(true)
				end
			end)
		end
	end

	bubble.MouseEnter:Connect(function()
		if Library.Minimized then
			if bubbleTween then bubbleTween:Cancel() end
			bubbleTween = Tween(bubbleScale, FAST, { Scale = 1.06 })
			Tween(bubble, FAST, { BackgroundColor3 = Theme.Elevated, BackgroundTransparency = 0 })
			Tween(bubbleStroke, FAST, { Transparency = 0 })
		end
	end)
	bubble.MouseLeave:Connect(function()
		if Library.Minimized then
			if bubbleTween then bubbleTween:Cancel() end
			bubbleTween = Tween(bubbleScale, FAST, { Scale = 1 })
			Tween(bubble, FAST, { BackgroundColor3 = Theme.Surface, BackgroundTransparency = 0.08 })
			Tween(bubbleStroke, FAST, { Transparency = 0.15 })
		end
	end)

	-- Drag vs click: movement past 5px turns the press into a drag.
	local bubbleStart, bubbleOrigin, bubbleInput
	bubble.InputBegan:Connect(function(input)
		if bubble.Visible and claimPointer(input) then
			bubbleInput = input
			bubbleStart, bubbleOrigin, bubbleDragged = input.Position, bubble.Position, false
		end
	end)
	Connect(UserInputService.InputChanged, function(input)
		if bubbleStart and movesPointer(bubbleInput, input) then
			local delta = input.Position - bubbleStart
			if not bubbleDragged and delta.Magnitude > 5 then
				bubbleDragged = true
			end
			if bubbleDragged then
				local vp = ScreenGui.AbsoluteSize
				local x = math.clamp(bubbleOrigin.X.Offset + delta.X, math.min(34, vp.X / 2), math.max(vp.X / 2, vp.X - 34))
				local y = math.clamp(bubbleOrigin.Y.Offset + delta.Y, math.min(34, vp.Y / 2), math.max(vp.Y / 2, vp.Y - 34))
				bubble.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
			end
		end
	end)
	Connect(UserInputService.InputEnded, function(input)
		if bubbleStart and endsPointer(bubbleInput, input) then
			bubbleStart = nil
			if bubbleDragged then
				bubbleMoved = true
			elseif Library.Minimized and input.UserInputState ~= Enum.UserInputState.Cancel then
				Library:SetMinimized(false)
			end
		end
	end)

	minimizeButton.Activated:Connect(function()
		Library:SetMinimized(true)
	end)

	function Library:Toggle()
		if self.Minimized then
			self:SetMinimized(false)
			return
		end
		self:SetOpen(not self.Open)
	end

	closeButton.Activated:Connect(function()
		Library:SetOpen(false)
		Library:Notify({
			Title = "Interface hidden",
			Icon = "eye",
			Content = "Press " .. keyName(Library.ToggleKey) .. " to bring it back.",
			Duration = 3,
		})
	end)

	-- Mobile toggle pill removed (no extra floating button)
	Connect(ScreenGui:GetPropertyChangedSignal("AbsoluteSize"), function()
		local vp = viewport()
		bubble.Position = UDim2.fromOffset(math.clamp(bubble.Position.X.Offset, math.min(34, vp.X / 2), math.max(vp.X / 2, vp.X - 34)), math.clamp(bubble.Position.Y.Offset, math.min(34, vp.Y / 2), math.max(vp.Y / 2, vp.Y - 34)))
		endsPointer(bubbleInput, bubbleInput)
		bubbleStart = nil
		if dragging then endsPointer(dragging, dragging); dragging = nil end
	end)

	-- Search -------------------------------------------------------------------
	local function applySearch()
		local tab = Window.ActiveTab
		if not tab then
			return
		end
		local query = searchBox.Text:lower():gsub("^%s+", ""):gsub("%s+$", "")
		for _, section in ipairs(tab.Sections) do
			local sectionMatch = query == "" or section.Name:lower():find(query, 1, true) ~= nil
			local any = false
			for _, element in ipairs(section.Elements) do
				local visible = query == "" or sectionMatch or element.Name:lower():find(query, 1, true) ~= nil
				element.Frame.Visible = visible
				any = any or visible
			end
			section.Frame.Visible = any or sectionMatch or #section.Elements == 0 and query == ""
		end
		tab.EmptyLabel.Visible = query ~= "" and (function()
			for _, section in ipairs(tab.Sections) do
				if section.Frame.Visible then
					return false
				end
			end
			return true
		end)()
	end

	-- Tabs -----------------------------------------------------------------------
	-- Top-level tabs can hold sub-tabs (categories). They fold open beneath their parent on a
	-- tree guide; the parent shows a chevron and stays lit while one of its children is open.
	local TAB_HEIGHT, SUB_HEIGHT, SUB_GAP = COMPACT and 38 or 36, 30, 2
	local GUIDE_X = 20 -- centre of a parent's 17px icon (icon at x=12)
	local SUB_INDENT = 30 -- sub-tab buttons start here, right of the guide

	function Window:SidebarHeading(text)
		if COMPACT then
			-- The rail has no room for words: a short rule separates the groups.
			if #Window.Tabs == 0 then
				return
			end
			local gap = Create("Frame", {
				Name = "Heading",
				Size = UDim2.new(1, 0, 0, 9),
				BackgroundTransparency = 1,
				LayoutOrder = nextOrder(),
				Parent = tabList,
			})
			Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(16, 1),
				BackgroundColor3 = Theme.Stroke,
				BorderSizePixel = 0,
				Parent = gap,
			})
			return
		end
		local heading = Label({
			Text = string.upper(text),
			FontFace = Fonts.SemiBold,
			TextSize = 13,
			TextColor3 = Theme.Muted,
			Size = UDim2.new(1, 0, 0, #Window.Tabs == 0 and 20 or 34),
			TextYAlignment = Enum.TextYAlignment.Bottom,
			LayoutOrder = nextOrder(),
			Parent = tabList,
		})
		Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingBottom = UDim.new(0, 7) }).Parent = heading
	end

	-- One selection pill follows the active entry. It is driven by a spring each frame, so it
	-- glides between tabs, resizes between a tab and a sub-tab, and tracks folding groups.
	local selection = Create("Frame", {
		Name = "Selection",
		Size = UDim2.fromOffset(SIDEBAR_WIDTH - 20, TAB_HEIGHT),
		Position = UDim2.fromOffset(10, 0),
		BackgroundColor3 = Theme.Surface,
		Visible = false,
		ZIndex = 1,
		Parent = sidebar,
	}, { Corner(9), Stroke(Theme.Stroke, 0.45) })
	-- Accent bar on the pill's inner left edge.
	local selectionBar = Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(3, 16),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = selection,
	}, { Corner(2) })
	tabList.ZIndex = 2

	local pill = { x = 10, y = 0, w = SIDEBAR_WIDTH - 20, h = TAB_HEIGHT, snap = true }
	-- A sub-tab inside a folded group hands the pill to its parent.
	local function pillButton()
		local tab = Window.ActiveTab
		if not tab then
			return nil
		end
		if tab.Parent and (COMPACT or not tab.Parent.Expanded) then
			return tab.Parent.Button
		end
		return tab.Button
	end
	Connect(tabList:GetPropertyChangedSignal("CanvasPosition"), function()
		pill.snap = true
	end)
	Connect(RunService.RenderStepped, function(dt)
		if not Library.Open then
			return
		end
		local button = pillButton()
		if not button then
			return
		end
		local s = math.max(scale.Scale, 0.01)
		local origin = sidebar.AbsolutePosition
		local tx = (button.AbsolutePosition.X - origin.X) / s
		local ty = (button.AbsolutePosition.Y - origin.Y) / s
		local tw, th = button.AbsoluteSize.X / s, button.AbsoluteSize.Y / s
		if button ~= pill.button then
			if pill.button == nil then
				pill.snap = true
			else
				-- The bar stretches while travelling, then settles: reads as motion, not a jump.
				selectionBar.Size = UDim2.fromOffset(3, 26)
				Tween(selectionBar, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(3, 16) })
			end
			pill.button = button
		end
		if pill.snap then
			pill.x, pill.y, pill.w, pill.h = tx, ty, tw, th
			pill.snap = false
		else
			local k = 1 - math.exp(-dt * 17)
			local function approach(key, goal)
				local value = pill[key] + (goal - pill[key]) * k
				pill[key] = math.abs(goal - value) < 0.3 and goal or value
			end
			approach("x", tx)
			approach("y", ty)
			approach("w", tw)
			approach("h", th)
		end
		local listTop = (tabList.AbsolutePosition.Y - origin.Y) / s
		local listBottom = listTop + tabList.AbsoluteSize.Y / s
		local x, y = math.floor(pill.x + 0.5), math.floor(pill.y + 0.5)
		selection.Visible = y + pill.h > listTop + 2 and y < listBottom - 2
		selection.Position = UDim2.fromOffset(x, y)
		selection.Size = UDim2.fromOffset(math.floor(pill.w + 0.5), math.floor(pill.h + 0.5))
	end)

	-- "active" (open page), "branch" (a parent whose child is open), "hover" or "idle".
	local function restState(tab)
		local active = Window.ActiveTab
		if active == tab then
			return "active"
		end
		if active and active.Parent == tab then
			return "branch"
		end
		return "idle"
	end

	-- One place decides how a sidebar entry looks.
	local function paintTab(tab, state)
		state = state or restState(tab)
		local previous = tab._state
		tab._state = state
		local lit = state ~= "idle"
		Tween(tab.Button, FAST, { BackgroundTransparency = state == "hover" and 0.55 or 1 })
		if tab.IsSub then
			Tween(tab.ButtonLabel, FAST, { TextColor3 = lit and Theme.Text or Theme.Muted })
			if tab.Branch then
				Tween(tab.Branch, FAST, { BackgroundColor3 = state == "active" and Theme.Text or Theme.Stroke })
			end
			if tab.IconImage then
				Tween(tab.IconImage, FAST, { ImageColor3 = lit and Theme.Text or Theme.Muted })
			end
			return
		end
		Tween(tab.ButtonLabel, FAST, { TextColor3 = lit and Theme.Text or Theme.SubText })
		if tab.IconImage then
			Tween(tab.IconImage, FAST, {
				ImageColor3 = (state == "active" or state == "branch") and Theme.Text or state == "hover" and Theme.SubText or Theme.Muted,
			})
		end
		if tab.Chevron then
			Tween(tab.Chevron, FAST, { ImageColor3 = lit and Theme.Text or Theme.Muted })
		end
		if state == "active" and previous ~= "active" and tab.IconScale then
			tab.IconScale.Scale = 0.7
			Tween(tab.IconScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		end
	end
	Window._paintTab = paintTab

	local function setGlyph(name)
		local data = resolveIcon(name)
		headerGlyphImage.Image = data and ("rbxassetid://" .. data[1]) or (type(name) == "string" and name:find("^rbxasset") and name or "")
		headerGlyphImage.ImageRectSize = data and data[4] ~= 0 and Vector2.new(48, 48) or Vector2.zero
		headerGlyphImage.ImageRectOffset = data and Vector2.new(data[2], data[3]) or Vector2.zero
	end

	-- Header: glyph tile, breadcrumb and description rise into place with a short fade.
	local shownBranch
	local function renderHeader(tab, animate)
		if COMPACT then
			local branch = tab.Parent or tab
			for _, entry in ipairs(Window.Tabs) do
				if entry.ChipGroup then
					entry.ChipGroup.Visible = entry == branch
				end
			end
			chipDivider.Visible = branch.ChipGroup ~= nil
			if branch == shownBranch then
				return
			end
			shownBranch = branch
			compactTitle.Text = branch.Name
			if animate then
				compactTitle.TextTransparency = 1
				compactTitle.Position = UDim2.fromOffset(0, 5)
				Tween(compactTitle, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { TextTransparency = 0, Position = UDim2.fromOffset(0, 0) })
				if branch.ChipGroup then
					local scaleObject = branch.ChipGroup:FindFirstChildOfClass("UIScale")
					if scaleObject then
						scaleObject.Scale = 0.94
						Tween(scaleObject, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
					end
				end
			end
			return
		end
		local parent = tab.Parent
		local glyph = tab.Icon or (parent and parent.Icon)
		local textX = glyph and 60 or 18
		headerGlyph.Visible = glyph ~= nil
		if glyph then
			setGlyph(glyph)
		end
		crumbLabel.Visible = parent ~= nil
		crumbSeparator.Visible = parent ~= nil
		crumbLabel.Text = parent and parent.Name or ""
		pageTitle.Text = tab.Name
		pageDescription.Text = tab.Description or (parent and parent.Description) or ""
		local titleHome = UDim2.fromOffset(textX, pageDescription.Text == "" and 18 or 9)
		local descriptionHome = UDim2.fromOffset(textX, 31)
		titleRow.Size = UDim2.new(1, -textX - 100, 0, 20)
		pageDescription.Size = UDim2.new(1, -textX - 100, 0, 15)
		if not animate then
			titleRow.Position, pageDescription.Position = titleHome, descriptionHome
			return
		end
		local info = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		titleRow.Position = titleHome + UDim2.fromOffset(0, 6)
		pageDescription.Position = descriptionHome + UDim2.fromOffset(0, 6)
		for _, object in ipairs({ crumbLabel, pageTitle, pageDescription }) do
			object.TextTransparency = 1
		end
		crumbSeparator.ImageTransparency = 1
		Tween(titleRow, info, { Position = titleHome })
		Tween(crumbLabel, info, { TextTransparency = 0 })
		Tween(crumbSeparator, info, { ImageTransparency = 0 })
		Tween(pageTitle, info, { TextTransparency = 0 })
		task.delay(0.04, function()
			Tween(pageDescription, info, { Position = descriptionHome, TextTransparency = 0 })
		end)
		if glyph then
			headerGlyphScale.Scale = 0.8
			Tween(headerGlyphScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		end
	end

	-- A parent with sub-tabs and no sections of its own opens its last (or first) child.
	local function resolveTab(tab)
		if tab.SubTabs and #tab.SubTabs > 0 and #tab.Sections == 0 then
			return tab._lastSub or tab.SubTabs[1]
		end
		return tab
	end

	function Window:SelectTab(tab)
		tab = resolveTab(tab)
		if Window.ActiveTab == tab then
			return
		end
		local previous = Window.ActiveTab
		Window.ActiveTab = tab
		if tab.Parent then
			tab.Parent._lastSub = tab
			if not tab.Parent.Expanded then
				tab.Parent:SetExpanded(true)
			end
		end
		if previous then
			previous.Page.Visible = false
			paintTab(previous)
			if previous.Parent then
				paintTab(previous.Parent)
			end
		end
		paintTab(tab)
		if tab.Parent then
			paintTab(tab.Parent)
		end
		renderHeader(tab, previous ~= nil)
		tab.Page.Visible = true
		-- Columns arrive one after the other for a light staggered entrance.
		for index, column in ipairs({ tab.Left, tab.Right }) do
			local home = column:GetAttribute("Home")
			column.Position = home + UDim2.fromOffset(0, 14)
			task.delay((index - 1) * 0.05, function()
				Tween(column, TweenInfo.new(0.36, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = home })
			end)
		end
		applySearch()
	end

	-- Builds a tab's page: one scroll area with two columns, smooth wheel scrolling, the empty
	-- state and the :Section() constructor. Shared by tabs and sub-tabs.
	local function buildPage(Tab)
		local page = Create("Frame", {
			Name = Tab.Name,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = pages,
		})
		Tab.Page = page

		-- One scroll area holds both columns, so they always move together.
		local scroll = Create("ScrollingFrame", {
			Name = "Scroll",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = COMPACT and 2 or 3,
			ScrollBarImageColor3 = Theme.Muted,
			ScrollBarImageTransparency = 1,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ElasticBehavior = Enum.ElasticBehavior.Never,
			-- Desktop wheel scrolling is handled below (faster, eased, pixel-snapped);
			-- touch keeps Roblox's native drag scrolling.
			ScrollingEnabled = UserInputService.TouchEnabled,
			Parent = page,
		}, { COMPACT and Padding(8, 0, 10, 0) or Padding(12, 0, 16, 0) })
		Tab.Scroll = scroll

		local CONTENT_WIDTH = COLUMN_WIDTH
		local function column(name, x)
			return Create("Frame", {
				Name = name,
				Position = UDim2.fromOffset(x, 0),
				Size = UDim2.fromOffset(CONTENT_WIDTH, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Parent = scroll,
			}, { List(COMPACT and 8 or 12) })
		end
		Tab.Left = column("Left", PAGE_MARGIN)
		Tab.Right = column("Right", PAGE_MARGIN + COLUMN_WIDTH + COLUMN_GAP)
		for _, col in ipairs({ Tab.Left, Tab.Right }) do
			col:SetAttribute("Home", col.Position)
		end

		-- Smooth wheel scrolling -------------------------------------------------
		-- lastWritten identifies our own writes: property signals are deferred, so a flag
		-- set around the write would already be cleared when the handler runs.
		local target, lastWritten, scrollToken = 0, 0, 0
		local lastWheel = 0
		local function maxScroll()
			local s = scale.Scale
			return math.max(0, (scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y) / s)
		end
		local lastScrollbarFlash = -math.huge
		local function flashScrollbar()
			local now = os.clock()
			if now - lastScrollbarFlash < 0.15 then return end
			lastScrollbarFlash = now
			scrollToken += 1
			local mine = scrollToken
			Tween(scroll, FAST, { ScrollBarImageTransparency = 0.25 })
			task.delay(0.9, function()
				if mine == scrollToken then
					Tween(scroll, SMOOTH, { ScrollBarImageTransparency = 1 })
				end
			end)
		end
		Connect(scroll:GetPropertyChangedSignal("CanvasPosition"), function()
			flashScrollbar()
			if UserInputService.TouchEnabled then target = scroll.CanvasPosition.Y; return end
			if math.abs(scroll.CanvasPosition.Y - lastWritten) < 0.5 then
				return
			end
			-- Someone else moved it (reveal-on-expand, touch drag): adopt it, snapped to whole pixels.
			local y = math.floor(scroll.CanvasPosition.Y + 0.5)
			target = y
			if scroll.CanvasPosition.Y ~= y or scroll.CanvasPosition.X ~= 0 then
				lastWritten = y
				scroll.CanvasPosition = Vector2.new(0, y)
			end
		end)
		local function overOpenList(p)
			local open = Library._openDropdown
			local list = open and open._list
			if not (list and list.Visible) then
				return false
			end
			local a, s = list.AbsolutePosition, list.AbsoluteSize
			return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
		end
		Connect(UserInputService.InputChanged, function(input)
			if UserInputService.TouchEnabled or input.UserInputType ~= Enum.UserInputType.MouseWheel then
				return
			end
			if not Library.Open or Window.ActiveTab ~= Tab or not page.Visible then
				return
			end
			local p = input.Position
			local a, s = scroll.AbsolutePosition, scroll.AbsoluteSize
			if p.X < a.X or p.X > a.X + s.X or p.Y < a.Y or p.Y > a.Y + s.Y or overOpenList(p) then
				return
			end
			-- Quick successive notches travel further (momentum), single notches stay precise.
			local now = os.clock()
			local burst = (now - lastWheel < 0.12) and 1.35 or 1
			lastWheel = now
			target = math.clamp(target - input.Position.Z * 140 * burst, 0, maxScroll())
		end)
		Connect(RunService.RenderStepped, function(dt)
			if UserInputService.TouchEnabled or not Library.Open or Window.ActiveTab ~= Tab then
				return
			end
			target = math.clamp(target, 0, maxScroll())
			local current = scroll.CanvasPosition.Y
			local gap = target - current
			if math.abs(gap) < 0.5 then
				return
			end
			-- Exponential ease: quick to respond, soft to land. Always whole pixels.
			local step = gap * (1 - math.exp(-dt * 14))
			local nextY = current + (math.abs(step) < 1 and math.sign(gap) or step)
			lastWritten = math.floor(nextY + 0.5)
			scroll.CanvasPosition = Vector2.new(0, lastWritten)
		end)

		-- Empty search state: icon + message, centred in the page.
		local empty = Create("Frame", {
			Name = "Empty",
			Position = UDim2.fromOffset(math.floor((PANEL_WIDTH - 240) / 2), 70),
			Size = UDim2.fromOffset(240, 90),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = page,
		})
		local emptyTile = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(40, 40),
			BackgroundColor3 = Theme.Surface,
			Parent = empty,
		}, { Corner(10), Stroke(Theme.Stroke) })
		Icon("search", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(18, 18),
			ImageColor3 = Theme.SubText,
			Parent = emptyTile,
		})
		Label({
			Text = "No matching options",
			FontFace = Fonts.Medium,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 52),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = empty,
		})
		Label({
			Text = "Try a different word",
			TextSize = 13,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 72),
			Size = UDim2.new(1, 0, 0, 16),
			Parent = empty,
		})
		Tab.EmptyLabel = empty

		function Tab:Section(sectionOptions)
			if type(sectionOptions) == "string" then
				sectionOptions = { Name = sectionOptions }
			end
			return Library._createSection(Tab, sectionOptions)
		end
	end

	-- Badge pill used by tabs and sub-tabs.
	local function createBadge(parent, text, height, x)
		return Create("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, x, 0.5, 0),
			Size = UDim2.fromOffset(0, height),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Theme.Accent,
			Text = tostring(text),
			FontFace = Fonts.Bold,
			TextSize = 11,
			TextColor3 = Theme.OnAccent,
			ZIndex = 3,
			Parent = parent,
		}, { Corner(math.floor(height / 2)), Padding(0, 7, 0, 7) })
	end

	function Window:Tab(options)
		if type(options) == "string" then
			options = { Name = options }
		end
		local Tab = {
			Name = options.Name or "Tab",
			Description = options.Description,
			Icon = options.Icon,
			Sections = {},
			SubTabs = {},
			Expanded = false,
		}

		local button = Create("TextButton", {
			Name = Tab.Name,
			Size = UDim2.new(1, 0, 0, TAB_HEIGHT),
			BackgroundColor3 = Theme.Hover,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = nextOrder(),
			ZIndex = 2,
			Parent = tabList,
		}, { Corner(9) })
		-- Reserve the slot right under this button for its sub-tab group.
		local childOrder = nextOrder()
		Tab.Button = button
		local textX = 14
		if options.Icon then
			Tab.IconImage = Icon(options.Icon, {
				AnchorPoint = COMPACT and Vector2.new(0.5, 0.5) or Vector2.new(0, 0.5),
				Position = COMPACT and UDim2.fromScale(0.5, 0.5) or UDim2.new(0, 12, 0.5, 0),
				Size = UDim2.fromOffset(COMPACT and 18 or 17, COMPACT and 18 or 17),
				ImageColor3 = Theme.Muted,
				ZIndex = 3,
				Parent = button,
			})
			Tab.IconScale = Create("UIScale", { Parent = Tab.IconImage })
			textX = 39
		end
		local badgeWidth = 0
		if options.Badge and COMPACT then
			-- No room for a pill on the rail: a dot in the icon's corner.
			Tab.Badge = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -9, 0, 9),
				Size = UDim2.fromOffset(7, 7),
				BackgroundColor3 = Theme.Accent,
				ZIndex = 4,
				Parent = button,
			}, { Corner(4), Create("UIStroke", { Color = Theme.Background, Thickness = 1.5 }) })
		elseif options.Badge then
			Tab.Badge = createBadge(button, options.Badge, 18, -8)
			badgeWidth = 44
		end
		Tab.ButtonLabel = Label({
			Text = (COMPACT and not options.Icon) and Tab.Name:sub(1, 2) or Tab.Name,
			FontFace = Fonts.Medium,
			TextSize = 15,
			TextColor3 = Theme.SubText,
			Position = UDim2.fromOffset(COMPACT and 0 or textX, 0),
			Size = COMPACT and UDim2.fromScale(1, 1) or UDim2.new(1, -textX - 6 - badgeWidth, 1, 0),
			TextXAlignment = COMPACT and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left,
			Visible = not (COMPACT and options.Icon),
			ZIndex = 3,
			Parent = button,
		})
		if COMPACT then
			Library:_attachTooltip(button, Tab.Name)
		end

		button.MouseEnter:Connect(function()
			if restState(Tab) ~= "active" then
				paintTab(Tab, "hover")
			end
		end)
		button.MouseLeave:Connect(function()
			paintTab(Tab)
		end)
		button.Activated:Connect(function()
			if #Tab.SubTabs == 0 then
				Window:SelectTab(Tab)
				return
			end
			-- Inside its own branch the parent just folds; from elsewhere it opens the branch.
			local active = Window.ActiveTab
			if active == Tab or (active and active.Parent == Tab) then
				Tab:SetExpanded(not Tab.Expanded)
			else
				Tab:SetExpanded(true)
				Window:SelectTab(Tab)
			end
		end)

		buildPage(Tab)

		-- Sub-tab group ---------------------------------------------------------------
		local group, groupList, guide
		local expandToken = 0
		local function groupHeight()
			local count = #Tab.SubTabs
			if count == 0 then
				return 0
			end
			return count * SUB_HEIGHT + (count - 1) * SUB_GAP + 4
		end
		local function ensureGroup()
			if COMPACT then
				-- Compact: the branch's sub-tabs are chips in the header, behind one gliding pill.
				if Tab.ChipGroup then
					return
				end
				local chipGroup = Create("Frame", {
					Name = Tab.Name .. "_Chips",
					Size = UDim2.fromOffset(0, 28),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundColor3 = Theme.Background,
					Visible = false,
					Parent = chipHost,
				}, { Corner(8), Stroke(Theme.StrokeSoft), Padding(3, 3, 3, 3) })
				Create("UIScale", { Parent = chipGroup })
				local chipList = Create("Frame", {
					Name = "List",
					Size = UDim2.fromOffset(0, 22),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					ZIndex = 3,
					Parent = chipGroup,
				}, { List(2, Enum.FillDirection.Horizontal) })
				local chipPill = Create("Frame", {
					Name = "Pill",
					Size = UDim2.fromOffset(0, 22),
					BackgroundColor3 = Theme.Surface,
					Visible = false,
					ZIndex = 2,
					Parent = chipGroup,
				}, { Corner(6), Stroke(Theme.Stroke, 0.45) })
				-- Accent tick under the open chip, echoing the rail's bar.
				local tick = Create("Frame", {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, 0),
					Size = UDim2.fromOffset(12, 2),
					BackgroundColor3 = Theme.Accent,
					BorderSizePixel = 0,
					ZIndex = 3,
					Parent = chipPill,
				}, { Corner(1) })
				Tab.ChipGroup, Tab.ChipList = chipGroup, chipList
				local spring = { x = 0, w = 0, button = nil }
				Connect(RunService.RenderStepped, function(dt)
					local active = Window.ActiveTab
					if not Library.Open or not chipGroup.Visible or not active or active.Parent ~= Tab then
						chipPill.Visible = false
						spring.button = nil
						return
					end
					local s = math.max(scale.Scale, 0.01)
					local chip = active.Button
					local tx = (chip.AbsolutePosition.X - chipList.AbsolutePosition.X) / s
					local tw = chip.AbsoluteSize.X / s
					if tw < 1 then
						return
					end
					if spring.button == nil then
						spring.x, spring.w = tx, tw
					elseif spring.button ~= chip then
						tick.Size = UDim2.fromOffset(20, 2)
						Tween(tick, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(12, 2) })
					end
					spring.button = chip
					local k = 1 - math.exp(-dt * 18)
					spring.x += (tx - spring.x) * k
					spring.w += (tw - spring.w) * k
					if math.abs(tx - spring.x) < 0.3 then spring.x = tx end
					if math.abs(tw - spring.w) < 0.3 then spring.w = tw end
					chipPill.Visible = true
					chipPill.Position = UDim2.fromOffset(math.floor(spring.x + 0.5), 0)
					chipPill.Size = UDim2.fromOffset(math.floor(spring.w + 0.5), 22)
				end)
				return
			end
			if group then
				return
			end
			group = Create("Frame", {
				Name = Tab.Name .. "_SubTabs",
				Size = UDim2.new(1, 0, 0, 0),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Visible = false,
				LayoutOrder = childOrder,
				ZIndex = 2,
				Parent = tabList,
			})
			guide = Create("Frame", {
				Name = "Guide",
				Position = UDim2.fromOffset(GUIDE_X, 0),
				Size = UDim2.fromOffset(1, 0),
				BackgroundColor3 = Theme.Stroke,
				BorderSizePixel = 0,
				ZIndex = 2,
				Parent = group,
			})
			groupList = Create("Frame", {
				Name = "List",
				Position = UDim2.fromOffset(SUB_INDENT, 2),
				Size = UDim2.new(1, -SUB_INDENT, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ZIndex = 2,
				Parent = group,
			}, { List(SUB_GAP) })
			Tab.Chevron = Icon("chevron-right", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10 - badgeWidth, 0.5, 0),
				Size = UDim2.fromOffset(14, 14),
				ImageColor3 = Theme.Muted,
				ZIndex = 3,
				Parent = button,
			})
			Tab.ButtonLabel.Size = UDim2.new(1, -textX - 28 - badgeWidth, 1, 0)
		end

		-- Folds the sub-tab group open or closed.
		function Tab:SetExpanded(value, instant)
			value = value == true
			Tab.Expanded = value
			if not group then
				return
			end
			expandToken += 1
			local mine = expandToken
			local info = instant and TweenInfo.new(0) or SMOOTH
			Tween(Tab.Chevron, info, { Rotation = value and 90 or 0 })
			if value then
				group.Visible = true
				Tween(group, info, { Size = UDim2.new(1, 0, 0, groupHeight()) })
				if not instant then
					guide.Size = UDim2.fromOffset(1, 0)
				end
				local count = #Tab.SubTabs
				local guideHeight = 2 + (count - 1) * (SUB_HEIGHT + SUB_GAP) + math.floor(SUB_HEIGHT / 2)
				Tween(guide, instant and info or TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(1, guideHeight) })
			else
				Tween(group, info, { Size = UDim2.new(1, 0, 0, 0) })
				task.delay(info.Time, function()
					if mine == expandToken and not Tab.Expanded then
						group.Visible = false
					end
				end)
			end
			paintTab(Tab)
		end
		Tab.Expand = Tab.SetExpanded

		function Tab:SubTab(subOptions)
			if type(subOptions) == "string" then
				subOptions = { Name = subOptions }
			end
			ensureGroup()
			local Sub = {
				Name = subOptions.Name or "Category",
				Description = subOptions.Description,
				Icon = subOptions.Icon,
				Sections = {},
				Parent = Tab,
				IsSub = true,
			}
			local subButton
			if COMPACT then
				subButton = Create("TextButton", {
					Name = Sub.Name,
					Size = UDim2.fromOffset(0, 22),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundColor3 = Theme.Hover,
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					LayoutOrder = #Tab.SubTabs + 1,
					ZIndex = 3,
					Parent = Tab.ChipList,
				}, {
					Corner(6),
					Padding(0, 10, 0, subOptions.Icon and 8 or 10),
					Create("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 5),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				})
				Sub.Button = subButton
				if subOptions.Icon then
					Sub.IconImage = Icon(subOptions.Icon, {
						Size = UDim2.fromOffset(12, 12),
						ImageColor3 = Theme.Muted,
						LayoutOrder = 1,
						ZIndex = 4,
						Parent = subButton,
					})
				end
				Sub.ButtonLabel = Label({
					Text = Sub.Name,
					FontFace = Fonts.Medium,
					TextSize = 14,
					TextColor3 = Theme.Muted,
					Size = UDim2.fromOffset(0, 22),
					AutomaticSize = Enum.AutomaticSize.X,
					TextTruncate = Enum.TextTruncate.None,
					LayoutOrder = 2,
					ZIndex = 4,
					Parent = subButton,
				})
				if subOptions.Badge then
					Sub.Badge = Create("Frame", {
						Size = UDim2.fromOffset(6, 6),
						BackgroundColor3 = Theme.Accent,
						LayoutOrder = 3,
						ZIndex = 4,
						Parent = subButton,
					}, { Corner(3) })
				end
				Library:_attachTooltip(subButton, subOptions.Description)
			else
				subButton = Create("TextButton", {
					Name = Sub.Name,
					Size = UDim2.new(1, 0, 0, SUB_HEIGHT),
					BackgroundColor3 = Theme.Hover,
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					LayoutOrder = #Tab.SubTabs + 1,
					ZIndex = 2,
					Parent = groupList,
				}, { Corner(7) })
				Sub.Button = subButton
				-- Branch tick from the guide to the entry; lights up on the open sub-tab.
				Sub.Branch = Create("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, GUIDE_X - SUB_INDENT, 0.5, 0),
					Size = UDim2.fromOffset(SUB_INDENT - GUIDE_X - 3, 1),
					BackgroundColor3 = Theme.Stroke,
					BorderSizePixel = 0,
					ZIndex = 2,
					Parent = subButton,
				})
				local subTextX = 11
				if subOptions.Icon then
					Sub.IconImage = Icon(subOptions.Icon, {
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(0, 10, 0.5, 0),
						Size = UDim2.fromOffset(14, 14),
						ImageColor3 = Theme.Muted,
						ZIndex = 3,
						Parent = subButton,
					})
					subTextX = 31
				end
				local subBadgeWidth = 0
				if subOptions.Badge then
					Sub.Badge = createBadge(subButton, subOptions.Badge, 16, -7)
					subBadgeWidth = 40
				end
				Sub.ButtonLabel = Label({
					Text = Sub.Name,
					FontFace = Fonts.Regular,
					TextSize = 14,
					TextColor3 = Theme.Muted,
					Position = UDim2.fromOffset(subTextX, 0),
					Size = UDim2.new(1, -subTextX - 6 - subBadgeWidth, 1, 0),
					ZIndex = 3,
					Parent = subButton,
				})
			end
			subButton.MouseEnter:Connect(function()
				if Window.ActiveTab ~= Sub then
					paintTab(Sub, "hover")
				end
			end)
			subButton.MouseLeave:Connect(function()
				paintTab(Sub)
			end)
			subButton.Activated:Connect(function()
				Window:SelectTab(Sub)
			end)

			buildPage(Sub)
			table.insert(Tab.SubTabs, Sub)
			Sub.Index = #Tab.SubTabs
			if Tab.Expanded then
				Tab:SetExpanded(true, true)
			end
			if #Tab.SubTabs == 1 then
				-- Wait for the script to finish building: a parent with no sections of its own
				-- hands its page to the first child.
				task.defer(function()
					if Window.ActiveTab == Tab and #Tab.Sections == 0 then
						Window:SelectTab(Tab)
					end
				end)
				if options.Expanded then
					Tab:SetExpanded(true, true)
				end
			end
			return Sub
		end
		Tab.Subcategory = Tab.SubTab
		Tab.Category = Tab.SubTab

		table.insert(Window.Tabs, Tab)
		if not Window.ActiveTab then
			Window:SelectTab(Tab)
		end
		return Tab
	end

	Library.Window = Window
	return Window
end

--// Sections & elements ---------------------------------------------------------

local Section = {}
Section.__index = Section

function Library._createSection(tab, options)
	local self = setmetatable({
		Name = options.Name or "Section",
		Elements = {},
		Tab = tab,
	}, Section)

	local parentColumn = (options.Side == "Right" or options.Side == 2) and tab.Right or tab.Left
	local frame = Create("Frame", {
		Name = self.Name,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Surface,
		LayoutOrder = nextOrder(),
		Parent = parentColumn,
	}, {
		Corner(COMPACT and 10 or 12),
		Stroke(Theme.StrokeSoft),
		COMPACT and Padding(5, 5, 6, 5) or Padding(8, 8, 8, 8),
		List(0),
	})
	self.Frame = frame

	-- Header: optional icon tile, title and a hairline separating it from the controls.
	local header = Create("TextButton", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, COMPACT and 36 or 40),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = 0,
		Parent = frame,
	})
	local titleX = 8
	if options.Icon then
		local tile = Create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, -2),
			Size = UDim2.fromOffset(COMPACT and 24 or 26, COMPACT and 24 or 26),
			BackgroundColor3 = Theme.Elevated,
			Parent = header,
		}, { Corner(COMPACT and 6 or 8), Stroke(Theme.Stroke, 0.3) })
		Icon(options.Icon, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(COMPACT and 14 or 15, COMPACT and 14 or 15),
			ImageColor3 = Theme.Text,
			Parent = tile,
		})
		titleX = COMPACT and 37 or 40
	end
	local titleLabel = Label({
		Text = self.Name,
		FontFace = Fonts.SemiBold,
		TextSize = COMPACT and 16 or 15,
		Position = UDim2.fromOffset(titleX, 0),
		Size = UDim2.new(1, -titleX - 36, 1, -4),
		Parent = header,
	})
	local hairline = Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -2),
		Size = UDim2.new(1, -16, 0, 1),
		BackgroundColor3 = Theme.StrokeSoft,
		BorderSizePixel = 0,
		Parent = header,
	})
	local fold = Icon("chevron-down", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, -2),
		Size = UDim2.fromOffset(14, 14),
		ImageColor3 = Theme.Muted,
		Parent = header,
	})

	local list = List(1)
	self.Container = Create("Frame", {
		Name = "Elements",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = frame,
	}, { list })

	-- Clicking the header folds the section; height animates between 0 and its content.
	local collapsed, foldToken = false, 0
	header.MouseEnter:Connect(function()
		Tween(fold, FAST, { ImageColor3 = Theme.Text })
	end)
	header.MouseLeave:Connect(function()
		Tween(fold, FAST, { ImageColor3 = Theme.Muted })
	end)
	header.Activated:Connect(function()
		collapsed = not collapsed
		foldToken += 1
		local mine = foldToken
		local container = self.Container
		local s = Library.Window and Library.Window.Scale.Scale or 1
		local full = math.floor(list.AbsoluteContentSize.Y / s + 0.5)
		Tween(fold, SMOOTH, { Rotation = collapsed and -90 or 0 })
		Tween(hairline, FAST, { BackgroundTransparency = collapsed and 1 or 0 })
		Tween(titleLabel, FAST, { TextColor3 = collapsed and Theme.SubText or Theme.Text })
		container.AutomaticSize = Enum.AutomaticSize.None
		container.ClipsDescendants = true -- only while animating (it would crop slider bubbles)
		if collapsed then
			container.Size = UDim2.new(1, 0, 0, full)
			Tween(container, SMOOTH, { Size = UDim2.new(1, 0, 0, 0) })
			task.delay(SMOOTH.Time, function()
				if mine == foldToken and collapsed then
					container.Visible = false
				end
			end)
		else
			container.Visible = true
			container.Size = UDim2.new(1, 0, 0, 0)
			Tween(container, SMOOTH, { Size = UDim2.new(1, 0, 0, full) })
			task.delay(SMOOTH.Time, function()
				if mine == foldToken and not collapsed then
					container.AutomaticSize = Enum.AutomaticSize.Y
					container.ClipsDescendants = false
				end
			end)
		end
	end)

	table.insert(tab.Sections, self)
	return self
end

-- Shared row scaffold: name + optional description, returns header height.
function Section:_row(options, clickable)
	local hasDescription = type(options.Description) == "string" and options.Description ~= ""
	-- Compact keeps one line per option: the description moves into the hover tooltip.
	local tooltip = options.Tooltip
	if COMPACT and hasDescription then
		tooltip = tooltip or options.Description
		hasDescription = false
	end
	local header = COMPACT and 32 or (hasDescription and 48 or 34)
	local row = Create(clickable and "TextButton" or "Frame", {
		Name = options.Name or "Element",
		Size = UDim2.new(1, 0, 0, header),
		BackgroundColor3 = Theme.Elevated,
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
		ClipsDescendants = false,
		Parent = self.Container,
	}, { Corner(8) })
	-- Reserve the next layout slot so a nested group can later sit directly beneath this row.
	row:SetAttribute("NestOrder", nextOrder())
	if clickable then
		row.Text = ""
		row.AutoButtonColor = false
		row.MouseEnter:Connect(function()
			Tween(row, FAST, { BackgroundTransparency = 0.45 })
		end)
		row.MouseLeave:Connect(function()
			Tween(row, FAST, { BackgroundTransparency = 1 })
		end)
	end
	-- Optional leading icon shifts the text block right.
	local textX = 8
	if options.Icon then
		Icon(options.Icon, {
			Name = "Glyph",
			Position = UDim2.fromOffset(8, COMPACT and 8 or 9),
			Size = UDim2.fromOffset(COMPACT and 15 or 16, COMPACT and 15 or 16),
			ImageColor3 = Theme.SubText,
			Parent = row,
		})
		textX = COMPACT and 30 or 32
	end
	local name = Label({
		Name = "Title",
		Text = options.Name or "Element",
		TextSize = 15,
		Position = UDim2.fromOffset(textX, COMPACT and 7 or 8),
		Size = UDim2.new(1, -textX - 8, 0, 18),
		Parent = row,
	})
	local description
	if hasDescription then
		description = Label({
			Name = "Description",
			Text = options.Description,
			TextSize = COMPACT and 11 or 13,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(textX, COMPACT and 22 or 26),
			Size = UDim2.new(1, -textX - 8, 0, 14),
			Parent = row,
		})
		-- Elements shrink the title to make room for their control (switch, keycap...);
		-- the description follows so it never runs underneath that control.
		name:GetPropertyChangedSignal("Size"):Connect(function()
			description.Size = UDim2.new(name.Size.X.Scale, name.Size.X.Offset, 0, 14)
		end)
	end
	table.insert(self.Elements, { Name = options.Name or "", Frame = row })
	Library:_attachTooltip(row, tooltip)
	return row, name, header, description
end

local function registerFlag(options, api)
	if options.Flag then
		Library.Options[options.Flag] = api
	end
end

local function setFlag(options, value)
	if options.Flag then
		Library.Flags[options.Flag] = value
	end
end

-- Scrolls the owning column while an element expands so its new content never
-- opens below the fold. Follows the tween frame by frame instead of jumping.
local function revealWhileGrowing(frame, duration)
	local column = frame:FindFirstAncestorWhichIsA("ScrollingFrame")
	if not column then
		return
	end
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if os.clock() - started > (duration or 0.4) or not frame.Parent then
			connection:Disconnect()
			return
		end
		local s = Library.Window and Library.Window.Scale.Scale or 1
		local top = frame.AbsolutePosition.Y - column.AbsolutePosition.Y
		local overflow = frame.AbsolutePosition.Y + frame.AbsoluteSize.Y - (column.AbsolutePosition.Y + column.AbsoluteSize.Y - 10 * s)
		overflow = math.min(overflow, top - 6 * s)
		if overflow > 0.5 then
			column.CanvasPosition = Vector2.new(0, math.ceil(column.CanvasPosition.Y + overflow / s))
		end
	end)
	table.insert(Library._connections, connection)
end

-- Keycap (shared by Keybind and Toggle keybinds) ---------------------------------
local function createKeycap(parent, position, anchor)
	local cap = Create("TextButton", {
		Name = "Keycap",
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Elevated,
		Text = "None",
		FontFace = Fonts.Medium,
		TextSize = 13,
		TextColor3 = Theme.SubText,
		AutoButtonColor = false,
		Parent = parent,
	}, { Corner(6), Padding(0, 8, 0, 8) })
	local stroke = Stroke(Theme.Stroke)
	stroke.Parent = cap
	return cap, stroke
end

-- Binds a keycap to key-listening behaviour. Returns an API with Get/Set.
local function attachKeyPicker(cap, stroke, initial, onChanged)
	local picker = { Key = initial, Listening = false }

	local function render()
		cap.Text = picker.Listening and "..." or keyName(picker.Key)
		Tween(cap, FAST, { TextColor3 = (picker.Listening or picker.Key) and Theme.Text or Theme.Muted })
		Tween(stroke, FAST, { Color = picker.Listening and Theme.SubText or Theme.Stroke })
	end

	function picker:Set(key, silent)
		picker.Key = key
		render()
		if not silent then
			onChanged(key)
		end
	end

	function picker:Listen()
		if picker.Listening then
			return
		end
		picker.Listening = true
		Library._listening = true
		render()
		-- Breathing outline while waiting for a key.
		task.spawn(function()
			local bright = true
			while picker.Listening and cap.Parent do
				Tween(stroke, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Color = bright and Theme.Text or Theme.Stroke })
				bright = not bright
				task.wait(0.5)
			end
		end)
		local connection
		connection = UserInputService.InputBegan:Connect(function(input)
			local key
			if input.UserInputType == Enum.UserInputType.Keyboard then
				key = input.KeyCode
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
				key = input.UserInputType
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				return -- ignore the click that started listening; click another key instead
			else
				return
			end
			connection:Disconnect()
			picker.Listening = false
			task.defer(function()
				Library._listening = false
			end)
			if key == Enum.KeyCode.Escape then
				render()
				return
			end
			if key == Enum.KeyCode.Backspace or key == Enum.KeyCode.Delete then
				key = nil
			end
			picker:Set(key)
		end)
		table.insert(Library._connections, connection)
	end

	cap.Activated:Connect(function()
		picker:Listen()
	end)

	render()
	return picker
end

local function inputMatches(input, key)
	if not key then
		return false
	end
	if key.EnumType == Enum.KeyCode then
		return input.KeyCode == key
	end
	return input.UserInputType == key
end

-- Nested group -------------------------------------------------------------------
-- A clipped, animated container that sits beneath a row and behaves like a Section,
-- so any element can live inside it. Used by Toggle sub-options and Collapsible.
local function createNested(section, row)
	local outer = Create("Frame", {
		Name = (row and row.Name or "Group") .. "_Nested",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = false,
		LayoutOrder = row and row:GetAttribute("NestOrder") or nextOrder(),
		Parent = section.Container,
	})
	-- Guide line ties the children visually to their parent option.
	local guide = Create("Frame", {
		Name = "Guide",
		Position = UDim2.fromOffset(13, 2),
		Size = UDim2.new(0, 2, 1, -10),
		BackgroundColor3 = Theme.Stroke,
		BorderSizePixel = 0,
		Parent = outer,
	}, { Corner(1) })
	local inner = Create("Frame", {
		Name = "Inner",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = outer,
	}, { Padding(0, 0, 6, 18) })
	local innerList = List(1)
	innerList.Parent = inner

	local sub = setmetatable({
		Name = section.Name,
		Elements = section.Elements,
		Tab = section.Tab,
		Frame = section.Frame,
		Container = inner,
	}, Section)

	local open, token, follow = false, 0, nil
	local function contentHeight()
		local s = Library.Window and Library.Window.Scale.Scale or 1
		return math.floor(innerList.AbsoluteContentSize.Y / s + 0.5) + 6
	end

	local function setOpen(value, instant)
		open = value
		token += 1
		local mine = token
		if follow then
			follow:Disconnect()
			follow = nil
		end
		if value then
			outer.Visible = true
			local goal = UDim2.new(1, 0, 0, contentHeight())
			if instant then
				outer.Size = goal
			else
				guide.Size = UDim2.new(0, 2, 0, 0)
				Tween(guide, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size = UDim2.new(0, 2, 1, -10) })
				Tween(outer, SMOOTH, { Size = goal })
				revealWhileGrowing(outer)
			end
			-- Children that expand (dropdowns, pickers) keep resizing the group live.
			follow = innerList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				if open and mine == token then
					outer.Size = UDim2.new(1, 0, 0, contentHeight())
				end
			end)
		else
			Tween(outer, instant and TweenInfo.new(0) or SMOOTH, { Size = UDim2.new(1, 0, 0, 0) })
			task.delay(instant and 0 or SMOOTH.Time, function()
				if mine == token and not open then
					outer.Visible = false
				end
			end)
		end
	end

	return sub, setOpen, function()
		return open
	end
end

-- Toggle -----------------------------------------------------------------------
function Section:Toggle(options)
	options = options or {}
	local api = { Type = "Toggle", Value = options.Default == true }
	local row, title = self:_row(options, true)

	-- Switch metrics: knob size, travel (on position) and the squish width mid-travel.
	local KNOB, KNOB_ON, KNOB_SQUISH = COMPACT and 12 or 16, COMPACT and 17 or 19, COMPACT and 16 or 21
	local switch = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = COMPACT and UDim2.fromOffset(32, 18) or UDim2.fromOffset(38, 22),
		BackgroundColor3 = Theme.Elevated,
		Parent = row,
	}, { Corner(COMPACT and 9 or 11) })
	local switchStroke = Stroke(Theme.Stroke)
	switchStroke.Parent = switch
	local knob = Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(KNOB, KNOB),
		BackgroundColor3 = Theme.Muted,
		Parent = switch,
	}, { Corner(KNOB / 2) })

	local reserved = COMPACT and 46 or 54
	local picker
	if options.Keybind ~= nil then
		local cap, capStroke = createKeycap(row, UDim2.new(1, -54, 0.5, 0), Vector2.new(1, 0.5))
		picker = attachKeyPicker(cap, capStroke, options.Keybind or nil, function(key)
			if options.Flag then
				Library.Flags[options.Flag .. "_Key"] = key and key.Name or "None"
			end
		end)
		reserved = 118
		table.insert(Library._binds, {
			Name = options.Name or "Toggle",
			Get = function()
				return picker.Key
			end,
			State = function()
				return api.Value
			end,
			Press = function()
				api:Set(not api.Value)
			end,
		})
		if options.Flag then
			Library.Flags[options.Flag .. "_Key"] = picker.Key and picker.Key.Name or "None"
			Library.Options[options.Flag .. "_Key"] = {
				Type = "Keybind",
				Get = function()
					return picker.Key
				end,
				Set = function(_, key)
					picker:Set(key)
				end,
			}
		end
	end
	title.Size = UDim2.new(1, -reserved - title.Position.X.Offset + 8, 0, 18)
	api.KeyPicker = picker

	local nested, setNestedOpen, chevron
	local function render(instant)
		local info = instant and TweenInfo.new(0) or TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		Tween(switch, info, { BackgroundColor3 = api.Value and Theme.Accent or Theme.Elevated })
		Tween(switchStroke, info, { Color = api.Value and Theme.Accent or Theme.Stroke })
		Tween(knob, info, {
			Position = api.Value and UDim2.new(0, KNOB_ON, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
			BackgroundColor3 = api.Value and Theme.OnAccent or Theme.Muted,
		})
		if not instant then
			-- The knob stretches mid-travel and snaps back: a small, physical-feeling squish.
			knob.Size = UDim2.fromOffset(KNOB_SQUISH, KNOB)
			Tween(knob, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(KNOB, KNOB) })
			if api.Value then
				-- Switching on sends a soft accent ring out from the switch.
				local glow = Create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.new(1, 0, 1, 0),
					BackgroundTransparency = 1,
					ZIndex = switch.ZIndex,
					Parent = switch,
				}, { Corner(13), Create("UIStroke", { Color = Theme.Accent, Thickness = 1.5, Transparency = 0.25 }) })
				glow:SetAttribute("NoTheme", true)
				local glowInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
				Tween(glow, glowInfo, { Size = UDim2.new(1, 12, 1, 12) })
				Tween(glow:FindFirstChildOfClass("UIStroke"), glowInfo, { Transparency = 1 })
				task.delay(0.5, function()
					glow:Destroy()
				end)
			end
		end
		Tween(title, info, { TextColor3 = api.Value and Theme.Text or Theme.SubText })
		if setNestedOpen and chevron then
			setNestedOpen(api.Value, instant)
			Tween(chevron, instant and TweenInfo.new(0) or SMOOTH, {
				Rotation = api.Value and 90 or 0,
				ImageColor3 = api.Value and Theme.Text or Theme.Muted,
			})
		end
	end

	function api:Set(value, silent)
		value = value == true
		api.Value = value
		setFlag(options, value)
		render()
		if not silent then
			safeCall(options.Callback, value)
		end
	end
	function api:Get()
		return api.Value
	end

	-- Sub-options: a group of elements beneath the toggle. Always visible by default;
	-- SubOptions({ Fold = true }) brings back the old behaviour (unfolds only while on).
	function api:SubOptions(subOptions)
		if nested then
			return nested
		end
		nested, setNestedOpen = createNested(self._section, row)
		if not (type(subOptions) == "table" and subOptions.Fold) then
			setNestedOpen(true, true)
			return nested
		end
		chevron = Icon("chevron-right", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -(reserved + 2), 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			ImageColor3 = Theme.Muted,
			Parent = row,
		})
		reserved += 22
		title.Size = UDim2.new(1, -reserved - title.Position.X.Offset + 8, 0, 18)
		render(true)
		return nested
	end
	api._section = self

	row.Activated:Connect(function()
		api:Set(not api.Value)
	end)

	setFlag(options, api.Value)
	registerFlag(options, api)
	render(true)
	if api.Value and options.CallOnInit ~= false then
		safeCall(options.Callback, true)
	end
	return api
end

-- Slider -----------------------------------------------------------------------
function Section:Slider(options)
	options = options or {}
	local min, max = options.Min or 0, options.Max or 100
	local step = options.Increment or 1
	local suffix = options.Suffix or ""
	local function display(value)
		if type(options.Format) == "function" then
			return tostring(options.Format(value))
		end
		return formatNumber(value, step) .. suffix
	end
	local api = { Type = "Slider", Value = math.clamp(options.Default or min, min, max) }

	local row, _, header = self:_row(options, false)
	row.Size = UDim2.new(1, 0, 0, header + (COMPACT and 10 or 14))

	local valueBox = Create("TextBox", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, COMPACT and 6 or 8),
		Size = UDim2.fromOffset(70, 18),
		BackgroundTransparency = 1,
		Text = "",
		FontFace = Fonts.Medium,
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		ClearTextOnFocus = false,
		Parent = row,
	})
	row.Title.Size = UDim2.new(1, -90 - row.Title.Position.X.Offset + 8, 0, 18)

	local track = Create("Frame", {
		Position = UDim2.new(0, 8, 0, header - (COMPACT and 4 or 3)),
		Size = UDim2.new(1, -16, 0, COMPACT and 4 or 6),
		BackgroundColor3 = Theme.Elevated,
		BorderSizePixel = 0,
		Parent = row,
	}, { Corner(3) })
	local fill = Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = track,
	}, { Corner(3) })
	-- Light knob with a card-coloured ring, so it reads on both the fill and the empty track.
	local knob = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Theme.Text,
		ZIndex = 2,
		Parent = track,
	}, { Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Create("UIStroke", { Color = Theme.Surface, Thickness = 3 }) })
	local hitbox = Create("TextButton", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 3,
		Parent = track,
	})

	-- Value bubble that rides above the knob while dragging.
	local bubble = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -8),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Accent,
		Visible = false,
		ZIndex = 6,
		Parent = knob,
	}, { Corner(5), Padding(0, 7, 0, 7) })
	local bubbleText = Label({
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = Fonts.Medium,
		TextSize = 13,
		TextColor3 = Theme.OnAccent,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = 7,
		Parent = bubble,
	})
	local bubbleScale = Create("UIScale", { Scale = 0, Parent = bubble })
	local function showBubble(visible)
		if visible then
			bubble.Visible = true
			Tween(bubbleScale, BOUNCE, { Scale = 1 })
		else
			local t = Tween(bubbleScale, FAST, { Scale = 0 })
			t.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					bubble.Visible = false
				end
			end)
		end
	end

	local function render(instant)
		local alpha = (max > min) and (api.Value - min) / (max - min) or 0
		local info = instant and TweenInfo.new(0) or TweenInfo.new(0.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		Tween(fill, info, { Size = UDim2.fromScale(alpha, 1) })
		Tween(knob, info, { Position = UDim2.fromScale(alpha, 0.5) })
		bubbleText.Text = display(api.Value)
		if not valueBox:IsFocused() then
			valueBox.Text = display(api.Value)
		end
	end

	function api:Set(value, silent)
		value = tonumber(value)
		if not value then
			render()
			return
		end
		value = math.clamp(round(value, step), min, max)
		-- Normalise floating point residue from rounding (e.g. 0.30000000000000004).
		value = tonumber(formatNumber(value, step))
		local changed = value ~= api.Value
		api.Value = value
		setFlag(options, value)
		render()
		if changed and not silent then
			safeCall(options.Callback, value)
		end
	end
	function api:Get()
		return api.Value
	end

	local dragging = nil
	hitbox.MouseEnter:Connect(function()
		Tween(knob, FAST, { Size = UDim2.fromOffset(17, 17) })
	end)
	hitbox.MouseLeave:Connect(function()
		if not dragging then
			Tween(knob, FAST, { Size = UDim2.fromOffset(14, 14) })
		end
	end)
	local function update(x)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		api:Set(min + (max - min) * alpha)
	end
	hitbox.InputBegan:Connect(function(input)
		if claimPointer(input) then
			dragging = input
			Tween(knob, FAST, { Size = UDim2.fromOffset(17, 17) })
			Tween(valueBox, FAST, { TextColor3 = Theme.Text })
			update(input.Position.X)
			showBubble(true)
		end
	end)
	Connect(UserInputService.InputChanged, function(input)
		if movesPointer(dragging, input) then
			update(input.Position.X)
		end
	end)
	Connect(UserInputService.InputEnded, function(input)
		if endsPointer(dragging, input) then
			dragging = nil
			Tween(knob, FAST, { Size = UDim2.fromOffset(14, 14) })
			Tween(valueBox, FAST, { TextColor3 = Theme.SubText })
			showBubble(false)
		end
	end)

	valueBox.Focused:Connect(function()
		valueBox.Text = formatNumber(api.Value, step)
		Tween(valueBox, FAST, { TextColor3 = Theme.Text })
	end)
	valueBox.FocusLost:Connect(function()
		Tween(valueBox, FAST, { TextColor3 = Theme.SubText })
		local number = tonumber((valueBox.Text:gsub("[^%d%.%-]", "")))
		if number then
			api:Set(number)
		end
		valueBox.Text = display(api.Value)
	end)

	setFlag(options, api.Value)
	registerFlag(options, api)
	render(true)
	return api
end

-- Chevron drawn from two strokes; rotating each stroke flips it smoothly.
local function createChevron(parent, position)
	local holder = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = position,
		Size = UDim2.fromOffset(12, 8),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local left = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, -2, 0.5, 0),
		Size = UDim2.fromOffset(6, 1.5),
		Rotation = 45,
		BackgroundColor3 = Theme.SubText,
		BorderSizePixel = 0,
		Parent = holder,
	})
	local right = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 2, 0.5, 0),
		Size = UDim2.fromOffset(6, 1.5),
		Rotation = -45,
		BackgroundColor3 = Theme.SubText,
		BorderSizePixel = 0,
		Parent = holder,
	})
	return function(open)
		Tween(left, SMOOTH, { Rotation = open and -45 or 45, BackgroundColor3 = open and Theme.Text or Theme.SubText })
		Tween(right, SMOOTH, { Rotation = open and 45 or -45, BackgroundColor3 = open and Theme.Text or Theme.SubText })
	end
end

-- Dropdown ---------------------------------------------------------------------
function Section:Dropdown(options)
	options = options or {}
	local multi = options.Multi == true
	local api = { Type = "Dropdown", Options = table.clone(options.Options or {}), Open = false }
	if multi then
		api.Value = {}
		for _, v in ipairs(type(options.Default) == "table" and options.Default or {}) do
			api.Value[v] = true
		end
	else
		api.Value = options.Default
	end

	local row, title, header = self:_row(options, false)
	-- Compact without a description: the box sits inline on the title's row.
	local inline = COMPACT and not (type(options.Description) == "string" and options.Description ~= "")
	local BOX = COMPACT and 26 or 30
	local boxTop = inline and math.floor((header - BOX) / 2) or header - (COMPACT and 4 or 6)
	local closedHeight = inline and header or boxTop + BOX + (COMPACT and 6 or 8)
	row.Size = UDim2.new(1, 0, 0, closedHeight)
	row.ClipsDescendants = true

	local box = Create("TextButton", {
		AnchorPoint = inline and Vector2.new(1, 0) or Vector2.zero,
		Position = inline and UDim2.new(1, -6, 0, boxTop) or UDim2.fromOffset(8, boxTop),
		Size = inline and UDim2.new(0.56, -6, 0, BOX) or UDim2.new(1, -16, 0, BOX),
		BackgroundColor3 = Theme.Elevated,
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	}, { Corner(COMPACT and 7 or 8) })
	if inline then
		title.Size = UDim2.new(0.44, -title.Position.X.Offset, 0, 18)
	end
	local boxStroke = Stroke(Theme.Stroke)
	boxStroke.Parent = box
	local display = Label({
		Text = "",
		TextSize = 14,
		TextColor3 = Theme.SubText,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -36, 1, 0),
		Parent = box,
	})
	local setChevron = createChevron(box, UDim2.new(1, -10, 0.5, 0))

	local listFrame = Create("Frame", {
		Position = UDim2.fromOffset(8, inline and closedHeight + 2 or boxTop + BOX + 4),
		Size = UDim2.new(1, -16, 0, 0),
		BackgroundColor3 = Theme.Elevated,
		ClipsDescendants = true,
		Parent = row,
	}, { Corner(8) })
	Stroke(Theme.Stroke).Parent = listFrame

	local filter
	local searchable = #api.Options > 7 or options.Searchable
	if searchable then
		filter = Create("TextBox", {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 0, 24),
			BackgroundColor3 = Theme.Surface,
			Text = "",
			PlaceholderText = "Filter…",
			PlaceholderColor3 = Theme.Muted,
			TextColor3 = Theme.Text,
			FontFace = Fonts.Regular,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			Parent = listFrame,
		}, { Corner(6), Padding(0, 8, 0, 8) })
	end

	local scroller = Create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, searchable and 30 or 0),
		Size = UDim2.new(1, 0, 1, searchable and -30 or 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.Stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = listFrame,
	}, { List(0), Padding(4, 4, 4, 4) })

	local ITEM = COMPACT and 24 or 26
	local optionButtons = {}

	local function isSelected(value)
		if multi then
			return api.Value[value] == true
		end
		return api.Value == value
	end

	local function displayText()
		if multi then
			local picked = {}
			for _, value in ipairs(api.Options) do
				if api.Value[value] then
					table.insert(picked, tostring(value))
				end
			end
			return #picked > 0 and table.concat(picked, ", ") or "None"
		end
		return api.Value ~= nil and tostring(api.Value) or "None"
	end

	local function visibleCount()
		local count = 0
		for _, entry in ipairs(optionButtons) do
			if entry.Button.Visible then
				count += 1
			end
		end
		return count
	end

	local function listHeight()
		local count = math.max(visibleCount(), 1)
		return math.min(count, 6) * ITEM + 8 + (searchable and 30 or 0)
	end

	local layoutToken = 0
	local function layout(instant)
		local info = instant and TweenInfo.new(0) or SMOOTH
		local open = api.Open
		local h = open and listHeight() or 0
		-- A zero-height list would still draw its stroke as a hairline, so hide it once collapsed.
		layoutToken += 1
		local token = layoutToken
		if open then
			listFrame.Visible = true
		elseif instant then
			listFrame.Visible = false
		else
			task.delay(SMOOTH.Time, function()
				if token == layoutToken and not api.Open then
					listFrame.Visible = false
				end
			end)
		end
		Tween(listFrame, info, { Size = UDim2.new(1, -16, 0, h) })
		Tween(row, info, { Size = UDim2.new(1, 0, 0, closedHeight + (open and h + 4 or 0)) })
		Tween(boxStroke, FAST, { Color = open and Theme.Muted or Theme.Stroke })
		setChevron(open)
		if open and not instant then
			revealWhileGrowing(row)
		end
	end

	local function renderItems()
		for _, entry in ipairs(optionButtons) do
			local selected = isSelected(entry.Value)
			Tween(entry.Label, FAST, { TextColor3 = selected and Theme.Text or Theme.SubText })
			Tween(entry.MarkScale, selected and BOUNCE or FAST, { Scale = selected and 1 or 0 })
		end
		local text = displayText()
		display.Text = text
		display.TextColor3 = (text == "None") and Theme.Muted or Theme.Text
	end

	local function commit(silent)
		if multi then
			local list = {}
			for _, value in ipairs(api.Options) do
				if api.Value[value] then
					table.insert(list, value)
				end
			end
			setFlag(options, list)
			renderItems()
			if not silent then
				safeCall(options.Callback, list)
			end
		else
			setFlag(options, api.Value)
			renderItems()
			if not silent then
				safeCall(options.Callback, api.Value)
			end
		end
	end

	local function buildItems()
		for _, entry in ipairs(optionButtons) do
			entry.Button:Destroy()
		end
		table.clear(optionButtons)
		for index, value in ipairs(api.Options) do
			local button = Create("TextButton", {
				Size = UDim2.new(1, 0, 0, ITEM),
				BackgroundColor3 = Theme.Hover,
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = index,
				Parent = scroller,
			}, { Corner(6) })
			local label = Label({
				Text = tostring(value),
				TextSize = 14,
				TextColor3 = Theme.SubText,
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.new(1, -30, 1, 0),
				Parent = button,
			})
			local mark = Icon("check", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(14, 14),
				ImageColor3 = Theme.Text,
				Parent = button,
			})
			local markScale = Create("UIScale", { Scale = 0, Parent = mark })
			button.MouseEnter:Connect(function()
				Tween(button, FAST, { BackgroundTransparency = 0 })
			end)
			button.MouseLeave:Connect(function()
				Tween(button, FAST, { BackgroundTransparency = 1 })
			end)
			button.Activated:Connect(function()
				if multi then
					api.Value[value] = not api.Value[value] or nil
					commit()
				else
					if api.Value == value and options.AllowNone then
						api.Value = nil
					else
						api.Value = value
					end
					commit()
					api:Close()
				end
			end)
			table.insert(optionButtons, { Button = button, Label = label, Mark = mark, MarkScale = markScale, Value = value })
		end
		renderItems()
	end

	if filter then
		filter:GetPropertyChangedSignal("Text"):Connect(function()
			local query = filter.Text:lower()
			for _, entry in ipairs(optionButtons) do
				entry.Button.Visible = query == "" or tostring(entry.Value):lower():find(query, 1, true) ~= nil
			end
			if api.Open then
				layout()
			end
		end)
	end

	api._row = row
	api._list = listFrame
	function api:Close()
		if api.Open then
			api.Open = false
			layout()
		end
		if Library._openDropdown == api then
			Library._openDropdown = nil
		end
	end

	box.Activated:Connect(function()
		api.Open = not api.Open
		-- Only one list open at a time.
		if api.Open then
			if Library._openDropdown and Library._openDropdown ~= api then
				Library._openDropdown:Close()
			end
			Library._openDropdown = api
		elseif Library._openDropdown == api then
			Library._openDropdown = nil
		end
		layout()
		if api.Open then
			-- Items cascade in: each label slides a few pixels with a tiny stagger.
			local shown = 0
			for _, entry in ipairs(optionButtons) do
				if entry.Button.Visible then
					shown += 1
					entry.Label.Position = UDim2.fromOffset(16, 0)
					entry.Label.TextTransparency = 1
					task.delay(math.min(shown, 8) * 0.025, function()
						Tween(entry.Label, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(8, 0), TextTransparency = 0 })
					end)
				end
			end
		end
	end)
	box.MouseEnter:Connect(function()
		Tween(box, FAST, { BackgroundColor3 = Theme.Hover })
	end)
	box.MouseLeave:Connect(function()
		Tween(box, FAST, { BackgroundColor3 = Theme.Elevated })
	end)

	function api:Set(value, silent)
		if multi then
			api.Value = {}
			for _, v in ipairs(type(value) == "table" and value or {}) do
				if table.find(api.Options, v) then
					api.Value[v] = true
				end
			end
		else
			api.Value = table.find(api.Options, value) and value or nil
		end
		commit(silent)
	end
	function api:Get()
		if multi then
			local list = {}
			for _, v in ipairs(api.Options) do
				if api.Value[v] then
					table.insert(list, v)
				end
			end
			return list
		end
		return api.Value
	end
	function api:Refresh(newOptions, keepSelection)
		api.Options = table.clone(newOptions or {})
		if not keepSelection then
			api.Value = multi and {} or nil
		elseif multi then
			for v in pairs(api.Value) do
				if not table.find(api.Options, v) then
					api.Value[v] = nil
				end
			end
		elseif not table.find(api.Options, api.Value) then
			api.Value = nil
		end
		buildItems()
		commit(true)
		if api.Open then
			layout()
		end
	end

	buildItems()
	commit(true)
	layout(true)
	registerFlag(options, api)
	return api
end

-- Keybind ----------------------------------------------------------------------
function Section:Keybind(options)
	options = options or {}
	local mode = options.Mode or "Press" -- "Press" | "Hold" | "Toggle"
	local api = { Type = "Keybind", State = false }
	local row, title = self:_row(options, true)
	local cap, capStroke = createKeycap(row, UDim2.new(1, -8, 0.5, 0), Vector2.new(1, 0.5))
	title.Size = UDim2.new(1, -90 - title.Position.X.Offset + 8, 0, 18)
	title.TextColor3 = Theme.SubText

	local picker = attachKeyPicker(cap, capStroke, options.Default, function(key)
		setFlag(options, key and key.Name or "None")
		safeCall(options.ChangedCallback, key)
	end)
	row.Activated:Connect(function()
		picker:Listen() -- the whole row is a click target, not just the keycap
	end)

	table.insert(Library._binds, {
		Name = options.Name or "Keybind",
		Hidden = options.HideFromList,
		Get = function()
			return picker.Key
		end,
		State = function()
			if mode == "Press" then
				return nil
			end
			return api.State
		end,
		Press = function()
			if mode == "Toggle" then
				api.State = not api.State
				safeCall(options.Callback, api.State)
			elseif mode == "Hold" then
				api.State = true
				safeCall(options.Callback, true)
			else
				safeCall(options.Callback)
			end
		end,
		Release = function()
			if mode == "Hold" then
				api.State = false
				safeCall(options.Callback, false)
			end
		end,
	})

	function api:Set(key, silent)
		picker:Set(key, silent)
		if silent then
			setFlag(options, key and key.Name or "None")
		end
	end
	function api:Get()
		return picker.Key
	end

	setFlag(options, picker.Key and picker.Key.Name or "None")
	registerFlag(options, api)
	return api
end

-- Color picker -----------------------------------------------------------------
function Section:ColorPicker(options)
	options = options or {}
	local api = { Type = "ColorPicker", Value = options.Default or Color3.new(1, 1, 1), Open = false }
	local h, s, v = api.Value:ToHSV()

	local row, title, header = self:_row(options, true)
	row.ClipsDescendants = true
	title.Size = UDim2.new(1, -60 - title.Position.X.Offset + 8, 0, 18)
	local PANEL = 148

	local swatch = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0, header / 2),
		Size = UDim2.fromOffset(26, 16),
		BackgroundColor3 = api.Value,
		Parent = row,
	}, { Corner(4), Stroke(Theme.Stroke) })

	-- A button (not a frame) so clicks on empty panel space don't fall through and collapse the row.
	local panel = Create("TextButton", {
		Position = UDim2.fromOffset(8, header),
		Size = UDim2.new(1, -16, 0, PANEL - 8),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})

	local svBox = Create("TextButton", {
		Size = UDim2.new(1, -24, 0, 104),
		BackgroundColor3 = Color3.fromHSV(h, 1, 1),
		Text = "",
		AutoButtonColor = false,
		Parent = panel,
	}, { Corner(5) })
	-- live colour previews must never be recoloured by a theme change
	svBox:SetAttribute("NoTheme", true)
	swatch:SetAttribute("NoTheme", true)
	Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = svBox,
	}, {
		Corner(5),
		Create("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		}),
	})
	Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		Parent = svBox,
	}, {
		Corner(5),
		Create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
		}),
	})
	local svCursor = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = svBox,
	}, { Corner(5), Create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }) })

	local hueBar = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(12, 104),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Text = "",
		AutoButtonColor = false,
		Parent = panel,
	}, {
		Corner(4),
		Create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
				ColorSequenceKeypoint.new(1 / 6, Color3.fromHSV(1 / 6, 1, 1)),
				ColorSequenceKeypoint.new(2 / 6, Color3.fromHSV(2 / 6, 1, 1)),
				ColorSequenceKeypoint.new(3 / 6, Color3.fromHSV(3 / 6, 1, 1)),
				ColorSequenceKeypoint.new(4 / 6, Color3.fromHSV(4 / 6, 1, 1)),
				ColorSequenceKeypoint.new(5 / 6, Color3.fromHSV(5 / 6, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1)),
			}),
		}),
	})
	local hueCursor = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, h),
		Size = UDim2.new(1, 4, 0, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
		Parent = hueBar,
	}, { Corner(2), Create("UIStroke", { Color = Theme.Background, Thickness = 1 }) })

	local hexBox = Create("TextBox", {
		Position = UDim2.fromOffset(0, 112),
		Size = UDim2.new(0.5, -4, 0, 24),
		BackgroundColor3 = Theme.Elevated,
		Text = "",
		FontFace = Fonts.Medium,
		TextSize = 14,
		TextColor3 = Theme.Text,
		ClearTextOnFocus = false,
		Parent = panel,
	}, { Corner(5), Stroke(Theme.Stroke) })
	local rgbLabel = Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 112),
		Size = UDim2.new(0.5, -4, 0, 24),
		TextSize = 13,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = panel,
	})

	local function render()
		api.Value = Color3.fromHSV(h, s, v)
		swatch.BackgroundColor3 = api.Value
		svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		svCursor.Position = UDim2.fromScale(s, 1 - v)
		hueCursor.Position = UDim2.fromScale(0.5, h)
		if not hexBox:IsFocused() then
			hexBox.Text = "#" .. colorToHex(api.Value)
		end
		rgbLabel.Text = string.format("%d, %d, %d", api.Value.R * 255 + 0.5, api.Value.G * 255 + 0.5, api.Value.B * 255 + 0.5)
	end

	local function changed(silent)
		render()
		setFlag(options, api.Value)
		if not silent then
			safeCall(options.Callback, api.Value)
		end
	end

	function api:Set(color, silent)
		if typeof(color) == "string" then
			color = hexToColor(color)
		end
		if typeof(color) ~= "Color3" then
			return
		end
		h, s, v = color:ToHSV()
		changed(silent)
	end
	function api:Get()
		return api.Value
	end

	local mode, colorInput
	local function updateFrom(position)
		if mode == "sv" then
			local p, size = svBox.AbsolutePosition, svBox.AbsoluteSize
			s = math.clamp((position.X - p.X) / size.X, 0, 1)
			v = 1 - math.clamp((position.Y - p.Y) / size.Y, 0, 1)
		elseif mode == "hue" then
			local p, size = hueBar.AbsolutePosition, hueBar.AbsoluteSize
			h = math.clamp((position.Y - p.Y) / size.Y, 0, 0.999)
		end
		changed()
	end
	svBox.InputBegan:Connect(function(input)
		if claimPointer(input) then
			colorInput = input
			mode = "sv"
			updateFrom(input.Position)
		end
	end)
	hueBar.InputBegan:Connect(function(input)
		if claimPointer(input) then
			colorInput = input
			mode = "hue"
			updateFrom(input.Position)
		end
	end)
	Connect(UserInputService.InputChanged, function(input)
		if mode and movesPointer(colorInput, input) then
			updateFrom(input.Position)
		end
	end)
	Connect(UserInputService.InputEnded, function(input)
		if mode and endsPointer(colorInput, input) then
			mode = nil
		end
	end)

	hexBox.FocusLost:Connect(function()
		local color = hexToColor(hexBox.Text)
		if color then
			api:Set(color)
		else
			render()
		end
	end)

	panel.Visible = false
	local openToken = 0
	row.Activated:Connect(function()
		api.Open = not api.Open
		openToken += 1
		local token = openToken
		-- Hide the panel when collapsed so its cursors can't peek into the header row.
		if api.Open then
			panel.Visible = true
			revealWhileGrowing(row)
		else
			task.delay(SMOOTH.Time, function()
				if token == openToken and not api.Open then
					panel.Visible = false
				end
			end)
		end
		Tween(row, SMOOTH, { Size = UDim2.new(1, 0, 0, header + (api.Open and PANEL or 0)) })
		Tween(title, FAST, { TextColor3 = api.Open and Theme.Text or Theme.SubText })
	end)
	title.TextColor3 = Theme.SubText

	render()
	setFlag(options, api.Value)
	registerFlag(options, api)
	return api
end

-- Button -----------------------------------------------------------------------
function Section:Button(options)
	options = options or {}
	local holder = Create("Frame", {
		Name = options.Name or "Button",
		Size = UDim2.new(1, 0, 0, COMPACT and 32 or 38),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
		Parent = self.Container,
	})
	local primary = options.Style == "Primary"
	local danger = options.Style == "Danger"
	local DANGER = Color3.fromRGB(242, 120, 120)
	-- Read at use time so theme changes apply to hover states too.
	local function baseColor()
		return primary and Theme.Accent or Theme.Elevated
	end
	local function hoverColor()
		return primary and Theme.AccentHover or Theme.Hover
	end
	local base, ink = baseColor(), primary and Theme.OnAccent or (danger and DANGER or Theme.Text)

	local button = Create("TextButton", {
		Position = UDim2.fromOffset(COMPACT and 6 or 8, 4),
		Size = UDim2.new(1, COMPACT and -12 or -16, 0, COMPACT and 26 or 30),
		BackgroundColor3 = base,
		Text = "",
		AutoButtonColor = false,
		ClipsDescendants = true,
		Parent = holder,
	}, { Corner(8) })
	local stroke = Stroke(primary and Theme.Accent or (danger and DANGER or Theme.Stroke), danger and 0.7 or 0)
	stroke.Parent = button
	if danger then stroke:SetAttribute("NoTheme", true) end
	local press = Create("UIScale", { Parent = button })

	-- Icon + label centred as one unit.
	local content = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = button,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 7),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	if options.Icon then
		Icon(options.Icon, {
			Size = UDim2.fromOffset(15, 15),
			ImageColor3 = ink,
			LayoutOrder = 1,
			ZIndex = 2,
			Parent = content,
		})
	end
	local text = Label({
		Text = options.Name or "Button",
		FontFace = Fonts.Medium,
		TextSize = 14,
		TextColor3 = ink,
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None,
		LayoutOrder = 2,
		ZIndex = 2,
		Parent = content,
	})
	if danger then
		for _, d in ipairs(content:GetDescendants()) do d:SetAttribute("NoTheme", true) end
	end
	table.insert(self.Elements, { Name = options.Name or "", Frame = holder })
	Library:_attachTooltip(button, options.Tooltip)

	-- Centre on whole pixels: AnchorPoint 0.5 puts odd-width content on x.5 and blurs the label.
	content.AnchorPoint = Vector2.zero
	local function centre()
		local s = Library.Window and Library.Window.Scale.Scale or 1
		local free = (button.AbsoluteSize.X - content.AbsoluteSize.X) / s
		content.Position = UDim2.fromOffset(math.floor(free / 2), 6)
	end
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(centre)
	button:GetPropertyChangedSignal("AbsoluteSize"):Connect(centre)
	task.defer(centre)

	-- Ink ripple from the exact click point.
	local function ripple(x, y)
		local s = Library.Window and Library.Window.Scale.Scale or 1
		local localX = (x - button.AbsolutePosition.X) / s
		local localY = (y - button.AbsolutePosition.Y) / s
		local size = button.AbsoluteSize.X / s * 2.2
		local dot = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(localX, localY),
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = primary and Theme.OnAccent or Theme.Accent,
			BackgroundTransparency = primary and 0.85 or 0.88,
			ZIndex = 1,
			Parent = button,
		}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		Tween(dot, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
		})
		task.delay(0.6, function()
			dot:Destroy()
		end)
	end

	local armed = false
	button.MouseEnter:Connect(function()
		Tween(button, FAST, { BackgroundColor3 = hoverColor() })
		if not primary and not armed then
			-- the edge picks up the accent (red on destructive buttons) while hovered
			Tween(stroke, FAST, { Color = danger and DANGER or Theme.Accent, Transparency = danger and 0.35 or 0.55 })
		end
	end)
	button.MouseLeave:Connect(function()
		Tween(button, FAST, { BackgroundColor3 = baseColor() })
		Tween(press, FAST, { Scale = 1 })
		if not primary and not armed then
			Tween(stroke, FAST, { Color = danger and DANGER or Theme.Stroke, Transparency = danger and 0.7 or 0 })
		end
	end)
	button.MouseButton1Down:Connect(function(x, y)
		Tween(press, FAST, { Scale = 0.97 })
		ripple(x, y) -- same space as AbsolutePosition
	end)
	button.MouseButton1Up:Connect(function()
		Tween(press, BOUNCE, { Scale = 1 })
	end)

	button.Activated:Connect(function()
		if options.Confirm and not armed then
			armed = true
			text.Text = options.ConfirmText or "Click again to confirm"
			Tween(stroke, FAST, { Color = danger and DANGER or Theme.SubText, Transparency = 0 })
			task.delay(2.5, function()
				if armed then
					armed = false
					text.Text = options.Name or "Button"
					Tween(stroke, FAST, { Color = primary and Theme.Accent or (danger and DANGER or Theme.Stroke), Transparency = danger and 0.7 or 0 })
				end
			end)
			return
		end
		armed = false
		text.Text = options.Name or "Button"
		safeCall(options.Callback)
	end)

	return {
		SetText = function(_, value)
			options.Name = value
			text.Text = value
		end,
	}
end

-- Input ------------------------------------------------------------------------
function Section:Input(options)
	options = options or {}
	local api = { Type = "Input", Value = options.Default or "" }
	local row, _, header = self:_row(options, false)
	local boxTop = header - 6
	row.Size = UDim2.new(1, 0, 0, boxTop + 38)

	local box = Create("TextBox", {
		Position = UDim2.fromOffset(8, boxTop),
		Size = UDim2.new(1, -16, 0, 30),
		BackgroundColor3 = Theme.Elevated,
		Text = api.Value,
		PlaceholderText = options.Placeholder or "",
		PlaceholderColor3 = Theme.Muted,
		TextColor3 = Theme.Text,
		FontFace = Fonts.Regular,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ClearTextOnFocus = false,
		Parent = row,
	}, { Corner(8), Padding(0, 10, 0, 10) })
	local stroke = Stroke(Theme.Stroke)
	stroke.Parent = box

	if options.Numeric then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local cleaned = box.Text:gsub("[^%d%.%-]", "")
			if cleaned ~= box.Text then
				box.Text = cleaned
			end
		end)
	end
	if options.MaxLength then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if #box.Text > options.MaxLength then
				box.Text = box.Text:sub(1, options.MaxLength)
			end
		end)
	end

	box.Focused:Connect(function()
		Tween(stroke, FAST, { Color = Theme.Muted })
	end)
	box.FocusLost:Connect(function(enterPressed)
		Tween(stroke, FAST, { Color = Theme.Stroke })
		if options.Finished and not enterPressed then
			box.Text = api.Value
			return
		end
		api:Set(box.Text)
	end)

	function api:Set(text, silent)
		text = tostring(text or "")
		local changed = text ~= api.Value
		api.Value = text
		box.Text = text
		setFlag(options, text)
		if changed and not silent then
			safeCall(options.Callback, text)
		end
	end
	function api:Get()
		return api.Value
	end

	setFlag(options, api.Value)
	registerFlag(options, api)
	return api
end

-- Paragraph / Label / Divider --------------------------------------------------
function Section:Paragraph(options)
	options = options or {}
	local holder = Create("Frame", {
		Name = options.Title or "Paragraph",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
		Parent = self.Container,
	}, { Padding(6, 8, 8, 8), List(4) })
	local title
	if options.Title then
		title = Label({
			Text = options.Title,
			FontFace = Fonts.Medium,
			TextSize = 15,
			Size = UDim2.new(1, 0, 0, 16),
			LayoutOrder = 1,
			Parent = holder,
		})
	end
	local body = Label({
		Text = options.Content or "",
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = true,
		LineHeight = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = holder,
	})
	table.insert(self.Elements, { Name = (options.Title or "") .. " " .. (options.Content or ""), Frame = holder })
	return {
		Set = function(_, content, newTitle)
			body.Text = content or body.Text
			if title and newTitle then
				title.Text = newTitle
			end
		end,
	}
end

function Section:Label(options)
	if type(options) == "string" then
		options = { Name = options }
	end
	local row, title = self:_row(options, false)
	title.TextColor3 = Theme.SubText
	local value
	if options.Value ~= nil then
		title.Size = UDim2.new(0.5, -8, 0, 18)
		value = Label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.new(0.5, -8, 0, 18),
			Text = tostring(options.Value),
			FontFace = Fonts.Medium,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
	end
	return {
		Set = function(_, text)
			if value then
				value.Text = tostring(text)
			else
				title.Text = tostring(text)
			end
		end,
	}
end

function Section:Divider()
	local holder = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 9),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
		Parent = self.Container,
	})
	Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.new(1, -16, 0, 1),
		BackgroundColor3 = Theme.StrokeSoft,
		BorderSizePixel = 0,
		Parent = holder,
	})
end

-- Checkbox ---------------------------------------------------------------------
function Section:Checkbox(options)
	options = options or {}
	local api = { Type = "Toggle", Value = options.Default == true }
	local row, title = self:_row(options, true)
	title.Size = UDim2.new(1, -40 - title.Position.X.Offset + 8, 0, 18)

	local box = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(COMPACT and 16 or 19, COMPACT and 16 or 19),
		BackgroundColor3 = Theme.Elevated,
		Parent = row,
	}, { Corner(COMPACT and 5 or 6) })
	local boxStroke = Stroke(Theme.Stroke)
	boxStroke.Parent = box
	local mark = Icon("check", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(13, 13),
		ImageColor3 = Theme.OnAccent,
		Parent = box,
	})
	local markScale = Create("UIScale", { Parent = mark })

	local function render(instant)
		local info = instant and TweenInfo.new(0) or FAST
		Tween(box, info, { BackgroundColor3 = api.Value and Theme.Accent or Theme.Elevated })
		Tween(boxStroke, info, { Color = api.Value and Theme.Accent or Theme.Stroke })
		Tween(title, info, { TextColor3 = api.Value and Theme.Text or Theme.SubText })
		Tween(markScale, instant and TweenInfo.new(0) or (api.Value and BOUNCE or FAST), { Scale = api.Value and 1 or 0 })
	end

	function api:Set(value, silent)
		api.Value = value == true
		setFlag(options, api.Value)
		render()
		if not silent then
			safeCall(options.Callback, api.Value)
		end
	end
	function api:Get()
		return api.Value
	end
	row.Activated:Connect(function()
		api:Set(not api.Value)
	end)

	setFlag(options, api.Value)
	registerFlag(options, api)
	render(true)
	return api
end

-- Segmented control --------------------------------------------------------------
-- Inline single choice with a pill that glides between segments.
function Section:Segmented(options)
	options = options or {}
	local choices = options.Options or {}
	local api = { Type = "Segmented", Value = options.Default or choices[1] }
	local row, _, header = self:_row(options, false)
	local top = header - 6
	row.Size = UDim2.new(1, 0, 0, top + 32 + 8)

	local track = Create("Frame", {
		Position = UDim2.fromOffset(8, top),
		Size = UDim2.new(1, -16, 0, 32),
		BackgroundColor3 = Theme.Elevated,
		Parent = row,
	}, { Corner(9), Stroke(Theme.Stroke) })
	local pill = Create("Frame", {
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(0, 0, 1, -6),
		BackgroundColor3 = Theme.Accent,
		Parent = track,
	}, { Corner(7) })

	local segments = {}
	for index, choice in ipairs(choices) do
		local button = Create("TextButton", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = tostring(choice),
			FontFace = Fonts.Medium,
			TextSize = 14,
			TextColor3 = Theme.SubText,
			AutoButtonColor = false,
			ZIndex = 2,
			Parent = track,
		})
		segments[index] = { Button = button, Value = choice }
		button.Activated:Connect(function()
			api:Set(choice)
		end)
		button.MouseEnter:Connect(function()
			if api.Value ~= choice then
				Tween(button, FAST, { TextColor3 = Theme.Text })
			end
		end)
		button.MouseLeave:Connect(function()
			if api.Value ~= choice then
				Tween(button, FAST, { TextColor3 = Theme.SubText })
			end
		end)
	end

	-- Segment geometry is computed in whole pixels (scale-based thirds land on x.5 and blur text).
	local geometry = {}
	local function measure()
		local s = Library.Window and Library.Window.Scale.Scale or 1
		local width = math.floor(track.AbsoluteSize.X / s + 0.5) - 6
		local count = math.max(#segments, 1)
		local base = math.floor(width / count)
		local x = 3
		for index, segment in ipairs(segments) do
			local w = index == count and (width + 3 - x) or base
			segment.Button.Position = UDim2.fromOffset(x, 0)
			segment.Button.Size = UDim2.new(0, w, 1, 0)
			geometry[index] = { X = x, W = w }
			x += w
		end
	end

	local function render(instant)
		local index = table.find(choices, api.Value)
		local g = index and geometry[index]
		if g then
			local goal = { Position = UDim2.fromOffset(g.X, 3), Size = UDim2.new(0, g.W, 1, -6) }
			Tween(pill, instant and TweenInfo.new(0) or TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal)
		end
		pill.Visible = g ~= nil
		for i, segment in ipairs(segments) do
			Tween(segment.Button, instant and TweenInfo.new(0) or FAST, { TextColor3 = i == index and Theme.OnAccent or Theme.SubText })
		end
	end

	track:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		measure()
		render(true)
	end)

	function api:Set(value, silent)
		if not table.find(choices, value) then
			return
		end
		local changed = value ~= api.Value
		api.Value = value
		setFlag(options, value)
		render()
		if changed and not silent then
			safeCall(options.Callback, value)
		end
	end
	function api:Get()
		return api.Value
	end

	measure()
	render(true)
	setFlag(options, api.Value)
	registerFlag(options, api)
	return api
end

-- Stepper ------------------------------------------------------------------------
-- Compact −/+ number control; holding a button repeats with acceleration.
function Section:Stepper(options)
	options = options or {}
	local min, max, step = options.Min or 0, options.Max or 100, options.Increment or 1
	local api = { Type = "Slider", Value = math.clamp(options.Default or min, min, max) }
	local row, title = self:_row(options, false)
	title.Size = UDim2.new(1, -120 - title.Position.X.Offset + 8, 0, 18)

	local group = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0, 17),
		Size = UDim2.fromOffset(104, 26),
		BackgroundColor3 = Theme.Elevated,
		Parent = row,
	}, { Corner(8), Stroke(Theme.Stroke) })
	local valueLabel = Label({
		Position = UDim2.fromOffset(26, 0),
		Size = UDim2.fromOffset(52, 26),
		FontFace = Fonts.Medium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = group,
	})
	local valueScale = Create("UIScale", { Parent = valueLabel })

	local function button(icon, x)
		local b = Create("TextButton", {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = Theme.Hover,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Parent = group,
		}, { Corner(8) })
		local glyph = Icon(icon, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(13, 13),
			ImageColor3 = Theme.SubText,
			Parent = b,
		})
		b.MouseEnter:Connect(function()
			Tween(b, FAST, { BackgroundTransparency = 0 })
			Tween(glyph, FAST, { ImageColor3 = Theme.Text })
		end)
		b.MouseLeave:Connect(function()
			Tween(b, FAST, { BackgroundTransparency = 1 })
			Tween(glyph, FAST, { ImageColor3 = Theme.SubText })
		end)
		return b
	end
	local minus = button("minus", 0)
	local plus = button("plus", 78)

	local function render()
		valueLabel.Text = formatNumber(api.Value, step) .. (options.Suffix or "")
	end

	function api:Set(value, silent)
		value = tonumber(value)
		if not value then
			return
		end
		value = tonumber(formatNumber(math.clamp(round(value, step), min, max), step))
		local changed = value ~= api.Value
		api.Value = value
		setFlag(options, value)
		render()
		if changed then
			valueScale.Scale = 1.18
			Tween(valueScale, BOUNCE, { Scale = 1 })
			if not silent then
				safeCall(options.Callback, value)
			end
		end
	end
	function api:Get()
		return api.Value
	end

	local function hold(b, direction)
		local holding = false
		b.MouseButton1Down:Connect(function()
			holding = true
			api:Set(api.Value + step * direction)
			task.delay(0.4, function()
				local interval = 0.09
				while holding and b.Parent do
					api:Set(api.Value + step * direction)
					task.wait(interval)
					interval = math.max(interval * 0.9, 0.03)
				end
			end)
		end)
		local function release()
			holding = false
		end
		b.MouseButton1Up:Connect(release)
		b.MouseLeave:Connect(release)
	end
	hold(minus, -1)
	hold(plus, 1)

	render()
	setFlag(options, api.Value)
	registerFlag(options, api)
	return api
end

-- Progress -----------------------------------------------------------------------
-- Read-only meter for things like cooldowns, health or task progress.
function Section:Progress(options)
	options = options or {}
	local max = options.Max or 100
	local api = { Value = options.Default or 0 }
	local row, title, header = self:_row(options, false)
	row.Size = UDim2.new(1, 0, 0, header + 12)
	title.Size = UDim2.new(1, -70 - title.Position.X.Offset + 8, 0, 18)
	local valueLabel = Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(60, 18),
		FontFace = Fonts.Medium,
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	local bar = Create("Frame", {
		Position = UDim2.new(0, 8, 0, header - 3),
		Size = UDim2.new(1, -16, 0, 6),
		BackgroundColor3 = Theme.Elevated,
		BorderSizePixel = 0,
		Parent = row,
	}, { Corner(3) })
	local fill = Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = bar,
	}, { Corner(3) })

	function api:Set(value)
		api.Value = math.clamp(tonumber(value) or 0, 0, max)
		local alpha = max > 0 and api.Value / max or 0
		Tween(fill, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size = UDim2.fromScale(alpha, 1) })
		valueLabel.Text = type(options.Format) == "function" and tostring(options.Format(api.Value, max))
			or string.format("%d%%", alpha * 100 + 0.5)
	end
	function api:Get()
		return api.Value
	end
	api:Set(api.Value)
	return api
end

-- Collapsible group ---------------------------------------------------------------
-- A clickable header that folds a group of elements open and closed.
function Section:Collapsible(options)
	options = options or {}
	local row, title = self:_row(options, true)
	title.Size = UDim2.new(1, -36 - title.Position.X.Offset + 8, 0, 18)
	title.TextColor3 = Theme.SubText
	local chevron = Icon("chevron-right", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		ImageColor3 = Theme.Muted,
		Parent = row,
	})
	local sub, setOpen, isOpen = createNested(self, row)
	local function apply(value, instant)
		setOpen(value, instant)
		Tween(chevron, instant and TweenInfo.new(0) or SMOOTH, {
			Rotation = value and 90 or 0,
			ImageColor3 = value and Theme.Text or Theme.Muted,
		})
		Tween(title, FAST, { TextColor3 = value and Theme.Text or Theme.SubText })
	end
	row.Activated:Connect(function()
		apply(not isOpen())
	end)
	task.defer(apply, options.Open ~= false, true)
	return sub
end

--// Global input ------------------------------------------------------------------

-- Clicking anywhere outside the open dropdown closes it.
Connect(UserInputService.InputBegan, function(input)
	local open = Library._openDropdown
	if not open or not isPointer(input) then
		return
	end
	local p, row = input.Position, open._row
	local a, s = row.AbsolutePosition, row.AbsoluteSize
	if p.X < a.X or p.X > a.X + s.X or p.Y < a.Y or p.Y > a.Y + s.Y then
		open:Close()
	end
end)

Connect(UserInputService.InputBegan, function(input, gameProcessed)
	if Library._listening then
		return
	end
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if inputMatches(input, Library.ToggleKey) and Library.Window then
		Library:Toggle()
		return
	end
	if gameProcessed and input.UserInputType == Enum.UserInputType.Keyboard then
		return
	end
	for _, bind in ipairs(Library._binds) do
		if inputMatches(input, bind.Get()) then
			bind.Press()
		end
	end
end)

Connect(UserInputService.InputEnded, function(input)
	if Library._listening then
		return
	end
	for _, bind in ipairs(Library._binds) do
		if bind.Release and inputMatches(input, bind.Get()) then
			bind.Release()
		end
	end
end)

--// Keybind list overlay ---------------------------------------------------------------

do
	local panel = Create("Frame", {
		Name = "KeybindList",
		Active = true,
		-- Below Roblox's top bar buttons (the ScreenGui ignores the inset).
		Position = UDim2.fromOffset(16, game:GetService("GuiService"):GetGuiInset().Y + 16),
		Size = UDim2.fromOffset(200, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Surface,
		Visible = false,
		ZIndex = 20,
		Parent = ScreenGui,
	}, { Corner(12), Stroke(Theme.Stroke), Padding(12, 14, 12, 14), List(7) })

	local header = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		LayoutOrder = 0,
		ZIndex = 20,
		Parent = panel,
	})
	Icon("keyboard", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromOffset(0, 1),
		ImageColor3 = Theme.SubText,
		ZIndex = 21,
		Parent = header,
	})
	Label({
		Text = "Keybinds",
		FontFace = Fonts.SemiBold,
		TextSize = 14,
		Position = UDim2.fromOffset(22, 0),
		Size = UDim2.new(1, -22, 1, 0),
		ZIndex = 21,
		Parent = header,
	})
	local empty = Label({
		Text = "No keys bound",
		TextSize = 13,
		TextColor3 = Theme.Muted,
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = 1,
		ZIndex = 21,
		Parent = panel,
	})

	local rows = {}
	local function rowFor(bind)
		if rows[bind] then
			return rows[bind]
		end
		local frame = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			ZIndex = 20,
			Parent = panel,
		})
		local name = Label({
			Text = bind.Name,
			TextSize = 14,
			Size = UDim2.new(1, -60, 1, 0),
			ZIndex = 21,
			Parent = frame,
		})
		local key = Label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 56, 1, 0),
			FontFace = Fonts.Medium,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 21,
			Parent = frame,
		})
		rows[bind] = { Frame = frame, Name = name, Key = key }
		return rows[bind]
	end

	-- Drag the overlay anywhere; position is kept in offsets so it survives resizes.
	local dragStart, origin, panelInput
	panel.InputBegan:Connect(function(input)
		if claimPointer(input) then
			panelInput = input
			dragStart, origin = input.Position, panel.Position
		end
	end)
	Connect(UserInputService.InputChanged, function(input)
		if dragStart and movesPointer(panelInput, input) then
			local delta = input.Position - dragStart
			local vp, size = ScreenGui.AbsoluteSize, panel.AbsoluteSize
			panel.Position = UDim2.fromOffset(math.clamp(origin.X.Offset + delta.X, 0, math.max(0, vp.X - size.X)), math.clamp(origin.Y.Offset + delta.Y, 0, math.max(0, vp.Y - math.min(size.Y, 32))))
		end
	end)
	Connect(UserInputService.InputEnded, function(input)
		if dragStart and endsPointer(panelInput, input) then
			dragStart = nil
		end
	end)

	Connect(ScreenGui:GetPropertyChangedSignal("AbsoluteSize"), function()
		local vp, size = ScreenGui.AbsoluteSize, panel.AbsoluteSize
		panel.Position = UDim2.fromOffset(math.clamp(panel.Position.X.Offset, 0, math.max(0, vp.X - size.X)), math.clamp(panel.Position.Y.Offset, 0, math.max(0, vp.Y - math.min(size.Y, 32))))
		endsPointer(panelInput, panelInput)
		dragStart = nil
	end)
	local accumulator = 0
	Connect(RunService.Heartbeat, function(dt)
		accumulator += dt
		if not panel.Visible or accumulator < 0.1 then
			return
		end
		accumulator = 0
		local shown = 0
		for _, bind in ipairs(Library._binds) do
			local key = bind.Get()
			local row = rowFor(bind)
			local visible = key ~= nil and not bind.Hidden
			row.Frame.Visible = visible
			if visible then
				shown += 1
				local state = bind.State and bind.State()
				row.Key.Text = "[" .. keyName(key) .. "]"
				row.Name.TextColor3 = (state == false) and Theme.Muted or Theme.Text
				row.Key.TextColor3 = (state == false) and Theme.Muted or Theme.SubText
			end
		end
		empty.Visible = shown == 0
	end)

	function Library:SetKeybindListVisible(visible)
		panel.Visible = visible
	end
end

--// Watermark ------------------------------------------------------------------------

do
	local mark = Create("Frame", {
		Name = "Watermark",
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Surface,
		Visible = false,
		ZIndex = 20,
		Parent = ScreenGui,
	}, {
		Corner(8),
		Stroke(Theme.Stroke),
		Padding(0, 10, 0, 5),
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local logo = Create("Frame", {
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Theme.Accent,
		LayoutOrder = 1,
		ZIndex = 21,
		Parent = mark,
	}, { Corner(5) })
	Label({
		Text = "N",
		FontFace = Fonts.Bold,
		TextSize = 13,
		TextColor3 = Theme.OnAccent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 22,
		Parent = logo,
	})
	local text = Label({
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = Fonts.Medium,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.None,
		RichText = true,
		LayoutOrder = 2,
		ZIndex = 21,
		Parent = mark,
	})

	-- Right-aligned by computed whole-pixel offset (AnchorPoint 1 would land on x.5).
	local inset = game:GetService("GuiService"):GetGuiInset().Y
	local function place()
		local x = math.floor(ScreenGui.AbsoluteSize.X - mark.AbsoluteSize.X - 16)
		mark.Position = UDim2.fromOffset(x, inset + 16)
	end
	mark:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	Connect(ScreenGui:GetPropertyChangedSignal("AbsoluteSize"), place)

	local frames, clock = 0, 0
	Connect(RunService.RenderStepped, function(dt)
		frames += 1
		clock += dt
		if clock < 0.5 or not mark.Visible then
			if clock >= 0.5 then
				frames, clock = 0, 0
			end
			return
		end
		local fps = frames / clock
		frames, clock = 0, 0
		local ok, ping = pcall(function()
			return LocalPlayer:GetNetworkPing() * 1000
		end)
		local dim = '<font color="#8A8A92">·</font>'
		text.Text = string.format("Crown Hub %s %d fps %s %s ms %s %s", dim, fps + 0.5, dim, ok and tostring(math.floor(ping + 0.5)) or "—", dim, os.date("%H:%M"))
	end)

	function Library:SetWatermarkVisible(visible)
		mark.Visible = visible
		place()
	end
end

--// Configs -------------------------------------------------------------------------

-- Configs live in CrownHub/configs, or CrownHub/configs/<scope> once a script calls
-- Library:SetConfigScope("NDS"): a multi-game hub keeps each game's configs and autoload apart.
Library.ConfigScope = nil
local function configDir()
	local base = Library.Folder .. "/configs"
	return Library.ConfigScope and (base .. "/" .. Library.ConfigScope) or base
end
local function autoloadPath()
	return Library.ConfigScope and (configDir() .. "/autoload.txt") or (Library.Folder .. "/autoload.txt")
end
function Library:SetConfigScope(name)
	local scope = tostring(name or ""):gsub("[^%w%-_]", "")
	self.ConfigScope = scope ~= "" and scope or nil
end

local function ensureFolders()
    if not FS.available then return false end
    local ok = pcall(function()
        for _, path in ipairs({Library.Folder, Library.Folder .. "/configs", configDir()}) do
            if not FS.isfolder(path) then FS.makefolder(path) end
        end
    end)
    if not ok then FS.available = false end
    return ok
end

local function encodeValue(option)
	local value = option:Get()
	if option.Type == "ColorPicker" then
		return colorToHex(value)
	elseif option.Type == "Keybind" then
		return value and value.Name or "None"
	end
	return value
end

local function decodeValue(option, raw)
	if option.Type == "ColorPicker" then
		return hexToColor(raw)
	elseif option.Type == "Keybind" then
		return keyFromName(raw)
	end
	return raw
end

function Library:SaveConfig(name)
	if not ensureFolders() then
		return false, "File system unavailable"
	end
	name = tostring(name or ""):gsub("[^%w%s%-_]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		return false, "Invalid config name"
	end
	local data = {}
	for flag, option in pairs(self.Options) do
		if not option.NoSave then
			data[flag] = encodeValue(option)
		end
	end
	local ok, err = pcall(FS.writefile, configDir() .. "/" .. name .. ".json", HttpService:JSONEncode(data))
	return ok, err
end

function Library:LoadConfig(name)
	if not ensureFolders() then
		return false, "File system unavailable"
	end
	local path = configDir() .. "/" .. tostring(name) .. ".json"
	if not FS.exists(path) then
		return false, "Config not found"
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(FS.readfile(path))
	end)
	if not ok or type(data) ~= "table" then
		return false, "Config is corrupted"
	end
	for flag, raw in pairs(data) do
		local option = self.Options[flag]
		if option and not option.NoSave then
			task.spawn(function()
				option:Set(decodeValue(option, raw))
			end)
		end
	end
	return true
end

function Library:ExportConfig()
	local data = {}
	for flag, option in pairs(self.Options) do
		if not option.NoSave then
			data[flag] = encodeValue(option)
		end
	end
	local ok, json = pcall(HttpService.JSONEncode, HttpService, data)
	if ok then
		return json
	end
	return nil, "Could not encode config"
end

function Library:ImportConfig(json)
	if type(json) ~= "string" or json == "" then
		return false, "Empty JSON"
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or type(data) ~= "table" then
		return false, "Invalid JSON"
	end
	local applied = 0
	for flag, raw in pairs(data) do
		local option = self.Options[flag]
		if option and not option.NoSave then
			task.spawn(function()
				option:Set(decodeValue(option, raw))
			end)
			applied += 1
		end
	end
	return true, applied
end

function Library:OverwriteConfig(name)
	-- Same as SaveConfig but requires the name to already exist
	if not ensureFolders() then
		return false, "File system unavailable"
	end
	name = tostring(name or ""):gsub("[^%w%s%-_]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		return false, "Select a config first"
	end
	local path = configDir() .. "/" .. name .. ".json"
	if not FS.exists(path) then
		return false, "Config not found — use Save to create it"
	end
	return self:SaveConfig(name)
end

function Library:DeleteConfig(name)
	if not ensureFolders() or not FS.delfile then
		return false, "File system unavailable"
	end
	local path = configDir() .. "/" .. tostring(name) .. ".json"
	if not FS.exists(path) then
		return false, "Config not found"
	end
	return pcall(FS.delfile, path)
end

function Library:ListConfigs()
	if not ensureFolders() then
		return {}
	end
	if not FS.listfiles then return {} end
	local ok, files = pcall(FS.listfiles, configDir())
	if not ok or type(files) ~= "table" then return {} end
	local list = {}
	for _, file in ipairs(files) do
		local name = tostring(file):match("([^/\\]+)%.json$")
		if name then
			table.insert(list, name)
		end
	end
	table.sort(list)
	return list
end

function Library:GetAutoload()
	if not ensureFolders() then
		return nil
	end
	local path = autoloadPath()
	if FS.exists(path) then
		local ok, name = pcall(FS.readfile, path)
		return ok and type(name) == "string" and name ~= "" and name or nil
	end
	return nil
end

function Library:SetAutoload(name)
	if not ensureFolders() then
		return false
	end
	return pcall(FS.writefile, autoloadPath(), name or "")
end

--// Themes ----------------------------------------------------------------------------
-- Every element copies Theme colours into its properties when it is built, and hover /
-- toggle code reads Theme again each time it animates. Switching themes therefore does
-- two things: mutate Theme (so everything animated or created later uses the new colours)
-- and repaint the existing tree by swapping every property that still holds an old theme
-- colour for its new counterpart. Instances tagged with the "NoTheme" attribute (colour
-- picker swatches and the like) are left alone.
--
-- Gradient themes: a theme is two colours, A → B. Theme.Accent becomes their per-channel
-- maximum, and every accent-filled surface gets a UIGradient whose keypoints are A/Accent
-- and B/Accent. UIGradient multiplies, so the rendered result is exactly A → B, while text,
-- icons and anything that only reads Theme.Accent still get one solid colour.

local NEUTRAL = table.clone(Theme)
local PAINT_PROPS = { "BackgroundColor3", "TextColor3", "ImageColor3", "PlaceholderColor3", "ScrollBarImageColor3" }
local THEME_FILE = Library.Folder .. "/theme.json"

local function colorKey(c)
	return math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
end

local function channelMax(a, b)
	return Color3.new(math.max(a.R, b.R), math.max(a.G, b.G), math.max(a.B, b.B))
end

-- Surface ladder: { brightness, how strongly the layer takes the theme hue }. Every layer is
-- built from the same hue, so a theme colours the whole window instead of just its accents.
local LADDER = {
	Background = { 0.045, 1.00 },
	Sidebar = { 0.057, 0.95 },
	Surface = { 0.080, 0.85 },
	Elevated = { 0.116, 0.75 },
	Hover = { 0.152, 0.70 },
	StrokeSoft = { 0.112, 0.90 },
	Stroke = { 0.180, 0.90 },
}
-- Text keeps its brightness and only leans toward the hue, so contrast never drops.
local INK = {
	Text = { 0.984, 0.03 },
	SubText = { 0.875, 0.10 },
	Muted = { 0.635, 0.18 },
}

-- Builds a full palette from a gradient. `tint` (0..1) is how much of the theme's hue flows
-- into the dark surfaces and the text; the brightness ladder stays fixed so the layers keep
-- the same contrast in every theme.
local function buildTheme(a, b, tint)
	b = b or a
	tint = math.clamp(tint or 0, 0, 1)
	local theme = table.clone(NEUTRAL)
	local mid = a:Lerp(b, 0.5)
	local h, s = mid:ToHSV()
	s = math.min(s, 1)
	for key, step in pairs(LADDER) do
		local sat = math.min(s * tint * step[2] * 1.4, 0.75)
		-- saturated darks look darker than grey ones of the same value; lift them to match
		theme[key] = Color3.fromHSV(h, sat, math.min(step[1] * (1 + sat * 0.8), 1))
	end
	for key, step in pairs(INK) do
		theme[key] = Color3.fromHSV(h, math.min(s * tint * step[2] * 1.6, 0.3), step[1])
	end
	local accent = channelMax(a, b)
	local ah, as, av = accent:ToHSV()
	theme.Accent = accent
	theme.AccentHover = Color3.fromHSV(ah, as, av * 0.86)
	-- Ink on accent surfaces: those render the full a→b gradient, so pick whichever of dark or
	-- light ink keeps the better contrast against the weaker of the two ends (WCAG ratio).
	local function relative(c)
		local function channel(x)
			return x <= 0.03928 and x / 12.92 or ((x + 0.055) / 1.055) ^ 2.4
		end
		return 0.2126 * channel(c.R) + 0.7152 * channel(c.G) + 0.0722 * channel(c.B)
	end
	local function contrast(x, y)
		local p, q = relative(x), relative(y)
		return (math.max(p, q) + 0.05) / (math.min(p, q) + 0.05)
	end
	local dark, light = NEUTRAL.OnAccent, Color3.fromRGB(250, 250, 252)
	local darkScore = math.min(contrast(dark, a), contrast(dark, b))
	local lightScore = math.min(contrast(light, a), contrast(light, b))
	theme.OnAccent = darkScore >= lightScore and dark or light
	return theme
end

-- Two keys sharing a colour would make the repaint ambiguous, so nudge duplicates by one
-- step of blue — invisible, but keeps every theme key unique.
local function ensureUnique(theme)
	local used = {}
	for _, key in ipairs({ "Text", "SubText", "Muted", "Background", "Sidebar", "Surface", "Elevated", "Hover", "Stroke", "StrokeSoft", "OnAccent", "AccentHover", "Accent" }) do
		local c = theme[key]
		while used[colorKey(c)] do
			local b = math.floor(c.B * 255 + 0.5)
			c = Color3.fromRGB(math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), b >= 255 and b - 1 or b + 1)
		end
		used[colorKey(c)] = true
		theme[key] = c
	end
	return theme
end

local rgb = Color3.fromRGB
Library.Themes = {
	-- Only two themes: Halloween (orange) and Christmas (green/red)
	Halloween = { A = rgb(255, 140, 0), B = rgb(255, 69, 0) },
	Christmas = { A = rgb(34, 139, 34), B = rgb(220, 20, 60) },
}
Library.ThemeOrder = { "Halloween", "Christmas" }
Library.CurrentTheme = "Halloween"
Library.ThemeTint = 0 -- 0 keeps the window surfaces neutral; only the accent is coloured
Library.Backdrop = "Solid" -- "Depth" (soft light from the top, in the theme's hue) | "Solid"
Library._backdrops = {}
Library.GradientStyle = "Static" -- "Static" (default, no motion) | "Flow" (colours stream along) | "Spin"
Library.GradientAngle = 0 -- degrees, for Flow and Static
Library.GradientSpeed = 1
Library.GradientAnimated = false -- legacy mirror: GradientStyle ~= "Static"
Library.Roundness = 1 -- multiplier for every rounded corner
Library.FontFamily = "BuilderSans"
Library.FontFamilies = {
	"BuilderSans", "GothamSSm", "Montserrat", "Ubuntu", "Nunito", "Roboto",
	"Arimo", "SourceSansPro", "RobotoCondensed", "TitilliumWeb", "JosefinSans", "Oswald",
	"Jura", "Michroma", "Sarpanch", "BuilderExtended", "BuilderMono", "RobotoMono",
	"FredokaOne", "Merriweather",
}
Library.ThemeGradient ={ A = Library.Themes.Halloween.A, B = Library.Themes.Halloween.B }
Library._themeCallbacks = {}

function Library:OnThemeChanged(callback)
	table.insert(self._themeCallbacks, callback)
end

-- Accent gradients ---------------------------------------------------------------------

local accentGradients = setmetatable({}, { __mode = "k" }) -- [host] = UIGradient
local activeGradients = setmetatable({}, { __mode = "k" }) -- [UIGradient] = true

local function ratio(color, accent)
	local function r(c, m)
		return m > 0.001 and math.clamp(c / m, 0, 1) or 1
	end
	return Color3.new(r(color.R, accent.R), r(color.G, accent.G), r(color.B, accent.B))
end

local function distance(a, b)
	return math.sqrt((a.R - b.R) ^ 2 + (a.G - b.G) ^ 2 + (a.B - b.B) ^ 2)
end

-- How "accent" a colour is: 1 at Accent/AccentHover, fading to 0 a short distance away, so
-- a switch tweening into the accent blends its gradient in instead of popping.
local function accentWeight(color)
	local d = math.min(distance(color, Theme.Accent), distance(color, Theme.AccentHover))
	return math.clamp(1 - d / 0.22, 0, 1)
end

local function updateGradient(host)
	if host:GetAttribute("NoTheme") or host:GetAttribute("NoGradient") then
		return
	end
	local color = host:IsA("UIStroke") and host.Color or host.BackgroundColor3
	local weight = accentWeight(color)
	local gradient = accentGradients[host]
	if weight <= 0 then
		if gradient then
			gradient.Enabled = false
			activeGradients[gradient] = nil
		end
		return
	end
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Name = "CrownAccent"
		gradient:SetAttribute("NoTheme", true)
		gradient.Parent = host
		gradient.Rotation = Library.GradientAngle
		accentGradients[host] = gradient
	end
	local white = Color3.new(1, 1, 1)
	local g = Library.ThemeGradient
	local a = white:Lerp(ratio(g.A, Theme.Accent), weight)
	local b = white:Lerp(ratio(g.B, Theme.Accent), weight)
	if Library.GradientStyle == "Flow" then
		-- A → B → A: both ends match, so sliding the offset loops without a seam
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, a),
			ColorSequenceKeypoint.new(0.5, b),
			ColorSequenceKeypoint.new(1, a),
		})
	else
		gradient.Color = ColorSequence.new(a, b)
	end
	gradient.Enabled = true
	activeGradients[gradient] = true
end

local function watch(object)
	if object:IsA("UIStroke") then
		object:GetPropertyChangedSignal("Color"):Connect(function()
			updateGradient(object)
		end)
		updateGradient(object)
	elseif object:IsA("GuiObject") and not object:IsA("TextLabel") and not object:IsA("TextBox") and not object:IsA("ScrollingFrame") then
		object:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
			updateGradient(object)
		end)
		updateGradient(object)
	end
end

for _, object in ipairs(ScreenGui:GetDescendants()) do
	watch(object)
end
Connect(ScreenGui.DescendantAdded, function(object)
	-- deferred so Create() has finished setting the starting colours
	task.defer(function()
		if object.Parent then
			watch(object)
		end
	end)
end)

local function refreshGradients()
	for host in pairs(accentGradients) do
		if host.Parent then
			updateGradient(host)
		end
	end
	for _, object in ipairs(ScreenGui:GetDescendants()) do
		if not accentGradients[object] then
			if object:IsA("UIStroke") or (object:IsA("GuiObject") and not object:IsA("TextLabel") and not object:IsA("TextBox")) then
				updateGradient(object)
			end
		end
	end
end

-- Every accent gradient moves together. Flow streams the colours along the angle, Spin
-- turns the gradient (a full turn every ~9 s at 100%), Static just holds the angle.
local gradientClock = 0
Connect(RunService.RenderStepped, function(dt)
	if not Library.Open then
		return
	end
	local style = Library.GradientStyle
	if style == "Static" or Library.GradientSpeed == 0 then return end
	gradientClock += dt
	if UserInputService.TouchEnabled and gradientClock < 1 / 30 then return end
	gradientClock = 0
	local t = os.clock() * Library.GradientSpeed
	local rotation, offset = Library.GradientAngle, Vector2.zero
	if style == "Spin" then
		rotation = (t * 40) % 360
	elseif style == "Flow" then
		offset = Vector2.new((t * 0.35) % 2 - 1, 0)
	end
	for gradient in pairs(activeGradients) do
		gradient.Rotation = rotation
		gradient.Offset = offset
	end
end)

-- Roundness ------------------------------------------------------------------------------
-- Each UICorner remembers its designed radius the first time it is seen; the multiplier is
-- applied on top. Pill/circle corners (scale-based) are left as they are.

local function applyCorner(corner)
	if corner.CornerRadius.Scale > 0 then
		return
	end
	local base = corner:GetAttribute("BaseRadius")
	if not base then
		base = corner.CornerRadius.Offset
		corner:SetAttribute("BaseRadius", base)
	end
	corner.CornerRadius = UDim.new(0, math.floor(base * Library.Roundness + 0.5))
end

Connect(ScreenGui.DescendantAdded, function(object)
	if object:IsA("UICorner") then
		task.defer(function()
			if object.Parent and Library.Roundness ~= 1 then
				applyCorner(object)
			end
		end)
	end
end)

function Library:SetRoundness(multiplier)
	self.Roundness = math.clamp(tonumber(multiplier) or 1, 0, 2)
	for _, object in ipairs(ScreenGui:GetDescendants()) do
		if object:IsA("UICorner") then
			applyCorner(object)
		end
	end
	if self._saveTheme then
		self._saveTheme()
	end
end

-- Font -------------------------------------------------------------------------------------
-- Swaps the family everywhere and keeps each label's weight, so the hierarchy survives.

local function familyAsset(name)
	return "rbxasset://fonts/families/" .. name .. ".json"
end

local function applyFontFamily(object, fromAsset, toAsset)
	if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		local face = object.FontFace
		if face.Family == fromAsset then
			object.FontFace = Font.new(toAsset, face.Weight, face.Style)
		end
	end
end

function Library:SetFont(name)
	if not table.find(self.FontFamilies, name) then
		return false
	end
	local fromAsset, toAsset = familyAsset(self.FontFamily), familyAsset(name)
	self.FontFamily = name
	for key, face in pairs(Fonts) do
		Fonts[key] = Font.new(toAsset, face.Weight, face.Style)
	end
	for _, object in ipairs(ScreenGui:GetDescendants()) do
		applyFontFamily(object, fromAsset, toAsset)
	end
	if self._saveTheme then
		self._saveTheme()
	end
	return true
end

-- Theme application ----------------------------------------------------------------------

local function repaint(map, instant)
	local info = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	for _, object in ipairs(ScreenGui:GetDescendants()) do
		if not object:GetAttribute("NoTheme") then
			if object:IsA("UIStroke") then
				local target = map[colorKey(object.Color)]
				if target then
					if instant then
						object.Color = target
					else
						Tween(object, info, { Color = target })
					end
				end
			elseif object:IsA("GuiObject") then
				local goals
				for _, prop in ipairs(PAINT_PROPS) do
					local ok, value = pcall(function()
						return object[prop]
					end)
					local target = ok and typeof(value) == "Color3" and map[colorKey(value)]
					if target then
						goals = goals or {}
						goals[prop] = target
					end
				end
				if goals then
					if instant then
						for prop, value in pairs(goals) do
							object[prop] = value
						end
					else
						Tween(object, info, goals)
					end
				end
			end
		end
	end
end

local function saveTheme()
	if not FS.available then
		return
	end
	pcall(function()
		if not FS.isfolder(Library.Folder) then
			FS.makefolder(Library.Folder)
		end
		FS.writefile(THEME_FILE, HttpService:JSONEncode({
			Name = Library.CurrentTheme,
			A = colorToHex(Library.ThemeGradient.A),
			B = colorToHex(Library.ThemeGradient.B),
			Tint = Library.ThemeTint,
			Style = Library.GradientStyle,
			Angle = Library.GradientAngle,
			Speed = Library.GradientSpeed,
			Roundness = Library.Roundness,
			Font = Library.FontFamily,
			Backdrop = Library.Backdrop,
			V = 2,
		}))
	end)
end
Library._saveTheme = saveTheme

local function applyPalette(palette, gradient, name, opts)
	local new = table.clone(Theme)
	for key, value in pairs(palette) do
		if new[key] ~= nil and typeof(value) == "Color3" then
			new[key] = value
		end
	end
	ensureUnique(new)

	local map = {}
	for key, old in pairs(Theme) do
		if colorKey(old) ~= colorKey(new[key]) then
			map[colorKey(old)] = new[key]
		end
	end
	for key, value in pairs(new) do
		Theme[key] = value
	end
	Library.ThemeGradient = gradient
	Library.CurrentTheme = name
	if next(map) then
		repaint(map, opts.Instant)
		-- Hover/press tweens that were already running finish on the old colours; sweep once
		-- more after they settle.
		if not opts.Instant then
			task.delay(0.45, function()
				if not Library.Unloaded then
					repaint(map, true)
					refreshGradients()
				end
			end)
		end
	end
	refreshGradients()
	if opts.Save ~= false then
		saveTheme()
	end
	for _, callback in ipairs(Library._themeCallbacks) do
		safeCall(callback, name, Theme)
	end
	return true
end

-- Applies a gradient. `a`/`b` are the two colours (b defaults to a for a solid accent).
-- Options: { Instant = bool, Save = bool (default true), Name = string }.
function Library:SetGradient(a, b, opts)
	if typeof(a) ~= "Color3" then
		return false
	end
	b = typeof(b) == "Color3" and b or a
	opts = opts or {}
	local palette = buildTheme(a, b, self.ThemeTint)
	local preset = opts.Name and self.Themes[opts.Name]
	if preset and preset.Palette then
		for key, value in pairs(preset.Palette) do palette[key] = value end
	end
	return applyPalette(palette, { A = a, B = b }, opts.Name or "Custom", opts)
end

-- `theme` is a preset name (see Library.ThemeOrder) or a palette table of Theme keys.
function Library:SetTheme(theme, opts)
	opts = opts or {}
	if type(theme) == "string" then
		local preset = self.Themes[theme]
		if not preset then
			return false
		end
		opts.Name = theme
		return self:SetGradient(preset.A, preset.B, opts)
	elseif type(theme) == "table" then
		local accent = theme.Accent or Theme.Accent
		return applyPalette(theme, { A = accent, B = accent }, opts.Name or "Custom", opts)
	end
	return false
end

-- Kept for scripts that set one colour: a solid accent is a gradient from it to itself.
function Library:SetAccent(color, opts)
	return self:SetGradient(color, color, opts)
end

function Library:SetThemeTint(amount, opts)
	self.ThemeTint = math.clamp(amount or 0, 0, 1)
	opts = opts or {}
	opts.Name = self.CurrentTheme
	return self:SetGradient(self.ThemeGradient.A, self.ThemeGradient.B, opts)
end

-- "Flow" | "Spin" | "Static". Flow uses a three-stop gradient, so the colours are rebuilt.
function Library:SetGradientStyle(style)
	if style ~= "Flow" and style ~= "Spin" and style ~= "Static" then
		return false
	end
	self.GradientStyle = style
	self.GradientAnimated = style ~= "Static"
	for gradient in pairs(activeGradients) do
		gradient.Offset = Vector2.zero
		gradient.Rotation = self.GradientAngle
	end
	refreshGradients()
	saveTheme()
	return true
end

-- Legacy switch from the first theme API: on = Flow, off = Static.
function Library:SetGradientAnimated(value)
	return self:SetGradientStyle(value and "Flow" or "Static")
end

function Library:SetGradientAngle(degrees)
	self.GradientAngle = (tonumber(degrees) or 0) % 360
	for gradient in pairs(activeGradients) do
		gradient.Rotation = self.GradientAngle
	end
	saveTheme()
end

function Library:SetGradientSpeed(multiplier)
	self.GradientSpeed = math.clamp(tonumber(multiplier) or 1, 0.1, 5)
	saveTheme()
end

-- "Depth" lays a soft light over the window and panel tops, in the theme's hue; "Solid" keeps
-- the plain background.
function Library:SetBackdrop(style)
	if style ~= "Depth" and style ~= "Solid" then
		return false
	end
	self.Backdrop = style
	for _, frame in ipairs(self._backdrops) do
		if frame.Parent then
			frame.Visible = style == "Depth"
		end
	end
	saveTheme()
	return true
end

function Library:GetTheme()
	return table.clone(Theme), self.CurrentTheme, self.ThemeGradient
end

-- Ready-made "Theme" section for any tab: preset list, the two gradient colours, gradient
-- style / angle / speed, background tint, roundness, font and reset. One line in a game
-- script:  Library:AddThemeSection(ConfigTab, "Right")
function Library:AddThemeSection(tab, side)
	local section = tab:Section({ Name = "Theme", Icon = "palette", Side = side or "Right" })
	-- Only Halloween and Christmas — one simple selector
	section:Segmented({
		Name = "Theme",
		Options = { "Halloween", "Christmas" },
		Default = (self.CurrentTheme == "Christmas") and "Christmas" or "Halloween",
		Callback = function(value)
			if value then
				self:SetTheme(value)
			end
		end,
	})
	return section
end


-- Restore the last theme before any window exists, so everything is built in it directly.
do
	local restored = false
	if FS.available then
		pcall(function()
			if FS.isfile(THEME_FILE) then
				local data = HttpService:JSONDecode(FS.readfile(THEME_FILE))
				-- A theme file from before the blue default (no V) is ignored once, so the new look shows.
				if data.V ~= 2 then error("old theme file") end
				Library.ThemeTint = tonumber(data.Tint) or Library.ThemeTint
				if data.Style == "Flow" or data.Style == "Spin" or data.Style == "Static" then
					Library.GradientStyle = data.Style
				elseif data.Animated == false then
					Library.GradientStyle = "Static"
				end
				Library.GradientAnimated = Library.GradientStyle ~= "Static"
				Library.GradientAngle = (tonumber(data.Angle) or 0) % 360
				Library.GradientSpeed = math.clamp(tonumber(data.Speed) or 1, 0.1, 5)
				Library.Roundness = math.clamp(tonumber(data.Roundness) or 1, 0, 2)
				if data.Backdrop == "Solid" or data.Backdrop == "Depth" then
					Library.Backdrop = data.Backdrop
				end
				if data.Font and table.find(Library.FontFamilies, data.Font) and data.Font ~= Library.FontFamily then
					local toAsset = familyAsset(data.Font)
					for key, face in pairs(Fonts) do
						Fonts[key] = Font.new(toAsset, face.Weight, face.Style)
					end
					Library.FontFamily = data.Font
				end
				local opts = { Instant = true, Save = false }
				if data.Name and Library.Themes[data.Name] then
					restored = Library:SetTheme(data.Name, opts)
				else
					local a = hexToColor(data.A or data.Accent or "")
					local b = hexToColor(data.B or "") or a
					if a then
						opts.Name = "Custom"
						restored = Library:SetGradient(a, b, opts)
					end
				end
			end
		end)
	end
	if not restored then
		Library:SetTheme("Halloween", { Instant = true, Save = false })
	end
end

-- Elements built later pick up the restored font and roundness on their own: Label() reads
-- Fonts at creation, and new UICorners are scaled as they are added.

--// Config tab builder -------------------------------------------------------------------
-- One call builds a complete settings page for any game script in the hub:
--     Library:AddConfigSections(ConfigTab, {
--         Scope = "NDS",                                   -- per-game config folder + autoload
--         Reexecute = 'loadstring(readfile("NDS.lua"))()', -- optional: re-run after teleports
--     })
-- Sections: Interface, Configs, Theme, Server, Performance. Everything restores on unload.

function Library:AddConfigSections(tab, opts)
	opts = opts or {}
	if opts.Scope then
		self:SetConfigScope(opts.Scope)
	end
	local TeleportService = game:GetService("TeleportService")
	local setclipboard = envFunction("setclipboard") or envFunction("toclipboard")
	local httpRequest = requestFunction()
	local queueOnTeleport = envFunction("queue_on_teleport") or envFunction("queueonteleport") or namespaceFunction("syn", "queue_on_teleport")
	local setfpscap = envFunction("setfpscap")
	local getfpscap = envFunction("getfpscap")
	local identifyexecutor = envFunction("identifyexecutor")

	local function notify(title, content, kind)
		self:Notify({ Title = title, Content = content, Type = kind or "info", Duration = 3 })
	end
	local function copy(text, what)
		if setclipboard and pcall(setclipboard, text) then
			notify("Copied", what .. " is on your clipboard.", "success")
		else
			notify(what, text)
		end
	end

	-- Interface ------------------------------------------------------------------------
	local interface = tab:Section({ Name = "Interface", Icon = "monitor", Side = "Left" })
	local menuBind
	menuBind = interface:Keybind({
		Name = "Menu key", Icon = "keyboard", Default = self.ToggleKey, HideFromList = true, Flag = "menu_key",
		ChangedCallback = function(key)
			if not key then
				menuBind:Set(Enum.KeyCode.RightShift)
				return
			end
			self.ToggleKey = key
		end,
	})
	interface:Slider({
		Name = "Scale", Icon = "move", Min = 70, Max = 130, Default = 100, Increment = 5, Suffix = "%", Flag = "ui_scale",
		Callback = function(value)
			self.UserScale = value / 100
			if self.Window then
				self.Window:UpdateScale()
			end
		end,
	})
	interface:Toggle({ Name = "Notifications", Icon = "bell", Default = true, CallOnInit = false, Flag = "ui_notifications", Callback = function(value) self.NotificationsEnabled = value end })
	interface:Toggle({ Name = "Keybind list", Icon = "list", Flag = "keybind_list", Callback = function(value) self:SetKeybindListVisible(value) end })
	interface:Toggle({ Name = "Watermark", Icon = "activity", Flag = "ui_watermark", Callback = function(value) self:SetWatermarkVisible(value) end })
	if queueOnTeleport and opts.Reexecute then
		local queued = false
		interface:Toggle({
			Name = "Re-execute on teleport", Icon = "refresh-cw", Description = "Loads the hub again after a rejoin or server hop",
			Flag = "ui_reexecute",
			Callback = function(value)
				if value and not queued then
					queued = true
					pcall(queueOnTeleport, opts.Reexecute)
				end
			end,
		})
	end
	interface:Divider()
	interface:Button({
		Name = "Close hub", Icon = "power", Confirm = true, ConfirmText = "Click again to close",
		Callback = function()
			self:Unload()
		end,
	})

	-- Configs --------------------------------------------------------------------------
	local configs = tab:Section({ Name = "Configs", Icon = "folder", Side = "Left" })
	if not FS.available then
		configs:Label({ Name = "File system unavailable" })
	else
		local nameInput = configs:Input({ Name = "Config name", Icon = "save", Placeholder = "e.g. main", MaxLength = 32 })
		local list = configs:Dropdown({ Name = "Saved configs", Icon = "folder", Options = self:ListConfigs(), AllowNone = true })
		local autoloadLabel = configs:Label({ Name = "Autoload", Value = self:GetAutoload() or "None" })
		local function refresh()
			list:Refresh(self:ListConfigs(), true)
			autoloadLabel:Set(self:GetAutoload() or "None")
		end
		configs:Button({
			Name = "Save", Icon = "save", Style = "Primary",
			Callback = function()
				local name = nameInput:Get()
				if name == "" then
					name = list:Get() or ""
				end
				local ok, err = self:SaveConfig(name)
				notify(ok and "Config saved" or "Could not save", ok and name or tostring(err), ok and "success" or "error")
				refresh()
			end,
		})
		configs:Button({
			Name = "Overwrite", Icon = "refresh-cw",
			Callback = function()
				local name = list:Get() or nameInput:Get()
				if not name or name == "" then
					notify("Select a config first", nil, "warning")
					return
				end
				local ok, err = self:OverwriteConfig(name)
				notify(ok and "Config overwritten" or "Could not overwrite", ok and name or tostring(err), ok and "success" or "error")
				refresh()
			end,
		})
		configs:Button({
			Name = "Load", Icon = "download",
			Callback = function()
				local name = list:Get()
				if not name then
					notify("Select a config first", nil, "warning")
					return
				end
				local ok, err = self:LoadConfig(name)
				notify(ok and "Config loaded" or "Could not load", ok and name or tostring(err), ok and "success" or "error")
			end,
		})
		configs:Button({
			Name = "Delete", Icon = "trash-2", Style = "Danger", Confirm = true, ConfirmText = "Click again to delete",
			Callback = function()
				local name = list:Get()
				if not name then
					notify("Select a config first", nil, "warning")
					return
				end
				local ok = self:DeleteConfig(name)
				if ok and self:GetAutoload() == name then
					self:SetAutoload("")
				end
				notify(ok and "Config deleted" or "Could not delete", name, ok and "success" or "error")
				refresh()
			end,
		})
		configs:Button({
			Name = "Set as autoload", Icon = "star",
			Callback = function()
				local name = list:Get()
				self:SetAutoload(name or "")
				notify("Autoload", name and (name .. " loads on start") or "Autoload cleared")
				refresh()
			end,
		})
		configs:Button({ Name = "Refresh list", Icon = "refresh-cw", Callback = refresh })
		configs:Divider()
		configs:Button({
			Name = "Export JSON", Icon = "copy",
			Callback = function()
				local json, err = self:ExportConfig()
				if not json then
					notify("Export failed", tostring(err), "error")
					return
				end
				if setclipboard and pcall(setclipboard, json) then
					notify("Exported", "Config JSON copied to clipboard.", "success")
				else
					print("[Crown Hub] Config JSON:\n" .. json)
					notify("Export JSON", "Clipboard unavailable — printed to console.", "warning")
				end
			end,
		})
		local jsonInput = configs:Input({ Name = "Import JSON", Placeholder = "Paste config JSON here", MaxLength = 100000 })
		configs:Button({
			Name = "Import from JSON", Icon = "download", Style = "Primary",
			Callback = function()
				local text = jsonInput:Get()
				if not text or text == "" then
					notify("Paste JSON first", nil, "warning")
					return
				end
				local ok, result = self:ImportConfig(text)
				if ok then
					notify("Config imported", "Applied " .. tostring(result) .. " setting(s).", "success")
					jsonInput:Set("")
				else
					notify("Import failed", tostring(result), "error")
				end
			end,
		})
		local autoload = self:GetAutoload()
		if autoload then
			task.delay(0.5, function()
				if not self.Unloaded and self:LoadConfig(autoload) then
					notify("Autoloaded config", autoload, "success")
				end
			end)
		end
	end

	-- Theme ----------------------------------------------------------------------------
	self:AddThemeSection(tab, "Right")

	-- Server ---------------------------------------------------------------------------
	local server = tab:Section({ Name = "Server", Icon = "wifi", Side = "Right" })
	local playersLabel = server:Label({ Name = "Players", Value = "—" })
	local uptimeLabel = server:Label({ Name = "Server uptime", Value = "—" })
	task.spawn(function()
		while not self.Unloaded do
			playersLabel:Set(#Players:GetPlayers() .. " / " .. Players.MaxPlayers)
			local t = math.floor(Workspace.DistributedGameTime)
			uptimeLabel:Set(string.format("%dh %02dm", t // 3600, (t % 3600) // 60))
			task.wait(2)
		end
	end)
	server:Button({
		Name = "Rejoin", Icon = "refresh-cw",
		Callback = function()
			if #Players:GetPlayers() <= 1 then
				TeleportService:Teleport(game.PlaceId, LocalPlayer)
			else
				TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
			end
		end,
	})
	local function fetchServers()
		local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
		local ok, body = pcall(function()
			if httpRequest then
				local response = httpRequest({ Url = url, Method = "GET" })
                if type(response) ~= "table" then error("Invalid HTTP response") end
                local status = tonumber(response.StatusCode or response.status_code or response.Status or response.status)
                if status and (status < 200 or status >= 300) then error("HTTP request failed") end
                local body = response.Body or response.body
                if type(body) ~= "string" then error("HTTP response body unavailable") end
                return body
			end
			return game:HttpGet(url)
		end)
		if not ok or type(body) ~= "string" then
			return nil
		end
		local decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
		return decoded and type(data) == "table" and data.data or nil
	end
	local function hop(pick)
		local servers = fetchServers()
		if not servers then
			notify("Server hop", "Could not reach the server list.", "error")
			return
		end
		local candidates = {}
		for _, s in ipairs(servers) do
			if s.id ~= game.JobId and tonumber(s.playing) and tonumber(s.maxPlayers) and s.playing < s.maxPlayers then
				table.insert(candidates, s)
			end
		end
		if #candidates == 0 then
			notify("Server hop", "No other server with free slots.", "warning")
			return
		end
		local target = pick(candidates)
		notify("Server hop", "Joining a server with " .. target.playing .. " players…")
		TeleportService:TeleportToPlaceInstance(game.PlaceId, target.id, LocalPlayer)
	end
	server:Button({
		Name = "Server hop", Icon = "arrow-right", Style = "Primary",
		Callback = function()
			task.spawn(hop, function(list)
				return list[math.random(1, #list)]
			end)
		end,
	})
	server:Button({
		Name = "Smallest server", Icon = "user",
		Callback = function()
			task.spawn(hop, function(list)
				table.sort(list, function(a, b)
					return a.playing < b.playing
				end)
				return list[1]
			end)
		end,
	})
	server:Button({ Name = "Copy JobId", Icon = "copy", Callback = function() copy(game.JobId, "JobId") end })
	server:Button({
		Name = "Copy join script", Icon = "clipboard",
		Callback = function()
			copy(string.format('game:GetService("TeleportService"):TeleportToPlaceInstance(%d, "%s")', game.PlaceId, game.JobId), "Join script")
		end,
	})

	-- Performance ----------------------------------------------------------------------
	local perf = tab:Section({ Name = "Performance", Icon = "gauge", Side = "Left" })
	if setfpscap then
		local original = getfpscap and getfpscap() or 60
		local unlocked, cap = false, 144
		local function applyCap()
			pcall(setfpscap, unlocked and 0 or cap)
		end
		perf:Toggle({ Name = "Unlock FPS", Icon = "zap", Flag = "perf_unlock", Callback = function(value) unlocked = value applyCap() end })
		perf:Slider({ Name = "FPS cap", Icon = "gauge", Min = 30, Max = 360, Increment = 10, Default = 144, Flag = "perf_cap", Callback = function(value) cap = value if not unlocked then applyCap() end end })
		self:OnUnload(function()
			pcall(setfpscap, original)
		end)
	end

	-- Low graphics: shadows, fog, particles, decals/textures. Originals are kept and put back.
	local saved = {}
	local lowOn = false
	local function lowGraphics(on)
		lowOn = on
		if on then
			saved.GlobalShadows = Lighting.GlobalShadows
			saved.FogEnd = Lighting.FogEnd
			Lighting.GlobalShadows = false
			Lighting.FogEnd = 1e9
			saved.objects = {}
			for _, object in ipairs(Workspace:GetDescendants()) do
				if object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Smoke") or object:IsA("Fire") or object:IsA("Sparkles") then
					if object.Enabled then
						saved.objects[object] = "Enabled"
						object.Enabled = false
					end
				elseif object:IsA("Decal") or object:IsA("Texture") then
					if object.Transparency < 1 then
						saved.objects[object] = object.Transparency
						object.Transparency = 1
					end
				end
			end
			for _, effect in ipairs(Lighting:GetChildren()) do
				if effect:IsA("PostEffect") and effect.Enabled then
					saved.objects[effect] = "Enabled"
					effect.Enabled = false
				end
			end
		elseif saved.objects then
			Lighting.GlobalShadows = saved.GlobalShadows
			Lighting.FogEnd = saved.FogEnd
			for object, value in pairs(saved.objects) do
				if object.Parent then
					if value == "Enabled" then
						object.Enabled = true
					else
						object.Transparency = value
					end
				end
			end
			saved.objects = nil
		end
	end
	perf:Toggle({ Name = "Low graphics", Icon = "monitor", Description = "No shadows, fog, particles or textures", Flag = "perf_low", Callback = lowGraphics })
	self:OnUnload(function()
		if lowOn then
			lowGraphics(false)
		end
	end)

	local antiAfk = false
	local VirtualUser = game:GetService("VirtualUser")
	Connect(LocalPlayer.Idled, function()
		if antiAfk then
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.zero)
			end)
		end
	end)
	perf:Toggle({ Name = "Anti-AFK", Icon = "timer", Description = "Never get kicked for idling", Default = true, Flag = "perf_antiafk", Callback = function(value) antiAfk = value end })

	local executor = "Unknown"
	if identifyexecutor then
		local ok, name, version = pcall(identifyexecutor)
		if ok and name then
			executor = tostring(name) .. (version and (" " .. tostring(version)) or "")
		end
	end
	perf:Label({ Name = "Executor", Value = executor })
end

--// Unload ----------------------------------------------------------------------------

function Library:Unload()
	if self.Unloaded then
		return
	end
	self.Unloaded = true
	capturedPointer = nil
	for _, callback in ipairs(self._unloadCallbacks) do
		pcall(callback)
	end
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	ScreenGui:Destroy()
	if ENV.CROWN_UNLOAD then
		ENV.CROWN_UNLOAD = nil
	end
end

ENV.CROWN_UNLOAD = function()
	Library:Unload()
end
ENV.CROWN = Library

--//=================================================================================
--// Demo build — every feature here is client-side and restores itself on unload.
--//=================================================================================

-- Library-only mode: another script sets getgenv().CROWN_LIB_ONLY = true, loadstrings this
-- file to get the Library, then builds its own window. Skips the key gate and the demo.
if ENV.CROWN_LIB_ONLY then
	CrownUI = Library
else
-- demo window below


-- Keyless: no key system required.

local Window = Library:CreateWindow({
	Title = "Crown Hub",
	Subtitle = "v1.0 · " .. (RunService:IsStudio() and "studio" or "live"),
	Logo = "rbxassetid://113737142720252",
})

Window:SidebarHeading("General")
local HomeTab = Window:Tab({ Name = "Home", Icon = "layout-dashboard", Description = "Overview of your session" })
local PlayerTab = Window:Tab({ Name = "Player", Icon = "person-standing", Description = "Movement and camera" })
local VisualsTab = Window:Tab({ Name = "Visuals", Icon = "eye", Description = "Lighting, crosshair and highlights" })
local ComponentsTab = Window:Tab({ Name = "Components", Icon = "puzzle", Badge = "NEW", Description = "Every building block in one place" })
-- Sub-tabs (categories) fold open under their parent in the sidebar.
local ControlsSub = ComponentsTab:SubTab({ Name = "Controls", Icon = "toggle-right", Description = "Toggles, sliders and choices" })
local InputsSub = ComponentsTab:SubTab({ Name = "Inputs", Icon = "mouse-pointer-2", Description = "Keybinds, colours, text and buttons" })
local LayoutSub = ComponentsTab:SubTab({ Name = "Layout", Icon = "layers", Badge = "NEW", Description = "Labels, paragraphs and dividers" })
Window:SidebarHeading("System")
local SettingsTab = Window:Tab({ Name = "Settings", Icon = "settings", Description = "Interface and configuration" })

local function getHumanoid()
	local character = LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- Home --------------------------------------------------------------------------------
do
	local welcome = HomeTab:Section({ Name = "Welcome", Icon = "hand", Side = "Left" })
	welcome:Paragraph({
		Title = "Hello, " .. LocalPlayer.DisplayName,
		Content = "Every control in this build is live. Drag the window by its top bar, minimize it into a floating icon, and hide it with your menu key (<b>RightShift</b> by default).",
	})
	welcome:Button({
		Name = "Explore components",
		Icon = "puzzle",
		Style = "Primary",
		Callback = function()
			Window:SelectTab(ComponentsTab)
		end,
	})

	local quick = HomeTab:Section({ Name = "Quick actions", Icon = "zap", Side = "Left" })
	quick:Button({
		Name = "Send a test notification",
		Icon = "bell",
		Callback = function()
			Library:Notify({ Title = "Hello there", Content = "Hover a notification to pause it, click to dismiss.", Type = "info", Duration = 4 })
		end,
	})
	quick:Button({
		Name = "Turn every feature off",
		Icon = "power",
		Confirm = true,
		Callback = function()
			for _, flag in ipairs({ "speed_enabled", "jump_enabled", "fov_enabled", "zoom_enabled", "fullbright", "no_fog", "lock_time", "crosshair_enabled", "self_highlight" }) do
				local option = Library.Options[flag]
				if option then
					option:Set(false)
				end
			end
			Library:Notify({ Title = "Features reset", Content = "Every gameplay toggle is off again.", Type = "success", Duration = 3 })
		end,
	})

	local session = HomeTab:Section({ Name = "Session", Icon = "activity", Side = "Right" })
	local gameName = "Unknown"
	task.spawn(function()
		-- The games API keeps the untranslated title in sourceName; fall back to the product info.
		local ok, name = pcall(function()
			local body = game:HttpGet("https://games.roblox.com/v1/games?universeIds=" .. tostring(game.GameId))
			local item = game:GetService("HttpService"):JSONDecode(body).data[1]
			return item and ((item.sourceName ~= "" and item.sourceName) or item.name)
		end)
		if not (ok and type(name) == "string" and name ~= "") then
			local okInfo, info = pcall(function()
				return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
			end)
			name = okInfo and info and info.Name or nil
		end
		if name then
			gameName = name
		end
	end)
	local gameLabel = session:Label({ Name = "Game", Icon = "gamepad-2", Value = "…" })
	local playersLabel = session:Label({ Name = "Players", Icon = "user", Value = "…" })
	local pingLabel = session:Label({ Name = "Ping", Icon = "wifi", Value = "…" })
	local timeLabel = session:Label({ Name = "Session", Icon = "timer", Value = "0:00" })
	local fpsMeter = session:Progress({
		Name = "Frame rate",
		Max = 240,
		Format = function(value)
			return string.format("%d fps", value + 0.5)
		end,
	})

	local started = os.clock()
	local frames, elapsed = 0, 0
	Connect(RunService.RenderStepped, function(dt)
		frames += 1
		elapsed += dt
		if elapsed >= 0.5 then
			local fps = frames / elapsed
			frames, elapsed = 0, 0
			if not Library.Open then
				return
			end
			gameLabel:Set(RunService:IsStudio() and "Studio" or gameName)
			playersLabel:Set(string.format("%d / %d", #Players:GetPlayers(), Players.MaxPlayers))
			fpsMeter:Set(fps)
			local okPing, ping = pcall(function()
				return LocalPlayer:GetNetworkPing() * 1000
			end)
			pingLabel:Set(okPing and string.format("%d ms", ping + 0.5) or "—")
			local seconds = math.floor(os.clock() - started)
			timeLabel:Set(string.format("%d:%02d", seconds // 60, seconds % 60))
		end
	end)

	local shortcuts = HomeTab:Section({ Name = "Shortcuts", Icon = "keyboard", Side = "Right" })
	Library._menuKeyLabel = shortcuts:Label({ Name = "Toggle menu", Value = keyName(Library.ToggleKey) })
	shortcuts:Label({ Name = "Clear a keybind", Value = "Backspace" })
	shortcuts:Label({ Name = "Cancel keybind", Value = "Esc" })
	shortcuts:Label({ Name = "Type a slider value", Value = "Click number" })
end

-- Components ---------------------------------------------------------------------------
do
	local basics = ControlsSub:Section({ Name = "Toggles", Icon = "toggle-right", Side = "Left" })
	basics:Toggle({
		Name = "Toggle",
		Icon = "power",
		Default = true,
		CallOnInit = false,
		Flag = "demo_toggle",
		Callback = function(value)
			Library:Notify({ Title = "Toggle", Content = value and "Enabled" or "Disabled", Type = value and "success" or "info", Duration = 2 })
		end,
	})
	local expanding = basics:Toggle({
		Name = "Toggle with options",
		Tooltip = "Sub-options stay folded until this is on",
		Icon = "layers",
		Description = "Turn it on to reveal its settings",
		Flag = "demo_expanding",
	})
	local sub = expanding:SubOptions()
	sub:Slider({ Name = "Strength", Min = 0, Max = 100, Default = 60, Suffix = "%", Flag = "demo_sub_strength" })
	sub:Dropdown({ Name = "Target", Options = { "Nearest", "Lowest health", "Random" }, Default = "Nearest", Flag = "demo_sub_target" })
	sub:Checkbox({ Name = "Visible only", Default = true, Flag = "demo_sub_visible" })
	basics:Toggle({
		Name = "Toggle with keybind",
		Icon = "keyboard",
		Description = "Bind a key to flip it anywhere",
		Keybind = Enum.KeyCode.G,
		Flag = "demo_bound_toggle",
		Callback = function(value)
			Library:Notify({ Title = "Bound toggle", Content = value and "Enabled" or "Disabled", Type = value and "success" or "info", Duration = 2 })
		end,
	})
	basics:Checkbox({ Name = "Checkbox", Default = true, Flag = "demo_checkbox" })
	basics:Checkbox({ Name = "Another checkbox", Flag = "demo_checkbox_2" })

	local values = ControlsSub:Section({ Name = "Values", Icon = "sliders-horizontal", Side = "Left" })
	values:Slider({ Name = "Slider", Min = 0, Max = 100, Default = 40, Suffix = "%", Flag = "demo_slider" })
	values:Slider({ Name = "Precise slider", Min = 0, Max = 1, Default = 0.25, Increment = 0.05, Flag = "demo_slider_precise" })
	values:Stepper({ Name = "Stepper", Tooltip = "Hold − or + to repeat faster", Icon = "hash", Min = 0, Max = 50, Default = 5, Flag = "demo_stepper" })
	local progress = values:Progress({ Name = "Progress", Default = 35 })
	values:Button({
		Name = "Randomise progress",
		Icon = "refresh-cw",
		Callback = function()
			progress:Set(math.random(0, 100))
		end,
	})

	local choices = ControlsSub:Section({ Name = "Choices", Icon = "list", Side = "Right" })
	choices:Segmented({
		Name = "Segmented",
		Tooltip = "Inline choice with a sliding pill",
		Options = { "Legit", "Balanced", "Rage" },
		Default = "Balanced",
		Flag = "demo_segmented",
		Callback = function(value)
			Library:Notify({ Title = "Mode", Content = value, Type = "info", Duration = 2 })
		end,
	})
	choices:Dropdown({
		Name = "Dropdown",
		Options = { "Nearest", "Lowest health", "Random", "Crosshair" },
		Default = "Nearest",
		Flag = "demo_dropdown",
	})
	choices:Dropdown({
		Name = "Multi dropdown",
		Multi = true,
		Options = { "Head", "Torso", "Arms", "Legs" },
		Default = { "Head", "Torso" },
		Flag = "demo_multi",
	})
	choices:Dropdown({
		Name = "Searchable dropdown",
		Options = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliett" },
		Default = "Alpha",
		Flag = "demo_search_dropdown",
	})

	local inputs = InputsSub:Section({ Name = "Inputs", Icon = "mouse-pointer-2", Side = "Right" })
	inputs:Keybind({
		Name = "Keybind",
		Default = Enum.KeyCode.F,
		Flag = "demo_keybind",
		Callback = function()
			Library:Notify({ Title = "Keybind", Content = "Pressed", Type = "success", Duration = 1.5 })
		end,
	})
	inputs:ColorPicker({ Name = "Color", Default = Color3.fromRGB(255, 255, 255), Flag = "demo_color" })
	inputs:Input({
		Name = "Input",
		Placeholder = "Type and press enter",
		Flag = "demo_input",
		Callback = function(text)
			Library:Notify({ Title = "Input", Content = text ~= "" and text or "(empty)", Type = "info", Duration = 2 })
		end,
	})
	local advanced = inputs:Collapsible({ Name = "Advanced", Icon = "wrench", Description = "Click to fold open" })
	advanced:Slider({ Name = "Smoothing", Min = 0, Max = 10, Default = 3, Flag = "demo_adv_smoothing" })
	advanced:Toggle({ Name = "Prediction", Flag = "demo_adv_prediction" })

	local buttons = InputsSub:Section({ Name = "Buttons", Icon = "box", Side = "Left" })
	buttons:Button({
		Name = "Primary action",
		Icon = "play",
		Style = "Primary",
		Callback = function()
			Library:Notify({ Title = "Primary", Content = "Primary button pressed.", Type = "success", Duration = 2 })
		end,
	})
	buttons:Button({
		Name = "Secondary action",
		Icon = "star",
		Callback = function()
			Library:Notify({ Title = "Secondary", Content = "Secondary button pressed.", Type = "info", Duration = 2 })
		end,
	})
	buttons:Button({
		Name = "Needs confirmation",
		Icon = "triangle-alert",
		Confirm = true,
		Callback = function()
			Library:Notify({ Title = "Confirmed", Content = "Two-step buttons prevent misclicks.", Type = "warning", Duration = 2.5 })
		end,
	})

	local text = LayoutSub:Section({ Name = "Text", Icon = "list", Side = "Left" })
	text:Paragraph({
		Title = "Sub-tabs",
		Content = "Call <b>Tab:SubTab({ Name, Icon, Description })</b> to add a category under a sidebar tab. Click the parent to fold it.",
	})
	text:Divider()
	text:Label({ Name = "Label", Icon = "info", Value = "Value" })
	text:Label({ Name = "Another label", Value = "42" })

	local navigation = LayoutSub:Section({ Name = "Navigation", Icon = "layout-dashboard", Side = "Right" })
	navigation:Button({
		Name = "Open Controls",
		Icon = "toggle-right",
		Callback = function()
			Window:SelectTab(ControlsSub)
		end,
	})
	navigation:Button({
		Name = "Fold Components",
		Icon = "chevron-right",
		Callback = function()
			ComponentsTab:SetExpanded(false)
		end,
	})
end

-- Player ----------------------------------------------------------------------------
do
	local movement = PlayerTab:Section({ Name = "Movement", Icon = "zap", Side = "Left" })
	local speedEnabled, speedValue = false, 16
	local jumpEnabled, jumpValue = false, 50
	local defaults = {}

	local function remember(humanoid)
		if defaults.humanoid ~= humanoid then
			defaults = {
				humanoid = humanoid,
				WalkSpeed = humanoid.WalkSpeed,
				JumpPower = humanoid.JumpPower,
				UseJumpPower = humanoid.UseJumpPower,
			}
		end
	end

	local function restore()
		local humanoid = defaults.humanoid
		if humanoid and humanoid.Parent then
			if not speedEnabled then
				humanoid.WalkSpeed = defaults.WalkSpeed
			end
			if not jumpEnabled then
				humanoid.JumpPower = defaults.JumpPower
				humanoid.UseJumpPower = defaults.UseJumpPower
			end
		end
	end

	Connect(RunService.Heartbeat, function()
		if not (speedEnabled or jumpEnabled) then
			return
		end
		local humanoid = getHumanoid()
		if not humanoid then
			return
		end
		remember(humanoid)
		if speedEnabled and humanoid.WalkSpeed ~= speedValue then
			humanoid.WalkSpeed = speedValue
		end
		if jumpEnabled then
			humanoid.UseJumpPower = true
			if humanoid.JumpPower ~= jumpValue then
				humanoid.JumpPower = jumpValue
			end
		end
	end)

	local speedToggle = movement:Toggle({
		Name = "WalkSpeed override",
		Icon = "rocket",
		Description = "Reveals the speed slider",
		Flag = "speed_enabled",
		Callback = function(value)
			speedEnabled = value
			local humanoid = getHumanoid()
			if humanoid then
				remember(humanoid)
			end
			restore()
		end,
	})
	speedToggle:SubOptions():Slider({
		Name = "WalkSpeed", Min = 16, Max = 120, Default = 24, Flag = "speed_value",
		Callback = function(value)
			speedValue = value
		end,
	})
	speedValue = 24
	local jumpToggle = movement:Toggle({
		Name = "JumpPower override",
		Icon = "move",
		Description = "Reveals the jump slider",
		Flag = "jump_enabled",
		Callback = function(value)
			jumpEnabled = value
			local humanoid = getHumanoid()
			if humanoid then
				remember(humanoid)
			end
			restore()
		end,
	})
	jumpToggle:SubOptions():Slider({
		Name = "JumpPower", Min = 50, Max = 200, Default = 70, Flag = "jump_value",
		Callback = function(value)
			jumpValue = value
		end,
	})
	jumpValue = 70

	Library:OnUnload(function()
		speedEnabled, jumpEnabled = false, false
		restore()
	end)

	local camera = PlayerTab:Section({ Name = "Camera", Icon = "camera", Side = "Right" })
	local fovEnabled, fovValue = false, 90
	local originalFov
	Connect(RunService.RenderStepped, function()
		local cam = Workspace.CurrentCamera
		if fovEnabled and cam then
			originalFov = originalFov or cam.FieldOfView
			cam.FieldOfView = fovValue
		end
	end)
	local fovToggle = camera:Toggle({
		Name = "Field of view override",
		Icon = "eye",
		Flag = "fov_enabled",
		Callback = function(value)
			fovEnabled = value
			if not value and originalFov and Workspace.CurrentCamera then
				Workspace.CurrentCamera.FieldOfView = originalFov
				originalFov = nil
			end
		end,
	})
	fovToggle:SubOptions():Slider({
		Name = "Field of view", Min = 40, Max = 120, Default = 90, Suffix = "°", Flag = "fov_value",
		Callback = function(value)
			fovValue = value
		end,
	})
	local originalZoom = LocalPlayer.CameraMaxZoomDistance
	camera:Toggle({
		Name = "Extended zoom",
		Tooltip = "Lets the camera zoom much further out",
		Icon = "search",
		Description = "Raises max zoom distance to 1000",
		Flag = "zoom_enabled",
		Callback = function(value)
			Library:SetMaxZoom(value and 1000 or originalZoom)
		end,
	})
	Library:OnUnload(function()
		fovEnabled = false
		if originalFov and Workspace.CurrentCamera then
			Workspace.CurrentCamera.FieldOfView = originalFov
		end
		LocalPlayer.CameraMaxZoomDistance = originalZoom
	end)

	local character = PlayerTab:Section({ Name = "Character", Icon = "user", Side = "Right" })
	character:Button({
		Name = "Respawn",
		Icon = "refresh-cw",
		Confirm = true,
		Callback = function()
			local humanoid = getHumanoid()
			if humanoid then
				humanoid.Health = 0
			end
		end,
	})
end

-- Visuals ---------------------------------------------------------------------------
do
	local lighting = VisualsTab:Section({ Name = "Lighting", Icon = "lightbulb", Side = "Left" })
	local original = {
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		GlobalShadows = Lighting.GlobalShadows,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		ClockTime = Lighting.ClockTime,
	}
	local fullbright, noFog, lockTime, clock = false, false, false, 14
	local atmospheres = {}

	Connect(RunService.RenderStepped, function()
		if fullbright then
			Lighting.Brightness = 2
			Lighting.Ambient = Color3.fromRGB(178, 178, 178)
			Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
			Lighting.GlobalShadows = false
		end
		if noFog then
			Lighting.FogEnd = 1e6
			Lighting.FogStart = 1e6
		end
		if lockTime then
			Lighting.ClockTime = clock
		end
	end)

	lighting:Toggle({
		Name = "Fullbright",
		Tooltip = "Removes darkness and shadows (client-side)",
		Icon = "sun",
		Flag = "fullbright",
		Callback = function(value)
			fullbright = value
			if not value then
				Lighting.Brightness = original.Brightness
				Lighting.Ambient = original.Ambient
				Lighting.OutdoorAmbient = original.OutdoorAmbient
				Lighting.GlobalShadows = original.GlobalShadows
			end
		end,
	})
	lighting:Toggle({
		Name = "Remove fog",
		Icon = "sparkles",
		Description = "Also hides Atmosphere effects",
		Flag = "no_fog",
		Callback = function(value)
			noFog = value
			if value then
				for _, child in ipairs(Lighting:GetChildren()) do
					if child:IsA("Atmosphere") and child.Parent then
						atmospheres[child] = true
						child.Parent = nil
					end
				end
			else
				Lighting.FogEnd = original.FogEnd
				Lighting.FogStart = original.FogStart
				for atmosphere in pairs(atmospheres) do
					atmosphere.Parent = Lighting
				end
				table.clear(atmospheres)
			end
		end,
	})
	local timeToggle = lighting:Toggle({
		Name = "Lock time of day",
		Icon = "moon",
		Flag = "lock_time",
		Callback = function(value)
			lockTime = value
			if not value then
				Lighting.ClockTime = original.ClockTime
			end
		end,
	})
	timeToggle:SubOptions():Slider({
		Name = "Time of day", Min = 0, Max = 24, Default = 14, Increment = 0.25, Flag = "clock_time",
		Format = function(value)
			local minutes = math.floor(value * 60 + 0.5)
			return string.format("%02d:%02d", minutes // 60 % 24, minutes % 60)
		end,
		Callback = function(value)
			clock = value
		end,
	})

	Library:OnUnload(function()
		fullbright, noFog, lockTime = false, false, false
		for key, value in pairs(original) do
			Lighting[key] = value
		end
		for atmosphere in pairs(atmospheres) do
			atmosphere.Parent = Lighting
		end
	end)

	-- Crosshair (drawn in our own ScreenGui, centred on the viewport)
	local crosshairSection = VisualsTab:Section({ Name = "Crosshair", Icon = "crosshair", Side = "Right" })
	local crosshair = Create("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 30,
		Parent = ScreenGui,
	})
	local arms = {}
	for i = 1, 4 do
		arms[i] = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			ZIndex = 30,
			Parent = crosshair,
		})
	end
	local dot = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BorderSizePixel = 0,
		ZIndex = 30,
		Parent = crosshair,
	}, { Corner(2) })
	local ch = { color = Color3.new(1, 1, 1), size = 8, gap = 4, thickness = 2, dot = false }
	local function drawCrosshair()
		local offset = ch.gap + ch.size / 2
		local directions = { Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(-1, 0), Vector2.new(1, 0) }
		for i, direction in ipairs(directions) do
			local arm = arms[i]
			arm.BackgroundColor3 = ch.color
			arm.Position = UDim2.new(0.5, direction.X * offset, 0.5, direction.Y * offset)
			arm.Size = direction.X == 0 and UDim2.fromOffset(ch.thickness, ch.size) or UDim2.fromOffset(ch.size, ch.thickness)
		end
		dot.Visible = ch.dot
		dot.BackgroundColor3 = ch.color
		dot.Size = UDim2.fromOffset(ch.thickness + 1, ch.thickness + 1)
	end
	drawCrosshair()

	local crosshairToggle = crosshairSection:Toggle({
		Name = "Crosshair",
		Icon = "target",
		Description = "Style options unfold when enabled",
		Flag = "crosshair_enabled",
		Callback = function(value)
			crosshair.Visible = value
		end,
	})
	local crosshairOptions = crosshairToggle:SubOptions()
	crosshairOptions:ColorPicker({
		Name = "Color", Default = Color3.new(1, 1, 1), Flag = "crosshair_color",
		Callback = function(color)
			ch.color = color
			drawCrosshair()
		end,
	})
	crosshairOptions:Slider({ Name = "Length", Min = 2, Max = 24, Default = 8, Suffix = "px", Flag = "crosshair_size",
		Callback = function(value)
			ch.size = value
			drawCrosshair()
		end,
	})
	crosshairOptions:Slider({ Name = "Gap", Min = 0, Max = 20, Default = 4, Suffix = "px", Flag = "crosshair_gap",
		Callback = function(value)
			ch.gap = value
			drawCrosshair()
		end,
	})
	crosshairOptions:Slider({ Name = "Thickness", Min = 1, Max = 6, Default = 2, Suffix = "px", Flag = "crosshair_thickness",
		Callback = function(value)
			ch.thickness = value
			drawCrosshair()
		end,
	})
	crosshairOptions:Checkbox({ Name = "Center dot", Flag = "crosshair_dot",
		Callback = function(value)
			ch.dot = value
			drawCrosshair()
		end,
	})

	-- Self highlight
	local selfSection = VisualsTab:Section({ Name = "Self", Icon = "user", Side = "Left" })
	local highlight = Create("Highlight", {
		Name = "Crown_SelfHighlight",
		FillColor = Color3.new(1, 1, 1),
		OutlineColor = Color3.new(1, 1, 1),
		FillTransparency = 0.75,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Enabled = false,
	})
	local highlightEnabled = false
	local function attachHighlight()
		highlight.Adornee = LocalPlayer.Character
		highlight.Parent = highlightEnabled and ScreenGui or nil
		highlight.Enabled = highlightEnabled
	end
	Connect(LocalPlayer.CharacterAdded, function()
		task.defer(attachHighlight)
	end)
	local highlightToggle = selfSection:Toggle({
		Name = "Highlight character",
		Icon = "paintbrush",
		Description = "Colours unfold when enabled",
		Flag = "self_highlight",
		Callback = function(value)
			highlightEnabled = value
			attachHighlight()
		end,
	})
	local highlightOptions = highlightToggle:SubOptions()
	highlightOptions:ColorPicker({
		Name = "Fill color", Default = Color3.new(1, 1, 1), Flag = "self_highlight_fill",
		Callback = function(color)
			highlight.FillColor = color
		end,
	})
	highlightOptions:ColorPicker({
		Name = "Outline color", Default = Color3.new(1, 1, 1), Flag = "self_highlight_outline",
		Callback = function(color)
			highlight.OutlineColor = color
		end,
	})
	highlightOptions:Slider({
		Name = "Fill opacity", Min = 0, Max = 100, Default = 25, Suffix = "%", Flag = "self_highlight_opacity",
		Callback = function(value)
			highlight.FillTransparency = 1 - value / 100
		end,
	})
	Library:OnUnload(function()
		highlight:Destroy()
	end)
end

-- Settings --------------------------------------------------------------------------
do
	local interface = SettingsTab:Section({ Name = "Interface", Icon = "monitor", Side = "Left" })
	local menuBind
	menuBind = interface:Keybind({
		Name = "Menu keybind",
		Icon = "keyboard",
		Default = Library.ToggleKey,
		Flag = "menu_key",
		HideFromList = true,
		ChangedCallback = function(key)
			if not key then
				-- An unbound menu key would make a hidden window unrecoverable on desktop.
				menuBind:Set(Enum.KeyCode.RightShift)
				Library:Notify({ Title = "Menu key can't be empty", Content = "Reset to RShift.", Type = "warning", Duration = 3 })
				return
			end
			Library.ToggleKey = key
			if Library._menuKeyLabel then
				Library._menuKeyLabel:Set(keyName(key))
			end
		end,
	})
	interface:Slider({
		Icon = "move",
		Name = "Interface scale", Min = 70, Max = 130, Default = 100, Increment = 5, Suffix = "%", Flag = "ui_scale",
		Callback = function(value)
			Library.UserScale = value / 100
			Window:UpdateScale()
		end,
	})
	interface:Toggle({
		Name = "Notifications",
		Icon = "bell",
		Default = true,
		Flag = "notifications",
		CallOnInit = false,
		Callback = function(value)
			Library.NotificationsEnabled = value
		end,
	})
	interface:Toggle({
		Name = "Watermark",
		Icon = "activity",
		Description = "Name, fps, ping and clock overlay",
		Tooltip = "Shows in the top-right corner of the screen",
		Flag = "watermark",
		Callback = function(value)
			Library:SetWatermarkVisible(value)
		end,
	})
	interface:Toggle({
		Name = "Keybind list",
		Icon = "list",
		Description = "Floating overlay of bound keys",
		Flag = "keybind_list",
		Callback = function(value)
			Library:SetKeybindListVisible(value)
		end,
	})
	-- Optional depth-of-field behind the menu; eases in/out with the window.
	local blur = Create("BlurEffect", { Name = "Crown_Blur", Size = 0, Parent = Lighting })
	local blurEnabled, blurSize = false, 12
	Connect(RunService.RenderStepped, function(dt)
		local goal = (blurEnabled and Library.Open) and blurSize or 0
		if math.abs(blur.Size - goal) > 0.05 then
			blur.Size += (goal - blur.Size) * (1 - math.exp(-dt * 12))
		elseif blur.Size ~= goal then
			blur.Size = goal
		end
	end)
	Library:OnUnload(function()
		blur:Destroy()
	end)
	local blurToggle = interface:Toggle({
		Name = "Background blur",
		Icon = "sparkles",
		Description = "Blurs the game behind it",
		Flag = "ui_blur",
		Callback = function(value)
			blurEnabled = value
		end,
	})
	blurToggle:SubOptions():Slider({
		Name = "Blur strength",
		Min = 2,
		Max = 24,
		Default = 12,
		Flag = "ui_blur_size",
		Callback = function(value)
			blurSize = value
		end,
	})
	interface:Divider()
	interface:Button({
		Name = "Unload",
		Icon = "power",
		Confirm = true,
		ConfirmText = "Click again to unload",
		Callback = function()
			Library:Unload()
		end,
	})

	Library:AddThemeSection(SettingsTab, "Left")

	local configs = SettingsTab:Section({ Name = "Configuration", Icon = "folder", Side = "Right" })
	local setclipboard = (type(getgenv) == "function" and getgenv().setclipboard) or _G.setclipboard or (syn and syn.write_clipboard)
	-- try common clipboard APIs
	do
		local env = getfenv and getfenv() or _G
		setclipboard = setclipboard
			or (type(env) == "table" and (env.setclipboard or env.toclipboard))
			or (type(getgenv) == "function" and (getgenv().setclipboard or getgenv().toclipboard))
	end

	if not FS.available then
		configs:Paragraph({
			Title = "File system unavailable",
			Content = "Local save/load needs writefile / readfile. You can still export / import JSON below.",
		})
	end

	local nameInput = configs:Input({ Name = "Config name", Placeholder = "e.g. legit", MaxLength = 32 })
	local list = configs:Dropdown({ Name = "Saved configs", Options = FS.available and Library:ListConfigs() or {}, AllowNone = true })
	local autoloadLabel

	local function refresh()
		if FS.available then
			list:Refresh(Library:ListConfigs(), true)
		end
		if autoloadLabel then
			autoloadLabel:Set(Library:GetAutoload() or "None")
		end
	end

	if FS.available then
		configs:Button({
			Name = "Save",
			Icon = "save",
			Style = "Primary",
			Callback = function()
				local name = nameInput:Get()
				if name == "" then
					name = list:Get() or ""
				end
				local ok, err = Library:SaveConfig(name)
				Library:Notify({
					Title = ok and "Config saved" or "Could not save",
					Type = ok and "success" or "error",
					Content = ok and ("Saved as \"" .. name .. "\"") or tostring(err),
					Duration = 3,
				})
				refresh()
			end,
		})
		configs:Button({
			Name = "Overwrite",
			Icon = "refresh-cw",
			Callback = function()
				local name = list:Get() or nameInput:Get()
				if not name or name == "" then
					Library:Notify({ Title = "Select a config first", Type = "warning", Duration = 2.5 })
					return
				end
				local ok, err = Library:OverwriteConfig(name)
				Library:Notify({
					Title = ok and "Config overwritten" or "Could not overwrite",
					Type = ok and "success" or "error",
					Content = ok and ("Overwrote \"" .. name .. "\"") or tostring(err),
					Duration = 3,
				})
				refresh()
			end,
		})
		configs:Button({
			Name = "Load",
			Icon = "download",
			Callback = function()
				local name = list:Get()
				if not name then
					Library:Notify({ Title = "Select a config first", Type = "warning", Duration = 2.5 })
					return
				end
				local ok, err = Library:LoadConfig(name)
				Library:Notify({
					Title = ok and "Config loaded" or "Could not load",
					Type = ok and "success" or "error",
					Content = ok and ("Loaded \"" .. name .. "\"") or tostring(err),
					Duration = 3,
				})
			end,
		})
		configs:Button({
			Name = "Delete",
			Icon = "trash-2",
			Style = "Danger",
			Confirm = true,
			Callback = function()
				local name = list:Get()
				if not name then
					Library:Notify({ Title = "Select a config first", Type = "warning", Duration = 2.5 })
					return
				end
				local ok = Library:DeleteConfig(name)
				if ok and Library:GetAutoload() == name then
					Library:SetAutoload("")
				end
				Library:Notify({ Title = ok and "Config deleted" or "Could not delete", Content = name, Type = ok and "success" or "error", Duration = 3 })
				refresh()
			end,
		})
		configs:Divider()
		configs:Button({
			Name = "Set as autoload",
			Icon = "star",
			Callback = function()
				local name = list:Get()
				Library:SetAutoload(name or "")
				Library:Notify({
					Title = "Autoload",
					Icon = "star",
					Content = name and ("\"" .. name .. "\" will load on start") or "Autoload cleared",
					Duration = 3,
				})
				refresh()
			end,
		})
		autoloadLabel = configs:Label({ Name = "Autoload", Value = "None" })
		refresh()

		local autoload = Library:GetAutoload()
		if autoload then
			task.defer(function()
				local ok = Library:LoadConfig(autoload)
				if ok then
					Library:Notify({ Title = "Autoloaded config", Content = autoload, Type = "success", Duration = 3 })
				end
			end)
		end
	end

	-- JSON export / import (works even without filesystem)
	configs:Divider()
	configs:Button({
		Name = "Export JSON",
		Icon = "copy",
		Callback = function()
			local json, err = Library:ExportConfig()
			if not json then
				Library:Notify({ Title = "Export failed", Content = tostring(err), Type = "error", Duration = 3 })
				return
			end
			local copied = false
			if type(setclipboard) == "function" then
				copied = pcall(setclipboard, json)
			end
			if copied then
				Library:Notify({ Title = "Exported", Content = "Config JSON copied to clipboard.", Type = "success", Duration = 3 })
			else
				Library:Notify({ Title = "Export JSON", Content = "Clipboard unavailable — JSON is in the console (F9).", Type = "warning", Duration = 4 })
				print("[Crown Hub] Config JSON:\n" .. json)
			end
		end,
	})
	local jsonInput = configs:Input({
		Name = "Import JSON",
		Placeholder = "Paste config JSON here",
		MaxLength = 100000,
	})
	configs:Button({
		Name = "Import from JSON",
		Icon = "download",
		Style = "Primary",
		Callback = function()
			local text = jsonInput:Get()
			if not text or text == "" then
				Library:Notify({ Title = "Paste JSON first", Type = "warning", Duration = 2.5 })
				return
			end
			local ok, result = Library:ImportConfig(text)
			if ok then
				Library:Notify({
					Title = "Config imported",
					Content = "Applied " .. tostring(result) .. " setting(s).",
					Type = "success",
					Duration = 3,
				})
				jsonInput:Set("")
			else
				Library:Notify({
					Title = "Import failed",
					Content = tostring(result),
					Type = "error",
					Duration = 3,
				})
			end
		end,
	})
end

-- Play the entrance animation on first load.
Window.Frame.Visible = false
Library:SetOpen(true)

Library:Notify({
	Title = "Crown Hub loaded",
	Icon = "sparkles",
	Content = "Press " .. keyName(Library.ToggleKey) .. " to toggle the interface.",
	Duration = 4,
})

CrownUI = Library
end -- else demo

end -- do CrownUI

return CrownUI
