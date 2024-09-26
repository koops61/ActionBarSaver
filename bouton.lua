-- Créer un bouton autour de la minimap
local minimapButton = CreateFrame("Button", "ABSMinimapButton", Minimap)
minimapButton:SetSize(32, 32) -- Taille du bouton
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT") -- Position initiale

-- Ajouter une texture à l'icône du bouton
minimapButton.icon = minimapButton:CreateTexture(nil, "BACKGROUND")
minimapButton.icon:SetTexture("Interface\\Icons\\abs3.png") -- Chemin vers l'icône
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
        -- Clic droit pour vérifier les mises à jour manuellement
        checkForUpdate()
    end
end)

-- Tooltip pour le bouton minimap
minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("ActionBarSaver")
    GameTooltip:AddLine("Clic gauche pour ouvrir l'interface")
    GameTooltip:AddLine("Clic droit pour vérifier les mises à jour")
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

-- Interface utilisateur pour afficher la version actuelle et le bouton CheckUpdate
local function CreateUpdateFrame()
    local frame = CreateFrame("Frame", "ABSUpdateFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(200, 100)
    frame:SetPoint("CENTER", UIParent, "CENTER")

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
    frame.title:SetText("ActionBarSaver")

    -- Texte pour afficher la version actuelle
    frame.versionText = frame:CreateFontString(nil, "OVERLAY")
    frame.versionText:SetFontObject("GameFontHighlight")
    frame.versionText:SetPoint("TOPLEFT", 10, -30)
    frame.versionText:SetText("Version actuelle: " .. currentVersion)

    -- Bouton CheckUpdate
    local checkButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    checkButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
    checkButton:SetSize(100, 30)
    checkButton:SetText("CheckUpdate")
    checkButton:SetNormalFontObject("GameFontNormalLarge")
    checkButton:SetHighlightFontObject("GameFontHighlightLarge")

    -- Action du bouton
    checkButton:SetScript("OnClick", function()
        checkForUpdate()
    end)

    frame:Hide() -- Par défaut, l'interface est cachée

    return frame
end

-- Créer le cadre d'UI pour les mises à jour au lancement
ABSUIFrame = CreateUpdateFrame()
