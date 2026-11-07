-- Completed quests at the bottom of each zone in the quest log (the map-style
-- log next to the world map).
--
-- Blizzard's QuestLogQuests_Update gives every row a layoutIndex and then lets
-- QuestScrollFrame.Contents (a vertical layout frame) stack them in that order.
-- Objective lines are anchored to their quest row, so they move with it. After
-- each update we reorder the quest rows within each zone and lay out again.

local hooked, lastError = false, nil

-- Quests in the same zone have consecutive layoutIndex values (the zone
-- header sits just before them), so a gap starts a new zone.
local function Groups()
	local titles = {}
	for frame in QuestScrollFrame.titleFramePool:EnumerateActive() do
		if frame:IsShown() and frame.layoutIndex and frame.questID then
			titles[#titles + 1] = frame
		end
	end
	table.sort(titles, function(a, b) return a.layoutIndex < b.layoutIndex end)

	local groups, current = {}, nil
	for _, frame in ipairs(titles) do
		if current and frame.layoutIndex == current[#current].layoutIndex + 1 then
			current[#current + 1] = frame
		else
			current = { frame }
			groups[#groups + 1] = current
		end
	end
	return groups
end

local function Reorder()
	local changed = false
	for _, group in ipairs(Groups()) do
		-- Unfinished quests keep their order, completed ones follow.
		local open, done = {}, {}
		for _, frame in ipairs(group) do
			if C_QuestLog.IsComplete(frame.questID) then
				done[#done + 1] = frame
			else
				open[#open + 1] = frame
			end
		end
		if #done > 0 and #open > 0 then
			-- Spacing depends on what is above a row (the first quest under a
			-- header sits differently), so it stays with the position.
			local slots = {}
			for i, frame in ipairs(group) do
				slots[i] = { layoutIndex = frame.layoutIndex, topPadding = frame.topPadding }
			end
			local i = 0
			for _, list in ipairs({ open, done }) do
				for _, frame in ipairs(list) do
					i = i + 1
					if frame.layoutIndex ~= slots[i].layoutIndex then changed = true end
					frame.layoutIndex = slots[i].layoutIndex
					frame.topPadding = slots[i].topPadding
				end
			end
		end
	end
	if changed then QuestScrollFrame.Contents:Layout() end
end

local function TryHook()
	if hooked or not QuestLogQuests_Update or not QuestScrollFrame
		or not QuestScrollFrame.titleFramePool or not C_QuestLog or not C_QuestLog.IsComplete then
		return
	end
	hooked = true
	hooksecurefunc("QuestLogQuests_Update", function()
		local ok, err = pcall(Reorder)
		if not ok and err ~= lastError then
			lastError = err
			print("|cffff8040QuestLogSort error:|r " .. tostring(err))
		end
	end)
	-- The log may already be built; sort it now too.
	pcall(Reorder)
end

-- The quest log may be loaded after this addon; hook it once it exists.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", TryHook)
TryHook()

-- Quest tracker on screen: it lists watched quests in watch-list order, so
-- quests are put in order by unwatching and watching them again. Unfinished
-- quests first, then completed ones, each by level (ties in quest log order).
-- This only uses the quest API and never touches the tracker's own code, so
-- it can't cause blocked actions in combat.
local Watch = C_QuestLog
local canSortTracker = Watch and Watch.GetNumQuestWatches and Watch.GetQuestIDForQuestWatchIndex
	and Watch.AddQuestWatch and Watch.RemoveQuestWatch and Watch.IsComplete
local trackerPending = false

local function WatchedQuests()
	local ids = {}
	for i = 1, Watch.GetNumQuestWatches() do
		local id = Watch.GetQuestIDForQuestWatchIndex(i)
		if id then ids[#ids + 1] = id end
	end
	return ids
end

local function Desired(ids)
	local key = {}
	for _, id in ipairs(ids) do
		local index = Watch.GetLogIndexForQuestID and Watch.GetLogIndexForQuestID(id) or 9999
		local info = Watch.GetInfo and Watch.GetInfo(index)
		key[id] = { done = Watch.IsComplete(id) and 1 or 0, level = info and info.level or 0, index = index }
	end
	local sorted = { unpack(ids) }
	table.sort(sorted, function(a, b)
		local ka, kb = key[a], key[b]
		if ka.done ~= kb.done then return ka.done < kb.done end
		if ka.level ~= kb.level then return ka.level < kb.level end
		return ka.index < kb.index
	end)
	return sorted
end

local function SameOrder(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

-- Where a re-watched quest lands: "first" or "last" in the list. Clients
-- differ, so the first sort finds out.
local rewatchLandsAt = nil

local function Rewatch(ids)
	for _, id in ipairs(ids) do
		local watchType = Watch.GetQuestWatchType and Watch.GetQuestWatchType(id)
		Watch.RemoveQuestWatch(id)
		Watch.AddQuestWatch(id, watchType)
	end
end

local function GiveUp()
	canSortTracker = false
	print("|cffff8040QuestLogSort:|r the quest tracker can't be sorted on this client; only the quest log will be.")
end

local function SortTracker()
	trackerPending = false
	local ids = WatchedQuests()
	local desired = Desired(ids)
	if SameOrder(ids, desired) then return end

	local superTracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()

	if rewatchLandsAt == nil then
		-- Re-watch the last quest and see whether it stays last or goes first.
		local probe = ids[#ids]
		Rewatch({ probe })
		local after = WatchedQuests()
		if after[1] == probe then
			rewatchLandsAt = "first"
		elseif after[#after] == probe then
			rewatchLandsAt = "last"
		else
			GiveUp()
			return
		end
	end

	if rewatchLandsAt == "last" then
		Rewatch(desired)
	else
		local reversed = {}
		for i = #desired, 1, -1 do reversed[#reversed + 1] = desired[i] end
		Rewatch(reversed)
	end

	if superTracked and superTracked ~= 0 and C_SuperTrack.SetSuperTrackedQuestID
		and C_SuperTrack.GetSuperTrackedQuestID() ~= superTracked then
		C_SuperTrack.SetSuperTrackedQuestID(superTracked)
	end

	-- Never keep re-watching if the order still doesn't come out right.
	if not SameOrder(WatchedQuests(), desired) then GiveUp() end
end

local function QueueTrackerSort()
	if not canSortTracker or trackerPending then return end
	trackerPending = true
	-- Wait a moment so a burst of quest updates only sorts once.
	C_Timer.After(0.2, function()
		local ok, err = pcall(SortTracker)
		if not ok and err ~= lastError then
			lastError = err
			print("|cffff8040QuestLogSort error:|r " .. tostring(err))
		end
	end)
end

local trackerEvents = CreateFrame("Frame")
trackerEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
trackerEvents:RegisterEvent("QUEST_LOG_UPDATE")
trackerEvents:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
trackerEvents:SetScript("OnEvent", QueueTrackerSort)
