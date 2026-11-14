-- Bolagsverket: the register of who belongs to which company. Colors the
-- names on the party (and raid) frames by class and puts a small lightning
-- bolt next to the names of guildmates. Instead of the class colors, every
-- party name can take one color you pick (/bv egen, /bv välj), and
-- guildmates one of their own, on the party frames and nameplates alike
-- (/bv gillefärg, /bv välj gille; 0.4).
--
-- The names floating over characters are drawn by the game and can't be
-- recolored, but the game can show a guild's name under its members' names.
-- /bv gillenamn switches that on and off (the UnitNameGuildTitle setting).
--
-- /bv namnskyltar (0.3, off by default) puts friendly players' nameplates in
-- their place: names only, no friendly NPCs. Those are frames, so guildmates
-- get their color and the bolt there too, your group the party color, others
-- keep the game's own color, and
-- everyone in a guild "<Guild>" under the name. The game's settings it changes
-- are saved and put back when it is turned off, and only changed out of
-- combat. In dungeons and raids the game locks friendly nameplates, so they
-- stay plain there; everyone there is on the party frames anyway.
--
-- Works on whichever party frames the client shows: the old
-- PartyMemberFrame1-4, the retail PartyFrame.MemberFrame1-4 and the
-- raid-style CompactPartyFrame/CompactRaidFrame. Nameplates go through the
-- same CompactUnitFrame code; only friendly players' are touched, and only
-- with namnskyltar on.
--
-- The frames are Blizzard's, so nothing is written onto them: what we know
-- about each name lives in our own table, and the name is only recolored
-- after Blizzard sets its text or color (hooksecurefunc), never instead of it.
-- /bolagsverket for settings.

local ADDON = ...

-- partyColor: the color you picked, used instead of class colors when custom
-- is on (the default). Starts as the party chat's light blue.
-- plates: friendly players' nameplates instead of the floating names.
-- guildCustom/guildColor (0.4): guildmates' own color, everywhere (party
-- frames and nameplates); starts as the guild chat's green.
local defaults = {
	color = true, icon = true, custom = true, plates = false, partyColor = { r = 0.67, g = 0.67, b = 1 },
	guildCustom = true, guildColor = { r = 0.25, g = 1, b = 0.25 },
}
local SETTINGS_VERSION = 2
local db
local tracked = {}       -- name FontString -> { frame, icon, base = { r, g, b, a } }
local guildByGUID = {}   -- last known answer, for when the game hides it in combat
local applying = false   -- our own SetTextColor calls, which the hook must ignore

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff3399ffBolagsverket:|r " .. text)
end

