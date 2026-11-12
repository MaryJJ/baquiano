-- Baquiano: page in the game's Options > AddOns, with the same switches as
-- the /baq commands. Every row goes in through Settings.RegisterInitializer
-- (inserted by Blizzard's own code, so the options search is not tainted),
-- and a choice is a stepped slider: this client's dropdowns misbehave.
local ADDON, ns = ...

local Options = {}
ns.Options = Options

local category
local variables = {} -- every setting's name, to refresh them all

local function Header(text)
    if CreateSettingsListSectionHeaderInitializer then
        Settings.RegisterInitializer(category, CreateSettingsListSectionHeaderInitializer(text))
    end
end

-- A switch: get() says whether it is on, toggle() flips it (with whatever
-- else the matching /baq command does).
local function Checkbox(key, name, tooltip, get, toggle)
    local variable = "Baquiano_" .. key
    variables[#variables + 1] = variable
    local setting = Settings.RegisterProxySetting(category, variable, Settings.VarType.Boolean, name,
        get(), get,
        function(value)
            if (value == true) ~= (get() == true) then toggle() end
        end)
    Settings.RegisterInitializer(category, Settings.CreateCheckboxInitializer(setting, nil, tooltip))
end

-- One of several values (options: { value, label } in order), as a slider.
local function Choice(key, name, tooltip, options, get, set)
    local variable = "Baquiano_" .. key
    variables[#variables + 1] = variable
    local function Index()
        for i, o in ipairs(options) do
            if o[1] == get() then return i end
        end
        return 1
    end
    local setting = Settings.RegisterProxySetting(category, variable, Settings.VarType.Number, name,
        Index(), Index,
        function(i)
            if options[i] then set(options[i][1]) end
        end)
    local slider = Settings.CreateSliderOptions(1, #options, 1)
    slider:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(i)
        return options[i] and options[i][2] or ""
    end)
    Settings.RegisterInitializer(category, Settings.CreateSliderInitializer(setting, slider, tooltip))
end

local function Button(name, label, tooltip, onClick)
    if CreateSettingsButtonInitializer then
        Settings.RegisterInitializer(category,
            CreateSettingsButtonInitializer(name, label, onClick, tooltip, false))
    end
end

local function Build()
    category = Settings.RegisterVerticalLayoutCategory("Baquiano")
    local db = BaquianoDB

    Header("Route")
    Checkbox("arrow", "Guide arrow",
        "The arrow on screen that points along the route. Right click on it clears the route.",
        function() return db.arrow.shown end, ns.Arrow.Toggle)
    Checkbox("minimap", "Route on the minimap", nil,
        function() return db.minimap end, ns.MinimapOverlay.Toggle)
    Checkbox("carbonite", "Route and paths on Carbonite's map",
        "Only with the Carbonite addon. Alt + click on its map sets a destination too.",
        function() return db.carbonite end, ns.CarboniteOverlay.Toggle)
    Checkbox("flights", "Use known flights",
        "Routes may include flights your character knows, when faster than walking.",
        function() return db.useFlights end, ns.Flights.Toggle)
    Checkbox("boats", "Use boats and zeppelins",
        "Docks of every boat and zeppelin of your faction are known; how long each trip takes is measured the first time you ride it. /baq boats list shows them.",
        function() return db.useBoats end, ns.Transports.Toggle)
    Checkbox("avoid", "Avoid the other faction's towns",
        "Routes go round the other faction's towns and capital cities when there is a way; if not, the chat warns.",
        function() return db.avoidEnemy end, function() db.avoidEnemy = not db.avoidEnemy end)
    Checkbox("follow", "Follow waypoints from other addons",
        "Waypoints set through TomTom (or Carbonite's stand-in), such as SkillUp Forever's, or the game's map pin, become the destination; removing them clears the route.",
        function() return db.followWaypoints end, ns.Waypoints.Toggle)
    Button("Clear the route", "Clear", nil, function() ns.Nav.Unmark() end)
    Button("Arrow position", "Reset", "Puts the guide arrow back in its starting place.", function()
        ns.Arrow.ResetPosition()
    end)

    Header("Recorded paths")
    Checkbox("record", "Record the paths you walk", nil,
        function() return db.recording end, ns.Recorder.Toggle)
    Checkbox("paths", "Show recorded paths",
        "Blue outdoors, violet indoors, on the map and the minimap. Without it they show on the map while Shift is held.",
        function() return db.pathsAlways end, ns.PathView.Toggle)
    Checkbox("cities", "Show them in capital cities too", nil,
        function() return db.cityPaths end, function()
            db.cityPaths = not db.cityPaths
            ns.MapOverlay.Refresh()
        end)
    Checkbox("trail", "Trail of what you just walked",
        "Green breadcrumbs that fade out behind you.",
        function() return db.trail end, function()
            db.trail = not db.trail
            ns.MapOverlay.Refresh()
        end)

    Header("Distance walked")
    Checkbox("walked", "Show the distance walked",
        "This session and in total, per character. Drag it to move it; right click starts the session count again.",
        function() return db.odometer.shown end, ns.Odometer.Toggle)
    Choice("units", "Unit", nil,
        { { "yd", "yards" }, { "m", "metres" }, { "km", "kilometres" }, { "mi", "miles" } },
        function() return db.odometer.unit or "yd" end, ns.Odometer.SetUnit)
    Button("Session count", "Reset", "Starts the count of this session again.", function()
        ns.Odometer.Reset()
    end)

    Settings.RegisterAddOnCategory(category)
end

function Options.Init()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then
        return -- a client without this options panel: the /baq commands remain
    end
    Build()
end

-- After a /baq command changed something: the panel shows it.
function Options.Refresh()
    if not category or not Settings.NotifyUpdate then return end
    for _, variable in ipairs(variables) do pcall(Settings.NotifyUpdate, variable) end
end

-- Opens the panel; false if this client has none.
function Options.Open()
    if not category then return false end
    Settings.OpenToCategory(category:GetID())
    return true
end
