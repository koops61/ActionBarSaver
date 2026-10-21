--[[ 
	Action Bar Saver 3 (WotLK 3.3.5a / Warmane Edition)
	Original by Shadowed, Enhanced by koops61
]]

ActionBarSaver = select(2, ...)

local ABS = ActionBarSaver
local L = ABS.locals

-- WoW 3.3.5a compatibility polyfill for Frame:SetSize
local frameMeta = getmetatable(CreateFrame("Frame")).__index
if not frameMeta.SetSize then
	frameMeta.SetSize = function(self, w, h)
		self:SetWidth(w)
		self:SetHeight(h or w)
	end
end

local ADDON_NAME = select(1, ...) or "ActionBarSaver"
local restoreErrors, spellCache, macroCache, macroNameCache, highestRanks = {}, {}, {}, {}, {}
local iconCache
local playerClass = select(2, UnitClass("player"))

local MAX_MACROS = 54
local MAX_CHAR_MACROS = 18
local MAX_GLOBAL_MACROS = 36
local MAX_ACTION_BUTTONS = 144
local POSSESSION_START = 121
local POSSESSION_END = 132

function ABS:OnInitialize()
	playerClass = select(2, UnitClass("player")) or playerClass
	
	local defaults = {
		macro = true,
		checkCount = false,
		restoreRank = true,
		restoreBinds = true,
		spellSubs = {},
		sets = {},
		dualSpec = {
			enable = false,
		},
		minimapPos = 215,
		showAllClasses = false,
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
	
	ActionBarSaverDB.dualSpec = ActionBarSaverDB.dualSpec or {}
	for classToken in pairs(RAID_CLASS_COLORS) do
		ActionBarSaverDB.dualSpec[classToken] = ActionBarSaverDB.dualSpec[classToken] or { [1] = "", [2] = "" }
	end
	
	self.db = ActionBarSaverDB
	self.isInitialized = true
end

function ABS:CheckDB()
	if not self.db then
		self:OnInitialize()
	end
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

-- Save a profile
function ABS:SaveProfile(name)
	self:CheckDB()
	playerClass = playerClass or select(2, UnitClass("player"))
	self.db.sets[playerClass][name] = self.db.sets[playerClass][name] or {}
	local set = self.db.sets[playerClass][name]
	
	for actionID=1, MAX_ACTION_BUTTONS do
		set[actionID] = nil
		
		local type, id, subType, extraID = GetActionInfo(actionID)
		if( type and id and ( actionID < POSSESSION_START or actionID > POSSESSION_END ) ) then
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

-- Save key bindings for a profile
function ABS:SaveKeyBindings(profileName, overrideClass)
	self:CheckDB()
	local targetClass = overrideClass or playerClass or select(2, UnitClass("player"))
	self.db.sets[targetClass] = self.db.sets[targetClass] or {}
	self.db.sets[targetClass][profileName] = self.db.sets[targetClass][profileName] or {}
	local bindings = {}
	for i = 1, GetNumBindings() do
		local action, key1, key2 = GetBinding(i)
		if key1 or key2 then
			bindings[action] = { key1, key2 }
		end
	end
	self.db.sets[targetClass][profileName].bindings = bindings
	self.db.sets[targetClass][profileName].bindingSet = GetCurrentBindingSet()
	self:Print(string.format(L["BINDS_SAVED"], profileName))
end

-- Restore key bindings for a profile
function ABS:RestoreKeyBindings(profileName, overrideClass)
	self:CheckDB()
	local targetClass = overrideClass or playerClass or select(2, UnitClass("player"))
	local set = self.db.sets[targetClass] and self.db.sets[targetClass][profileName]
	local bindings = set and set.bindings
	if not bindings then
		self:Print(string.format(L["NO_BINDS_FOUND"], profileName))
		return
	end

	local targetSet = set.bindingSet or GetCurrentBindingSet()
	if LoadBindings then
		LoadBindings(targetSet)
	end

	-- Clear current bindings
	for i = 1, GetNumBindings() do
		local action, key1, key2 = GetBinding(i)
		if key1 then SetBinding(key1) end
		if key2 then SetBinding(key2) end
	end

	-- Restore saved bindings
	for action, keys in pairs(bindings) do
		if keys[1] and keys[1] ~= "" then
			SetBinding(keys[1], action)
		end
		if keys[2] and keys[2] ~= "" then
			SetBinding(keys[2], action)
		end
	end

	SaveBindings(targetSet)
	self:Print(string.format(L["BINDS_RESTORED"], profileName))
end

-- Finds the macroID in case it's changed
function ABS:FindMacro(id, name, data)
	if( macroCache[id] == data ) then
		return id
	end
		
	for id, currentMacro in pairs(macroCache) do
		if( currentMacro == data ) then
			return id
		end
	end
	
	if( macroNameCache[name] ) then
		return macroNameCache[name]
	end
	
	return nil
end

-- Restore any macros that don't exist
function ABS:RestoreMacros(set)
	local perCharacter = true
	for id, data in pairs(set) do
		if type(data) == "string" then
			local type, id, binding, macroName, macroIcon, macroData = string.split("|", data)
			if( type == "macro" ) then
				local macroID = self:FindMacro(id, macroName, macroData)
				if( not macroID ) then
					local globalNum, charNum = GetNumMacros()
					if( globalNum == MAX_GLOBAL_MACROS and charNum == MAX_CHAR_MACROS ) then
						table.insert(restoreErrors, L["Unable to restore macros, you already have 18 global and 18 per character ones created."])
						break
					elseif( charNum == MAX_CHAR_MACROS ) then
						perCharacter = false
					end

					if( not iconCache ) then
						iconCache = {}
						for i=1, GetNumMacroIcons() do
							iconCache[(GetMacroIconInfo(i))] = i
						end
					end
					
					macroName = self:UncompressText(macroName)
					CreateMacro(macroName == "" and " " or macroName, iconCache[macroIcon] or 1, self:UncompressText(macroData), perCharacter)
				end
			end
		end
	end
	
	-- Recache macros
	for i=1, MAX_MACROS do
		local name, icon, macro = GetMacroInfo(i)
		if( name ) then
			if( not macroNameCache[name] ) then
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
		self:Print(string.format(L["No profile with the name \"%s\" exists."], name))
		return
	elseif( InCombatLockdown() ) then
		self:Print(string.format(L["Unable to restore profile \"%s\", you are in combat."], name))
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
			if spell then
				spellCache[spell] = index
				spellCache[string.lower(spell)] = index
				
				if( rank and rank ~= "" ) then
					spellCache[spell .. rank] = index
				end
			end
		end
	end
	
	-- Cache macros
	local blacklist = {}
	for i=1, MAX_MACROS do
		local name, icon, macro = GetMacroInfo(i)
		
		if( name ) then
			if( macroNameCache[name] ) then
				blacklist[name] = true
				macroNameCache[name] = i
			elseif( not blacklist[name] ) then
				macroNameCache[name] = i
			end
		end
		
		macroCache[i] = macro and self:CompressText(macro) or nil
	end
	
	if( self.db.macro ) then
		self:RestoreMacros(set)
	end
	
	ClearCursor()
	
	local soundToggle = GetCVar("Sound_EnableAllSound")
	SetCVar("Sound_EnableAllSound", 0)

	for i=1, MAX_ACTION_BUTTONS do
		if( i < POSSESSION_START or i > POSSESSION_END ) then
			local type, id = GetActionInfo(i)
		
			if( id or type ) then
				PickupAction(i)
				ClearCursor()
			end
		
			if( set[i] and type(set[i]) == "string" ) then
				self:RestoreAction(i, string.split("|", set[i]))
			end
		end
	end
	
	SetCVar("Sound_EnableAllSound", soundToggle)
	
	if( #(restoreErrors) == 0 ) then
		self:Print(string.format(L["Restored profile %s!"], name))
	else
		self:Print(string.format(L["Restored profile %s, failed to restore %d buttons type /abs errors for more information."], name, #(restoreErrors)))
	end
end

function ABS:RestoreAction(i, type, actionID, binding, ...)
	if( type == "spell" ) then
		local spellName, spellRank = ...
		if( ( self.db.restoreRank or spellRank == "" ) and spellCache[spellName] ) then
			PickupSpell(spellCache[spellName], BOOKTYPE_SPELL)
		elseif( spellRank ~= "" and spellCache[spellName .. spellRank] ) then
			PickupSpell(spellCache[spellName .. spellRank], BOOKTYPE_SPELL)
		end
		
		if( GetCursorInfo() ~= type ) then
			local lowerSpell = string.lower(spellName or "")
			for spell, linked in pairs(self.db.spellSubs) do
				if( lowerSpell == spell and spellCache[linked] ) then
					self:RestoreAction(i, type, actionID, binding, linked, nil)
					return
				elseif( lowerSpell == linked and spellCache[spell] ) then
					self:RestoreAction(i, type, actionID, binding, spell, nil)
					return
				end
			end
			
			table.insert(restoreErrors, string.format(L["Unable to restore spell \"%s\" to slot #%d, it does not appear to have been learned yet."], spellName or "Unknown", i))
			ClearCursor()
			return
		end

		PlaceAction(i)
	elseif( type == "equipmentset" ) then
		local slotID = -1
		for idx=1, GetNumEquipmentSets() do
			if( GetEquipmentSetInfo(idx) == actionID ) then
				slotID = idx
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
			
	elseif( type == "companion" ) then
		local critterName, critterType, critterID = ...
		PickupCompanion(critterType, actionID)
		if( GetCursorInfo() ~= "companion" ) then
			table.insert(restoreErrors, string.format(L["Unable to restore companion \"%s\" to slot #%d, it does not appear to exist yet."], critterName or "Unknown", i))
			ClearCursor()
			return
		end
		
		PlaceAction(i)
	elseif( type == "item" ) then
		PickupItem(actionID)

		if( GetCursorInfo() ~= type ) then
			local itemName = select(1, ...)
			table.insert(restoreErrors, string.format(L["Unable to restore item \"%s\" to slot #%d, cannot be found in inventory."], itemName and itemName ~= "" and itemName or actionID, i))
			ClearCursor()
			return
		end
		
		PlaceAction(i)
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

-- Dual Spec Auto-Switch
function ABS:RestoreActiveSpecProfile()
	local spec = GetActiveTalentGroup and GetActiveTalentGroup() or 1
	if self.db.dualSpec and self.db.dualSpec[playerClass] then
		local profile = self.db.dualSpec[playerClass][spec]
		if profile and profile ~= "" and profile ~= L["NONE"] and self.db.sets[playerClass][profile] then
			self:RestoreProfile(profile, playerClass)
			if self.db.restoreBinds then
				self:RestoreKeyBindings(profile, playerClass)
			end
			return true
		end
	end
	return false
end

function ABS:OnTalentGroupChanged()
	if not self.db.dualSpec or not self.db.dualSpec.enable then return end
	
	if InCombatLockdown() then
		self.pendingDualSpec = true
		return
	end
	
	self:RestoreActiveSpecProfile()
end

function ABS:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ABS|r: " .. (msg or ""))
end

-- Slash Commands
SLASH_ABS1 = "/abs"
SLASH_ABS2 = "/actionbarsaver"
SlashCmdList["ABS"] = function(msg)
	msg = msg or ""
	
	local cmd, arg = string.split(" ", msg, 2)
	cmd = string.lower(cmd or "")
	arg = string.lower(arg or "")
	
	local self = ABS
	self:CheckDB()
	
	-- Open UI
	if cmd == "ui" then
		if SlashCmdList["ABSUI"] then
			SlashCmdList["ABSUI"]()
		end

	-- Profile saving
	elseif( cmd == "save" and arg ~= "" ) then
		self:SaveProfile(arg)
		if self.db.restoreBinds then
			self:SaveKeyBindings(arg)
		end
	
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
		table.wipe(restoreErrors)
				
		if( not self.db.sets[playerClass][arg] ) then
			self:Print(string.format(L["Cannot restore profile \"%s\", you can only restore profiles saved to your class."], arg))
			return
		end
		
		self:RestoreProfile(arg, playerClass)
		if self.db.restoreBinds then
			self:RestoreKeyBindings(arg, playerClass)
		end
		
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
	elseif( cmd == "delete" and arg ~= "" ) then
		self.db.sets[playerClass][arg] = nil
		self:Print(string.format(L["Deleted saved profile %s."], arg))
	
	-- List profiles
	elseif( cmd == "list" ) then
		local classes = {}
		local setList = {}
		
		for class, sets in pairs(self.db.sets) do
			table.insert(classes, class)
		end
		
		table.sort(classes)
		
		for _, class in pairs(classes) do
			table.wipe(setList)
			for setName in pairs(self.db.sets[class]) do
				table.insert(setList, setName)
			end
			
			if( #(setList) > 0 ) then
				DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99%s|r: %s", L[class] or class, table.concat(setList, ", ")))
			end
		end
		
	-- Macro restoring toggle
	elseif( cmd == "macro" ) then
		self.db.macro = not self.db.macro
		if( self.db.macro ) then
			self:Print(L["Auto macro restoration is now enabled!"])
		else
			self:Print(L["Auto macro restoration is now disabled!"])
		end
	
	-- Binds toggle
	elseif( cmd == "binds" ) then
		self.db.restoreBinds = not self.db.restoreBinds
		if( self.db.restoreBinds ) then
			self:Print("Sauvegarde et restauration des raccourcis : |cff00ff00Activée|r")
		else
			self:Print("Sauvegarde et restauration des raccourcis : |cffff0000Désactivée|r")
		end

	-- Dual-spec toggle
	elseif( cmd == "dual" ) then
		self.db.dualSpec.enable = not self.db.dualSpec.enable
		if( self.db.dualSpec.enable ) then
			self:Print("Changement automatique en Dual Spec : |cff00ff00Activé|r")
		else
			self:Print("Changement automatique en Dual Spec : |cffff0000Désactivé|r")
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

	-- Export profile
	elseif( cmd == "export" and arg ~= "" ) then
		ABS:OpenExportDialog(arg, playerClass)

	-- Import profile
	elseif( cmd == "import" ) then
		ABS:OpenImportDialog(function(pName, cToken)
			if ABSUIFrame and ABSUIFrame:IsShown() then
				ABSUIFrame:Hide()
				ABSUIFrame:Show()
			end
		end)

	-- Version check
	elseif( cmd == "version" or cmd == "ver" ) then
		if self.CheckForUpdate then
			self:CheckForUpdate()
		end
		
	-- Help
	else
		self:Print(L["Slash commands"])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs ui - Ouvre l'interface graphique de gestion des profils."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs save <profile> - Saves your current action bar setup under the given profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs restore <profile> - Changes your action bars to the passed profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs delete <profile> - Deletes the saved profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs rename <oldProfile> <newProfile> - Renames a saved profile from oldProfile to newProfile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs export <profile> - Exporte le profil sous forme de texte pour un autre compte/ami."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs import - Ouvre la fenêtre d'importation d'un profil."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs link \"<spell 1>\" \"<spell 2>\" - Links a spell with another, INCLUDE QUOTES for example you can use \"Shadowmeld\" \"War Stomp\" so if War Stomp can't be found, it'll use Shadowmeld and vica versa."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs binds - Active ou désactive la sauvegarde des raccourcis clavier."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs dual - Active ou désactive le changement automatique selon la spé."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs count - Toggles checking if you have the item in your inventory before restoring it, use if you have disconnect issues when restoring."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs macro - Attempts to restore macros that have been deleted for a profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs rank - Toggles if ABS should restore the highest rank of the spell, or the one saved originally."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs list - Lists all saved profiles."])
	end
end

-- =========================================================================
-- BASE64 ENCODER / DECODER & EXPORT-IMPORT ENGINE
-- =========================================================================

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64lookup = {}
for i = 1, #b64chars do
	b64lookup[b64chars:sub(i, i)] = i - 1
end

local function Base64Encode(data)
	local bytes = { data:byte(1, #data) }
	local len = #bytes
	local out = {}
	local pad = (3 - (len % 3)) % 3
	
	for i = 1, pad do
		bytes[len + i] = 0
	end
	
	for i = 1, len + pad, 3 do
		local b1, b2, b3 = bytes[i], bytes[i+1], bytes[i+2]
		local n = b1 * 65536 + b2 * 256 + b3
		local c1 = math.floor(n / 262144) % 64 + 1
		local c2 = math.floor(n / 4096) % 64 + 1
		local c3 = math.floor(n / 64) % 64 + 1
		local c4 = n % 64 + 1
		table.insert(out, b64chars:sub(c1, c1) .. b64chars:sub(c2, c2) .. b64chars:sub(c3, c3) .. b64chars:sub(c4, c4))
	end
	
	local str = table.concat(out)
	if pad == 1 then
		str = str:sub(1, -2) .. "="
	elseif pad == 2 then
		str = str:sub(1, -3) .. "=="
	end
	return str
end

local function Base64Decode(data)
	data = data:gsub("[^A-Za-z0-9+/=]", "")
	local len = #data
	if len % 4 ~= 0 then return nil end
	local out = {}
	
	for i = 1, len, 4 do
		local c1, c2, c3, c4 = data:sub(i, i), data:sub(i+1, i+1), data:sub(i+2, i+2), data:sub(i+3, i+3)
		local n1 = b64lookup[c1] or 0
		local n2 = b64lookup[c2] or 0
		local n3 = b64lookup[c3] or 0
		local n4 = b64lookup[c4] or 0
		
		local n = n1 * 262144 + n2 * 4096 + n3 * 64 + n4
		local b1 = math.floor(n / 65536) % 256
		local b2 = math.floor(n / 256) % 256
		local b3 = n % 256
		
		table.insert(out, string.char(b1))
		if c3 ~= "=" then table.insert(out, string.char(b2)) end
		if c4 ~= "=" then table.insert(out, string.char(b3)) end
	end
	
	return table.concat(out)
end

function ABS:ExportProfile(profileName, classToken)
	classToken = classToken or playerClass
	local set = self.db.sets[classToken] and self.db.sets[classToken][profileName]
	if not set then return nil end

	local lines = {}
	table.insert(lines, classToken)
	table.insert(lines, profileName)
	for i = 1, MAX_ACTION_BUTTONS do
		if set[i] and type(set[i]) == "string" then
			table.insert(lines, i .. "=" .. set[i])
		end
	end
	if set.bindings then
		table.insert(lines, "BINDINGS")
		for action, keys in pairs(set.bindings) do
			table.insert(lines, action .. "=" .. (keys[1] or "") .. "," .. (keys[2] or ""))
		end
	end

	local raw = table.concat(lines, "\n")
	return "!ABS:1!" .. Base64Encode(raw)
end

function ABS:ImportProfile(encoded)
	if not encoded or encoded == "" then
		return false, L["IMPORT_ERR_INVALID"]
	end
	encoded = string.trim(encoded)
	if not encoded:find("^!ABS:1!") then
		return false, L["IMPORT_ERR_INVALID"]
	end

	local b64 = encoded:sub(8)
	local raw = Base64Decode(b64)
	if not raw or raw == "" then
		return false, L["IMPORT_ERR_INVALID"]
	end

	local lines = { string.split("\n", raw) }
	local classToken = lines[1]
	local profileName = lines[2]
	if not classToken or not profileName or classToken == "" or profileName == "" then
		return false, L["IMPORT_ERR_INVALID"]
	end

	self.db.sets[classToken] = self.db.sets[classToken] or {}
	self.db.sets[classToken][profileName] = self.db.sets[classToken][profileName] or {}
	local set = self.db.sets[classToken][profileName]
	table.wipe(set)

	local inBindings = false
	for i = 3, #lines do
		local line = lines[i]
		if line == "BINDINGS" then
			inBindings = true
			set.bindings = {}
		elseif inBindings then
			local action, keys = string.split("=", line, 2)
			if action and keys then
				local k1, k2 = string.split(",", keys, 2)
				set.bindings[action] = { k1 ~= "" and k1 or nil, k2 ~= "" and k2 or nil }
			end
		else
			local slot, data = string.split("=", line, 2)
			local slotNum = tonumber(slot)
			if slotNum and data then
				set[slotNum] = data
			end
		end
	end

	return true, profileName, classToken
end

local function CreateExportImportDialog()
	local dialog = CreateFrame("Frame", "ABSExportImportDialog", UIParent)
	dialog:SetWidth(450)
	dialog:SetHeight(320)
	dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
	dialog:SetFrameStrata("FULLSCREEN_DIALOG")
	dialog:EnableMouse(true)
	dialog:SetMovable(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

	dialog:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 }
	})

	local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", dialog, "TOP", 0, -16)
	title:SetText(L["EXPORT_TITLE"])
	dialog.title = title

	local desc = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	desc:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -38)
	desc:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -20, -38)
	desc:SetJustifyH("LEFT")
	desc:SetText(L["EXPORT_DESC"])
	dialog.desc = desc

	-- ScrollFrame with EditBox
	local scroll = CreateFrame("ScrollFrame", "ABSExportImportScroll", dialog, "UIPanelScrollFrameTemplate")
	scroll:SetWidth(380)
	scroll:SetHeight(180)
	scroll:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -65)

	local ebBg = CreateFrame("Frame", nil, dialog)
	ebBg:SetPoint("TOPLEFT", scroll, "TOPLEFT", -5, 5)
	ebBg:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 25, -5)
	ebBg:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	ebBg:SetBackdropColor(0, 0, 0, 0.8)

	local editBox = CreateFrame("EditBox", "ABSExportImportEditBox", scroll)
	editBox:SetWidth(370)
	editBox:SetHeight(180)
	editBox:SetMultiLine(true)
	editBox:SetAutoFocus(false)
	editBox:SetFontObject("GameFontHighlightSmall")
	editBox:SetMaxLetters(99999)
	editBox:SetScript("OnEscapePressed", function() dialog:Hide() end)
	scroll:SetScrollChild(editBox)
	dialog.editBox = editBox

	-- Action Button (Importer)
	local actionBtn = CreateFrame("Button", nil, dialog, "GameMenuButtonTemplate")
	actionBtn:SetWidth(150)
	actionBtn:SetHeight(26)
	actionBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 40, 16)
	actionBtn:SetText(L["IMPORT_CONFIRM"])
	dialog.actionBtn = actionBtn

	-- Close Button
	local closeBtn = CreateFrame("Button", nil, dialog, "GameMenuButtonTemplate")
	closeBtn:SetWidth(110)
	closeBtn:SetHeight(26)
	closeBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -40, 16)
	closeBtn:SetText(L["CLOSE"])
	closeBtn:SetScript("OnClick", function() dialog:Hide() end)

	dialog:Hide()
	return dialog
