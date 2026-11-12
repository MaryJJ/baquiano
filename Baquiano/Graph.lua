-- Baquiano: path network per zone.
-- Saved as (BaquianoDB.maps[mapID]):
--   nodes = { x1, y1, x2, y2, ... }   0..1 map coordinates
--   edges = { a1, b1, a2, b2, ... }   pairs of connected node indices
--   inside = { [i] = true, ... }      nodes recorded indoors (caves, buildings)
-- The game gives no height, so a tunnel can lie right under a path outside.
-- Indoor and outdoor nodes are never merged, joined or bridged automatically:
-- they only connect where the player actually walked in or out.
local ADDON, ns = ...

local Graph = {}
ns.Graph = Graph

local CELL = 20 -- yards per cell of the lookup grid
local graphs = {}

local function Round(v)
    return math.floor(v * 100000 + 0.5) / 100000
end

local function CellKey(g, x, y)
    return math.floor(x / g.cellW) * 8192 + math.floor(y / g.cellH)
end

local function GridInsert(g, i, x, y)
    local key = CellKey(g, x, y)
    local cell = g.grid[key]
    if not cell then
        cell = {}
        g.grid[key] = cell
    end
    cell[#cell + 1] = i
end

-- (Re)builds the in-memory lookups (adjacency, grid) from the saved arrays.
local function Build(g)
    local nodes, edges = g.saved.nodes, g.saved.edges
    g.n = math.floor(#nodes / 2)
    g.adj, g.grid = {}, {}
    g.version = g.version + 1
    for i = 1, g.n do
        g.adj[i] = {}
        GridInsert(g, i, nodes[i * 2 - 1], nodes[i * 2])
    end
    for e = 1, #edges, 2 do
        local a, b = edges[e], edges[e + 1]
        if g.adj[a] and g.adj[b] then
            g.adj[a][#g.adj[a] + 1] = b
            g.adj[b][#g.adj[b] + 1] = a
        end
    end
end

-- Returns the zone's network. With create = true it is created if missing.
function Graph.Get(mapID, create)
    local g = graphs[mapID]
    if g then return g end

    local saved = BaquianoDB.maps[mapID]
    if not saved then
        if not create then return nil end
        saved = { nodes = {}, edges = {} }
        BaquianoDB.maps[mapID] = saved
    end

    local w, h = ns.MapSize(mapID)
    g = {
        mapID = mapID,
        saved = saved,
        version = 0, -- grows with every change; invalidates cached bridges
        cellW = CELL / w,
        cellH = CELL / h,
    }
    Build(g)
    graphs[mapID] = g

    -- Paths recorded in different sessions may have been left unconnected.
    local joined = Graph.JoinPieces(g)
    if joined > 0 then
        ns.Print(string.format("joined %d gaps between recorded paths.", joined))
    end
    return g
end

function Graph.NodeXY(g, i)
    local nodes = g.saved.nodes
    return nodes[i * 2 - 1], nodes[i * 2]
end

-- true if node i was recorded indoors.
function Graph.Inside(g, i)
    local inside = g.saved.inside
    return (inside and inside[i]) == true
end

function Graph.SameKind(g, a, b)
    return Graph.Inside(g, a) == Graph.Inside(g, b)
end

function Graph.NodeDist(g, a, b)
    local ax, ay = Graph.NodeXY(g, a)
    local bx, by = Graph.NodeXY(g, b)
    return ns.Dist(g.mapID, ax, ay, bx, by)
end

-- Node nearest to (x, y). With maxYards only neighbouring cells are checked;
-- without it every node is scanned (rare: only when a route is calculated).
-- Calls fn(i, d) for every node within maxYards of (x, y), using the grid.
local function EachNear(g, x, y, maxYards, fn)
    local nodes = g.saved.nodes
    local r = math.ceil(maxYards / CELL)
    local cx, cy = math.floor(x / g.cellW), math.floor(y / g.cellH)
    for ix = cx - r, cx + r do
        for iy = cy - r, cy + r do
            local cell = g.grid[ix * 8192 + iy]
            if cell then
                for k = 1, #cell do
                    local i = cell[k]
                    local d = ns.Dist(g.mapID, x, y, nodes[i * 2 - 1], nodes[i * 2])
                    if d <= maxYards then fn(i, d) end
                end
            end
        end
    end
end

-- Optional accept(i) filters which nodes count.
function Graph.Nearest(g, x, y, maxYards, accept)
    local best, bestD
    local function Consider(i, d)
        if (not bestD or d < bestD) and (not accept or accept(i)) then
            best, bestD = i, d
        end
    end

    if maxYards then
        EachNear(g, x, y, maxYards, Consider)
    else
        local nodes = g.saved.nodes
        for i = 1, g.n do
            Consider(i, ns.Dist(g.mapID, x, y, nodes[i * 2 - 1], nodes[i * 2]))
        end
    end
    return best, bestD
end

-- Every node within maxYards of (x, y).
function Graph.Within(g, x, y, maxYards)
    local list = {}
    EachNear(g, x, y, maxYards, function(i) list[#list + 1] = i end)
    return list
end

-- Union-find over the network: Find(i) returns the id of i's connected piece.
local function Pieces(g)
    local parent = {}
    local function Find(i)
        local root = i
        while parent[root] and parent[root] ~= root do root = parent[root] end
        while i ~= root do
            local nxt = parent[i]
            parent[i] = root
            i = nxt or root
        end
        return root
    end
    local function Union(a, b)
        local ra, rb = Find(a), Find(b)
        if ra ~= rb then parent[rb] = ra end
    end
    for i = 1, g.n do
        local list = g.adj[i]
        for k = 1, #list do Union(i, list[k]) end
    end
    return Find, Union
end

-- Distance along the network from node src to every node within limit yards
-- of travel. Returns dist[node] (nodes farther away are absent).
local function NetDistances(g, src, limit)
    local dist = { [src] = 0 }
    local queue, head = { src }, 1
    while head <= #queue do
        local cur = queue[head]
        head = head + 1
        local list = g.adj[cur]
        for k = 1, #list do
            local nb = list[k]
            local d = dist[cur] + Graph.NodeDist(g, cur, nb)
            if d <= limit and (not dist[nb] or d < dist[nb]) then
                dist[nb] = d
                queue[#queue + 1] = nb
            end
        end
    end
    return dist
end

-- Straight-line crossings over unrecorded gaps, not saved: each dead end gets
-- one towards the nearest node within BRIDGE yards that the network does not
-- already reach by a short way round.
-- Returns bridges[i] = { j, ... } (both directions). Cached until the network changes.
function Graph.Bridges(g)
    if g.bridges and g.bridgesVersion == g.version then return g.bridges end
    local cfg = ns.cfg
    local bridges = {}
    local function Add(a, b)
        bridges[a] = bridges[a] or {}
        bridges[a][#bridges[a] + 1] = b
    end
    for i = 1, g.n do
        if #g.adj[i] <= 1 then
            local x, y = Graph.NodeXY(g, i)
            -- A candidate is worth it only if going round by known paths is
            -- longer than the penalized straight crossing (or impossible:
            -- another piece). This also covers a dead end that stops short of
            -- a path of its own piece, which would otherwise mean a long detour.
            local net = NetDistances(g, i, cfg.BRIDGE * cfg.BRIDGE_COST)
            local j = Graph.Nearest(g, x, y, cfg.BRIDGE, function(k)
                if not Graph.SameKind(g, i, k) then return false end -- through rock
                local around = net[k]
                return not around or around > cfg.BRIDGE_COST * Graph.NodeDist(g, i, k)
            end)
            if j then
                Add(i, j)
                Add(j, i)
            end
        end
    end
    g.bridges, g.bridgesVersion = bridges, g.version
    return bridges
end

function Graph.Linked(g, a, b)
    local list = g.adj[a]
    for k = 1, #list do
        if list[k] == b then return true end
    end
    return false
end

function Graph.CountPieces(g)
    local Find = Pieces(g)
    local seen, count = {}, 0
    for i = 1, g.n do
        local r = Find(i)
        if not seen[r] then
            seen[r] = true
            count = count + 1
        end
    end
    return count
end

-- Repairs gaps: each dead end (a node with 0 or 1 links) is linked to the
-- nearest node of a *different* piece, if one is close. Within one piece
-- nothing is added, so no shortcuts appear through walls on a connected path.
function Graph.JoinPieces(g)
    local Find, Union = Pieces(g)
    local joined = 0
    for i = 1, g.n do
        if #g.adj[i] <= 1 then
            local x, y = Graph.NodeXY(g, i)
            local ri = Find(i)
            local j = Graph.Nearest(g, x, y, ns.cfg.JOIN, function(k)
                return Find(k) ~= ri and Graph.SameKind(g, i, k)
            end)
            if j and Graph.AddEdge(g, i, j) then
                Union(i, j)
                joined = joined + 1
            end
        end
    end
    return joined
end

-- With inside = true the node is marked as recorded indoors.
function Graph.AddNode(g, x, y, inside)
    x, y = Round(x), Round(y)
    local nodes = g.saved.nodes
    nodes[#nodes + 1] = x
    nodes[#nodes + 1] = y
    g.n = g.n + 1
    if inside then
        g.saved.inside = g.saved.inside or {}
        g.saved.inside[g.n] = true
    end
    g.version = g.version + 1
    g.adj[g.n] = {}
    GridInsert(g, g.n, x, y)
    return g.n
end

-- Links two nodes. Returns true if the link is new.
function Graph.AddEdge(g, a, b)
    if a == b then return false end
    local list = g.adj[a]
    for k = 1, #list do
        if list[k] == b then return false end
    end
    list[#list + 1] = b
    g.adj[b][#g.adj[b] + 1] = a
    g.version = g.version + 1
    local edges = g.saved.edges
    edges[#edges + 1] = a
    edges[#edges + 1] = b
    return true
end

-- Size of the saved arrays, to undo later with Truncate.
function Graph.Mark(g)
    return #g.saved.nodes, #g.saved.edges
end

-- Drops everything added after Mark returned (nodeLen, edgeLen).
function Graph.Truncate(g, nodeLen, edgeLen)
    local nodes, edges = g.saved.nodes, g.saved.edges
    for i = #nodes, nodeLen + 1, -1 do nodes[i] = nil end
    for i = #edges, edgeLen + 1, -1 do edges[i] = nil end
    local inside = g.saved.inside
    if inside then
        for i in pairs(inside) do
            if i > nodeLen / 2 then inside[i] = nil end
        end
    end
    Build(g)
end

-- Deletes node k and its links. Later nodes shift down by one index.
function Graph.RemoveNode(g, k)
    local old = g.saved
    local nodes, edges, newIndex = {}, {}, {}
    for i = 1, g.n do
        if i ~= k then
            nodes[#nodes + 1] = old.nodes[i * 2 - 1]
            nodes[#nodes + 1] = old.nodes[i * 2]
            newIndex[i] = #nodes / 2
        end
    end
    for e = 1, #old.edges, 2 do
        local a, b = newIndex[old.edges[e]], newIndex[old.edges[e + 1]]
        if a and b then
            edges[#edges + 1] = a
            edges[#edges + 1] = b
        end
    end
    if old.inside then
        local inside = {}
        for i in pairs(old.inside) do
            if newIndex[i] then inside[newIndex[i]] = true end
        end
        old.inside = inside
    end
    old.nodes, old.edges = nodes, edges
    Build(g)
end

-- Deletes the nodes numbered n0+1 to n1 and the links at positions e0+1 to
-- e1 of the edge array (what an import added, see Share.lua), with every
-- link to those nodes. Later nodes shift down.
function Graph.RemoveSpan(g, n0, n1, e0, e1)
    local old = g.saved
    local nodes, edges, newIndex = {}, {}, {}
    for i = 1, g.n do
        if i <= n0 or i > n1 then
            nodes[#nodes + 1] = old.nodes[i * 2 - 1]
            nodes[#nodes + 1] = old.nodes[i * 2]
            newIndex[i] = #nodes / 2
        end
    end
    for e = 1, #old.edges, 2 do
        if e <= e0 or e > e1 then
            local a, b = newIndex[old.edges[e]], newIndex[old.edges[e + 1]]
            if a and b then
                edges[#edges + 1] = a
                edges[#edges + 1] = b
            end
        end
    end
    if old.inside then
        local inside = {}
        for i in pairs(old.inside) do
            if newIndex[i] then inside[newIndex[i]] = true end
        end
        old.inside = inside
    end
    old.nodes, old.edges = nodes, edges
    Build(g)
end

function Graph.Stats(mapID)
    local g = Graph.Get(mapID)
    if not g then return 0, 0, 0 end
    return g.n, math.floor(#g.saved.edges / 2), Graph.CountPieces(g)
end

-- Zone crossings ("portals"), saved in BaquianoDB.portals as
-- { mapA, xA, yA, mapB, xB, yB }: walking from that point of map A you reach
-- that point of map B. Stored by position, not node index, so they survive
-- deleting points; they are resolved to the nearest node when routing.
function Graph.AddPortal(mA, xA, yA, mB, xB, yB)
    xA, yA, xB, yB = Round(xA), Round(yA), Round(xB), Round(yB)
    local list = BaquianoDB.portals
    for _, p in ipairs(list) do
        -- One crossing per spot is enough, in either direction.
        local same = (p[1] == mA and p[4] == mB
                and ns.Dist(mA, p[2], p[3], xA, yA) < ns.cfg.JOIN
                and ns.Dist(mB, p[5], p[6], xB, yB) < ns.cfg.JOIN)
            or (p[1] == mB and p[4] == mA
                and ns.Dist(mB, p[2], p[3], xB, yB) < ns.cfg.JOIN
                and ns.Dist(mA, p[5], p[6], xA, yA) < ns.cfg.JOIN)
        if same then return false end
    end
    list[#list + 1] = { mA, xA, yA, mB, xB, yB }
    return true
end

function Graph.PortalCount(mapID)
    local count = 0
    for _, p in ipairs(BaquianoDB.portals) do
        if p[1] == mapID or p[4] == mapID then count = count + 1 end
    end
    return count
end

function Graph.Wipe(mapID)
    BaquianoDB.maps[mapID] = nil
    graphs[mapID] = nil
    local list = BaquianoDB.portals
    for i = #list, 1, -1 do
        if list[i][1] == mapID or list[i][4] == mapID then table.remove(list, i) end
    end
end
