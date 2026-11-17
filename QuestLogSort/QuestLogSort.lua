-- Completed quests at the bottom of each zone in the quest log (the map-style
-- log next to the world map).
--
-- Blizzard's QuestLogQuests_Update gives every row a layoutIndex and then lets
-- QuestScrollFrame.Contents (a vertical layout frame) stack them in that order.
-- Objective lines are anchored to their quest row, so they move with it.
--
-- 1.8: nothing is written into Blizzard's rows any more. Up to 1.7 we changed
-- their layoutIndex and topPadding and laid the log out again from addon
-- code, which tainted the world map's quest panel and could get Blizzard's
-- own actions blocked later ("Interface action failed because of an AddOn").
-- Now, after every layout, the rows of a zone are only moved: each keeps its
-- own anchors, shifted up or down so the zone's rows swap places. Moving a
-- frame that isn't protected doesn't taint anything, so it also works in
-- combat, and Blizzard's next layout simply starts over from its own order.

local hooked, lastError = false, nil

-- /qls av turns the whole addon off (saved per account), for players whose
-- own quest tracker (Questie) fights over the watch order. The hook on the
-- quest log can't be removed, so it just does nothing while off. Saved
-- variables arrive with our ADDON_LOADED; nothing sorts before that.
local ready = false
local function Enabled()
	return ready and not (QuestLogSortDB and QuestLogSortDB.disabled)
end

-- The tracker isn't re-sorted in combat (dungeons are mostly combat):
-- re-watching quests rebuilds the tracker, which can't move its quest item
-- buttons in combat. It catches up when combat ends.
local function InCombat()
	return InCombatLockdown and InCombatLockdown()
end

local function Report(ok, err)
	if not ok and err ~= lastError then
		lastError = err
		print("|cffff8040QuestLogSort error:|r " .. tostring(err))
	end
end

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

-- A row's anchors, all of which must be on the log's contents frame (where
-- the layout puts them), and the y offset of its top. nil if it's anchored
-- some other way; then the zone is left as Blizzard laid it out.
local function Anchors(frame, contents)
	local points, top = {}, nil
	for i = 1, frame:GetNumPoints() do
		local p = { frame:GetPoint(i) }
		if p[2] ~= contents then return end
		points[i] = p
		if not top and type(p[1]) == "string" and p[1]:find("^TOP") then top = p[5] or 0 end
	end
	if #points == 0 or not top then return end
	return points, top
end

local function Shift(frame, points, dy)
	frame:ClearAllPoints()
	for _, p in ipairs(points) do frame:SetPoint(p[1], p[2], p[3], p[4] or 0, (p[5] or 0) + dy) end
end

-- One zone: the places its rows take up (top to bottom, wherever they are
-- right now, so running this twice changes nothing) are filled again with
-- the unfinished quests first and the completed ones after, each in
-- Blizzard's order. The space below each place stays with the place.
local function ReorderGroup(group, contents)
	local open, done = {}, {}
	for _, frame in ipairs(group) do
		if C_QuestLog.IsComplete(frame.questID) then
			done[#done + 1] = frame
		else
			open[#open + 1] = frame
		end
	end
	if #done == 0 or #open == 0 then return end

	local rows = {}
	for _, frame in ipairs(group) do
		local points, top = Anchors(frame, contents)
		local height = frame:GetHeight()
		if not points or not height or height <= 0 then return end
		rows[#rows + 1] = { frame = frame, points = points, top = top, height = height }
	end
	local byFrame = {}
	for _, row in ipairs(rows) do byFrame[row.frame] = row end
	local places = { unpack(rows) }
	table.sort(places, function(a, b) return a.top > b.top end)
	local gaps = {}
	for i = 1, #places - 1 do
		gaps[i] = math.max(0, places[i].top - places[i + 1].top - places[i].height)
	end

	local y, k = places[1].top, 0
	for _, list in ipairs({ open, done }) do
		for _, frame in ipairs(list) do
			k = k + 1
			local row = byFrame[frame]
			if math.abs(y - row.top) > 0.01 then Shift(frame, row.points, y - row.top) end
			y = y - row.height - (gaps[k] or 0)
		end
	end
end

local function Reorder()
	if not Enabled() then return end
	local contents = QuestScrollFrame.Contents
	if not contents then return end
	for _, group in ipairs(Groups()) do ReorderGroup(group, contents) end
end

local function SafeReorder()
	Report(pcall(Reorder))
end

local function TryHook()
	if hooked or not QuestLogQuests_Update or not QuestScrollFrame
		or not QuestScrollFrame.titleFramePool or not C_QuestLog or not C_QuestLog.IsComplete then
		return
	end
	hooked = true
	hooksecurefunc("QuestLogQuests_Update", SafeReorder)
	-- The contents may also be laid out again on their own (a quest's
	-- objectives growing): every layout puts Blizzard's order back.
	local contents = QuestScrollFrame.Contents
	if contents and type(contents.Layout) == "function" then hooksecurefunc(contents, "Layout", SafeReorder) end
	-- The log may already be built; sort it now too.
	SafeReorder()
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
		Report(pcall(SortTracker))
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
		if not trackerAfterCombat then return end
		trackerAfterCombat = false
	end
	if InCombat() then trackerAfterCombat = true return end
	QueueTrackerSort()
end)

-- Zone lines beside the tracker, in zone mode: the first quest of each zone
-- gets the zone's name next to its title, on the side of the tracker that
-- has room (the left, unless the tracker sits at the screen's left edge).
--
-- 1.8: these are frames of our own, on UIParent, that only follow a block's
-- position and visibility. Up to 1.7 they sat inside the tracker, which
-- meant moving the block's title and growing block.height: a write into
-- Blizzard's tracker that tainted it, so its quest item buttons could get
-- "Interface action failed because of an AddOn". Nothing in the tracker is
-- written or moved now, so it also works in combat.
--
-- Clicking a zone line folds the zone up: its quests are unwatched (only
-- through the quest API, like the sorting) and remembered per character,
-- and the zone stays as a line "+ Westfall (3)" under the last quest.
-- Clicking that watches them again. A quest in a folded zone that gets
-- watched (a new quest, or the game watching one that made progress) is
-- folded away with the rest. Folding waits for combat to end.
local ROW = 16
local lines = setmetatable({}, { __mode = "k" })   -- our frame -> its zone line frames
local holders = setmetatable({}, { __mode = "k" }) -- tracker block -> our frame over it

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
-- tracker update asks): quest ID -> { name = the zone it starts, below =
-- folded zones, under the last quest }.
local plan, planAt = nil, nil
local function Plan()
	local now = GetTime()
	if plan and planAt == now then return plan end
	plan, planAt = {}, now
	local zones, names = ZoneOrder()
	local last, lastID = nil, nil
	for _, id in ipairs(WatchedQuests()) do
		local z = zones[id]
		if z then
			if z ~= last and names[z] then plan[id] = { name = names[z] } end
			last, lastID = z, id
		end
	end
	local rows = FoldedRows(names)
	if lastID and #rows > 0 then
		plan[lastID] = plan[lastID] or {}
		plan[lastID].below = rows
	end
	return plan
end

local function ZoneLine(owner, i)
	local list = lines[owner]
	if not list then
		list = {}
		lines[owner] = list
	end
	local line = list[i]
	if line then return line end
	line = CreateFrame("Frame", nil, owner)
	line:SetHeight(ROW - 2)
	line:EnableMouse(true)
	line.text = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	line.text:SetAllPoints()
	line:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
	line:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 0.82, 0) end)
	line:SetScript("OnMouseUp", function(self) if self.zone then ToggleZone(self.zone) end end)
	list[i] = line
	return line
