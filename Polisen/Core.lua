-- Polisen: PvP incident log for THÖNDERSTÖRM on WoW Forever.
-- Rättsmedicinalverket tells us about every guild member's death; when a
-- hostile player did it (the killing blow, or most of the damage in the
-- last 10 s when a pet or guard finished the job) it becomes an incident
-- against that player. Members who were offline catch up when they log in.
-- When a reported player shows up (nameplate, target or mouseover; the
-- combat log is closed to addons on Forever) you get a warning, the guild hears about it, and the
-- player's tooltip shows the record. Incidents are kept for 30 days.
--
-- Guild channel:
--   F;since                         send me incidents newer than since
--   B;asker                         I am answering asker (others stay quiet)
--   I;id;victim;suspect;guid;level;class;race;zone;stamp   one incident
--   E;asker;more;last               end of an answer (0.4); more = 1 when
--                                   there are more after last: ask again
--   S;guid;name;zone;level          I just saw this reported player
--   K;id;victim;guid;level;class;race;zone;stamp;hk   I (0.5) killed a hostile
--                                   player; hk = 1 when the game gave an
--                                   honorable kill for it
--
-- Victories (0.5): a hostile player we fought dies, see "Victories" below.
-- Killing someone in the registry is celebrated by the whole guild.
--
-- Catching up: db.synced is the (server) time up to which this client has
-- every incident. At login it asks for everything after it, oldest first,
-- a page at a time, and only moves db.synced once the answer is complete;
-- while online it hears incidents live, so db.synced then follows the
-- clock. If nobody answers, it asks again later from the same point.
-- (0.3 asked from its newest incident, so a death seen in the first
-- seconds after login skipped everything that happened while offline.)
--
-- Suspects are matched by GUID, and by name when the GUID is unknown.

local _, ns = ...

ns.GUILD = "THÖNDERSTÖRM"
ns.VERSION = "0.1"
ns.PREFIX = "POLIS"
local KEEP_DAYS = 30
local WARN_EVERY = 300     -- seconds between warnings about the same player
local SYNC_MAX = 40        -- incidents per catch-up page
local SYNC_MARGIN = 600    -- seconds asked for before db.synced (clock differences)
local ASK_AGAIN = 300      -- seconds between asks while nobody has answered
local OLD_ANSWER_WAIT = 60 -- an answer without E (from 0.3) counts as complete after this

-- Server time where the client has it: the same clock for every member.
local function Now()
	return GetServerTime and GetServerTime() or time()
end

local db
ns.suspects = {}           -- key -> suspect (see Rebuild)
local byGUID, byName = {}, {}
local warned, heardSeen = {}, {}
local lastAnswer, answering = 0, {}

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff3366ffPolisen:|r " .. text)
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

-- This character's full name as the guild sees it (two-word Forever names).
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

-- Throttled: the server drops floods (see Statskontoret.Sender).
local Send = Statskontoret.Sender(ns.PREFIX)

---------------------------------------------------------------------------
-- Incidents and suspects.

function ns.ClassText(classFile, text)
	return Statskontoret.ClassText(classFile, text)
end

function ns.ClassName(classFile)
	return classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile] or ""
end

function ns.LevelText(level)
	if not level then return "?" end
	if level < 0 then return "??" end
	return tostring(level)
end

function ns.Ago(t)
	local s = time() - (t or 0)
	if s < 60 then return "nyss" end
	if s < 3600 then return string.format("för %d min sedan", math.floor(s / 60)) end
	if s < 86400 then return string.format("för %d h sedan", math.floor(s / 3600)) end
	return string.format("för %d d sedan", math.floor(s / 86400))
end

