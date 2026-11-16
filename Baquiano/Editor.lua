-- Baquiano: edit mode. Draw paths on the map by clicking, point by point.
--   click         adds a point linked to the previous one
--   click on the last point again, or Shift + click: starts a new line
--   Ctrl + click  deletes the nearest point
--   Ctrl + Shift + click  deletes the whole stretch through the nearest point,
--                 up to the junctions or ends (a zeppelin's track, say)
-- Clicking near an existing point reuses it, so new lines join the network.
local ADDON, ns = ...

local Editor = { active = false }
ns.Editor = Editor

local Graph = ns.Graph
local cfg = ns.cfg

local last = {}  -- [mapID] = node the next click links from
local undo = {}  -- [mapID] = stack of { nodeLen, edgeLen, last }
local lastEditedMap

function Editor.Toggle()
    Editor.active = not Editor.active
    -- Outside edit mode the recorder appends points, so undo would no longer be safe.
    wipe(last)
    wipe(undo)
    ns.MapOverlay.Refresh()
    ns.MapOverlay.UpdateEditLabel()
    return Editor.active
end

function Editor.LastNode(mapID)
    return last[mapID]
end

-- Continents and the world map hold no paths: routes use the zone map.
local function Editable(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    if info and info.mapType and Enum and Enum.UIMapType
        and info.mapType <= Enum.UIMapType.Continent then
        return false
    end
    return mapID ~= nil
end

-- Links a to b, filling long stretches with points every SPACING yards, so the
-- line can be joined from the middle and recorded walks merge with it.
local function Link(g, a, b)
    local ax, ay = Graph.NodeXY(g, a)
    local bx, by = Graph.NodeXY(g, b)
    local steps = math.floor(ns.Dist(g.mapID, ax, ay, bx, by) / cfg.SPACING)
    local prev = a
    for s = 1, steps - 1 do
        local t = s / steps
        local x, y = ax + (bx - ax) * t, ay + (by - ay) * t
        -- Where the line passes over an existing point, it joins it.
        local node = Graph.Nearest(g, x, y, cfg.MERGE) or Graph.AddNode(g, x, y)
        Graph.AddEdge(g, prev, node)
        prev = node
    end
    Graph.AddEdge(g, prev, b)
end

-- Nodes of the stretch through k: k and its neighbours along the line, up to
-- (not including) junctions, and including loose ends. nil if k is itself a
-- junction (which stretch would be ambiguous).
local function Stretch(g, k)
    if #g.adj[k] >= 3 then return nil end
    local set, list = { [k] = true }, { k }
    local function Walk(from, cur)
        while not set[cur] do
            local links = g.adj[cur]
            if #links >= 3 then return end -- a junction stays
            set[cur] = true
            list[#list + 1] = cur
            if #links ~= 2 then return end -- a loose end
            local nxt = (links[1] == from) and links[2] or links[1]
            from, cur = cur, nxt
        end
    end
    for _, nb in ipairs(g.adj[k]) do Walk(k, nb) end
    return list
end

-- Handles a click on the map at (x, y), 0..1 coordinates. snap is the
-- distance in yards within which an existing point is picked.
function Editor.OnClick(mapID, x, y, snap)
    if not Editable(mapID) then
        ns.Print("open the map of a zone to edit its paths.")
        return
    end
    local g = Graph.Get(mapID, true)

    if IsControlKeyDown() then
        local k = Graph.Nearest(g, x, y, snap)
        if not k then
            ns.Print("no point there to delete.")
            return
        end
        if IsShiftKeyDown() then
            local list = Stretch(g, k)
            if not list then
                ns.Print("that point is a junction: Ctrl + Shift + click a point along the stretch.")
                return
            end
            -- Highest index first: removing a point shifts the ones after it.
            table.sort(list, function(a, b) return a > b end)
            for _, i in ipairs(list) do Graph.RemoveNode(g, i) end
            ns.Print(string.format("stretch deleted (%d points).", #list))
        else
            Graph.RemoveNode(g, k)
        end
        -- Indices have shifted: the line in progress and undo no longer apply.
        last[mapID] = nil
        undo[mapID] = nil
        ns.MapOverlay.Refresh()
        return
    end

    local near = Graph.Nearest(g, x, y, snap)
    if near and near == last[mapID] then
        last[mapID] = nil
        ns.Print("line finished. The next click starts a new one.")
        ns.MapOverlay.Refresh()
        return
    end

    local nodeLen, edgeLen = Graph.Mark(g)
    local node = near or Graph.AddNode(g, x, y)
    local from = not IsShiftKeyDown() and last[mapID]
    if from then Link(g, from, node) end

    undo[mapID] = undo[mapID] or {}
    table.insert(undo[mapID], { nodeLen, edgeLen, last[mapID] })
    last[mapID] = node
    lastEditedMap = mapID
    ns.MapOverlay.Refresh()
end

-- Undoes the last click (not deletions).
function Editor.Undo()
    local mapID = lastEditedMap
    local stack = mapID and undo[mapID]
    local step = stack and table.remove(stack)
    if not step then
        ns.Print("nothing to undo.")
        return
    end
    Graph.Truncate(Graph.Get(mapID), step[1], step[2])
    last[mapID] = step[3]
    ns.MapOverlay.Refresh()
    ns.Print("last point undone.")
end
