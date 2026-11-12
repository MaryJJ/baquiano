-- Baquiano: recorded paths prepared for display. Walks that passed through the
-- same place a few yards apart are bundled into a single line (thicker the
-- more often that way was walked), and straight stretches are drawn with few
-- lines. Display only: the saved network is not changed.
local ADDON, ns = ...

local PathView = {}
ns.PathView = PathView

local Graph = ns.Graph

local BUNDLE   = 12 -- yards: points of the same kind this close are drawn as one
local SIMPLIFY = 3  -- yards: a bend smaller than this is drawn straight
local LOOP     = 100 -- yards: a detour that comes back to the path within this
                     -- length (circling round an NPC, a knot) is not drawn
local SPUR     = 25 -- yards: a short dead end off a path is not drawn

-- Colours: outdoors blue, indoors (caves, buildings) violet.
local COLOR = {
    [false] = { 0.35, 0.8, 1 },
    [true]  = { 0.85, 0.45, 1 },
}

-- Shared look of the active route on every map (Blizzard map, minimap,
-- Carbonite), like Carbonite's own routes: a row of arrows along the way,
-- gold when walking and white when flying, slowly moving forward; the
-- destination is a gold disc. The textures carry their own colours
-- (tools/make_textures.py), so nothing needs tinting.
local TEX = "Interface\\AddOns\\Baquiano\\"
PathView.ARROW        = TEX .. "chevron_gold"
PathView.ARROW_FLIGHT = TEX .. "chevron_white"
PathView.ARROW_GAP    = TEX .. "chevron_faint" -- faint orange: a straight stretch with no recorded path
PathView.DEST         = TEX .. "dest"
PathView.DOT          = TEX .. "dot" -- white disc, tinted (edit-mode points)
PathView.ROUTE        = { 1, 0.82, 0, 1 }
PathView.ARROW_SPEED  = 12 -- pixels per second the arrows move forward

-- Arrow texture for a stretch: flown, an unrecorded gap, or walked.
function PathView.ArrowTexture(kind)
    if kind == "fly" then return PathView.ARROW_FLIGHT end
    if kind == "gap" then return PathView.ARROW_GAP end
    return PathView.ARROW
end

-- How the stretch that ends at route point p is travelled: "fly", "gap" or nil.
function PathView.Kind(p)
    return ((p.fly or p.sail) and "fly") or (p.gap and "gap") or nil
end

-- Places arrows every `spacing` pixels along a line { {x, y, kind}, ... }
-- in screen pixels with y pointing down; kind (see Kind) tells how the
-- stretch that ends at that point is travelled. The first arrow is `offset`
-- pixels from the start. Calls fn(x, y, angle, kind) for each, angle in
-- radians clockwise from up; fn may return false to stop.
function PathView.Arrows(line, spacing, offset, fn)
    local pos = offset
    for i = 1, #line - 1 do
        local a, b = line[i], line[i + 1]
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then
            local angle = math.atan2(dx, -dy)
            while pos <= len do
                if fn(a[1] + dx * pos / len, a[2] + dy * pos / len, angle, b[3]) == false then return end
                pos = pos + spacing
            end
            pos = pos - len
        end
    end
end

-- Offset for arrows that move forward over time.
function PathView.ArrowPhase(spacing)
    return (GetTime() * PathView.ARROW_SPEED) % spacing
end

local cache = setmetatable({}, { __mode = "k" }) -- g -> { version, segs }

