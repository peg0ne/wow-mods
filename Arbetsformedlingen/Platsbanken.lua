-- Arbetsförmedlingen: Platsbanken, the guild's own job board for groups.
-- A member posts one listing (what, and how many tanks, healers and DPS
-- they need, optionally tied to a quest); online members see it in
-- /platsbanken, and apply with a role. The poster sees who applied under
-- their listing, invites with a click, and the needs count down; the
-- listing closes by itself when full, after an hour, or when the poster
-- goes offline.
--
-- Guild channel:
--   J;version;id;tank;heal;dps;quest;level;text   my listing, sent again every 2 minutes
--   X;id                                          my listing is gone
-- Whispers:
--   S;id;role    applicant -> poster: I want in, as T, H or D
--   I;id         poster -> applicant: invited
--   Z;id         poster -> applicant: application removed
--
-- Listings of others are kept for 5 minutes after the last time they were
-- heard. Your own listing is saved, so a /reload keeps it.

local _, ns = ...

local REPEAT, FORGET, LIFETIME = 120, 300, 3600
local ROLE_NAMES = { T = "tank", H = "helare", D = "DPS" }
local ROLE_KEYS = { T = "tank", H = "heal", D = "dps" }
ns.ROLE_NAMES = ROLE_NAMES

ns.listings = {}    -- poster -> { id, tank, heal, dps, quest, level, text, seen }
ns.myListing = nil  -- { id, tank, heal, dps, quest, text, posted, applicants = { name -> { role, at, invited } } }
ns.applied = {}     -- poster -> { id, role, invited }

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