-- Suspects from the incidents: { key, name, guid, class, race, level,
-- count, last (incident), victims = { name = count } }.
local function Rebuild()
	local suspects = {}
	byGUID, byName = {}, {}
	local cutoff = time() - KEEP_DAYS * 86400
	for id, t in pairs(db.forgotten) do
		if t < cutoff then db.forgotten[id] = nil end
	end
	for id, inc in pairs(db.incidents) do
		if inc.time < cutoff then
			db.incidents[id] = nil
		else
			local key = inc.guid or ("n:" .. inc.suspect)
			local s = suspects[key]
			if not s then
				s = { key = key, name = inc.suspect, guid = inc.guid, count = 0, victims = {} }
				suspects[key] = s
			end
			s.count = s.count + 1
			s.victims[inc.victim] = (s.victims[inc.victim] or 0) + 1
			s.class = s.class or inc.class
			s.race = s.race or inc.race
			if inc.level and inc.level > (s.level or 0) then s.level = inc.level end
			if not s.last or inc.time > s.last.time then s.last = inc end
		end
	end
	for _, s in pairs(suspects) do
		if s.guid then byGUID[s.guid] = s end
		byName[s.name] = s
	end
	ns.suspects = suspects
	-- How often the guild has killed each reported player.
	for id, k in pairs(db.kills) do
		if k.time < cutoff then
			db.kills[id] = nil
		else
			local s = (k.guid and byGUID[k.guid]) or byName[k.victim]
			if s then s.kills = (s.kills or 0) + 1 end
		end
	end
end

local function Changed()
	Rebuild()
	if ns.RefreshWindow then ns.RefreshWindow() end
end

-- The suspect behind a GUID or name, or nil.
function ns.Suspect(guid, name)
	if guid and byGUID[guid] then return byGUID[guid] end
	if name then
		local s = byName[name]
		-- A reported name with a known GUID only matches that GUID.
		if s and (not s.guid or not guid) then return s end
	end
end

local function Add(inc)
	if db.incidents[inc.id] or db.forgotten[inc.id] or inc.time < time() - KEEP_DAYS * 86400 then return false end
	db.incidents[inc.id] = inc
	return true
end

local function OnDeath(r)
	local name, guid, level, class, race
	if r.kind == "player" and r.hostile then
		name, guid, level, class, race = r.killer, r.killerGUID, r.killerLevel, r.killerClass, r.killerRace
	elseif r.blame then
		name, guid, level, class, race = r.blame, r.blameGUID, r.blameLevel, r.blameClass, r.blameRace
	end
	if not name then return end
	local inc = {
		id = r.id, victim = r.victim, suspect = name, guid = guid, level = level,
		class = class, race = race, zone = r.zone or "", time = Now(),
	}
	if Add(inc) then
		Changed()
		local s = ns.Suspect(guid, name)
		local who = r.me and "du" or r.victim
		Print(string.format("%s dödades av %s i %s. %s har nu %d anmälning%s.",
			who, ns.ClassText(class, name), inc.zone, name, s and s.count or 1, (s and s.count or 1) == 1 and "" or "ar"))
	end
end

---------------------------------------------------------------------------
-- Catching up after logging in.

local function Newest()
	local newest = 0
	for _, inc in pairs(db.incidents) do newest = math.max(newest, inc.time) end
	return newest
end

-- Cut text to at most max bytes without splitting a multi-byte letter
-- (å, ä, ö are two bytes each); a half letter breaks the message.
local function Cut(text, max)
	if #text <= max then return text end
	text = text:sub(1, max)
	local i = #text
	while i > 0 and text:byte(i) >= 128 and text:byte(i) < 192 do i = i - 1 end
	local lead = text:byte(i)
	if lead and lead >= 192 then
		local need = lead >= 240 and 4 or (lead >= 224 and 3 or 2)
		if #text - i + 1 < need then text = text:sub(1, i - 1) end
	end
	return text
end

local function Clean(text)
	return Cut((tostring(text or ""):gsub("[;|]", ",")), 40)
end

local function SendIncident(inc)
	Send(string.format("I;%s;%s;%s;%s;%s;%s;%s;%s;%d", Clean(inc.id), Clean(inc.victim), Clean(inc.suspect),
		inc.guid or "", inc.level or "", inc.class or "", Clean(inc.race), Clean(inc.zone), inc.time))
end

