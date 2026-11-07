-- ApiProbe: records which API functions and frames exist on this client,
-- into ApiProbeDB (written to WTF/Account/<account>/SavedVariables/ApiProbe.lua
-- on /reload or logout). /probe prints what is missing.

local NAMES = {
	-- items, spells
	"GetItemInfo", "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant", "C_Item.RequestLoadItemDataByID",
	"GetSpellInfo", "C_Spell.GetSpellInfo", "C_Spell.GetSpellName", "GetSpellLink", "C_Spell.GetSpellLink",
	-- bags, merchant
	"C_Container.GetContainerItemInfo", "C_Container.UseContainerItem", "C_Container.GetContainerNumSlots",
	"GetContainerItemInfo", "UseContainerItem", "CanMerchantRepair", "GetRepairAllCost", "RepairAllItems",
	-- professions
	"GetNumTradeSkills", "GetTradeSkillLine", "GetTradeSkillInfo", "GetTradeSkillItemLink",
	"GetTradeSkillRecipeLink", "GetTradeSkillCooldown", "C_TradeSkillUI", "C_TradeSkillUI.GetAllRecipeIDs",
	"C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetTradeSkillLine",
	"GetNumCrafts", "GetCraftDisplaySkillLine", "GetCraftInfo", "GetCraftItemLink",
	"GetNumSkillLines", "GetSkillLineInfo", "GetProfessions", "GetProfessionInfo",
	-- map, units, combat
	"C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "C_Map.GetWorldPosFromMapPos",
	"C_Map.GetMapRectOnMap", "CreateVector2D", "GetPlayerInfoByGUID", "CombatLogGetCurrentEventInfo",
	"C_NamePlate.GetNamePlates", "GetQuestDifficultyColor", "C_PartyInfo.InviteUnit", "InviteUnit",
	-- guild, chat
	"C_GuildInfo.GuildRoster", "GuildRoster", "GetGuildRosterShowOffline", "C_ChatInfo.SendAddonMessage",
	"SendAddonMessage", "ChatFrame_SendTell", "ChatEdit_GetActiveWindow", "ChatEdit_InsertLink", "Ambiguate",
	-- UI
	"TooltipDataProcessor.AddTooltipPostCall", "BackdropTemplateMixin", "RaidNotice_AddMessage",
	"RAID_CLASS_COLORS", "LOCALIZED_CLASS_NAMES_MALE", "SOUNDKIT.RAID_WARNING", "WorldMapFrame",
	"WorldMapFrame.ScrollContainer.Child", "UISpecialFrames", "C_Timer.NewTicker", "bit.band", "strsplit",
	"Settings.RegisterCanvasLayoutCategory", "InterfaceOptions_AddCategory", "C_AddOns.GetAddOnInfo",
	"GetAddOnInfo", "C_QuestLog.GetInfo", "GetQuestLogTitle", "C_Item.GetItemQualityColor",
	-- round 2: death recap, restrictions, modern professions, names
	"C_DeathRecap", "C_DeathRecap.GetRecapEvents", "C_DeathRecap.HasRecapEvents", "C_DeathRecap.GetRecapLink",
	"C_DeathRecap.GetRecapMaxHealth", "DeathRecap_GetEvents", "DeathRecap_HasEvents", "GetDeathRecapLink",
	"DeathRecapFrame", "C_DamageMeter", "issecretvalue", "C_Secrets", "C_CombatLog", "C_EventUtils.IsEventValid",
	"C_TradeSkillUI.GetProfessionInfoBySkillLineID", "C_TradeSkillUI.GetChildProfessionInfo",
	"C_TradeSkillUI.GetRecipeCooldown", "C_TradeSkillUI.GetRecipeOutputItemData", "C_TradeSkillUI.GetRecipeSchematic",
	"C_TradeSkillUI.GetRecipeItemLink", "C_TradeSkillUI.GetRecipeLink", "C_TradeSkillUI.IsTradeSkillLinked",
	"C_TradeSkillUI.IsTradeSkillGuild", "C_TradeSkillUI.IsNPCCrafting", "C_TradeSkillUI.GetProfessionInfoByRecipeID",
	"C_TradeSkillUI.OpenTradeSkill", "ProfessionsFrame", "TradeSkillFrame", "C_Item.GetItemNameByID",
	"C_TooltipInfo", "Enum.TooltipDataType.Item", "Enum.TooltipDataType.Unit", "C_Spell.GetSpellCooldown",
	"UnitIsFriend", "UnitIsEnemy", "PlaySound", "GetRealZoneText", "C_Map.GetMapInfo",
}

