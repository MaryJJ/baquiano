-- Baquiano: core. Settings, player position and map geometry.
local ADDON, ns = ...

-- All distances are in game yards.
ns.cfg = {
    SPACING      = 10,  -- spacing between recorded points
    MERGE        = 6,   -- closer than this, an existing point is reused
    MAX_EDGE     = 30,  -- a link longer than this is dropped (jump, teleport)
    TELEPORT     = 60,  -- jump between two readings that breaks the recording
    ARRIVE       = 8,   -- radius that counts as reaching an intermediate point
    ARRIVE_FINAL = 5,   -- radius that counts as reaching the destination
    OFFROUTE     = 45,  -- farther from the route than this, it is recalculated
    JOIN         = 20,  -- a loose path end is linked to another path this close
    REACH        = 40,  -- a route may enter/leave the network at any point this close
    BRIDGE       = 250, -- a route may cross an unrecorded gap this wide in a straight line...
    BRIDGE_COST  = 3,   -- ...counting it this many times longer, so known paths are preferred
                        -- (a straight line may cross hills or cliffs the game has)
    MAX_LINES    = 4000, -- cap on lines drawn on the map
    TRAIL        = 400, -- the trail's breadcrumbs fade out over this many yards walked
    SNAP_PX      = 10,  -- edit mode: a click this close (screen pixels) picks an existing point
    -- Flights: compared with walking by time, at the player's current run speed.
    FLY_SPEED    = 32,  -- yards per second on a flight
    FLY_WAIT     = 20,  -- seconds lost per flight taken (talking, take-off, landing)
    FLY_REACH    = 80,  -- a flight master links to recorded points this close
    FLY_ARRIVE   = 30,  -- radius that counts as having landed at a flight master
    -- Boats and zeppelins (Transports.lua).
    BOAT_TRIP    = 120, -- seconds a trip is guessed to take until ridden
    BOAT_NEAR    = 250, -- a ride this close to a dock of the tables is that trip
    BOAT_WAIT    = 150, -- seconds waited at the dock on average
    TRAM_TRIP    = 100, -- the Deeprun Tram: walking in, the ride and out
    TRAM_WAIT    = 30,  -- seconds waited for the tram
    BOAT_ARRIVE  = 60,  -- radius that counts as being at a dock
    BOAT_MIN     = 300, -- a ride shorter than this is not a trip (a knockback, say)
    BOAT_SAME    = 150, -- docks this close count as the same
    BOAT_SETTLE  = 20,  -- seconds on firm ground that end a trip
    -- The other faction's towns: walking within ENEMY_RADIUS of one counts
    -- ENEMY_COST times longer, so routes go round them when they can.
    ENEMY_RADIUS = 150,
    ENEMY_COST   = 10,
}

