-- Baquiano: boats and zeppelins. Their docks come from TransportData.lua
-- (generated from Leatrix Maps, see tools/make_transports.py); how long each
-- trip takes is measured the first time it is ridden, and estimated until
-- then. A trip ridden that is not in those tables is learned too: where it
-- was boarded, where it landed and how long it took.
--
-- BaquianoDB.boatTimes[key] = { seconds, times } -- trips of the tables
-- BaquianoDB.boats = { { m1, x1, y1, m2, x2, y2, seconds, times }, ... } -- others
local ADDON, ns = ...

local Transports = {}
ns.Transports = Transports

local cfg = ns.cfg

local function ZoneName(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name or "?"
end

local function Duration(sec)
    sec = math.floor(sec + 0.5)
    if sec < 60 then return sec .. " s" end
    return string.format("%d min %d s", math.floor(sec / 60), sec % 60)
end

local function Key(d)
    return string.format("%d:%.3f:%.3f>%d:%.3f:%.3f", d[1], d[2], d[3], d[4], d[5], d[6])
end

-- The faction letter of the tables for the player: A, H or nil.
local function Side()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return (f == "Alliance" and "A") or (f == "Horde" and "H") or nil
end

-- Every trip this character can take, rebuilt by Trips():
-- { m1, x1, y1, m2, x2, y2, seconds, oneWay =, measured =, key = | learned = i, kind = }
local list = {}

-- Trips usable in routes (none when turned off). Docks are side 0 (boarded)
-- and 1 (landed); a one-way trip only sails from 0 to 1.
function Transports.Trips()
    wipe(list)
    if not BaquianoDB.useBoats then return list end
    local side = Side()
    for _, d in ipairs(ns.TransportData or {}) do
        if d[7] == "N" or not side or d[7] == side then
            local key = Key(d)
            local time = BaquianoDB.boatTimes[key]
            local tram = d[9] == "tram"
            list[#list + 1] = { d[1], d[2], d[3], d[4], d[5], d[6],
                time and time[1] or (tram and cfg.TRAM_TRIP) or cfg.BOAT_TRIP,
                oneWay = not d[8], measured = time ~= nil, key = key, kind = d[9],
                wait = tram and cfg.TRAM_WAIT or cfg.BOAT_WAIT }
        end
    end
    for i, t in ipairs(BaquianoDB.boats) do
        list[#list + 1] = { t[1], t[2], t[3], t[4], t[5], t[6], t[7], measured = true, learned = i }
    end
    return list
end

-- Dock of trip t (as numbered by the last Trips()): mapID, x, y.
function Transports.Dock(t, side)
    local trip = list[t]
    if not trip then return nil end
    if side == 0 then return trip[1], trip[2], trip[3] end
    return trip[4], trip[5], trip[6]
end

-- What trip t is, for messages: "boat", "zeppelin", "tram", or "boat or
-- zeppelin" for one learned by riding it.
function Transports.Ride(t)
    return list[t] and list[t].kind or "boat or zeppelin"
end

-- Name of a dock, for messages: its zone.
function Transports.Name(t, side)
    return ZoneName((Transports.Dock(t, side)))
end

-- A ride that matches a trip of the tables: its key, or nil.
local function Known(bm, bx, by, lm, lx, ly)
    local function Near(m1, x1, y1, m2, x2, y2)
        local d = ns.WorldDist(m1, x1, y1, m2, x2, y2)
        return d and d <= cfg.BOAT_NEAR
    end
    for _, d in ipairs(ns.TransportData or {}) do
        if Near(bm, bx, by, d[1], d[2], d[3]) and Near(lm, lx, ly, d[4], d[5], d[6]) then return Key(d) end
        if d[8] and Near(bm, bx, by, d[4], d[5], d[6]) and Near(lm, lx, ly, d[1], d[2], d[3]) then return Key(d) end
    end
end

-- Saves a ride: the time of a trip of the tables, or a trip of its own (new,
-- or averaged with the same one taken before).
local function Note(bm, bx, by, lm, lx, ly, seconds, far)
    local key = Known(bm, bx, by, lm, lx, ly)
    if key then
        local t = BaquianoDB.boatTimes[key]
        if t then
            t[1], t[2] = (t[1] * t[2] + seconds) / (t[2] + 1), t[2] + 1
        else
            BaquianoDB.boatTimes[key] = { seconds, 1 }
            ns.Print(string.format("boat or zeppelin from %s to %s: %s, noted for routes.",
                ZoneName(bm), ZoneName(lm), Duration(seconds)))
        end
        return
    end
    -- Not in the tables: only a long ride into another zone counts (every
    -- boat and zeppelin lands in a zone other than the one it left).
    if lm == bm or not far then return end
    for _, trip in ipairs(BaquianoDB.boats) do
        local db = ns.WorldDist(trip[1], trip[2], trip[3], bm, bx, by)
        local dl = ns.WorldDist(trip[4], trip[5], trip[6], lm, lx, ly)
        if db and dl and db <= cfg.BOAT_SAME and dl <= cfg.BOAT_SAME then
            local n = trip[8] or 1
            trip[7] = (trip[7] * n + seconds) / (n + 1)
            trip[8] = n + 1
            return
        end
    end
    BaquianoDB.boats[#BaquianoDB.boats + 1] = { bm, bx, by, lm, lx, ly, seconds, 1 }
    ns.Print(string.format("learned a boat or zeppelin trip: %s to %s (%s).",
        ZoneName(bm), ZoneName(lm), Duration(seconds)))
end

-- Trips with a time measured, to share: the known ones of the tables and the
-- learned ones. { m1, x1, y1, m2, x2, y2, seconds }, ...
function Transports.Measured()
    local out = {}
    for _, d in ipairs(ns.TransportData or {}) do
        local t = BaquianoDB.boatTimes[Key(d)]
        if t then out[#out + 1] = { d[1], d[2], d[3], d[4], d[5], d[6], t[1] } end
    end
    for _, t in ipairs(BaquianoDB.boats) do
        out[#out + 1] = { t[1], t[2], t[3], t[4], t[5], t[6], t[7] }
    end
    return out
end

-- A trip shared by another player: its time is taken if none was measured
-- here, and an unknown trip is added. Nothing measured here is replaced.
function Transports.Merge(bm, bx, by, lm, lx, ly, seconds)
    local key = Known(bm, bx, by, lm, lx, ly)
    if key then
        if not BaquianoDB.boatTimes[key] then BaquianoDB.boatTimes[key] = { seconds, 1 } end
        return
    end
    if lm == bm then return end
    for _, trip in ipairs(BaquianoDB.boats) do
        local db = ns.WorldDist(trip[1], trip[2], trip[3], bm, bx, by)
        local dl = ns.WorldDist(trip[4], trip[5], trip[6], lm, lx, ly)
        if db and dl and db <= cfg.BOAT_SAME and dl <= cfg.BOAT_SAME then return end
    end
    BaquianoDB.boats[#BaquianoDB.boats + 1] = { bm, bx, by, lm, lx, ly, seconds, 1 }
end

-- Watching rides (ns.riding, see Core): the trip starts where the player
-- stood before moving, and ends where the ride stopped. A ride broken by a
-- loading screen (from one continent to another) is still one trip: it ends
-- only after a while on firm ground.
local still       -- { m, x, y }: last position while not riding
local trip        -- { board = { m, x, y }, start, land = { m, x, y }, landTime }
local groundSince -- when the current spell on firm ground began

local function Tick()
    local now = GetTime()
    if UnitOnTaxi and UnitOnTaxi("player") then
        trip = nil -- a flight, not a boat
        return
    end
    local m, x, y = ns.PlayerPos()
    if ns.riding then
        groundSince = nil
        if not trip and still then
            trip = { board = still, start = now }
        end
        if trip and m then
            trip.land, trip.landTime = { m, x, y }, now
        end
        return
    end
    if m then still = { m, x, y } end
    if not trip then return end
    groundSince = groundSince or now
    if now - groundSince < cfg.BOAT_SETTLE then return end

    local b, l = trip.board, trip.land
    local seconds = (trip.landTime or now) - trip.start
    trip = nil
    if not l then return end
    local d = ns.WorldDist(b[1], b[2], b[3], l[1], l[2], l[3])
    -- Another continent (no distance) or far enough: not a knockback.
    Note(b[1], b[2], b[3], l[1], l[2], l[3], seconds, d == nil or d >= cfg.BOAT_MIN)
end

function Transports.Init()
    -- Trips noted by mistake earlier (same zone at both ends) are dropped,
    -- and so are those the tables already know.
    for i = #BaquianoDB.boats, 1, -1 do
        local t = BaquianoDB.boats[i]
        if t[1] == t[4] or Known(t[1], t[2], t[3], t[4], t[5], t[6]) then
            table.remove(BaquianoDB.boats, i)
        end
    end
    C_Timer.NewTicker(0.25, function()
        local ok, err = pcall(Tick)
        if not ok and not Transports.warned then
            Transports.warned = true
            ns.Print("boat watch error: " .. tostring(err))
        end
    end)
end

-- Turns boats and zeppelins in routes on or off; returns whether on now.
function Transports.Toggle()
    BaquianoDB.useBoats = not BaquianoDB.useBoats
    return BaquianoDB.useBoats
end

-- Lists the trips this character can take in the chat.
function Transports.Describe()
    local on = BaquianoDB.useBoats
    BaquianoDB.useBoats = true
    local trips = Transports.Trips()
    BaquianoDB.useBoats = on
    if #trips == 0 then
        ns.Print("no boat or zeppelin trips known.")
        return
    end
    ns.Print(string.format("%d boat and zeppelin trips%s:", #trips, on and "" or " (not used in routes now)"))
    for i, t in ipairs(trips) do
        print(string.format("  %d. %s %.1f %.1f %s %s %.1f %.1f, %s", i,
            ZoneName(t[1]), t[2] * 100, t[3] * 100, t.oneWay and "->" or "<->",
            ZoneName(t[4]), t[5] * 100, t[6] * 100,
            t.measured and Duration(t[7]) or ("~" .. Duration(t[7]) .. ", not ridden yet"))
            .. (t.kind and (" (" .. t.kind .. ")") or ""))
    end
end

-- Forgets what was measured or learned: all of it, or about trip i of the
-- list. Returns false when there is no trip i.
function Transports.Forget(i)
    if not i then
        wipe(BaquianoDB.boats)
        wipe(BaquianoDB.boatTimes)
        return true
    end
    local on = BaquianoDB.useBoats
    BaquianoDB.useBoats = true
    local t = Transports.Trips()[i]
    BaquianoDB.useBoats = on
    if not t then return false end
    if t.learned then
        table.remove(BaquianoDB.boats, t.learned)
    else
        BaquianoDB.boatTimes[t.key] = nil
    end
    return true
end
