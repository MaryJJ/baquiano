-- Baquiano: waypoints set elsewhere become Baquiano's destination too. Other
-- addons (SkillUp Forever, quest helpers...) set them through TomTom, or
-- through Carbonite's stand-in for TomTom; or set the game's own map pin.
-- When that waypoint is removed, the route goes too.
local ADDON, ns = ...

local Waypoints = {}
ns.Waypoints = Waypoints

local ready = false -- not at login: a pin left from before is not a new request

-- The waypoint the current route follows: { kind = "pin" | "tomtom", m, x, y }.
local following

-- Whether the route still goes to the followed waypoint (and not to a
-- destination set since, by a click on the map for instance).
local function StillFollowing(kind)
    return following and following.kind == kind and ns.Nav.route
        and ns.Nav.IsDestination(following[1], following[2], following[3], 5)
end

local function Follow(kind, mapID, x, y, title)
    if not ready or not BaquianoDB.followWaypoints or ns.Editor.active then return end
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return end
    if x < 0 or x > 1 or y < 0 or y > 1 then return end
    -- The same point twice (one addon may set it both ways): once is enough.
    if ns.Nav.IsDestination(mapID, x, y, 5) then return end
    local route, why = ns.Nav.SetDestination(mapID, x, y)
    if route then
        following = { kind = kind, mapID, x, y }
        if title and title ~= "" then ns.Print("following the waypoint to " .. title .. ".") end
        ns.Nav.Announce(route)
    else
        ns.Print(why)
    end
end

local function Unfollow(kind, mapID, x, y)
    if not BaquianoDB.followWaypoints or not StillFollowing(kind) then return end
    -- A known point that is not the followed one: some other waypoint went.
    if mapID and x and y then
        local d = ns.WorldDist(mapID, x, y, following[1], following[2], following[3])
        if d and d > 5 then return end
    end
    following = nil
    ns.Nav.Unmark()
end

-- Run after the caller is done: the route search must not slow it down, an
-- error here must not reach it, and adds and removes keep their order.
local function Later(fn, ...)
    local args = { n = select("#", ...), ... }
    C_Timer.After(0, function()
        local ok, err = pcall(fn, unpack(args, 1, args.n))
        if not ok then ns.Print("waypoint error: " .. tostring(err)) end
    end)
end

local function HookTomTom()
    local function Hook(t)
        hooksecurefunc(t, "AddWaypoint", function(_, m, x, y, opts)
            Later(Follow, "tomtom", m, x, y, type(opts) == "table" and opts.title or nil)
        end)
        -- TomTom's waypoint ids are { mapID, x, y, ... }; other shapes say
        -- nothing of where it was.
        if type(t.RemoveWaypoint) == "function" then
            hooksecurefunc(t, "RemoveWaypoint", function(_, uid)
                if type(uid) == "table" and type(uid[1]) == "number" then
                    Later(Unfollow, "tomtom", uid[1], uid[2], uid[3])
                else
                    Later(Unfollow, "tomtom")
                end
            end)
        end
        if type(t.ClearAllWaypoints) == "function" then
            hooksecurefunc(t, "ClearAllWaypoints", function() Later(Unfollow, "tomtom") end)
        end
    end
    -- Carbonite's stand-in for TomTom: the global TomTom table it builds
    -- (maybe after login) forwards every call to this one, which stays.
    local Carbonite = _G.Carbonite
    local emu = Carbonite and Carbonite.Modules and Carbonite.Modules.Integrations
        and Carbonite.Modules.Integrations.TomTom
    if emu and emu.AddWaypoint then Hook(emu) end
    -- The real TomTom, if installed. (If it is the stand-in's table, the
    -- point arrives twice and Follow takes it once.)
    if _G.TomTom and _G.TomTom ~= emu and type(_G.TomTom.AddWaypoint) == "function" then
        Hook(_G.TomTom)
    end
end

-- The game's map pin was set, moved or removed. Protected: an error must
-- never reach whoever set the pin.
local function OnUserWaypoint()
    pcall(function()
        local point = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
        local pos = point and point.position
        if not pos then
            Later(Unfollow, "pin")
            return
        end
        -- On this client the position is a plain { x, y } table, not a vector.
        local x, y = pos.x, pos.y
        if (not x or not y) and type(pos.GetXY) == "function" then x, y = pos:GetXY() end
        Later(Follow, "pin", point.uiMapID, x, y)
    end)
end

function Waypoints.Init()
    local ok, err = pcall(HookTomTom)
    if not ok then ns.Print("could not follow TomTom waypoints: " .. tostring(err)) end

    local f = CreateFrame("Frame")
    if ns.SafeRegisterEvent(f, "USER_WAYPOINT_UPDATED") then
        f:SetScript("OnEvent", OnUserWaypoint)
    end
    C_Timer.After(5, function() ready = true end)
end

-- Turns following on or off; returns whether it is on now.
function Waypoints.Toggle()
    BaquianoDB.followWaypoints = not BaquianoDB.followWaypoints
    return BaquianoDB.followWaypoints
end
