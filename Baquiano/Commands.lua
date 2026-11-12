-- Baquiano: /baquiano and /baq commands.
local ADDON, ns = ...

local function Help()
    ns.Print("commands:")
    print("  /baq record - turn path recording on or off")
    print("  /baq go X Y - set a destination in your zone (coordinates 0 to 100)")
    print("  /baq stop - clear the active route")
    print("  /baq arrow - show or hide the arrow")
    print("  /baq arrow reset - put the arrow back in its starting position")
    print("  /baq paths - show or hide the recorded paths on the map")
    print("  /baq info - how much is recorded in your zone")
    print("  /baq wipe - delete the recorded paths of your zone")
    print("  On the map: Alt + left click sets a destination.")
end

StaticPopupDialogs["BAQUIANO_WIPE_ZONE"] = {
    text = "Delete all recorded paths in %s? This cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, mapID)
        if ns.Nav.route and ns.Nav.route.mapID == mapID then ns.Nav.Clear() end
        ns.Graph.Wipe(mapID)
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

    if cmd == "record" then
        if ns.Recorder.Toggle() then
            ns.Print("recording on.")
        else
            ns.Print("recording paused.")
        end

    elseif cmd == "go" then
        local sx, sy = rest:gsub(",", "."):match("^(%d+%.?%d*)%s+(%d+%.?%d*)$")
        local x, y = tonumber(sx), tonumber(sy)
        if not x or not y or x > 100 or y > 100 then
            ns.Print("usage: /baq go 45.2 63.1")
            return
        end
        local mapID = ns.PlayerPos()
        if not mapID then
            ns.Print(NO_POSITION)
            return
        end
        local route, why = ns.Nav.SetDestination(mapID, x / 100, y / 100)
        if not route then
            ns.Print(why)
        elseif route.partial then
            ns.Print("partial route: the last stretch is a straight line.")
        elseif route.usedNetwork then
            ns.Print("route found along known paths.")
        else
            ns.Print("no recorded paths help here; guiding you in a straight line.")
        end

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

    elseif cmd == "paths" then
        BaquianoDB.showNetwork = not BaquianoDB.showNetwork
        ns.MapOverlay.MarkDirty()
        ns.Print(BaquianoDB.showNetwork and "paths shown on the map." or "paths hidden on the map.")

    elseif cmd == "info" then
        local mapID = ns.PlayerPos()
        if not mapID then
            ns.Print(NO_POSITION)
            return
        end
        local nodes, edges = ns.Graph.Stats(mapID)
        ns.Print(string.format("%s: %d points and %d links recorded. Recording %s.",
            ZoneName(mapID), nodes, edges, BaquianoDB.recording and "on" or "paused"))
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

SLASH_BAQUIANO1 = "/baquiano"
SLASH_BAQUIANO2 = "/baq"
SlashCmdList["BAQUIANO"] = function(msg)
    local ok, err = pcall(Handle, msg)
    if not ok then ns.Print("error: " .. tostring(err)) end
end
