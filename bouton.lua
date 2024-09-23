-- Créer un bouton autour de la minimap
local minimapButton = CreateFrame("Button", "ABSMinimapButton", Minimap)
minimapButton:SetSize(32, 32) -- Taille du bouton
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT") -- Position initiale

-- Ajouter une texture à l'icône du bouton
minimapButton.icon = minimapButton:CreateTexture(nil, "BACKGROUND")
minimapButton.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") -- Chemin vers l'icône
minimapButton.icon:SetSize(20, 20)
minimapButton.icon:SetPoint("CENTER")

-- Ajouter une texture pour l'arrière-plan (optionnel)
minimapButton.background = minimapButton:CreateTexture(nil, "OVERLAY")
minimapButton.background:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
minimapButton.background:SetSize(54, 54)
minimapButton.background:SetPoint("TOPLEFT")

-- Gestion des clics sur le bouton
minimapButton:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        -- Ouvre ou ferme l'interface utilisateur avec un clic gauche
        if ABSUIFrame then
            if ABSUIFrame:IsShown() then
                ABSUIFrame:Hide()
            else
                ABSUIFrame:Show()
            end
        end
    elseif button == "RightButton" then
        -- Clic droit pour les options ou autre
        print("Clic droit : Options")
    end
end)

-- Tooltip pour le bouton minimap
minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("ActionBarSaver")
    GameTooltip:AddLine("Clic gauche pour ouvrir l'interface")
    GameTooltip:AddLine("Clic droit pour les options")
    GameTooltip:Show()
end)

minimapButton:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

-- Fonction pour gérer la position du bouton autour de la minimap
local function UpdateMinimapButtonPosition()
    local xpos = 80 * cos(60) -- Modifiez l'angle (45) pour la position autour de la minimap
    local ypos = 80 * sin(60)
    minimapButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT", xpos, ypos)
end

-- Appel de la fonction de mise à jour pour initialiser la position
UpdateMinimapButtonPosition()
