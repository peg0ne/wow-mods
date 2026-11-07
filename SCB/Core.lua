-- SCB (Statistiska centralbyrån): guild statistics for THÖNDERSTÖRM on
-- WoW Forever. Each character counts its own:
--   deaths     from Rättsmedicinalverket, by cause (fall, drowning, NPC,
--              hostile player, other)
--   kills      kills that gave experience (the "X dies, you gain N
--              experience" line; the combat log is closed to addons)
--   quests     quests handed in
--   earned / spent   gold gained and lost (vendor, loot, mail, trade ...)
--   played     time played: taken from /played when you type it, and
--              counted while you are logged in
-- and shares the totals with the guild, where everyone keeps everyone's
-- latest figures between sessions.
--
-- Guild channel:
--   F                                   everyone: send your figures
--   S;version;level;class;deaths;fall;drown;npc;pvp;kills;quests;earned;spent;played;stamp

local _, ns = ...

ns.GUILD = "THÖNDERSTÖRM"
ns.VERSION = "0.1"
ns.PREFIX = "SCB"
local SEND_EVERY = 600

local db, char
local lastSent, lastSentAt, lastAnswer, lastAsk, warnedVersion = nil, 0, 0, 0, false
local sessionStart, lastMoney

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66aaccSCB:|r " .. text)
end
ns.Print = Print

local function Plain(v)
	if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
	return v
end

function ns.Short(name)
	if not name then return nil end
	if Ambiguate then return Ambiguate(name, "none") end
	return (name:gsub("%-.*", ""))
end

function ns.InOurGuild()
	return GetGuildInfo("player") == ns.GUILD
end

-- This character's full name as the guild sees it (two-word Forever names;
-- see Arbetsförmedlingen).
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

function ns.IsMe(name)
	local me = ns.Me()
	if me then return name == me end
	return name == UnitName("player") or (name and name:match("^(%S+)") == UnitName("player"))
end

local function Send(msg)
	if not IsInGuild() then return end
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(ns.PREFIX, msg, "GUILD")
	elseif SendAddonMessage then
		SendAddonMessage(ns.PREFIX, msg, "GUILD")
	end
end

local function Changed()
	if ns.RefreshWindow then ns.RefreshWindow() end
end

---------------------------------------------------------------------------
-- Own counting.

local FIELDS = { "deaths", "fall", "drown", "npc", "pvp", "kills", "quests", "earned", "spent" }

function ns.Played()
	if not char.played then return nil end
	return char.played + (GetTime() - sessionStart)
end

local function OnDeath(r)
	if not r.me then return end
	char.deaths = char.deaths + 1
	if r.kind == "environment" and r.env == "Falling" then char.fall = char.fall + 1
	elseif r.kind == "environment" and r.env == "Drowning" then char.drown = char.drown + 1
	elseif (r.kind == "player" and r.hostile) or r.blame then char.pvp = char.pvp + 1
	elseif r.kind == "npc" or r.kind == "pet" then char.npc = char.npc + 1 end
	Changed()
end

-- "%s dies, you gain %d experience." and its group, raid and rested
-- variants all start the same way; match that start in any language.
local killPattern
local function KillPattern()
	if killPattern ~= nil then return killPattern end
	local template = COMBATLOG_XPGAIN_FIRSTPERSON
	local head = template and template:match("^(.-)%%d")
	if not head then
		killPattern = false
		return false
	end
	head = head:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", ".+")
	killPattern = "^" .. head
	return killPattern
end

local function OnXP(msg)
	msg = Plain(msg)
	local pattern = KillPattern()
	if msg and pattern and msg:find(pattern) then
		char.kills = char.kills + 1
	end
end

local function OnMoney()
	local now = GetMoney()
	if lastMoney then
		local delta = now - lastMoney
		if delta > 0 then char.earned = char.earned + delta elseif delta < 0 then char.spent = char.spent - delta end
	end
	lastMoney = now
end

---------------------------------------------------------------------------
-- Sharing.

