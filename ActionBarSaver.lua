--[[ 
	Action Bar Saver, Shadowed & Koops61
]]
ActionBarSaver = select(2, ...)

local ABS = ActionBarSaver
local L = ABS.locals

local restoreErrors, spellCache, macroCache, macroNameCache, highestRanks = {}, {}, {}, {}, {}
local iconCache, playerClass

local MAX_MACROS = 54
local MAX_CHAR_MACROS = 18
local MAX_GLOBAL_MACROS = 36
local MAX_ACTION_BUTTONS = 144
local POSSESSION_START = 121
local POSSESSION_END = 132


function ABS:OnInitialize()
	local defaults = {
		macro = false,
		checkCount = false,
		restoreRank = true,
		spellSubs = {},
		sets = {}
	}
	
	ActionBarSaverDB = ActionBarSaverDB or {}
		
	-- Load defaults in
	for key, value in pairs(defaults) do
		if( ActionBarSaverDB[key] == nil ) then
			ActionBarSaverDB[key] = value
		end
	end
	
	for classToken in pairs(RAID_CLASS_COLORS) do
		ActionBarSaverDB.sets[classToken] = ActionBarSaverDB.sets[classToken] or {}
	end
	
	self.db = ActionBarSaverDB
	
	playerClass = select(2, UnitClass("player"))
end

-- Text "compression" so it can be stored in our format fine
function ABS:CompressText(text)
	text = string.gsub(text, "\n", "/n")
	text = string.gsub(text, "/n$", "")
	text = string.gsub(text, "||", "/124")
	
	return string.trim(text)
end

function ABS:UncompressText(text)
	text = string.gsub(text, "/n", "\n")
	text = string.gsub(text, "/124", "|")
	
	return string.trim(text)
end

-- Restore a saved profile
function ABS:SaveProfile(name)
	self.db.sets[playerClass][name] = self.db.sets[playerClass][name] or {}
	local set = self.db.sets[playerClass][name]
	
	for actionID=1, MAX_ACTION_BUTTONS do
		set[actionID] = nil
		
		local type, id, subType, extraID = GetActionInfo(actionID)
		if( type and id and ( actionID < POSSESSION_START or actionID > POSSESSION_END ) ) then
			-- DB Format: <type>|<id>|<binding>|<name>|<extra ...>
			-- Save a companion
			if( type == "companion" ) then
				set[actionID] = string.format("%s|%s|%s|%s|%s|%s", type, id, "", name, subType, extraID)
			-- Save an equipment set
			elseif( type == "equipmentset" ) then
				set[actionID] = string.format("%s|%s|%s", type, id, "")
			-- Save an item
			elseif( type == "item" ) then
				set[actionID] = string.format("%s|%d|%s|%s", type, id, "", (GetItemInfo(id)) or "")
			-- Save a spell
			elseif( type == "spell" and id > 0 ) then
				local spell, rank = GetSpellName(id, BOOKTYPE_SPELL)
				if( spell ) then
					set[actionID] = string.format("%s|%d|%s|%s|%s|%s", type, id, "", spell, rank or "", extraID or "")
				end
			-- Save a macro
			elseif( type == "macro" ) then
				local name, icon, macro = GetMacroInfo(id)
				if( name and icon and macro ) then
					set[actionID] = string.format("%s|%d|%s|%s|%s|%s", type, actionID, "", self:CompressText(name), icon, self:CompressText(macro))
				end
			end
		end
	end
	
	self:Print(string.format(L["Saved profile %s!"], name))
end

-- Finds the macroID in case it's changed
function ABS:FindMacro(id, name, data)
	if( macroCache[id] == data ) then
		return id
	end
		
	-- No such luck, check text
	for id, currentMacro in pairs(macroCache) do
		if( currentMacro == data ) then
			return id
		end
	end
	
	-- Still no luck, let us try name
	if( macroNameCache[name] ) then
		return macroNameCache[name]
	end
	
	return nil
end

