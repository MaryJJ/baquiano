-- Baquiano: Carbonite's map, through its public Map Provider API
-- (Carbonite\Docs\MapProvider.md):
--   - the active route, as a row of moving arrows like Carbonite's own;
--   - the recorded paths, when shown (PathView.Toggle), blue outdoors and
--     violet indoors, bundled like on the Blizzard map;
--   - Alt + left click on Carbonite's map sets a destination.
-- Does nothing without Carbonite.
local ADDON, ns = ...

local CarboniteOverlay = {}
ns.CarboniteOverlay = CarboniteOverlay

local routeLayer, pathLayer, trailLayer, coords
local lastRoute
local pathsKey -- what the path layer currently shows (see PathsKey)
local trailKey -- same for the trail layer
local hooked

-- Point (x, y) of map mapID (0..1) in Carbonite world coordinates, or nil.
local function World(mapID, x, y)
    local wx, wy = coords:WorldFromZone(mapID, x * 100, y * 100)
    if not wx or (wx == 0 and wy == 0) then return nil end
    return wx, wy
end

-- The same look as on the other maps (PathView), and as Carbonite's own
-- routes: arrows every ARROW_GAP screen pixels, gold when walking and white
-- when flying, moving forward; the gold disc on the destination.
local ARROW_GAP, MAX_ARROWS = 18, 400

-- Carbonite's main map, for its zoom and visible area.
local function CarbMap()
    local Nx = _G.Nx
    return Nx and Nx.Map and Nx.Map.Maps and Nx.Map.Maps[1]
end

-- Turns the pin's arrow (pointing up) by pin.angle, clockwise. Done through
-- the texture coordinates, as Carbonite turns its own arrows; Carbonite
-- resets them for every icon it stamps, so other icons are not affected.
local function TurnArrow(pin, f)
    local co, si = math.cos(pin.angle), math.sin(pin.angle)
    local function UV(u, v)
        u, v = u - 0.5, v - 0.5
        return u * co + v * si + 0.5, -u * si + v * co + 0.5
    end
    local x1, y1 = UV(0, 0)
    local x2, y2 = UV(0, 1)
    local x3, y3 = UV(1, 0)
    local x4, y4 = UV(1, 1)
    f.texture:SetTexCoord(x1, y1, x2, y2, x3, y3, x4, y4)
end

local function DrawRoute()
    routeLayer:Clear()
    local route = ns.Nav.route
    local map = CarbMap()
    if not route or not map or not map.ScaleDraw or map.ScaleDraw <= 0 then return end

    -- Carbonite draws world point (wx, wy) at pixel
    -- ((wx - MapPosXDraw) * ScaleDraw, (wy - MapPosYDraw) * ScaleDraw) from
    -- the map's centre, y down: the line is built in those pixels.
    local scale, cx, cy = map.ScaleDraw, map.MapPosXDraw or 0, map.MapPosYDraw or 0
    local halfW, halfH = (map.MapW or 0) / 2 + 20, (map.MapH or 0) / 2 + 20
    local line = {}
    local mapID, px, py = ns.PlayerPos()
    if mapID then
        local wx, wy = World(mapID, px, py)
        if wx then line[1] = { (wx - cx) * scale, (wy - cy) * scale } end
    end
    for _, p in ipairs(ns.PathView.RouteLine(route, ns.Nav.index)) do
        local wx, wy = World(p[3], p[1], p[2])
        if wx then line[#line + 1] = { (wx - cx) * scale, (wy - cy) * scale, ns.PathView.Kind(p) } end
    end

    local count = 0
    ns.PathView.Arrows(line, ARROW_GAP, ns.PathView.ArrowPhase(ARROW_GAP), function(x, y, angle, kind)
        -- Only arrows in view.
        if math.abs(x) <= halfW and math.abs(y) <= halfH then
            count = count + 1
            if count > MAX_ARROWS then return false end
            routeLayer:Add((kind == "fly" and "ArrowFlight") or (kind == "gap" and "ArrowGap") or "Arrow", cx + x / scale, cy + y / scale,
                { angle = angle, onStamp = TurnArrow })
        end
    end)

    local dx, dy = World(route.destMap, route.destX, route.destY)
    if dx then routeLayer:Add("Dest", dx, dy) end
end

-- Pin kind for a path segment: In/Out plus thickness step 1..3.
local function PathKind(inside, weight)
    local step = (weight >= 5 and 3) or (weight >= 2 and 2) or 1
    return (inside and "In" or "Out") .. step
end

-- Zones whose paths are drawn: those in view on Carbonite's map (with
-- recorded paths), like the Blizzard map shows the zone on display. While
-- Carbonite's map is closed, the last set stays.
local viewZones = {}

