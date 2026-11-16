-- Baquiano: flights. Flight masters and the flights between them come from
-- FlightData.lua (generated from the game's tables, see tools/make_flights.py).
-- Which ones this character knows is learned each time a flight master's map
-- is opened; only those are used for routes.
local ADDON, ns = ...

local Flights = {}
ns.Flights = Flights

local function Data()
    return ns.FlightData
end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Known flight masters of this character: known[nodeID] = true.
local function Known()
    local key = CharKey()
    local known = BaquianoDB.flights[key]
    if not known then
        known = {}
        BaquianoDB.flights[key] = known
    end
    return known
end

function Flights.KnownCount()
    local data, count = Data(), 0
    if not data then return 0 end
    for id in pairs(Known()) do
        if data.nodes[id] then count = count + 1 end
    end
    return count
end

-- Name of a flight master, in the client's language once it has been seen.
function Flights.Name(id)
    local name = BaquianoDB.flightNames[id]
    if name then return name end
    local d = Data() and Data().nodes[id]
    return d and d[1] or ("flight master " .. tostring(id))
end

-- Player's current running speed (mounted or not), in yards per second.
function Flights.RunSpeed()
    local ok, _, run = pcall(GetUnitSpeed, "player")
    if ok and type(run) == "number" and run > 0 then return run end
    return 7
end

-- World position of a flight master: continentID, wx, wy (yards).
function Flights.World(id)
    local d = Data() and Data().nodes[id]
    if not d then return nil end
    return d[2], d[3], d[4]
end

-- Text compared loosely: lower case, no accents, no doubled letters, only
-- letters and digits ("Orgrimmar" and "ogrimar" end up close).
local ACCENTS = {
    ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n",
    ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ú"] = "u", ["Ü"] = "u", ["Ñ"] = "n",
    ["à"] = "a", ["è"] = "e", ["ê"] = "e", ["ô"] = "o", ["ç"] = "c", ["ö"] = "o", ["ä"] = "a",
}
local function Loose(s)
    s = s:gsub("\195[\128-\191]", ACCENTS):lower():gsub("[^%w]", "")
    return (s:gsub("(%a)%1+", "%1"))
end

-- Edit distance between two strings (letters added, removed or changed).
local function Distance(a, b)
    local prev = {}
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        local cur = { [0] = i }
        for j = 1, #b do
            local same = a:byte(i) == b:byte(j) and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + same)
        end
        prev = cur
    end
    return prev[#b]
end

-- The flight master whose town best matches text ("orgrimmar", "cima del
-- trueno", "crossroads"), in English or as the game names it: a match at the
-- start of the name, then anywhere in it, then the closest spelling; among
-- equals, the nearest to the player. Returns its id, or nil.
function Flights.Search(text)
    local data = Data()
    local q = Loose(text)
    if not data or q == "" then return nil end
    local pc, pwx, pwy
    local pm, px, py = ns.PlayerPos()
    if pm then pc, pwx, pwy = ns.WorldXY(pm, px, py) end

    local best, bestScore
    for id, d in pairs(data.nodes) do
        if not d[1]:find("^Quest Path") and not d[1]:find("^zz") then
            local score
            for _, name in ipairs({ BaquianoDB.flightNames[id] or "", d[1] }) do
                local town = Loose(name:match("^[^,]*") or name) -- "Crossroads, The Barrens"
                local full = Loose(name)
                local s
                if town ~= "" and town:sub(1, #q) == q then
                    s = 0
                elseif full:find(q, 1, true) then
                    s = 1
                elseif town ~= "" then
                    local dist = Distance(q, town)
                    if dist <= math.max(1, math.floor(#town / 4)) then s = 2 + dist end
                end
                if s and (not score or s < score) then score = s end
            end
            if score then
                -- Nearer first among equals; another continent last.
                local far = 1e9
                if pc and d[2] == pc then far = math.sqrt((d[3] - pwx) ^ 2 + (d[4] - pwy) ^ 2) end
                score = score * 1e10 + far
                if not bestScore or score < bestScore then best, bestScore = id, score end
            end
        end
    end
    return best
end

-- Flight master's position in map mapID (0..1), or nil if outside it.
function Flights.InMap(id, mapID)
    local c, wx, wy = Flights.World(id)
    if not c then return nil end
    local x, y = ns.MapXYFromWorld(mapID, c, wx, wy)
    if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
    return nil
end

local function IsZoneMap(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    local types = Enum and Enum.UIMapType
    return info and types and (info.mapType == types.Zone or info.mapType == types.Micro)
end

-- Zone where a flight master stands: mapID, x, y (0..1). Zone rectangles
-- overlap (a city inside its zone), so the zone whose recorded paths come
-- closest to it wins; otherwise the zone the game places it in.
local zoneCache = {}

local function FindZone(id)
    local c, wx, wy = Flights.World(id)
    if not c then return nil end

    local best, bestD
    for mapID in pairs(BaquianoDB.maps) do
        local x, y = Flights.InMap(id, mapID)
        local g = x and ns.Graph.Get(mapID)
        if g then
            local _, d = ns.Graph.Nearest(g, x, y, ns.cfg.FLY_REACH)
            if d and (not bestD or d < bestD) then best, bestD = { mapID, x, y }, d end
        end
    end
    if best then return best end

    -- The game's own map at that spot; a continent is narrowed to its zone.
    local found
    pcall(function()
        local mapID, pos = C_Map.GetMapPosFromWorldPos(c, CreateVector2D(wx, wy))
        if mapID and pos and not IsZoneMap(mapID) and C_Map.GetMapInfoAtPosition then
            local px, py = pos:GetXY()
            local info = C_Map.GetMapInfoAtPosition(mapID, px, py)
            mapID = info and info.mapID
        end
        if IsZoneMap(mapID) then
            local x, y = Flights.InMap(id, mapID)
            if x then found = { mapID, x, y } end
        end
    end)
    if found then return found end

    -- Last resort: any zone with recorded paths that contains it.
    for mapID in pairs(BaquianoDB.maps) do
        local x, y = Flights.InMap(id, mapID)
        if x then return { mapID, x, y } end
    end
    return nil
end

function Flights.Zone(id)
    local z = zoneCache[id]
    -- While it has no recorded paths near, it is looked up again now and
    -- then: they may be recorded later.
    if not z or (not z.withPaths and GetTime() - z.time > 10) then
        z = FindZone(id) or {}
        z.time = GetTime()
        if z[1] then
            local g = ns.Graph.Get(z[1])
            z.withPaths = g and ns.Graph.Nearest(g, z[2], z[3], ns.cfg.FLY_REACH) ~= nil
        end
        zoneCache[id] = z
    end
    if not z[1] then return nil end
    return z[1], z[2], z[3]
end

-- Flights this character can take: adj[from] = { { to, yards }, ... }, both
-- ends known. nil if none (or flights are turned off).
function Flights.Graph()
    local data = Data()
    if not data or not BaquianoDB.useFlights then return nil end
    local known = Known()
    local adj, any = {}, false
    local f = data.flights
    for k = 1, #f, 3 do
        local a, b, yards = f[k], f[k + 1], f[k + 2]
        if known[a] and known[b] then
            adj[a] = adj[a] or {}
            adj[a][#adj[a] + 1] = { b, yards }
            any = true
        end
    end
    return any and adj or nil
end

-- Reads the flight master's map that has just opened.
local function Learn()
    local data = Data()
    if not data then return end
    local known, names = Known(), BaquianoDB.flightNames
    local before = Flights.KnownCount()
    local read = false

    -- Newer API: node ids directly.
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
        local uiMap = (GetTaxiMapID and GetTaxiMapID()) or C_Map.GetBestMapForUnit("player")
        local ok, list = pcall(C_TaxiMap.GetAllTaxiNodes, uiMap)
        if ok and type(list) == "table" and #list > 0 then
            local unreachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Unreachable
            for _, n in ipairs(list) do
                if n.nodeID and data.nodes[n.nodeID] and n.state ~= unreachable then
                    known[n.nodeID] = true
                    if n.name then names[n.nodeID] = n.name end
                end
            end
            read = true
        end
    end

    -- Older API: names only, matched to node ids.
    if not read and NumTaxiNodes then
        local byName = {}
        for id, d in pairs(data.nodes) do byName[d[1]] = id end
        for id, name in pairs(names) do byName[name] = id end
        if C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
            for _, cont in ipairs({ 1414, 1415 }) do -- Kalimdor, Eastern Kingdoms
                local ok, list = pcall(C_TaxiMap.GetTaxiNodesForMap, cont)
                for _, n in ipairs(ok and list or {}) do
                    if n.name and n.nodeID then byName[n.name] = n.nodeID end
                end
            end
        end
        for i = 1, NumTaxiNodes() do
            local kind = TaxiNodeGetType(i)
            if kind == "CURRENT" or kind == "REACHABLE" then
                local name = TaxiNodeName(i)
                local id = name and byName[name]
                if id and data.nodes[id] then
                    known[id] = true
                    names[id] = name
                end
            end
        end
    end

    local after = Flights.KnownCount()
    if after > before then
        ns.Print(string.format("%d flight master%s known; routes can use flights now.",
            after, after == 1 and "" or "s"))
    end
end

function Flights.Init()
    if not Data() then
        ns.Print("flight data missing (FlightData.lua); routes will not use flights.")
        return
    end
    local f = CreateFrame("Frame")
    ns.SafeRegisterEvent(f, "TAXIMAP_OPENED")
    f:SetScript("OnEvent", function()
        local ok, err = pcall(Learn)
        if not ok then ns.Print("could not read the flight map: " .. tostring(err)) end
    end)
end

function Flights.Toggle()
    BaquianoDB.useFlights = not BaquianoDB.useFlights
    return BaquianoDB.useFlights
end