local function Figures()
	local f = { UnitLevel("player"), select(2, UnitClass("player")) or "" }
	for _, key in ipairs(FIELDS) do table.insert(f, math.floor(char[key] or 0)) end
	table.insert(f, math.floor(ns.Played() or 0))
	return table.concat(f, ";")
end

local function SendFigures(force)
	if not char or not ns.InOurGuild() then return end
	local figures = Figures()
	if not force and figures == lastSent then return end
	lastSent, lastSentAt = figures, GetTime()
	Send(string.format("S;%s;%s;%d", ns.VERSION, figures, time()))
end

function ns.Ask()
	if GetTime() - lastAsk < 10 then return end
	lastAsk = GetTime()
	Send("F")
end

local function VersionNumber(v)
	local major, minor = tostring(v or ""):match("^(%d+)%.(%d+)")
	return major and (tonumber(major) * 1000 + tonumber(minor)) or 0
end

local function OnFigures(sender, f)
	if not warnedVersion and VersionNumber(f[2]) > VersionNumber(ns.VERSION) then
		warnedVersion = true
		Print("det finns en nyare SCB (" .. f[2] .. "); be gildeledaren om den.")
	end
	local m = { level = tonumber(f[3]), class = f[4] ~= "" and f[4] or nil, seen = time() }
	for i, key in ipairs(FIELDS) do m[key] = tonumber(f[4 + i]) or 0 end
	m.played = tonumber(f[14])
	if m.played == 0 then m.played = nil end
	db.members[sender] = m
	Changed()
end

local function OnAddonMessage(prefix, msg, channel, sender)
	if prefix ~= ns.PREFIX or channel ~= "GUILD" or not char or not ns.InOurGuild() then return end
	sender = ns.Short(sender)
	if not sender or ns.IsMe(sender) then return end
	local f = { strsplit(";", msg) }
	if f[1] == "F" then
		if GetTime() - lastAnswer > 5 then
			lastAnswer = GetTime()
			C_Timer.After(math.random() * 4, function() SendFigures(true) end)
		end
	elseif f[1] == "S" then
		OnFigures(sender, f)
	end
end

local function OnRoster()
	if GetNumGuildMembers() == 0 or not (GetGuildRosterShowOffline and GetGuildRosterShowOffline()) then return end
	local all = {}
	for i = 1, GetNumGuildMembers() do
		local name = ns.Short(GetGuildRosterInfo(i))
		if name then all[name] = true end
	end
	for name in pairs(db.members) do
		if not all[name] then db.members[name] = nil end
	end
end

---------------------------------------------------------------------------
-- Tables for the window.

-- Everyone with figures, own character included: { name, me, level, class, deaths, ... played }.
function ns.People()
	local people = {}
	local me = { name = ns.Me() or UnitName("player"), me = true, level = UnitLevel("player"),
		class = select(2, UnitClass("player")), played = ns.Played() }
	for _, key in ipairs(FIELDS) do me[key] = char[key] or 0 end
	table.insert(people, me)
	for name, m in pairs(db.members) do
		if not ns.IsMe(name) then
			local p = { name = name }
			for k, v in pairs(m) do p[k] = v end
			table.insert(people, p)
		end
	end
	return people
end

