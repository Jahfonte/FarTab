----------------------------------------------
-- FarTab - Reverse Tab-Targeting
-- Cycles enemies from furthest to closest.
-- Only targets mobs already in combat.
-- Requires SuperWoW for nameplate GUID scanning.
----------------------------------------------

FarTab = FarTab or {}
FarTabDB = FarTabDB or {}

local _G = _G or getfenv(0)
local getn = table.getn
local format = string.format
local floor = math.floor
local sqrt = math.sqrt
local cos = math.cos
local sin = math.sin
local rad = math.rad

local ADDON_NAME = "FarTab"
local ADDON_VERSION = "1.0.0"
local ADDON_COLOR = "|cff00ccff"
local ADDON_PREFIX = ADDON_COLOR .. "FarTab|r: "

local superwow = false
local enemies = {}
local cycleIdx = 0
local lastScanTime = 0
local initialized = false

local defaults = {
    enabled = true,
    maxRange = 100,
    showChat = false,
    showMinimap = true,
    minimapAngle = 160,
}

----------------------------------------------
-- Utility
----------------------------------------------

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. tostring(msg))
end

local function EnsureDB()
    if not FarTabDB or type(FarTabDB) ~= "table" then
        FarTabDB = {}
    end
    for k, v in pairs(defaults) do
        if FarTabDB[k] == nil then
            FarTabDB[k] = v
        end
    end
end

----------------------------------------------
-- Distance
----------------------------------------------

local function GetDistance(unit)
    if not UnitExists(unit) then return nil end
    local x1, y1, z1 = UnitPosition("player")
    local x2, y2, z2 = UnitPosition(unit)
    if x1 and x2 then
        return sqrt((x2 - x1)^2 + (y2 - y1)^2 + (z2 - z1)^2)
    end
    return nil
end

----------------------------------------------
-- Nameplate Scanning (SuperWoW)
-- Tries 3 methods to find nameplate GUIDs:
--   1. pfUI nameplate frames (pfNamePlateN)
--   2. Vanilla nameplate frames via WorldFrame
--   3. All WorldFrame children brute-force
----------------------------------------------

local seenGuid = {}
local TryAddEnemy

local function SafeGetNameArg(frame)
    if not frame or type(frame.GetName) ~= "function" then return nil end
    local ok, value = pcall(function()
        return frame:GetName(1)
    end)
    if ok then
        return value
    end
    return nil
end

local function GetGuidCandidate(value)
    if value == nil then return nil end
    if type(value) ~= "string" then
        value = tostring(value)
    end
    if value == "" then return nil end
    return value
end

local function GuidExists(guid)
    local okEx, exists = pcall(UnitExists, guid)
    if okEx and exists then
        return true
    end
    return false
end

local function GetFrameGuid(frame)
    local guid = GetGuidCandidate(SafeGetNameArg(frame))
    if not guid then return nil end
    if GuidExists(guid) then
        return guid
    end
    return nil
end

local function AddFrameGuid(frame)
    local guid = GetFrameGuid(frame)
    if guid then
        TryAddEnemy(guid)
    end
end

TryAddEnemy = function(guid)
    guid = GetGuidCandidate(guid)
    if not guid then return end
    if seenGuid[guid] then return end

    if not GuidExists(guid) then return end

    -- hostile check
    local okAtk, canAtk = pcall(UnitCanAttack, "player", guid)
    if not okAtk or not canAtk then return end

    -- dead check
    local okDead, isDead = pcall(UnitIsDead, guid)
    if okDead and isDead then return end

    -- combat check: try mob first, fall back to player combat state
    local playerInCombat = UnitAffectingCombat("player")
    local inCombat = false
    local okC, affC = pcall(UnitAffectingCombat, guid)
    if okC and affC then
        inCombat = true
    elseif playerInCombat then
        inCombat = true
    end
    if not inCombat then return end

    -- distance
    local dist = GetDistance(guid)
    if not dist or dist > (FarTabDB.maxRange or 100) then return end

    local okN, name = pcall(UnitName, guid)
    if not okN or not name then name = "?" end

    seenGuid[guid] = true
    table.insert(enemies, { guid = guid, name = name, dist = dist })
end

local function ScanFrameChildren(frame, depth, visited)
    if not frame or depth < 0 then return end
    if visited[frame] then return end
    visited[frame] = true

    AddFrameGuid(frame)

    if depth == 0 or type(frame.GetNumChildren) ~= "function" then
        return
    end

    local okCount, count = pcall(function()
        return frame:GetNumChildren()
    end)
    if not okCount or not count or count < 1 then
        return
    end

    local okChildren, children = pcall(function()
        return { frame:GetChildren() }
    end)
    if not okChildren or not children then
        return
    end

    for i = 1, count do
        ScanFrameChildren(children[i], depth - 1, visited)
    end
