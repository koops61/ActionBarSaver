--[[
    ActionBarSaver 3 - Update / Version Checker (WotLK 3.3.5a compatible)
    Uses in-game Addon communication channels (Guild / Party / Raid)
]]

local ABS = select(2, ...)
local L = ABS.locals

local CURRENT_VERSION = "3.3"
local PREFIX = "ABS_VER"
local hasNotified = false

ABS.version = CURRENT_VERSION

-- Helper to compare semver-like strings (e.g., "3.1.2" vs "3.1")
local function IsNewerVersion(remote, current)
    local r1, r2, r3 = string.match(remote, "^v?(%d+)%.?(%d*)%.?(%d*)")
    local c1, c2, c3 = string.match(current, "^v?(%d+)%.?(%d*)%.?(%d*)")
    
    r1, r2, r3 = tonumber(r1) or 0, tonumber(r2) or 0, tonumber(r3) or 0
    c1, c2, c3 = tonumber(c1) or 0, tonumber(c2) or 0, tonumber(c3) or 0
    
    if r1 ~= c1 then return r1 > c1 end
    if r2 ~= c2 then return r2 > c2 end
    return r3 > c3
end

local function BroadcastVersion()
    if IsInGuild() then
        SendAddonMessage(PREFIX, CURRENT_VERSION, "GUILD")
    end
    if GetNumRaidMembers() > 0 then
        SendAddonMessage(PREFIX, CURRENT_VERSION, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendAddonMessage(PREFIX, CURRENT_VERSION, "PARTY")
    end
end

function ABS:CheckForUpdate()
    ABS:Print(string.format("Version actuelle : |cff00ff00v%s|r", CURRENT_VERSION))
    BroadcastVersion()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(self, event, prefix, message, distribution, sender)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Register addon prefix for 3.3.5
        RegisterAddonMessagePrefix(PREFIX)
        BroadcastVersion()
    elseif event == "CHAT_MSG_ADDON" and prefix == PREFIX then
        if sender and sender ~= UnitName("player") and message then
            if IsNewerVersion(message, CURRENT_VERSION) and not hasNotified then
                hasNotified = true
                ABS:Print(string.format(L["NEW_VERSION_ALERT"], message, sender))
            end
        end
    end
end)
