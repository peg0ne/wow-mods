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
	"NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "Polisen" then
			PolisenDB = PolisenDB or {}
			db = PolisenDB
			db.incidents = db.incidents or {}
			db.forgotten = db.forgotten or {}
			if db.alarm == nil then db.alarm = true end
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
	elseif event == "CHAT_MSG_ADDON" then
		OnAddonMessage(...)
	elseif event == "PLAYER_LOGOUT" then
		if sync.done then db.synced = Now() end
	elseif not next(ns.suspects) then
		return   -- nobody reported: nothing to look for
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		CheckUnit(...)
	elseif event == "PLAYER_TARGET_CHANGED" then
		CheckUnit("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		CheckUnit("mouseover")
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
	elseif cmd == "" then
		ns.ToggleWindow()
	else
		Print("/polisen öppnar fönstret, /polisen larm slår av eller på varningen på skärmen, /polisen tyst döljer andras observationer.")
	end
end
