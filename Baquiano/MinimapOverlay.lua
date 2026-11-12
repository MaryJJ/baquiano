-- Baquiano: the active route drawn on the minimap, and the recorded paths
-- around the player when they are shown (see PathView.Toggle).
local ADDON, ns = ...

local MinimapOverlay = {}
ns.MinimapOverlay = MinimapOverlay

-- Yards across the minimap at each zoom level (0 = zoomed out the most).
local SIZE = {
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
    indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
}

local frame
local lines, usedLines = {}, 0
local destDot
local sinceUpdate = 0

local function YardsAcross()
    local sizes = (IsIndoors and IsIndoors()) and SIZE.indoor or SIZE.outdoor
    return sizes[Minimap:GetZoom()] or sizes[0]
end

-- Addons that make the minimap square define GetMinimapShape.
local function IsSquare()
    return GetMinimapShape ~= nil and GetMinimapShape() == "SQUARE"
end

-- Part of the segment (x0, y0)-(x1, y1) inside the minimap: a circle of
-- radius r around the center, or a square of half-side r. nil if none.
local function Clip(x0, y0, x1, y1, r, square)
    local dx, dy = x1 - x0, y1 - y0
    local t0, t1 = 0, 1
    if square then
        local p = { -dx, dx, -dy, dy }
        local q = { x0 + r, r - x0, y0 + r, r - y0 }
        for k = 1, 4 do
            if p[k] == 0 then
                if q[k] < 0 then return nil end
            else
                local t = q[k] / p[k]
                if p[k] < 0 then
                    if t > t1 then return nil end
                    if t > t0 then t0 = t end
                else
                    if t < t0 then return nil end
                    if t < t1 then t1 = t end
                end
            end
        end
    else
        local a = dx * dx + dy * dy
        if a == 0 then return nil end
        local b = 2 * (x0 * dx + y0 * dy)
        local c = x0 * x0 + y0 * y0 - r * r
        local disc = b * b - 4 * a * c
        if disc <= 0 then return nil end
        local s = math.sqrt(disc)
        t0 = math.max(0, (-b - s) / (2 * a))
        t1 = math.min(1, (-b + s) / (2 * a))
        if t0 >= t1 then return nil end
    end
    return x0 + dx * t0, y0 + dy * t0, x0 + dx * t1, y0 + dy * t1
end

-- Route arrows, the same look as on the map (PathView): gold when walking,
-- white when flying, moving forward.
local ARROW_SIZE, ARROW_GAP, MAX_ARROWS = 8, 10, 250

local function DrawArrow(x, y, angle, kind)
    if usedLines >= MAX_ARROWS then return false end
    usedLines = usedLines + 1
    local a = lines[usedLines]
    if not a then
        a = frame:CreateTexture(nil, "OVERLAY", nil, 0)
        a:SetSize(ARROW_SIZE, ARROW_SIZE)
        lines[usedLines] = a
    end
    a:SetTexture(ns.PathView.ArrowTexture(kind))
    a:SetRotation(-angle)
    a:ClearAllPoints()
    a:SetPoint("CENTER", frame, "CENTER", x, y)
    a:Show()
end

-- Recorded paths: their own pool, drawn under the route.
local pathLines, usedPaths = {}, 0
local MAX_PATH_LINES = 600

local function DrawPath(x0, y0, x1, y1, s)
    usedPaths = usedPaths + 1
    local line = pathLines[usedPaths]
    if not line then
        line = frame:CreateLine(nil, "ARTWORK")
        pathLines[usedPaths] = line
    end
    local t, r, g, b, a = ns.PathView.Style(s[5], s[6])
    line:SetThickness(1.5 * t)
    line:SetColorTexture(r, g, b, a + 0.15)
    line:SetStartPoint("CENTER", frame, x0, y0)
    line:SetEndPoint("CENTER", frame, x1, y1)
    line:Show()
end

-- Breadcrumbs of the trail walked this session, over the paths.
local crumbs, usedCrumbs = {}, 0

