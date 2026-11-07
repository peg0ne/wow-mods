-- Rättsmedicinalverket: death records for THÖNDERSTÖRM on WoW Forever.
-- Reads your own combat log, keeps the damage you took in the last 10 s,
-- and when you die works out what killed you. The record goes to the guild,
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
--                 player hit you in the last 10 s: the one who did most
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
local WINDOW = 10       -- seconds of damage kept
local KEEP = 500        -- deaths kept in the saved log

local API = {}
Rattsmedicinalverket = API

local db
local listeners = {}
local recent = {}       -- damage taken: { t, guid, name, flags, ability, amount, env }
local levels, levelCount = {}, 0
local playerGUID

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
	local guid = UnitExists(unit) and UnitGUID(unit)
	if not guid then return end
	if levelCount > 1000 then levels, levelCount = {}, 0 end
	if not levels[guid] then levelCount = levelCount + 1 end
	levels[guid] = UnitLevel(unit)
end

local function LookFor(guid)
	if not guid or levels[guid] then return end
	for _, unit in ipairs({ "target", "mouseover", "targettarget", "pettarget" }) do
		if UnitGUID(unit) == guid then Note(unit) return end
	end
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
			if unit and UnitGUID(unit) == guid then Note(unit) return end
		end
	end
end

local function PlayerInfo(guid)
	if not guid or not GetPlayerInfoByGUID then return end
	local ok, _, class, _, race = pcall(GetPlayerInfoByGUID, guid)
	if ok then return class, race end
end

---------------------------------------------------------------------------
-- Damage taken.

local function Prune()
	local cutoff = GetTime() - WINDOW
	while recent[1] and recent[1].t < cutoff do table.remove(recent, 1) end
end

local function OnCombatLog()
	local _, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, _, _, _, a1, a2, a3, a4 = CombatLogGetCurrentEventInfo()
	if dstGUID ~= playerGUID then return end
	local entry
	if sub == "SWING_DAMAGE" then
		entry = { ability = "", amount = a1 }
	elseif sub == "ENVIRONMENTAL_DAMAGE" then
		entry = { env = a1, amount = a2 }
	elseif sub == "RANGE_DAMAGE" or sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE"
		or sub == "DAMAGE_SHIELD" or sub == "DAMAGE_SPLIT" then
		entry = { ability = a2 or "", amount = a4 }
	else
		return
	end
	entry.t, entry.guid, entry.name, entry.flags = GetTime(), srcGUID, srcName, srcFlags or 0
	table.insert(recent, entry)
	Prune()
	if srcGUID and srcGUID ~= "" then LookFor(srcGUID) end
end

local function Kind(flags)
	if band(flags, TYPE_PLAYER) > 0 then return "player" end
	if band(flags, TYPE_PET) > 0 or band(flags, TYPE_GUARDIAN) > 0 then return "pet" end
	return "npc"
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

local function OnDeath()
	Prune()
	local stamp = time()
	local victim = Me() or UnitName("player")
	local map, x, y = Position()
	local r = {
		id = victim .. ":" .. stamp, stamp = stamp, time = stamp, victim = victim, me = true,
		victimLevel = UnitLevel("player"), victimClass = select(2, UnitClass("player")),
		zone = GetRealZoneText and GetRealZoneText() or GetZoneText(), subzone = GetSubZoneText(),
		map = map, x = x, y = y, kind = "unknown",
	}
	local last = recent[#recent]
	if last and GetTime() - last.t <= 5 then
		r.amount = last.amount
		if last.env then
			r.kind, r.env = "environment", last.env
		else
			r.kind = Kind(last.flags)
			r.killer, r.killerGUID, r.ability = last.name, last.guid, last.ability
			r.hostile = band(last.flags, HOSTILE) > 0
			r.killerLevel = levels[last.guid]
			if r.kind == "player" then r.killerClass, r.killerRace = PlayerInfo(last.guid) end
		end
	end
	-- Someone else landed the blow (a pet, a guard, the fall): blame the
	-- hostile player who did the most damage in the window, if any.
	if not (r.kind == "player" and r.hostile) then
		local dealt, names = {}, {}
		for _, e in ipairs(recent) do
			if e.guid and band(e.flags, TYPE_PLAYER) > 0 and band(e.flags, HOSTILE) > 0 then
				dealt[e.guid] = (dealt[e.guid] or 0) + (e.amount or 0)
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
	recent = {}
	Store(r)
	Broadcast(r)
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
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_ADDON", "PLAYER_DEAD",
	"COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do
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
		playerGUID = UnitGUID("player")
		local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
		if register then register(ns.PREFIX) end
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		OnCombatLog()
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
