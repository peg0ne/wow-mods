-- Statskontoret: code the THÖNDERSTÖRM addons share, so a fix lands in one
-- place. Other addons list it under ## Dependencies, which makes the game
-- load it first, and reach it through the global Statskontoret.
--
-- Keep it backwards compatible: an addon from an older pack may run against
-- a newer Statskontoret. Add functions; don't change what existing ones
-- take or return. Bump API when adding, so an addon can check for it.

local S = {}
Statskontoret = S
S.API = 1

---------------------------------------------------------------------------
-- Windows.

-- Whether the client has an XML template (Forever has the retail ones).
function S.HasTemplate(name)
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then return C_XMLUtil.GetTemplateInfo(name) ~= nil end
	return true
end

-- The look of Skatteverket's panel: the game's portrait window (like the
-- Character window) with the guild's lightning bolt from Skatteverket's
-- art, the title on the title bar and a recessed inset. Falls back to the
-- old dialog look on a client without the template, as Skatteverket does.
-- Returns the frame and whether the portrait template was used.
--
-- The window is top-level: clicking it brings it in front of the other
-- guild windows, and it comes to the front when it opens. Without this,
-- windows that share a strata and frame level draw their parts interleaved
-- (one window's background over another's text).
function S.Panel(name, titleText)
	local ok, f = false, nil
	local portraitLook = false
	if S.HasTemplate("ButtonFrameTemplate") then ok, f = pcall(CreateFrame, "Frame", name, UIParent, "ButtonFrameTemplate") end
	if ok and f then
		portraitLook = true
		local bolt = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Skatteverket")
		local art = bolt and "Interface\\AddOns\\Skatteverket\\Media\\Bolt" or "Interface\\Icons\\Spell_Nature_Lightning"
		local portrait = f.portrait or f.Portrait or (f.PortraitContainer and f.PortraitContainer.portrait)
			or _G[name .. "Portrait"]
		if f.SetPortraitToAsset then
			f:SetPortraitToAsset(art)
		elseif portrait then
			portrait:SetTexture(art)
		end
		if portrait then portrait:Show() end
		local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
		if title then title:SetText(titleText) end
	else
		f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		local header = f:CreateTexture(nil, "ARTWORK")
		header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
		header:SetSize(320, 64)
		header:SetPoint("TOP", 0, 12)
		local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOP", header, "TOP", 0, -14)
		title:SetText(titleText)
		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -6, -6)
	end
	f:SetToplevel(true)
	f:HookScript("OnShow", function(self) self:Raise() end)
	return f, portraitLook
end

-- A Panel set up the way every guild window is: centered, in the DIALOG
-- strata, kept on screen, dragged by its body and closed by Escape.
function S.Window(name, titleText, width, height)
	local f, portraitLook = S.Panel(name, titleText)
	f:SetSize(width, height)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, name)
	return f, portraitLook
end

---------------------------------------------------------------------------
-- Guild.

-- Asks the server for a fresh guild roster (GUILD_ROSTER_UPDATE follows).
function S.RequestRoster()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

-- Sends an addon message; channel defaults to GUILD. Returns what the game
-- returns (on Forever a result code), or nil when it can't send at all.
function S.SendAddon(prefix, msg, channel, target)
	channel = channel or "GUILD"
	if channel == "GUILD" and not IsInGuild() then return end
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		return C_ChatInfo.SendAddonMessage(prefix, msg, channel, target)
	elseif SendAddonMessage then
		return SendAddonMessage(prefix, msg, channel, target)
	end
end

-- In a battleground or arena: deaths and enemy players there are part of
-- the game, not something to report to the guild.
function S.InPvPInstance()
	if not IsInInstance then return false end
	local _, kind = IsInInstance()
	return kind == "pvp" or kind == "arena"
end

function S.Invite(name)
	if C_PartyInfo and C_PartyInfo.InviteUnit then
		C_PartyInfo.InviteUnit(name)
	elseif InviteUnit then
		InviteUnit(name)
	end
end

-- An addon's ## Version from its .toc, or fallback if the client can't say.
function S.AddonVersion(addon, fallback)
	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local v = meta and meta(addon, "Version")
	return v or fallback
end

---------------------------------------------------------------------------
-- Text.

-- text in the color of a class ("WARRIOR", ...); plain text if unknown.
function S.ClassText(classFile, text)
	local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if not color then return text end
	return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, text)
end
