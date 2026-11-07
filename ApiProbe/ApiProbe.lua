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
}

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
	result.time = date and time() or nil
	ApiProbeDB = result
	return result
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() C_Timer.After(5, Probe) end)

SLASH_APIPROBE1 = "/probe"
SlashCmdList.APIPROBE = function()
	local r = Probe()
	DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffaaaaaaApiProbe:|r %s build %s (toc %s). %d missing: %s",
		tostring(r.build.version), tostring(r.build.build), tostring(r.build.toc), #r.missing, table.concat(r.missing, ", ")))
	DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaaApiProbe:|r saved; /reload to write it to disk.")
end
