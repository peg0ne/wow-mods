-- Kölapp: which quest an item belongs to, on the item's tooltip (bags,
-- Baganator, bank, chat links, loot). Shows "Uppdrag: <quest> 3/8" for
-- quests in your log that collect, use or hand out the item, and
-- "Startar: <quest>" for items that start one. A quest item that belongs
-- to no quest in your log names its quests and whether they're done, so
-- you know if it can be thrown away.
--
-- Two sources: the quest log itself (item objectives matched by name, and
-- usable quest items by item ID), and ItemData.lua, generated from
-- Questie's database by tools/kolapp_data.py, for items that aren't an
-- objective (letters to deliver, items a quest hands you).

local _, ns = ...
local itemNeeds, itemStarts, itemRewards, itemQuests = ns.itemNeeds, ns.itemStarts, ns.itemRewards, ns.itemQuests

local QUEST_ITEM_CLASS = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12

---------------------------------------------------------------------------
-- The quest log, read again only after it changed.

local dirty = true
local inLog = {}    -- questID -> { title = , complete = }
local byName = {}   -- item name -> { {questID, "3/8", finished}, ... }
local bySpecial = {} -- itemID -> questID (usable quest items)
local texts         -- questID -> lowercase quest text, nil until read (see ReadTexts)

-- "Tough Wolf Meat: 3/8" (Classic) or "3/8 Tough Wolf Meat" (retail).
local function ParseObjective(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
	local name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
	if not name then have, need, name = text:match("^(%d+)%s*/%s*(%d+)%s+(.+)$") end
	if name then return strtrim(name), have .. "/" .. need end
	return strtrim(text)
end

local function AddObjective(questID, text, objectiveType, finished)
	if objectiveType ~= "item" then return end
	local name, progress = ParseObjective(text)
	if not name or name == "" then return end
	byName[name] = byName[name] or {}
	table.insert(byName[name], { questID, progress, finished })
end

local function ReadLog()
	dirty = false
	texts = nil
	wipe(inLog); wipe(byName); wipe(bySpecial)
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		local id = info and not info.isHeader and info.questID
		if id and id > 0 then
			inLog[id] = { title = info.title, complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) }
			local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
			if objectives then
				for _, o in ipairs(objectives) do AddObjective(id, o.text, o.type, o.finished) end
			elseif GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
				for j = 1, GetNumQuestLeaderBoards(index) or 0 do
					AddObjective(id, GetQuestLogLeaderBoard(j, index))
				end
			end
			if GetQuestLogSpecialItemInfo then
				local link = GetQuestLogSpecialItemInfo(index)
				local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)"))
				if itemID then bySpecial[itemID] = id end
			end
		end
	end
end

-- The quest texts (description and objectives), read only when a quest
-- item nothing else knows is hovered: reading them means selecting each
-- quest in turn, and the old selection is put back right after.
local function ReadTexts()
	texts = {}
	if not (GetQuestLogQuestText and C_QuestLog.SetSelectedQuest and C_QuestLog.GetSelectedQuest) then return end
	local selected = C_QuestLog.GetSelectedQuest()
	for id in pairs(inLog) do
		C_QuestLog.SetSelectedQuest(id)
		local description, objectives = GetQuestLogQuestText()
		local text = (description or "") .. "\n" .. (objectives or "")
		if not (issecretvalue and issecretvalue(text)) then texts[id] = text:lower() end
	end
	if selected then C_QuestLog.SetSelectedQuest(selected) end
end

local function MentionedIn(name)
	if not texts then ReadTexts() end
	local found, lower = {}, name:lower()
	for id, text in pairs(texts) do
		if text:find(lower, 1, true) then found[#found + 1] = id end
	end
	return found
end

---------------------------------------------------------------------------
-- Tooltip.

local GOLD, WHITE, GREEN, GREY = "|cffffd100", "|cffffffff", "|cff40ff40", "|cff9d9d9d"

local function QuestName(id)
	local title = inLog[id] and inLog[id].title
		or (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id))
	return title or (itemQuests[id] and itemQuests[id][1]) or ("#" .. id)
end

local function WithChain(id, text)
	local label = ns.Label and ns.Label(id)
	return label and (text .. " " .. label) or text
end

local function Done(id)
	return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id)
end

local function ForMe(id)
	local q = itemQuests[id]
	return not q or not ns.RaceFits or ns.RaceFits(q[2])
end

-- The first copy of the item in the bags: (questID or nil, is a quest
-- item, quest is active). Retail returns a table, older clients values.
local function BagQuestInfo(itemID)
	local C = C_Container
	if not (C and C.GetContainerItemQuestInfo and C.GetContainerNumSlots and C.GetContainerItemID) then return end
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C.GetContainerNumSlots(bag) or 0 do
			if C.GetContainerItemID(bag, slot) == itemID then
				local info, questID, isActive = C.GetContainerItemQuestInfo(bag, slot)
				if type(info) == "table" then
					return info.questID, info.isQuestItem, info.isActive
				end
				return questID, info, isActive
			end
		end
	end