-- Capital cities (their own maps in the game's UiMap table) and their
-- faction. So many paths cross there that the recorded ones are not drawn,
-- unless asked; and routes keep out of the other faction's.
ns.CITIES = {
    [1453] = "A", -- Stormwind City
    [1454] = "H", -- Orgrimmar
    [1455] = "A", -- Ironforge
    [1456] = "H", -- Thunder Bluff
    [1457] = "A", -- Darnassus
    [1458] = "H", -- Undercity
}

-- Whether the recorded paths of map mapID are drawn (when paths are shown).
function ns.ShowsPaths(mapID)
    return BaquianoDB.cityPaths or not ns.CITIES[mapID]
end

-- 1234 -> "1,234 yd".
function ns.Yards(d)
    local s = tostring(math.floor(d + 0.5))
    while true do
        local n
        s, n = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if n == 0 then break end
    end
    return s .. " yd"
end

function ns.Print(msg)
    print("|cff33ff99Baquiano|r: " .. tostring(msg))
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- Returns mapID, x, y (0..1 zone map coordinates), or nil when the game
-- does not give the position (dungeons, loading screens).
function ns.PlayerPos()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or IsSecret(mapID) then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if IsSecret(x) or IsSecret(y) then return nil end
    if not x or not y or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end

-- Map size in yards. If the client does not provide it, an approximate value
-- is used: guidance still works but distances are only indicative.
local sizeCache = {}
ns.approxSize = false

function ns.MapSize(mapID)
    local c = sizeCache[mapID]
    if c then return c[1], c[2] end

    local w, h
    pcall(function()
        local _, tl = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local _, mid = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
        if tl and mid then
            local top, left = tl:GetXY()
            local midY, midX = mid:GetXY()
            w = math.abs(left - midX) * 2
            h = math.abs(top - midY) * 2
        end
    end)

    if not (w and h and w > 0 and h > 0) then
        w, h = 1000, 667
        ns.approxSize = true
    end
    sizeCache[mapID] = { w, h }
    return w, h
end

-- World position (in yards) of a point on a map, to compare points of
-- different zones. Map to world is linear, so three corners per map are
-- enough. Returns continentID, wx, wy; or nil if the client does not say.
local worldCache = {}

function ns.WorldXY(mapID, x, y)
    local t = worldCache[mapID]
    if t == nil then
        t = false
        pcall(function()
            local c, p00 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
            local _, p10 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 0))
            local _, p01 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 1))
            if c and p00 and p10 and p01 then
                local ax, ay = p00:GetXY()
                local bx, by = p10:GetXY()
                local cx, cy = p01:GetXY()
                t = { c, ax, ay, bx - ax, by - ay, cx - ax, cy - ay }
            end
        end)
        worldCache[mapID] = t
    end
    if not t then return nil end
    return t[1], t[2] + x * t[4] + y * t[6], t[3] + x * t[5] + y * t[7]
end

-- Point (x, y) of map fromMap expressed in toMap's coordinates (it may fall
-- outside 0..1). nil if unknown or on different continents.
function ns.ConvertXY(fromMap, x, y, toMap)
    if fromMap == toMap then return x, y end
    local c, wx, wy = ns.WorldXY(fromMap, x, y)
    if not c then return nil end
    return ns.MapXYFromWorld(toMap, c, wx, wy)
end

-- World position (continent c, wx, wy in yards) in map toMap's coordinates
-- (it may fall outside 0..1). nil if unknown or on another continent.
function ns.MapXYFromWorld(toMap, c, wx, wy)
    ns.WorldXY(toMap, 0, 0) -- fills the cache
    local t = worldCache[toMap]
    if not t or t[1] ~= c then return nil end
    -- Solve wx = ox + mx*ax + my*bx, wy = oy + mx*ay + my*by for (mx, my).
    local ax, ay, bx, by = t[4], t[5], t[6], t[7]
    local det = ax * by - bx * ay
    if det == 0 then return nil end
    local rx, ry = wx - t[2], wy - t[3]
    return (rx * by - bx * ry) / det, (ax * ry - rx * ay) / det
end

-- Yards between points of (possibly) different maps; nil if unknown or on
-- different continents.
function ns.WorldDist(m1, x1, y1, m2, x2, y2)
    if m1 == m2 then return ns.Dist(m1, x1, y1, x2, y2) end
    local c1, a1, b1 = ns.WorldXY(m1, x1, y1)
    local c2, a2, b2 = ns.WorldXY(m2, x2, y2)
    if not c1 or c1 ~= c2 then return nil end
    return math.sqrt((a1 - a2) ^ 2 + (b1 - b2) ^ 2)
end

function ns.Dist(mapID, x1, y1, x2, y2)
    local w, h = ns.MapSize(mapID)
    local dx, dy = (x1 - x2) * w, (y1 - y2) * h
    return math.sqrt(dx * dx + dy * dy)
end

-- On this client, registering an event that does not exist throws and aborts
-- the file, so every registration is protected.
function ns.SafeRegisterEvent(frame, event)
    return pcall(frame.RegisterEvent, frame, event)
end

