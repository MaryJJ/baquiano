-- Baquiano: shortest-path search over the network (A*).
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

-- Node path from start towards goal. If goal is unreachable (unconnected
-- stretches), it ends at the reachable node nearest to the destination.
-- Returns the node list and whether goal was reached.
local function AStar(g, start, goal, destX, destY)
    local mapID = g.mapID
    local function H(i)
        local x, y = Graph.NodeXY(g, i)
        return ns.Dist(mapID, x, y, destX, destY)
    end

    local cost = { [start] = 0 }
    local came = {}
    local closed = {}
    local heap = {}
    local best, bestH = start, H(start)
    HeapPush(heap, start, bestH)

    local reached = false
    while #heap > 0 do
        local cur = HeapPop(heap)
        if not closed[cur] then
            closed[cur] = true
            if cur == goal then
                reached = true
                break
            end
            local h = H(cur)
            if h < bestH then best, bestH = cur, h end

            local list = g.adj[cur]
            for k = 1, #list do
                local nb = list[k]
                if not closed[nb] then
                    local c = cost[cur] + Graph.NodeDist(g, cur, nb)
                    if not cost[nb] or c < cost[nb] then
                        cost[nb] = c
                        came[nb] = cur
                        HeapPush(heap, nb, c + H(nb))
                    end
                end
            end
        end
    end

    local last = reached and goal or best
    local path = {}
    while last do
        table.insert(path, 1, last)
        last = came[last]
    end
    return path, reached
end

-- Route from (sx, sy) to (dx, dy) within one zone.
-- Returns { mapID, destX, destY, points = { {x, y}, ... }, usedNetwork, partial }.
function Pathfinder.Find(mapID, sx, sy, dx, dy)
    local route = { mapID = mapID, destX = dx, destY = dy, points = {} }
    local direct = ns.Dist(mapID, sx, sy, dx, dy)

    local g = Graph.Get(mapID)
    if g and g.n > 0 then
        local s, sDist = Graph.Nearest(g, sx, sy)
        local t = Graph.Nearest(g, dx, dy)
        -- The network only helps if its entry point is closer than the destination.
        if s and t and sDist < direct then
            local path, reached = AStar(g, s, t, dx, dy)
            local endX, endY = Graph.NodeXY(g, path[#path])
            -- And if it gets closer to the destination: otherwise a straight line is better.
            local endDist = ns.Dist(mapID, endX, endY, dx, dy)
            if endDist < direct then
                for i = 1, #path do
                    local x, y = Graph.NodeXY(g, path[i])
                    route.points[#route.points + 1] = { x, y }
                end
                route.usedNetwork = true
                -- Partial: the network stops short and the last stretch is a straight line.
                route.partial = (not reached) or endDist > ns.cfg.MAX_EDGE
            end
        end
    end

    -- Drop leading points that lie behind the player.
    local pts = route.points
    while #pts >= 2 do
        local p1, p2 = pts[1], pts[2]
        if ns.Dist(mapID, sx, sy, p2[1], p2[2]) < ns.Dist(mapID, p1[1], p1[2], p2[1], p2[2]) then
            table.remove(pts, 1)
        else
            break
        end
    end

    pts[#pts + 1] = { dx, dy }
    return route
end
