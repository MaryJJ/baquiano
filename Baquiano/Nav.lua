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

-- Sets a destination in the current zone. Returns the route, or nil and the reason.
function Nav.SetDestination(mapID, x, y)
    local pMap, px, py = ns.PlayerPos()
    if not pMap then
        return nil, "the game does not give your position here."
    end
    if pMap ~= mapID then
        return nil, "for now, routes only work within the zone you are in."
    end
    Nav.route = ns.Pathfinder.Find(mapID, px, py, x, y)
    Nav.index = 1
    Nav.onRoute = false
    ns.MapOverlay.MarkDirty()
    return Nav.route
end

-- Called several times per second with the player's position.
-- Returns the current point (x, y), its distance and whether it is the final one;
-- nil if there is no route or the player is in another zone.
function Nav.Update(mapID, x, y)
    local route = Nav.route
    if not route or route.mapID ~= mapID then return nil end
    local pts = route.points
    local n = #pts

    -- If the player is already next to a later point (shortcut), skip ahead to it.
    for i = n, Nav.index, -1 do
        local radius = (i == n) and cfg.ARRIVE_FINAL or cfg.ARRIVE
        if ns.Dist(mapID, x, y, pts[i][1], pts[i][2]) <= radius then
            if i == n then
                ns.Print("you have arrived.")
                Nav.Clear()
                return nil
            end
            Nav.index = i + 1
            ns.MapOverlay.MarkDirty()
            break
        end
    end

    -- If the player strays far from the rest of the route, recalculate from here.
    local now = GetTime()
    if now - lastOffRouteCheck > 2 then
        lastOffRouteCheck = now
        local minD
        for i = Nav.index, n do
            local d = ns.Dist(mapID, x, y, pts[i][1], pts[i][2])
            if not minD or d < minD then minD = d end
        end
        if minD and minD <= cfg.OFFROUTE then
            Nav.onRoute = true
        elseif minD and Nav.onRoute and n > 1 then
            -- Only after having been on the route, so it does not recalculate in a loop
            -- while the player is still approaching the first point.
            Nav.route = ns.Pathfinder.Find(mapID, x, y, route.destX, route.destY)
            Nav.index = 1
            Nav.onRoute = false
            ns.MapOverlay.MarkDirty()
            route = Nav.route
            pts = route.points
            n = #pts
        end
    end

    local p = pts[Nav.index]
    return p[1], p[2], ns.Dist(mapID, x, y, p[1], p[2]), Nav.index == n
end