local function OnAsk(sender, since)
	since = tonumber(since) or 0
	if GetTime() - lastAnswer < 30 then return end
	-- Whoever answers first answers alone. An empty answer (B, then E) still
	-- goes out: it tells the asker it has everything.
	answering[sender] = nil
	C_Timer.After(1 + math.random() * 3, function()
		if answering[sender] then return end
		answering[sender] = true
		lastAnswer = GetTime()
		local list = {}
		for _, inc in pairs(db.incidents) do
			if inc.time > since then table.insert(list, inc) end
		end
		-- Oldest first, so a long gap is filled page by page.
		table.sort(list, function(a, b) return a.time < b.time end)
		Send("B;" .. sender)
		local last = since
		for i = 1, math.min(SYNC_MAX, #list) do
			SendIncident(list[i])
			last = list[i].time
		end
		Send(string.format("E;%s;%d;%d", sender, #list > SYNC_MAX and 1 or 0, last))
	end)
end

-- This client's own catch-up.
local sync = { done = false }

local function Ask(since)
	if not ns.InOurGuild() then return end
	since = math.max(since, Now() - KEEP_DAYS * 86400)
	sync.asked, sync.answered, sync.since = Now(), false, since
	Send("F;" .. math.floor(since))
end

local function SyncDone()
	sync.done = true
	-- Everything up to the first ask arrived; since then we heard it live.
	db.synced = sync.from
end

-- B for us: someone is answering. A 0.3 answerer never sends E, so if
-- none comes the answer is taken as complete after a while, unless it was
-- a full page (0.3 sends only its newest SYNC_MAX): then db.synced stays
-- put and the next login asks again, perhaps of an updated member.
local function OnAnswering()
	if sync.done then return end
	sync.answered, sync.received = true, 0
	local asked = sync.asked
	C_Timer.After(OLD_ANSWER_WAIT, function()
		if sync.done or sync.asked ~= asked then return end
		if sync.received < SYNC_MAX then SyncDone() end
	end)
end

local function OnEnd(f)
	if sync.done or not ns.IsMe(f[2]) then return end
	if f[3] == "1" then
		-- More to come: ask for the next page once the answerer may answer again.
		-- A second back, so incidents sharing that second are not skipped
		-- (the one already received is ignored as a duplicate).
		local last = (tonumber(f[4]) or 0) - 1
		sync.asked = nil
		C_Timer.After(31, function() Ask(last) end)
	else
		SyncDone()
	end
end

local function StartSync()
	sync.from = Now()
	local since = (db.synced or sync.newestAtLoad) - SYNC_MARGIN
	Ask(since)
	C_Timer.NewTicker(ASK_AGAIN, function()
		if sync.done then
			db.synced = Now()   -- online and listening: complete up to now
		elseif not sync.answered then
			Ask(sync.since or since)
		end
	end)
end

local function OnIncident(f)
	local stamp = tonumber(f[10])
	if not f[2] or not f[4] or not stamp then return end
	local inc = {
		id = f[2], victim = f[3], suspect = f[4], guid = f[5] ~= "" and f[5] or nil, level = tonumber(f[6]),
		class = f[7] ~= "" and f[7] or nil, race = f[8] ~= "" and f[8] or nil, zone = f[9] or "", time = stamp,
	}
	if sync.received then sync.received = sync.received + 1 end
	if Add(inc) then Changed() end
end

---------------------------------------------------------------------------
-- Sightings.

local function Alarm(s, zone, level, spotter)
	local text = string.format("%s (%d anmälning%s) %s", s.name, s.count, s.count == 1 and "" or "ar",
		spotter and ("syns i " .. (zone or "?") .. " enligt " .. spotter) or "är i närheten!")
	Print(ns.ClassText(s.class, text) .. (level and level ~= 0 and (" Nivå " .. ns.LevelText(level) .. ".") or ""))
	if db.alarm and not spotter then
		if RaidNotice_AddMessage and RaidWarningFrame then
			RaidNotice_AddMessage(RaidWarningFrame, "Polisen: " .. text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.3, b = 0.1 })
		end
		if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
	end
end

local function Seen(guid, name, level)
	local s = ns.Suspect(guid, name)
	if not s then return end
	local key = s.key
	if GetTime() - (warned[key] or -999) < WARN_EVERY then return end
	warned[key] = GetTime()
	Alarm(s, nil, level)
	-- Tell the guild, unless someone else just did.
	if GetTime() - (heardSeen[key] or -999) >= WARN_EVERY then
		heardSeen[key] = GetTime()
		local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
		Send(string.format("S;%s;%s;%s;%s", s.guid or "", Clean(s.name), Clean(zone), level or ""))
	end
end

-- The client may hand addons "secret" values that cannot be compared;
-- treat those as unknown.
local function Plain(v)
	if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
	return v
end

local function CheckUnit(unit)
	-- Every enemy in a battleground or arena is there to fight; no sightings.
	if Statskontoret.InPvPInstance() then return end
	if not unit or not UnitExists(unit) or not Plain(UnitIsPlayer(unit)) then return end
	if UnitIsFriend and Plain(UnitIsFriend("player", unit)) then return end
	local guid, name = Plain(UnitGUID(unit)), Plain(UnitName(unit))
	if guid or name then Seen(guid, name, Plain(UnitLevel(unit))) end
end

local function OnSeen(sender, f)
	local guid, name, zone, level = f[2] ~= "" and f[2] or nil, f[3], f[4], tonumber(f[5])
	local s = ns.Suspect(guid, name)
	if not s then return end
	heardSeen[s.key] = GetTime()
	if db.quiet or Statskontoret.InPvPInstance() then return end
	if GetTime() - (warned["g:" .. s.key] or -999) < WARN_EVERY then return end
	warned["g:" .. s.key] = GetTime()
	Alarm(s, zone, level, sender)
end

---------------------------------------------------------------------------
-- Victories (0.5). Without the combat log nobody can see who landed the
-- killing blow, so a kill is: a hostile player of the other faction who
-- was seen alive and then dead, and whom I fought in the last
-- FIGHT_WINDOW seconds (my target while I was in combat, or they had me
-- or someone in my group targeted). Everyone in the group who fought them
-- counts it; the guild merges the reports into one victory. If the client
-- sends honorable kill messages (CHAT_MSG_COMBAT_HONOR_GAIN), one of those
-- counts too and marks the kill as honorable. Never in battlegrounds or
-- arenas. Kills are not caught up after login: they are a celebration,
-- not a record.

local FIGHT_WINDOW = 20
local KILL_SAME = 60      -- the same victim again within this is the same kill
local foes = {}           -- key -> { name, guid, level, class, race, alive, fought }
local recentKill = {}     -- victim name -> GetTime() of their kill

local NORMAL = {
	"{who} fällde {victim} i {zone}!",
	"{who} skickade {victim} till andeläkaren i {zone}!",
	"{victim} fick se sig besegrad av {by} i {zone}.",
	"{who} gav {victim} en lektion i {zone}.",
}

local WANTED = {
	"Efterlyst gripen! {who} fällde {victim} i {zone}. {victim} hade {count}. Hämnd för {victims}!",
	"Rättvisa skipad! {victim}, efterlyst för {count}, föll för {by} i {zone}. Hämnd för {victims}!",
}

local function Fill(text, vars)
	return (text:gsub("{(%a+)}", function(key) return vars[key] or "?" end))
end

-- The same kill gets the same wording on every computer.
local function Pick(list, id)
	local n = 0
	for i = 1, #id do n = (n * 31 + id:byte(i)) % 2147483647 end
	return list[n % #list + 1]
end

-- 1:a, 2:a, 3:e ... 21:a, but 11:e and 12:e.
local function Ordinal(n)
	local last, lastTwo = n % 10, n % 100
	if (last == 1 or last == 2) and lastTwo ~= 11 and lastTwo ~= 12 then return n .. ":a" end
	return n .. ":e"
end

local function Join(names)
	if #names <= 1 then return names[1] or "" end
	return table.concat(names, ", ", 1, #names - 1) .. " och " .. names[#names]
end

local function Fanfare()
	if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.LEVELUPSOUND or 888) end
end

local function AddKill(k)
	if db.kills[k.id] or k.time < time() - KEEP_DAYS * 86400 then return false end
	db.kills[k.id] = k
	return true
end

-- My victories in the last 30 days.
local function MyKills()
	local n = 0
	for _, k in pairs(db.kills) do
		if ns.IsMe(k.killer) then n = n + 1 end
	end
	return n
end

-- The kill as text. forGuild: third person and no colors, for guild chat.
local function KillText(k, s, mine, forGuild)
	local you = mine and not forGuild
	local vars = {
		who = you and "Du" or k.killer, by = you and "dig" or k.killer,
		victim = forGuild and k.victim or ns.ClassText(k.class, k.victim), zone = k.zone ~= "" and k.zone or "okänd plats",
	}
	if not s then return Fill(Pick(NORMAL, k.id), vars) end
	vars.count = string.format("%d anmälning%s", s.count, s.count == 1 and "" or "ar")
	local victims = {}
	for name in pairs(s.victims) do table.insert(victims, (not forGuild and ns.IsMe(name)) and "dig" or name) end
	table.sort(victims)
	vars.victims = Join(victims)
	return Fill(Pick(WANTED, k.id), vars)
end

-- Guild chat, for members without the addon and the Discord bridge.
-- Only the killer posts, 2 s after the K message so that members with the
-- addon know to hide the line (they have their own). Ordinary kills at most
-- once per GUILD_EVERY seconds; a wanted one always.
local GUILD_EVERY = 30
local lastGuildPost = -999
local ownCopy = {}        -- guild chat lines we already show ourselves
local heardKill = {}      -- sender -> GetTime() of their last K

local function GuildLine(text)
	local line = "Polisen: " .. text
	if #line > 255 then line = Cut(line, 252) .. "..." end
	return line
end

local function PostToGuild(k, s)
	if not db.guildChat or not IsInGuild() then return end
	if not s and GetTime() - lastGuildPost < GUILD_EVERY then return end
	lastGuildPost = GetTime()
	local line = GuildLine(KillText(k, s, true, true))
	ownCopy[line] = true
	C_Timer.After(2, function()
		local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
		if send then send(line, "GUILD") end
	end)
end

local function Celebrate(k, mine)
	local s = ns.Suspect(k.guid, k.victim)
	k.wanted = s and true or nil
	Changed()
	local text = KillText(k, s, mine, false)
	if mine then
		text = text .. string.format(" Din %s seger de senaste 30 dagarna.", Ordinal(MyKills()))
		PostToGuild(k, s)
	end
	Print(text)
	-- Your own kill is celebrated on your screen; a wanted one on everybody's.
	if (mine or s) and not db.noCheer then
		if RaidNotice_AddMessage and RaidWarningFrame then
			local banner = s and ("Efterlyst gripen: " .. k.victim .. "!") or ("Seger! " .. k.victim .. " är fälld.")
			RaidNotice_AddMessage(RaidWarningFrame, "Polisen: " .. banner, { r = 0.3, g = 1, b = 0.3 })
		end
		Fanfare()
	end
end

local function Kill(foe, hk)
	if not ns.InOurGuild() or Statskontoret.InPvPInstance() then return end
	local last = recentKill[foe.name]
	if last and GetTime() - last < KILL_SAME then
		-- Already counted: by me (an honorable kill message only confirms
		-- it), or by someone in my group, and then I helped.
		for _, k in pairs(db.kills) do
			if k.victim == foe.name and math.abs(Now() - k.time) < KILL_SAME then
				if ns.IsMe(k.killer) then
					if hk then k.hk = true end
				else
					k.helpers = k.helpers or {}
					local me = ns.Me() or UnitName("player")
					if not tContains(k.helpers, me) then
						table.insert(k.helpers, me)
						Changed()
						-- Others merge it into the same victory.
						Send(string.format("K;%s;%s;;;;;%s;%d;%s", Clean(me .. ":" .. Now()), Clean(foe.name),
							Clean(k.zone), Now(), hk and "1" or "0"))
					end
				end
			end
		end
		return
	end
	recentKill[foe.name] = GetTime()
	local me = ns.Me() or UnitName("player")
	local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
	local k = {
		id = me .. ":" .. Now(), killer = me, victim = foe.name, guid = foe.guid, level = foe.level,
		class = foe.class, race = foe.race, zone = zone or "", time = Now(), hk = hk or nil,
	}
	if not AddKill(k) then return end
	Celebrate(k, true)
	Send(string.format("K;%s;%s;%s;%s;%s;%s;%s;%d;%s", Clean(k.id), Clean(k.victim), k.guid or "", k.level or "",
		k.class or "", Clean(k.race), Clean(k.zone), k.time, hk and "1" or "0"))
end

local function OnKill(sender, f)
	heardKill[sender] = GetTime()
	local stamp = tonumber(f[9])
	if not f[2] or not f[3] or f[3] == "" or not stamp then return end
	local victim = f[3]
	-- Someone in the same fight already reported it (perhaps me): one victory.
	local last = recentKill[victim]
	if last and GetTime() - last < KILL_SAME then
		for _, k in pairs(db.kills) do
			if k.victim == victim and math.abs(k.time - stamp) < KILL_SAME and k.killer ~= sender then
				k.helpers = k.helpers or {}
				if not tContains(k.helpers, sender) then table.insert(k.helpers, sender) end
			end
		end
		Changed()
		return
	end
	recentKill[victim] = GetTime()
	local k = {
		id = f[2], killer = sender, victim = victim, guid = f[4] ~= "" and f[4] or nil, level = tonumber(f[5]),
		class = f[6] ~= "" and f[6] or nil, race = f[7] ~= "" and f[7] or nil, zone = f[8] or "", time = stamp,
		hk = f[10] == "1" or nil,
	}
	if AddKill(k) then Celebrate(k, false) end
end

local function InGroup(unit)
	if not UnitExists(unit) then return false end
	if Plain(UnitIsUnit(unit, "player")) then return true end
	if UnitInParty and Plain(UnitInParty(unit)) then return true end
	if UnitInRaid and Plain(UnitInRaid(unit)) then return true end
	return false
end

-- Called for every unit event: remembers hostile players, whether we are
-- fighting them, and notices when one dies.
local function Watch(unit)
	if type(unit) ~= "string" or unit == "player" or not UnitExists(unit) or not Plain(UnitIsPlayer(unit)) then return end
	if Statskontoret.InPvPInstance() then return end
	local guid, name = Plain(UnitGUID(unit)), Plain(UnitName(unit))
	if not name then return end
	local key = guid or ("n:" .. name)
	local dead = Plain(UnitIsDeadOrGhost(unit)) and not (UnitIsFeignDeath and Plain(UnitIsFeignDeath(unit)))
	local foe = foes[key]
	if not foe then
		if dead or not Plain(UnitCanAttack("player", unit)) then return end
		-- Duels and mind control are the same faction: not a victory.
		local theirs, ours = Plain(UnitFactionGroup(unit)), Plain(UnitFactionGroup("player"))
		if theirs and ours and theirs == ours then return end
		local _, class = UnitClass(unit)
		foe = { name = name, guid = guid, class = Plain(class), race = Plain(UnitRace(unit)) }
		foes[key] = foe
	end
	local level = Plain(UnitLevel(unit))
	if level then foe.level = level end
	local now = GetTime()
	if not dead then
		foe.alive = now
		if (Plain(UnitIsUnit(unit, "target")) and Plain(UnitAffectingCombat("player"))) or InGroup(unit .. "target") then
			foe.fought = now
		end
	elseif foe.alive and foe.fought and now - foe.fought <= FIGHT_WINDOW then
		-- UnitIsFeignDeath only works on the group: a feigning hunter still has health.
		local hp = Plain(UnitHealth(unit))
		if foe.class == "HUNTER" and hp and hp > 0 then return end
		foe.alive = nil
		Kill(foe)
	end
end

-- Forget hostile players not seen for ten minutes.
local function PruneFoes()
	local cutoff = GetTime() - 600
	for key, foe in pairs(foes) do
		if (foe.alive or 0) < cutoff and (foe.fought or 0) < cutoff then foes[key] = nil end
	end
end

-- "%s dies, honorable kill ..." as a pattern capturing the name.
local honorPatterns
local function ToPattern(fmt)
	if type(fmt) ~= "string" then return nil end
	local p = fmt:gsub("%%%d*%$?s", "\001"):gsub("%%%d*%$?d", "\002")
	p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	p = p:gsub("\001", "(.+)"):gsub("\002", "%%d+")
	return "^" .. p
end

local function OnHonor(msg)
	msg = Plain(msg)
	if type(msg) ~= "string" then return end
	if not honorPatterns then
		honorPatterns = {}
		for _, fmt in ipairs({ COMBATLOG_HONORGAIN, COMBATLOG_HONORGAIN_NO_RANK }) do
			local p = ToPattern(fmt)
			if p then table.insert(honorPatterns, p) end
		end
	end
	for _, p in ipairs(honorPatterns) do
		local name = msg:match(p)
		if name then
			name = ns.Short(name)
			local found
			for _, foe in pairs(foes) do
				if foe.name == name then found = foe end
			end
			Kill(found or { name = name }, true)
			return
		end
	end
end

-- Members with the addon already have the celebration: hide the guild chat
-- copy (our own exactly; others' "Polisen:" line when their K came lately).
if ChatFrame_AddMessageEventFilter then
	ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", function(_, _, msg, author)
		msg, author = Plain(msg), Plain(author)
		if not db or type(msg) ~= "string" then return end
		if ownCopy[msg] then return true end
		if type(author) ~= "string" or not msg:match("^Polisen: ") then return end
		local t = heardKill[ns.Short(author)]
		if t and GetTime() - t < 60 then return true end
	end)
end

-- Victories, newest first.
function ns.Kills()
	local list = {}
	for _, k in pairs(db.kills) do table.insert(list, k) end
	table.sort(list, function(a, b) return a.time > b.time end)
	return list
end

---------------------------------------------------------------------------
-- Tooltips on reported players.

local function OnTooltipUnit(tooltip)
	if not db or not tooltip.GetUnit then return end
	local _, unit = tooltip:GetUnit()
	unit = Plain(unit)
	if not unit or not Plain(UnitIsPlayer(unit)) then return end
	local s = ns.Suspect(Plain(UnitGUID(unit)), Plain(UnitName(unit)))
	if not s then return end
	tooltip:AddLine(string.format("Polisen: %d anmälning%s", s.count, s.count == 1 and "" or "ar"), 1, 0.2, 0.2)
	if s.last then
		tooltip:AddLine(string.format("Senast: dödade %s i %s %s", s.last.victim, s.last.zone, ns.Ago(s.last.time)), 1, 0.5, 0.5)
	end
	if s.kills then
		tooltip:AddLine(string.format("Fälld av gillet %d gång%s", s.kills, s.kills == 1 and "" or "er"), 0.3, 1, 0.3)
	end
	tooltip:Show()
end

local function HookTooltips()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipUnit)
	else
		pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", OnTooltipUnit)
	end
end

---------------------------------------------------------------------------

local function OnAddonMessage(prefix, msg, channel, sender)
	if prefix ~= ns.PREFIX or channel ~= "GUILD" or not db or not ns.InOurGuild() then return end
	sender = ns.Short(sender)
	if not sender or ns.IsMe(sender) then return end
	local f = { strsplit(";", msg) }
	if f[1] == "F" then OnAsk(sender, f[2])
	elseif f[1] == "B" then
		answering[f[2] or ""] = true
		if ns.IsMe(f[2]) then OnAnswering() end
	elseif f[1] == "I" then OnIncident(f)
	elseif f[1] == "E" then OnEnd(f)
	elseif f[1] == "S" then OnSeen(sender, f)
	elseif f[1] == "K" then OnKill(sender, f)
	end
end

-- Forgotten incidents are remembered by id until they would have expired,
-- so another member's catch-up answer cannot bring them back. A new
-- incident by the same player still counts.
function ns.Forget(key)
	for id, inc in pairs(db.incidents) do
		if (inc.guid or ("n:" .. inc.suspect)) == key then
			db.incidents[id] = nil
			db.forgotten[id] = inc.time
		end
	end
	Changed()
end

-- Recent incidents, newest first.
function ns.Incidents()
	local list = {}
	for _, inc in pairs(db.incidents) do table.insert(list, inc) end
	table.sort(list, function(a, b) return a.time > b.time end)
	return list
end

-- Suspects, most reports first.
function ns.Wanted()
	local list = {}
	for _, s in pairs(ns.suspects) do table.insert(list, s) end
	table.sort(list, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.last.time > b.last.time
	end)
	return list
end

local events = CreateFrame("Frame")
-- No combat log: Forever's client (like current retail) blocks addons from it.
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "CHAT_MSG_ADDON",
	"NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
	"UNIT_HEALTH", "UNIT_FLAGS", "UNIT_TARGET", "CHAT_MSG_COMBAT_HONOR_GAIN" }) do
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "Polisen" then
			PolisenDB = PolisenDB or {}
			db = PolisenDB
			db.incidents = db.incidents or {}
			db.forgotten = db.forgotten or {}
			db.kills = db.kills or {}
			if db.alarm == nil then db.alarm = true end
			if db.guildChat == nil then db.guildChat = true end
			ns.db = db
			-- Upgrading from 0.3 (no db.synced): start from the newest incident
			-- as it is now, before deaths heard after login can move it.
			sync.newestAtLoad = Newest()
			Rebuild()
			HookTooltips()
			Rattsmedicinalverket.Register(OnDeath)
		end
	elseif not db then
		return
	elseif event == "PLAYER_LOGIN" then
		local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
		if register then register(ns.PREFIX) end
		C_Timer.After(20, StartSync)
		C_Timer.NewTicker(300, PruneFoes)
	elseif event == "CHAT_MSG_ADDON" then
		OnAddonMessage(...)
	elseif event == "PLAYER_LOGOUT" then
		if sync.done then db.synced = Now() end
	elseif event == "UNIT_HEALTH" or event == "UNIT_FLAGS" or event == "UNIT_TARGET" then
		Watch((...))
	elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
		OnHonor((...))
	else
		local unit = event == "NAME_PLATE_UNIT_ADDED" and (...)
			or event == "PLAYER_TARGET_CHANGED" and "target"
			or event == "UPDATE_MOUSEOVER_UNIT" and "mouseover"
		Watch(unit)
		-- Sightings: only when somebody is reported.
		if next(ns.suspects) then CheckUnit(unit) end
	end
