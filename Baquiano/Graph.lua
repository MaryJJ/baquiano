-- Baquiano: path network per zone.
-- Saved as (BaquianoDB.maps[mapID]):
--   nodes = { x1, y1, x2, y2, ... }   0..1 map coordinates
--   edges = { a1, b1, a2, b2, ... }   pairs of connected node indices
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
        n = math.floor(#saved.nodes / 2),
        adj = {},
        grid = {},
        cellW = CELL / w,
        cellH = CELL / h,
    }

    local nodes, edges = saved.nodes, saved.edges
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

    graphs[mapID] = g
    return g
end

function Graph.NodeXY(g, i)
    local nodes = g.saved.nodes
    return nodes[i * 2 - 1], nodes[i * 2]
end

function Graph.NodeDist(g, a, b)
    local ax, ay = Graph.NodeXY(g, a)
    local bx, by = Graph.NodeXY(g, b)
    return ns.Dist(g.mapID, ax, ay, bx, by)
end

-- Node nearest to (x, y). With maxYards only neighbouring cells are checked;
-- without it every node is scanned (rare: only when a route is calculated).
function Graph.Nearest(g, x, y, maxYards)
    local best, bestD
    local nodes = g.saved.nodes

    if maxYards then
        local r = math.ceil(maxYards / CELL)
        local cx, cy = math.floor(x / g.cellW), math.floor(y / g.cellH)
        for ix = cx - r, cx + r do
            for iy = cy - r, cy + r do
                local cell = g.grid[ix * 8192 + iy]
                if cell then
                    for k = 1, #cell do
                        local i = cell[k]
                        local d = ns.Dist(g.mapID, x, y, nodes[i * 2 - 1], nodes[i * 2])
                        if d <= maxYards and (not bestD or d < bestD) then
                            best, bestD = i, d
                        end
                    end
                end
            end
        end
    else
        for i = 1, g.n do
            local d = ns.Dist(g.mapID, x, y, nodes[i * 2 - 1], nodes[i * 2])
            if not bestD or d < bestD then
                best, bestD = i, d
            end
        end
    end
    return best, bestD
end

function Graph.AddNode(g, x, y)
    x, y = Round(x), Round(y)
    local nodes = g.saved.nodes
    nodes[#nodes + 1] = x
    nodes[#nodes + 1] = y
    g.n = g.n + 1
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
    local edges = g.saved.edges
    edges[#edges + 1] = a
    edges[#edges + 1] = b
    return true
end

function Graph.Stats(mapID)
    local g = Graph.Get(mapID)
    if not g then return 0, 0 end
    return g.n, math.floor(#g.saved.edges / 2)
end

function Graph.Wipe(mapID)
    BaquianoDB.maps[mapID] = nil
    graphs[mapID] = nil
end
