-- Dödsannonser: obituaries for THÖNDERSTÖRM on WoW Forever.
-- Rättsmedicinalverket hands every member the record of every guild
-- member's death; this turns each one into a short newspaper-style notice
-- in chat. Nothing is sent: everyone with the addon writes the notice
-- themselves, so it costs no messages and cannot be blocked. The one who
-- died also posts their own obituary in guild chat (on by default; off
-- with /dodsannons gillet), for members without the addon and the guild's
-- Discord bridge. Only the one who died posts, and members with the addon
-- hide that line, since they already have the notice.
--
-- Wording is picked at random from the lists below, but the same death
-- always gets the same wording on every computer (seeded by the death's id).
--
-- Level-ups get a notice too ("Familjenytt"). The death records don't cover
-- them, so the one who levelled tells the guild: on PLAYER_LEVEL_UP they
-- send "L;<name>;<level>;<classFile>" (prefix DODSANNONS) and, like an
-- obituary, post the notice in guild chat 2 s later. Everyone with the
-- addon writes the same notice from that message (seeded by name and
-- level) and hides the guild chat copy. /dodsannons nivå turns them off.
--
-- 0.5: hunter pets too. When your pet levels (UNIT_LEVEL for "pet", the same
-- pet by GUID one level higher than we last saw it) the owner sends
-- "P;<owner>;<pet>;<level>;<family>" and posts in guild chat the same way.
-- Only hunters: a warlock's demon just follows its master's level.
-- 0.4 ignores these messages. /dodsannons husdjur turns them off.

local _, ns = ...

ns.GUILD = "THÖNDERSTÖRM"
local SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14|t"
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:14|t"
local PREFIX = "DODSANNONS"   -- addon message prefix for level-ups
local KEEP = 50

local db
local shown = {}   -- death ids already announced this session
local ownCopy = {} -- guild chat lines we already show ourselves
local heard = {}   -- ["Dödsannons:" or "Familjenytt:" .. name] = GetTime() we showed it

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

-- The obituary as it goes out in guild chat (at most 255 bytes).
local function GuildLine(text, heading)
	local line = (heading or "Dödsannons") .. ": " .. text
	if #line > 255 then line = Cut(line, 252) .. "..." end
	return line
end

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffbbbbbbDödsannonser:|r " .. text)
end

local function InOurGuild()
	return GetGuildInfo("player") == ns.GUILD
end

---------------------------------------------------------------------------
-- Wording. {v} victim, {vd} victim with level and class, {k} killer,
-- {kl} killer level, {a} ability, {z} zone, {c} killer's race, class, level.

local OPENINGS = {
	"Vår kära {vd} har lämnat oss.",
	"Det är med sorg vi meddelar att {vd} har gått bort.",
	"{vd} har somnat in.",
	"Ett tomrum har uppstått i gillet: {vd} är inte längre med oss.",
	"{vd} har tagit sitt sista andetag.",
}

local CAUSES = {
	npc = {
		"Rycktes bort av en {k} i {z}.",
		"Föll offer för en {k} i {z}.",
		"En {k} i {z} blev för mycket.",
		"Mötte sitt öde i form av en {k} i {z}.",
	},
	npcAbility = {
		"Ett sista {a} från en {k} i {z} avgjorde saken.",
		"Fick ett {a} av en {k} i {z} och reste sig aldrig igen.",
	},
	player = {
		"Mördad av {k}, {c}, i {z}. Polisen är underrättad.",
		"Föll för {k} ({c}) i {z}. Ärendet är överlämnat till Polisen.",
		"Bragd om livet av {k}, {c}, i {z}. Gärningsmannen är efterlyst.",
	},
	pet = {
		"Dödad av {k} i {z}. Djurets ägare eftersöks.",
	},
	Falling = { "Föll från hög höjd i {z}.", "Glömde att man inte kan flyga i {z}." },
	Drowning = { "Drunknade i {z}.", "Höll andan för länge i {z}." },
	Fatigue = { "Simmade för långt ut i {z}." },
	Fire = { "Brann inne i {z}." },
	Lava = { "Gick ut i lavan i {z}." },
	Slime = { "Föll i slemmet i {z}." },
	unknown = { "Gick bort under oklara omständigheter i {z}." },
}

local SHAME = {
	"Fienden var bara nivå {kl}. Vi pratar inte om det.",
	"Fienden var nivå {kl}. Gillet ber om respekt för de anhörigas önskan om stillhet.",
}

local CLOSINGS = {
	"Saknad av hela " .. ns.GUILD .. ".",
	"Djupt saknad.",
	"Vila i frid.",
	"Begravningen sker vid närmaste andeläkare.",
	"I stället för blommor: betala din skatt.",
}

local function Fill(text, vars)
	return (text:gsub("{(%a+)}", function(key) return vars[key] or "?" end))
end

-- A tiny random generator seeded by the death id, so every member picks
-- the same wording for the same death.
local function Picker(id)
	local seed = 0
	for i = 1, #id do seed = (seed * 31 + id:byte(i)) % 2147483647 end
	if seed == 0 then seed = 1 end   -- 0 would stay 0 forever
	return function(list)
		seed = (seed * 16807) % 2147483647
		return list[seed % #list + 1]
	end
end

local function ClassName(classFile)
	return classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]
end

-- How many times this victim has died, as far as Rättsmedicinalverket knows.
local function DeathCount(victim)
	local n = 0
	for _, r in ipairs(Rattsmedicinalverket.Deaths()) do
		if r.victim == victim then n = n + 1 end
	end
	return n
end

local function Obituary(r)
	local pick = Picker(r.id)
	local killer = r.killer
	local blamed = false
	if r.kind ~= "player" and r.blame then
		-- A pet or guard landed the blow, but a hostile player was behind it.
		killer, blamed = r.blame, true
	end
	local vars = {
		v = r.victim, k = killer, kl = r.killerLevel and r.killerLevel > 0 and tostring(r.killerLevel) or nil,
		a = r.ability ~= "" and r.ability or nil, z = r.zone or "okänd plats",
	}
	local cause
	if blamed or (r.kind == "player" and r.hostile) then
		local level = blamed and r.blameLevel or r.killerLevel
		local class = ClassName(blamed and r.blameClass or r.killerClass)
		local race = blamed and r.blameRace or r.killerRace
		local desc = {}
		if race then table.insert(desc, race) end
		if class then table.insert(desc, class) end
		vars.c = (#desc > 0 and table.concat(desc, " ") or "okänd") .. (level and level > 0 and (" nivå " .. level) or "")
		cause = pick(CAUSES.player)
	elseif r.kind == "environment" then
		cause = pick(CAUSES[r.env] or CAUSES.unknown)
	elseif r.kind == "pet" and killer then
		cause = pick(CAUSES.pet)
	elseif killer then
		cause = pick(vars.a and CAUSES.npcAbility or CAUSES.npc)
	else
		cause = pick(CAUSES.unknown)
	end

	local who = {}
	if r.victimLevel then table.insert(who, "nivå " .. r.victimLevel) end
	local vclass = ClassName(r.victimClass)
	if vclass then table.insert(who, vclass) end
	vars.vd = #who > 0 and string.format("%s (%s)", r.victim, table.concat(who, " ")) or r.victim
	local parts = { Fill(pick(OPENINGS), vars), Fill(cause, vars) }
	-- Killed by something far below your level.
	if r.kind == "npc" and r.killerLevel and r.killerLevel > 0 and r.victimLevel
		and r.victimLevel - r.killerLevel >= 5 then
		table.insert(parts, Fill(pick(SHAME), vars))
	end
	local count = DeathCount(r.victim)
	if count > 1 then table.insert(parts, string.format("Det var dödsfall nummer %d.", count)) end
	table.insert(parts, pick(CLOSINGS))
	return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Level-up wording. {v} name, {vd} name with class, {l} the new level.

local LEVEL_OPENINGS = {
	"{vd} fyller {l} i dag.",
	"Grattis {vd}, som har nått nivå {l}!",
	"{vd} har tagit steget upp till nivå {l}.",
	"Hipp hipp hurra: {vd} är nu nivå {l}.",
	"Gillet gratulerar {vd} på nivå {l}.",
}

-- An extra line on the levels that matter.
local LEVEL_MILESTONES = {
	[10] = "Nu börjar talangerna.",
	[20] = "En tredjedel av vägen är avklarad.",
	[30] = "Halvvägs dit.",
	[40] = "Dags för ridlektioner.",
	[50] = "Bara tio nivåer kvar.",
}

local LEVEL_CLOSINGS = {
	"Grattis från hela " .. ns.GUILD .. ".",
	"Uppvaktning undanbedes.",
	"Tårta serveras vid närmaste värdshus.",
	"Kom ihåg att skatten följer inkomsten.",
	"Hurra!",
}

local MAX_LEVEL_LINES = {
	"{vd} har nått nivå {l}, den högsta som finns. Nu börjar det riktiga arbetet. Ett stort grattis från hela " .. ns.GUILD .. "!",
	"Hela " .. ns.GUILD .. " firar: {vd} har nått nivå {l}! Fanfarer, tårta och ledigt resten av dagen.",
}

local function LevelNotice(name, level, classFile)
	local pick = Picker(name .. ":" .. level)
	local class = ClassName(classFile)
	local vars = { v = name, l = tostring(level), vd = class and string.format("%s (%s)", name, class) or name }
	local maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
	if level >= maxLevel then return Fill(pick(MAX_LEVEL_LINES), vars) end
	local parts = { Fill(pick(LEVEL_OPENINGS), vars) }
	if LEVEL_MILESTONES[level] then table.insert(parts, LEVEL_MILESTONES[level]) end
	table.insert(parts, pick(LEVEL_CLOSINGS))
	return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Pet level-up wording. {p} the pet, {pd} the pet with its family, {o} the
-- owner, {os} the owner's genitive ("Kalles"), {l} the new level.

local PET_OPENINGS = {
	"{os} {pd} fyller {l} i dag.",
	"Grattis {pd}, som har nått nivå {l}! Ägaren {o} är mycket stolt.",
	"Det morras av glädje hos {o}: {pd} är nu nivå {l}.",
	"{pd} har tagit steget upp till nivå {l}, med {o} i kopplet.",
	"Gillet gratulerar {os} trogna {pd} på nivå {l}.",
}

local PET_CLOSINGS = {
	"Extra ben i matskålen i kväll.",
	"Klappar mottages tacksamt.",
	"Husdjur är skattebefriade. Än så länge.",
	"Glöm inte att mata.",
	"Ingen har varit en bättre vovve. Eller vad det nu är.",
	"Grattis från hela " .. ns.GUILD .. ".",
}

local PET_MAX_LINES = {
	"{os} {pd} har nått nivå {l}, den högsta som finns. Bäst i kullen! Grattis från hela " .. ns.GUILD .. ".",
	"Hela " .. ns.GUILD .. " firar: {os} {pd} är nivå {l}! Det blir köttben åt alla.",
}

-- Swedish genitive: Kalle → Kalles, Lars → Lars.
local function Genitive(name)
	if name:match("[sSxXzZ]$") then return name end
	return name .. "s"
end

local function PetNotice(owner, pet, level, family)
	local pick = Picker(owner .. ":" .. pet .. ":" .. level)
	local vars = {
		o = owner, os = Genitive(owner), p = pet, l = tostring(level),
		pd = (family and family ~= "") and string.format("%s (%s)", pet, family:lower()) or pet,
	}
	local maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
	if level >= maxLevel then return Fill(pick(PET_MAX_LINES), vars) end
	return Fill(pick(PET_OPENINGS), vars) .. " " .. pick(PET_CLOSINGS)
end

---------------------------------------------------------------------------

local function OnDeath(r)
	if not db or shown[r.id] or not InOurGuild() then return end
	shown[r.id] = true
	local text = Obituary(r)
	table.insert(db.recent, { id = r.id, time = r.time, text = text })
	while #db.recent > KEEP do table.remove(db.recent, 1) end
	if not db.quiet then
		DEFAULT_CHAT_FRAME:AddMessage(SKULL .. " |cffd8d8d8" .. text .. "|r")
		if PlaySound and SOUNDKIT and SOUNDKIT.UI_BNET_TOAST then
			-- A quiet chime; the obituary should not make anyone jump.
			pcall(PlaySound, SOUNDKIT.UI_BNET_TOAST)
		end
	end
	ownCopy[GuildLine(text)] = true
	heard["Dödsannons:" .. r.victim] = GetTime()
	if r.me and db.guildChat and IsInGuild() then
		-- Wait a little: Rättsmedicinalverket's record must reach the others
		-- before this line does, so their filter knows to hide it.
		C_Timer.After(2, function()
			-- Newer clients moved it into C_ChatInfo.
			local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
			if send then send(GuildLine(text), "GUILD") end
		end)
	end
end

local levelShown = {}   -- "name:level" already announced this session

local function ShowLevel(name, level, classFile)
	local key = name .. ":" .. level
	if levelShown[key] then return end
	levelShown[key] = true
	local text = LevelNotice(name, level, classFile)
	ownCopy[GuildLine(text, "Familjenytt")] = true
	heard["Familjenytt:" .. name] = GetTime()
	if not db.quiet then
		DEFAULT_CHAT_FRAME:AddMessage(STAR .. " |cffffe28a" .. text .. "|r")
	end
	return text
end

local function OnLevelUp(level)
	if not db or db.noLevels or not InOurGuild() or not level or level < 2 then return end
	local name = UnitName("player")
	local _, classFile = UnitClass("player")
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(PREFIX, string.format("L;%s;%d;%s", name, level, classFile or ""), "GUILD")
	end
	local text = ShowLevel(name, level, classFile)
	if text and db.guildChat then
		-- Same wait as the obituary, so the others hide the copy.
		C_Timer.After(2, function()
			local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
			if send and IsInGuild() then send(GuildLine(text, "Familjenytt"), "GUILD") end
		end)
	end
end

local PAW = "|TInterface\\Icons\\Ability_Hunter_BeastTraining:14|t"

local function ShowPetLevel(owner, pet, level, family)
	local key = "pet:" .. owner .. ":" .. pet .. ":" .. level
	if levelShown[key] then return end
	levelShown[key] = true
	local text = PetNotice(owner, pet, level, family)
	ownCopy[GuildLine(text, "Familjenytt")] = true
	heard["Familjenytt:" .. owner] = GetTime()
	if not db.quiet then
		DEFAULT_CHAT_FRAME:AddMessage(PAW .. " |cffffe28a" .. text .. "|r")
	end
	return text
end

-- Your pet's GUID and level as last seen, to tell a level-up from summoning
-- another pet.
local petGUID, petLevel

local function Plain(v)
	if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
	return v
end

local function ReadPet()
	if not UnitExists("pet") then petGUID, petLevel = nil, nil return end
	local guid, level = Plain(UnitGUID("pet")), Plain(UnitLevel("pet"))
	if guid ~= petGUID then
		-- Another pet, or the first look at this one: only remember it.
		petGUID, petLevel = guid, level
		return
	end
	local old = petLevel
	petLevel = level
	if not (old and level and level == old + 1) then return end
	local _, class = UnitClass("player")
	if class ~= "HUNTER" or not db or db.noLevels or db.noPets or not InOurGuild() then return end
	local owner, pet = UnitName("player"), Plain(UnitName("pet"))
	if not pet or pet == "" or pet:find(";") then return end
	local family = Plain(UnitCreatureFamily and UnitCreatureFamily("pet")) or ""
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(PREFIX, string.format("P;%s;%s;%d;%s", owner, pet, level, family), "GUILD")
	end
	local text = ShowPetLevel(owner, pet, level, family)
	if text and db.guildChat then
		C_Timer.After(2, function()
			local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
			if send and IsInGuild() then send(GuildLine(text, "Familjenytt"), "GUILD") end
		end)
	end
end

local function OnAddonMessage(prefix, msg, channel)
	if prefix ~= PREFIX or channel ~= "GUILD" or not db or db.noLevels or not InOurGuild() then return end
	if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
	local kind, name, a, b, c = strsplit(";", msg)
	if not name or name == "" or name == UnitName("player") then return end
	if kind == "L" then
		local level = tonumber(a)
		if level then ShowLevel(name, level, b ~= "" and b or nil) end
	elseif kind == "P" and not db.noPets then
		local level = tonumber(b)
		if a and a ~= "" and level then ShowPetLevel(name, a, level, c) end
	end
end

-- Members with the addon already have the notice in their own chat; hide
-- the copy the victim posts in guild chat (it is there for members
-- without the addon, and for the Discord bridge). With /dodsannons tyst
-- the guild line is the only one, so it stays.
--
-- The line can differ from ours (the death count is each member's own
-- count, and Rättsmedicinalverket shortens long fields on the way), so an
-- exact match is not enough: also hide a "Dödsannons:"/"Familjenytt:" line
-- from someone we showed a notice for in the last minute.
local function PlainText(v)
	if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) then return nil end
	return v
end

if ChatFrame_AddMessageEventFilter then
	ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", function(_, _, msg, author)
		msg, author = PlainText(msg), PlainText(author)
		if not db or db.quiet or not msg then return end
		if ownCopy[msg] then return true end
		local heading = msg:match("^(Dödsannons):") or msg:match("^(Familjenytt):")
		if not heading or not author then return end
		author = Ambiguate and Ambiguate(author, "none") or author:gsub("%-.*", "")
		local t = heard[heading .. ":" .. author]
		if t and GetTime() - t < 60 then return true end
	end)
