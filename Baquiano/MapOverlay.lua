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
local sinceLine = 0

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

-- Sizes are given in screen pixels: px converts them to the map canvas, which
-- is scaled when zooming, so lines keep the same width at any zoom.
local px = 1

local function ScreenScale()
    local ok, k = pcall(function() return UIParent:GetEffectiveScale() / overlay:GetEffectiveScale() end)
    return (ok and k and k > 0) and k or 1
end

-- Draw order: recorded paths ARTWORK 0, trail ARTWORK 1, route arrows
-- OVERLAY 0, destination OVERLAY 1, edit-mode points OVERLAY 2+.
local function DrawLine(w, h, x1, y1, x2, y2, thickness, r, g, b, a, sublevel)
    local line = NewLine()
    line:SetDrawLayer("ARTWORK", sublevel or 0)
    line:SetThickness(thickness * px)
    line:SetColorTexture(r, g, b, a)
    line:SetStartPoint("TOPLEFT", overlay, x1 * w, -y1 * h)
    line:SetEndPoint("TOPLEFT", overlay, x2 * w, -y2 * h)
    line:Show()
end

-- A texture that carries its own colours (trail breadcrumbs), under the
-- route's arrows.
local function DrawMark(w, h, x, y, size, texture, alpha)
    local dot = NewDot()
    dot:SetDrawLayer("ARTWORK", 2)
    dot:SetSize(size * px, size * px)
    dot:SetTexture(texture)
    dot:SetVertexColor(1, 1, 1, alpha or 1)
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", overlay, "TOPLEFT", x * w, -y * h)
    dot:Show()
end

-- A round dot (layer OVERLAY unless given).
local function DrawDot(w, h, x, y, size, r, g, b, a, sublevel, layer)
    local dot = NewDot()
    dot:SetDrawLayer(layer or "OVERLAY", sublevel or 0)
    dot:SetSize(size * px, size * px)
    dot:SetTexture(ns.PathView.DOT)
    dot:SetVertexColor(r, g, b, a)
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", overlay, "TOPLEFT", x * w, -y * h)
    dot:Show()
end

-- The active route, like Carbonite's: arrows every ARROW_GAP screen pixels
-- from the player to the destination, moving forward, and the destination
-- disc. Redrawn many times per second on its own (the arrows move and follow
-- the player), apart from the recorded paths. Only what lies in the map on
-- display.
local ARROW_SIZE, ARROW_GAP, MAX_ARROWS = 14, 16, 800
local arrows, usedArrows = {}, 0
local destMark

