----------------------------------------------
-- FarTab - Options Panel
-- Glass-style UI with keybind capture
----------------------------------------------

local _G = _G or getfenv(0)

local glassBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local sectionBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 9,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

----------------------------------------------
-- Helpers
----------------------------------------------

local function CreateSectionHeader(parent, text, yOffset)
    local header = parent:CreateFontString(nil, "OVERLAY")
    header:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    header:SetTextColor(1, 0.82, 0, 1)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, yOffset)
    header:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(1, 0.82, 0, 0.3)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    line:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
    return header
end

local function CreateCB(name, parent, text, tooltip, onClick)
    local cb = CreateFrame("CheckButton", "FT_CB_" .. name, parent, "UICheckButtonTemplate")
    cb:SetWidth(22)
    cb:SetHeight(22)
    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    label:SetText(text)
    label:SetTextColor(0.9, 0.9, 0.9, 1)
    cb.label = label
    if tooltip then
        cb:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:AddLine(text, 1, 1, 1)
            GameTooltip:AddLine(tooltip, 0.7, 0.7, 0.7, 1)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    cb:SetScript("OnClick", function()
        if onClick then onClick(this:GetChecked() and true or false) end
    end)
    return cb
end

----------------------------------------------
-- Keybind Capture Button
----------------------------------------------

local activeCapture = nil

local mousebuttonmap = {
    LeftButton = "BUTTON1",
    RightButton = "BUTTON2",
    MiddleButton = "BUTTON3",
    Button4 = "BUTTON4",
    Button5 = "BUTTON5",
}

local function GetModPrefix()
    local prefix = ""
    if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsAltKeyDown() then prefix = prefix .. "ALT-" end
    return prefix
end

local function CreateKeybindButton(name, parent, label, bindingName, yPos)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(24)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, yPos)
    row:SetPoint("RIGHT", parent, "RIGHT", -14, 0)

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
    lbl:SetText(label)
    lbl:SetTextColor(0.9, 0.9, 0.9, 1)

    local btn = CreateFrame("Button", "FT_Bind_" .. name, row)
    btn:SetWidth(140)
    btn:SetHeight(22)
    btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    btn:SetBackdrop(sectionBackdrop)
    btn:SetBackdropColor(0.1, 0.1, 0.15, 0.9)
    btn:SetBackdropBorderColor(0.5, 0.5, 0.6, 0.8)
    btn:EnableKeyboard(false)

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btnText:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.text = btnText
    btn.bindingName = bindingName

    local function UpdateLabel()
        local key1 = GetBindingKey(bindingName)
        if key1 then
            btnText:SetText("|cff00ff00" .. GetBindingText(key1, "KEY_", 1) .. "|r")
        else
            btnText:SetText("|cff888888Not Bound|r")
        end
    end

    local function StopCapture()
        btn:EnableKeyboard(false)
        btn:SetBackdropBorderColor(0.5, 0.5, 0.6, 0.8)
        btn:SetScript("OnKeyDown", nil)
        btn:SetScript("OnMouseDown", nil)
        activeCapture = nil
        UpdateLabel()
    end

    local function HandleKey(key)
        if key == "ESCAPE" then
            -- unbind
            local existing = GetBindingKey(bindingName)
            if existing then
                SetBinding(existing)
                SaveBindings(GetCurrentBindingSet())
            end
            StopCapture()
            return
        end

        -- ignore modifier-only keys
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
            return
        end

        local prefix = GetModPrefix()
        local fullKey = prefix .. key
        SetBinding(fullKey, bindingName)
        SaveBindings(GetCurrentBindingSet())
        StopCapture()
    end

    btn:SetScript("OnClick", function()
        if activeCapture and activeCapture ~= btn then
            -- cancel other capture
            activeCapture:EnableKeyboard(false)
            activeCapture:SetBackdropBorderColor(0.5, 0.5, 0.6, 0.8)
            activeCapture:SetScript("OnKeyDown", nil)
            activeCapture:SetScript("OnMouseDown", nil)
        end

        activeCapture = btn
        btnText:SetText("|cffffd700Press a key...|r")
        btn:SetBackdropBorderColor(1, 0.82, 0, 1)
        btn:EnableKeyboard(true)

        btn:SetScript("OnKeyDown", function()
            HandleKey(arg1)
        end)

        btn:SetScript("OnMouseDown", function()
            local mapped = mousebuttonmap[arg1]
            if mapped then
                local prefix = GetModPrefix()
                SetBinding(prefix .. mapped, bindingName)
                SaveBindings(GetCurrentBindingSet())
                StopCapture()
            end
        end)
    end)

    -- Clear button
    local clearBtn = CreateFrame("Button", nil, row)
    clearBtn:SetWidth(18)
    clearBtn:SetHeight(18)
    clearBtn:SetPoint("LEFT", btn, "RIGHT", 4, 0)

    local clearText = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clearText:SetPoint("CENTER", clearBtn, "CENTER", 0, 0)
    clearText:SetText("|cffff4444X|r")
    clearBtn:SetScript("OnClick", function()
        local existing = GetBindingKey(bindingName)
        if existing then
            SetBinding(existing)
            SaveBindings(GetCurrentBindingSet())
        end
        UpdateLabel()
    end)
    clearBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Clear keybind", 1, 0.3, 0.3)
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn.Update = UpdateLabel
    UpdateLabel()
    return btn
end

----------------------------------------------
-- Main Options Frame
----------------------------------------------

local optionsFrame = nil
local keybindButtons = {}

