-- Rättsmedicinalverket: death records for THÖNDERSTÖRM on WoW Forever.
-- When you die it reads the game's Death Recap (the combat log is closed
-- to addons on Forever) and works out what killed you. Values the client
-- marks secret are treated as unknown. The record goes to the guild,
-- so every member with the addon gets the same record for every member's
-- death. It shows nothing itself; other addons listen:
--
--   Rattsmedicinalverket.Register(function(record) ... end)
--   Rattsmedicinalverket.Deaths()   -- the saved log, oldest first
--
-- A record:
--   id            victim .. ":" .. the victim's time() at death (unique)
--   victim, me    who died; me = true for this character
--   victimLevel, victimClass (class file, e.g. "WARRIOR")
--   kind          "player", "pet", "npc", "environment" or "unknown"
--   killer, killerGUID, killerLevel (-1 = skull), killerClass, killerRace
--   hostile       the killer was hostile
--   ability, amount     the killing blow ("" ability = melee)
--   env           environment damage: "Falling", "Drowning", "Fatigue",
--                 "Fire", "Lava" or "Slime"
--   blame, blameGUID, blameLevel, blameClass, blameRace
--                 when the killer was not a hostile player but a hostile
--                 player is in the recap: the one who did most damage
--   zone, subzone, map, x, y (0-1), time (the receiver's time())
--
-- Guild channel:
--   D;version;victimLevel;victimClass;kind;killer;killerGUID;killerLevel;
--     killerClass;killerRace;hostile;ability;amount;env;zone;subzone;map;
--     x;y;blame;blameGUID;blameLevel;blameClass;blameRace;stamp

local _, ns = ...

ns.GUILD = "THÖNDERSTÖRM"
ns.VERSION = "0.1"
ns.PREFIX = "RMV"
local KEEP = 500        -- deaths kept in the saved log

local API = {}
Rattsmedicinalverket = API

local db
local listeners = {}
local levels, levelCount = {}, 0
local lastRecap         -- the recap ID already used, so an old recap is never reused

-- The client may hand addons "secret" values that cannot be compared or
-- printed; treat those as unknown.
local function Plain(v)
	if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
	return v
end

local band = bit.band
local TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400
local TYPE_PET = COMBATLOG_OBJECT_TYPE_PET or 0x1000
local TYPE_GUARDIAN = COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x2000
local HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40

function API.Register(fn)
	table.insert(listeners, fn)
end

function API.Deaths()
	return db and db.deaths or {}
end

local function Short(name)
	if not name then return nil end
	if Ambiguate then return Ambiguate(name, "none") end
	return (name:gsub("%-.*", ""))
end

local function InOurGuild()
	return GetGuildInfo("player") == ns.GUILD
end

-- This character's full name as the guild sees it (two-word Forever names;
-- see Arbetsförmedlingen).
local myName
local function Me()
	if myName then return myName end
	local guid, first = UnitGUID("player"), UnitName("player")
	local match, count = nil, 0
	for i = 1, GetNumGuildMembers() do
		local info = { GetGuildRosterInfo(i) }
		local name = Short(info[1])
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

local function IsMe(name)
	local me = Me()
	if me then return name == me end
	return name == UnitName("player") or (name and name:match("^(%S+)") == UnitName("player"))
end

---------------------------------------------------------------------------
-- Levels are only known while a unit is in view, so note them as they pass.

local function Note(unit)
	local guid = UnitExists(unit) and Plain(UnitGUID(unit))
	if not guid then return end
	if levelCount > 1000 then levels, levelCount = {}, 0 end
	if not levels[guid] then levelCount = levelCount + 1 end
	levels[guid] = Plain(UnitLevel(unit))
end

local function PlayerInfo(guid)
	if not guid or not GetPlayerInfoByGUID then return end
	local ok, _, class, _, race = pcall(GetPlayerInfoByGUID, guid)
	if ok then return Plain(class), Plain(race) end
end

---------------------------------------------------------------------------
-- The Death Recap: the last hits before death, as
-- { t, guid, name, flags, ability, amount, env }.