-- Riding a boat or a zeppelin: the position moves faster than the player
-- does (standing on deck the player's own speed is 0). Checked five times a
-- second; ns.riding stays set a few seconds after, as transports pause.
-- A ride starts only after RIDE_HITS readings in a row moving while the
-- player stands still (a fall or a knockback is shorter); once on board,
-- walking on deck does not end it.
-- Nothing is recorded or counted meanwhile: the sea is not a path.
ns.riding = false
local rideM, rideX, rideY, rideT, rideUntil
local rideHits = 0
local RIDE_HITS = 10 -- two seconds

local function CheckRiding()
    local now = GetTime()
    local m, x, y = ns.PlayerPos()
    if m and rideM then
        local d = ns.WorldDist(rideM, rideX, rideY, m, x, y)
        local dt = now - rideT
        local ok, speed = pcall(GetUnitSpeed, "player")
        if not ok or type(speed) ~= "number" then speed = 7 end
        local moved = d and dt > 0 and d < ns.cfg.TELEPORT and d > speed * dt * 1.5 + 1.5
        if moved and (speed < 0.1 or ns.riding) then
            rideHits = rideHits + 1
        elseif d then
            rideHits = 0
        end
        if rideHits >= RIDE_HITS then rideUntil = now + 3 end
    end
    rideM, rideX, rideY, rideT = m, x, y, now
    ns.riding = rideUntil ~= nil and now < rideUntil
end

local defaults = {
    version = 1,
    recording = true,
    minimap = true,      -- active route drawn on the minimap
    carbonite = true,    -- active route drawn on Carbonite's map, if installed
    pathsAlways = false, -- false: recorded paths show on the map only while Shift is held
    cityPaths = false,   -- recorded paths drawn in capital cities too
    trail = true,        -- what is walked this session shown as green breadcrumbs
    arrow = { shown = true },
    odometer = { shown = false }, -- yards walked, see Odometer.lua
    walked = {},                  -- yards walked in total, per character
    useBoats = true,              -- routes may include boats and zeppelins learned
    boats = {},                   -- trips learned, see Transports.lua
    boatTimes = {},               -- times measured of the known trips
    imports = {},                 -- paths imported from other players, see Share.lua
    avoidEnemy = true,            -- routes keep away from the other faction's towns
    followWaypoints = true,       -- waypoints set by other addons or on the map become the destination
    maps = {},
    portals = {}, -- zone crossings, see Graph.AddPortal
    useFlights = true, -- routes may include flights the character knows
    flights = {},      -- known flight masters per character, see Flights.lua
    flightNames = {},  -- flight master names in the client's language, by node id
}

local loader = CreateFrame("Frame")
ns.SafeRegisterEvent(loader, "ADDON_LOADED")
ns.SafeRegisterEvent(loader, "PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        if type(BaquianoDB) ~= "table" then BaquianoDB = {} end
        for k, v in pairs(defaults) do
            if BaquianoDB[k] == nil then
                BaquianoDB[k] = (type(v) == "table") and CopyTable(v) or v
            end
        end
        BaquianoDB.showNetwork = nil -- replaced by pathsAlways
    elseif event == "PLAYER_LOGIN" then
        C_Timer.NewTicker(0.2, function() pcall(CheckRiding) end)
        for _, name in ipairs({ "Flights", "Transports", "Recorder", "MapOverlay", "MinimapOverlay", "CarboniteOverlay", "Arrow", "Odometer", "Waypoints", "Share", "Options" }) do
            local mod = ns[name]
            if mod and mod.Init then
                local ok, err = pcall(mod.Init)
                if not ok then
                    ns.Print("could not start " .. name .. ": " .. tostring(err))
                end
            end
        end
        local zones, points = 0, 0
        for _, m in pairs(BaquianoDB.maps) do
            zones = zones + 1
            points = points + math.floor(#(m.nodes or {}) / 2)
        end
        ns.Print(string.format("loaded: %d points saved in %d zones. Type /baq to see the commands.",
            points, zones))
    end
end)
