-- Baquiano: drawing on the world map. Known paths as faint lines, the active
-- route highlighted, and Alt+left click to set a destination.
local ADDON, ns = ...

local MapOverlay = {}
ns.MapOverlay = MapOverlay

local Graph = ns.Graph
local cfg = ns.cfg

local canvas, overlay
local lines, usedLines = {}, 0
local dots, usedDots = {}, 0
local linesWork = true
local dirty = true
local sinceDraw = 0

function MapOverlay.MarkDirty()
    dirty = true
end

local function NewLine()
    usedLines = usedLines + 1
    local line = lines[usedLines]
    if not line then
        line = overlay:CreateLine(nil, "ARTWORK")
        lines[usedLines] = line
    end
    return line
end

local function NewDot()
    usedDots = usedDots + 1
    local dot = dots[usedDots]
    if not dot then
        dot = overlay:CreateTexture(nil, "OVERLAY")
        dots[usedDots] = dot
    end
    return dot
end

local function DrawLine(w, h, x1, y1, x2, y2, thickness, r, g, b, a)
    local line = NewLine()
    line:SetThickness(thickness)
    line:SetColorTexture(r, g, b, a)
    line:SetStartPoint("TOPLEFT", overlay, x1 * w, -y1 * h)
    line:SetEndPoint("TOPLEFT", overlay, x2 * w, -y2 * h)
    line:Show()
end

local function DrawDot(w, h, x, y, size, r, g, b, a, sublevel)
    local dot = NewDot()
    dot:SetDrawLayer("OVERLAY", sublevel or 0)
    dot:SetSize(size, size)
    dot:SetColorTexture(r, g, b, a)
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", overlay, "TOPLEFT", x * w, -y * h)
    dot:Show()
end

local function Redraw()
    dirty = false
    usedLines, usedDots = 0, 0

    local mapID = WorldMapFrame:GetMapID()
    local w, h = canvas:GetSize()

    if mapID and w and w > 0 then
        -- Network of known paths.
        local g = BaquianoDB.showNetwork and Graph.Get(mapID)
        if g then
            local nodes, edges = g.saved.nodes, g.saved.edges
            if linesWork then
                for e = 1, #edges, 2 do
                    if usedLines >= cfg.MAX_LINES then break end
                    local a, b = edges[e], edges[e + 1]
                    DrawLine(w, h, nodes[a * 2 - 1], nodes[a * 2], nodes[b * 2 - 1], nodes[b * 2],
                        2, 0.35, 0.8, 1, 0.45)
                end
            else
                for i = 1, g.n do
                    if usedDots >= cfg.MAX_LINES then break end
                    DrawDot(w, h, nodes[i * 2 - 1], nodes[i * 2], 3, 0.35, 0.8, 1, 0.6)
                end
            end
        end

        -- Active route, from the point being walked to up to the destination.
        local route = ns.Nav.route
        if route and route.mapID == mapID then
            local pts = route.points
            for i = ns.Nav.index, #pts do
                local p = pts[i]
                if linesWork and i < #pts then
                    local q = pts[i + 1]
                    DrawLine(w, h, p[1], p[2], q[1], q[2], 4, 1, 0.82, 0, 0.95)
                elseif not linesWork then
                    DrawDot(w, h, p[1], p[2], 5, 1, 0.82, 0, 0.95)
                end
            end
            DrawDot(w, h, route.destX, route.destY, 12, 0, 0, 0, 0.9, 1)
            DrawDot(w, h, route.destX, route.destY, 8, 1, 0.82, 0, 1, 2)
        end
    end

    for i = usedLines + 1, #lines do lines[i]:Hide() end
    for i = usedDots + 1, #dots do dots[i]:Hide() end
end

local function SafeRedraw()
    local ok, err = pcall(Redraw)
    if not ok then
        -- If lines do not work on this client, fall back to drawing dots.
        if linesWork then
            linesWork = false
            for i = 1, #lines do pcall(lines[i].Hide, lines[i]) end
            ns.Print("this client cannot draw lines; using dots instead.")
            ok, err = pcall(Redraw)
        end
        if not ok and not MapOverlay.warned then
            MapOverlay.warned = true
            ns.Print("map drawing error: " .. tostring(err))
        end
    end
end

local function OnMapClick(self, button)
    if button ~= "LeftButton" or not IsAltKeyDown() then return end
    local source = self.GetNormalizedCursorPosition and self or WorldMapFrame
    local x, y = source:GetNormalizedCursorPosition()
    if not x or x < 0 or x > 1 or y < 0 or y > 1 then return end

    local route, why = ns.Nav.SetDestination(WorldMapFrame:GetMapID(), x, y)
    if not route then
        ns.Print(why)
    elseif route.partial then
        ns.Print("partial route: recorded paths do not reach that far; the last stretch is a straight line.")
    elseif route.usedNetwork then
        ns.Print("route found along known paths.")
    else
        ns.Print("no recorded paths help here; guiding you in a straight line.")
    end
end

function MapOverlay.Init()
    if not WorldMapFrame then return end
    canvas = (WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()) or WorldMapFrame.ScrollContainer.Child

    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints(canvas)

    -- Above the unexplored-area fog, below the map icons.
    local level = 2200
    pcall(function()
        level = WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI")
    end)
    overlay:SetFrameLevel(level)

    overlay:SetScript("OnUpdate", function(self, elapsed)
        sinceDraw = sinceDraw + elapsed
        if dirty and sinceDraw > 0.5 then
            sinceDraw = 0
            SafeRedraw()
        end
    end)

    -- The map notifies its data providers when it opens or changes zone.
    local hooked = pcall(function()
        local provider = CreateFromMixins(MapCanvasDataProviderMixin)
        function provider:RefreshAllData()
            SafeRedraw()
        end
        function provider:RemoveAllData()
        end
        WorldMapFrame:AddDataProvider(provider)
    end)
    if not hooked then
        WorldMapFrame:HookScript("OnShow", MapOverlay.MarkDirty)
        pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", MapOverlay.MarkDirty)
    end

    WorldMapFrame.ScrollContainer:HookScript("OnMouseUp", OnMapClick)
end