end

local function Ago(t)
	local s = time() - (t or 0)
	if s < 3600 then return string.format("%d min sedan", math.max(1, math.floor(s / 60))) end
	if s < 86400 then return string.format("%d h sedan", math.floor(s / 3600)) end
	return string.format("%d d sedan", math.floor(s / 86400))
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("UNIT_PET")
events:RegisterEvent("UNIT_LEVEL")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
		if register then register(PREFIX) end
		ReadPet()
		return
	elseif event == "UNIT_PET" then
		if ... == "player" then ReadPet() end
		return
	elseif event == "UNIT_LEVEL" then
		if ... == "pet" then ReadPet() end
		return
	elseif event == "PLAYER_LEVEL_UP" then
		OnLevelUp(...)
		return
	elseif event == "CHAT_MSG_ADDON" then
		OnAddonMessage(...)
		return
	end
	local name = ...
	if name ~= "Dodsannonser" then return end
	DodsannonserDB = DodsannonserDB or {}
	db = DodsannonserDB
	db.recent = db.recent or {}
	-- On by default, so the guild's Discord bridge gets every obituary.
	if db.guildChat == nil then db.guildChat = true end
	for _, n in ipairs(db.recent) do
		shown[n.id] = true
		ownCopy[GuildLine(n.text)] = true
	end
	Rattsmedicinalverket.Register(OnDeath)
