-- Baquiano: recorder. Adds points and links to the network as you walk.
local ADDON, ns = ...

local Recorder = {}
ns.Recorder = Recorder

local Graph = ns.Graph
local cfg = ns.cfg

local lastMap, lastNode, lastX, lastY

local function Reset()
    lastMap, lastNode, lastX, lastY = nil, nil, nil, nil
end

-- Nothing is recorded while flying, on a taxi or dead: that ground is not walkable.
local function CanRecord()
    if UnitOnTaxi and UnitOnTaxi("player") then return false end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
    if IsFlying and IsFlying() then return false end
    return true
end

local function Tick()
    if not BaquianoDB.recording or not CanRecord() then
        Reset()
        return
    end

    local mapID, x, y = ns.PlayerPos()
    if not mapID then
        Reset()
        return
    end

    if mapID ~= lastMap then
        Reset()
        lastMap = mapID
    elseif lastX and ns.Dist(mapID, lastX, lastY, x, y) > cfg.TELEPORT then
        lastNode = nil
    end
    lastX, lastY = x, y

    local g = Graph.Get(mapID, true)

    -- If a point already exists nearby, it is reused instead of adding another.
    local near = Graph.Nearest(g, x, y, cfg.MERGE)
    if near then
        if near ~= lastNode then
            if lastNode and Graph.NodeDist(g, lastNode, near) <= cfg.MAX_EDGE then
                if Graph.AddEdge(g, lastNode, near) then
                    ns.MapOverlay.MarkDirty()
                end
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

    local node = Graph.AddNode(g, x, y)
    if lastNode then
        Graph.AddEdge(g, lastNode, node)
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

function Recorder.Toggle()
    BaquianoDB.recording = not BaquianoDB.recording
    Reset()
    return BaquianoDB.recording
end