local function DrawCrumb(x, y, alpha)
    usedCrumbs = usedCrumbs + 1
    local c = crumbs[usedCrumbs]
    if not c then
        c = frame:CreateTexture(nil, "ARTWORK", nil, 2)
        c:SetTexture(ns.PathView.TRAIL_DOT)
        c:SetSize(5, 5)
        crumbs[usedCrumbs] = c
    end
    c:SetVertexColor(1, 1, 1, alpha)
    c:ClearAllPoints()
    c:SetPoint("CENTER", frame, "CENTER", x, y)
    c:Show()
end

-- Distance in yards from (px, py) to the segment s of map mapID.
local function SegDist(mapID, s, px, py)
    local w, h = ns.MapSize(mapID)
    local ax, ay = (s[1] - px) * w, (s[2] - py) * h
    local dx, dy = (s[3] - s[1]) * w, (s[4] - s[2]) * h
    local len2 = dx * dx + dy * dy
    local t = 0
    if len2 > 0 then t = math.max(0, math.min(1, -(ax * dx + ay * dy) / len2)) end
    local x, y = ax + dx * t, ay + dy * t
    return math.sqrt(x * x + y * y)
end

-- Segments near the player. Filtering the whole zone is only redone after
-- walking a while, zooming, or when the paths change; not on every frame.
local near = {}
local nearMap, nearX, nearY, nearYards, nearSegs, nearTrail, nearFlags
local MOVE = 40 -- yards walked before the list is rebuilt