end)

SLASH_DODSANNONSER1 = "/dodsannons"
SLASH_DODSANNONSER2 = "/dödsannons"
SLASH_DODSANNONSER3 = "/minnesord"
SlashCmdList.DODSANNONSER = function(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "gillet" then
		db.guildChat = not db.guildChat
		Print(db.guildChat and "dina egna annonser (död och ny nivå) skrivs nu också i gillechatten (för medlemmar utan addonen)."
			or "dina annonser skrivs inte längre i gillechatten.")
	elseif cmd == "nivå" or cmd == "niva" then
		db.noLevels = not db.noLevels
		Print(db.noLevels and "nivåannonser är avstängda: du ser inga och skickar inga."
			or "nivåannonser är på igen: gillet får veta när du går upp en nivå.")
	elseif cmd == "husdjur" or cmd == "pet" then
		db.noPets = not db.noPets
		Print(db.noPets and "husdjurens nivåannonser är avstängda: du ser inga och skickar inga."
			or "husdjurens nivåannonser är på igen: gillet får veta när ditt husdjur går upp en nivå.")
	elseif cmd == "test husdjur" or cmd == "test pet" then
		-- A preview in your own chat only; nothing is sent.
		local pet = Plain(UnitName("pet")) or "Fluffy"
		local family = Plain(UnitCreatureFamily and UnitCreatureFamily("pet")) or "Varg"
		local level = (Plain(UnitLevel("pet")) or 23) + 1
		DEFAULT_CHAT_FRAME:AddMessage(PAW .. " |cffffe28a" .. PetNotice(UnitName("player"), pet, level, family) .. "|r")
	elseif cmd == "tyst" then
		db.quiet = not db.quiet
		Print(db.quiet and "annonser visas inte längre i chatten (dödsannonserna sparas ändå; /dodsannons visar dem)."
			or "annonser visas i chatten igen.")
	elseif cmd == "" then
		if #db.recent == 0 then
			Print("inga dödsannonser än.")
			return
		end
		Print("de senaste dödsannonserna:")
		for i = math.max(1, #db.recent - 9), #db.recent do
			local n = db.recent[i]
			DEFAULT_CHAT_FRAME:AddMessage(SKULL .. " |cff999999" .. Ago(n.time) .. ":|r " .. n.text)
		end
	else
		Print("/dodsannons visar de senaste, /dodsannons tyst döljer nya i chatten, /dodsannons gillet skriver dina egna i gillechatten, /dodsannons nivå stänger av nivåannonserna, /dodsannons husdjur stänger av husdjurens.")
	end
end
