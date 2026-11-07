-- Handläggaren: quest automation.
-- Talking to a quest giver: picks up its quests and hands in finished
-- ones, then accepts and completes them. Holding Shift when the window
-- opens skips everything for that conversation. Never hands in a quest
-- that costs gold. With a choice of rewards it marks the one that sells
-- for most and lets you choose (or picks it, with /hl belöning). Gray
-- (trivial) quests are left alone unless /hl grå. Choosing an NPC's only
-- chat option is off by default (/hl prat): some single options do things
-- (set your home, open a vendor).
--
-- Written for Forever's retail-based client (C_GossipInfo), with the older
-- quest greeting functions for NPCs that use that window instead.

local defaults = {
	on = true,        -- accept and hand in
	pickBest = false, -- pick the most valuable reward instead of only marking it
	share = false,    -- share newly accepted quests with the group
	gossip = false,   -- choose an NPC's only chat option
	trivial = false,  -- also take gray quests
}

local db
local skipping = false   -- Shift was down when this conversation opened
local marker

local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff99cc66Handläggaren:|r " .. text)
end

local function Money(copper)
	copper = math.floor(copper or 0)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then return string.format("%dg %ds %dc", g, s, c) end
	if s > 0 then return string.format("%ds %dc", s, c) end
	return string.format("%dc", c)
end

local function Active()
	return db and db.on and not skipping
end

---------------------------------------------------------------------------
-- Gossip windows (most NPCs).

local function OnGossip()
	skipping = IsShiftKeyDown()
	if not Active() or not C_GossipInfo then return end
	-- Finished quests first.
	for _, q in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
		if q.isComplete and q.questID then
			C_GossipInfo.SelectActiveQuest(q.questID)
			return
		end
	end
	for _, q in ipairs(C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}) do
		if q.questID and not q.isIgnored and (db.trivial or not q.isTrivial) then
			C_GossipInfo.SelectAvailableQuest(q.questID)
			return
		end
	end
	if db.gossip and C_GossipInfo.GetOptions and C_GossipInfo.SelectOption then
		local options = C_GossipInfo.GetOptions() or {}
		local available = C_GossipInfo.GetAvailableQuests and #C_GossipInfo.GetAvailableQuests() or 0
		local active = C_GossipInfo.GetActiveQuests and #C_GossipInfo.GetActiveQuests() or 0
		if #options == 1 and available == 0 and active == 0 and options[1].gossipOptionID then
			C_GossipInfo.SelectOption(options[1].gossipOptionID)
		end
	end
end

-- The older quest greeting window (NPCs with only quests).
local function OnGreeting()
	skipping = IsShiftKeyDown()
	if not Active() then return end
	for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
		local _, isComplete = GetActiveTitle(i)
		if isComplete then
			SelectActiveQuest(i)
			return
		end
	end
	for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
		local isTrivial = GetAvailableQuestInfo and select(1, GetAvailableQuestInfo(i))
		if db.trivial or not isTrivial then
			SelectAvailableQuest(i)
			return
		end
	end
end

---------------------------------------------------------------------------
-- The quest window itself.

local function OnDetail()
	if IsShiftKeyDown() then skipping = true end
	if not Active() then return end
	-- Quests the game accepts by itself need nothing from us. (Escort
	-- quests ask through QUEST_ACCEPT_CONFIRM, which is left to you.)
	if QuestGetAutoAccept and QuestGetAutoAccept() then return end
	AcceptQuest()
end

local function OnProgress()
	if IsShiftKeyDown() then skipping = true end
	if not Active() then return end
	if IsQuestCompletable() and (GetQuestMoneyToGet and GetQuestMoneyToGet() or 0) == 0 then
		CompleteQuest()
	end
end

-- The reward buttons: retail's list, or the older numbered globals.
local function RewardButton(i)
	local frame = QuestInfoRewardsFrame
	if frame and frame.RewardButtons and frame.RewardButtons[i] then return frame.RewardButtons[i] end
	return _G["QuestInfoRewardsFrameQuestInfoItem" .. i]
end