local function RecapID()
	if not GetDeathRecapLink then return end
	local ok, link = pcall(GetDeathRecapLink)
	link = ok and Plain(link)
	local id = type(link) == "string" and link:match("death:(%d+)")
	return id and tonumber(id)
end

local function RecapEvents()
	local id = RecapID()
	if not id or id == lastRecap then return end
	local get = (C_DeathRecap and C_DeathRecap.GetRecapEvents) or DeathRecap_GetEvents
	if not get then return end
	local ok, events = pcall(get, id)
	if not ok or type(events) ~= "table" or #events == 0 then return end
	lastRecap = id
	local list = {}
	for _, e in ipairs(events) do
		local amount = Plain(e.amount)
		if type(amount) == "number" then
			table.insert(list, {
				t = Plain(e.timestamp) or 0, guid = Plain(e.sourceGUID), name = Plain(e.sourceName),
				flags = Plain(e.sourceFlags), ability = Plain(e.spellName) or "", amount = amount,
				env = Plain(e.environmentalType),
			})
		end
	end
	return list
end

-- What kind of thing a source is: from its flags, else from its GUID.
local function Kind(e)
	if e.flags then
		if band(e.flags, TYPE_PLAYER) > 0 then return "player" end
		if band(e.flags, TYPE_PET) > 0 or band(e.flags, TYPE_GUARDIAN) > 0 then return "pet" end
		return "npc"
	end
	local prefix = e.guid and e.guid:match("^(%a+)%-")
	if prefix == "Player" then return "player" end
	if prefix == "Pet" then return "pet" end
	if prefix then return "npc" end
	return "unknown"
end

-- Hostile from the flags; without flags, any other player in the recap
-- (duels end before death, and group members do not hit you).
local function Hostile(e)
	if e.flags then return band(e.flags, HOSTILE) > 0 end
	return Kind(e) == "player" or Kind(e) == "npc"
end

local function Position()
	if not C_Map or not C_Map.GetBestMapForUnit then return end
	local map = C_Map.GetBestMapForUnit("player")
	local pos = map and C_Map.GetPlayerMapPosition(map, "player")
	if not pos then return map end
	return map, pos:GetXY()
end

---------------------------------------------------------------------------
-- Records.

local function Store(record)
	table.insert(db.deaths, record)
	while #db.deaths > KEEP do table.remove(db.deaths, 1) end
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, record)
		if not ok and geterrorhandler then geterrorhandler()(err) end
	end
end

local function Clean(text, max)
	return tostring(text or ""):gsub("[;|]", ","):sub(1, max or 40)
end

local function Broadcast(r)
	if not IsInGuild() or not InOurGuild() then return end
	local fields = {
		"D", ns.VERSION, r.victimLevel or "", r.victimClass or "", r.kind,
		Clean(r.killer), r.killerGUID or "", r.killerLevel or "", r.killerClass or "", Clean(r.killerRace, 20),
		r.hostile and "1" or "0", Clean(r.ability), r.amount or "", r.env or "",
		Clean(r.zone), Clean(r.subzone), r.map or "",
		r.x and math.floor(r.x * 10000) or "", r.y and math.floor(r.y * 10000) or "",
		Clean(r.blame), r.blameGUID or "", r.blameLevel or "", r.blameClass or "", Clean(r.blameRace, 20),
		r.stamp,
	}
	for i, v in ipairs(fields) do fields[i] = tostring(v) end
	local msg = table.concat(fields, ";")
	if #msg > 254 then
		fields[16] = ""   -- subzone is the least needed
		msg = table.concat(fields, ";"):sub(1, 254)
	end
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(ns.PREFIX, msg, "GUILD")
	elseif SendAddonMessage then
		SendAddonMessage(ns.PREFIX, msg, "GUILD")
	end
end

