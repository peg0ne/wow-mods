-- Arbetsförmedlingen: shared quests for THÖNDERSTÖRM on WoW Forever.
-- Every member with the addon tells the guild which quests are in their
-- log (quest IDs only, and whether the objectives are done). /uppdrag
-- then lists the quests in your own log that online guild members also
-- have, and who they are. Nothing is kept about members once they go
-- offline; their log may have changed by the next time they log in.
--
-- Guild channel:
--   F                                     everyone: send your quest list
--   L;version;part;total;id[*],id[*],...  my quests, * = objectives done;
--                                         long lists come in several parts
--   W;id,id,...                           what are these quests called?
--   N;id;level;zone;title                 answer from one member who has it
--   J;version;id;tank;heal;dps;quest;level;text   Platsbanken: my listing
--   X;id                                  Platsbanken: my listing is gone
-- Whispers (Platsbanken, see Platsbanken.lua):
--   S;id;role   apply      I;id   invited      Z;id   application removed
--
-- The lists carry IDs only, so the names of quests you do not have come
-- from the game's own quest cache when it knows them, else from a member
-- who has the quest. The first answer wins; others who hear it stay quiet.
-- Names learned are kept in ArbetsformedlingenCharDB.titles.
--
-- Collapsed zones hide their quests from the quest log API, so the quests
-- last seen under each zone are kept in ArbetsformedlingenCharDB and used
-- while that zone stays collapsed.

local _, ns = ...

ns.GUILD = "THÖNDERSTÖRM"
ns.VERSION = "0.3"
ns.PREFIX = "UPPDRAG"
local CHUNK = 200

local char
ns.mine = {}     -- questID -> { title, level, zone, done }
ns.others = {}   -- name -> { [questID] = done }
local incoming = {}
local lastSent, sendQueued, lastAnswer, lastAsk, warnedVersion = nil, false, 0, 0, false

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffArbetsförmedlingen:|r " .. text)
end
ns.Print = Print

function ns.Short(name)
	if not name then return nil end
	if Ambiguate then return Ambiguate(name, "none") end
	return (name:gsub("%-.*", ""))
end

function ns.InOurGuild()
	return GetGuildInfo("player") == ns.GUILD
end

local RequestRoster = Statskontoret.RequestRoster
ns.RequestRoster = RequestRoster

-- This character's full name as the guild sees it. Forever names have two
-- words and UnitName gives only the first, so look it up by GUID in the
-- roster (as Skatteverket does); nil until the roster has loaded.
local myName
function ns.Me()
	if myName then return myName end
	local guid, first = UnitGUID("player"), UnitName("player")
	local match, count = nil, 0
	for i = 1, GetNumGuildMembers() do
		local info = { GetGuildRosterInfo(i) }
		local name = ns.Short(info[1])
		if name and guid and info[17] == guid then
			myName = name
			return name
		end
		if name and name:match("^(%S+)") == first then match, count = name, count + 1 end
	end
	if count == 1 then
		myName = match
		return match
	end
end

-- Whether a sender is this character, even before the roster has loaded.
function ns.IsMe(name)
	local me = ns.Me()
	if me then return name == me end
	return name == UnitName("player") or (name and name:match("^(%S+)") == UnitName("player"))
end

local function Send(msg)
	if not IsInGuild() then return end
	Statskontoret.SendAddon(ns.PREFIX, msg, "GUILD")
end
ns.Send = Send

-- An addon whisper to one member.
function ns.SendTo(target, msg)
	Statskontoret.SendAddon(ns.PREFIX, msg, "WHISPER", target)
end

local function Changed()
	if ns.RefreshWindow then ns.RefreshWindow() end
end
ns.Changed = Changed

local function IsComplete(id, fallback)
	if C_QuestLog and C_QuestLog.IsComplete then return C_QuestLog.IsComplete(id) and true or false end
	if IsQuestComplete then return IsQuestComplete(id) and true or false end
	return fallback
end

local function StillOnQuest(id)
	if C_QuestLog and C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(id) end
	return true
end