-- Restore any macros that don't exist
function ABS:RestoreMacros(set)
	local perCharacter = true
	for id, data in pairs(set) do
		local type, id, binding, macroName, macroIcon, macroData = string.split("|", data)
		if( type == "macro" ) then
			-- Do we already have a macro?
			local macroID = self:FindMacro(id, macroName, macroData)
			if( not macroID ) then
				local globalNum, charNum = GetNumMacros()
				-- Make sure we aren't at the limit
				if( globalNum == MAX_GLOBAL_MACROS and charNum == MAX_CHAR_MACROS ) then
					table.insert(restoreErrors, L["Unable to restore macros, you already have 18 global and 18 per character ones created."])
					break

				-- We ran out of space for per character, so use global
				elseif( charNum == MAX_CHAR_MACROS ) then
					perCharacter = false
				end

				-- When creating a macro, we have to pass the icon id not the icon path
				if( not iconCache ) then
					iconCache = {}
					for i=1, GetNumMacroIcons() do
						iconCache[(GetMacroIconInfo(i))] = i
					end
				end
				
				macroName = self:UncompressText(macroName)
				
				-- No macro name means a space has to be used or else it won't be created and saved
				CreateMacro(macroName == "" and " " or macroName, iconCache[macroIcon] or 1, self:UncompressText(macroData), nil, perCharacter)
			end
		end
	end
	
	-- Recache macros due to any additions
	local blacklist = {}
	for i=1, MAX_MACROS do
		local name, icon, macro = GetMacroInfo(i)
		
		if( name ) then
			-- If there are macros with the same name, then blacklist and don't look by name
			if( macroNameCache[name] ) then
				blacklist[name] = true
				macroNameCache[name] = i
			elseif( not blacklist[name] ) then
				macroNameCache[name] = i
			end
		end
		
		macroCache[i] = macro and self:CompressText(macro) or nil
	end
end

