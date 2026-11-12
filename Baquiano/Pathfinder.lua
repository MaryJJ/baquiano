-- Baquiano: shortest-path search over the network (A*), across zones and,
-- with known flights, through the air.
local ADDON, ns = ...

local Pathfinder = {}
ns.Pathfinder = Pathfinder

local Graph = ns.Graph

-- Binary min-heap of (node, priority) pairs.
local function HeapPush(heap, node, prio)
    local i = #heap + 1
    heap[i] = { node, prio }
    while i > 1 do
        local parent = math.floor(i / 2)
        if heap[parent][2] <= heap[i][2] then break end
        heap[parent], heap[i] = heap[i], heap[parent]
        i = parent
    end
end

local function HeapPop(heap)
    local top = heap[1]
    local n = #heap
    heap[1] = heap[n]
    heap[n] = nil
    n = n - 1
    local i = 1
    while true do
        local l, r, smallest = i * 2, i * 2 + 1, i
        if l <= n and heap[l][2] < heap[smallest][2] then smallest = l end
        if r <= n and heap[r][2] < heap[smallest][2] then smallest = r end
        if smallest == i then break end
        heap[smallest], heap[i] = heap[i], heap[smallest]
        i = smallest
    end
    return top[1]
end

-- A node of any zone is identified by one number: mapID and index together.
-- Flight masters are negative numbers: -nodeID.
local SHIFT = 1048576
local function Key(mapID, i) return mapID * SHIFT + i end
local function Split(key)
    local m = math.floor(key / SHIFT)
    return m, key - m * SHIFT
end

local DEST = 0 -- virtual node standing for the destination itself

-- Docks of boats and zeppelins (Transports): -(DOCK + trip * 2 + side), side
-- 0 where the trip was boarded and 1 where it landed. Flight masters are the
-- negative numbers above -DOCK.
local DOCK = 1000000
local function DockKey(t, side) return -(DOCK + t * 2 + side) end
local function IsDock(key) return key <= -DOCK end
local function IsFlight(key) return key < 0 and key > -DOCK end
local function DockOf(key)
    local n = -key - DOCK
    local side = n % 2
    return (n - side) / 2, side
end

-- The other faction: "A" or "H", or nil (avoiding is off, or no faction).
local function EnemySide()
    if not BaquianoDB.avoidEnemy then return nil end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction == "Horde" then return "A" end
    if faction == "Alliance" then return "H" end
end

-- Name of the other faction's town at (mapID: x, y), or nil: within
-- ENEMY_RADIUS of the flight master of one of its towns (FlightData.towns),
-- or inside one of its capital cities.
function Pathfinder.EnemyTown(mapID, x, y)
    local side = EnemySide()
    if not side then return nil end
    if ns.CITIES[mapID] == side then
        local info = C_Map.GetMapInfo(mapID)
        return info and info.name or "a capital city"
    end
    local towns = ns.FlightData and ns.FlightData.towns
    if not towns then return nil end
    local c, wx, wy = ns.WorldXY(mapID, x, y)
    if not c then return nil end
    local r2 = ns.cfg.ENEMY_RADIUS ^ 2
    for id, t in pairs(towns) do
        if t[2] == side and t[3] == c and (t[4] - wx) ^ 2 + (t[5] - wy) ^ 2 <= r2 then
            return BaquianoDB.flightNames[id] or t[1]
        end
    end
end

-- Position of any node key: mapID, x, y.
local function Pos(key)
    if IsDock(key) then return ns.Transports.Dock(DockOf(key)) end
    if key < 0 then return ns.Flights.Zone(-key) end
    local m, i = Split(key)
    local x, y = Graph.NodeXY(Graph.Get(m), i)
    return m, x, y
end