end)

SLASH_POLISEN1 = "/polisen"
SLASH_POLISEN2 = "/polis"
SlashCmdList.POLISEN = function(msg)
	if not ns.InOurGuild() then
		Print("den här karaktären är inte med i " .. ns.GUILD .. ".")
		return
	end
	local cmd = strtrim(msg or ""):lower()
	if cmd == "larm" then
		db.alarm = not db.alarm
		Print(db.alarm and "varningar på skärmen och ljud är på." or "varningar på skärmen och ljud är av (chattraden finns kvar).")
	elseif cmd == "tyst" then
		db.quiet = not db.quiet
		Print(db.quiet and "visar inte längre när andra i gillet ser efterlysta." or "visar när andra i gillet ser efterlysta.")
	elseif cmd == "gillet" then
		db.guildChat = not db.guildChat
		Print(db.guildChat and "dina segrar skrivs nu också i gillechatten (för medlemmar utan addonen)."
			or "dina segrar skrivs inte längre i gillechatten.")
	elseif cmd == "jubel" then
		db.noCheer = not db.noCheer
		Print(db.noCheer and "segrar firas bara i chatten." or "segrar firas med text på skärmen och ljud.")
	elseif cmd == "" then
		ns.ToggleWindow()
	else
		Print("/polisen öppnar fönstret, /polisen larm slår av eller på varningen på skärmen, /polisen tyst döljer andras observationer, /polisen jubel slår av eller på firandet av segrar på skärmen, /polisen gillet slår av eller på dina segrar i gillechatten.")
	end
end