end

local function ScanNameplates()
    enemies = {}
    seenGuid = {}
    if not superwow then return end

    -- Method 1: scan pfUI nameplate frames directly (pfNamePlate1, pfNamePlate2, ...)
    for idx = 1, 40 do
        local pfPlate = getglobal("pfNamePlate" .. tostring(idx))
        if pfPlate and pfPlate.parent then
            AddFrameGuid(pfPlate.parent)
        end
    end

    -- Method 2/3: recursively scan WorldFrame descendants.
    ScanFrameChildren(WorldFrame, 3, {})

    table.sort(enemies, function(a, b) return a.dist > b.dist end)
end

local function PrintDebugWorldFrame(verbose)
    local okCount, wfCount = pcall(function()
        return WorldFrame:GetNumChildren()
    end)
    if not okCount or not wfCount or wfCount < 1 then
        Print("WorldFrame children: 0")
        return
    end

    local children = { WorldFrame:GetChildren() }
    local candidateCount = 0

    for i = 1, wfCount do
        local frame = children[i]
        if frame then
            local raw = SafeGetNameArg(frame)
            local guid = GetGuidCandidate(raw)
            local exists = guid and GuidExists(guid) or false
            local has0x = guid and string.find(guid, "^0x") and true or false

            if guid then
                candidateCount = candidateCount + 1
            end

            if verbose or guid then
                DEFAULT_CHAT_FRAME:AddMessage(
                    "  WF[" .. tostring(i) .. "] name1=" .. tostring(guid) ..
                    " exists=" .. tostring(exists) ..
                    " old0x=" .. tostring(has0x)
                )
            end
        end
    end

    Print("WorldFrame children: " .. tostring(wfCount) .. " | name1 candidates: " .. tostring(candidateCount))
end

----------------------------------------------
-- Combat Log Fallback (no SuperWoW)
----------------------------------------------

local knownEnemies = {}

local combatFrame = CreateFrame("Frame", "FarTabCombatLog")
local combatEvents = {
    "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS",
    "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES",
    "CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS",
    "CHAT_MSG_COMBAT_CREATURE_VS_PARTY_MISSES",
    "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
    "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
    "CHAT_MSG_COMBAT_HOSTILE_DEATH",
    "PLAYER_REGEN_ENABLED",
}

for _, ev in ipairs(combatEvents) do
    combatFrame:RegisterEvent(ev)
end

combatFrame:SetScript("OnEvent", function()
    if event == "PLAYER_REGEN_ENABLED" then
        knownEnemies = {}
        return
    end
    if event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
        local _, _, name = string.find(arg1, "(.+) dies")
        if name then knownEnemies[name] = nil end
        return
    end
    if arg1 then
        local _, _, name = string.find(arg1, "^(.-)%s+hit")
        if not name then _, _, name = string.find(arg1, "^(.-)%s+miss") end
        if not name then _, _, name = string.find(arg1, "^(.-)%s+attack") end
        if not name then _, _, name = string.find(arg1, "^(.-)'s ") end
        if name and name ~= "" then
            knownEnemies[name] = true
        end
    end
end)

local function ScanCombatLog()
    enemies = {}
    local savedTarget = UnitName("target")
    local hadTarget = UnitExists("target")

    for name, _ in pairs(knownEnemies) do
        TargetByName(name, true)
        if UnitExists("target") and UnitName("target") == name then
            if UnitCanAttack("player", "target")
               and not UnitIsDead("target")
               and UnitAffectingCombat("target")
            then
                local dist = GetDistance("target")
                if dist and dist <= (FarTabDB.maxRange or 100) then
                    table.insert(enemies, { guid = nil, name = name, dist = dist })
                end
            end
        end
    end

    if hadTarget and savedTarget then
        TargetByName(savedTarget, true)
    else
        ClearTarget()
    end

    table.sort(enemies, function(a, b) return a.dist > b.dist end)
end

----------------------------------------------
-- Scan
----------------------------------------------

local function RefreshEnemies()
    local now = GetTime()
    if now - lastScanTime < 0.15 then return end
    lastScanTime = now

    if superwow then
        ScanNameplates()
    else
        ScanCombatLog()
    end
end

----------------------------------------------
-- Targeting
----------------------------------------------

local function TargetEnemy(entry)
    if not entry then return end
    if superwow and entry.guid then
        TargetUnit(entry.guid)
    else
        TargetByName(entry.name, true)
    end
    if FarTabDB.showChat then
        local yd = format("%.0f", entry.dist)
        Print(entry.name .. " (" .. yd .. " yd) [" .. tostring(cycleIdx) .. "/" .. tostring(getn(enemies)) .. "]")
    end
end

