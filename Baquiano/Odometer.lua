-- Baquiano: odometer. Yards walked (or ridden) this session and in total,
-- per character, in a small text that can be dragged around the screen.
local ADDON, ns = ...

local Odometer = {}
ns.Odometer = Odometer

Odometer.session = 0

local frame, sessionText, totalText
local lastMap, lastX, lastY

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function Total()
    return BaquianoDB.walked[CharKey()] or 0
end

-- Taxi rides, boats, zeppelins and flying do not count (walking as a ghost does).
local function Counts()
    if UnitOnTaxi and UnitOnTaxi("player") then return false end
    if ns.riding then return false end
    if IsFlying and IsFlying() then return false end
    return true
end

-- Units the counts can be shown in: yards per unit, decimals, label.
Odometer.UNITS = {
    yd = { 1, 0, "yd" },
    m  = { 1 / 0.9144, 0, "m" },
    km = { 1000 / 0.9144, 2, "km" },
    mi = { 1760, 2, "mi" },
}

-- Yards in the chosen unit: 1234 -> "1,234 yd", "1,128 m", "1.13 km", "0.70 mi".
local function Format(yards)
    local u = Odometer.UNITS[BaquianoDB.odometer.unit] or Odometer.UNITS.yd
    local s = string.format("%." .. u[2] .. "f", yards / u[1])
    local int, frac = s:match("^(%d+)(.*)$")
    while true do
        local n
        int, n = int:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if n == 0 then break end
    end
    return int .. frac .. " " .. u[3]
end

local function Refresh()
    if not frame or not frame:IsShown() then return end
    sessionText:SetText(Format(Odometer.session) .. " walked")
    totalText:SetText("total " .. Format(Total()))
end

-- Sets the unit (yd, m, km or mi); returns false if unknown.
function Odometer.SetUnit(unit)
    if not Odometer.UNITS[unit] then return false end
    BaquianoDB.odometer.unit = unit
    Refresh()
    return true
end

local function Tick()
    local mapID, x, y = ns.PlayerPos()
    if not mapID or not Counts() then
        lastMap = nil
        return
    end
    if lastMap then
        local d = ns.WorldDist(lastMap, lastX, lastY, mapID, x, y)
        -- A bigger jump is a teleport (hearthstone, portal, summon).
        if d and d > 0.05 and d <= ns.cfg.TELEPORT then
            Odometer.session = Odometer.session + d
            BaquianoDB.walked[CharKey()] = Total() + d
            Refresh()
        end
    end
    lastMap, lastX, lastY = mapID, x, y
end

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    BaquianoDB.odometer.pos = { point, relPoint, x, y }
end

local function RestorePosition()
    frame:ClearAllPoints()
    local pos = BaquianoDB.odometer.pos
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -60)
    end
end

function Odometer.Init()
    frame = CreateFrame("Frame", "BaquianoOdometerFrame", UIParent)
    frame:SetSize(150, 34)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    -- Right click starts the session count again.
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Odometer.Reset() end
    end)

    -- Plain text with a soft shadow: an outline looks too heavy at this size.
    sessionText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sessionText:SetPoint("TOP", frame, "TOP", 0, -2)
    sessionText:SetShadowColor(0, 0, 0, 0.8)
    sessionText:SetShadowOffset(1, -1)

    totalText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    totalText:SetPoint("TOP", sessionText, "BOTTOM", 0, -2)
    totalText:SetTextColor(0.85, 0.85, 0.85)
    totalText:SetShadowColor(0, 0, 0, 0.8)
    totalText:SetShadowOffset(1, -1)

    RestorePosition()
    frame:SetShown(BaquianoDB.odometer.shown)
    Refresh()

    C_Timer.NewTicker(0.25, Tick)
end

-- Shows or hides the odometer; returns whether it is shown now.
function Odometer.Toggle()
    BaquianoDB.odometer.shown = not BaquianoDB.odometer.shown
    frame:SetShown(BaquianoDB.odometer.shown)
    Refresh()
    return BaquianoDB.odometer.shown
end

function Odometer.Reset()
    Odometer.session = 0
    Refresh()
    ns.Print("walked count for this session reset.")
end

function Odometer.Describe()
    ns.Print(string.format("walked this session: %s; in total with this character: %s.",
        Format(Odometer.session), Format(Total())))
end