-- One pass over the quest log: { header, collapsed } rows and quest rows.
local function LogEntries()
	local entries = {}
	if C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries then
		for i = 1, (C_QuestLog.GetNumQuestLogEntries()) do
			local info = C_QuestLog.GetInfo(i)
			if info and info.isHeader then
				table.insert(entries, { header = info.title, collapsed = info.isCollapsed })
			elseif info and info.questID and info.questID > 0 then
				table.insert(entries, { id = info.questID, title = info.title, level = info.level,
					done = IsComplete(info.questID, false) })
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		for i = 1, (GetNumQuestLogEntries()) do
			local title, level, _, isHeader, isCollapsed, isComplete, _, questID = GetQuestLogTitle(i)
			if isHeader then
				table.insert(entries, { header = title, collapsed = isCollapsed })
			elseif questID and questID > 0 then
				table.insert(entries, { id = questID, title = title, level = level, done = isComplete == 1 })
			end
		end
	end
	return entries
end

-- Rebuild ns.mine from the quest log, filling collapsed zones from the cache.
local function ReadLog()
	local mine, cache = {}, {}
	local zone
	local function Keep(c)
		if c then
			for id, q in pairs(c) do
				if StillOnQuest(id) then
					mine[id] = { title = q.title, level = q.level, zone = zone, done = IsComplete(id, q.done) }
				end
			end
		end
	end
	for _, e in ipairs(LogEntries()) do
		if e.header then
			zone = e.header
			if e.collapsed then Keep(char.cache[zone]) end
		else
			mine[e.id] = { title = e.title, level = e.level, zone = zone or "", done = e.done }
		end
	end
	for id, q in pairs(mine) do
		local z = q.zone or ""
		cache[z] = cache[z] or {}
		cache[z][id] = { title = q.title, level = q.level, done = q.done }
	end
	char.cache = cache
	ns.mine = mine
	for id, q in pairs(mine) do
		if q.title then char.titles[id] = { title = q.title, level = q.level, zone = q.zone } end
	end
end
ns.ReadLog = function() if char then ReadLog() end end

-- Name, level and zone of any quest: our own log, names we have learned,
-- or the game's quest cache. nil when nobody has told us yet.
function ns.QuestInfo(id)
	local q = ns.mine[id] or (char and char.titles[id])
	if q and q.title then return q end
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
	if not title and C_QuestLog and C_QuestLog.GetQuestInfo then title = C_QuestLog.GetQuestInfo(id) end
	if title and title ~= "" then return { title = title } end
end

-- Ask the guild for the names of these quests, at most every 5 s and each
-- quest at most once a minute.
local askedAt, wanted, lookupQueued = {}, {}, false
function ns.LookUp(ids)
	local now = GetTime()
	for _, id in ipairs(ids) do
		if now - (askedAt[id] or -999) > 60 then wanted[id] = true end
	end
	if lookupQueued or not next(wanted) then return end
	lookupQueued = true
	C_Timer.After(1, function()
		lookupQueued = false
		local list, length = {}, 0
		for id in pairs(wanted) do
			local item = tostring(id)
			if length + #item + 1 > CHUNK then break end
			table.insert(list, item)
			length = length + #item + 1
			askedAt[id], wanted[id] = GetTime(), nil
		end
		if #list > 0 then Send("W;" .. table.concat(list, ",")) end
		if next(wanted) then C_Timer.After(5, function() ns.LookUp({}) end) end
	end)
end

-- Names someone else has already given since a question; we skip those.
local answered = {}
local function OnWhat(parts)
	for item in (parts[2] or ""):gmatch("[^,]+") do
		local id = tonumber(item)
		local q = id and ns.mine[id]
		if q and q.title then
			answered[id] = nil
			C_Timer.After(math.random() * 3, function()
				if answered[id] then return end
				answered[id] = true
				local title = q.title:gsub(";", ","):sub(1, 150)
				local zone = (q.zone or ""):gsub(";", ","):sub(1, 50)
				Send(string.format("N;%d;%s;%s;%s", id, tostring(q.level or ""), zone, title))
			end)
		end
	end
end

local function OnName(parts)
	local id = tonumber(parts[2])
	if not id or not parts[5] or parts[5] == "" then return end
	answered[id] = true
	if not ns.mine[id] then
		char.titles[id] = { title = parts[5], level = tonumber(parts[3]), zone = parts[4] ~= "" and parts[4] or nil }
		Changed()
	end
end