function FarTab_CycleNext()
    if not FarTabDB.enabled then return end
    RefreshEnemies()
    local n = getn(enemies)
    if n == 0 then return end
    cycleIdx = cycleIdx + 1
    if cycleIdx > n then cycleIdx = 1 end
    TargetEnemy(enemies[cycleIdx])
end

function FarTab_CyclePrev()
    if not FarTabDB.enabled then return end
    RefreshEnemies()
    local n = getn(enemies)
    if n == 0 then return end
    cycleIdx = cycleIdx - 1
    if cycleIdx < 1 then cycleIdx = n end
    TargetEnemy(enemies[cycleIdx])
end

function FarTab_TargetFurthest()
    if not FarTabDB.enabled then return end
    RefreshEnemies()
    if getn(enemies) == 0 then return end
    cycleIdx = 1
    TargetEnemy(enemies[1])
end

----------------------------------------------
-- Events
----------------------------------------------

local frame = CreateFrame("Frame", "FarTabFrame", UIParent)
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" then
        EnsureDB()
        if SetAutoloot or SUPERWOW_VERSION then
            superwow = true
        end
        initialized = true
        Print("v" .. ADDON_VERSION .. " loaded." .. (superwow and " SuperWoW detected." or " |cffff4444No SuperWoW - using combat log fallback.|r"))
        Print("Type |cff00ccff/ft|r for commands.")
    elseif event == "PLAYER_REGEN_ENABLED" then
        enemies = {}
        cycleIdx = 0
    end
end)

----------------------------------------------
-- Slash Commands
----------------------------------------------

local function HandleSlash(msg)
    msg = string.lower(msg or "")
    if msg == "toggle" then
        FarTabDB.enabled = not FarTabDB.enabled
        Print(FarTabDB.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r")
    elseif msg == "status" then
        Print("SuperWoW=" .. tostring(superwow) .. " | Enabled=" .. tostring(FarTabDB.enabled) .. " | MaxRange=" .. tostring(FarTabDB.maxRange))
    elseif msg == "debug" or msg == "debug2" then
        Print("|cffffd700Debug scan:|r")
        Print("SuperWoW=" .. tostring(superwow) .. " | PlayerInCombat=" .. tostring(UnitAffectingCombat("player")))
        -- check pfUI plates
        local pfCount = 0
        for idx = 1, 40 do
            local pfPlate = getglobal("pfNamePlate" .. tostring(idx))
            if pfPlate then
                pfCount = pfCount + 1
                local pguid = ""
                if pfPlate.parent then
                    local g = SafeGetNameArg(pfPlate.parent)
                    if g then pguid = tostring(g) end
                end
                local vis = pfPlate:IsVisible() and "vis" or "hid"
                DEFAULT_CHAT_FRAME:AddMessage("  pfNamePlate" .. tostring(idx) .. " [" .. vis .. "] guid=" .. tostring(pguid))
            end
        end
        Print("pfUI plates found: " .. tostring(pfCount))
        PrintDebugWorldFrame(msg == "debug2")
        -- run actual scan
        RefreshEnemies()
        Print("Enemies found: " .. tostring(getn(enemies)))
    elseif msg == "range" or msg == "list" then
        RefreshEnemies()
        if getn(enemies) == 0 then
            Print("No enemies in combat.")
        else
            for i, e in ipairs(enemies) do
                DEFAULT_CHAT_FRAME:AddMessage("  " .. tostring(i) .. ". " .. tostring(e.name) .. " - " .. format("%.1f", e.dist) .. " yd")
            end
        end
    else
        if FarTab.ToggleOptions then
            FarTab.ToggleOptions()
        else
            Print("|cffffd700FarTab Commands:|r")
            DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/ft|r - Open settings")
            DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/ft toggle|r - Enable/disable")
            DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/ft status|r - Show status")
            DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/ft list|r - List enemies by distance")
            DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/ft debug|r - Show detected GUID candidates")
            DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/ft debug2|r - Dump every WorldFrame child")
        end
    end
end

SLASH_FARTAB1 = "/ft"
SLASH_FARTAB2 = "/fartab"
SlashCmdList["FARTAB"] = HandleSlash

----------------------------------------------
-- Binding Names
----------------------------------------------

BINDING_HEADER_FARTAB = "FarTab (Reverse Tab-Target)"
BINDING_NAME_FARTAB_CYCLE = "Cycle Furthest -> Closest"
BINDING_NAME_FARTAB_REVERSE = "Cycle Closest -> Furthest"
BINDING_NAME_FARTAB_FURTHEST = "Target Furthest Enemy"

----------------------------------------------
-- Public API
----------------------------------------------

function FarTab.IsEnabled() return FarTabDB and FarTabDB.enabled end
function FarTab.GetVersion() return ADDON_VERSION end
function FarTab.GetEnemies() return enemies end
function FarTab.HasSuperWoW() return superwow end