function ns.Totals(people)
	local t = { members = #people }
	for _, key in ipairs(FIELDS) do t[key] = 0 end
	t.played = 0
	for _, p in ipairs(people) do
		for _, key in ipairs(FIELDS) do t[key] = t[key] + (p[key] or 0) end
		t.played = t.played + (p.played or 0)
	end
	return t
end

local function Most(people, key)
	local best
	for _, p in ipairs(people) do
		if (p[key] or 0) > 0 and (not best or p[key] > best[key]) then best = p end
	end
	return best
end

function ns.Hours(seconds)
	if not seconds then return "?" end
	local h = math.floor(seconds / 3600)
	if h >= 48 then return string.format("%d d %d h", math.floor(h / 24), h % 24) end
	return string.format("%d h %d min", h, math.floor(seconds / 60) % 60)
end

function ns.Gold(copper)
	return string.format("%dg", math.floor((copper or 0) / 10000))
end

local function Pct(part, whole)
	if whole <= 0 then return 0 end
	return math.floor(part / whole * 100 + 0.5)
end

-- A few sentences about the guild, picked from what is notable right now.
function ns.Facts(people)
	local t = ns.Totals(people)
	local facts = {}
	local function Name(p) return p.me and "du" or p.name end
	if t.deaths > 0 then
		table.insert(facts, string.format("%s har dött %d gånger; %d%% av dem var fall, %d%% mot andra spelare.",
			ns.GUILD, t.deaths, Pct(t.fall, t.deaths), Pct(t.pvp, t.deaths)))
	end
	if t.kills > 0 and t.deaths > 0 then
		table.insert(facts, string.format("Gillet dödar %.1f fiender per dödsfall.", t.kills / t.deaths))
	end
	local p = Most(people, "deaths")
	if p and p.deaths >= 3 then table.insert(facts, string.format("Flest dödsfall: %s (%d).", Name(p), p.deaths)) end
	p = Most(people, "fall")
	if p and p.fall >= 2 then table.insert(facts, string.format("%s har fallit ihjäl %d gånger. Gillet erbjuder fallskärm.", Name(p), p.fall)) end
	p = Most(people, "quests")
	if p then table.insert(facts, string.format("Flitigast med uppdrag: %s (%d).", Name(p), p.quests)) end
	p = Most(people, "kills")
	if p then table.insert(facts, string.format("Flest dödade fiender: %s (%d).", Name(p), p.kills)) end
	p = Most(people, "earned")
	if p then table.insert(facts, string.format("Mest guld in: %s (%s).", Name(p), ns.Gold(p.earned))) end
	if t.played > 0 then
		table.insert(facts, string.format("Tillsammans har gillet spelat %s (av de som skrivit /played).", ns.Hours(t.played)))
	end
	return facts
end

---------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE",
	"CHAT_MSG_COMBAT_XP_GAIN", "QUEST_TURNED_IN", "PLAYER_MONEY", "TIME_PLAYED_MSG", "PLAYER_LEVEL_UP" }) do
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "SCB" then
			SCBDB = SCBDB or {}
			db = SCBDB
			db.members = db.members or {}
			SCBCharDB = SCBCharDB or {}
			char = SCBCharDB
			for _, key in ipairs(FIELDS) do char[key] = char[key] or 0 end
			sessionStart = GetTime()
			if Rattsmedicinalverket then Rattsmedicinalverket.Register(OnDeath) end
		end
	elseif not char then
		return
	elseif event == "PLAYER_LOGIN" then
		lastMoney = GetMoney()
		local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
		if register then register(ns.PREFIX) end
		C_Timer.After(20, function()
			SendFigures(true)
			ns.Ask()
		end)
		C_Timer.NewTicker(60, function()
			if GetTime() - lastSentAt >= SEND_EVERY then SendFigures(false) end
		end)
	elseif event == "PLAYER_LOGOUT" then
		char.played = ns.Played()
	elseif event == "CHAT_MSG_ADDON" then
		OnAddonMessage(...)
	elseif event == "GUILD_ROSTER_UPDATE" then
		OnRoster()
	elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
		OnXP(...)
		Changed()
	elseif event == "QUEST_TURNED_IN" then
		char.quests = char.quests + 1
		Changed()
	elseif event == "PLAYER_MONEY" then
		OnMoney()
		Changed()
	elseif event == "TIME_PLAYED_MSG" then
		local total = Plain((...))
		if type(total) == "number" then
			char.played, sessionStart = total, GetTime()
			Changed()
		end
	elseif event == "PLAYER_LEVEL_UP" then
		C_Timer.After(1, function() SendFigures(true) end)
	end
end)

SLASH_SCB1 = "/scb"
SLASH_SCB2 = "/statistik"
SlashCmdList.SCB = function()
	ns.ToggleWindow()
end
