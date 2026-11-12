-- Baquiano: navigation. Holds the active route and advances point by point.
local ADDON, ns = ...

local Nav = {}
ns.Nav = Nav

local cfg = ns.cfg

Nav.route = nil -- active route (see Pathfinder.Find)
Nav.index = 1   -- route point currently being walked to

local lastOffRouteCheck = 0

function Nav.Clear()
    Nav.route = nil
    Nav.index = 1
    ns.MapOverlay.MarkDirty()
end

-- Whether (mapID: x, y) is within the given yards of the destination.
function Nav.IsDestination(mapID, x, y, yards)
    local route = Nav.route
    if not route then return false end
    local d = ns.WorldDist(route.destMap, route.destX, route.destY, mapID, x, y)
    return d ~= nil and d <= yards
end

-- Clears the route at the player's request (map click, arrow, key).
function Nav.Unmark()
    if not Nav.route then return end
    Nav.Clear()
    ns.Print("route cleared.")
end

-- Sets a destination at (x, y) of map destMap, which may be another zone.
-- Returns the route, or nil and the reason.
function Nav.SetDestination(destMap, x, y)
    local pMap, px, py = ns.PlayerPos()
    if not pMap then
        return nil, "the game does not give your position here."
    end
    local route, why = ns.Pathfinder.Find(pMap, px, py, destMap, x, y)
    if not route then return nil, why end
    Nav.route = route
    Nav.index = 1
    Nav.onRoute = false
    ns.MapOverlay.MarkDirty()
    return route
end

-- New route from the player's position to the same destination.
-- Keeps the old one if no route is found from here.
local function Recalculate(mapID, x, y)
    local old = Nav.route
    local route = ns.Pathfinder.Find(mapID, x, y, old.destMap, old.destX, old.destY)
    if not route then return false end
    Nav.route = route
    Nav.index = 1
    Nav.onRoute = false
    ns.MapOverlay.MarkDirty()
    return true
end

-- One click reaches Baquiano only once, even if both the Blizzard map and
-- Carbonite's see it (one on press, the other on release). Returns false if
-- a click was already used a moment ago.
local clickTime
function Nav.ClickOnce()
    local now = GetTime()
    if clickTime and now - clickTime < 0.4 then return false end
    clickTime = now
    return true
end