local function ViewZones()
    local map = CarbMap()
    if not map or not map.Frm or not map.Frm:IsVisible() or not map.ScaleDraw
        or map.ScaleDraw <= 0 then
        return viewZones
    end
    -- Visible rectangle in Carbonite world coordinates (see DrawRoute).
    local scale = map.ScaleDraw
    local cx, cy = map.MapPosXDraw or 0, map.MapPosYDraw or 0
    local halfW, halfH = (map.MapW or 0) / 2 / scale, (map.MapH or 0) / 2 / scale
    local list = {}
    for mapID in pairs(BaquianoDB.maps) do
        local ax, ay = World(mapID, 0, 0)
        local bx, by = World(mapID, 1, 1)
        if ax and bx
            and math.max(ax, bx) >= cx - halfW and math.min(ax, bx) <= cx + halfW
            and math.max(ay, by) >= cy - halfH and math.min(ay, by) <= cy + halfH then
            list[#list + 1] = mapID
        end
    end
    table.sort(list)
    viewZones = list
    return list
end

-- Changes whenever the paths to show change: shown or not, which zones, and
-- each one's network version (versions only grow).
local function PathsKey()
    if not BaquianoDB.pathsAlways then return "off" end
    local parts = { tostring(BaquianoDB.cityPaths) }
    for _, mapID in ipairs(ViewZones()) do
        local g = ns.Graph.Get(mapID)
        parts[#parts + 1] = mapID .. "=" .. (g and g.version or 0)
    end
    return table.concat(parts, ",")
end

-- Only the zones in view (see ViewZones).
local function DrawPaths()
    pathLayer:Clear()
    if not BaquianoDB.pathsAlways then return end
    for _, mapID in ipairs(viewZones) do
        local g = ns.ShowsPaths(mapID) and ns.Graph.Get(mapID) -- not in capitals
        if g then
            for _, s in ipairs(ns.PathView.Segments(g)) do
                local x1, y1 = World(mapID, s[1], s[2])
                local x2, y2 = World(mapID, s[3], s[4])
                if x1 and x2 then
                    pathLayer:Add(PathKind(s[5], s[6]), x1, y1, { x2 = x2, y2 = y2 })
                end
            end
        end
    end
end

-- What has just been walked (Recorder.trail): green breadcrumbs, one per
-- recorded point, fading behind the player in CRUMB_STEPS steps (one pin
-- type per opacity). Small, so every zone of it is drawn.
local CRUMB_STEPS = { 1, 0.75, 0.5, 0.25 }

local function DrawTrail()
    trailLayer:Clear()
    if not BaquianoDB.pathsAlways or not BaquianoDB.trail then return end
    for mapID, list in pairs(ns.Recorder.trail) do
        for k, s in ipairs(list) do
            local a = ns.Recorder.TrailAlpha(s)
            local pin = "Crumb" .. math.min(#CRUMB_STEPS, math.floor((1 - a) * #CRUMB_STEPS) + 1)
            if k == 1 then
                local x, y = World(mapID, s[1], s[2])
                if x then trailLayer:Add(pin, x, y) end
            end
            local x, y = World(mapID, s[3], s[4])
            if x then trailLayer:Add(pin, x, y) end
        end
    end
end

-- Zone under a Carbonite world point, and the point in it (0..1). Prefers
-- the zone Carbonite is showing, then the player's, then zones with paths;
-- the continent only as a last resort.
local function ZoneAt(shown, wx, wy)
    local function InZone(mapID)
        if not mapID then return nil end
        local x, y = coords:ZoneFromWorld(mapID, wx, wy)
        if not x or (x == 0 and y == 0) then return nil end
        if x < 0 or x > 100 or y < 0 or y > 100 then return nil end
        return x / 100, y / 100
    end
    local function IsZone(mapID)
        local info = mapID and C_Map.GetMapInfo(mapID)
        return info and Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Zone
    end

    local candidates = {}
    if IsZone(shown) then candidates[#candidates + 1] = shown end
    candidates[#candidates + 1] = (ns.PlayerPos())
    for mapID in pairs(BaquianoDB.maps) do candidates[#candidates + 1] = mapID end
    candidates[#candidates + 1] = shown
    for _, mapID in ipairs(candidates) do
        local x, y = InZone(mapID)
        if x then return mapID, x, y end
    end
end

-- Alt + left click on Carbonite's map. Carbonite runs its own handler first
-- (by default Alt + left click does nothing there), which leaves the click
-- position in map.ClickFrmX/Y. Ctrl + Alt is Carbonite's edit mode: left alone.
local SNAP_PX = 12 -- a click this close (screen pixels) to the destination is on it

local function OnMapClick(map, button)
    if button ~= "LeftButton" or not IsAltKeyDown() or IsControlKeyDown() then return end
    if not map.ClickFrmX or not map.FramePosToWorldPos then return end
    if not ns.Nav.ClickOnce() then return end
    local wx, wy = map:FramePosToWorldPos(map.ClickFrmX, map.ClickFrmY)
    -- Alt + click on the destination itself unmarks it.
    local route = ns.Nav.route
    if route and map.ScaleDraw then
        local dx, dy = World(route.destMap, route.destX, route.destY)
        if dx and math.sqrt((dx - wx) ^ 2 + (dy - wy) ^ 2) * map.ScaleDraw <= SNAP_PX then
            ns.Nav.Unmark()
            return
        end
    end
    local mapID, x, y = ZoneAt(map.MapId, wx, wy)
    if not mapID then
        ns.Print("that point is outside every known zone.")
        return
    end
    local route, why = ns.Nav.SetDestination(mapID, x, y)
    if route then ns.Nav.Announce(route) else ns.Print(why) end
end

-- Carbonite creates its map some time after login: hooked once it exists.
local function TryHook()
    local Nx = _G.Nx
    local map = Nx and Nx.Map and Nx.Map.Maps and Nx.Map.Maps[1]
    if not map or not map.Frm then return end
    hooked = true
    map.Frm:HookScript("OnMouseDown", function(_, button)
        local ok, err = pcall(OnMapClick, map, button)
        if not ok then ns.Print("Carbonite click error: " .. tostring(err)) end
    end)
end

local function Setup()
    local Carbonite = _G.Carbonite
    local api = Carbonite and Carbonite.Map and Carbonite.Map.CreateProvider
    coords = Carbonite and Carbonite.Modules and Carbonite.Modules.Map
        and Carbonite.Modules.Map.Coords
    if not api or not coords or not coords.WorldFromZone then return false end

    -- Separate layers, so each is redrawn only when it changes.
    pathLayer = Carbonite.Map:CreateProvider("Baquiano Paths")
    for step, thickness in ipairs({ 1.5, 2.25, 3 }) do
        local alpha = ({ "4D", "66", "80" })[step] -- faint: 30% to 50%
        pathLayer:DefinePin("Out" .. step, { drawMode = "LINE", color = alpha .. "59CCFF", thickness = thickness })
        pathLayer:DefinePin("In" .. step, { drawMode = "LINE", color = alpha .. "D973FF", thickness = thickness })
    end

    trailLayer = Carbonite.Map:CreateProvider("Baquiano Trail")
    for step, alpha in ipairs(CRUMB_STEPS) do
        trailLayer:DefinePin("Crumb" .. step, { drawMode = "WP", tex = ns.PathView.TRAIL_DOT, w = 6, h = 6,
            alpha = alpha, scaleMode = "navigation" })
    end

    -- The textures carry their colours; alpha = 1 makes Carbonite reset the
    -- tint of the pooled icon frame. "navigation" keeps them a fixed size
    -- on screen, like Carbonite's own route arrows.
    local P = ns.PathView
    routeLayer = Carbonite.Map:CreateProvider("Baquiano")
    local function Icon(tex, size)
        return { drawMode = "WP", tex = tex, w = size, h = size, alpha = 1, scaleMode = "navigation" }
    end
    routeLayer:DefinePin("Arrow", Icon(P.ARROW, 14))
    routeLayer:DefinePin("ArrowFlight", Icon(P.ARROW_FLIGHT, 14))
    routeLayer:DefinePin("ArrowGap", Icon(P.ARROW_GAP, 14))
    routeLayer:DefinePin("Dest", Icon(P.DEST, 16))
    return true
end

local function Report(ok, err)
    if not ok and not CarboniteOverlay.warned then
        CarboniteOverlay.warned = true
        ns.Print("Carbonite drawing error: " .. tostring(err))
    end
end

function CarboniteOverlay.Init()
    if not _G.Carbonite then return end
    local ok, ready = pcall(Setup)
    if not ok or not ready then
        if not ok then ns.Print("could not connect to Carbonite: " .. tostring(ready)) end
        return
    end

    C_Timer.NewTicker(0.25, function()
        if not hooked then pcall(TryHook) end

        -- Paths: rebuilt only when they change.
        local key = PathsKey()
        if key ~= pathsKey then
            pathsKey = key
            Report(pcall(DrawPaths))
        end
        local tkey = (BaquianoDB.pathsAlways and BaquianoDB.trail) and ns.Recorder.trailVersion or "off"
        if tkey ~= trailKey then
            trailKey = tkey
            Report(pcall(DrawTrail))
        end

    end)

    -- Route: its arrows move, follow the player and depend on the zoom, so
    -- they are placed again 20 times a second while Carbonite's map is shown.
    C_Timer.NewTicker(0.05, function()
        local route = ns.Nav.route
        local map = CarbMap()
        local shown = map and map.Frm and map.Frm:IsVisible()
        if not BaquianoDB.carbonite or not shown then route = nil end
        if not route and not lastRoute then return end
        if route then
            Report(pcall(DrawRoute))
        else
            Report(pcall(routeLayer.Clear, routeLayer))
        end
        lastRoute = route
    end)
end

function CarboniteOverlay.Toggle()
    BaquianoDB.carbonite = not BaquianoDB.carbonite
    return BaquianoDB.carbonite
end
