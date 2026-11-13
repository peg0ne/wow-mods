-- Kölapp: where a quest sits in its quest chain, like a queue ticket.
-- The quest window's title gets "(2/4)" (offered, in progress, rewards and
-- the quest log's details), and so does the quest tracker. The quest log's
-- tooltip names the next quests, and chat says the number when you accept
-- a chain quest and what comes next when you hand one in (/kolapp tyst
-- turns the chat lines off).
--
-- The client has no quest chain data, so Data.lua carries the links from
-- Questie's database (built by tools/kolapp_data.py). A quest's number is
-- the longest run of earlier quests leading to it, plus one; the total adds
-- the longest run of later quests. Quests your race or class can't take
-- are left out, so a class quest branch only counts for that class.

local _, ns = ...
local quests = ns.quests

local defaults = { chat = true, items = true }
local db

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffe0b050Kölapp:|r " .. text)
end

-- Questie's race and class bits (bit n-1 for race/class ID n).
local RACE_IDS = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6, Gnome = 7, Troll = 8 }
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }

local raceID, classID, horde

local function HasBit(mask, id)
	if mask == 0 or not id then return true end
	return math.floor(mask / 2 ^ (id - 1)) % 2 == 1
end

local function Fits(id)
	local q = quests[id]
	return q and HasBit(q[2], raceID) and HasBit(q[3], classID)
end

local function Successors(id)
	local q, list = quests[id], {}
	if not q then return list end
	for _, field in ipairs({ 4, horde and 6 or 5 }) do
		for _, s in ipairs(q[field] or {}) do
			if Fits(s) then list[#list + 1] = s end
		end
	end
	return list
end

-- Built on first use, once race, class and faction are known.
local predecessors, depth, rest

local function Build()
	local _, raceFile = UnitRace("player")
	local _, classFile = UnitClass("player")
	raceID, classID = RACE_IDS[raceFile], CLASS_IDS[classFile]
	horde = UnitFactionGroup("player") == "Horde"
	predecessors, depth, rest = {}, {}, {}
	for id in pairs(quests) do
		if Fits(id) then
			for _, s in ipairs(Successors(id)) do
				predecessors[s] = predecessors[s] or {}
				table.insert(predecessors[s], id)
			end
		end
	end
end

-- The values set before recursing stop a loop in the data from recursing
-- forever.
local function Depth(id)
	if depth[id] then return depth[id] end
	depth[id] = 1
	local best = 0
	for _, p in ipairs(predecessors[id] or {}) do best = math.max(best, Depth(p)) end
	depth[id] = best + 1
	return depth[id]
end

local function Rest(id)
	if rest[id] then return rest[id] end
	rest[id] = 0
	local best = 0
	for _, s in ipairs(Successors(id)) do best = math.max(best, Rest(s) + 1) end
	rest[id] = best
	return best
end

-- Number and total for a quest in a chain, or nil.
local function Position(id)
	if not id or not quests[id] then return nil end
	if not predecessors then Build() end
	if not Fits(id) then return nil end
	local step = Depth(id)
	local total = step + Rest(id)
	if total < 2 then return nil end
	return step, total
end

local function Label(id)
	local step, total = Position(id)
	if step then return "(" .. step .. "/" .. total .. ")" end
end

ns.Label = Label

-- For Items.lua: can the player's race take a quest with this race mask?
function ns.RaceFits(mask)
	if not predecessors then Build() end
	return HasBit(mask or 0, raceID)
end

local function Name(id)
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
	return title or quests[id][1]
end

local function Done(id)
	return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id)
end