local function Mark(button)
	if not marker then
		marker = CreateFrame("Frame", nil, UIParent)
		marker:SetSize(18, 18)
		marker.icon = marker:CreateTexture(nil, "OVERLAY")
		marker.icon:SetAllPoints()
		marker.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
	end
	marker:SetParent(button)
	marker:SetFrameLevel(button:GetFrameLevel() + 5)
	marker:ClearAllPoints()
	marker:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
	marker:Show()
end

local function OnComplete()
	if marker then marker:Hide() end
	if IsShiftKeyDown() then skipping = true end
	local choices = GetNumQuestChoices() or 0
	if choices <= 1 then
		if Active() then GetQuestReward(choices) end
		return
	end
	-- Several rewards: find the one that sells for most.
	local best, bestPrice = nil, -1
	for i = 1, choices do
		local link = GetQuestItemLink("choice", i)
		local price = link and select(11, GetItemInfo(link)) or 0
		if price > bestPrice then best, bestPrice = i, price end
	end
	if not best or bestPrice <= 0 then return end
	if Active() and db.pickBest then
		Print(string.format("valde %s (säljs för %s).", GetQuestItemLink("choice", best) or "belöningen", Money(bestPrice)))
		GetQuestReward(best)
		return
	end
	-- Only mark it; the frame may still be laying itself out.
	C_Timer.After(0.1, function()
		local button = RewardButton(best)
		if button and button:IsShown() then Mark(button) end
	end)
end

local function OnAccepted(questID)
	if not db or not db.share or not questID or not IsInGroup() then return end
	if C_QuestLog and C_QuestLog.IsPushableQuest and not C_QuestLog.IsPushableQuest(questID) then return end
	if C_QuestLog and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(questID) end
	if QuestLogPushQuest then QuestLogPushQuest() end
end

---------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL",
	"QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED", "GOSSIP_CLOSED", "QUEST_FINISHED" }) do
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "Handlaggaren" then
			HandlaggarenDB = HandlaggarenDB or {}
			db = HandlaggarenDB
			for k, v in pairs(defaults) do
				if db[k] == nil then db[k] = v end
			end
		end
	elseif not db then
		return
	elseif event == "GOSSIP_SHOW" then OnGossip()
	elseif event == "QUEST_GREETING" then OnGreeting()
	elseif event == "QUEST_DETAIL" then OnDetail()
	elseif event == "QUEST_PROGRESS" then OnProgress()
	elseif event == "QUEST_COMPLETE" then OnComplete()
	elseif event == "QUEST_ACCEPTED" then
		-- Retail passes the quest ID; older clients pass the log index first.
		local a, b = ...
		OnAccepted(b or a)
	elseif event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then
		-- The conversation is over; the next one decides afresh.
		skipping = false
		if marker then marker:Hide() end
	end
end)

local SETTINGS = {
	{ "on", "", "automatiken" },
	{ "pickBest", "belöning", "välj dyraste belöningen själv" },
	{ "share", "dela", "dela nya uppdrag med gruppen" },
	{ "gossip", "prat", "välj NPC:ns enda pratval" },
	{ "trivial", "grå", "ta gråa uppdrag" },
}

local function Status()
	local parts = {}
	for _, s in ipairs(SETTINGS) do
		table.insert(parts, string.format("%s: %s", s[3], db[s[1]] and "|cff40ff40på|r" or "|cffff4040av|r"))
	end
	Print(table.concat(parts, ", ") .. ". Håll Shift för att hoppa över.")
end

SLASH_HANDLAGGAREN1 = "/hl"
SLASH_HANDLAGGAREN2 = "/handlaggaren"
SlashCmdList.HANDLAGGAREN = function(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "" then Status() return end
	if cmd == "av" or cmd == "på" or cmd == "pa" then
		db.on = cmd ~= "av"
		Status()
		return
	end
	local aliases = { belöning = "pickBest", beloning = "pickBest", dela = "share", prat = "gossip", ["grå"] = "trivial", gra = "trivial" }
	local key = aliases[cmd]
	if not key then
		Print("/hl visar inställningarna. /hl av | på, /hl belöning, /hl dela, /hl prat, /hl grå slår av eller på.")
		return
	end
	db[key] = not db[key]
	Status()
end