local function CreateOptionsFrame()
    if optionsFrame then return optionsFrame end

    local f = CreateFrame("Frame", "FarTabOptionsFrame", UIParent)
    f:SetWidth(360)
    f:SetHeight(340)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetBackdrop(glassBackdrop)
    f:SetBackdropColor(0.03, 0.05, 0.1, 0.92)
    f:SetBackdropBorderColor(0, 0.6, 0.8, 0.9)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    titleBar:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", tile = true, tileSize = 16 })
    titleBar:SetBackdropColor(0, 0.1, 0.15, 0.8)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetText("|cff00ccffFarTab|r |cff888888v1.0.0|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local yPos = -42

    -- === General ===
    CreateSectionHeader(f, "General", yPos)
    yPos = yPos - 22

    local cbEnabled = CreateCB("Enabled", f, "Enabled",
        "Enable or disable FarTab targeting.",
        function(checked) FarTabDB.enabled = checked end)
    cbEnabled:SetPoint("TOPLEFT", f, "TOPLEFT", 14, yPos)
    f.cbEnabled = cbEnabled

    local cbChat = CreateCB("Chat", f, "Show target in chat",
        "Print targeted enemy name and distance to chat.",
        function(checked) FarTabDB.showChat = checked end)
    cbChat:SetPoint("TOPLEFT", f, "TOPLEFT", 180, yPos)
    f.cbChat = cbChat

    yPos = yPos - 24

    local cbMinimap = CreateCB("Minimap", f, "Show minimap button",
        "Toggle minimap button visibility.",
        function(checked)
            FarTabDB.showMinimap = checked
            if FarTab.minimapButton then
                if checked then FarTab.minimapButton:Show() else FarTab.minimapButton:Hide() end
            end
        end)
    cbMinimap:SetPoint("TOPLEFT", f, "TOPLEFT", 14, yPos)
    f.cbMinimap = cbMinimap

    yPos = yPos - 30

    -- === Max Range ===
    local rangeLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rangeLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 14, yPos)
    rangeLbl:SetText("Max Range (yards):")
    rangeLbl:SetTextColor(0.9, 0.9, 0.9, 1)

    local rangeEB = CreateFrame("EditBox", "FT_EB_Range", f)
    rangeEB:SetWidth(50)
    rangeEB:SetHeight(20)
    rangeEB:SetPoint("LEFT", rangeLbl, "RIGHT", 10, 0)
    rangeEB:SetFontObject(GameFontHighlightSmall)
    rangeEB:SetAutoFocus(false)
    rangeEB:SetMaxLetters(4)

    local rangeBG = CreateFrame("Frame", nil, rangeEB)
    rangeBG:SetPoint("TOPLEFT", rangeEB, "TOPLEFT", -4, 2)
    rangeBG:SetPoint("BOTTOMRIGHT", rangeEB, "BOTTOMRIGHT", 4, -2)
    rangeBG:SetBackdrop(sectionBackdrop)
    rangeBG:SetBackdropColor(0.05, 0.05, 0.1, 0.9)
    rangeBG:SetBackdropBorderColor(0.4, 0.4, 0.5, 0.8)
    rangeBG:SetFrameLevel(rangeEB:GetFrameLevel() - 1)

    rangeEB:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    rangeEB:SetScript("OnEnterPressed", function()
        local val = tonumber(this:GetText())
        if val and val > 0 and val <= 200 then
            FarTabDB.maxRange = val
        else
            this:SetText(tostring(FarTabDB.maxRange or 100))
        end
        this:ClearFocus()
    end)
    f.rangeEB = rangeEB

    yPos = yPos - 34

    -- === Keybinds ===
    CreateSectionHeader(f, "Keybinds (click to set, ESC to unbind)", yPos)
    yPos = yPos - 26

    local kb1 = CreateKeybindButton("Cycle", f, "Cycle Furthest -> Closest", "FARTAB_CYCLE", yPos)
    table.insert(keybindButtons, kb1)
    yPos = yPos - 28

    local kb2 = CreateKeybindButton("Reverse", f, "Cycle Closest -> Furthest", "FARTAB_REVERSE", yPos)
    table.insert(keybindButtons, kb2)
    yPos = yPos - 28

    local kb3 = CreateKeybindButton("Furthest", f, "Target Furthest Enemy", "FARTAB_FURTHEST", yPos)
    table.insert(keybindButtons, kb3)
    yPos = yPos - 34

    -- === Status ===
    CreateSectionHeader(f, "Status", yPos)
    yPos = yPos - 22

    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", f, "TOPLEFT", 14, yPos)
    statusText:SetTextColor(0.7, 0.7, 0.7, 1)
    f.statusText = statusText

    f:Hide()
    optionsFrame = f
    return f
end

local function RefreshOptions()
    if not optionsFrame then return end
    optionsFrame.cbEnabled:SetChecked(FarTabDB.enabled)
    optionsFrame.cbChat:SetChecked(FarTabDB.showChat)
    optionsFrame.cbMinimap:SetChecked(FarTabDB.showMinimap)
    optionsFrame.rangeEB:SetText(tostring(FarTabDB.maxRange or 100))

    local sw = FarTab.HasSuperWoW and FarTab.HasSuperWoW() or false
    optionsFrame.statusText:SetText(
        "SuperWoW: " .. (sw and "|cff00ff00Yes|r" or "|cffff4444No (combat log fallback)|r") ..
        "    |    Enemies tracked: " .. tostring(table.getn(FarTab.GetEnemies and FarTab.GetEnemies() or {}))
    )

    for _, btn in ipairs(keybindButtons) do
        if btn.Update then btn.Update() end
    end
end

function FarTab.ToggleOptions()
    local f = CreateOptionsFrame()
    if f:IsShown() then
        f:Hide()
    else
        RefreshOptions()
        f:Show()
    end
end