-- Nodes where the route may enter or leave the network: every node within
-- REACH of the point, or the single nearest one if none is that close.
-- With inside given (true/false), nodes of that kind are preferred if any is
-- within REACH: inside a cave, the path above it is not an entry.
local function Entries(g, x, y, inside)
    local list = Graph.Within(g, x, y, ns.cfg.REACH)
    if inside ~= nil then
        local same = {}
        for _, i in ipairs(list) do
            if Graph.Inside(g, i) == inside then same[#same + 1] = i end
        end
        if #same > 0 then list = same end
    end
    if #list == 0 then
        local i = Graph.Nearest(g, x, y)
        if i then list[1] = i end
    end
    return list
end

-- Saved zone crossings resolved to node keys: links[key] = { otherKey, ... }.
local function PortalLinks()
    local links = {}
    local function Add(a, b)
        links[a] = links[a] or {}
        links[a][#links[a] + 1] = b
    end
    for _, p in ipairs(BaquianoDB.portals) do
        local ga, gb = Graph.Get(p[1]), Graph.Get(p[4])
        local a = ga and Graph.Nearest(ga, p[2], p[3], ns.cfg.JOIN)
        local b = gb and Graph.Nearest(gb, p[5], p[6], ns.cfg.JOIN)
        if a and b then
            Add(Key(p[1], a), Key(p[4], b))
            Add(Key(p[4], b), Key(p[1], a))
        end
    end
    return links
end

-- Cost of walking d yards in a straight line off the recorded paths, as for
-- gaps; nil if too far.
local function Straight(d, near)
    if not d then return nil end
    if d <= near then return d end
    if d <= ns.cfg.BRIDGE then return d * ns.cfg.BRIDGE_COST end
    return nil
end

-- Node path from (sm: sx, sy) towards (dm: dx, dy). The player and the
-- destination act as virtual nodes linked in a straight line to the nearby
-- network nodes. Within a zone the search follows links and gap bridges;
-- between zones, the learned crossings; and known flights between flight
-- masters. Costs are yards of walking: a flight counts as the yards that
-- could be run in the time it takes. If the destination is unreachable, the
-- path ends at the reachable node of the destination's zone nearest to it.
-- Returns the list of node keys and whether the destination was reached.
local function AStar(sm, sx, sy, dm, dx, dy)
    local cfg = ns.cfg
    local graphs, bridges = {}, {}
    local function G(m)
        if graphs[m] == nil then graphs[m] = Graph.Get(m) or false end
        return graphs[m]
    end
    local function Bridges(m)
        if not bridges[m] then bridges[m] = Graph.Bridges(G(m)) end
        return bridges[m]
    end
    local portals = PortalLinks()

    -- Flights: each flight master links to the recorded points around it.
    local flights = ns.Flights.Graph()
    local speed = ns.Flights.RunSpeed()
    local perYardFlown = speed / cfg.FLY_SPEED
    local boarding = cfg.FLY_WAIT * speed
    local toFlight, fromFlight = {}, {} -- [groundKey] / [flightKey] = { { key, yards }, ... }
    local ids = {} -- flight masters usable for this character
    if flights then
        for a, list in pairs(flights) do
            ids[a] = true
            for _, f in ipairs(list) do ids[f[1]] = true end
        end
        local function Link(id, m, i, x, y)
            local g = G(m)
            local nx, ny = Graph.NodeXY(g, i)
            local step = Straight(ns.Dist(m, x, y, nx, ny), cfg.FLY_REACH)
            if step then
                local gk, fk = Key(m, i), -id
                toFlight[gk] = toFlight[gk] or {}
                toFlight[gk][#toFlight[gk] + 1] = { fk, step }
                fromFlight[fk] = fromFlight[fk] or {}
                fromFlight[fk][#fromFlight[fk] + 1] = { gk, step }
            end
        end
        for id in pairs(ids) do
            -- Recorded points around it, in every zone that contains it (a
            -- city and the zone around it overlap).
            for m in pairs(BaquianoDB.maps) do
                local x, y = ns.Flights.InMap(id, m)
                local g = x and G(m)
                if g then
                    for _, i in ipairs(Graph.Within(g, x, y, cfg.FLY_REACH)) do Link(id, m, i, x, y) end
                end
            end
            -- None that close: the nearest one in its own zone, as a gap.
            if not fromFlight[-id] then
                local m, x, y = ns.Flights.Zone(id)
                local g = m and G(m)
                local i = g and Graph.Nearest(g, x, y, cfg.BRIDGE)
                if i then Link(id, m, i, x, y) end
            end
        end
    end

    -- Boats and zeppelins: each dock links to the recorded points around it
    -- (in every zone that holds it), and to the other dock of its trip (both
    -- ways, unless a leg of a round trip); taking one costs the trip and the
    -- wait at the dock. A trip within one continent may cost less than its
    -- length: the estimate below is scaled down for it (boatScale).
    local boatScale = 1
    local trips = ns.Transports.Trips()
    local sailTo, toDock, fromDock, docks = {}, {}, {}, {}
    local function LinkDock(dk, m, i, x, y)
        local nx, ny = Graph.NodeXY(G(m), i)
        local step = Straight(ns.Dist(m, x, y, nx, ny), cfg.FLY_REACH)
        if step then
            local gk = Key(m, i)
            toDock[gk] = toDock[gk] or {}
            toDock[gk][#toDock[gk] + 1] = { dk, step }
            fromDock[dk] = fromDock[dk] or {}
            fromDock[dk][#fromDock[dk] + 1] = { gk, step }
        end
    end
    for t, trip in ipairs(trips) do
        local a, b = DockKey(t, 0), DockKey(t, 1)
        local c = (trip[7] + (trip.wait or cfg.BOAT_WAIT)) * speed
        sailTo[a] = sailTo[a] or {}
        sailTo[a][#sailTo[a] + 1] = { b, c }
        if not trip.oneWay then
            sailTo[b] = sailTo[b] or {}
            sailTo[b][#sailTo[b] + 1] = { a, c }
        end
        local yards = ns.WorldDist(trip[1], trip[2], trip[3], trip[4], trip[5], trip[6])
        if yards and yards > 0 then boatScale = math.min(boatScale, c / yards) end
        for _, dk in ipairs({ a, b }) do
            docks[#docks + 1] = dk
            local dm0, dx0, dy0 = Pos(dk)
            for m in pairs(BaquianoDB.maps) do
                local g = G(m)
                local x, y
                if g then x, y = ns.ConvertXY(dm0, dx0, dy0, m) end
                if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    for _, i in ipairs(Graph.Within(g, x, y, cfg.FLY_REACH)) do LinkDock(dk, m, i, x, y) end
                end
            end
            if not fromDock[dk] then
                local g = G(dm0)
                local i = g and Graph.Nearest(g, dx0, dy0, cfg.BRIDGE)
                if i then LinkDock(dk, dm0, i, dx0, dy0) end
            end
        end
    end

    -- Estimate to the destination: in its zone, the map distance; elsewhere the
    -- world distance, or 0 when the client does not give world positions.
    -- With flights, a stretch may cost less than its length, so the estimate
    -- is scaled down to never exceed the real cost.
    local hScale = flights and math.min(1, perYardFlown) or 1
    hScale = math.min(hScale, boatScale)
    local dc, dwx, dwy = ns.WorldXY(dm, dx, dy)
    local function H(key)
        local m, x, y = Pos(key)
        if not m then return 0 end
        if m == dm then return ns.Dist(dm, x, y, dx, dy) * hScale end
        if dc then
            local c, wx, wy = ns.WorldXY(m, x, y)
            if c == dc then return math.sqrt((wx - dwx) ^ 2 + (wy - dwy) ^ 2) * hScale end
        end
        return 0
    end

    -- Walking into the other faction's towns costs more (cached per node).
    local enemyCost, enemy = cfg.ENEMY_COST, {}
    local avoiding = EnemySide() ~= nil
    local function Penalty(key)
        if not avoiding or key <= 0 then return 1 end
        local e = enemy[key]
        if e == nil then
            local m, x, y = Pos(key)
            e = Pathfinder.EnemyTown(m, x, y) ~= nil
            enemy[key] = e
        end
        return e and enemyCost or 1
    end

    local cost, came, closed, heap = {}, {}, {}, {}
    local function Start(k, c)
        if not cost[k] or c < cost[k] then
            cost[k] = c
            HeapPush(heap, k, c + H(k))
        end
    end
    local gs, gd = G(sm), G(dm)
    if gs then
        -- The start is always the player's position (see Nav).
        local inside = (IsIndoors and IsIndoors()) and true or false
        for _, s in ipairs(Entries(gs, sx, sy, inside)) do
            local x, y = Graph.NodeXY(gs, s)
            Start(Key(sm, s), ns.Dist(sm, sx, sy, x, y))
        end
    end
    -- A flight master close to the player, even with no paths recorded there.
    local sc, swx, swy = ns.WorldXY(sm, sx, sy)
    for id in pairs(ids) do
        local c, wx, wy = ns.Flights.World(id)
        if sc and c == sc and ns.Flights.Zone(id) then
            local step = Straight(math.sqrt((wx - swx) ^ 2 + (wy - swy) ^ 2), cfg.FLY_REACH)
            if step then Start(-id, step + boarding) end
        end
    end
    -- A dock on the player's continent, even far and with no paths recorded
    -- on the way: a straight line to it, as a gap, when nothing better.
    for _, dk in ipairs(docks) do
        local m, x, y = Pos(dk)
        local d = ns.WorldDist(sm, sx, sy, m, x, y)
        if d then Start(dk, d <= cfg.FLY_REACH and d or d * cfg.BRIDGE_COST) end
    end
    -- Where the route may end: recorded points near the destination, in any
    -- zone. Zone maps overlap at their borders, so a point picked on one
    -- zone's map may lie on paths recorded while in the neighbouring zone.
    local exits = {}
    for m in pairs(BaquianoDB.maps) do
        local g = G(m)
        local x, y
        if g then x, y = ns.ConvertXY(dm, dx, dy, m) end
        if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            for _, t in ipairs(Graph.Within(g, x, y, cfg.REACH)) do exits[Key(m, t)] = true end
        end
    end
    if not next(exits) and gd then
        for _, t in ipairs(Entries(gd, dx, dy)) do exits[Key(dm, t)] = true end
    end

    local best, bestH
    local reached = false
    while #heap > 0 do
        local cur = HeapPop(heap)
        if cur == DEST then
            reached = true
            break
        end
        if not closed[cur] then
            closed[cur] = true
            local h = H(cur)
            local cm = Pos(cur)
            -- (h is 0 only at the destination itself or where the distance is unknown)
            if (cm == dm or h > 0) and (not bestH or h < bestH) then best, bestH = cur, h end

            local function Relax(nb, step)
                if not closed[nb] then
                    local c = cost[cur] + step
                    if not cost[nb] or c < cost[nb] then
                        cost[nb] = c
                        came[nb] = cur
                        HeapPush(heap, nb, c + (nb == DEST and 0 or H(nb)))
                    end
                end
            end

            if exits[cur] then
                local m, x, y = Pos(cur)
                Relax(DEST, ns.WorldDist(m, x, y, dm, dx, dy) or 0)
            end

            if IsDock(cur) then
                -- At a dock: sail, or walk away from it.
                for _, s in ipairs(sailTo[cur] or {}) do Relax(s[1], s[2]) end
                for _, link in ipairs(fromDock[cur] or {}) do Relax(link[1], link[2]) end
                -- Just landed: straight on to the destination on this
                -- continent, however far (as a gap). Otherwise only close by,
                -- so a route on one continent never detours by a dock.
                local m, x, y = Pos(cur)
                local d = ns.WorldDist(m, x, y, dm, dx, dy)
                local step = Straight(d, cfg.FLY_REACH)
                if d and not step and came[cur] and IsDock(came[cur]) then step = d * cfg.BRIDGE_COST end
                if step then Relax(DEST, step) end
            elseif cur < 0 then
                -- At a flight master: fly on, or walk away from it.
                local id = -cur
                for _, f in ipairs(flights[id] or {}) do
                    Relax(-f[1], f[2] * perYardFlown)
                end
                for _, link in ipairs(fromFlight[cur] or {}) do
                    Relax(link[1], link[2])
                end
                -- Landing close to the destination, even with no paths there.
                local m, x, y = Pos(cur)
                local step = Straight(ns.WorldDist(m, x, y, dm, dx, dy), cfg.FLY_REACH)
                if step then Relax(DEST, step) end
            else
                local m, i = Split(cur)
                local g = G(m)
                local list = g.adj[i]
                for k = 1, #list do
                    local nb = Key(m, list[k])
                    Relax(nb, Graph.NodeDist(g, i, list[k]) * Penalty(nb))
                end
                local hops = Bridges(m)[i]
                if hops then
                    for k = 1, #hops do
                        local nb = Key(m, hops[k])
                        Relax(nb, Graph.NodeDist(g, i, hops[k]) * cfg.BRIDGE_COST * Penalty(nb))
                    end
                end
                local cross = portals[cur]
                if cross then
                    local x, y = Graph.NodeXY(g, i)
                    for k = 1, #cross do
                        local om, ox, oy = Pos(cross[k])
                        Relax(cross[k], ns.WorldDist(m, x, y, om, ox, oy) or 5)
                    end
                end
                for _, link in ipairs(toFlight[cur] or {}) do
                    Relax(link[1], link[2] + boarding)
                end
                for _, link in ipairs(toDock[cur] or {}) do
                    Relax(link[1], link[2])
                end
            end
        end
    end

    local last = reached and came[DEST] or best
    local path = {}
    while last do
        table.insert(path, 1, last)
        last = came[last]
    end
    return path, reached
end

-- Route from (startMap: sx, sy) to (destMap: dx, dy).
-- Returns { destMap, destX, destY, points = { {x, y, mapID}, ... },
-- usedNetwork, partial, gaps, flights }, or nil and the reason.
-- gaps counts the unrecorded stretches the route crosses in a straight line.
-- A flight is two points: the flight master where it is taken (.board = true)
-- and the one where it lands (.fly = its node id); stops in between are left
-- out, the game chains them itself.
function Pathfinder.Find(startMap, sx, sy, destMap, dx, dy)
    local route = { destMap = destMap, destX = dx, destY = dy, points = {}, gaps = 0, flights = {}, boats = {} }
    local sameZone = startMap == destMap
    local direct = sameZone and ns.Dist(startMap, sx, sy, dx, dy)

    local path, reached = AStar(startMap, sx, sy, destMap, dx, dy)
    if #path > 0 then
        local fm, fx, fy = Pos(path[1])
        local lm, lx, ly = Pos(path[#path])
        if lm and lm ~= destMap then
            -- The route ends on another zone's paths: the destination is
            -- given in that zone's map, so the last stretch stays in one map.
            local cx, cy = ns.ConvertXY(destMap, dx, dy, lm)
            if cx and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
                destMap, dx, dy = lm, cx, cy
                route.destMap, route.destX, route.destY = lm, cx, cy
            end
        end
        local endDist = ns.WorldDist(lm, lx, ly, destMap, dx, dy) or math.huge
        local useful
        if sameZone then
            -- The network only helps if it is closer than the destination and
            -- gets closer to it: otherwise a straight line is better.
            local startDist = ns.WorldDist(startMap, sx, sy, fm, fx, fy) or math.huge
            useful = startDist < direct and endDist < direct
        else
            useful = true
        end
        if useful then
            for k = 1, #path do
                local key = path[k]
                local m, x, y = Pos(key)
                local prevFlight = k > 1 and IsFlight(path[k - 1])
                local nextFlight = k < #path and IsFlight(path[k + 1])
                local prevDock = k > 1 and IsDock(path[k - 1])
                local nextDock = k < #path and IsDock(path[k + 1])
                if IsFlight(key) and prevFlight and nextFlight then
                    -- A stop on the way: the flight goes on by itself.
                else
                    local pt = { x, y, m }
                    if IsFlight(key) and nextFlight then pt.board = true end
                    if IsFlight(key) and prevFlight then
                        pt.fly = -key
                        route.flights[#route.flights + 1] = -key
                    end
                    -- A boat or zeppelin: boarded at one dock (.board, .dock),
                    -- left at the other (.sail = its name, .dock, .ride = "boat",
                    -- "zeppelin" or "tram").
                    if IsDock(key) then pt.dock = true end
                    if IsDock(key) and nextDock then pt.board = true end
                    if IsDock(key) and prevDock then
                        pt.sail = ns.Transports.Name(DockOf(key))
                        pt.ride = ns.Transports.Ride((DockOf(key)))
                        route.boats[#route.boats + 1] = pt.ride .. " to " .. pt.sail
                    end
                    route.points[#route.points + 1] = pt
                end
                -- A straight line to or from a dock with no paths near it.
                local prev = path[k - 1]
                if (IsDock(key) or (prev and IsDock(prev))) and not (prev and IsDock(key) and IsDock(prev)) then
                    local d
                    if prev then
                        local pm, px, py = Pos(prev)
                        d = ns.WorldDist(pm, px, py, m, x, y)
                    else
                        d = ns.WorldDist(startMap, sx, sy, m, x, y)
                    end
                    if d and d > ns.cfg.FLY_REACH and route.points[#route.points][3] == m then
                        route.gaps = route.gaps + 1
                        route.points[#route.points].gap = true
                    end
                end
                if k > 1 and key > 0 and path[k - 1] > 0 then
                    local pm, pi = Split(path[k - 1])
                    local _, i = Split(key)
                    if pm == m and not Graph.Linked(Graph.Get(m), pi, i) then
                        -- An unrecorded gap crossed in a straight line: drawn apart.
                        route.gaps = route.gaps + 1
                        route.points[#route.points].gap = true
                    end
                end
            end
            route.usedNetwork = true
            -- Partial: the network stops short and the last stretch is a straight line.
            route.partial = (not reached) or endDist > ns.cfg.REACH
        end
    end

    if not route.usedNetwork and not sameZone then
        return nil, "no recorded path leads to that zone yet. Walk there once and Baquiano will learn the way."
    end

    -- Drop leading points that lie behind the player (never a flight master).
    local pts = route.points
    while #pts >= 2 and pts[1][3] == startMap and pts[2][3] == startMap
        and not pts[1].board and not pts[2].fly and not pts[2].sail do
        local p1, p2 = pts[1], pts[2]
        if ns.Dist(startMap, sx, sy, p2[1], p2[2]) < ns.Dist(startMap, p1[1], p1[2], p2[1], p2[2]) then
            table.remove(pts, 1)
        else
            break
        end
    end

    -- Through the other faction's town all the same (no way round, or it is
    -- the destination): the first one is named.
    for _, p in ipairs(pts) do
        route.enemy = Pathfinder.EnemyTown(p[3], p[1], p[2])
        if route.enemy then break end
    end

    -- The last stretch is a straight guess when the paths stop short of it,
    -- or when no recorded path helps at all.
    pts[#pts + 1] = { dx, dy, destMap, gap = (route.partial or not route.usedNetwork) or nil }
    return route
end
