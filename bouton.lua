--[[
    ActionBarSaver 3 - Minimap Button (WotLK 3.3.5a compatible)
]]

local ABS = select(2, ...)
local L = ABS.locals

local minimapButton = CreateFrame("Button", "ABSMinimapButton", Minimap)
minimapButton:SetWidth(32)
minimapButton:SetHeight(32)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:EnableMouse(true)
minimapButton:SetMovable(true)

-- Icon texture (using 128x128 32-bit TGA compatible with 3.3.5)
minimapButton.icon = minimapButton:CreateTexture(nil, "BACKGROUND")
minimapButton.icon:SetTexture("Interface\\AddOns\\ActionBarSaver\\Icons\\abs3.tga")
minimapButton.icon:SetWidth(20)
minimapButton.icon:SetHeight(20)
minimapButton.icon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)

-- Border texture
minimapButton.border = minimapButton:CreateTexture(nil, "OVERLAY")
minimapButton.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
minimapButton.border:SetWidth(54)
minimapButton.border:SetHeight(54)
minimapButton.border:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 0, 0)

-- Highlight texture
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Position helper
local function UpdatePosition()
    local angle = math.rad((ActionBarSaverDB and ActionBarSaverDB.minimapPos) or 215)
    local radius = 80
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Dragging around Minimap
minimapButton:RegisterForDrag("LeftButton")
minimapButton:SetScript("OnDragStart", function(self)
    self.isDragging = true
    self:SetScript("OnUpdate", function(self)
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        local deg = math.deg(math.atan2(py - my, px - mx))
        if deg < 0 then deg = deg + 360 end
        if ActionBarSaverDB then
            ActionBarSaverDB.minimapPos = deg
        end
        UpdatePosition()
    end)
end)

minimapButton:SetScript("OnDragStop", function(self)
    self.isDragging = false
    self:SetScript("OnUpdate", nil)
end)

-- Click handling
minimapButton:SetScript("OnClick", function(self, button)
    if self.isDragging then return end

    if button == "LeftButton" then
        if SlashCmdList["ABSUI"] then
            SlashCmdList["ABSUI"]()
        end
    elseif button == "RightButton" then
        -- Quick restore for current talent spec if configured, or print current profile info
        if ABS and ABS.RestoreActiveSpecProfile then
            ABS:RestoreActiveSpecProfile()
        else
            if SlashCmdList["ABSUI"] then
                SlashCmdList["ABSUI"]()
            end
        end
    end
end)

-- Tooltip
minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(L["MINIMAP_TOOLTIP_TITLE"], 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffffff" .. L["MINIMAP_TOOLTIP_L1"] .. "|r")
    GameTooltip:AddLine("|cffffffff" .. L["MINIMAP_TOOLTIP_L2"] .. "|r")
    GameTooltip:AddLine("|cffaaaaaa" .. L["MINIMAP_TOOLTIP_L3"] .. "|r")
    
    -- Show active spec info if available
    local spec = GetActiveTalentGroup and GetActiveTalentGroup() or 1
    if ActionBarSaverDB and ActionBarSaverDB.dualSpec and ActionBarSaverDB.dualSpec.enable then
        local playerClass = select(2, UnitClass("player"))
        local classSpecs = ActionBarSaverDB.dualSpec[playerClass]
        local currentProfile = classSpecs and classSpecs[spec]
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("Spé %d : |cff00ff00%s|r", spec, currentProfile or L["NONE"]), 0.9, 0.9, 0.9)
    end
    
    GameTooltip:Show()
end)

minimapButton:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

-- Initialization on load
local loader = CreateFrame("Frame")
loader:RegisterEvent("VARIABLES_LOADED")
loader:SetScript("OnEvent", function(self, event)
    UpdatePosition()
    self:UnregisterEvent("VARIABLES_LOADED")
end)