-- The quest list as message parts, each well under the 255 byte limit.
local function Encode()
	local ids = {}
	for id in pairs(ns.mine) do table.insert(ids, id) end
	table.sort(ids)
	local parts, current = {}, {}
	local length = 0
	for _, id in ipairs(ids) do
		local item = tostring(id) .. (ns.mine[id].done and "*" or "")
		if length + #item + 1 > CHUNK and #current > 0 then
			table.insert(parts, table.concat(current, ","))
			current, length = {}, 0
		end
		table.insert(current, item)
		length = length + #item + 1
	end
	table.insert(parts, table.concat(current, ","))
	return parts
end

local function SendList(force)
	if not char or not ns.InOurGuild() then return end
	ReadLog()
	local parts = Encode()
	local whole = table.concat(parts, "|")
	Changed()
	if whole == lastSent and not force then return end
	lastSent = whole
	for i, part in ipairs(parts) do
		Send(string.format("L;%s;%d;%d;%s", ns.VERSION, i, #parts, part))
	end
end

-- The quest log changes in bursts; send once it has settled.
local function QueueSend()
	if sendQueued then return end
	sendQueued = true
	C_Timer.After(2, function()
		sendQueued = false
		SendList(false)
	end)
end

function ns.Ask()
	if GetTime() - lastAsk < 10 then return end
	lastAsk = GetTime()
	Send("F")
	RequestRoster()
end

local function VersionNumber(v)
	local major, minor = tostring(v or ""):match("^(%d+)%.(%d+)")
	return major and (tonumber(major) * 1000 + tonumber(minor)) or 0
end

local function OnList(sender, parts)
	local version, part, total = parts[2], tonumber(parts[3]), tonumber(parts[4])
	if not warnedVersion and VersionNumber(version) > VersionNumber(ns.VERSION) then
		warnedVersion = true
		Print("det finns en nyare Arbetsförmedlingen (" .. version .. "); be gildeledaren om den.")
	end
	if not part or not total then return end
	if part == 1 then incoming[sender] = {} end
	local list = incoming[sender]
	if not list then return end
	for item in (parts[5] or ""):gmatch("[^,]+") do
		local id, star = item:match("^(%d+)(%*?)$")
		if id then list[tonumber(id)] = star == "*" end
	end
	if part >= total then
		ns.others[sender] = list
		incoming[sender] = nil
		Changed()
	end
end

local function OnAddonMessage(prefix, msg, channel, sender)
	if prefix ~= ns.PREFIX or not char or not ns.InOurGuild() then return end
	sender = ns.Short(sender)
	if ns.IsMe(sender) then return end
	local parts = { strsplit(";", msg) }
	if channel == "WHISPER" then
		if ns.OnPlatsWhisper then ns.OnPlatsWhisper(sender, parts) end
		return
	end
	if channel ~= "GUILD" then return end
	if parts[1] == "F" then
		-- Many answer at once; spread the answers out and answer at most every 5 s.
		if GetTime() - lastAnswer > 5 then
			lastAnswer = GetTime()
			C_Timer.After(math.random() * 4, function()
				SendList(true)
				if ns.OnPlatsAsked then ns.OnPlatsAsked() end
			end)
		end
	elseif parts[1] == "J" or parts[1] == "X" then
		if ns.OnPlatsGuild then ns.OnPlatsGuild(sender, parts) end
	elseif parts[1] == "L" then
		OnList(sender, parts)
	elseif parts[1] == "W" then
		OnWhat(parts)
	elseif parts[1] == "N" then
		OnName(parts)
	end
end

-- Forget members who went offline or left the guild.
local function Prune()
	local n = GetNumGuildMembers()
	if n == 0 then return end
	local online = {}
	for i = 1, n do
		local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
		if name and isOnline then online[ns.Short(name)] = true end
	end
	if ns.PrunePlats then ns.PrunePlats(online) end
	local changed = false
	for name in pairs(ns.others) do
		if not online[name] then
			ns.others[name], incoming[name] = nil, nil
			changed = true
		end
	end
	if changed then Changed() end
end

-- Your quests that online members also have: { id, title, level, zone, done, members = { {name, done} } }.
function ns.Shared()
	local list = {}
	for id, q in pairs(ns.mine) do
		local members = ns.MembersOn(id)
		if #members > 0 then
			table.insert(list, { id = id, title = q.title, level = q.level, zone = q.zone, done = q.done, members = members })
		end
	end
	table.sort(list, function(a, b)
		if #a.members ~= #b.members then return #a.members > #b.members end
		if a.zone ~= b.zone then return (a.zone or "") < (b.zone or "") end
		return (a.title or "") < (b.title or "")
	end)
	return list
end

-- Quests online members have that you do not: { id, title, level, zone, members }.
-- Quests whose names are not known yet are asked for and shown by number.
function ns.Wanted()
	local byId, unknown = {}, {}
	for name, quests in pairs(ns.others) do
		if not ns.IsMe(name) then
			for id, done in pairs(quests) do
				if not ns.mine[id] then
					byId[id] = byId[id] or {}
					table.insert(byId[id], { name = name, done = done })
				end
			end
		end
	end
	local list = {}
	for id, members in pairs(byId) do
		table.sort(members, function(a, b) return a.name < b.name end)
		local q = ns.QuestInfo(id)
		if not q then table.insert(unknown, id) end
		q = q or {}
		table.insert(list, { id = id, title = q.title, level = q.level, zone = q.zone, members = members })
	end
	if #unknown > 0 then ns.LookUp(unknown) end
	table.sort(list, function(a, b)
		if #a.members ~= #b.members then return #a.members > #b.members end
		if (a.zone or "") ~= (b.zone or "") then return (a.zone or "") < (b.zone or "") end
		if (a.title or "") ~= (b.title or "") then return (a.title or "") < (b.title or "") end
		return a.id < b.id
	end)
	return list
end

-- Online members who have this quest, as { name, done }.
function ns.MembersOn(id)
	local members = {}
	for name, quests in pairs(ns.others) do
		if quests[id] ~= nil and not ns.IsMe(name) then table.insert(members, { name = name, done = quests[id] }) end
	end
	table.sort(members, function(a, b) return a.name < b.name end)
	return members
end

function ns.CountOthers()
	local n = 0
	for _ in pairs(ns.others) do n = n + 1 end
	return n
end

local events = CreateFrame("Frame")
for _, event in ipairs({
	"ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE",
	"QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
}) do
	-- Not every client has every event; an unknown one would raise an error.
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "Arbetsformedlingen" then
			ArbetsformedlingenCharDB = ArbetsformedlingenCharDB or {}
			char = ArbetsformedlingenCharDB
			char.cache = char.cache or {}
			char.titles = char.titles or {}
			ns.char = char
		end
	elseif not char then
		return
	elseif event == "PLAYER_LOGIN" then
		local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
		if register then register(ns.PREFIX) end
		RequestRoster()
		C_Timer.After(15, function()
			SendList(true)
			ns.Ask()
			if ns.PlatsLogin then ns.PlatsLogin() end
		end)
	elseif event == "CHAT_MSG_ADDON" then
		OnAddonMessage(...)
	elseif event == "GUILD_ROSTER_UPDATE" then
		Prune()
	else
		QueueSend()
	end
end)

SLASH_ARBETSFORMEDLINGEN1 = "/uppdrag"
SLASH_ARBETSFORMEDLINGEN2 = "/af"
SlashCmdList.ARBETSFORMEDLINGEN = function(msg)
	if not ns.InOurGuild() then
		Print("den här karaktären är inte med i " .. ns.GUILD .. ".")
		return
	end
	local cmd = (msg or ""):lower():match("^%s*(%S*)")
	if cmd == "tyst" then
		char.quiet = not char.quiet
		Print(char.quiet and "nya annonser i Platsbanken visas inte längre i chatten." or "nya annonser i Platsbanken visas i chatten igen.")
	elseif cmd == "" then
		ns.ToggleWindow()
	else
		Print("/uppdrag öppnar fönstret, /platsbanken öppnar Platsbanken, /uppdrag tyst stänger av chattraderna om nya annonser.")
	end
end

SLASH_PLATSBANKEN1 = "/platsbanken"
SlashCmdList.PLATSBANKEN = function()
	if not ns.InOurGuild() then
		Print("den här karaktären är inte med i " .. ns.GUILD .. ".")
		return
	end
	ns.ToggleWindow("plats")
end
