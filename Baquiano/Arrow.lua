-- Baquiano: on-screen guide arrow. Points at the next route point; below it,
-- what is left to the destination and roughly how long it takes.
local ADDON, ns = ...

local Arrow = {}
ns.Arrow = Arrow

local frame, tex, distText, stepText
local sinceUpdate = 0
local shownTurn -- angle on screen now; eased towards the real one

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

local Yards = ns.Yards

-- Seconds -> "~3 min" (under a minute: "<1 min").
local function Time(sec)
    if sec < 60 then return "<1 min" end
    return string.format("~%d min", math.floor(sec / 60 + 0.5))
end

-- Green when heading the right way, through yellow, to red when going
-- backwards; off is the angle away from the right way, 0 to pi.
local function Colour(off)
    local t = math.min(1, off / math.pi)
    if t < 0.5 then
        local k = t / 0.5
        return 0.2 + 0.8 * k, 1 - 0.18 * k, 0.2 - 0.2 * k
    end
    local k = (t - 0.5) / 0.5
    return 1, 0.82 - 0.57 * k, 0.25 * k
end

-- Name of the flight master the route flies to from point i, if any.
-- Where the flight, boat, zeppelin or tram taken at (or landing at) point i
-- goes: its name, and for all but a flight what it is ("boat", "tram"...).
local function FlightAt(i)
    local pts = ns.Nav.route.points
    local nextPoint = pts[i + 1]
    if pts[i].board and nextPoint then
        if nextPoint.fly then return ns.Flights.Name(nextPoint.fly) end
        if nextPoint.sail then return nextPoint.sail, nextPoint.ride or "boat or zeppelin" end
    end
    if pts[i].fly then return ns.Flights.Name(pts[i].fly) end
    if pts[i].sail then return pts[i].sail, pts[i].ride or "boat or zeppelin" end
end

local function Update(elapsed)
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

    -- On a flight Nav guides nothing: just say where it lands.
    if UnitOnTaxi and UnitOnTaxi("player") then
        tex:Hide()
        distText:SetText("flying")
        stepText:SetText("to " .. (FlightAt(ns.Nav.index) or "?"))
        return
    end
    -- On a boat or zeppelin of the route, likewise.
    local p = ns.Nav.route.points[ns.Nav.index]
    if not tx and ns.riding and p and p.sail then
        tex:Hide()
        distText:SetText("on board")
        stepText:SetText("to " .. p.sail)
        return
    end
    if not tx then
        tex:Hide()
        distText:SetText("off the route")
        stepText:SetText("looking for a way back")
        return
    end

    -- What is left to the destination, and how long at the current speed.
    -- With a flight ahead, what is left to its flight master instead: that
    -- is the walk to do now.
    local walk, fly, toBoard, boardAt = ns.Nav.Remaining(mapID, x, y)
    local flight, boat
    if boardAt then flight, boat = FlightAt(boardAt) end
    if flight then
        distText:SetText(Yards(toBoard))
        local radius = boat and ns.cfg.BOAT_ARRIVE or ns.cfg.FLY_ARRIVE
        if boardAt == ns.Nav.index and dist <= radius then
            stepText:SetText("take the " .. (boat or "flight") .. " to " .. flight)
        elseif boat == "tram" then
            stepText:SetText(Time(toBoard / ns.Flights.RunSpeed()) .. " to the tram, then ride to " .. flight)
        elseif boat then
            stepText:SetText(Time(toBoard / ns.Flights.RunSpeed()) .. " to the dock, then sail to " .. flight)
        else
            stepText:SetText(Time(toBoard / ns.Flights.RunSpeed()) .. " to the flight master, then fly to " .. flight)
        end
    else
        distText:SetText(Yards(walk + fly))
        if isFinal and dist < 40 then
            stepText:SetText("almost there")
        else
            stepText:SetText(Time(walk / ns.Flights.RunSpeed() + fly / ns.cfg.FLY_SPEED))
        end
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

    -- Eased towards the real angle (the short way round), so it does not jitter.
    if not shownTurn then shownTurn = turn end
    local diff = math.atan2(math.sin(turn - shownTurn), math.cos(turn - shownTurn))
    shownTurn = shownTurn + diff * math.min(1, elapsed * 12)
    tex:SetRotation(shownTurn)

    local off = math.abs(math.atan2(math.sin(turn), math.cos(turn)))
    tex:SetVertexColor(Colour(off))
    tex:Show()
end

function Arrow.Init()
    frame = CreateFrame("Frame", "BaquianoArrowFrame", UIParent)
    frame:SetSize(120, 84)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    -- Right click on the arrow unmarks the destination.
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ns.Nav.Unmark() end
    end)

    tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetSize(44, 44)
    tex:SetPoint("TOP", frame, "TOP", 0, 0)
    tex:SetTexture("Interface\\AddOns\\Baquiano\\arrow")

    -- Outlined text, readable over any background.
    distText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    distText:SetPoint("TOP", tex, "BOTTOM", 0, 0)
    local font, size = distText:GetFont()
    distText:SetFont(font, size, "OUTLINE")

    stepText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stepText:SetPoint("TOP", distText, "BOTTOM", 0, -2)
    font, size = stepText:GetFont()
    stepText:SetFont(font, size - 1, "OUTLINE")

    RestorePosition()
    frame:Hide()

    -- The driver lives in a separate frame: a hidden one gets no OnUpdate.
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(self, elapsed)
        sinceUpdate = sinceUpdate + elapsed
        if sinceUpdate < 0.02 then return end
        local step = sinceUpdate
        sinceUpdate = 0
        -- Navigation keeps advancing even when the arrow is hidden.
        if ns.Nav.route then
            frame:SetShown(BaquianoDB.arrow.shown)
            local ok, err = pcall(Update, step)
            if not ok and not Arrow.warned then
                Arrow.warned = true
                ns.Print("arrow error: " .. tostring(err))
            end
        else
            shownTurn = nil
            if frame:IsShown() then frame:Hide() end
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