end

function ABS:OpenExportDialog(profileName, classToken)
	if not profileName or profileName == "" then
		self:Print(L["SELECT_PROFILE_FIRST"])
		return
	end
	classToken = classToken or playerClass
	local encoded = self:ExportProfile(profileName, classToken)
	if not encoded then
		self:Print(L["SELECT_PROFILE_FIRST"])
		return
	end

	if not self.exportDialog then
		self.exportDialog = CreateExportImportDialog()
	end

	local d = self.exportDialog
	d.title:SetText(L["EXPORT_TITLE"] .. " : " .. profileName)
	d.desc:SetText(L["EXPORT_DESC"])
	d.actionBtn:Hide()
	d.editBox:SetText(encoded)
	d:Show()
	d.editBox:SetFocus()
	d.editBox:HighlightText()
end

function ABS:OpenImportDialog(onSuccessCallback)
	if not self.exportDialog then
		self.exportDialog = CreateExportImportDialog()
	end

	local d = self.exportDialog
	d.title:SetText(L["IMPORT_TITLE"])
	d.desc:SetText(L["IMPORT_DESC"])
	d.editBox:SetText("")
	d.actionBtn:Show()
	d.actionBtn:SetScript("OnClick", function()
		local text = d.editBox:GetText()
		local success, pName, cToken = ABS:ImportProfile(text)
		if success then
			ABS:Print(string.format(L["IMPORT_SUCCESS"], pName, L[cToken] or cToken))
			d:Hide()
			if onSuccessCallback then
				onSuccessCallback(pName, cToken)
			end
		else
			ABS:Print(pName or L["IMPORT_ERR_INVALID"])
		end
	end)
	d:Show()
	d.editBox:SetFocus()
