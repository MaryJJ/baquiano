-- Baquiano: sharing recorded paths with other players, as a text to copy
-- and paste. /baq export shows the text; /baq import takes one and adds it
-- to the paths already recorded (nothing is ever deleted); /baq import undo
-- takes the last import out again.
--
-- The text: "BAQ1;" sections separated by ";", then "=" and a checksum.
--   M<map><nodes>,<edges>,<inside>   a zone: nodes are two coordinates of 3
--                                    letters each; edges are pairs of node
--                                    numbers (as differences); inside, the
--                                    numbers of the nodes indoors
--   P<map><x><y><map><x><y>...       crossings between zones
--   B<map><x><y><map><x><y><s>...    boat and zeppelin trips and their time
-- Numbers are written in the letters of ALPHABET: a letter below 32 ends the
-- number, one from 32 up carries 5 bits and goes on. Only letters, digits,
-- "+" and "/" are used, so chat programs leave the text alone.
--
-- BaquianoDB.imports = { { name, at, maps = { [mapID] = { n0, n1, e0, e1,
-- x, y, a, b } }, portals = { {...}, ... } }, ... }: what each import added,
-- to undo it (n = node counts, e = edge array lengths, before and after;
-- x, y, a, b the first node and edge added, to check nothing changed since).
local ADDON, ns = ...

local Share = {}
ns.Share = Share

local Graph = ns.Graph

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE = {}
for i = 1, 64 do VALUE[ALPHABET:byte(i)] = i - 1 end
local function Char(v) return ALPHABET:sub(v + 1, v + 1) end

local COORD = 262143 -- 18 bits: coordinates from -0.5 to 1.5 in 3 letters