-- Fill in the killer from the recap's hits.
local function Examine(r, hits)
	local last
	for _, e in ipairs(hits) do
		if not last or e.t >= last.t then last = e end
	end
	if not last then return end
	r.amount = last.amount
	if last.env then
		r.kind, r.env = "environment", last.env
	else
		r.kind = Kind(last)
		r.killer, r.killerGUID, r.ability = last.name, last.guid, last.ability
		r.hostile = Hostile(last)
		r.killerLevel = last.guid and levels[last.guid]
		if r.kind == "player" then r.killerClass, r.killerRace = PlayerInfo(last.guid) end
	end
	-- Someone else landed the blow (a pet, a guard, the fall): blame the
	-- hostile player who did the most damage in the recap, if any.
	if r.kind == "player" and r.hostile then return end
	local dealt, names = {}, {}
	for _, e in ipairs(hits) do
		if e.guid and Kind(e) == "player" and Hostile(e) then
			dealt[e.guid] = (dealt[e.guid] or 0) + e.amount
			names[e.guid] = e.name
		end
	end
	local best
	for guid, amount in pairs(dealt) do
		if not best or amount > dealt[best] then best = guid end
	end
	if best then
		r.blame, r.blameGUID, r.blameLevel = names[best], best, levels[best]
		r.blameClass, r.blameRace = PlayerInfo(best)
	end
end

local function OnDeath()
	local stamp = time()
	local victim = Me() or UnitName("player")
	local map, x, y = Position()
	local r = {
		id = victim .. ":" .. stamp, stamp = stamp, time = stamp, victim = victim, me = true,
		victimLevel = UnitLevel("player"), victimClass = select(2, UnitClass("player")),
		zone = GetRealZoneText and GetRealZoneText() or GetZoneText(), subzone = GetSubZoneText(),
		map = map, x = x, y = y, kind = "unknown",
	}
	-- The recap may take a moment to fill; try for a few seconds.
	local tries = 0
	local function Try()
		tries = tries + 1
		local hits = RecapEvents()
		if not hits and tries < 4 then
			C_Timer.After(1, Try)
			return
		end
		if hits then Examine(r, hits) end
		Store(r)
		Broadcast(r)
	end
	C_Timer.After(0.5, Try)
end

local function OnAddonMessage(prefix, msg, channel, sender)
	if prefix ~= ns.PREFIX or channel ~= "GUILD" or not InOurGuild() then return end
	sender = Short(sender)
	if not sender or IsMe(sender) then return end
	local f = { strsplit(";", msg) }
	if f[1] ~= "D" then return end
	local function S(i) return f[i] ~= "" and f[i] or nil end
	local function N(i) return tonumber(f[i]) end
	local stamp = N(25) or time()
	local r = {
		id = sender .. ":" .. stamp, stamp = stamp, time = time(), victim = sender, me = false,
		victimLevel = N(3), victimClass = S(4), kind = S(5) or "unknown",
		killer = S(6), killerGUID = S(7), killerLevel = N(8), killerClass = S(9), killerRace = S(10),
		hostile = f[11] == "1", ability = f[12] or "", amount = N(13), env = S(14),
		zone = S(15), subzone = S(16), map = N(17), x = N(18) and N(18) / 10000, y = N(19) and N(19) / 10000,
		blame = S(20), blameGUID = S(21), blameLevel = N(22), blameClass = S(23), blameRace = S(24),
	}
	Store(r)
end

local events = CreateFrame("Frame")
-- Never COMBAT_LOG_EVENT_UNFILTERED: on Forever, registering for it gets the
-- addon blocked.
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_ADDON", "PLAYER_DEAD",
	"PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "Rattsmedicinalverket" then
			RattsmedicinalverketDB = RattsmedicinalverketDB or {}
			db = RattsmedicinalverketDB
			db.deaths = db.deaths or {}
		end
	elseif not db then
		return
	elseif event == "PLAYER_LOGIN" then
		-- A recap left over from before this session must not be read as new.
		lastRecap = RecapID()
		local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
		if register then register(ns.PREFIX) end
	elseif event == "PLAYER_DEAD" then
		OnDeath()
	elseif event == "CHAT_MSG_ADDON" then
		OnAddonMessage(...)
	elseif event == "PLAYER_TARGET_CHANGED" then
		Note("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		Note("mouseover")
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		Note(...)
	end
end)