-- Douglas-Peucker: of a line { {x, y}, ... } in map coordinates (w by h
-- yards), only the points that bend it more than tol yards are kept.
function PathView.Simplify(line, tol, w, h)
    local n = #line
    if n <= 2 then return line end
    local keep = { [1] = true, [n] = true }
    local stack = { 1, n }
    while #stack > 0 do
        local j = table.remove(stack)
        local i = table.remove(stack)
        if j > i + 1 then
            local ax, ay = line[i][1] * w, line[i][2] * h
            local dx, dy = line[j][1] * w - ax, line[j][2] * h - ay
            local len = math.sqrt(dx * dx + dy * dy)
            local far, farD = nil, -1
            for k = i + 1, j - 1 do
                local x, y = line[k][1] * w - ax, line[k][2] * h - ay
                local d = (len == 0) and math.sqrt(x * x + y * y) or math.abs(x * dy - y * dx) / len
                if d > farD then far, farD = k, d end
            end
            if farD > tol then
                keep[far] = true
                stack[#stack + 1] = i
                stack[#stack + 1] = far
                stack[#stack + 1] = far
                stack[#stack + 1] = j
            end
        end
    end
    local out = {}
    for k = 1, n do
        if keep[k] then out[#out + 1] = line[k] end
    end
    return out
end

-- Rounds the corners of a line (Chaikin, twice); the ends stay in place.
-- Extra fields of the end points (zone, flags) are kept.
function PathView.Smooth(line)
    for _ = 1, 2 do
        local n = #line
        if n < 3 then return line end
        local out = { line[1] }
        for k = 1, n - 1 do
            local a, b = line[k], line[k + 1]
            out[#out + 1] = { a[1] * 0.75 + b[1] * 0.25, a[2] * 0.75 + b[2] * 0.25 }
            out[#out + 1] = { a[1] * 0.25 + b[1] * 0.75, a[2] * 0.25 + b[2] * 0.75 }
        end
        out[#out + 1] = line[n]
        line = out
    end
    return line
end

-- The active route as it is drawn, from point index (the one being walked
-- to) to the end: { {x, y, mapID, fly = true if a flight leads to it,
-- gap = true if an unrecorded gap does}, ... }. Stretches walked within one
-- zone are simplified and smoothed; flight masters, gaps and zone changes
-- stay exact. Cached until the route or index changes.
local lineCache = {}

function PathView.RouteLine(route, index)
    if lineCache.route == route and lineCache.index == index then return lineCache.line end
    local pts, out = route.points, {}
    local run = {}
    local function Flush()
        if #run == 0 then return end
        local m = run[1][3]
        local w, h = ns.MapSize(m)
        local smooth = PathView.Smooth(PathView.Simplify(run, 2, w, h))
        for k = 1, #smooth do
            local p = smooth[k]
            out[#out + 1] = { p[1], p[2], m, fly = (p.fly or p.sail) and true or nil, gap = p.gap and true or nil }
        end
        run = {}
    end
    for i = index, #pts do
        local p = pts[i]
        -- A run ends at a zone change, a flight master, a landing or a gap
        -- (it starts a new run, so the straight stretch is kept as it is).
        if #run > 0 and (p[3] ~= run[1][3] or p.fly or p.sail or p.gap) then Flush() end
        run[#run + 1] = p
        if p.board then Flush() end
    end
    Flush()
    lineCache.route, lineCache.index, lineCache.line = route, index, out
    return out
end

-- Groups nodes into clusters of the same kind (indoor/outdoor) within BUNDLE
-- yards. Returns of[node] = cluster, and per cluster its mean position and kind.
local function Cluster(g)
    local w, h = ns.MapSize(g.mapID)
    local cw, ch = BUNDLE / w, BUNDLE / h
    local nodes = g.saved.nodes
    local grid, of = {}, {}
    local cx, cy, kind, sx, sy, cn = {}, {}, {}, {}, {}, {}

    for i = 1, g.n do
        local x, y = nodes[i * 2 - 1], nodes[i * 2]
        local inside = Graph.Inside(g, i)
        local gx, gy = math.floor(x / cw), math.floor(y / ch)
        local best, bestD
        for ix = gx - 1, gx + 1 do
            for iy = gy - 1, gy + 1 do
                local cell = grid[ix * 8192 + iy]
                if cell then
                    for k = 1, #cell do
                        local c = cell[k]
                        if kind[c] == inside then
                            local d = ns.Dist(g.mapID, x, y, cx[c], cy[c])
                            if d <= BUNDLE and (not bestD or d < bestD) then best, bestD = c, d end
                        end
                    end
                end
            end
        end
        if not best then
            best = #cx + 1
            cx[best], cy[best], kind[best] = x, y, inside
            sx[best], sy[best], cn[best] = 0, 0, 0
            local key = gx * 8192 + gy
            grid[key] = grid[key] or {}
            grid[key][#grid[key] + 1] = best
        end
        of[i] = best
        sx[best], sy[best], cn[best] = sx[best] + x, sy[best] + y, cn[best] + 1
    end

    local px, py = {}, {}
    for c = 1, #cx do px[c], py[c] = sx[c] / cn[c], sy[c] / cn[c] end
    return of, px, py, kind
end

local function PairKey(a, b)
    if a > b then a, b = b, a end
    return a * 1048576 + b
end

-- Segments to draw: { x1, y1, x2, y2, inside, weight } in map coordinates;
-- weight = how many recorded links were bundled into it (about how many times
-- that way was walked).
local function Build(g)
    local of, px, py, kind = Cluster(g)
    local w, h = ns.MapSize(g.mapID)

    -- Links between clusters, without repeats.
    local adj, weight = {}, {}
    local edges = g.saved.edges
    for e = 1, #edges, 2 do
        local a, b = of[edges[e]], of[edges[e + 1]]
        if a and b and a ~= b then
            local key = PairKey(a, b)
            if not weight[key] then
                weight[key] = 0
                adj[a] = adj[a] or {}
                adj[b] = adj[b] or {}
                adj[a][#adj[a] + 1] = b
                adj[b][#adj[b] + 1] = a
            end
            weight[key] = weight[key] + 1
        end
    end

    -- A chain of clusters is cut where paths fork or end, and where indoors
    -- meets outdoors (the entrance gets its own line).
    local function Junction(c)
        local list = adj[c]
        if #list ~= 2 then return true end
        return kind[list[1]] ~= kind[c] or kind[list[2]] ~= kind[c]
    end

    local segs = {}

    -- Simplified, then smoothed.
    local function Emit(chain, wmax)
        local inside = kind[chain[1]] or kind[chain[2]]
        local line = {}
        for k = 1, #chain do line[k] = { px[chain[k]], py[chain[k]] } end
        line = PathView.Smooth(PathView.Simplify(line, SIMPLIFY, w, h))
        for k = 2, #line do
            local a, b = line[k - 1], line[k]
            segs[#segs + 1] = { a[1], a[2], b[1], b[2], inside, wmax }
        end
    end

    local done = {}
    local chains = {}
    local function Walk(start, nxt)
        local chain, wmax = { start }, 0
        local prev, cur = start, nxt
        while true do
            local key = PairKey(prev, cur)
            if done[key] then break end
            done[key] = true
            if weight[key] > wmax then wmax = weight[key] end
            chain[#chain + 1] = cur
            if cur == start or Junction(cur) then break end
            local list = adj[cur]
            prev, cur = cur, (list[1] == prev) and list[2] or list[1]
        end
        if #chain > 1 then chains[#chains + 1] = { chain = chain, w = wmax } end
    end

    -- First the chains that start at a fork or an end, then closed loops.
    for c, list in pairs(adj) do
        if Junction(c) then
            for k = 1, #list do
                if not done[PairKey(c, list[k])] then Walk(c, list[k]) end
            end
        end
    end
    for c, list in pairs(adj) do
        for k = 1, #list do
            if not done[PairKey(c, list[k])] then Walk(c, list[k]) end
        end
    end

    -- Knots: of the chains joining the same two forks, only the shortest is
    -- drawn; the others too if they are long (a real second way). A chain that
    -- leaves a fork and comes back to it is drawn only if long. Short dead
    -- ends off a fork are not drawn either.
    local shortest = {}
    for _, ch in ipairs(chains) do
        local c, len = ch.chain, 0
        for k = 2, #c do
            local dx, dy = (px[c[k]] - px[c[k - 1]]) * w, (py[c[k]] - py[c[k - 1]]) * h
            len = len + math.sqrt(dx * dx + dy * dy)
        end
        ch.len = len
        local a, b = c[1], c[#c]
        if a ~= b then
            local key = PairKey(a, b)
            if not shortest[key] or len < shortest[key].len then shortest[key] = ch end
        end
    end
    for _, ch in ipairs(chains) do
        local c = ch.chain
        local a, b = c[1], c[#c]
        local drop
        if a == b then
            drop = ch.len < LOOP
        elseif shortest[PairKey(a, b)] ~= ch then
            drop = ch.len < LOOP
        else
            -- A dead end (one side with no other link) hanging off a fork.
            local da, db = #adj[a], #adj[b]
            drop = ch.len < SPUR and ((da == 1 and db >= 3) or (db == 1 and da >= 3))
        end
        if not drop then Emit(c, ch.w) end
    end
    return segs
end

-- Display segments of network g, rebuilt only when the network changes.
function PathView.Segments(g)
    local c = cache[g]
    if c and c.version == g.version then return c.segs end
    local segs = Build(g)
    cache[g] = { version = g.version, segs = segs }
    return segs
end

-- Line style for a segment: thickness factor (1 to 1.75) and colour.
function PathView.Style(inside, weight)
    local col = COLOR[inside and true or false]
    local grow = (weight >= 5 and 0.75) or (weight >= 2 and 0.4) or 0
    return 1 + grow, col[1], col[2], col[3], 0.5 + grow / 3
end

-- What is being recorded this session (Recorder.trail): green breadcrumbs,
-- over the paths (the texture carries its colour).
PathView.TRAIL_DOT = "Interface\\AddOns\\Baquiano\\trail"

-- Shows or hides the recorded paths on the map and the minimap.
function PathView.Toggle()
    BaquianoDB.pathsAlways = not BaquianoDB.pathsAlways
    ns.MapOverlay.Refresh()
    return BaquianoDB.pathsAlways
end