local function DrawRouteArrows()
    usedArrows = 0
    local route = ns.Nav.route
    local mapID = WorldMapFrame:GetMapID()
    local w, h = canvas:GetSize()
    local destShown = false

    if route and mapID and w and w > 0 then
        local s = ScreenScale()
        local P = ns.PathView
        -- Canvas units are screen pixels times s: the line is built in
        -- screen pixels so the spacing does not change with zoom.
        local function Px(x, y) return x * w / s, y * h / s end

        -- Any point of the route, of whatever zone, in this map's
        -- coordinates (this map may be another zone, a part of one, or the
        -- continent); nil if it cannot be placed or lies well off the map.
        local function Here(m, x, y)
            x, y = ns.ConvertXY(m, x, y, mapID)
            if not x or x < -0.25 or x > 1.25 or y < -0.25 or y > 1.25 then return nil end
            return x, y
        end

        -- Pieces of the route that can be placed on this map, starting at
        -- the player's position.
        local pieces, piece = {}, nil
        local pm, ppx, ppy = ns.PlayerPos()
        local line = P.RouteLine(route, ns.Nav.index)
        local hx, hy
        if pm then hx, hy = Here(pm, ppx, ppy) end
        if hx then
            local x, y = Px(hx, hy)
            piece = { { x, y } }
            pieces[1] = piece
        end
        for _, p in ipairs(line) do
            local mx, my = Here(p[3], p[1], p[2])
            if mx then
                local x, y = Px(mx, my)
                if not piece then
                    piece = {}
                    pieces[#pieces + 1] = piece
                end
                piece[#piece + 1] = { x, y, P.Kind(p) }
            else
                piece = nil
            end
        end

        local phase = P.ArrowPhase(ARROW_GAP)
        for _, pc in ipairs(pieces) do
            P.Arrows(pc, ARROW_GAP, phase, function(x, y, angle, kind)
                if usedArrows >= MAX_ARROWS then return false end
                usedArrows = usedArrows + 1
                local a = arrows[usedArrows]
                if not a then
                    a = overlay:CreateTexture(nil, "OVERLAY", nil, 0)
                    arrows[usedArrows] = a
                end
                a:SetTexture(P.ArrowTexture(kind))
                a:SetRotation(-angle)
                a:SetSize(ARROW_SIZE * s, ARROW_SIZE * s)
                a:ClearAllPoints()
                a:SetPoint("CENTER", overlay, "TOPLEFT", x * s, -y * s)
                a:Show()
            end)
        end

        local dx, dy = Here(route.destMap, route.destX, route.destY)
        if dx and dx >= 0 and dx <= 1 and dy >= 0 and dy <= 1 then
            if not destMark then
                destMark = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
                destMark:SetTexture(P.DEST)
            end
            destMark:SetSize(16 * s, 16 * s)
            destMark:ClearAllPoints()
            destMark:SetPoint("CENTER", overlay, "TOPLEFT", dx * w, -dy * h)
            destShown = true
        end
    end

    for i = usedArrows + 1, #arrows do arrows[i]:Hide() end
    if destMark then destMark:SetShown(destShown) end
end

local function Redraw()
    dirty = false
    usedLines, usedDots = 0, 0

    local mapID = WorldMapFrame:GetMapID()
    local w, h = canvas:GetSize()
    px = ScreenScale()

    if mapID and w and w > 0 then
        -- Network of known paths.
        local editing = ns.Editor.active
        -- Recorded paths: only while Shift is held, unless set to always show
        -- (but not in capital cities, see ns.ShowsPaths).
        local shift = IsShiftKeyDown()
        local showPaths = editing or shift or (BaquianoDB.pathsAlways and ns.ShowsPaths(mapID))
        local g = showPaths and Graph.Get(mapID)

        -- What has just been walked: green breadcrumbs fading behind, over the paths.
        local trail = ns.Recorder.trail[mapID]
        if trail and BaquianoDB.trail and (editing or shift or BaquianoDB.pathsAlways) then
            for k, s in ipairs(trail) do
                if usedDots >= cfg.MAX_LINES then break end
                local a = ns.Recorder.TrailAlpha(s)
                if k == 1 then DrawMark(w, h, s[1], s[2], 6, ns.PathView.TRAIL_DOT, a) end
                DrawMark(w, h, s[3], s[4], 6, ns.PathView.TRAIL_DOT, a)
            end
        end
        if g then
            local nodes, edges = g.saved.nodes, g.saved.edges
            if linesWork and editing then
                -- Every recorded link, as saved: edits act on these.
                for e = 1, #edges, 2 do
                    if usedLines >= cfg.MAX_LINES then break end
                    local a, b = edges[e], edges[e + 1]
                    local t, r, gr, bl, al = ns.PathView.Style(Graph.Inside(g, a) or Graph.Inside(g, b), 1)
                    DrawLine(w, h, nodes[a * 2 - 1], nodes[a * 2], nodes[b * 2 - 1], nodes[b * 2],
                        2 * t, r, gr, bl, al)
                end
            elseif linesWork then
                -- Bundled and simplified: one line per way, violet indoors.
                for _, s in ipairs(ns.PathView.Segments(g)) do
                    if usedLines >= cfg.MAX_LINES then break end
                    local t, r, gr, bl, al = ns.PathView.Style(s[5], s[6])
                    DrawLine(w, h, s[1], s[2], s[3], s[4], 1.25 * t, r, gr, bl, al)
                end
            else
                for i = 1, g.n do
                    if usedDots >= cfg.MAX_LINES then break end
                    local _, r, gr, bl = ns.PathView.Style(Graph.Inside(g, i), 1)
                    DrawDot(w, h, nodes[i * 2 - 1], nodes[i * 2], 3, r, gr, bl, 0.6)
                end
            end

            -- While editing, every point is visible (they can be picked or deleted)
            -- and the one the next click links from stands out.
            if editing then
                if linesWork then
                    for i = 1, g.n do
                        if usedDots >= cfg.MAX_LINES then break end
                        DrawDot(w, h, nodes[i * 2 - 1], nodes[i * 2], 4, 1, 1, 1, 0.8, 1)
                    end
                end
                local k = ns.Editor.LastNode(mapID)
                if k and k <= g.n then
                    DrawDot(w, h, nodes[k * 2 - 1], nodes[k * 2], 10, 0, 0, 0, 0.9, 3)
                    DrawDot(w, h, nodes[k * 2 - 1], nodes[k * 2], 7, 0.2, 1, 0.2, 1, 4)
                end
            end
        end

        -- The active route is drawn apart, see DrawRouteArrows.
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

-- Redraws right away (edits), instead of on the next throttled pass.
function MapOverlay.Refresh()
    if canvas then SafeRedraw() end
end

-- Yards covered by SNAP_PX screen pixels at the current zoom, so picking an
-- existing point feels the same however zoomed in the map is.
local function SnapYards(mapID)
    local yards = 25
    pcall(function()
        local px = canvas:GetWidth() * canvas:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if px > 0 then yards = cfg.SNAP_PX * ns.MapSize(mapID) / px end
    end)
    return yards
end

-- A press that moved before release was a drag of the map, not a click.
local downX, downY
local lastClickTime

local function WasDragged()
    if not downX then return false end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return math.abs(x - downX) / scale > 4 or math.abs(y - downY) / scale > 4
end

-- Returns true if the click was ours (the map should not act on it).
local function HandleClick(button, x, y)
    if button ~= "LeftButton" then return false end
    if not (IsAltKeyDown() or ns.Editor.active) then return false end
    if lastClickTime == GetTime() then return true end -- already handled this frame
    if not x or x < 0 or x > 1 or y < 0 or y > 1 or WasDragged() then return false end
    if not WorldMapFrame:IsVisible() then return false end
    lastClickTime = GetTime()
    if IsAltKeyDown() and not ns.Nav.ClickOnce() then return true end

    local mapID = WorldMapFrame:GetMapID()
    if IsAltKeyDown() and ns.Nav.IsDestination(mapID, x, y, SnapYards(mapID)) then
        -- Alt + click on the destination itself unmarks it.
        ns.Nav.Unmark()
    elseif IsAltKeyDown() then
        local route, why = ns.Nav.SetDestination(mapID, x, y)
        if route then ns.Nav.Announce(route) else ns.Print(why) end
    else
        ns.Editor.OnClick(mapID, x, y, SnapYards(mapID))
    end
    return true
end

-- Edit-mode banner across the top of the map.
local editLabel

function MapOverlay.UpdateEditLabel()
    if not WorldMapFrame then return end
    if not editLabel then
        local holder = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
        holder:SetAllPoints()
        holder:SetFrameLevel(WorldMapFrame.ScrollContainer:GetFrameLevel() + 2000)
        local bg = holder:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(0, 0, 0, 0.7)
        editLabel = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        editLabel:SetPoint("TOP", holder, "TOP", 0, -8)
        editLabel:SetText("|cff33ff99Baquiano edit mode|r   click: add point   " ..
            "Shift+click or click the last point: new line   Ctrl+click: delete point\n" ..
            "Ctrl+Shift+click: delete the whole stretch     /baq undo: undo last point     /baq edit: finish editing")
        bg:SetPoint("TOPLEFT", editLabel, "TOPLEFT", -8, 5)
        bg:SetPoint("BOTTOMRIGHT", editLabel, "BOTTOMRIGHT", 8, -5)
        editLabel.holder = holder
    end
    editLabel.holder:SetShown(ns.Editor.active)
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

    local shiftWasDown = false
    overlay:SetScript("OnUpdate", function(self, elapsed)
        sinceDraw = sinceDraw + elapsed
        sinceLine = sinceLine + elapsed
        -- Pressing or releasing Shift shows or hides the paths right away.
        local shiftDown = IsShiftKeyDown() and true or false
        if shiftDown ~= shiftWasDown then
            shiftWasDown = shiftDown
            if not BaquianoDB.pathsAlways or not ns.ShowsPaths(WorldMapFrame:GetMapID()) then
                sinceDraw = 0
                SafeRedraw()
            end
        end
        -- Zooming changes the canvas scale: redrawn soon after, so line widths
        -- stay the same on screen.
        if math.abs(ScreenScale() - px) > px * 0.05 then
            dirty = true
            if sinceDraw > 0.15 then sinceDraw = 0.5 end
        end
        if dirty and sinceDraw > 0.5 then
            sinceDraw = 0
            SafeRedraw()
        end
        -- The route's arrows move and follow the player: about 30 times a second.
        if sinceLine > 0.033 then
            sinceLine = 0
            local ok, err = pcall(DrawRouteArrows)
            if not ok and not MapOverlay.arrowsWarned then
                MapOverlay.arrowsWarned = true
                ns.Print("route drawing error: " .. tostring(err))
            end
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

    local scroll = WorldMapFrame.ScrollContainer
    scroll:HookScript("OnMouseDown", function()
        downX, downY = GetCursorPosition()
    end)

    -- The map's own click handlers let us stop the click from also zooming or
    -- changing map. If this client lacks them, a plain hook still sees the click.
    pcall(WorldMapFrame.AddCanvasClickHandler, WorldMapFrame, function(_, button, x, y)
        return HandleClick(button, x, y)
    end, 1000)
    scroll:HookScript("OnMouseUp", function(self, button)
        local source = self.GetNormalizedCursorPosition and self or WorldMapFrame
        HandleClick(button, source:GetNormalizedCursorPosition())
    end)
end
