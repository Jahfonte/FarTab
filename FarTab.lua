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
-- Nameplate Detection
----------------------------------------------

local function IsNamePlate(frame)
    if not frame then return false end
    -- Method 1: check frame type (vanilla nameplates are Buttons)
    local ok, otype = pcall(frame.GetObjectType, frame)
    if not ok or otype ~= "Button" then return false end
    -- Method 2: check for nameplate border texture
    local ok2, region = pcall(frame.GetRegions, frame)
    if ok2 and region then
        local ok3, tex = pcall(region.GetTexture, region)
        if ok3 and tex == "Interface\\Tooltips\\Nameplate-Border" then return true end
    end
    -- Method 3: check for healthbar child (nameplates always have one)
    local ok4, child1 = pcall(frame.GetChildren, frame)
    if ok4 and child1 then
        local ok5, ctype = pcall(child1.GetObjectType, child1)
        if ok5 and ctype == "StatusBar" then return true end
    end
    return false
end

local function IsHostileColor(r, g, b)
    -- red = hostile NPC, red-ish = hostile player
    if r and r > 0.7 and g and g < 0.3 and b and b < 0.3 then return true end
    return false
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
        if plate and plate:IsVisible() and IsNamePlate(plate) then
            -- get SuperWoW GUID from the vanilla nameplate frame
            local ok, guid = pcall(plate.GetName, plate, 1)
            if ok and guid and guid ~= "" then
                -- check unit exists via multiple methods
                local exists = false
                if pcall(UnitExists, guid) then exists = UnitExists(guid) end

                if exists then
                    -- hostile check: try UnitCanAttack, fall back to healthbar color
                    local hostile = false
                    local okAtk, canAtk = pcall(UnitCanAttack, "player", guid)
                    if okAtk and canAtk then
                        hostile = true
                    else
                        -- fallback: check healthbar color (red = hostile)
                        local okChild, hpbar = pcall(plate.GetChildren, plate)
                        if okChild and hpbar then
                            local okColor, r, g, b = pcall(hpbar.GetStatusBarColor, hpbar)
                            if okColor then hostile = IsHostileColor(r, g, b) end
                        end
                    end

                    -- dead check
                    local dead = false
                    local okDead, isDead = pcall(UnitIsDead, guid)
                    if okDead then dead = isDead end

                    -- combat check: try UnitAffectingCombat, fall back to player combat state
                    local inCombat = false
                    local okCombat, affCombat = pcall(UnitAffectingCombat, guid)
                    if okCombat and affCombat then
                        inCombat = true
                    else
                        -- fallback: if player is in combat and mob is hostile + not dead, assume in combat
                        if UnitAffectingCombat("player") then
                            inCombat = true
                        end
                    end

                    if hostile and not dead and inCombat then
                        local dist = GetDistance(guid)
                        if dist and dist <= (FarTabDB.maxRange or 100) then
                            local okName, name = pcall(UnitName, guid)
                            if not okName or not name then name = "?" end
                            table.insert(enemies, { guid = guid, name = name, dist = dist })
                        end
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
