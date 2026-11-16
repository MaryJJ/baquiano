-- Baquiano: recorder. Adds points and links to the network as you walk.
local ADDON, ns = ...

local Recorder = {}
ns.Recorder = Recorder

local Graph = ns.Graph
local cfg = ns.cfg

local lastMap, lastNode, lastX, lastY

local Step -- defined below Tick

-- What has just been walked, drawn as breadcrumbs that fade out behind the
-- player: trail[mapID] = { { x1, y1, x2, y2, at = yards, key = id }, ... },
-- where at is Recorder.walked when the stretch was last walked. Positions,
-- not node indices, so deleting points later does not garble it. Not saved.
Recorder.trail = {}
Recorder.trailVersion = 0 -- grows with every change of the trail
Recorder.walked = 0       -- yards of trail walked so far
local trailSeen = {}      -- [key] = trail stretch

-- Drops the stretches walked more than cfg.TRAIL yards ago.
local function PruneTrail()
    for mapID, list in pairs(Recorder.trail) do
        local kept = {}
        for _, s in ipairs(list) do
            if Recorder.walked - s.at <= cfg.TRAIL then
                kept[#kept + 1] = s
            else
                trailSeen[s.key] = nil
            end
        end
        Recorder.trail[mapID] = (#kept > 0) and kept or nil
    end
end

local function AddTrail(g, mapID, a, b)
    Recorder.walked = Recorder.walked + Graph.NodeDist(g, a, b)
    local lo, hi = math.min(a, b), math.max(a, b)
    local key = mapID .. ":" .. lo .. ":" .. hi
    local s = trailSeen[key]
    if s then
        s.at = Recorder.walked -- walked again: fresh again
    else
        local ax, ay = Graph.NodeXY(g, a)
        local bx, by = Graph.NodeXY(g, b)
        s = { ax, ay, bx, by, at = Recorder.walked, key = key }
        trailSeen[key] = s
        local list = Recorder.trail[mapID] or {}
        Recorder.trail[mapID] = list
        list[#list + 1] = s
    end
    PruneTrail()
    Recorder.trailVersion = Recorder.trailVersion + 1
    ns.MapOverlay.MarkDirty()
end

-- Opacity of a trail stretch: 1 just walked, fading to nothing cfg.TRAIL
-- yards later.
function Recorder.TrailAlpha(s)
    return math.max(0, 1 - (Recorder.walked - s.at) / cfg.TRAIL)
end

-- Forgets the trail of one zone (wipe), or all of it.
function Recorder.ClearTrail(mapID)
    if mapID then
        Recorder.trail[mapID] = nil
        for key in pairs(trailSeen) do
            if key:match("^(%d+):") == tostring(mapID) then trailSeen[key] = nil end
        end
    else
        Recorder.trail, trailSeen = {}, {}
    end
    Recorder.trailVersion = Recorder.trailVersion + 1
    ns.MapOverlay.MarkDirty()
end

local function Reset()
    lastMap, lastNode, lastX, lastY = nil, nil, nil, nil
end

-- Nothing is recorded while flying, on a taxi or dead: that ground is not walkable.
local function CanRecord()
    if UnitOnTaxi and UnitOnTaxi("player") then return false end
    -- As a ghost the ground is the same, so it is recorded too (the jump back
    -- to the corpse or the spirit healer breaks the line like any teleport).
    if IsFlying and IsFlying() then return false end
    if ns.riding then return false end -- on a boat or zeppelin
    return true
end

local function Tick()
    -- Paused while editing: edits and undo rely on nothing else adding points.
    if not BaquianoDB.recording or ns.Editor.active or not CanRecord() then
        Reset()
        return
    end

    local mapID, x, y = ns.PlayerPos()
    if not mapID then
        Reset()
        return
    end

    -- Walking into another zone: remember where we left the old one, to save
    -- the crossing once the first point in the new zone is known. A hearthstone
    -- or portal also changes zone, but it is a jump in world position.
    local crossFrom
    if mapID ~= lastMap then
        if lastMap and lastNode then
            local d = ns.WorldDist(lastMap, lastX, lastY, mapID, x, y)
            if d and d <= cfg.TELEPORT then
                local nx, ny = Graph.NodeXY(Graph.Get(lastMap), lastNode)
                crossFrom = { lastMap, nx, ny }
            end
        end
        Reset()
        lastMap = mapID
    elseif lastX and ns.Dist(mapID, lastX, lastY, x, y) > cfg.TELEPORT then
        lastNode = nil
    end
    lastX, lastY = x, y

    local g = Graph.Get(mapID, true)
    Step(g, mapID, x, y)

    if crossFrom and lastNode then
        local nx, ny = Graph.NodeXY(g, lastNode)
        if Graph.AddPortal(crossFrom[1], crossFrom[2], crossFrom[3], mapID, nx, ny) then
            ns.Print("learned a crossing between zones.")
        end
    end
end

-- Adds the position (x, y) to the network: reuses a nearby point or adds a new
-- one, linked to the previous. Leaves lastNode on the player's point, if any.
Step = function(g, mapID, x, y)
    -- Indoors (cave, building) and outdoors are kept apart: a tunnel under a
    -- path outside must not merge with it. See Graph.lua.
    local inside = (IsIndoors and IsIndoors()) and true or false
    local function SameKind(k) return Graph.Inside(g, k) == inside end

    -- If a point already exists nearby, it is reused instead of adding another.
    local near = Graph.Nearest(g, x, y, cfg.MERGE, SameKind)
    if near then
        if near ~= lastNode then
            if lastNode and Graph.NodeDist(g, lastNode, near) <= cfg.MAX_EDGE then
                if Graph.AddEdge(g, lastNode, near) then
                    ns.MapOverlay.MarkDirty()
                end
                AddTrail(g, mapID, lastNode, near)
            end
            lastNode = near
        end
        return
    end

    if lastNode then
        local nx, ny = Graph.NodeXY(g, lastNode)
        local d = ns.Dist(mapID, x, y, nx, ny)
        if d < cfg.SPACING then return end
        if d > cfg.MAX_EDGE then lastNode = nil end
    end

    local node = Graph.AddNode(g, x, y, inside)
    if lastNode then
        -- Walking in or out links the last point outside with the first inside:
        -- that link is the entrance.
        Graph.AddEdge(g, lastNode, node)
        AddTrail(g, mapID, lastNode, node)
    else
        -- Start of a new stretch (login, teleport...): link it to the network
        -- if it is close, so it does not stay as a loose piece.
        local j = Graph.Nearest(g, x, y, cfg.JOIN, function(k)
            return k ~= node and SameKind(k)
        end)
        if j then Graph.AddEdge(g, node, j) end
    end
    lastNode = node
    ns.MapOverlay.MarkDirty()
end

function Recorder.Init()
    C_Timer.NewTicker(0.2, function()
        local ok, err = pcall(Tick)
        if not ok and not Recorder.warned then
            Recorder.warned = true
            ns.Print("recording error: " .. tostring(err))
        end
    end)
end

-- Starts the line afresh (after points were taken out by an undone import).
function Recorder.Restart()
    Reset()
    Recorder.ClearTrail()
end

function Recorder.Toggle()
    BaquianoDB.recording = not BaquianoDB.recording
    Reset()
    if not BaquianoDB.recording then Recorder.ClearTrail() end
    return BaquianoDB.recording
end
