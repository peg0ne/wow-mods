-- luacheck settings for the addons. Run `luacheck .` from the repo root;
-- the Lint workflow runs it on every push.
-- WoW runs Lua 5.1. Accessing a global that is not listed below is a warning,
-- which catches typos and API calls that would be nil in game: when you start
-- using a new game API, add it to read_globals.

std = "lua51"
max_line_length = false
exclude_files = { ".git", "tools" }

-- Globals the addons own: SavedVariables, slash commands, library tables.
globals = {
	"ApiProbeBlocked", "ApiProbeDB", "ArbetsformedlingenCharDB", "AtervinningscentralenDB",
	"DodsannonserDB", "EniroCharDB", "GildepanelDB", "HandlaggarenDB", "KolappDB", "PolisenDB",
	"PostnordDB", "Rattsmedicinalverket", "RattsmedicinalverketDB", "RevisorsinspektionenDB",
	"SCBCharDB", "Statskontoret", "SCBDB", "SLASH_APIPROBE1", "SLASH_ARBETSFORMEDLINGEN1", "SLASH_ARBETSFORMEDLINGEN2",
	"SLASH_ATERVINNING1", "SLASH_ATERVINNING2", "SLASH_DODSANNONSER1", "SLASH_DODSANNONSER2",
	"SLASH_DODSANNONSER3", "SLASH_ENIRO1", "SLASH_ENIRO2", "SLASH_GILDEPANEL1", "SLASH_GILDEPANEL2",
	"SLASH_HANDLAGGAREN1", "SLASH_HANDLAGGAREN2", "SLASH_KOLAPP1", "SLASH_PLATSBANKEN1",
	"SLASH_POLISEN1", "SLASH_POLISEN2", "SLASH_POSTNORD1", "SLASH_REVISORSINSPEKTIONEN1",
	"SLASH_SCB1", "SLASH_SCB2", "SLASH_SKOLVERKET1", "SLASH_SKOLVERKET2", "SkolverketCharDB",
	"SkolverketDB", "SlashCmdList",
}

-- Game API and UI globals the addons read. Some are only fallbacks for older
-- clients (see "The Forever client" in README.md).
read_globals = {
	"GossipFrame", "InCombatLockdown", "QuestFrame",
	"AcceptQuest", "Ambiguate", "BackdropTemplateMixin", "BokforingFrame",
	"COMBATLOG_OBJECT_REACTION_HOSTILE", "COMBATLOG_OBJECT_TYPE_GUARDIAN",
	"COMBATLOG_OBJECT_TYPE_PET", "COMBATLOG_OBJECT_TYPE_PLAYER", "COMBATLOG_XPGAIN_FIRSTPERSON",
	"C_AddOns", "C_CVar", "C_ChatInfo", "C_Container", "C_DeathRecap", "C_EventUtils", "C_GossipInfo",
	"C_GuildInfo", "C_Item", "C_Map", "C_Minimap", "C_PartyInfo", "C_QuestLog", "C_Spell",
	"C_SuperTrack", "C_Timer", "C_TradeSkillUI", "C_XMLUtil", "CanMerchantRepair",
	"ChatEdit_GetActiveWindow", "ChatFrame_AddMessageEventFilter", "ChatFrame_SendTell",
	"ChatTypeInfo", "CompleteQuest", "CreateFrame", "CreateVector2D", "DEFAULT_CHAT_FRAME",
	"DeathRecap_GetEvents", "Enum", "FauxScrollFrame_GetOffset", "GameTooltip", "GetActiveTitle",
	"GetAddOnMetadata", "GetAvailableQuestInfo", "GetAvailableTitle", "GetBuildInfo", "GetCVar",
	"GetCVarDefault", "GetContainerItemInfo", "GetContainerNumSlots", "GetCursorPosition",
	"GetDeathRecapLink", "GetGuildInfo", "GetGuildRosterInfo", "GetGuildRosterLastOnline",
	"GetGuildRosterMOTD", "GetGuildRosterShowOffline", "GetItemInfo", "GetMaxPlayerLevel", "GetMoney",
	"GetNumActiveQuests", "GetNumAvailableQuests", "GetNumGuildMembers", "GetNumQuestChoices",
	"GetNumQuestLeaderBoards", "GetNumQuestLogEntries", "GetNumTrackingTypes", "GetPlayerInfoByGUID",
	"GetProfessionInfo", "GetProfessions", "GetQuestDifficultyColor", "GetQuestID",
	"GetQuestItemLink", "GetQuestLogLeaderBoard", "GetQuestLogQuestText",
	"GetQuestLogSpecialItemInfo", "GetQuestLogTitle", "GetQuestMoneyToGet", "GetQuestReward",
	"GetRealZoneText", "GetRealmName", "GetRepairAllCost", "GetSpellInfo", "GetSubZoneText",
	"GetTime", "GetTotalAchievementPoints", "GetTrackingInfo", "GetZoneText", "GuildRoster",
	"InviteUnit", "IsAddOnLoaded", "IsInGroup", "IsInGuild", "IsInInstance", "IsQuestCompletable",
	"IsQuestComplete", "IsShiftKeyDown", "ItemRefTooltip", "LOCALIZED_CLASS_NAMES_MALE", "Minimap",
	"NUM_BAG_SLOTS", "PanelTemplates_DeselectTab", "PanelTemplates_SelectTab",
	"PanelTemplates_TabResize", "PlaySound", "QUESTS_DISPLAYED", "QuestGetAutoAccept",
	"QuestInfoFrame", "QuestInfoRewardsFrame", "QuestInfoTitleHeader", "QuestInfo_Display",
	"QuestLogListScrollFrame", "QuestLogPushQuest", "QuestLogQuests_Update", "QuestLog_Update",
	"QuestMapLogTitleButton_OnEnter", "QuestScrollFrame", "RAID_CLASS_COLORS",
	"RaidNotice_AddMessage", "RaidWarningFrame", "RegisterAddonMessagePrefix", "RepairAllItems",
	"SOUNDKIT", "SelectActiveQuest", "SelectAvailableQuest", "SendAddonMessage", "SendChatMessage",
	"SetCVar", "SetTracking", "ShoppingTooltip1", "ShoppingTooltip2", "SkatteverketCharDB",
	"SkatteverketDB", "SwedbankCharDB", "TooltipDataProcessor", "UIParent", "UISpecialFrames",
	"UnitClass", "UnitCreatureFamily", "UnitExists", "UnitFactionGroup", "UnitGUID",
	"UnitIsDeadOrGhost", "UnitIsFriend", "UnitIsPlayer", "UnitLevel", "UnitName", "UnitRace",
	"UseContainerItem", "WorldMapFrame", "bit", "date", "format", "geterrorhandler", "hooksecurefunc",
	"issecretvalue", "strsplit", "strtrim", "time", "tinsert", "wipe",
}