end

-- The text sets the line's width, so it can hug the tracker from either side.
local function ShowLine(line, zone, count, justify)
	line.zone = zone
	if count then
		line.text:SetText("+ " .. zone .. " |cffa0a0a0(" .. count .. ")|r")
	else
		line.text:SetText("- " .. zone)
	end
	line.text:SetJustifyH(justify or "LEFT")
	line.text:SetTextColor(1, 0.82, 0)
	line:SetWidth(math.ceil(line.text:GetStringWidth() or 100) + 4)
	line:Show()
end

local function HideLines(owner)
	if owner and lines[owner] then
		for _, line in ipairs(lines[owner]) do line:Hide() end
	end
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
	HideLines(panel)
	for i, row in ipairs(rows) do
		local line = ZoneLine(panel, i)
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -ROW * (i - 1))
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
		Report(pcall(UpdatePanel))
	end)
end

-- Our frame over a tracker block: on UIParent, so the tracker's own frames
-- get nothing new, but anchored to the block and shown and hidden with it.
local function Holder(block)
	local h = holders[block]
	if h then return h end
	h = CreateFrame("Frame", nil, UIParent)
	h:SetAllPoints(block)
	h:SetFrameStrata(block:GetFrameStrata() or "MEDIUM")
	h:SetShown(block:IsVisible())
	block:HookScript("OnShow", function() h:Show() end)
	block:HookScript("OnHide", function() h:Hide() end)
	holders[block] = h
	return h
end

-- The left of the tracker, unless it is too close to the screen's edge.
local function LeftSide(block)
	local tracker = ObjectiveTrackerFrame or QuestWatchFrame or block
	local left = tracker:GetLeft()
	return not left or left * tracker:GetEffectiveScale() > 200
end

-- A line beside the holder: at its top edge, or under its bottom edge.
local function PlaceLine(line, h, left, edge, y)
	line:ClearAllPoints()
	if left then
		line:SetPoint("TOPRIGHT", h, edge .. "LEFT", -8, y)
	else
		line:SetPoint("TOPLEFT", h, edge .. "RIGHT", 8, y)
	end
end

local function OnHeader(block)
	if not block or (block.IsForbidden and block:IsForbidden()) then return end
	-- Each update starts from nothing shown.
	HideLines(holders[block])
	if not (Enabled() and ByZone()) then return end
	local id = block.poiQuestID or block.questID or block.id
	local entry = type(id) == "number" and Plan()[id]
	if not entry then return end
	local h = Holder(block)
	h:SetScale(block:GetEffectiveScale() / UIParent:GetEffectiveScale())
	local left = LeftSide(block)
	local justify = left and "RIGHT" or "LEFT"
	local n = 0
	if entry.name then
		-- Level with the quest's title.
		local header = block.HeaderText
		local ht, bt = header and header:GetTop(), block:GetTop()
		n = n + 1
		local line = ZoneLine(h, n)
		PlaceLine(line, h, left, "TOP", (ht and bt) and (ht - bt + 1) or 0)
		ShowLine(line, entry.name, nil, justify)
	end
	if entry.below then
		for i, row in ipairs(entry.below) do
			n = n + 1
			local line = ZoneLine(h, n)
			PlaceLine(line, h, left, "BOTTOM", -2 - ROW * (i - 1))
			ShowLine(line, row.name, row.count, justify)
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
		if QuestScrollFrame and QuestScrollFrame:IsVisible() then SafeReorder() end
		if InCombat() then trackerAfterCombat = true else QueueTrackerSort() end
	else
		-- Blizzard's own order comes back the next time the log refreshes;
		-- the tracker keeps its current order until something changes it.
		UnfoldAll()
		Say("av. Inget sorteras längre (sparas för alla dina karaktärer). /qls på slår på igen.")
	end
end