-- "Name (3/4)" for each next quest not done yet, or nil.
local function NextList(id)
	local names = {}
	for _, s in ipairs(Successors(id)) do
		if not Done(s) then names[#names + 1] = Name(s) .. " " .. (Label(s) or "") end
	end
	if #names > 0 then return names end
end

---------------------------------------------------------------------------
-- Quest window title (offered, progress, rewards, quest log details).

local function ShownQuestID()
	if QuestInfoFrame and QuestInfoFrame.questLog then
		return C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
	end
	return GetQuestID and GetQuestID()
end

local function MarkTitle()
	local header = QuestInfoTitleHeader
	if not header or not header:IsShown() then return end
	local label = Label(ShownQuestID())
	local text = header:GetText()
	if label and text and not text:find(label, 1, true) then
		header:SetText(text .. " " .. label)
	end
end

---------------------------------------------------------------------------
-- Quest log tooltip.

local function AddTooltip(button)
	local id = button and button.questID
	local step, total = Position(id)
	if not step or not GameTooltip:IsOwned(button) then return end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Questkedja: del " .. step .. " av " .. total, 1, 0.82, 0)
	for _, name in ipairs(NextList(id) or {}) do
		GameTooltip:AddLine("Nästa: " .. name, 1, 1, 1)
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Quest tracker. Its blocks set their title through a SetHeader method
-- (newer trackers, one copy per block mixin) or the module's SetBlockHeader
-- (older ones). After it runs we add the label to the title's font string
-- only. Calling SetHeader again from here (as 0.3 did) ran the tracker's
-- own code from addon code: every field it wrote on the block was tainted,
-- the tracker's layout read them, and in combat that ended in "Kolapp has
-- been blocked from an action". Changing only the shown text touches no
-- field the tracker reads. The block was sized for the plain title, so the
-- label is only added when it fits on the lines the title already uses.
-- A block is only labelled when its title contains the quest's title, so
-- blocks for achievements or other things with the same ID are left alone.

local hookedTables = {}

local function TrackerLabel(block, text)
	local id = block and (block.poiQuestID or block.questID or block.id)
	if type(id) ~= "number" or type(text) ~= "string" or not quests[id] then return end
	if issecretvalue and issecretvalue(text) then return end
	-- The title may come with the level in front, like "[21] Beren's Peril".
	if not text:find(Name(id), 1, true) and not text:find(quests[id][1], 1, true) then return end
	local label = Label(id)
	if label and not text:find(label, 1, true) then return label end
end

local function ShowLabel(block, text, label)
	local header = block.HeaderText
	if not header or not header.SetText then return end
	local lines = header.GetNumLines and header:GetNumLines()
	header:SetText(text .. " " .. label)
	-- The tracker already sized the block for the title; if the label would
	-- need another line or get cut off, leave the title as it was.
	if (header.IsTruncated and header:IsTruncated()) or (lines and header:GetNumLines() > lines) then
		header:SetText(text)
	end
end

local function HookTracker()
	for name, value in pairs(_G) do
		if type(value) == "table" and not hookedTables[value] and type(name) == "string" then
			if name:find("BlockMixin") and type(rawget(value, "SetHeader")) == "function" then
				hookedTables[value] = true
				hooksecurefunc(value, "SetHeader", function(block, text)
					local ok, label = pcall(TrackerLabel, block, text)
					if ok and label then ShowLabel(block, text, label) end
				end)
			elseif name:find("TRACKER_MODULE") and type(rawget(value, "SetBlockHeader")) == "function" then
				hookedTables[value] = true
				hooksecurefunc(value, "SetBlockHeader", function(_, block, text)
					local ok, label = pcall(TrackerLabel, block, text)
					if ok and label then ShowLabel(block, text, label) end
				end)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Chat.

local function OnAccepted(...)
	-- Retail sends (questID); older clients send (logIndex, questID).
	local id = select("#", ...) >= 2 and select(2, ...) or ...
	local step, total = Position(id)
	if db.chat and step then
		Print("nummer " .. step .. " av " .. total .. " i kedjan: " .. Name(id) .. ".")
	end
end

local function OnTurnedIn(id)
	local step, total = Position(id)
	if not db.chat or not step then return end
	local names = NextList(id)
	if names then
		Print("nästa i kedjan: " .. table.concat(names, " eller ") .. ".")
	elseif step == total then
		Print("kedjan är klar (" .. step .. "/" .. total .. ")!")
	end
end

---------------------------------------------------------------------------

local function Hook()
	if QuestInfo_Display then
		hooksecurefunc("QuestInfo_Display", function() pcall(MarkTitle) end)
	end
	if QuestMapLogTitleButton_OnEnter then
		hooksecurefunc("QuestMapLogTitleButton_OnEnter", function(button) pcall(AddTooltip, button) end)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_TURNED_IN")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" and ... == "Blizzard_ObjectiveTracker" then
		HookTracker()
	elseif event == "ADDON_LOADED" and ... == "Kolapp" then
		KolappDB = KolappDB or {}
		db = KolappDB
		ns.db = db
		db.trace = nil -- left by a 0.1 diagnostic
		for k, v in pairs(defaults) do
			if db[k] == nil then db[k] = v end
		end
	elseif event == "PLAYER_LOGIN" then
		Hook()
		HookTracker()
	elseif event == "QUEST_ACCEPTED" and db then
		OnAccepted(...)
	elseif event == "QUEST_TURNED_IN" and db then
		OnTurnedIn(...)
	end
end)

-- The tracker may already be loaded; hook it before it makes any blocks.
HookTracker()

SLASH_KOLAPP1 = "/kolapp"
SlashCmdList.KOLAPP = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "tyst" then
		db.chat = not db.chat
		Print("meddelanden i chatten är nu " .. (db.chat and "på" or "av") .. ".")
	elseif msg == "föremål" or msg == "foremal" then
		db.items = not db.items
		Print("uppdrag på föremålens tooltips är nu " .. (db.items and "på" or "av") .. ".")
	else
		Print("visar var en quest ligger i sin kedja, till exempel (2/4) i questfönstrets rubrik. "
			.. "Meddelanden i chatten: " .. (db.chat and "på" or "av") .. " (/kolapp tyst växlar). "
			.. "Uppdrag på föremål: " .. (db.items and "på" or "av") .. " (/kolapp föremål växlar).")
	end
end