end

local function AddLines(tooltip, itemID)
	if dirty then ReadLog() end
	local lines, shown = {}, {}

	-- Quests in the log that need the item.
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	for _, entry in ipairs(name and byName[name] or {}) do
		local id, progress, finished = entry[1], entry[2], entry[3]
		if not shown[id] then
			shown[id] = true
			local status = progress and ((finished and GREEN or WHITE) .. progress .. "|r") or ""
			lines[#lines + 1] = GOLD .. "Uppdrag:|r " .. WHITE .. WithChain(id, QuestName(id)) .. "|r " .. status
		end
	end
	local special = bySpecial[itemID]
	local candidates = {}
	if special then candidates[1] = special end
	for _, id in ipairs(itemNeeds[itemID] or {}) do candidates[#candidates + 1] = id end
	for _, id in ipairs(candidates) do
		if inLog[id] and not shown[id] then
			shown[id] = true
			local status = inLog[id].complete and (GREEN .. "klar att lämna in|r") or ""
			lines[#lines + 1] = GOLD .. "Uppdrag:|r " .. WHITE .. WithChain(id, QuestName(id)) .. "|r " .. status
		end
	end

	-- Items that start a quest.
	for _, id in ipairs(itemStarts[itemID] or {}) do
		if not shown[id] and ForMe(id) then
			shown[id] = true
			local status = inLog[id] and (GREY .. "(i loggen)|r")
				or Done(id) and (GREY .. "(redan gjord)|r") or ""
			lines[#lines + 1] = GOLD .. "Startar:|r " .. WHITE .. WithChain(id, QuestName(id)) .. "|r " .. status
		end
	end

	-- What the game itself says, for a copy in the bags: the quest the item
	-- starts or belongs to. This covers this client's own items whatever
	-- their category (Venture Co. Work Order is Miscellaneous).
	local bagQuest, bagQuestItem, bagActive
	if #lines == 0 then bagQuest, bagQuestItem, bagActive = BagQuestInfo(itemID) end
	if bagQuest and not shown[bagQuest] then
		shown[bagQuest] = true
		local title = QuestName(bagQuest)
		if title:sub(1, 1) == "#" and C_QuestLog.RequestLoadQuestByID then
			C_QuestLog.RequestLoadQuestByID(bagQuest) -- named on the next hover
		end
		local status = (bagActive or inLog[bagQuest]) and (GREY .. "(i loggen)|r")
			or Done(bagQuest) and (GREY .. "(redan gjord)|r") or ""
		local label = bagQuestItem and "Uppdrag:" or "Startar:"
		lines[#lines + 1] = GOLD .. label .. "|r " .. WHITE .. WithChain(bagQuest, title) .. "|r " .. status
	end

	-- A quest item for no quest in the log: name its quests, so you know
	-- whether to keep it.
	local isQuestItem = #lines == 0
		and (bagQuestItem or select(6, C_Item.GetItemInfoInstant(itemID)) == QUEST_ITEM_CLASS)
	if isQuestItem then
		for _, id in ipairs(itemNeeds[itemID] or {}) do
			if ForMe(id) and #lines < 3 then
				local status = Done(id) and (GREEN .. "klar, kan slängas|r") or (GREY .. "inte i loggen|r")
				lines[#lines + 1] = GREY .. "Uppdrag: " .. QuestName(id) .. "|r " .. status
			end
		end
		-- Rewards no later quest needs, like Bethor's Potion.
		for _, id in ipairs(itemRewards[itemID] or {}) do
			if ForMe(id) and #lines < 3 then
				lines[#lines + 1] = GREY .. "Belöning från: " .. QuestName(id) .. "|r"
			end
		end
		-- Not in the data (this client's own items): a quest whose text
		-- names the item.
		if #lines == 0 and name then
			for _, id in ipairs(MentionedIn(name)) do
				lines[#lines + 1] = GOLD .. "Nämns i:|r " .. WHITE .. WithChain(id, QuestName(id)) .. "|r"
			end
		end
		if #lines == 0 then
			lines[#lines + 1] = GREY .. "Kölapp: okänt questföremål (ID " .. itemID .. ")|r"
		end
	end

	if #lines == 0 then return end
	for _, line in ipairs(lines) do tooltip:AddLine(line) end
end

local function OnTooltipItem(tooltip, data)
	if not ns.db or not ns.db.items then return end
	if tooltip == ShoppingTooltip1 or tooltip == ShoppingTooltip2 then return end
	local itemID = data and data.id
	if type(itemID) ~= "number" or (issecretvalue and issecretvalue(itemID)) then return end
	local ok, err = pcall(AddLines, tooltip, itemID)
	if not ok then ns.itemsError = err end -- kept for /dump, never shown
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_REMOVED")
events:SetScript("OnEvent", function(_, event)
	dirty = true
	if event == "PLAYER_LOGIN" and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
		and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipItem)
	end
end)