local function Clean(text, max)
	text = tostring(text or ""):gsub("[;|\n]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return Cut(text, max)
end

local function Ding()
	pcall(PlaySound, SOUNDKIT and SOUNDKIT.READY_CHECK or 8960)
end

function ns.NeedsText(l)
	local parts = {}
	if (l.tank or 0) > 0 then table.insert(parts, l.tank .. " tank") end
	if (l.heal or 0) > 0 then table.insert(parts, l.heal .. " helare") end
	if (l.dps or 0) > 0 then table.insert(parts, l.dps .. " DPS") end
	return #parts > 0 and table.concat(parts, ", ") or "full"
end

function ns.Minutes(t)
	local m = math.floor((time() - (t or time())) / 60)
	return m < 1 and "nyss" or (m .. " min sedan")
end

local function Broadcast()
	local l = ns.myListing
	if not l or not ns.InOurGuild() then return end
	ns.Send(string.format("J;%s;%d;%d;%d;%d;%d;%d;%s", ns.VERSION, l.id, l.tank, l.heal, l.dps,
		l.quest or 0, UnitLevel("player") or 0, l.text))
	l.lastSent = time()
end

local function Save()
	local l = ns.myListing
	ns.char.listing = l and { id = l.id, tank = l.tank, heal = l.heal, dps = l.dps, quest = l.quest, text = l.text, posted = l.posted } or nil
end

function ns.Unpost(reason)
	local l = ns.myListing
	if not l then return end
	ns.Send("X;" .. l.id)
	ns.myListing = nil
	Save()
	if reason then ns.Print(reason) end
	ns.Changed()
end

-- Post a listing, replacing your old one. Counts are what is still needed.
function ns.Post(text, tank, heal, dps, quest)
	text = Clean(text, 80)
	tank, heal, dps = math.max(0, math.min(9, tonumber(tank) or 0)), math.max(0, math.min(9, tonumber(heal) or 0)),
		math.max(0, math.min(9, tonumber(dps) or 0))
	if text == "" then ns.Print("skriv vad gruppen ska göra, till exempel Scholomance.") return false end
	if tank + heal + dps == 0 then ns.Print("ange hur många tankar, helare eller DPS du behöver.") return false end
	-- Updating keeps the id, so applicants stay applied (their clients drop
	-- an application when the id changes) and nobody gets a second chat line.
	local old = ns.myListing
	local id = old and old.id
	if not id then
		ns.char.nextId = (ns.char.nextId or 0) + 1
		id = ns.char.nextId
	end
	ns.myListing = { id = id, tank = tank, heal = heal, dps = dps, quest = quest, text = text,
		posted = time(), applicants = old and old.applicants or {} }
	Save()
	Broadcast()
	ns.Print("din annons ligger ute i Platsbanken: " .. text .. " (söker " .. ns.NeedsText(ns.myListing) .. ").")
	ns.Changed()
	return true
end

function ns.Apply(poster, role)
	local l = ns.listings[poster]
	if not l or not ROLE_NAMES[role] then return end
	ns.SendTo(poster, string.format("S;%d;%s", l.id, role))
	ns.applied[poster] = { id = l.id, role = role }
	ns.Print(string.format("du har sökt som %s hos %s (%s).", ROLE_NAMES[role], poster, l.text))
	ns.Changed()
end

-- Poster: invite an applicant (from a click, so the game allows it).
function ns.Invite(name)
	local l = ns.myListing
	local a = l and l.applicants[name]
	if not a then return end
	Statskontoret.Invite(name)
	ns.SendTo(name, "I;" .. l.id)
	if not a.invited then
		a.invited = true
		local key = ROLE_KEYS[a.role]
		if key and l[key] > 0 then l[key] = l[key] - 1 end
		Save()
	end
	if l.tank + l.heal + l.dps == 0 then
		ns.Unpost("gruppen är full; din annons har tagits bort från Platsbanken.")
	else
		Broadcast()
		ns.Changed()
	end
end

function ns.Reject(name)
	local l = ns.myListing
	if not l or not l.applicants[name] then return end
	ns.SendTo(name, "Z;" .. l.id)
	l.applicants[name] = nil
	ns.Changed()
end

function ns.OnPlatsGuild(sender, parts)
	if parts[1] == "J" then
		local id = tonumber(parts[3])
		if not id then return end
		local text = Clean(table.concat(parts, ";", 9), 80)
		local old = ns.listings[sender]
		local l = { id = id, tank = tonumber(parts[4]) or 0, heal = tonumber(parts[5]) or 0, dps = tonumber(parts[6]) or 0,
			quest = tonumber(parts[7]), level = tonumber(parts[8]), text = text, seen = time(),
			posted = old and old.id == id and old.posted or time() }
		if l.quest == 0 then l.quest = nil end
		ns.listings[sender] = l
		local applied = ns.applied[sender]
		if applied and applied.id ~= id then ns.applied[sender] = nil end
		if not (old and old.id == id) and not ns.char.quiet then
			local mine = l.quest and ns.mine[l.quest] and " |cff40ff40(du har uppdraget)|r" or ""
			ns.Print(string.format("|cff66ccffPlatsbanken:|r %s söker %s: %s%s. Skriv /platsbanken.",
				sender, ns.NeedsText(l), text, mine))
		end
		ns.Changed()
	elseif parts[1] == "X" then
		local l = ns.listings[sender]
		if l and tostring(l.id) == parts[2] then
			ns.listings[sender] = nil
			ns.applied[sender] = nil
			ns.Changed()
		end
	end
end

function ns.OnPlatsWhisper(sender, parts)
	local kind, id = parts[1], tonumber(parts[2])
	local l = ns.myListing
	if kind == "S" and l and id == l.id and ROLE_NAMES[parts[3]] then
		local a = l.applicants[sender]
		if a and a.role == parts[3] then return end
		l.applicants[sender] = { role = parts[3], at = time(), invited = a and a.invited }
		ns.Print(string.format("|cff66ccffPlatsbanken:|r %s vill vara med som %s. Klicka på namnet i /platsbanken för att bjuda in.",
			sender, ROLE_NAMES[parts[3]]))
		Ding()
		ns.Changed()
		return
	end
	local applied = ns.applied[sender]
	if not applied or applied.id ~= id then return end
	if kind == "I" then
		applied.invited = true
		ns.Print(sender .. " har bjudit in dig till gruppen.")
		ns.Changed()
	elseif kind == "Z" then
		ns.applied[sender] = nil
		ns.Print(sender .. " tog bort din ansökan.")
		ns.Changed()
	end
end

-- Someone asked everyone for their state.
function ns.OnPlatsAsked()
	Broadcast()
end

function ns.PrunePlats(online)
	local changed = false
	for name in pairs(ns.listings) do
		if not online[name] then ns.listings[name], ns.applied[name], changed = nil, nil, true end
	end
	local l = ns.myListing
	if l then
		for name in pairs(l.applicants) do
			if not online[name] then l.applicants[name], changed = nil, true end
		end
	end
	if changed then ns.Changed() end
end

function ns.PlatsLogin()
	local saved = ns.char.listing
	if saved and time() - (saved.posted or 0) < LIFETIME then
		ns.myListing = { id = saved.id, tank = saved.tank, heal = saved.heal, dps = saved.dps, quest = saved.quest,
			text = saved.text, posted = saved.posted, applicants = {} }
		Broadcast()
	else
		ns.char.listing = nil
	end
	C_Timer.NewTicker(30, function()
		local now, changed = time(), false
		for name, l in pairs(ns.listings) do
			if now - l.seen > FORGET then ns.listings[name], ns.applied[name], changed = nil, nil, true end
		end
		local mine = ns.myListing
		if mine then
			if now - mine.posted > LIFETIME then
				ns.Unpost("din annons i Platsbanken har legat ute en timme och har tagits bort. Lägg ut den igen om du fortfarande söker.")
			elseif now - (mine.lastSent or 0) >= REPEAT then
				Broadcast()
			end
		end
		if changed then ns.Changed() end
	end)
end

-- Rows for the Platsbanken view: your listing and its applicants first,
-- then everyone else's, those tied to a quest you have first.
function ns.PlatsRows()
	local rows = {}
	local l = ns.myListing
	if l then
		table.insert(rows, { kind = "mine", listing = l })
		local names = {}
		for name in pairs(l.applicants) do table.insert(names, name) end
		table.sort(names, function(a, b) return l.applicants[a].at < l.applicants[b].at end)
		for _, name in ipairs(names) do
			table.insert(rows, { kind = "applicant", name = name, app = l.applicants[name] })
		end
	end
	local posters = {}
	for name in pairs(ns.listings) do
		if not ns.IsMe(name) then table.insert(posters, name) end
	end
	local function Rank(name)
		local q = ns.listings[name].quest
		return q and ns.mine[q] and 0 or 1
	end
	table.sort(posters, function(a, b)
		if Rank(a) ~= Rank(b) then return Rank(a) < Rank(b) end
		return ns.listings[a].posted > ns.listings[b].posted
	end)
	for _, name in ipairs(posters) do
		table.insert(rows, { kind = "listing", name = name, listing = ns.listings[name] })
	end
	return rows
end
