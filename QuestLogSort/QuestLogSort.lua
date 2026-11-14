-- Completed quests at the bottom of each zone in the quest log (the map-style
-- log next to the world map).
--
-- Blizzard's QuestLogQuests_Update gives every row a layoutIndex and then lets
-- QuestScrollFrame.Contents (a vertical layout frame) stack them in that order.
-- Objective lines are anchored to their quest row, so they move with it. After
-- each update we reorder the quest rows within each zone and lay out again.

local hooked, lastError = false, nil

-- /qls av turns the whole addon off (saved per account), for players whose
-- own quest tracker (Questie) fights over the watch order. The hook on the
-- quest log can't be removed, so it just does nothing while off. Saved
-- variables arrive with our ADDON_LOADED; nothing sorts before that.
local ready = false
local function Enabled()
	return ready and not (QuestLogSortDB and QuestLogSortDB.disabled)
end

-- Nothing is reordered in combat (dungeons are mostly combat). Re-watching
-- quests rebuilds the tracker, which can't move its quest item buttons in
-- combat, and writing to the map's quest rows from addon code then would
-- risk "blocked action" errors on the world map. Both catch up when combat
-- ends.
local function InCombat()
	return InCombatLockdown and InCombatLockdown()
end
local logPending = false

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
		if not Enabled() then return end
		if InCombat() then logPending = true return end
		local ok, err = pcall(Reorder)
		if not ok and err ~= lastError then
			lastError = err
			print("|cffff8040QuestLogSort error:|r " .. tostring(err))
		end
	end)
	-- The log may already be built; sort it now too.
	if Enabled() and not InCombat() then pcall(Reorder) end
end

local function IsLoaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
	return IsAddOnLoaded and IsAddOnLoaded(name)
end

-- The quest log may be loaded after this addon; hook it once it exists.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name == "QuestLogSort" then
		QuestLogSortDB = QuestLogSortDB or {}
		ready = true
	elseif event == "PLAYER_LOGIN" and Enabled() and not QuestLogSortDB.questieHint
		and IsLoaded("Questie") then
		-- Once per account: the toggle is easy to miss otherwise.
		QuestLogSortDB.questieHint = true
		print("|cff80c0ffQuestLogSort:|r Questie är på och har egen questtracker. "
			.. "Om de bråkar om ordningen: /qls av stänger av QuestLogSort.")
	end
	TryHook()
end)
TryHook()

-- Quest tracker on screen: it lists watched quests in watch-list order, so
-- quests are put in order by unwatching and watching them again, in the
-- order Desired gives (ties in quest log order).
-- This only uses the quest API and never touches the tracker's own code, so
-- it can't cause blocked actions in combat.
local Watch = C_QuestLog
local canSortTracker = Watch and Watch.GetNumQuestWatches and Watch.GetQuestIDForQuestWatchIndex
	and Watch.AddQuestWatch and Watch.RemoveQuestWatch and Watch.IsComplete
local trackerPending = false

-- Levels by quest ID, so a quest the log can't look up right now (abandoned
-- mid-update, or the log is busy in an instance) still sorts by its level.
local levels = {}

