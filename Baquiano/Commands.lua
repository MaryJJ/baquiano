-- Baquiano: /baquiano and /baq commands.
local ADDON, ns = ...

local function Help()
    ns.Print("commands (most are also in Options > AddOns > Baquiano, or /baq options):")
    print("  /baq record - turn path recording on or off")
    print("  /baq go X Y - set a destination in your zone (coordinates 0 to 100)")
    print("  /baq go Orgrimmar - set a destination in a town with a flight master, by name")
    print("  /baq route - list the active route step by step")
    print("  /baq stop - clear the active route (also Alt + click on the destination, or right click on the arrow)")
    print("  /baq arrow - show or hide the arrow")
    print("  /baq arrow reset - put the arrow back in its starting position")
    print("  /baq minimap - show or hide the route on the minimap")
    print("  /baq carbonite - show or hide the route on Carbonite's map")
    print("  /baq flights - use known flights in routes, or not")
    print("  /baq paths - show or hide recorded paths on the map and minimap (also a key: Key Bindings > AddOns)")
    print("  /baq trail - show or hide the trail of what you just walked (green breadcrumbs)")
    print("  /baq cities - show or hide recorded paths in capital cities")
    print("  /baq walked - show or hide the yards walked (session and total); /baq walked reset starts the session count again")
    print("  /baq walked units yd|m|km|mi - unit for the distance walked")
    print("  /baq boats - use boats and zeppelins in routes, or not; /baq boats list; /baq boats forget [N] (times measured)")
    print("  /baq avoid - routes keep away from the other faction's towns, or not")
    print("  /baq follow - follow waypoints set by other addons (TomTom, Carbonite) or on the map, or not")
    if BaquianoDB.devTools then
        print("  /baq edit - edit mode: draw paths by clicking on the map")
        print("  /baq undo - undo the last point drawn in edit mode")
    end
    print("  /baq export - your zone's paths as a text to share; /baq export all, every zone")
    print("  /baq import [name] - add paths another player shared; /baq import list; /baq import undo")
    print("  /baq info - how much is recorded in your zone")
    print("  /baq wipe - delete the recorded paths of your zone")
    print("  On the map: Alt + left click sets a destination; hold Shift to see your recorded paths.")
    print("  On Carbonite's map: Alt + left click sets a destination too.")
end

