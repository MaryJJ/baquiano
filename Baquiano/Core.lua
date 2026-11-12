-- Baquiano: core. Settings, player position and map geometry.
local ADDON, ns = ...

-- All distances are in game yards.
ns.cfg = {
    SPACING      = 10,  -- spacing between recorded points
    MERGE        = 6,   -- closer than this, an existing point is reused
    MAX_EDGE     = 30,  -- a link longer than this is dropped (jump, teleport)
    TELEPORT     = 60,  -- jump between two readings that breaks the recording
    ARRIVE       = 8,   -- radius that counts as reaching an intermediate point
    ARRIVE_FINAL = 5,   -- radius that counts as reaching the destination
    OFFROUTE     = 45,  -- farther from the route than this, it is recalculated
    MAX_LINES    = 4000 -- cap on lines drawn on the map
}

function ns.Print(msg)
    print("|cff33ff99Baquiano|r: " .. tostring(msg))
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- Returns mapID, x, y (0..1 zone map coordinates), or nil when the game
-- does not give the position (dungeons, loading screens).
function ns.PlayerPos()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or IsSecret(mapID) then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if IsSecret(x) or IsSecret(y) then return nil end
    if not x or not y or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end

-- Map size in yards. If the client does not provide it, an approximate value
-- is used: guidance still works but distances are only indicative.
local sizeCache = {}
ns.approxSize = false

function ns.MapSize(mapID)
    local c = sizeCache[mapID]
    if c then return c[1], c[2] end

    local w, h
    pcall(function()
        local _, tl = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local _, mid = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
        if tl and mid then
            local top, left = tl:GetXY()
            local midY, midX = mid:GetXY()
            w = math.abs(left - midX) * 2
            h = math.abs(top - midY) * 2
        end
    end)

    if not (w and h and w > 0 and h > 0) then
        w, h = 1000, 667
        ns.approxSize = true
    end
    sizeCache[mapID] = { w, h }
    return w, h
end

function ns.Dist(mapID, x1, y1, x2, y2)
    local w, h = ns.MapSize(mapID)
    local dx, dy = (x1 - x2) * w, (y1 - y2) * h
    return math.sqrt(dx * dx + dy * dy)
end

-- On this client, registering an event that does not exist throws and aborts
-- the file, so every registration is protected.
function ns.SafeRegisterEvent(frame, event)
    return pcall(frame.RegisterEvent, frame, event)
end

local defaults = {
    version = 1,
    recording = true,
    showNetwork = true,
    arrow = { shown = true },
    maps = {},
}

local loader = CreateFrame("Frame")
ns.SafeRegisterEvent(loader, "ADDON_LOADED")
ns.SafeRegisterEvent(loader, "PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        if type(BaquianoDB) ~= "table" then BaquianoDB = {} end
        for k, v in pairs(defaults) do
            if BaquianoDB[k] == nil then
                BaquianoDB[k] = (type(v) == "table") and CopyTable(v) or v
            end
        end
    elseif event == "PLAYER_LOGIN" then
        for _, name in ipairs({ "Recorder", "MapOverlay", "Arrow" }) do
            local mod = ns[name]
            if mod and mod.Init then
                local ok, err = pcall(mod.Init)
                if not ok then
                    ns.Print("could not start " .. name .. ": " .. tostring(err))
                end
            end
        end
        ns.Print("loaded. Type /baq to see the commands.")
    end
end)