-- Watched quests that are still in the quest log. A quest that was just
-- abandoned can linger in the watch list for a moment; it can't be watched
-- again, so it is left out of the sort.
local function WatchedQuests()
	local ids = {}
	for i = 1, Watch.GetNumQuestWatches() do
		local id = Watch.GetQuestIDForQuestWatchIndex(i)
		if id and (not Watch.GetLogIndexForQuestID or Watch.GetLogIndexForQuestID(id)) then
			ids[#ids + 1] = id
		end
	end
	return ids
end

-- Tracker order, chosen with /qls zon or /qls nivå:
--   "level" (default): unfinished first, then completed, each by level.
--   "zone": zone by zone in quest log order; within a zone unfinished
--   first, then completed, each by level.
local function ByZone()
	return QuestLogSortDB and QuestLogSortDB.trackerMode == "zone"
end

-- Each quest's zone as the position of its header in the quest log, so
-- zones keep the order the log shows them in.
-- Also returns the zone names, by that position.
local function ZoneOrder()
	local zones, names = {}, {}
	if not (Watch.GetNumQuestLogEntries and Watch.GetInfo) then return zones, names end
	local header = 0
	for i = 1, (Watch.GetNumQuestLogEntries()) do
		local info = Watch.GetInfo(i)
		if info and info.isHeader then
			header = header + 1
			names[header] = info.title
		elseif info and info.questID then
			zones[info.questID] = header
		end
	end
	return zones, names
end

-- The zone you are in comes first: its quest log header has the zone's name.
local function ZoneRank(z, names)
	local here = GetRealZoneText and GetRealZoneText()
	if here and here ~= "" and names[z] == here then return 0 end
	return z
end

local function Desired(ids)
	local key = {}
	local zones, names
	if ByZone() then zones, names = ZoneOrder() end
	for _, id in ipairs(ids) do
		local index = Watch.GetLogIndexForQuestID and Watch.GetLogIndexForQuestID(id) or 9999
		local info = Watch.GetInfo and Watch.GetInfo(index)
		if info and info.questID == id and info.level and info.level > 0 then levels[id] = info.level end
		key[id] = { done = Watch.IsComplete(id) and 1 or 0, level = levels[id] or 0, index = index,
			zone = zones and zones[id] and ZoneRank(zones[id], names) or 0 }
	end
	local sorted = { unpack(ids) }
	table.sort(sorted, function(a, b)
		local ka, kb = key[a], key[b]
		if ka.zone ~= kb.zone then return ka.zone < kb.zone end
		if ka.done ~= kb.done then return ka.done < kb.done end
		if ka.level ~= kb.level then return ka.level < kb.level end
		if ka.index ~= kb.index then return ka.index < kb.index end
		return a < b
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

-- An order that didn't come out right. It isn't tried again (re-watching
-- fires another update, which would loop), but any change to the quests
-- gives a new order, and that one is tried. A single failure used to stop
-- tracker sorting for the whole session.
local failedOrder = nil

local function Signature(ids)
	return table.concat(ids, ",")
end

local trackerAfterCombat = false

local function SortTracker()
	trackerPending = false
	if not Enabled() then return end
	if InCombat() then trackerAfterCombat = true return end
	local ids = WatchedQuests()
	if #ids < 2 then return end
	local desired = Desired(ids)
	if SameOrder(ids, desired) then failedOrder = nil return end
	local signature = Signature(desired)
	if signature == failedOrder then return end

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
			failedOrder = signature
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

	if SameOrder(WatchedQuests(), desired) then
		failedOrder = nil
	else
		failedOrder = signature
	end
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
trackerEvents:RegisterEvent("QUEST_ACCEPTED")
trackerEvents:RegisterEvent("QUEST_REMOVED")
trackerEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
trackerEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
trackerEvents:SetScript("OnEvent", function(_, event)
	if not Enabled() then return end
	if event == "PLAYER_REGEN_ENABLED" then
		-- Combat is over: do what was held back.
		if logPending then
			logPending = false
			-- Reorder the rows as they are; calling Blizzard's update from
			-- here would run it as addon code.
			if QuestScrollFrame and QuestScrollFrame:IsVisible() then pcall(Reorder) end
		end
		if not trackerAfterCombat then return end
		trackerAfterCombat = false
	end
	if InCombat() then trackerAfterCombat = true return end
	QueueTrackerSort()
end)

-- Zone lines in the tracker, in zone mode: the first quest of each zone gets
-- the zone's name and a line above it. Blizzard works out a block's height
-- when it sets the block's title, so right after that the title is moved
-- down and the height grows by the same amount: the tracker then makes room
-- by itself. The quest item buttons are never touched.
--
-- Clicking a zone line folds the zone up: its quests are unwatched (only
-- through the quest API, like the sorting) and remembered per character,
-- and the zone stays as a line "+ Westfall (3)" in the gap above the next
-- zone, or below the last quest. Clicking that watches them again. A quest
-- in a folded zone that gets watched (a new quest, or the game watching one
-- that made progress) is folded away with the rest.
--
-- Changing the height is a write into Blizzard's data, so it is only done
-- out of combat; a tracker update in combat puts the title back and the
-- gap disappears until the next update after combat. Folding waits for
-- combat to end too.
local ROW, SPACE = 16, 8
local saved = setmetatable({}, { __mode = "k" }) -- block -> the title's own anchors
local lines = setmetatable({}, { __mode = "k" }) -- block -> its zone line frames

local function Say(text)
	print("|cff80c0ffQuestLogSort:|r " .. text)
end

local function CharDB()
	QuestLogSortCharDB = QuestLogSortCharDB or {}
	local c = QuestLogSortCharDB
	c.collapsed = c.collapsed or {} -- zone name -> true
	c.hidden = c.hidden or {}       -- quest ID -> zone name, unwatched by folding
	return c
end

-- Folded zones and how many quests each holds.
local function Folded()
	local c, counts = CharDB(), {}
	for _, zone in pairs(c.hidden) do
		if c.collapsed[zone] then counts[zone] = (counts[zone] or 0) + 1 end
	end
	for zone in pairs(c.collapsed) do
		if not counts[zone] then c.collapsed[zone] = nil end
	end
	return counts
end

local busy = false -- folding or unfolding: our own watch changes
local QueuePanel -- shows folded zones while the tracker has no quests (below)
local function Fold(zone)
	local c = CharDB()
	local zones, names = ZoneOrder()
	busy = true
	c.collapsed[zone] = true
	for _, id in ipairs(WatchedQuests()) do
		if names[zones[id]] == zone then
			c.hidden[id] = zone
			Watch.RemoveQuestWatch(id)
		end
	end
	busy = false
	QueuePanel()
end

local function Unfold(zone)
	local c = CharDB()
	busy = true
	c.collapsed[zone] = nil
	for id, z in pairs(c.hidden) do
		if z == zone then
			c.hidden[id] = nil
			if not Watch.GetLogIndexForQuestID or Watch.GetLogIndexForQuestID(id) then Watch.AddQuestWatch(id) end
		end
	end
	busy = false
	QueuePanel()
end

-- Opens every folded zone: /qls öppna, and when zone mode or the addon is
-- turned off. Waits for combat to end.
local unfoldAll, toggles = false, {}
local function UnfoldAll()
	if not ready then return end
	if InCombat() then unfoldAll = true return end
	local zones = {}
	for _, zone in pairs(CharDB().hidden) do zones[zone] = true end
	for zone in pairs(CharDB().collapsed) do zones[zone] = true end
	for zone in pairs(zones) do Unfold(zone) end
	QueuePanel()
end

local function ToggleZone(zone)
	if InCombat() then
		toggles[zone] = not toggles[zone] or nil
		Say("zonen fälls " .. (CharDB().collapsed[zone] and "ut" or "ihop") .. " när striden är över.")
		return
	end
	if CharDB().collapsed[zone] then Unfold(zone) else Fold(zone) end
end

-- Watched quests that belong in a folded zone go back into it.
local function Refold()
	if busy or not ready or InCombat() or not (Enabled() and ByZone()) then return end
	local c = CharDB()
	if not next(c.collapsed) then return end
	local zones, names = ZoneOrder()
	busy = true
	for _, id in ipairs(WatchedQuests()) do
		local zone = names[zones[id]]
		if zone and c.collapsed[zone] then
			c.hidden[id] = zone
			Watch.RemoveQuestWatch(id)
		end
	end
	busy = false
end

local foldEvents = CreateFrame("Frame")
foldEvents:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
foldEvents:RegisterEvent("QUEST_REMOVED")
foldEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
foldEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
foldEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
foldEvents:SetScript("OnEvent", function(_, event, id)
	if not ready then return end
	QueuePanel()
	if event == "QUEST_REMOVED" then
		if id then CharDB().hidden[id] = nil end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if unfoldAll then
			unfoldAll = false
			wipe(toggles)
			UnfoldAll()
		end
		for zone in pairs(toggles) do ToggleZone(zone) end
		wipe(toggles)
		Refold()
	elseif not busy then
		-- Once the change has settled.
		C_Timer.After(0, function() pcall(Refold) end)
	end
end)

-- Folded zones as { name, count, rank }, in tracker order.
local function FoldedRows(names)
	local rank = {}
	for i, name in pairs(names) do
		local r = ZoneRank(i, names)
		if not rank[name] or r < rank[name] then rank[name] = r end
	end
	local rows = {}
	for zone, count in pairs(Folded()) do
		rows[#rows + 1] = { name = zone, count = count, rank = rank[zone] or math.huge }
	end
	table.sort(rows, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		return a.name < b.name
	end)
	return rows
end

-- What each block shows, worked out once per frame (every block in one
-- tracker update asks): quest ID -> { name, above = folded zones over it,
-- gap, below = folded zones under the last quest, extra }.
local plan, planAt = nil, nil
local function Plan()
	local now = GetTime()
	if plan and planAt == now then return plan end
	plan, planAt = {}, now
	local zones, names = ZoneOrder()
	local rows = FoldedRows(names)
	local nextRow, last, lastID, shown = 1, nil, nil, 0
	for _, id in ipairs(WatchedQuests()) do
		local z = zones[id]
		if z then
			if z ~= last and names[z] then
				local entry = { name = names[z], above = {} }
				local r = ZoneRank(z, names)
				while rows[nextRow] and rows[nextRow].rank < r do
					entry.above[#entry.above + 1] = rows[nextRow]
					nextRow = nextRow + 1
				end
				entry.gap = (shown > 0 and SPACE or 0) + ROW * (#entry.above + 1)
				plan[id] = entry
				shown = shown + 1
			end
			last, lastID = z, id
		end
	end
	if lastID and rows[nextRow] then
		local entry = plan[lastID] or { above = {} }
		entry.below = {}
		while rows[nextRow] do
			entry.below[#entry.below + 1] = rows[nextRow]
			nextRow = nextRow + 1
		end
		entry.extra = SPACE + ROW * #entry.below
		plan[lastID] = entry
	end
	return plan
end

local function ZoneLine(block, i)
	local list = lines[block]
	if not list then
		list = {}
		lines[block] = list
	end
	local line = list[i]
	if line then return line end
	line = CreateFrame("Frame", nil, block)
	line:SetHeight(ROW - 2)
	line:EnableMouse(true)
	line.text = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	line.text:SetPoint("LEFT")
	line.rule = line:CreateTexture(nil, "ARTWORK")
	line.rule:SetHeight(1)
	if line.rule.SetColorTexture then line.rule:SetColorTexture(1, 0.82, 0, 0.35) end
	line.rule:SetPoint("LEFT", line.text, "RIGHT", 6, 0)
	line.rule:SetPoint("RIGHT")
	line:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
	line:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 0.82, 0) end)
	line:SetScript("OnMouseUp", function(self) if self.zone then ToggleZone(self.zone) end end)
	list[i] = line
	return line
end

local function ShowLine(line, zone, count)
	line.zone = zone
	if count then
		line.text:SetText("+ " .. zone .. " |cffa0a0a0(" .. count .. ")|r")
	else
		line.text:SetText("- " .. zone)
	end
	line.text:SetTextColor(1, 0.82, 0)
	line:Show()
end

-- With every zone folded no quest is watched, the tracker has no blocks to
-- carry the zone lines and hides itself. Then this small frame of our own
-- shows them where the tracker's quests would start, so they can still be
-- clicked open. It is an ordinary frame, so it can show in combat too.
local panel
local function UpdatePanel()
	local rows = {}
	if ready and Enabled() and ByZone() and #WatchedQuests() == 0 then
		local _, names = ZoneOrder()
		rows = FoldedRows(names)
	end
	if #rows == 0 then
		if panel then panel:Hide() end
		return
	end
	if not panel then
		panel = CreateFrame("Frame", "QuestLogSortFoldedZones", UIParent)
		panel:SetFrameStrata("LOW")
	end
	local tracker = ObjectiveTrackerFrame or QuestWatchFrame
	panel:ClearAllPoints()
	if tracker and tracker.Header then
		panel:SetPoint("TOPLEFT", tracker.Header, "BOTTOMLEFT", 12, -4)
	elseif tracker then
		panel:SetPoint("TOPLEFT", tracker, "TOPLEFT", 12, -30)
	else
		panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -80, -250)
	end
	local width = tracker and tracker:GetWidth() or 0
	panel:SetWidth(width > 50 and width - 24 or 220)
	panel:SetHeight(ROW * #rows)
	if lines[panel] then
		for _, line in ipairs(lines[panel]) do line:Hide() end
	end
	for i, row in ipairs(rows) do
		local line = ZoneLine(panel, i)
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -ROW * (i - 1))
		line:SetPoint("RIGHT", panel, "RIGHT")
		ShowLine(line, row.name, row.count)
	end
	panel:Show()
end

local panelPending = false
QueuePanel = function()
	if panelPending then return end
	panelPending = true
	-- Once the watch list has settled.
	C_Timer.After(0.1, function()
		panelPending = false
		local ok, err = pcall(UpdatePanel)
		if not ok and err ~= lastError then
			lastError = err
			print("|cffff8040QuestLogSort error:|r " .. tostring(err))
		end
	end)
end

local function PutBack(block)
	if lines[block] then
		for _, line in ipairs(lines[block]) do line:Hide() end
	end
	local points = saved[block]
	if not points then return end
	saved[block] = nil
	block.HeaderText:ClearAllPoints()
	for _, p in ipairs(points) do block.HeaderText:SetPoint(unpack(p)) end
end

local function OnHeader(block)
	local header = block and block.HeaderText
	if not (header and header.GetNumPoints) then return end
	-- Each update starts from where Blizzard puts the title.
	PutBack(block)
	if not (Enabled() and ByZone()) or InCombat() or type(block.height) ~= "number" then return end
	local id = block.poiQuestID or block.questID or block.id
	local entry = type(id) == "number" and Plan()[id]
	if not entry then return end
	local n = 0
	if entry.name then
		local points = {}
		for i = 1, header:GetNumPoints() do points[i] = { header:GetPoint(i) } end
		if #points == 0 then return end
		saved[block] = points
		header:ClearAllPoints()
		for _, p in ipairs(points) do header:SetPoint(p[1], p[2], p[3], p[4] or 0, (p[5] or 0) - entry.gap) end
		block.height = block.height + entry.gap
		-- Bottom up: this zone's line, then the folded zones above it.
		local stack = { { entry.name } }
		for i = #entry.above, 1, -1 do stack[#stack + 1] = { entry.above[i].name, entry.above[i].count } end
		for k, row in ipairs(stack) do
			n = n + 1
			local line = ZoneLine(block, n)
			line:ClearAllPoints()
			line:SetPoint("BOTTOMLEFT", header, "TOPLEFT", 0, 2 + ROW * (k - 1))
			line:SetPoint("RIGHT", block, "RIGHT")
			ShowLine(line, row[1], row[2])
		end
	end
	if entry.below then
		-- Folded zones after the last quest, in the space added at the bottom.
		block.height = block.height + entry.extra
		local hl, bl = header:GetLeft(), block:GetLeft()
		local indent = (hl and bl) and (hl - bl) or 0
		for i, row in ipairs(entry.below) do
			n = n + 1
			local line = ZoneLine(block, n)
			line:ClearAllPoints()
			line:SetPoint("BOTTOMLEFT", block, "BOTTOMLEFT", indent, ROW * (#entry.below - i))
			line:SetPoint("RIGHT", block, "RIGHT")
			ShowLine(line, row.name, row.count)
		end
	end
end

-- Same hooks as Kolapp: every *BlockMixin's SetHeader, and older trackers'
-- SetBlockHeader. Blocks copy the mixin when they are made, so this has to
-- run before the tracker makes any.
local hookedTables = {}
local function HookTracker()
	for name, value in pairs(_G) do
		if type(value) == "table" and type(name) == "string" and not hookedTables[value] then
			if name:find("BlockMixin") and type(rawget(value, "SetHeader")) == "function" then
				hookedTables[value] = true
				hooksecurefunc(value, "SetHeader", function(block) pcall(OnHeader, block) end)
			elseif name:find("TRACKER_MODULE") and type(rawget(value, "SetBlockHeader")) == "function" then
				hookedTables[value] = true
				hooksecurefunc(value, "SetBlockHeader", function(_, block) pcall(OnHeader, block) end)
			end
		end
	end
end

local trackerHook = CreateFrame("Frame")
trackerHook:RegisterEvent("ADDON_LOADED")
trackerHook:RegisterEvent("PLAYER_LOGIN")
trackerHook:SetScript("OnEvent", function(_, event, name)
	if event == "PLAYER_LOGIN" or name == "Blizzard_ObjectiveTracker" then HookTracker() end
end)
HookTracker()

SLASH_QUESTLOGSORT1 = "/qls"
SLASH_QUESTLOGSORT2 = "/questlogsort"
SlashCmdList.QUESTLOGSORT = function(msg)
	if not ready then return end
	msg = strtrim(msg or ""):lower()
	local zone = msg == "zon" or msg == "zone"
	if zone or msg == "nivå" or msg == "niva" or msg == "level" then
		QuestLogSortDB.trackerMode = zone and "zone" or nil
		failedOrder = nil -- the new order deserves a try
		if not zone then UnfoldAll() end
		QueuePanel()
		Say(zone and "trackern sorteras nu zon för zon, zonen du är i först: oklara först, sedan klara, efter nivå inom varje zon. Klicka på en zon för att fälla ihop den."
			or "trackern sorteras nu efter nivå: oklara först, sedan klara.")
		if not Enabled() then
			Say("sorteringen är avstängd just nu; /qls på slår på den.")
		elseif InCombat() then
			trackerAfterCombat = true
		else
			QueueTrackerSort()
		end
		return
	end
	if msg == "öppna" or msg == "oppna" or msg == "expand" then
		UnfoldAll()
		Say(InCombat() and "zonerna fälls ut när striden är över." or "alla zoner är utfällda.")
		return
	end
	local on
	if msg == "av" or msg == "off" then
		on = false
	elseif msg == "på" or msg == "pa" or msg == "on" then
		on = true
	elseif msg == "" then
		on = QuestLogSortDB.disabled -- no argument toggles
	else
		Say("/qls av stänger av all sortering (questloggen och trackern), /qls på slår på den igen. "
			.. "/qls zon sorterar trackern zon för zon (zonen du är i först; klicka på en zon för att fälla ihop den), "
			.. "/qls nivå bara efter nivå, /qls öppna fäller ut alla zoner. "
			.. "Nu: " .. (Enabled() and "på" or "av") .. ", trackern " .. (ByZone() and "zon för zon" or "efter nivå") .. ".")
		return
	end
	QuestLogSortDB.disabled = not on or nil
	QueuePanel()
	if on then
		Say("på. Questloggen och trackern sorteras igen.")
		if QuestScrollFrame and QuestScrollFrame:IsVisible() and not InCombat() then pcall(Reorder) end
		if InCombat() then trackerAfterCombat = true else QueueTrackerSort() end
	else
		-- Blizzard's own order comes back the next time the log refreshes;
		-- the tracker keeps its current order until something changes it.
		UnfoldAll()
		Say("av. Inget sorteras längre (sparas för alla dina karaktärer). /qls på slår på igen.")
	end
end