local function ZoneName(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name or ("zone " .. tostring(mapID))
end

----------------------------------------------------------------------------
-- Writing

local function Number(out, n)
    n = math.floor(n)
    while n >= 32 do
        out[#out + 1] = Char(32 + n % 32)
        n = math.floor(n / 32)
    end
    out[#out + 1] = Char(n)
end

local function Signed(out, n)
    Number(out, n >= 0 and n * 2 or -n * 2 - 1)
end

local function Coord(out, v)
    local q = math.floor((v + 0.5) / 2 * COORD + 0.5)
    q = math.max(0, math.min(COORD, q))
    out[#out + 1] = Char(math.floor(q / 4096))
    out[#out + 1] = Char(math.floor(q / 64) % 64)
    out[#out + 1] = Char(q % 64)
end

local function Checksum(s)
    local sum = 0
    for i = 1, #s do sum = (sum + s:byte(i) * (i % 7 + 1)) % 4096 end
    return Char(math.floor(sum / 64)) .. Char(sum % 64)
end

-- The text for the zones in mapIDs (a list), with the crossings that touch
-- them and the boat and zeppelin trips known. Returns text, zones, points.
function Share.Export(mapIDs)
    local parts, zones, points, wanted = { "BAQ1" }, 0, 0, {}
    for _, m in ipairs(mapIDs) do
        local saved = BaquianoDB.maps[m]
        local n = saved and math.floor(#saved.nodes / 2) or 0
        if n > 0 then
            wanted[m] = true
            zones, points = zones + 1, points + n
            local out = { "M" }
            Number(out, m)
            for i = 1, #saved.nodes do Coord(out, saved.nodes[i]) end
            out[#out + 1] = ","
            local prevA = 0
            for e = 1, #saved.edges, 2 do
                local a, b = saved.edges[e], saved.edges[e + 1]
                Signed(out, a - prevA)
                Signed(out, b - a)
                prevA = a
            end
            out[#out + 1] = ","
            local inside = {}
            for i in pairs(saved.inside or {}) do inside[#inside + 1] = i end
            table.sort(inside)
            local prev = 0
            for _, i in ipairs(inside) do
                Number(out, i - prev)
                prev = i
            end
            parts[#parts + 1] = table.concat(out)
        end
    end

    local out = { "P" }
    for _, p in ipairs(BaquianoDB.portals) do
        if wanted[p[1]] or wanted[p[4]] then
            Number(out, p[1]); Coord(out, p[2]); Coord(out, p[3])
            Number(out, p[4]); Coord(out, p[5]); Coord(out, p[6])
        end
    end
    if #out > 1 then parts[#parts + 1] = table.concat(out) end

    out = { "B" }
    for _, t in ipairs(ns.Transports.Measured()) do
        Number(out, t[1]); Coord(out, t[2]); Coord(out, t[3])
        Number(out, t[4]); Coord(out, t[5]); Coord(out, t[6])
        Number(out, t[7] + 0.5)
    end
    if #out > 1 then parts[#parts + 1] = table.concat(out) end

    local body = table.concat(parts, ";")
    return body .. ";=" .. Checksum(body), zones, points
end

----------------------------------------------------------------------------
-- Reading

-- Reads text back: { maps = { [mapID] = { nodes, edges, inside } },
-- portals = {...}, boats = {...} }, or nil and what is wrong.
function Share.Decode(text)
    text = (text or ""):gsub("%s", "")
    local body, sum = text:match("^(BAQ1;.*);=(..)$")
    if not body then
        if text:find("^BAQ%d") then return nil, "the text is incomplete: copy all of it, up to the end." end
        return nil, "this is not a Baquiano text."
    end
    if Checksum(body) ~= sum then
        return nil, "the text changed on the way (a letter missing or different): copy it again."
    end

    local data = { maps = {}, portals = {}, boats = {} }
    local ok, err = pcall(function()
        for section in body:gmatch("[^;]+") do
            local kind = section:sub(1, 1)
            local pos = 2
            local function More() return pos <= #section and section:sub(pos, pos) ~= "," end
            local function ReadNumber()
                local n, scale = 0, 1
                while true do
                    local v = VALUE[section:byte(pos)]
                    if not v then error("bad letter") end
                    pos = pos + 1
                    if v < 32 then return n + v * scale end
                    n = n + (v - 32) * scale
                    scale = scale * 32
                end
            end
            local function ReadSigned()
                local z = ReadNumber()
                return (z % 2 == 0) and z / 2 or -(z + 1) / 2
            end
            local function ReadCoord()
                local a, b, c = VALUE[section:byte(pos)], VALUE[section:byte(pos + 1)], VALUE[section:byte(pos + 2)]
                if not (a and b and c) then error("bad coordinate") end
                pos = pos + 3
                return math.floor(((a * 4096 + b * 64 + c) / COORD * 2 - 0.5) * 100000 + 0.5) / 100000
            end

            if section == "BAQ1" then
                -- the header, already checked
            elseif kind == "M" then
                local m = ReadNumber()
                local zone = { nodes = {}, edges = {}, inside = {} }
                while More() do zone.nodes[#zone.nodes + 1] = ReadCoord() end
                if #zone.nodes % 2 == 1 then error("odd coordinates") end
                local n = #zone.nodes / 2
                pos = pos + 1
                local a = 0
                while More() do
                    a = a + ReadSigned()
                    local b = a + ReadSigned()
                    if a < 1 or a > n or b < 1 or b > n then error("bad link") end
                    zone.edges[#zone.edges + 1] = a
                    zone.edges[#zone.edges + 1] = b
                end
                pos = pos + 1
                local i = 0
                while pos <= #section do
                    i = i + ReadNumber()
                    if i > n then error("bad indoor point") end
                    zone.inside[i] = true
                end
                data.maps[m] = zone
            elseif kind == "P" then
                while pos <= #section do
                    data.portals[#data.portals + 1] = { ReadNumber(), ReadCoord(), ReadCoord(),
                        ReadNumber(), ReadCoord(), ReadCoord() }
                end
            elseif kind == "B" then
                while pos <= #section do
                    data.boats[#data.boats + 1] = { ReadNumber(), ReadCoord(), ReadCoord(),
                        ReadNumber(), ReadCoord(), ReadCoord(), ReadNumber() }
                end
            else
                error("unknown section")
            end
        end
    end)
    if not ok then return nil, "the text is damaged (" .. tostring(err):gsub("^.-:%d+: ", "") .. ")." end
    return data
end

-- One line per zone of a decoded text, for the confirmation.
function Share.Summary(data)
    local lines, total = {}, 0
    for m, zone in pairs(data.maps) do
        local n = #zone.nodes / 2
        total = total + n
        lines[#lines + 1] = string.format("%s: %d points", ZoneName(m), n)
    end
    table.sort(lines)
    if #data.portals > 0 then lines[#lines + 1] = #data.portals .. " crossings between zones" end
    if #data.boats > 0 then lines[#lines + 1] = #data.boats .. " boat and zeppelin times" end
    return table.concat(lines, "\n"), total
end

----------------------------------------------------------------------------
-- Adding to the paths recorded, and taking it out again

-- Adds a decoded text to the paths. Points close to one already recorded are
-- joined to it; the rest are added. Returns points added, or nil and why.
function Share.Apply(data, name)
    if ns.Editor.active then return nil, "leave edit mode first." end
    local cfg = ns.cfg
    local rec = { name = name, at = time(), maps = {}, portals = {} }
    local added = 0
    for m, zone in pairs(data.maps) do
        local g = Graph.Get(m, true)
        local n0, e0 = g.n, #g.saved.edges
        local index = {}
        for i = 1, #zone.nodes / 2 do
            local x, y, inside = zone.nodes[i * 2 - 1], zone.nodes[i * 2], zone.inside[i] or false
            local near = Graph.Nearest(g, x, y, cfg.MERGE, function(k)
                return k <= n0 and Graph.Inside(g, k) == inside
            end)
            index[i] = near or Graph.AddNode(g, x, y, inside)
        end
        for e = 1, #zone.edges, 2 do
            Graph.AddEdge(g, index[zone.edges[e]], index[zone.edges[e + 1]])
        end
        Graph.JoinPieces(g)
        local saved = g.saved
        if g.n > n0 or #saved.edges > e0 then
            rec.maps[m] = { n0, g.n, e0, #saved.edges,
                saved.nodes[n0 * 2 + 1], saved.nodes[n0 * 2 + 2], saved.edges[e0 + 1], saved.edges[e0 + 2] }
            added = added + (g.n - n0)
        elseif g.n == 0 then
            Graph.Wipe(m)
        end
    end
    for _, p in ipairs(data.portals) do
        if Graph.AddPortal(p[1], p[2], p[3], p[4], p[5], p[6]) then
            local list = BaquianoDB.portals
            rec.portals[#rec.portals + 1] = list[#list]
        end
    end
    for _, t in ipairs(data.boats) do ns.Transports.Merge(t[1], t[2], t[3], t[4], t[5], t[6], t[7]) end

    if next(rec.maps) or #rec.portals > 0 then
        BaquianoDB.imports[#BaquianoDB.imports + 1] = rec
    end
    ns.MapOverlay.MarkDirty()
    return added
end

-- Takes out what the last import added. Returns its name, or nil and why.
function Share.Undo()
    local rec = BaquianoDB.imports[#BaquianoDB.imports]
    if not rec then return nil, "there is no import to undo." end
    if ns.Editor.active then return nil, "leave edit mode first." end
    -- Points deleted since (edit mode) would leave the numbers off.
    for m, r in pairs(rec.maps) do
        local saved = BaquianoDB.maps[m]
        local ok = saved and #saved.nodes >= r[2] * 2 and #saved.edges >= r[4]
            and (r[2] == r[1] or (saved.nodes[r[1] * 2 + 1] == r[5] and saved.nodes[r[1] * 2 + 2] == r[6]))
            and (r[4] == r[3] or (saved.edges[r[3] + 1] == r[7] and saved.edges[r[3] + 2] == r[8]))
        if not ok then
            return nil, "the paths of " .. ZoneName(m) .. " were edited since, so it cannot be undone."
        end
    end
    if ns.Nav.route then ns.Nav.Clear() end
    for m, r in pairs(rec.maps) do
        local g = Graph.Get(m)
        Graph.RemoveSpan(g, r[1], r[2], r[3], r[4])
        if g.n == 0 then Graph.Wipe(m) end
    end
    local list = BaquianoDB.portals
    for _, p in ipairs(rec.portals) do
        for i = #list, 1, -1 do
            local q = list[i]
            if q[1] == p[1] and q[2] == p[2] and q[3] == p[3] and q[4] == p[4] and q[5] == p[5] and q[6] == p[6] then
                table.remove(list, i)
                break
            end
        end
    end
    table.remove(BaquianoDB.imports)
    ns.Recorder.Restart()
    ns.MapOverlay.MarkDirty()
    return rec.name
end

function Share.List()
    local list = BaquianoDB.imports
    if #list == 0 then
        ns.Print("no imports yet.")
        return
    end
    ns.Print(#list .. " imports (the last one can be undone with /baq import undo):")
    for i, rec in ipairs(list) do
        local points, zones = 0, {}
        for m, r in pairs(rec.maps) do
            points = points + r[2] - r[1]
            zones[#zones + 1] = ZoneName(m)
        end
        table.sort(zones)
        print(string.format("  %d. %s (%s): %d points in %s", i, rec.name or "?",
            date("%Y-%m-%d", rec.at), points, #zones > 0 and table.concat(zones, ", ") or "no zone"))
    end
end

----------------------------------------------------------------------------
-- Paths that come with the addon (StarterData.lua, see
-- tools/make_starter.py): added once per version, like an import.

function Share.Init()
    local starter = ns.StarterData
    if not starter or BaquianoDB.starter == starter.version then return end
    C_Timer.After(3, function()
        local ok, added = pcall(function()
            local data, err = Share.Decode(starter.text)
            if not data then error(err) end
            return Share.Apply(data, "paths that came with Baquiano " .. starter.version)
        end)
        if not ok then
            ns.Print("could not add the paths that came with the addon: " .. tostring(added))
            return
        end
        if not added then return end -- edit mode: tried again next login
        BaquianoDB.starter = starter.version
        if added > 0 then
            ns.Print(string.format("added %d points of paths that came with the addon. /baq import undo takes them out.", added))
        end
    end)
end

----------------------------------------------------------------------------
-- The window

local frame, box, info, action, pasted, pending

local function Build()
    frame = CreateFrame("Frame", "BaquianoShareFrame", UIParent, "BackdropTemplate")
    frame:SetSize(520, 340)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "BaquianoShareFrame") -- Escape closes it

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", 0, -18)

    info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", 22, -40)
    info:SetPoint("TOPRIGHT", -22, -40)
    info:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", "BaquianoShareScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 22, -92)
    scroll:SetPoint("BOTTOMRIGHT", -40, 50)
    box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetWidth(450)
    box:SetHeight(200)
    box:SetScript("OnEscapePressed", function() frame:Hide() end)
    scroll:SetScrollChild(box)
    scroll:SetScript("OnMouseDown", function() box:SetFocus() end)

    -- Pasting a long text letter by letter into the box would freeze the
    -- game; the letters are gathered as they arrive and joined once.
    local buffer, count, lastAt = {}, 0, nil
    box:SetScript("OnChar", function(self, c)
        if frame.mode ~= "import" then return end
        if lastAt ~= GetTime() then
            buffer, count, lastAt = {}, 0, GetTime()
            self:SetScript("OnUpdate", function(s)
                s:SetScript("OnUpdate", nil)
                pasted = table.concat(buffer)
                Share.Check()
            end)
        end
        count = count + 1
        buffer[count] = c
    end)

    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(100, 22)
    close:SetPoint("BOTTOMRIGHT", -20, 18)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() frame:Hide() end)

    action = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    action:SetSize(100, 22)
    action:SetPoint("RIGHT", close, "LEFT", -8, 0)
    action:SetText("Import")
    action:SetScript("OnClick", function()
        if not pending then return end
        local added, err = Share.Apply(pending, frame.name)
        pending = nil
        if added then
            ns.Print(string.format("imported: %d points added to your paths. /baq import undo takes them out.", added))
            frame:Hide()
        else
            info:SetText("|cffff6060" .. err .. "|r")
        end
    end)
end

-- Reads what was pasted, and shows what it holds.
function Share.Check()
    local text = pasted or box:GetText()
    local data, err = Share.Decode(text)
    pending = data
    if data then
        local summary = Share.Summary(data)
        info:SetText("This text has what is listed below. Click Import to add it to your paths;\n/baq import undo takes it out again.")
        box:SetMaxBytes(0)
        box:SetText(summary)
        box:SetMaxBytes(2500)
        action:Enable()
    else
        info:SetText("|cffff6060" .. err .. "|r")
        action:Disable()
    end
end

function Share.ShowExport(mapIDs, what)
    if not frame then Build() end
    local text, zones, points = Share.Export(mapIDs)
    if zones == 0 then
        ns.Print("nothing recorded to export" .. (what and (" in " .. what) or "") .. ".")
        return
    end
    frame.mode = "export"
    frame.title:SetText("Baquiano: export")
    info:SetText(string.format("%s: %d zones, %d points (%d letters).\nCopy it with Ctrl+C and send it; the other player pastes it in /baq import.",
        what or "Your paths", zones, points, #text))
    action:Hide()
    box:SetMaxBytes(0)
    box:SetText(text)
    frame:Show()
    box:SetFocus()
    box:HighlightText()
end

function Share.ShowImport(name)
    if not frame then Build() end
    frame.mode = "import"
    frame.name = name
    frame.title:SetText("Baquiano: import")
    info:SetText("Paste the text here with Ctrl+V. Nothing is added until you click Import.")
    pasted, pending = nil, nil
    box:SetMaxBytes(0)
    box:SetText("")
    box:SetMaxBytes(2500) -- see OnChar: the box itself keeps little
    action:Show()
    action:Disable()
    frame:Show()
    box:SetFocus()
end
