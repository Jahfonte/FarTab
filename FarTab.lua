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
----------------------------------------------

local function ScanNameplates()
    enemies = {}
    if not superwow then return end

    local numChildren = WorldFrame:GetNumChildren()
    if numChildren == 0 then return end

    local children = { WorldFrame:GetChildren() }
    for i = 1, numChildren do
        local plate = children[i]
        if plate and plate:IsVisible() and plate.GetName then
            local guid = plate:GetName(1)
            if guid and guid ~= "" and UnitExists(guid) then
                if UnitCanAttack("player", guid)
                   and not UnitIsDead(guid)
                   and not UnitIsFriend("player", guid)
                   and UnitAffectingCombat(guid)
                then
                    local dist = GetDistance(guid)
                    if dist and dist <= (FarTabDB.maxRange or 100) then
                        local name = UnitName(guid) or "?"
                        table.insert(enemies, { guid = guid, name = name, dist = dist })
                    end
                end
            end
        end
    end

    table.sort(enemies, function(a, b) return a.dist > b.dist end)
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
        Print(entry.name .. " (" .. yd .. " yd) [" .. cycleIdx .. "/" .. getn(enemies) .. "]")
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
    elseif msg == "range" or msg == "list" then
        RefreshEnemies()
        if getn(enemies) == 0 then
            Print("No enemies in combat.")
        else
            for i, e in ipairs(enemies) do
                DEFAULT_CHAT_FRAME:AddMessage("  " .. i .. ". " .. e.name .. " - " .. format("%.1f", e.dist) .. " yd")
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