-- Events that may or may not exist on this client.
local EVENTS = {
	"COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_DEAD", "NAME_PLATE_UNIT_ADDED", "MERCHANT_SHOW",
	"GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW",
	"TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_CLOSE", "NEW_RECIPE_LEARNED",
	"CRAFT_SHOW", "CRAFT_UPDATE", "TRADE_SKILL_UPDATE", "CHAT_MSG_COMBAT_HOSTILE_DEATH", "CHAT_MSG_COMBAT_SELF_HITS",
	"UNIT_HEALTH", "PLAYER_ENTERING_WORLD", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
	"UPDATE_MOUSEOVER_UNIT", "ZONE_CHANGED_NEW_AREA", "TIME_PLAYED_MSG", "PLAYER_LEVEL_UP",
}

-- Record every blocked or forbidden action, whoever caused it.
ApiProbeBlocked = {}
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watcher:SetScript("OnEvent", function(_, event, addon, func)
	table.insert(ApiProbeBlocked, { event = event, addon = tostring(addon), func = tostring(func), t = date and date("%H:%M:%S") })
	if ApiProbeDB then ApiProbeDB.blocked = ApiProbeBlocked end
end)

-- Death recap: what the most recent recaps hold, if addons may read them.
local function RecapSample()
	local C = C_DeathRecap
	if not C or not C.GetRecapEvents then return end
	local sample = {}
	for id = 1, 20 do
		local ok, has = pcall(C.HasRecapEvents or function() return true end, id)
		if ok and has then
			local ok2, events = pcall(C.GetRecapEvents, id)
			if ok2 and type(events) == "table" then
				local last = events[1]
				local copy = {}
				if type(last) == "table" then
					for k, v in pairs(last) do copy[k] = (type(v) == "number" or type(v) == "string" or type(v) == "boolean") and v or type(v) end
				end
				sample[id] = { count = #events, first = copy }
			else
				sample[id] = { error = tostring(events) }
			end
		end
	end
	return sample
end

local function Lookup(path)
	local value = _G
	for part in path:gmatch("[^%.]+") do
		if type(value) ~= "table" then return nil end
		value = value[part]
	end
	return value
end

local function Probe()
	local result = { missing = {}, present = {} }
	for _, name in ipairs(NAMES) do
		local ok, value = pcall(Lookup, name)
		if ok and value ~= nil then
			result.present[name] = type(value)
		else
			table.insert(result.missing, name)
		end
	end
	local version, build, date, toc = GetBuildInfo()
	result.build = { version = version, build = build, date = date, toc = toc }
	result.tooltipScripts = {
		OnTooltipSetItem = GameTooltip:HasScript("OnTooltipSetItem"),
		OnTooltipSetUnit = GameTooltip:HasScript("OnTooltipSetUnit"),
	}
	-- What the item API actually returns, for a common item (Linen Cloth).
	local GII = GetItemInfo or (C_Item and C_Item.GetItemInfo)
	if GII then result.itemInfoLinen = { GII(2589) } end
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(2550)
		result.spellInfoCooking = type(info) == "table" and info or { info }
	end
	result.events = {}
	if C_EventUtils and C_EventUtils.IsEventValid then
		for _, event in ipairs(EVENTS) do result.events[event] = C_EventUtils.IsEventValid(event) and true or false end
	end
	result.recap = RecapSample()
	-- Own professions through the modern API.
	if GetProfessions then
		result.professions = {}
		for _, index in ipairs({ GetProfessions() }) do
			if index then
				local name, _, rank, max, _, _, skillLine = GetProfessionInfo(index)
				table.insert(result.professions, { name = name, rank = rank, max = max, skillLine = skillLine })
			end
		end
	end
	result.blocked = ApiProbeBlocked
	result.time = time()
	-- Keep snapshots taken earlier (profession window, death recap).
	if ApiProbeDB then
		result.tradeSkill = ApiProbeDB.tradeSkill
		result.recapAfterDeath = ApiProbeDB.recapAfterDeath
	end
	ApiProbeDB = result
	return result
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_DEAD")
f:SetScript("OnEvent", function(_, event)
	C_Timer.After(5, function()
		Probe()
		if event ~= "PLAYER_DEAD" then return end
		-- The recap of this death, field by field, marking secret values.
		local s = {}
		local ok, link = pcall(GetDeathRecapLink)
		s.link = ok and (issecretvalue and issecretvalue(link) and "<secret>" or tostring(link)) or "error"
		local plain = ok and not (issecretvalue and issecretvalue(link)) and type(link) == "string"
		local id = plain and tonumber(link:match("death:(%d+)"))
		s.id = id
		if id and C_DeathRecap and C_DeathRecap.GetRecapEvents then
			local ok2, events = pcall(C_DeathRecap.GetRecapEvents, id)
			if ok2 and type(events) == "table" then
				s.count = #events
				s.events = {}
				for i = 1, math.min(6, #events) do
					local copy = {}
					for k, v in pairs(events[i]) do
						if issecretvalue and issecretvalue(v) then copy[k] = "<secret>"
						elseif type(v) == "table" or type(v) == "function" then copy[k] = type(v)
						else copy[k] = v end
					end
					s.events[i] = copy
				end
			else
				s.error = tostring(events)
			end
		end
		ApiProbeDB.recapAfterDeath = s
	end)
end)

-- Opening a profession window: record what the modern API says about it.
local tf = CreateFrame("Frame")
pcall(tf.RegisterEvent, tf, "TRADE_SKILL_SHOW")
pcall(tf.RegisterEvent, tf, "TRADE_SKILL_LIST_UPDATE")
tf:SetScript("OnEvent", function(_, event)
	C_Timer.After(1, function()
		local T = C_TradeSkillUI
		if not T or not ApiProbeDB then return end
		local s = { event = event }
		local ok, base = pcall(T.GetBaseProfessionInfo)
		if ok and type(base) == "table" then
			s.base = {}
			for k, v in pairs(base) do if type(v) ~= "table" then s.base[k] = v end end
		end
		local ok2, ids = pcall(T.GetAllRecipeIDs)
		if ok2 and type(ids) == "table" then
			s.recipeCount = #ids
			s.recipes = {}
			for i = 1, math.min(5, #ids) do
				local info = T.GetRecipeInfo(ids[i])
				local r = { id = ids[i] }
				if type(info) == "table" then
					for k, v in pairs(info) do if type(v) ~= "table" and type(v) ~= "function" then r[k] = v end end
				end
				if T.GetRecipeOutputItemData then
					local okOut, out = pcall(T.GetRecipeOutputItemData, ids[i])
					if okOut and type(out) == "table" then r.outputItemID, r.outputHyperlink = out.itemID, out.hyperlink end
				end
				if T.GetRecipeCooldown then
					local okCd, cd = pcall(T.GetRecipeCooldown, ids[i])
					if okCd then r.cooldown = cd end
				end
				table.insert(s.recipes, r)
			end
		end
		ApiProbeDB.tradeSkill = s
	end)
end)

SLASH_APIPROBE1 = "/probe"
SlashCmdList.APIPROBE = function()
	local r = Probe()
	DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffaaaaaaApiProbe:|r %s build %s (toc %s). %d missing: %s",
		tostring(r.build.version), tostring(r.build.build), tostring(r.build.toc), #r.missing, table.concat(r.missing, ", ")))
	DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaaApiProbe:|r saved; /reload to write it to disk.")
end