local function ZoneName(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return (info and info.name) or ("zone " .. tostring(mapID))
end

-- Lists the active route in the chat, to check what was calculated.
function Nav.Describe()
    local route = Nav.route
    if not route then
        ns.Print("no active route.")
        return
    end
    ns.Print(string.format("route to %s %.1f %.1f (now at point %d of %d):",
        ZoneName(route.destMap), route.destX * 100, route.destY * 100, Nav.index, #route.points))
    -- Runs of points in the same zone are summed up in one line.
    local pts = route.points
    local i = 1
    while i <= #pts do
        local p = pts[i]
        if p.board and pts[i + 1] and pts[i + 1].sail then
            print(string.format("  %d. %s in %s %.1f %.1f: %s to %s", i,
                pts[i + 1].ride == "tram" and "tram" or "dock", ZoneName(p[3]),
                p[1] * 100, p[2] * 100, pts[i + 1].ride or "boat or zeppelin", pts[i + 1].sail))
            i = i + 1
        elseif p.board then
            print(string.format("  %d. flight master in %s %.1f %.1f: fly to %s", i, ZoneName(p[3]),
                p[1] * 100, p[2] * 100, pts[i + 1] and ns.Flights.Name(pts[i + 1].fly) or "?"))
            i = i + 1
        elseif p.fly or p.sail then
            print(string.format("  %d. land in %s %.1f %.1f", i, ZoneName(p[3]), p[1] * 100, p[2] * 100))
            i = i + 1
        else
            local j = i
            while j < #pts and pts[j + 1][3] == p[3] and not pts[j + 1].board and not pts[j + 1].fly
                and not pts[j + 1].sail do
                j = j + 1
            end
            local q = pts[j]
            print(string.format("  %d-%d. walk in %s from %.1f %.1f to %.1f %.1f", i, j, ZoneName(p[3]),
                p[1] * 100, p[2] * 100, q[1] * 100, q[2] * 100))
            i = j + 1
        end
    end
end

-- What is left of the route from the player at (mapID: x, y): yards to walk
-- and yards to fly, along the route's points. If a flight comes first, also
-- the yards to walk to its flight master and that point's index.
function Nav.Remaining(mapID, x, y)
    local route = Nav.route
    if not route then return 0, 0 end
    local pts = route.points
    local walk, fly = 0, 0
    local toBoard, boardAt
    local pm, px, py = mapID, x, y
    for i = Nav.index, #pts do
        local p = pts[i]
        local d = ns.WorldDist(pm, px, py, p[3], p[1], p[2])
        if d then
            if p.fly or p.sail then fly = fly + d else walk = walk + d end
        end
        if p.board and not boardAt then toBoard, boardAt = walk, i end
        pm, px, py = p[3], p[1], p[2]
    end
    return walk, fly, toBoard, boardAt
end

-- Tells the player what kind of route was found.
function Nav.Announce(route)
    ns.Print(string.format("destination: %s %.1f %.1f.", ZoneName(route.destMap),
        route.destX * 100, route.destY * 100))
    if not route.usedNetwork then
        ns.Print("no recorded paths help here; guiding you in a straight line.")
        return
    end
    local msg = "route found along known paths."
    if route.partial then
        msg = "partial route: recorded paths do not reach that far; the last stretch is a straight line."
    end
    ns.Print(msg)
    for _, id in ipairs(route.flights or {}) do
        ns.Print("the route includes a flight to " .. ns.Flights.Name(id) .. ".")
    end
    for _, ride in ipairs(route.boats or {}) do
        ns.Print("the route includes the " .. ride .. ".")
    end
    if route.gaps and route.gaps > 0 then
        ns.Print(string.format("the route crosses %d unrecorded stretch%s in a straight line.",
            route.gaps, route.gaps == 1 and "" or "es"))
    end
    if route.enemy then
        ns.Print("|cffff5050careful:|r the route goes through " .. route.enemy
            .. ", a town of the other faction.")
    end
end

-- Called several times per second with the player's position.
-- Returns the current point (x, y), its distance and whether it is the final one;
-- nil if there is no route or the player is in a zone the route does not cross.
function Nav.Update(mapID, x, y)
    local route = Nav.route
    if not route then return nil end
    local pts = route.points
    local n = #pts
    local now = GetTime()

    -- On a flight there is nothing to guide: the route goes on from where it
    -- lands. Taking the flight moves on to the landing point.
    if UnitOnTaxi and UnitOnTaxi("player") then
        if pts[Nav.index].board and Nav.index < n then
            Nav.index = Nav.index + 1
            ns.MapOverlay.MarkDirty()
        end
        lastOffRouteCheck = now
        return nil
    end

    -- On a boat or zeppelin, likewise: boarding moves on to the landing dock,
    -- and nothing is guided until a while after it stops (a loading screen
    -- between continents pauses the ride too).
    if ns.riding then Nav.rideSeen = now end
    if Nav.rideSeen and now - Nav.rideSeen < 15 then
        local p = pts[Nav.index]
        if p.board and pts[Nav.index + 1] and pts[Nav.index + 1].sail and ns.riding then
            Nav.index = Nav.index + 1
            ns.MapOverlay.MarkDirty()
        end
        if pts[Nav.index].sail and ns.riding then
            lastOffRouteCheck = now
            return nil
        end
    end

    -- Each point carries its zone. Entering the next zone of the route
    -- continues from its first point there.
    if pts[Nav.index][3] ~= mapID then
        local found
        for i = Nav.index + 1, n do
            if pts[i][3] == mapID then
                found = i
                break
            end
        end
        if found then
            Nav.index = found
            ns.MapOverlay.MarkDirty()
        elseif Nav.index > 1 and pts[Nav.index - 1][3] == mapID then
            -- Still walking up to the border: the next point is just across it.
        else
            -- A zone off the route (or the player went back): try from here.
            if now - lastOffRouteCheck <= 2 then return nil end
            lastOffRouteCheck = now
            if not Recalculate(mapID, x, y) then return nil end
            route = Nav.route
            pts = route.points
            n = #pts
            if pts[Nav.index][3] ~= mapID then return nil end
        end
    end

    -- If the player is already next to a later point (shortcut), skip ahead to it.
    for i = n, Nav.index, -1 do
        local p = pts[i]
        local radius = (i == n) and cfg.ARRIVE_FINAL or (p.fly and cfg.FLY_ARRIVE)
            or (p.dock and cfg.BOAT_ARRIVE) or cfg.ARRIVE
        if p[3] == mapID and ns.Dist(mapID, x, y, p[1], p[2]) <= radius then
            if i == n then
                ns.Print("you have arrived.")
                Nav.Clear()
                return nil
            end
            if p.board then
                -- At the flight master: the route waits here until the flight is taken.
                if Nav.told ~= p then
                    Nav.told = p
                    local nx = pts[i + 1]
                    if nx.sail then
                        ns.Print("take the " .. (nx.ride or "boat or zeppelin") .. " to " .. nx.sail .. ".")
                    else
                        ns.Print("take the flight to " .. ns.Flights.Name(nx.fly) .. ".")
                    end
                end
                Nav.index = i
            else
                Nav.index = i + 1
            end
            ns.MapOverlay.MarkDirty()
            break
        end
    end

    -- If the player strays far from the rest of the route, recalculate from here.
    if now - lastOffRouteCheck > 2 then
        lastOffRouteCheck = now
        local minD
        for i = math.max(1, Nav.index - 1), n do
            if pts[i][3] == mapID then
                local d = ns.Dist(mapID, x, y, pts[i][1], pts[i][2])
                if not minD or d < minD then minD = d end
            end
        end
        if minD and minD <= cfg.OFFROUTE then
            Nav.onRoute = true
        elseif minD and Nav.onRoute and n > 1 then
            -- Only after having been on the route, so it does not recalculate in a loop
            -- while the player is still approaching the first point.
            if Recalculate(mapID, x, y) then
                route = Nav.route
                pts = route.points
                n = #pts
            end
        end
    end

    -- The next point may lie just across the border, in the next zone: it is
    -- converted to this zone's coordinates so the arrow can still point at it.
    local p = pts[Nav.index]
    local tx, ty = ns.ConvertXY(p[3], p[1], p[2], mapID)
    if not tx then return nil end
    return tx, ty, ns.Dist(mapID, x, y, tx, ty), Nav.index == n
end