end

-- =========================================================================
-- GRAPHICAL USER INTERFACE (GUI) - WotLK 3.3.5a Optimized
-- =========================================================================

local function CreateABSUIFrame()
	local frame = CreateFrame("Frame", "ABSUIFrame", UIParent)
	frame:SetWidth(480)
	frame:SetHeight(470)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetFrameStrata("DIALOG")
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 }
	})

	-- Title
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", frame, "TOP", 0, -16)
	title:SetText(L["UI_TITLE"])

	-- Close Button
	local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)

	-- ========================================================
	-- SECTION 1 : SAUVEGARDE DE PROFIL
	-- ========================================================
	local saveLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	saveLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 25, -45)
	saveLabel:SetText(L["PROFILE_NAME"] .. " :")

	local profileInputBox = CreateFrame("EditBox", "ABSProfileInputBox", frame, "InputBoxTemplate")
	profileInputBox:SetWidth(250)
	profileInputBox:SetHeight(24)
	profileInputBox:SetPoint("TOPLEFT", saveLabel, "BOTTOMLEFT", 6, -6)
	profileInputBox:SetAutoFocus(false)
	profileInputBox:SetMaxLetters(50)

	local saveButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	saveButton:SetWidth(158)
	saveButton:SetHeight(26)
	saveButton:SetPoint("LEFT", profileInputBox, "RIGHT", 15, 0)
	saveButton:SetText(L["SAVE"])

	-- ========================================================
	-- SECTION 2 : GESTION DES PROFILS EXISTANTS
	-- ========================================================
	local selectLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	selectLabel:SetPoint("TOPLEFT", profileInputBox, "BOTTOMLEFT", -6, -18)
	selectLabel:SetText(L["SELECT_PROFILE"] .. " :")

	local allClassesCB = CreateFrame("CheckButton", "ABSAllClassesCB", frame, "UICheckButtonTemplate")
	allClassesCB:SetPoint("LEFT", selectLabel, "RIGHT", 15, -1)
	allClassesCB.text = allClassesCB:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	allClassesCB.text:SetPoint("LEFT", allClassesCB, "RIGHT", 4, 1)
	allClassesCB.text:SetText(L["ALL_CLASSES"])
	allClassesCB:SetChecked(ABS.db and ABS.db.showAllClasses)

	local profileDropdown = CreateFrame("Frame", "ABSUIProfileDropdown", frame, "UIDropDownMenuTemplate")
	profileDropdown:SetPoint("TOPLEFT", selectLabel, "BOTTOMLEFT", -15, -4)
	UIDropDownMenu_SetWidth(profileDropdown, 230)
	UIDropDownMenu_SetText(profileDropdown, L["SELECT_PROFILE"])

	local selectedProfileItem = nil

	local function GetProfilesList()
		ABS:CheckDB()
		local list = {}
		local showAll = ABS.db and ABS.db.showAllClasses
		local sets = (ABS.db and ABS.db.sets) or (ActionBarSaverDB and ActionBarSaverDB.sets) or {}

		if showAll then
			for className, classData in pairs(sets) do
				if type(classData) == "table" then
					for pName in pairs(classData) do
						table.insert(list, { name = pName, class = className, label = pName .. " (" .. (L[className] or className) .. ")" })
					end
				end
			end
		else
			local classData = sets[playerClass]
			if classData and type(classData) == "table" then
				for pName in pairs(classData) do
					table.insert(list, { name = pName, class = playerClass, label = pName })
				end
			end
		end

		table.sort(list, function(a, b)
			if a.class == b.class then
				return a.name < b.name
			else
				return a.class < b.class
			end
		end)

		return list
	end

	local function RefreshProfileDropdown()
		local profiles = GetProfilesList()
		if #profiles == 0 then
			selectedProfileItem = nil
			UIDropDownMenu_SetText(profileDropdown, L["NO_PROFILES"])
		else
			if not selectedProfileItem then
				selectedProfileItem = profiles[1]
			else
				local found = false
				for _, item in ipairs(profiles) do
					if item.name == selectedProfileItem.name and item.class == selectedProfileItem.class then
						selectedProfileItem = item
						found = true
						break
					end
				end
				if not found then
					selectedProfileItem = profiles[1]
				end
			end
			UIDropDownMenu_SetText(profileDropdown, selectedProfileItem and selectedProfileItem.label or L["SELECT_PROFILE"])
		end

		UIDropDownMenu_Initialize(profileDropdown, function(self, level)
			local info = UIDropDownMenu_CreateInfo()
			for _, item in ipairs(profiles) do
				info.text = item.label
				info.checked = (selectedProfileItem and selectedProfileItem.name == item.name and selectedProfileItem.class == item.class)
				info.func = function()
					selectedProfileItem = item
					UIDropDownMenu_SetText(profileDropdown, item.label)
				end
				UIDropDownMenu_AddButton(info)
			end
		end)
	end

	allClassesCB:SetScript("OnClick", function(self)
		ABS.db.showAllClasses = self:GetChecked() and true or false
		selectedProfileItem = nil
		RefreshProfileDropdown()
	end)

	-- Boutons d'action pour le profil sélectionné (Rangée 1 : 424px au total)
	local restoreBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	restoreBtn:SetWidth(100)
	restoreBtn:SetHeight(24)
	restoreBtn:SetPoint("TOPLEFT", profileDropdown, "BOTTOMLEFT", 18, -8)
	restoreBtn:SetText(L["RESTORE"])

	local renameBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	renameBtn:SetWidth(100)
	renameBtn:SetHeight(24)
	renameBtn:SetPoint("LEFT", restoreBtn, "RIGHT", 8, 0)
	renameBtn:SetText(L["RENAME"])

	local deleteBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	deleteBtn:SetWidth(100)
	deleteBtn:SetHeight(24)
	deleteBtn:SetPoint("LEFT", renameBtn, "RIGHT", 8, 0)
	deleteBtn:SetText(L["DELETE"])

	local refreshBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	refreshBtn:SetWidth(100)
	refreshBtn:SetHeight(24)
	refreshBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 8, 0)
	refreshBtn:SetText(L["REFRESH"])

	-- Boutons Export & Import (Rangée 2 : 424px au total)
	local exportBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	exportBtn:SetWidth(208)
	exportBtn:SetHeight(24)
	exportBtn:SetPoint("TOPLEFT", restoreBtn, "BOTTOMLEFT", 0, -6)
	exportBtn:SetText(L["EXPORT"])

	local importBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	importBtn:SetWidth(208)
	importBtn:SetHeight(24)
	importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
	importBtn:SetText(L["IMPORT"])

	-- ========================================================
	-- SECTION 3 : OPTIONS
	-- ========================================================
	local optLine = frame:CreateTexture(nil, "ARTWORK")
	optLine:SetTexture("Interface\\Buttons\\WHITE8X8")
	optLine:SetVertexColor(1, 1, 1, 0.2)
	optLine:SetHeight(1)
	optLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 25, -227)
	optLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, -227)

	-- Checkbox Binds
	local bindsCB = CreateFrame("CheckButton", "ABSOptionBinds", frame, "UICheckButtonTemplate")
	bindsCB:SetPoint("TOPLEFT", frame, "TOPLEFT", 25, -237)
	bindsCB.text = bindsCB:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	bindsCB.text:SetPoint("LEFT", bindsCB, "RIGHT", 4, 1)
	bindsCB.text:SetText(L["RESTORE_BINDS"])
	bindsCB:SetChecked(ABS.db and ABS.db.restoreBinds)
	bindsCB:SetScript("OnClick", function(self)
		ABS.db.restoreBinds = self:GetChecked() and true or false
	end)

	-- Checkbox Macros
	local macrosCB = CreateFrame("CheckButton", "ABSOptionMacros", frame, "UICheckButtonTemplate")
	macrosCB:SetPoint("TOPLEFT", bindsCB, "BOTTOMLEFT", 0, -4)
	macrosCB.text = macrosCB:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	macrosCB.text:SetPoint("LEFT", macrosCB, "RIGHT", 4, 1)
	macrosCB.text:SetText(L["RESTORE_MACROS"])
	macrosCB:SetChecked(ABS.db and ABS.db.macro)
	macrosCB:SetScript("OnClick", function(self)
		ABS.db.macro = self:GetChecked() and true or false
	end)

	-- Checkbox Spell Ranks
	local ranksCB = CreateFrame("CheckButton", "ABSOptionRanks", frame, "UICheckButtonTemplate")
	ranksCB:SetPoint("TOPLEFT", macrosCB, "BOTTOMLEFT", 0, -4)
	ranksCB.text = ranksCB:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ranksCB.text:SetPoint("LEFT", ranksCB, "RIGHT", 4, 1)
	ranksCB.text:SetText(L["RESTORE_RANK"])
	ranksCB:SetChecked(ABS.db and ABS.db.restoreRank)
	ranksCB:SetScript("OnClick", function(self)
		ABS.db.restoreRank = self:GetChecked() and true or false
	end)

	-- ========================================================
	-- SECTION 4 : DOUBLE SPÉCIALISATION (DUAL SPEC)
	-- ========================================================
	local dsLine = frame:CreateTexture(nil, "ARTWORK")
	dsLine:SetTexture("Interface\\Buttons\\WHITE8X8")
	dsLine:SetVertexColor(1, 1, 1, 0.2)
	dsLine:SetHeight(1)
	dsLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 25, -333)
	dsLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, -333)

	local dualSpecTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	dualSpecTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 25, -343)
	dualSpecTitle:SetText(L["DUAL_SPEC_TITLE"])

	local dualSpecCB = CreateFrame("CheckButton", "ABSOptionDualSpec", frame, "UICheckButtonTemplate")
	dualSpecCB:SetPoint("TOPLEFT", dualSpecTitle, "BOTTOMLEFT", -2, -6)
	dualSpecCB.text = dualSpecCB:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	dualSpecCB.text:SetPoint("LEFT", dualSpecCB, "RIGHT", 4, 1)
	dualSpecCB.text:SetText(L["DUAL_SPEC_ENABLE"])
	dualSpecCB:SetChecked(ABS.db and ABS.db.dualSpec and ABS.db.dualSpec.enable)
	dualSpecCB:SetScript("OnClick", function(self)
		ABS.db.dualSpec.enable = self:GetChecked() and true or false
	end)

	-- Colonne 1 : Spécialisation 1
	local spec1Label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	spec1Label:SetPoint("TOPLEFT", dualSpecCB, "BOTTOMLEFT", 6, -8)
	spec1Label:SetText(L["DUAL_SPEC_PRIMARY"])

	local spec1Dropdown = CreateFrame("Frame", "ABSUISpec1Dropdown", frame, "UIDropDownMenuTemplate")
	spec1Dropdown:SetPoint("TOPLEFT", spec1Label, "BOTTOMLEFT", -15, -4)
	UIDropDownMenu_SetWidth(spec1Dropdown, 160)

	-- Colonne 2 : Spécialisation 2
	local spec2Label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	spec2Label:SetPoint("TOPLEFT", dualSpecCB, "BOTTOMLEFT", 235, -8)
	spec2Label:SetText(L["DUAL_SPEC_SECONDARY"])

	local spec2Dropdown = CreateFrame("Frame", "ABSUISpec2Dropdown", frame, "UIDropDownMenuTemplate")
	spec2Dropdown:SetPoint("TOPLEFT", spec2Label, "BOTTOMLEFT", -15, -4)
	UIDropDownMenu_SetWidth(spec2Dropdown, 160)

	local function RefreshDualSpecDropdowns()
		local classSets = (ABS.db and ABS.db.sets and ABS.db.sets[playerClass]) or {}
		local profiles = {}
		for pName in pairs(classSets) do
			if type(classSets[pName]) == "table" or type(classSets[pName]) == "string" then
				table.insert(profiles, pName)
			end
		end
		table.sort(profiles)

		local curSpec1 = (ABS.db.dualSpec and ABS.db.dualSpec[playerClass] and ABS.db.dualSpec[playerClass][1]) or ""
		local curSpec2 = (ABS.db.dualSpec and ABS.db.dualSpec[playerClass] and ABS.db.dualSpec[playerClass][2]) or ""

		UIDropDownMenu_SetText(spec1Dropdown, (curSpec1 ~= "" and curSpec1 ~= L["NONE"]) and curSpec1 or L["NONE"])
		UIDropDownMenu_SetText(spec2Dropdown, (curSpec2 ~= "" and curSpec2 ~= L["NONE"]) and curSpec2 or L["NONE"])

		UIDropDownMenu_Initialize(spec1Dropdown, function(self, level)
			local selected = (ABS.db.dualSpec and ABS.db.dualSpec[playerClass] and ABS.db.dualSpec[playerClass][1]) or ""
			local info = UIDropDownMenu_CreateInfo()
			info.text = L["NONE"]
			info.checked = (selected == "" or selected == L["NONE"])
			info.func = function()
				ABS.db.dualSpec[playerClass][1] = ""
				UIDropDownMenu_SetText(spec1Dropdown, L["NONE"])
			end
			UIDropDownMenu_AddButton(info)

			for _, pName in ipairs(profiles) do
				info.text = pName
				info.checked = (selected == pName)
				info.func = function()
					ABS.db.dualSpec[playerClass][1] = pName
					UIDropDownMenu_SetText(spec1Dropdown, pName)
				end
				UIDropDownMenu_AddButton(info)
			end
		end)

		UIDropDownMenu_Initialize(spec2Dropdown, function(self, level)
			local selected = (ABS.db.dualSpec and ABS.db.dualSpec[playerClass] and ABS.db.dualSpec[playerClass][2]) or ""
			local info = UIDropDownMenu_CreateInfo()
			info.text = L["NONE"]
			info.checked = (selected == "" or selected == L["NONE"])
			info.func = function()
				ABS.db.dualSpec[playerClass][2] = ""
				UIDropDownMenu_SetText(spec2Dropdown, L["NONE"])
			end
			UIDropDownMenu_AddButton(info)

			for _, pName in ipairs(profiles) do
				info.text = pName
				info.checked = (selected == pName)
				info.func = function()
					ABS.db.dualSpec[playerClass][2] = pName
					UIDropDownMenu_SetText(spec2Dropdown, pName)
				end
				UIDropDownMenu_AddButton(info)
			end
		end)
	end

	-- Bouton Sauvegarder
	saveButton:SetScript("OnClick", function()
		local name = string.trim(profileInputBox:GetText() or "")
		if name and name ~= "" and name ~= L["PROFILE_NAME"] then
			ABS:SaveProfile(name)
			if bindsCB:GetChecked() then
				ABS:SaveKeyBindings(name)
			end
			profileInputBox:SetText("")
			selectedProfileItem = { name = name, class = playerClass, label = name }
			RefreshProfileDropdown()
			RefreshDualSpecDropdowns()
		else
			ABS:Print(L["ENTER_PROFILE_NAME"])
		end
	end)

	-- Bouton Restaurer
	restoreBtn:SetScript("OnClick", function()
		if selectedProfileItem then
			ABS:RestoreProfile(selectedProfileItem.name, selectedProfileItem.class)
			if bindsCB:GetChecked() then
				ABS:RestoreKeyBindings(selectedProfileItem.name, selectedProfileItem.class)
			end
		else
			ABS:Print(L["SELECT_PROFILE_FIRST"])
		end
	end)

	-- Bouton Supprimer
	deleteBtn:SetScript("OnClick", function()
		if selectedProfileItem and ABS.db.sets[selectedProfileItem.class] then
			if ABS.db.dualSpec and ABS.db.dualSpec[selectedProfileItem.class] then
				if ABS.db.dualSpec[selectedProfileItem.class][1] == selectedProfileItem.name then
					ABS.db.dualSpec[selectedProfileItem.class][1] = ""
				end
				if ABS.db.dualSpec[selectedProfileItem.class][2] == selectedProfileItem.name then
					ABS.db.dualSpec[selectedProfileItem.class][2] = ""
				end
			end
			ABS.db.sets[selectedProfileItem.class][selectedProfileItem.name] = nil
			ABS:Print(string.format(L["PROFILE_DELETED"], selectedProfileItem.name))
			selectedProfileItem = nil
			RefreshProfileDropdown()
			RefreshDualSpecDropdowns()
		else
			ABS:Print(L["SELECT_PROFILE_FIRST"])
		end
	end)

	-- Bouton Renommer
	renameBtn:SetScript("OnClick", function()
		local newName = string.trim(profileInputBox:GetText() or "")
		if not selectedProfileItem or not ABS.db.sets[selectedProfileItem.class] or not ABS.db.sets[selectedProfileItem.class][selectedProfileItem.name] then
			ABS:Print(L["SELECT_PROFILE_FIRST"])
			return
		end
		if not newName or newName == "" or newName == L["PROFILE_NAME"] then
			ABS:Print(L["ENTER_PROFILE_NAME"])
			return
		end
		local pClass = selectedProfileItem.class
		if ABS.db.sets[pClass][newName] then
			ABS:Print(string.format(L["Cannot rename \"%s\" to \"%s\" a profile already exists for %s."], selectedProfileItem.name, newName, (L[pClass] or pClass)))
			return
		end

		if ABS.db.dualSpec and ABS.db.dualSpec[pClass] then
			if ABS.db.dualSpec[pClass][1] == selectedProfileItem.name then
				ABS.db.dualSpec[pClass][1] = newName
			end
			if ABS.db.dualSpec[pClass][2] == selectedProfileItem.name then
				ABS.db.dualSpec[pClass][2] = newName
			end
		end

		ABS.db.sets[pClass][newName] = CopyTable(ABS.db.sets[pClass][selectedProfileItem.name])
		ABS.db.sets[pClass][selectedProfileItem.name] = nil
		ABS:Print(string.format(L["PROFILE_RENAMED"], selectedProfileItem.name, newName))

		profileInputBox:SetText("")
		selectedProfileItem = { name = newName, class = pClass, label = newName }
		RefreshProfileDropdown()
		RefreshDualSpecDropdowns()
	end)

	-- Bouton Rafraîchir
	refreshBtn:SetScript("OnClick", function()
		ABS:CheckDB()
		RefreshProfileDropdown()
		RefreshDualSpecDropdowns()
		bindsCB:SetChecked(ABS.db.restoreBinds)
		macrosCB:SetChecked(ABS.db.macro)
		ranksCB:SetChecked(ABS.db.restoreRank)
		dualSpecCB:SetChecked(ABS.db.dualSpec and ABS.db.dualSpec.enable)
		allClassesCB:SetChecked(ABS.db.showAllClasses)
		ABS:Print(L["PROFILES_REFRESHED"])
	end)

	-- Bouton Exporter
	exportBtn:SetScript("OnClick", function()
		if selectedProfileItem then
			ABS:OpenExportDialog(selectedProfileItem.name, selectedProfileItem.class)
		else
			ABS:Print(L["SELECT_PROFILE_FIRST"])
		end
	end)

	-- Bouton Importer
	importBtn:SetScript("OnClick", function()
		ABS:OpenImportDialog(function(pName, cToken)
			if cToken == playerClass then
				selectedProfileItem = { name = pName, class = cToken, label = pName }
			else
				ABS.db.showAllClasses = true
				if allClassesCB then allClassesCB:SetChecked(true) end
				selectedProfileItem = { name = pName, class = cToken, label = pName .. " (" .. (L[cToken] or cToken) .. ")" }
			end
			RefreshProfileDropdown()
			RefreshDualSpecDropdowns()
		end)
	end)

	-- OnShow: refresh everything
	frame:SetScript("OnShow", function()
		ABS:CheckDB()
		RefreshProfileDropdown()
		RefreshDualSpecDropdowns()
		bindsCB:SetChecked(ABS.db.restoreBinds)
		macrosCB:SetChecked(ABS.db.macro)
		ranksCB:SetChecked(ABS.db.restoreRank)
		dualSpecCB:SetChecked(ABS.db.dualSpec and ABS.db.dualSpec.enable)
		allClassesCB:SetChecked(ABS.db.showAllClasses)
	end)

	frame:Hide()
	return frame
end

SLASH_ABSUI1 = "/absui"
SlashCmdList["ABSUI"] = function()
	ABS:CheckDB()
	if not ABSUIFrame then
		ABSUIFrame = CreateABSUIFrame()
	end
	if ABSUIFrame:IsShown() then
		ABSUIFrame:Hide()
	else
		ABSUIFrame:Show()
	end
end

-- =========================================================================
-- EVENT LISTENER
-- =========================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, addon)
	if event == "ADDON_LOADED" then
		if addon == ADDON_NAME or (addon and (addon:lower() == "actionbarsaver" or addon:lower():find("actionbarsaver"))) then
			ABS:OnInitialize()
		end
	elseif event == "VARIABLES_LOADED" or event == "PLAYER_LOGIN" then
		if not ABS.isInitialized then
			ABS:OnInitialize()
		end
	elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
		ABS:OnTalentGroupChanged()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if ABS.pendingDualSpec then
			ABS.pendingDualSpec = nil
			ABS:OnTalentGroupChanged()
		end
	end
end)