-- Paths and this session's trail (marked .trail) near the player.
local function NearSegments(mapID, px, py, yards)
    local g = ns.Graph.Get(mapID)
    if not g then return nil end
    local segs = ns.PathView.Segments(g)
    local trailVersion = ns.Recorder.trailVersion
    -- Paths are left out in capital cities, the trail when turned off.
    local withPaths, withTrail = ns.ShowsPaths(mapID), BaquianoDB.trail
    local flags = tostring(withPaths) .. tostring(withTrail)
    if segs ~= nearSegs or mapID ~= nearMap or yards ~= nearYards or trailVersion ~= nearTrail
        or flags ~= nearFlags or ns.Dist(mapID, nearX, nearY, px, py) > MOVE then
        nearSegs, nearMap, nearX, nearY, nearYards, nearTrail = segs, mapID, px, py, yards, trailVersion
        nearFlags = flags
        near = {}
        -- Half the diagonal of the view, plus what can be walked meanwhile.
        local reach = yards * 0.71 + MOVE
        -- The trail first, so the line cap never cuts it.
        for _, s in ipairs(withTrail and ns.Recorder.trail[mapID] or {}) do
            if SegDist(mapID, s, px, py) <= reach then
                near[#near + 1] = { s[1], s[2], s[3], s[4], trail = ns.Recorder.TrailAlpha(s) }
            end
        end
        for _, s in ipairs(withPaths and segs or {}) do
            if SegDist(mapID, s, px, py) <= reach then near[#near + 1] = s end
        end
    end
    return near
end

local function Update()
    usedLines, usedPaths, usedCrumbs = 0, 0, 0
    local route = BaquianoDB.minimap and ns.Nav.route or nil
    local showPaths = BaquianoDB.pathsAlways
    local mapID, px, py
    if route or showPaths then mapID, px, py = ns.PlayerPos() end

    local destShown = false
    if mapID then
        local w, h = ns.MapSize(mapID)
        local r = Minimap:GetWidth() / 2
        local yards = YardsAcross()
        local perYard = r / (yards / 2)
        local square = IsSquare()

        -- With a rotating minimap, the direction the player faces is up.
        local sin, cos
        if GetCVar("rotateMinimap") == "1" then
            local facing = GetPlayerFacing()
            if facing and not (issecretvalue and issecretvalue(facing)) then
                sin, cos = math.sin(facing), math.cos(facing)
            end
        end

        -- Point (x, y) of map m in pixels from the minimap center (y up).
        -- Points of a neighbouring zone are converted to the player's zone.
        local function ToPixels(m, x, y)
            x, y = ns.ConvertXY(m, x, y, mapID)
            if not x then return nil end
            local east, north = (x - px) * w, (py - y) * h
            if sin then
                east, north = east * cos + north * sin, -east * sin + north * cos
            end
            return east * perYard, north * perYard
        end

        local inner = r - 2

        -- Recorded paths around the player (only those of the player's zone).
        local segs = showPaths and NearSegments(mapID, px, py, yards)
        if segs then
            for _, s in ipairs(segs) do
                if usedPaths >= MAX_PATH_LINES then break end
                local x0, y0 = ToPixels(mapID, s[1], s[2])
                local x1, y1 = ToPixels(mapID, s[3], s[4])
                if s.trail then
                    -- A breadcrumb at each recorded point, if in view.
                    local lim = inner - 3
                    local inView = square and (math.abs(x1) <= lim and math.abs(y1) <= lim)
                        or (not square and x1 * x1 + y1 * y1 <= lim * lim)
                    if inView then DrawCrumb(x1, y1, s.trail) end
                else
                    local ax, ay, bx, by = Clip(x0, y0, x1, y1, inner, square)
                    if ax then DrawPath(ax, ay, bx, by, s) end
                end
            end
        end

        -- From the player along the rest of the route (smoothed, see PathView),
        -- in pixels with y down; arrows outside the minimap are skipped.
        if route then
            local line = { { 0, 0 } }
            for _, p in ipairs(ns.PathView.RouteLine(route, ns.Nav.index)) do
                local x, y = ToPixels(p[3], p[1], p[2])
                if x then line[#line + 1] = { x, -y, ns.PathView.Kind(p) } end
            end
            local limit = inner - ARROW_SIZE / 2
            ns.PathView.Arrows(line, ARROW_GAP, ns.PathView.ArrowPhase(ARROW_GAP),
                function(x, y, angle, kind)
                    local visible
                    if square then
                        visible = math.abs(x) <= limit and math.abs(y) <= limit
                    else
                        visible = x * x + y * y <= limit * limit
                    end
                    if visible then return DrawArrow(x, -y, angle, kind) end
                end)
        end

        -- Destination, held at the edge while it is out of view.
        local dx, dy
        if route then dx, dy = ToPixels(route.destMap, route.destX, route.destY) end
        if dx then
            local edge = r - 5
            local scale
            if square then
                scale = edge / math.max(math.abs(dx), math.abs(dy), edge)
            else
                scale = edge / math.max(math.sqrt(dx * dx + dy * dy), edge)
            end
            dx, dy = dx * scale, dy * scale
            destDot:SetPoint("CENTER", frame, "CENTER", dx, dy)
            destShown = true
        end
    end

    destDot:SetShown(destShown)
    for i = usedLines + 1, #lines do lines[i]:Hide() end
    for i = usedPaths + 1, #pathLines do pathLines[i]:Hide() end
    for i = usedCrumbs + 1, #crumbs do crumbs[i]:Hide() end
end

function MinimapOverlay.Init()
    if not Minimap then return end
    frame = CreateFrame("Frame", nil, Minimap)
    frame:SetAllPoints(Minimap)
    frame:SetFrameLevel(Minimap:GetFrameLevel() + 5)

    -- Destination: the same gold disc with a dark rim as on the map.
    local P = ns.PathView
    destDot = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    destDot:SetSize(12, 12)
    destDot:SetTexture(P.DEST)

    frame:SetScript("OnUpdate", function(self, elapsed)
        sinceUpdate = sinceUpdate + elapsed
        if sinceUpdate < 0.05 then return end
        sinceUpdate = 0
        local ok, err = pcall(Update)
        if not ok and not MinimapOverlay.warned then
            MinimapOverlay.warned = true
            ns.Print("minimap drawing error: " .. tostring(err))
        end
    end)
end

function MinimapOverlay.Toggle()
    BaquianoDB.minimap = not BaquianoDB.minimap
    return BaquianoDB.minimap
end
