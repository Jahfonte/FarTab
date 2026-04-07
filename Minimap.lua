----------------------------------------------
-- FarTab - Minimap Button
----------------------------------------------

local function ensureOpts()
    if not FarTabDB or type(FarTabDB) ~= "table" then FarTabDB = {} end
    if FarTabDB.showMinimap == nil then FarTabDB.showMinimap = true end
    if type(FarTabDB.minimapAngle) ~= "number" then FarTabDB.minimapAngle = 160 end
end

local btn = CreateFrame("Button", "FarTabMinimapButton", Minimap)
btn:SetWidth(31)
btn:SetHeight(31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
btn:RegisterForClicks("AnyUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local overlay = btn:CreateTexture(nil, "OVERLAY")
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
overlay:SetWidth(53)
overlay:SetHeight(53)
overlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

local icon = btn:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\Icons\\Ability_Hunter_Quickshot")
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
icon:SetWidth(20)
icon:SetHeight(20)
icon:SetPoint("CENTER", btn, "CENTER", 0, 0)

local function updatePos()
    ensureOpts()
    local a = FarTabDB.minimapAngle
    local radius = 80
    local x = math.cos(math.rad(a)) * radius
    local y = math.sin(math.rad(a)) * radius
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

btn:SetScript("OnDragStart", function()
    btn.wasDragging = nil
    btn.isDragging = true
    btn:SetScript("OnUpdate", function()
        ensureOpts()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx = cx / scale
        cy = cy / scale
        local dx = cx - mx
        local dy = cy - my
        local ang
        if math.atan2 then
            ang = math.deg(math.atan2(dy, dx))
        else
            local a
            if dx == 0 then
                if dy > 0 then a = math.pi / 2 elseif dy < 0 then a = -math.pi / 2 else a = 0 end
            else
                a = math.atan(dy / dx)
                if dx < 0 then if dy >= 0 then a = a + math.pi else a = a - math.pi end end
            end
            ang = math.deg(a)
        end
        if ang < 0 then ang = ang + 360 end
        FarTabDB.minimapAngle = ang
        updatePos()
    end)
end)

btn:SetScript("OnDragStop", function()
    btn:SetScript("OnUpdate", nil)
    btn.isDragging = nil
    btn.wasDragging = true
    updatePos()
end)

btn:SetScript("OnMouseUp", function()
    if this.isDragging then return end
    if this.wasDragging then this.wasDragging = nil return end
    if arg1 == "LeftButton" then
        if FarTab.ToggleOptions then FarTab.ToggleOptions() end
    elseif arg1 == "RightButton" then
        FarTabDB.enabled = not FarTabDB.enabled
        if FarTabDB.enabled then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffFarTab|r: |cff00ff00Enabled|r")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffFarTab|r: |cffff0000Disabled|r")
        end
    end
end)

btn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff00ccffFarTab|r", 1, 1, 1)
    GameTooltip:AddLine("Reverse Tab-Targeting v1.0.0", 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ")
    if FarTabDB.enabled then
        GameTooltip:AddLine("|cff00ff00Enabled|r", 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine("|cffff0000Disabled|r", 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: Settings", 0.5, 0.8, 1)
    GameTooltip:AddLine("Right-click: Toggle on/off", 0.5, 0.8, 1)
    GameTooltip:AddLine("Drag: Move button", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)

btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

FarTab.minimapButton = btn

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    ensureOpts()
    updatePos()
    if not FarTabDB.showMinimap then btn:Hide() end
end)
