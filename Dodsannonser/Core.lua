-- Dödsannonser: obituaries for THÖNDERSTÖRM on WoW Forever.
-- Rättsmedicinalverket hands every member the record of every guild
-- member's death; this turns each one into a short newspaper-style notice
-- in chat. Nothing is sent: everyone with the addon writes the notice
-- themselves, so it costs no messages and cannot be blocked. A member who
-- turns on /dodsannons gillet also posts their own obituary in guild chat,
-- for members without the addon (only the one who died posts, so there
-- are no duplicates).
--
-- Wording is picked at random from the lists below, but the same death
-- always gets the same wording on every computer (seeded by the death's id).

local _, ns = ...

ns.GUILD = "THÖNDERSTÖRM"
local SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14|t"
local KEEP = 50

local db
local shown = {}   -- death ids already announced this session

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
	if r.me and db.guildChat and IsInGuild() then
		local line = "Dödsannons: " .. text
		if #line > 255 then line = line:sub(1, 252) .. "..." end
		-- Newer clients moved it into C_ChatInfo.
		local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
		if send then send(line, "GUILD") end
	end
end

local function Ago(t)
	local s = time() - (t or 0)
	if s < 3600 then return string.format("%d min sedan", math.max(1, math.floor(s / 60))) end
	if s < 86400 then return string.format("%d h sedan", math.floor(s / 3600)) end
	return string.format("%d d sedan", math.floor(s / 86400))
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, name)
	if name ~= "Dodsannonser" then return end
	DodsannonserDB = DodsannonserDB or {}
	db = DodsannonserDB
	db.recent = db.recent or {}
	for _, n in ipairs(db.recent) do shown[n.id] = true end
	Rattsmedicinalverket.Register(OnDeath)
end)

SLASH_DODSANNONSER1 = "/dodsannons"
SLASH_DODSANNONSER2 = "/dödsannons"
SLASH_DODSANNONSER3 = "/minnesord"
SlashCmdList.DODSANNONSER = function(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "gillet" then
		db.guildChat = not db.guildChat
		Print(db.guildChat and "din egen dödsannons skrivs nu också i gillechatten (för medlemmar utan addonen)."
			or "din dödsannons skrivs inte längre i gillechatten.")
	elseif cmd == "tyst" then
		db.quiet = not db.quiet
		Print(db.quiet and "dödsannonser visas inte längre i chatten (de sparas ändå; /dodsannons visar dem)."
			or "dödsannonser visas i chatten igen.")
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
		Print("/dodsannons visar de senaste, /dodsannons tyst döljer nya i chatten, /dodsannons gillet skriver din egen i gillechatten.")
	end
end