-- Restore a saved profile
function ABS:RestoreProfile(name, overrideClass)
	local set = self.db.sets[overrideClass or playerClass][name]
	if( not set ) then
		self:Print(string.format(L["No profile with the name \"%s\" exists."], set))
		return
	elseif( InCombatLockdown() ) then
		self:Print(String.format(L["Unable to restore profile \"%s\", you are in combat."], set))
		return
	end
	
	table.wipe(macroCache)
	table.wipe(spellCache)
	table.wipe(macroNameCache)
	
	-- Cache spells
	for book=1, MAX_SKILLLINE_TABS do
		local _, _, offset, numSpells = GetSpellTabInfo(book)

		for i=1, numSpells do
			local index = offset + i
			local spell, rank = GetSpellName(index, BOOKTYPE_SPELL)
			
			-- This way we restore the max rank of spells
			spellCache[spell] = index
			spellCache[string.lower(spell)] = index
			
			if( rank and rank ~= "" ) then
				spellCache[spell .. rank] = index
			end
		end
	end
		
	
	-- Cache macros
	local blacklist = {}
	for i=1, MAX_MACROS do
		local name, icon, macro = GetMacroInfo(i)
		
		if( name ) then
			-- If there are macros with the same name, then blacklist and don't look by name
			if( macroNameCache[name] ) then
				blacklist[name] = true
				macroNameCache[name] = i
			elseif( not blacklist[name] ) then
				macroNameCache[name] = i
			end
		end
		
		macroCache[i] = macro and self:CompressText(macro) or nil
	end
	
	-- Check if we need to restore any missing macros
	if( self.db.macro ) then
		self:RestoreMacros(set)
	end
	
	-- Start fresh with nothing on the cursor
	ClearCursor()
	
	-- Save current sound setting
	local soundToggle = GetCVar("Sound_EnableAllSound")
	-- Turn sound off
	SetCVar("Sound_EnableAllSound", 0)

	for i=1, MAX_ACTION_BUTTONS do
		if( i < POSSESSION_START or i > POSSESSION_END ) then
			local type, id = GetActionInfo(i)
		
			-- Clear the current spot
			if( id or type ) then
				PickupAction(i)
				ClearCursor()
			end
		
			-- Restore this spot
			if( set[i] ) then
				self:RestoreAction(i, string.split("|", set[i]))
			end
		end
	end
	
	-- Restore old sound setting
	SetCVar("Sound_EnableAllSound", soundToggle)
	
	-- Done!
	if( #(restoreErrors) == 0 ) then
		self:Print(string.format(L["Restored profile %s!"], name))
	else
		self:Print(string.format(L["Restored profile %s, failed to restore %d buttons type /abs errors for more information."], name, #(restoreErrors)))
	end
end

function ABS:RestoreAction(i, type, actionID, binding, ...)
	-- Restore a spell
	if( type == "spell" ) then
		local spellName, spellRank = ...
		if( ( self.db.restoreRank or spellRank == "" ) and spellCache[spellName] ) then
			PickupSpell(spellCache[spellName], BOOKTYPE_SPELL)
		elseif( spellRank ~= "" and spellCache[spellName .. spellRank] ) then
			PickupSpell(spellCache[spellName .. spellRank], BOOKTYPE_SPELL)
		end
		
		if( GetCursorInfo() ~= type ) then
			-- Bad restore, check if we should link at all
			local lowerSpell = string.lower(spellName)
			for spell, linked in pairs(self.db.spellSubs) do
				if( lowerSpell == spell and spellCache[linked] ) then
					self:RestoreAction(i, type, actionID, binding, linked, nil, arg3)
					return
				elseif( lowerSpell == linked and spellCache[spell] ) then
					self:RestoreAction(i, type, actionID, binding, spell, nil, arg3)
					return
				end
			end
			
			table.insert(restoreErrors, string.format(L["Unable to restore spell \"%s\" to slot #%d, it does not appear to have been learned yet."], spellName, i))
			ClearCursor()
			return
		end

		PlaceAction(i)
	-- Restore an equipment set button
	elseif( type == "equipmentset" ) then
		local slotID = -1
		for i=1, GetNumEquipmentSets() do
			if( GetEquipmentSetInfo(i) == actionID ) then
				slotID = i
				break
			end
		end
		
		PickupEquipmentSet(slotID)
		if( GetCursorInfo() ~= "equipmentset" ) then
			table.insert(restoreErrors, string.format(L["Unable to restore equipment set \"%s\" to slot #%d, it does not appear to exist anymore."], actionID, i))
			ClearCursor()
			return
		end
		
		PlaceAction(i)
			
	-- Restore a 3.1 saved companion
	elseif( type == "companion" ) then
		local critterName, critterType, critterID = ...
		PickupCompanion(critterType, actionID)
		if( GetCursorInfo() ~= "companion" ) then
			table.insert(restoreErrors, string.format(L["Unable to restore companion \"%s\" to slot #%d, it does not appear to exist yet."], critterName, i))
			ClearCursor()
			return
		end
		
		PlaceAction(i)
	-- Restore an item
	elseif( type == "item" ) then
		PickupItem(actionID)

		if( GetCursorInfo() ~= type ) then
			local itemName = select(i, ...)
			table.insert(restoreErrors, string.format(L["Unable to restore item \"%s\" to slot #%d, cannot be found in inventory."], itemName and itemName ~= "" and itemName or actionID, i))
			ClearCursor()
			return
		end
		
		PlaceAction(i)
	-- Restore a macro
	elseif( type == "macro" ) then
		local name, _, content = ...
		PickupMacro(self:FindMacro(actionID, name, content or -1))
		if( GetCursorInfo() ~= type ) then
			table.insert(restoreErrors, string.format(L["Unable to restore macro id #%d to slot #%d, it appears to have been deleted."], actionID, i))
			ClearCursor()
			return
		end
		
		PlaceAction(i)
	end
end

function ABS:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ABS|r: " .. msg)
end

SLASH_ACTIONBARSAVER1 = nil
SlashCmdList["ACTIONBARSAVER"] = nil

SLASH_ABS1 = "/abs"
SLASH_ABS2 = "/actionbarsaver"
SlashCmdList["ABS"] = function(msg)
	msg = msg or ""
	
	local cmd, arg = string.split(" ", msg, 2)
	cmd = string.lower(cmd or "")
	arg = string.lower(arg or "")
	
	local self = ABS
	
	-- Profile saving
	if( cmd == "save" and arg ~= "" ) then
		self:SaveProfile(arg)
	
	-- Spell sub
	elseif( cmd == "link" and arg ~= "" ) then
		local first, second = string.match(arg, "\"(.+)\" \"(.+)\"")
		first = string.trim(first or "")
		second = string.trim(second or "")
		
		if( first == "" or second == "" ) then
			self:Print(L["Invalid spells passed, remember you must put quotes around both of them."])
			return
		end
		
		self.db.spellSubs[first] = second
		
		self:Print(string.format(L["Spells \"%s\" and \"%s\" are now linked."], first, second))
		
	-- Profile restoring
	elseif( cmd == "restore" and arg ~= "" ) then
		for i=#(restoreErrors), 1, -1 do table.remove(restoreErrors, i) end
				
		if( not self.db.sets[playerClass][arg] ) then
			self:Print(string.format(L["Cannot restore profile \"%s\", you can only restore profiles saved to your class."], arg))
			return
		end
		
		self:RestoreProfile(arg, playerClass)
		
	-- Profile renaming
	elseif( cmd == "rename" and arg ~= "" ) then
		local old, new = string.split(" ", arg, 2)
		new = string.trim(new or "")
		old = string.trim(old or "")
		
		if( new == old ) then
			self:Print(string.format(L["You cannot rename \"%s\" to \"%s\" they are the same profile names."], old, new))
			return
		elseif( new == "" ) then
			self:Print(string.format(L["No name specified to rename \"%s\" to."], old))
			return
		elseif( self.db.sets[playerClass][new] ) then
			self:Print(string.format(L["Cannot rename \"%s\" to \"%s\" a profile already exists for %s."], old, new, (UnitClass("player"))))
			return
		elseif( not self.db.sets[playerClass][old] ) then
			self:Print(string.format(L["No profile with the name \"%s\" exists."], old))
			return
		end
		
		self.db.sets[playerClass][new] = CopyTable(self.db.sets[playerClass][old])
		self.db.sets[playerClass][old] = nil
		
		self:Print(string.format(L["Renamed \"%s\" to \"%s\""], old, new))
		
	-- Restore errors
	elseif( cmd == "errors" ) then
		if( #(restoreErrors) == 0 ) then
			self:Print(L["No errors found!"])
			return
		end

		self:Print(string.format(L["Errors found: %d"], #(restoreErrors)))
		for _, text in pairs(restoreErrors) do
			DEFAULT_CHAT_FRAME:AddMessage(text)
		end

	-- Delete profile
	elseif( cmd == "delete" ) then
		self.db.sets[playerClass][arg] = nil
		self:Print(string.format(L["Deleted saved profile %s."], arg))
	
	-- List profiles
	elseif( cmd == "list" ) then
		local classes = {}
		local setList = {}
		
		for class, sets in pairs(self.db.sets) do
			table.insert(classes, class)
		end
		
		table.sort(classes, function(a, b)
			return a < b
		end)
		
		for _, class in pairs(classes) do
			for i=#(setList), 1, -1 do table.remove(setList, i) end
			for setName in pairs(self.db.sets[class]) do
				table.insert(setList, setName)
			end
			
			if( #(setList) > 0 ) then
				DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99%s|r: %s", L[class] or "???", table.concat(setList, ", ")))
			end
		end
		
	-- Macro restoring
	elseif( cmd == "macro" ) then
		self.db.macro = not self.db.macro

		if( self.db.macro ) then
			self:Print(L["Auto macro restoration is now enabled!"])
		else
			self:Print(L["Auto macro restoration is now disabled!"])
		end
	
	-- Item counts
	elseif( cmd == "count" ) then
		self.db.checkCount = not self.db.checkCount

		if( self.db.checkCount ) then
			self:Print(L["Checking item count is now enabled!"])
		else
			self:Print(L["Checking item count is now disabled!"])		
		end
	
	-- Rank restore
	elseif( cmd == "rank" ) then
		self.db.restoreRank = not self.db.restoreRank
		
		if( self.db.restoreRank ) then
			self:Print(L["Auto restoring highest spell rank is now enabled!"])
		else
			self:Print(L["Auto restoring highest spell rank is now disabled!"])
		end
		
	-- Halp
	else
		self:Print(L["Slash commands"])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs save <profile> - Saves your current action bar setup under the given profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs restore <profile> - Changes your action bars to the passed profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs delete <profile> - Deletes the saved profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs rename <oldProfile> <newProfile> - Renames a saved profile from oldProfile to newProfile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs link \"<spell 1>\" \"<spell 2>\" - Links a spell with another, INCLUDE QUOTES for example you can use \"Shadowmeld\" \"War Stomp\" so if War Stomp can't be found, it'll use Shadowmeld and vica versa."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs count - Toggles checking if you have the item in your inventory before restoring it, use if you have disconnect issues when restoring."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs macro - Attempts to restore macros that have been deleted for a profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs rank - Toggles if ABS should restore the highest rank of the spell, or the one saved originally."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs list - Lists all saved profiles."])
	end
end

-- Table des traductions
local translations = {
    ["fr"] = {
        ["title"] = "ActionBarSaver - Gestion Complète des Profils",
        ["select_profile"] = "Sélectionner un Profil",
        ["save"] = "Sauvegarder",
        ["restore"] = "Restaurer",
        ["delete"] = "Supprimer",
        ["rename"] = "Renommer",
        ["refresh_profiles"] = "Rafraîchir Profils",
        ["restore_macros"] = "Restaurer les macros",
        ["restore_binds"] = "Restaurer les binds",
        ["profile_name"] = "Nom du Profil",
        ["no_profiles"] = "Aucun profil trouvé",
        ["save_success"] = "Profil %s sauvegardé.",
        ["restore_success"] = "Profil %s restauré.",
        ["enter_profile_name"] = "Veuillez entrer un nom de profil.",
        ["select_profile_first"] = "Veuillez sélectionner un profil.",
    },
    ["en"] = {
        ["title"] = "ActionBarSaver - Full Profile Management",
        ["select_profile"] = "Select a Profile",
        ["save"] = "Save",
        ["restore"] = "Restore",
        ["delete"] = "Delete",
        ["rename"] = "Rename",
        ["refresh_profiles"] = "Refresh Profiles",
        ["restore_macros"] = "Restore macros",
        ["restore_binds"] = "Restore keybinds",
        ["profile_name"] = "Profile Name",
        ["no_profiles"] = "No profiles found",
        ["save_success"] = "Profile %s saved.",
        ["restore_success"] = "Profile %s restored.",
        ["enter_profile_name"] = "Please enter a profile name.",
        ["select_profile_first"] = "Please select a profile first.",
    }
}

-- Langue par défaut
local currentLanguage = "fr"

-- Fonction pour obtenir le texte traduit
local function GetText(key)
    return translations[currentLanguage][key] or key
end


-- fonction pour sauvegarder les assignations de touches.
function ABS:SaveKeyBindings(profileName)
    self.db.sets[playerClass][profileName] = self.db.sets[playerClass][profileName] or {}
    local bindings = {}
    for i = 1, GetNumBindings() do
        local action, key1, key2 = GetBinding(i)
        if key1 then
            bindings[action] = { key1, key2 }
        end
    end
    self.db.sets[playerClass][profileName].bindings = bindings
    print("Bindings sauvegardés pour le profil : " .. profileName)
end

-- fonction pour restaurer les assignations de touches.
function ABS:RestoreKeyBindings(profileName)
    local bindings = self.db.sets[playerClass][profileName] and self.db.sets[playerClass][profileName].bindings
    if not bindings then
        print("Aucun binding trouvé pour le profil : " .. profileName)
        return
    end

    -- Effacer les assignations actuelles pour restaurer les nouvelles
    for i = 1, GetNumBindings() do
        local action, key1, key2 = GetBinding(i)
        if key1 then
            SetBinding(key1) -- Efface la liaison
        end
        if key2 then
            SetBinding(key2) -- Efface la liaison
        end
    end

    -- Restaurer les bindings sauvegardés
    for action, keys in pairs(bindings) do
        if keys[1] and keys[1] ~= "" then
            local success = SetBinding(keys[1], action)
            if not success then
                print("Erreur lors de la restauration de la touche " .. keys[1] .. " pour l'action " .. action)
            end
        end
        if keys[2] and keys[2] ~= "" then
            local success = SetBinding(keys[2], action)
            if not success then
                print("Erreur lors de la restauration de la touche " .. keys[2] .. " pour l'action " .. action)
            end
        end
    end

    -- Sauvegarder les assignations restaurées dans le set de bindings actuel
    SaveBindings(GetCurrentBindingSet())
    print("Bindings restaurés pour le profil : " .. profileName)
end



-- Fonction pour rafraîchir l'UI avec la langue sélectionnée
local function RefreshUI(frame, profileDropdown, saveButton, restoreButton, deleteButton, renameButton, refreshButton, languageDropdown)
    frame.title:SetText(GetText("title"))
    UIDropDownMenu_SetText(profileDropdown, GetText("select_profile"))
    saveButton:SetText(GetText("save"))
    restoreButton:SetText(GetText("restore"))
    deleteButton:SetText(GetText("delete"))
    renameButton:SetText(GetText("rename"))
    refreshButton:SetText(GetText("refresh_profiles"))
    UIDropDownMenu_SetText(languageDropdown, GetText("language"))
end

-- Fonction pour créer l'interface utilisateur améliorée pour ActionBarSaver
local function CreateABSUIFrame()
    local frame = CreateFrame("Frame", "ABSUIFrame", UIParent)
    frame:SetSize(500, 500)  -- Augmenté pour plus de place
    frame:SetPoint("CENTER")

    -- Ajouter un arrière-plan manuel
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    frame:SetBackdropColor(0.1, 0.1, 0.2, 1)

    -- Titre de la fenêtre
    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -10)
    frame.title:SetText(GetText("title"))
	
	-- Créer une boîte à cocher pour sauvegarder les bindings
local saveBindsCheckBox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
saveBindsCheckBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -190)
saveBindsCheckBox.text = saveBindsCheckBox:CreateFontString(nil, "OVERLAY")
saveBindsCheckBox.text:SetFontObject("GameFontHighlight")
saveBindsCheckBox.text:SetPoint("LEFT", saveBindsCheckBox, "RIGHT", 5, 0)
saveBindsCheckBox.text:SetText(GetText("restore_binds"))
saveBindsCheckBox:SetChecked(true) -- Par défaut activé

    -- Boîte de sélection pour le profil à restaurer
    local profileDropdown = CreateFrame("Frame", "ABSUIProfileDropdown", frame, "UIDropDownMenuTemplate")
    profileDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -50)
    UIDropDownMenu_SetWidth(profileDropdown, 150)
    UIDropDownMenu_SetText(profileDropdown, GetText("select_profile"))

    -- Champ de texte pour entrer le nom du profil
    local profileInputBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    profileInputBox:SetSize(150, 30)
    profileInputBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -90)
    profileInputBox:SetAutoFocus(false)
    profileInputBox:SetMaxLetters(50)
    profileInputBox:SetText(GetText("profile_name"))

    -- Créer un bouton "Sauvegarder"
    local saveButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    saveButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 80)
    saveButton:SetSize(120, 40)
    saveButton:SetText(GetText("save"))

    -- Créer un bouton "Restaurer"
    local restoreButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    restoreButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 80)
    restoreButton:SetSize(120, 40)
    restoreButton:SetText(GetText("restore"))

    -- Créer un bouton "Supprimer"
    local deleteButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    deleteButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 20)
    deleteButton:SetSize(120, 40)
    deleteButton:SetText(GetText("delete"))

    -- Créer un bouton "Renommer"
    local renameButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    renameButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 20)
    renameButton:SetSize(120, 40)
    renameButton:SetText(GetText("rename"))

    -- Créer un bouton "Rafraîchir Profils"
    local refreshButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    refreshButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 200, -50)
    refreshButton:SetSize(120, 40)
    refreshButton:SetText(GetText("refresh_profiles"))

    -- Créer un bouton "Fermer"
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    -- Ajouter le menu déroulant pour le changement de langue
    local languageDropdown = CreateFrame("Frame", "ABSUILanguageDropdown", frame, "UIDropDownMenuTemplate")
    languageDropdown:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -50)
    UIDropDownMenu_SetWidth(languageDropdown, 100)
    UIDropDownMenu_SetText(languageDropdown, GetText("language"))

    local function LoadLanguageOptions()
        local languages = {"fr", "en"}
        UIDropDownMenu_Initialize(languageDropdown, function(self, level, menuList)
            local info = UIDropDownMenu_CreateInfo()
            for _, lang in ipairs(languages) do
                info.text = lang:upper()
                info.func = function()
                    currentLanguage = lang
                    UIDropDownMenu_SetText(languageDropdown, lang:upper())
                    RefreshUI(frame, profileDropdown, saveButton, restoreButton, deleteButton, renameButton, refreshButton, languageDropdown)
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
    end

    LoadLanguageOptions()

    -- Fonction pour charger la liste des profils
    local function LoadProfileList()
        local profiles = {}
        if ActionBarSaverDB and ActionBarSaverDB["sets"] then
            for className, classData in pairs(ActionBarSaverDB["sets"]) do
                for profileName, _ in pairs(classData) do
                    table.insert(profiles, profileName .. " (" .. className .. ")")
                end
            end
        end
        if #profiles == 0 then
            UIDropDownMenu_SetText(profileDropdown, GetText("no_profiles"))
        else
            UIDropDownMenu_Initialize(profileDropdown, function(self, level, menuList)
                local info = UIDropDownMenu_CreateInfo()
                for _, profile in ipairs(profiles) do
                    info.text = profile
                    info.func = function(self)
                        UIDropDownMenu_SetText(profileDropdown, profile)
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end)
        end
    end

    -- Fonction pour retirer les espaces inutiles ou caractères spéciaux du profil
    local function ExtractProfileName(profile)
        local cleanName = string.match(profile, "^(.-)%s?%(") or profile
        return cleanName
    end

-- Gestion des clics sur le bouton Sauvegarder
saveButton:SetScript("OnClick", function()
    local profileName = profileInputBox:GetText()
    if profileName and profileName ~= "" then
        ABS:SaveProfile(profileName)
        if saveBindsCheckBox:GetChecked() then
            ABS:SaveKeyBindings(profileName)
        end
        print("Profil " .. profileName .. " sauvegardé.")
    else
        print("Veuillez entrer un nom de profil.")
    end
end)

-- Gestion des clics sur le bouton Restaurer
restoreButton:SetScript("OnClick", function()
    local selectedProfile = UIDropDownMenu_GetText(profileDropdown)
    if selectedProfile and selectedProfile ~= GetText("no_profiles") then
        selectedProfile = ExtractProfileName(selectedProfile)
        ABS:RestoreProfile(selectedProfile, playerClass)
        if saveBindsCheckBox:GetChecked() then
            ABS:RestoreKeyBindings(selectedProfile)
        end
    else
        print("Veuillez sélectionner un profil.")
    end
end)

-- Gestion des clics sur le bouton "Supprimer"
deleteButton:SetScript("OnClick", function()
    local selectedProfile = UIDropDownMenu_GetText(profileDropdown)
    if selectedProfile and selectedProfile ~= GetText("no_profiles") then
        selectedProfile = ExtractProfileName(selectedProfile)
        ABS.db.sets[playerClass][selectedProfile] = nil  -- Supprimer le profil
        print("Profil supprimé : " .. selectedProfile)
        LoadProfileList()  -- Rafraîchit la liste des profils après suppression
    else
        print("Veuillez sélectionner un profil.")
    end
end)

-- Gestion des clics sur le bouton "Renommer"
renameButton:SetScript("OnClick", function()
    local selectedProfile = UIDropDownMenu_GetText(profileDropdown)
    local newProfileName = profileInputBox:GetText()
    if selectedProfile and selectedProfile ~= GetText("no_profiles") and newProfileName and newProfileName ~= "" then
        selectedProfile = ExtractProfileName(selectedProfile)
        if ABS.db.sets[playerClass][newProfileName] then
            print("Un profil avec ce nom existe déjà.")
        else
            -- Renommer le profil
            ABS.db.sets[playerClass][newProfileName] = ABS.db.sets[playerClass][selectedProfile]
            ABS.db.sets[playerClass][selectedProfile] = nil
            print("Profil renommé en : " .. newProfileName)
            LoadProfileList()  -- Rafraîchit la liste des profils après renommage
        end
    else
        print("Veuillez sélectionner un profil et entrer un nouveau nom.")
    end
end)

    -- Gestion des clics sur le bouton "Rafraîchir Profils"
    refreshButton:SetScript("OnClick", function()
        LoadProfileList()  -- Recharge la liste des profils disponibles
        print("Liste des profils rafraîchie.")
    end)

    frame:Hide()
    return frame
end

-- Commande pour afficher l'interface utilisateur
SLASH_ABSUI1 = "/absui"
SlashCmdList["ABSUI"] = function()
    if not ABSUIFrame then
        ABSUIFrame = CreateABSUIFrame()
    end
    if ABSUIFrame:IsShown() then
        ABSUIFrame:Hide()
    else
        ABSUIFrame:Show()
    end
end

-- Check if we need to load
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
	if( addon == "ActionBarSaver" ) then
		ABS:OnInitialize()
		self:UnregisterEvent("ADDON_LOADED")
	end
end)