StaticPopupDialogs["BAQUIANO_WIPE_ZONE"] = {
    text = "Delete all recorded paths in %s? This cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, mapID)
        -- The active route may run through this zone.
        if ns.Nav.route then ns.Nav.Clear() end
        ns.Graph.Wipe(mapID)
        ns.Recorder.ClearTrail(mapID)
        ns.MapOverlay.MarkDirty()
        ns.Print("zone paths deleted.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function ZoneName(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return (info and info.name) or ("zone " .. tostring(mapID))
end

local NO_POSITION = "the game does not give your position here."

local function Handle(msg)
    local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")

    if cmd == "options" or cmd == "config" then
        if not ns.Options.Open() then ns.Print("this client has no options panel: use the commands.") end

    elseif cmd == "record" then
        if ns.Recorder.Toggle() then
            ns.Print("recording on.")
        else
            ns.Print("recording paused.")
        end

    elseif cmd == "go" then
        local sx, sy = rest:gsub(",", "."):match("^(%d+%.?%d*)%s+(%d+%.?%d*)$")
        local x, y = tonumber(sx), tonumber(sy)
        if not x and rest ~= "" then
            -- A place by name: its flight master. (The original text, not
            -- lowered, so accented letters stay whole.)
            local text = (msg:match("^%s*%S+%s+(.-)%s*$") or ""):gsub("^[Tt][Oo]%s+", "")
            local id = ns.Flights.Search(text)
            local m, fx, fy
            if id then m, fx, fy = ns.Flights.Zone(id) end
            if not m then
                ns.Print("no town called \"" .. text .. "\" is known (only towns with a flight master).")
                return
            end
            ns.Print("going to " .. ns.Flights.Name(id) .. " (its flight master).")
            local route, why = ns.Nav.SetDestination(m, fx, fy)
            if route then ns.Nav.Announce(route) else ns.Print(why) end
            return
        end
        if not x or not y or x > 100 or y > 100 then
            ns.Print("usage: /baq go 45.2 63.1, or /baq go Orgrimmar")
            return
        end
        local mapID = ns.PlayerPos()
        if not mapID then
            ns.Print(NO_POSITION)
            return
        end
        local route, why = ns.Nav.SetDestination(mapID, x / 100, y / 100)
        if route then ns.Nav.Announce(route) else ns.Print(why) end

    elseif cmd == "dev" then
        -- Not listed anywhere: unlocks edit mode on this account.
        BaquianoDB.devTools = not BaquianoDB.devTools or nil
        if not BaquianoDB.devTools and ns.Editor.active then ns.Editor.Toggle() end
        ns.Print(BaquianoDB.devTools and "edit mode unlocked (/baq edit, /baq undo)." or "edit mode locked.")

    elseif cmd == "edit" and BaquianoDB.devTools then
        if ns.Editor.Toggle() then
            ns.Print("edit mode on: open the map (M) and click to draw paths. Recording is paused.")
        else
            ns.Print("edit mode off.")
        end

    elseif cmd == "undo" and BaquianoDB.devTools then
        ns.Editor.Undo()

    elseif cmd == "route" then
        ns.Nav.Describe()

    elseif cmd == "stop" then
        ns.Nav.Clear()
        ns.Print("route cleared.")

    elseif cmd == "arrow" then
        if rest == "reset" then
            ns.Arrow.ResetPosition()
            ns.Print("arrow position reset.")
        elseif ns.Arrow.Toggle() then
            ns.Print("arrow on (it appears when there is a route).")
        else
            ns.Print("arrow hidden.")
        end

    elseif cmd == "minimap" then
        if ns.MinimapOverlay.Toggle() then
            ns.Print("route shown on the minimap.")
        else
            ns.Print("route hidden on the minimap.")
        end

    elseif cmd == "carbonite" then
        if not ns.CarboniteOverlay.Toggle() then
            ns.Print("route hidden on Carbonite's map.")
        elseif _G.Carbonite then
            ns.Print("route shown on Carbonite's map.")
        else
            ns.Print("route will be shown on Carbonite's map (Carbonite is not loaded).")
        end

    elseif cmd == "flights" then
        local known = ns.Flights.KnownCount()
        if ns.Flights.Toggle() then
            ns.Print(string.format("routes may use flights (%d flight masters known).", known))
            if known == 0 then
                ns.Print("open a flight master's map once so Baquiano learns which flights you know.")
            end
        else
            ns.Print("routes will not use flights.")
        end

    elseif cmd == "trail" then
        BaquianoDB.trail = not BaquianoDB.trail
        ns.MapOverlay.Refresh()
        ns.Print(BaquianoDB.trail and "trail shown as green breadcrumbs, fading behind you."
            or "trail hidden.")

    elseif cmd == "boats" then
        local n = tonumber(rest:match("^forget%s+(%d+)$") or "")
        if rest == "list" then
            ns.Transports.Describe()
        elseif n then
            ns.Print(ns.Transports.Forget(n) and ("what was measured of trip " .. n .. " is forgotten.") or ("there is no trip " .. n .. "."))
        elseif rest == "forget" then
            ns.Transports.Forget()
            ns.Print("boat and zeppelin times measured, and trips learned, forgotten.")
        elseif ns.Transports.Toggle() then
            ns.Print(string.format("routes may use boats and zeppelins (%d trips).", #ns.Transports.Trips()))
        else
            ns.Print("routes will not use boats or zeppelins.")
        end

    elseif cmd == "avoid" then
        BaquianoDB.avoidEnemy = not BaquianoDB.avoidEnemy
        ns.Print(BaquianoDB.avoidEnemy and "routes keep away from the other faction's towns."
            or "routes may go through the other faction's towns.")

    elseif cmd == "follow" then
        if ns.Waypoints.Toggle() then
            ns.Print("waypoints set by other addons or on the map become the destination.")
        else
            ns.Print("waypoints set by other addons or on the map are ignored.")
        end

    elseif cmd == "walked" then
        local unit = rest:match("^units?%s+(%S+)$")
        if rest == "reset" then
            ns.Odometer.Reset()
        elseif unit then
            if ns.Odometer.SetUnit(unit) then
                ns.Odometer.Describe()
            else
                ns.Print("unknown unit: use yd, m, km or mi.")
            end
        elseif ns.Odometer.Toggle() then
            ns.Odometer.Describe()
            ns.Print("yards walked shown (drag to move, right click to start the session count again).")
        else
            ns.Print("yards walked hidden.")
        end

    elseif cmd == "cities" then
        BaquianoDB.cityPaths = not BaquianoDB.cityPaths
        ns.MapOverlay.Refresh()
        ns.Print(BaquianoDB.cityPaths and "recorded paths shown in capital cities too."
            or "recorded paths hidden in capital cities (hold Shift on the map to see them).")

    elseif cmd == "paths" then
        Baquiano_TogglePaths()

    elseif cmd == "export" then
        if rest == "all" then
            local list = {}
            for m in pairs(BaquianoDB.maps) do list[#list + 1] = m end
            ns.Share.ShowExport(list, "All your paths")
        else
            local mapID = ns.PlayerPos()
            if not mapID then
                ns.Print(NO_POSITION)
            else
                ns.Share.ShowExport({ mapID }, ZoneName(mapID))
            end
        end

    elseif cmd == "import" then
        if rest == "list" then
            ns.Share.List()
        elseif rest == "undo" then
            local name, err = ns.Share.Undo()
            ns.Print(name and ("import \"" .. name .. "\" undone.") or err)
        else
            ns.Share.ShowImport(rest ~= "" and rest or date("import %Y-%m-%d %H:%M"))
        end

    elseif cmd == "info" then
        local mapID = ns.PlayerPos()
        if not mapID then
            ns.Print(NO_POSITION)
            return
        end
        local nodes, edges, pieces = ns.Graph.Stats(mapID)
        ns.Print(string.format("%s: %d points and %d links in %d separate pieces. Recording %s.",
            ZoneName(mapID), nodes, edges, pieces, BaquianoDB.recording and "on" or "paused"))
        ns.Print(string.format("%d known crossings to other zones.", ns.Graph.PortalCount(mapID)))
        ns.Print(string.format("%d flight masters known by this character; flights %s.",
            ns.Flights.KnownCount(), BaquianoDB.useFlights and "on" or "off"))
        if ns.approxSize then
            ns.Print("note: this client does not give the map size; distances are approximate.")
        end

    elseif cmd == "wipe" then
        local mapID = ns.PlayerPos()
        if not mapID then
            ns.Print(NO_POSITION)
            return
        end
        StaticPopup_Show("BAQUIANO_WIPE_ZONE", ZoneName(mapID), nil, mapID)

    else
        Help()
    end
end

-- Key binding (Bindings.xml): Key Bindings > AddOns > Baquiano.
BINDING_HEADER_BAQUIANO = "Baquiano"
BINDING_NAME_BAQUIANO_TOGGLE_PATHS = "Show or hide recorded paths"
BINDING_NAME_BAQUIANO_CLEAR_ROUTE = "Clear the route"

function Baquiano_ClearRoute()
    ns.Nav.Unmark()
end

function Baquiano_TogglePaths()
    if ns.PathView.Toggle() then
        ns.Print("recorded paths shown on the map and minimap (blue outdoors, violet indoors).")
    else
        ns.Print("recorded paths hidden (hold Shift on the map to see them).")
    end
    ns.Options.Refresh()
end

SLASH_BAQUIANO1 = "/baquiano"
SLASH_BAQUIANO2 = "/baq"
SlashCmdList["BAQUIANO"] = function(msg)
    local ok, err = pcall(Handle, msg)
    if not ok then ns.Print("error: " .. tostring(err)) end
    ns.Options.Refresh()
end
