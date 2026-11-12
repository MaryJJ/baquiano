-- Baquiano: on-screen guide arrow. Points at the next route point.
local ADDON, ns = ...

local Arrow = {}
ns.Arrow = Arrow

local frame, tex, distText, stepText
local sinceUpdate = 0

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    BaquianoDB.arrow.pos = { point, relPoint, x, y }
end

local function RestorePosition()
    frame:ClearAllPoints()
    local pos = BaquianoDB.arrow.pos
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

local function Update()
    if not ns.Nav.route then
        frame:Hide()
        return
    end

    local mapID, x, y = ns.PlayerPos()
    if not mapID then
        tex:Hide()
        distText:SetText("no position")
        stepText:SetText("")
        return
    end

    local tx, ty, dist, isFinal = ns.Nav.Update(mapID, x, y)
    if not ns.Nav.route then
        frame:Hide()
        return
    end
    if not tx then
        tex:Hide()
        distText:SetText("other zone")
        stepText:SetText("")
        return
    end

    distText:SetText(string.format("%d yd", dist))
    if isFinal then
        stepText:SetText("destination")
    else
        stepText:SetText(string.format("point %d of %d", ns.Nav.index, #ns.Nav.route.points))
    end

    local facing = GetPlayerFacing()
    if not facing or (issecretvalue and issecretvalue(facing)) then
        tex:Hide()
        return
    end

    -- Bearing to the point, in radians counterclockwise from north, the same
    -- convention as GetPlayerFacing. On the map, x grows east and y grows south.
    local w, h = ns.MapSize(mapID)
    local bearing = math.atan2(-(tx - x) * w, -(ty - y) * h)
    local turn = bearing - facing
    tex:SetRotation(turn)

    -- Green when heading the right way, yellow when drifting, red when going backwards.
    local off = math.abs(math.atan2(math.sin(turn), math.cos(turn)))
    if off < 0.45 then
        tex:SetVertexColor(0.2, 1, 0.2)
    elseif off < 1.6 then
        tex:SetVertexColor(1, 0.82, 0)
    else
        tex:SetVertexColor(1, 0.25, 0.25)
    end
    tex:Show()
end

function Arrow.Init()
    frame = CreateFrame("Frame", "BaquianoArrowFrame", UIParent)
    frame:SetSize(120, 92)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetSize(56, 56)
    tex:SetPoint("TOP", frame, "TOP", 0, 0)
    tex:SetTexture("Interface\\AddOns\\Baquiano\\arrow")

    distText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    distText:SetPoint("TOP", tex, "BOTTOM", 0, -2)

    stepText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stepText:SetPoint("TOP", distText, "BOTTOM", 0, -2)

    RestorePosition()
    frame:Hide()

    -- The driver lives in a separate frame: a hidden one gets no OnUpdate.
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(self, elapsed)
        sinceUpdate = sinceUpdate + elapsed
        if sinceUpdate < 0.05 then return end
        sinceUpdate = 0
        -- Navigation keeps advancing even when the arrow is hidden.
        if ns.Nav.route then
            frame:SetShown(BaquianoDB.arrow.shown)
            local ok, err = pcall(Update)
            if not ok and not Arrow.warned then
                Arrow.warned = true
                ns.Print("arrow error: " .. tostring(err))
            end
        elseif frame:IsShown() then
            frame:Hide()
        end
    end)
end

function Arrow.Toggle()
    BaquianoDB.arrow.shown = not BaquianoDB.arrow.shown
    return BaquianoDB.arrow.shown
end

function Arrow.ResetPosition()
    BaquianoDB.arrow.pos = nil
    RestorePosition()
end