-- Some values can be hidden from addons on this client; treat those as unknown.
local function Known(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function IconTexture()
	if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Skatteverket") then
		return "Interface\\AddOns\\Skatteverket\\Media\\Bolt", false
	end
	return "Interface\\Icons\\Spell_Nature_Lightning", true
end

-- The group unit a frame shows, or nil for anything else (nameplates,
-- target, the player frame).
local function GroupUnit(frame)
	local unit = Known(frame.unit) or Known(frame.displayedUnit)
	if type(unit) ~= "string" then return end
	if unit:match("^party%d$") or unit:match("^raid%d+$") then return unit end
	if unit == "player" then
		-- You, on the raid-style party frames.
		local name = frame.GetName and frame:GetName()
		if name and name:match("^Compact") then return unit end
	end
end

-- A friendly player's nameplate, with namnskyltar on.
local function PlateUnit(frame)
	if not db or not db.plates then return end
	local unit = Known(frame.unit) or Known(frame.displayedUnit)
	if type(unit) ~= "string" or not unit:match("^nameplate%d+$") then return end
	if Known(UnitIsPlayer(unit)) ~= true then return end
	local ok, hostile = pcall(UnitCanAttack, "player", unit)
	if not ok or Known(hostile) ~= false then return end
	return unit
end

-- The unit a frame shows that we color, and whether it is a nameplate.
local function Unit(frame)
	local unit = GroupUnit(frame)
	if unit then return unit, false end
	unit = PlateUnit(frame)
	if unit then return unit, true end
end

local function IsMe(unit)
	if unit == "player" then return true end
	local ok, same = pcall(UnitIsUnit, unit, "player")
	return ok and Known(same) == true
end

local function InMyGuild(unit)
	if not IsInGuild() then return false end
	local guid = Known(UnitGUID(unit))
	local answer
	if UnitIsInMyGuild then
		local ok, v = pcall(UnitIsInMyGuild, unit)
		if ok then answer = Known(v) end
	end
	if answer == nil then
		local mine = GetGuildInfo("player")
		local ok, theirs = pcall(GetGuildInfo, unit)
		theirs = ok and Known(theirs)
		if mine and theirs then answer = theirs == mine end
	end
	if answer ~= nil then
		answer = answer and true or false
		if guid then guildByGUID[guid] = answer end
		return answer
	end
	return guid and guildByGUID[guid] or false
end

local function ClassColor(unit)
	local _, class = UnitClass(unit)
	class = Known(class)
	return class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
end

-- In your party or raid (for a nameplate's unit).
local function InGroup(unit)
	for _, fn in ipairs({ UnitInParty, UnitInRaid }) do
		local ok, v = pcall(fn, unit)
		if ok and Known(v) then return true end
	end
	return false
end

local function SetColor(fs, r, g, b, a)
	applying = true
	fs:SetTextColor(r, g, b, a)
	applying = false
end

-- Puts the bolt just after the text, wherever the text is justified.
local function PlaceIcon(t, fs)
	local icon = t.icon
	local _, size = fs:GetFont()
	size = math.floor((Known(size) or 12) + 0.5)
	icon:SetSize(size, size)
	icon:ClearAllPoints()
	local ok, w = pcall(fs.GetStringWidth, fs)
	w = ok and Known(w)
	local box = Known(fs:GetWidth())
	if w and box and box > 0 then w = math.min(w, box) end
	if not w then
		icon:SetPoint("RIGHT", fs, "LEFT", -1, 0)
		return
	end
	local justify = fs:GetJustifyH()
	if justify == "CENTER" then
		icon:SetPoint("LEFT", fs, "CENTER", w / 2 + 1, 0)
	elseif justify == "RIGHT" then
		icon:SetPoint("LEFT", fs, "RIGHT", 1, 0)
	else
		icon:SetPoint("LEFT", fs, "LEFT", w + 1, 0)
	end
end

-- "<Guild>" under a nameplate's name: gold for our guild, grey for others.
local function GuildLine(t, fs, unit, guildmate)
	local ok, guild = pcall(GetGuildInfo, unit)
	guild = ok and Known(guild)
	if type(guild) ~= "string" or guild == "" then
		if t.guild then t.guild:Hide() end
		return
	end
	if not t.guild then
		t.guild = fs:GetParent():CreateFontString(nil, "OVERLAY")
		t.guild:SetPoint("TOP", fs, "BOTTOM", 0, -1)
	end
	local font, size, flags = fs:GetFont()
	size = Known(size) or 12
	if font then t.guild:SetFont(font, math.max(8, math.floor(size * 0.85 + 0.5)), flags) end
	t.guild:SetText("<" .. guild .. ">")
	if guildmate then t.guild:SetTextColor(1, 0.82, 0) else t.guild:SetTextColor(0.7, 0.7, 0.7) end
	t.guild:Show()
end

local function Apply(fs)
	local t = tracked[fs]
	if not t or not db then return end
	local unit, plate = Unit(t.frame)
	local exists = unit and UnitExists(unit)
	local base = t.base
	local guildmate = exists and not IsMe(unit) and InMyGuild(unit)

	-- Guildmates take the guild color wherever they are; your group (and
	-- guildmates, with the guild color off) the party color or class color,
	-- as on the party frames. On nameplates everyone else keeps the game's
	-- own color (0.4.1: they had their class color, which was unwanted).
	local c
	if exists and db.color then
		if guildmate and db.guildCustom then
			c = db.guildColor
		elseif guildmate or not plate or InGroup(unit) then
			c = db.custom and db.partyColor or ClassColor(unit)
		end
	end
	if c then
		SetColor(fs, c.r, c.g, c.b, base[4])
	else
		SetColor(fs, base[1], base[2], base[3], base[4])
	end

	if exists and db.icon and guildmate then
		PlaceIcon(t, fs)
		t.icon:Show()
	else
		t.icon:Hide()
	end

	if exists and plate then
		GuildLine(t, fs, unit, guildmate)
	elseif t.guild then
		t.guild:Hide()
	end
end

local function NameString(frame)
	local fs = frame.name or frame.Name
	if not fs and frame.GetName and frame:GetName() then fs = _G[frame:GetName() .. "Name"] end
	if type(fs) == "table" and fs.SetTextColor and fs.GetStringWidth then return fs end
end

local function Attach(frame)
	if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
	local fs = NameString(frame)
	if not fs then return end
	if tracked[fs] then return fs end
	local r, g, b, a = fs:GetTextColor()
	local t = { frame = frame, base = { r or 1, g or 0.82, b or 0, a or 1 } }
	local texture, isIcon = IconTexture()
	t.icon = fs:GetParent():CreateTexture(nil, "OVERLAY")
	t.icon:SetTexture(texture)
	if isIcon then t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	t.icon:Hide()
	tracked[fs] = t
	-- Blizzard sets the text whenever the unit changes, and sometimes the
	-- color: remember its color (to give back when ours is off) and recolor.
	hooksecurefunc(fs, "SetText", function() Apply(fs) end)
	hooksecurefunc(fs, "SetTextColor", function(_, nr, ng, nb, na)
		if applying then return end
		t.base = { nr or 1, ng or 1, nb or 1, na or 1 }
		Apply(fs)
	end)
	return fs
end

local function ApplyAll()
	for fs in pairs(tracked) do Apply(fs) end
end

local function FindPartyFrames()
	for i = 1, 4 do
		Attach(_G["PartyMemberFrame" .. i])
		if PartyFrame then Attach(PartyFrame["MemberFrame" .. i]) end
	end
	ApplyAll()
end

-- The raid-style frames are made when first needed; meet them as they update.
local function HookCompactFrames()
	if not CompactUnitFrame_UpdateName then return end
	hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
		if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
		if not Unit(frame) then return end
		local fs = Attach(frame)
		if fs then Apply(fs) end
	end)
end

-- A nameplate coming into view: after Blizzard has filled it in.
local function PlateAdded(unit)
	if not db or not db.plates or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if not ok or not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
	local uf = plate.UnitFrame
	if not uf or (uf.IsForbidden and uf:IsForbidden()) or not PlateUnit(uf) then return end
	local fs = Attach(uf)
	if fs then C_Timer.After(0, function() Apply(fs) end) end
end

local function AllPlates()
	if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if not ok or type(plates) ~= "table" then return end
	for _, plate in ipairs(plates) do
		local uf = plate.UnitFrame
		local unit = uf and not (uf.IsForbidden and uf:IsForbidden()) and Known(uf.unit)
		if type(unit) == "string" then PlateAdded(unit) end
	end
end

-- After Blizzard's own handlers for the same event have run.
local pending = false
local function Refresh()
	if pending then return end
	pending = true
	C_Timer.After(0, function()
		pending = false
		ApplyAll()
	end)
end

---------------------------------------------------------------------------
-- The guild's name under the floating names: the game's own setting, which
-- the game saves itself. db.guildTitle mirrors it, so Gildepanel's box shows
-- the truth even after a change in Interface -> Names.

local GUILD_TITLE = "UnitNameGuildTitle"

local function GetSetting(name)
	if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
	return GetCVar and GetCVar(name)
end

local function SetSetting(name, value)
	if C_CVar and C_CVar.SetCVar then return pcall(C_CVar.SetCVar, name, value) end
	return pcall(SetCVar, name, value)
end

-- Returns false when the client has no such setting.
local function SetGuildTitle(on)
	if GetSetting(GUILD_TITLE) == nil then return false end
	SetSetting(GUILD_TITLE, on and "1" or "0")
	db.guildTitle = GetSetting(GUILD_TITLE) == "1"
	return true
end

-- At login: on the first run, turn it on; after that, follow the game.
local function SyncGuildTitle()
	local now = GetSetting(GUILD_TITLE)
	if now == nil then db.guildTitle = nil return end
	if not db.guildTitleSet then
		db.guildTitleSet = true
		SetGuildTitle(true)
	else
		db.guildTitle = now == "1"
	end
end

---------------------------------------------------------------------------
-- Namnskyltar: the game's settings for friendly nameplates. What they were
-- before is kept in db.platesSaved and put back when it is turned off. The
-- game refuses nameplate settings in combat, so changes wait for it to end.

-- Each with the names it has had across game versions; every one the client
-- has is set. This client (found with ApiProbe, 2026-11-14) has the newer
-- nameplateShowFriendlyPlayers and nameplateShowOnlyNameForFriendlyPlayerUnits,
-- not nameplateShowFriends or nameplateShowOnlyNames.
local PLATE_SETTINGS = {
	{ value = "1", label = "vänliga spelares namnskyltar", needed = true,
		names = { "nameplateShowFriendlyPlayers", "nameplateShowFriends" } },
	{ value = "0", names = { "nameplateShowFriendlyNpcs", "nameplateShowFriendlyNPCs" } },
	{ value = "1", label = "bara namn på namnskyltarna",
		names = { "nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateShowOnlyNames" } },
}
local platesWaiting = false

local function ApplyPlateSettings()
	if InCombatLockdown() then
		platesWaiting = true
		return
	end
	platesWaiting = false
	if db.plates then
		db.platesSaved = db.platesSaved or {}
		for _, s in ipairs(PLATE_SETTINGS) do
			local found = false
			for _, name in ipairs(s.names) do
				local now = GetSetting(name)
				if now ~= nil then
					found = true
					if db.platesSaved[name] == nil then db.platesSaved[name] = now end
					if now ~= s.value then SetSetting(name, s.value) end
				end
			end
			if not found and s.label then
				Print("klienten har ingen inställning för " .. s.label .. (s.needed and "; namnskyltarna kan inte visas." or "."))
			end
		end
		AllPlates()
	elseif db.platesSaved then
		for name, value in pairs(db.platesSaved) do SetSetting(name, value) end
		db.platesSaved = nil
	end
end

local function Hex(c)
	return string.format("ff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

local function Status()
	local kind = db.custom and ("|c" .. Hex(db.partyColor) .. "egen färg|r") or "klassfärg"
	local guild = db.guildCustom and ("|c" .. Hex(db.guildColor) .. "egen färg|r") or "som andra"
	local title = db.guildTitle == nil and "finns inte i klienten" or (db.guildTitle and "på" or "av")
	Print(string.format("färg på namnen: %s (%s, gillemedlemmar %s), blixt vid gillemedlemmar: %s, gillets namn över huvudet: %s, namnskyltar: %s%s.",
		db.color and "på" or "av", kind, guild, db.icon and "på" or "av", title, db.plates and "på" or "av",
		platesWaiting and " (efter striden)" or ""))
end

-- The game's color picker, with the names changing as you drag. Picking a
-- color turns that color on; Cancel puts back what was there before.
-- colorKey/flagKey: "partyColor"/"custom" or "guildColor"/"guildCustom".
local function PickColor(colorKey, flagKey)
	local picker = ColorPickerFrame
	if not picker then Print("färgväljaren finns inte i den här klienten.") return end
	local cur = db[colorKey]
	local old = { r = cur.r, g = cur.g, b = cur.b, flag = db[flagKey], color = db.color }
	local function Changed()
		local r, g, b = picker:GetColorRGB()
		db[colorKey] = { r = r, g = g, b = b }
		db[flagKey], db.color = true, true
		ApplyAll()
	end
	local function Cancel()
		db[colorKey] = { r = old.r, g = old.g, b = old.b }
		db[flagKey], db.color = old.flag, old.color
		ApplyAll()
	end
	if picker.SetupColorPickerAndShow then
		picker:SetupColorPickerAndShow({
			r = old.r, g = old.g, b = old.b, hasOpacity = false,
			swatchFunc = Changed, cancelFunc = Cancel,
		})
	else
		picker.hasOpacity = false
		picker.func, picker.swatchFunc, picker.cancelFunc = Changed, Changed, Cancel
		picker.previousValues = { old.r, old.g, old.b }
		picker:SetColorRGB(old.r, old.g, old.b)
		picker:Hide()
		ShowUIPanel(picker)
	end
end

SLASH_BOLAGSVERKET1 = "/bolagsverket"
SLASH_BOLAGSVERKET2 = "/bv"
SlashCmdList.BOLAGSVERKET = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "färg" or msg == "farg" then
		db.color = not db.color
	elseif msg == "gille" or msg == "blixt" then
		db.icon = not db.icon
	elseif msg == "egen" then
		db.custom = not db.custom
		if db.custom then db.color = true end
	elseif msg == "gillenamn" then
		if not SetGuildTitle(not db.guildTitle) then
			Print("klienten har ingen inställning för gillets namn över huvudet.")
			return
		end
	elseif msg == "välj" or msg == "valj" then
		PickColor("partyColor", "custom")
		return
	elseif msg == "välj gille" or msg == "valj gille" then
		PickColor("guildColor", "guildCustom")
		return
	elseif msg == "gillefärg" or msg == "gillefarg" then
		db.guildCustom = not db.guildCustom
		if db.guildCustom then db.color = true end
	elseif msg == "namnskyltar" or msg == "skyltar" then
		db.plates = not db.plates
		ApplyPlateSettings()
	elseif msg ~= "" then
		Print("/bv visar inställningarna, /bv färg slår på eller av färgen på namnen, /bv egen växlar mellan klassfärg och din egen färg, /bv välj väljer din egen färg, /bv gillefärg slår på eller av en egen färg för gillemedlemmar, /bv välj gille väljer den, /bv gille slår på eller av blixten vid gillemedlemmar, /bv gillenamn slår på eller av gillets namn under namnen över huvudet, /bv namnskyltar visar andra spelares namn som namnskyltar med färg, blixt och gille (utanför instanser).")
		return
	end
	ApplyAll()
	Status()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("UNIT_NAME_UPDATE")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "NAME_PLATE_UNIT_ADDED" then
		if type(arg1) == "string" then PlateAdded(arg1) end
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		if platesWaiting then ApplyPlateSettings() end
		return
	end
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		BolagsverketDB = BolagsverketDB or {}
		db = BolagsverketDB
		-- Before version 1 class colors were the default and that got saved;
		-- your own color is the default now, so switch saved settings over once.
		-- Version 2: "color" was labeled "class color" in Gildepanel, so turning
		-- class colors off there turned all coloring off; turn it back on once.
		local version = db.version or 0
		if version < 1 then db.custom = true end
		if version < 2 then db.color = true end
		db.version = SETTINGS_VERSION
		for k, v in pairs(defaults) do
			if db[k] == nil then db[k] = v end
		end
	elseif event == "PLAYER_LOGIN" then
		HookCompactFrames()
		SyncGuildTitle()
		-- Settings changed in Interface -> Nameplates while it was on are
		-- set back; turning it off still restores what was there first.
		if db.plates then ApplyPlateSettings() end
		FindPartyFrames()
	elseif event == "PLAYER_ENTERING_WORLD" then
		FindPartyFrames()
	else
		Refresh()
	end
end)
