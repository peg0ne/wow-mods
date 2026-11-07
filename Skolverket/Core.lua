-- Skolverket: guild crafting directory for THÖNDERSTÖRM on WoW Forever.
-- Opening a profession window saves its recipes (only ever adding: recipes
-- are never unlearned, so collapsed headers and search filters cannot lose
-- any). Professions and ranks come from the skill list, so they show up
-- even before their window has been opened. Members announce what they
-- have and when each profession last changed; anyone holding older data
-- asks for it. Everything is kept between sessions, so crafters who are
-- offline can still be found.
--
-- Guild channel:
--   F                                          everyone: announce your professions
--   H;version;full;prof=rank=max=stamp,...     my professions; full = 1 when the
--                                              list is complete (others may drop
--                                              professions missing from it)
--   G;owner;prof                               owner: please send this profession
--   P;version;prof;stamp;part;total;key,...    a profession's recipes, in parts
-- Recipe keys: i<itemID> for recipes that make an item, e<recipeID> (a
-- spell ID) for the rest, such as enchants. A key may end
-- in @<seconds>: a cooldown recipe, ready in that many seconds (0 = ready).
--
-- Saved data: SkolverketCharDB.profs holds this character's own professions,
-- SkolverketDB.members everyone else's, SkolverketDB.names recipe names.
-- Never rename these or the folder.

local _, ns = ...

ns.GUILD = "THÖNDERSTÖRM"
ns.VERSION = "0.1"
ns.PREFIX = "SKOLA"
local CHUNK = 200

local db, char
ns.online = {}
local incoming = {}          -- sender -> prof -> { stamp, items, cd }
local requested = {}         -- "owner;prof" -> GetTime() we last wanted it (or heard it asked for)
local heard = {}             -- "owner;prof" -> GetTime() we last heard someone ask for it
local sentProf = {}          -- prof -> GetTime() we last sent it
local lastHello, lastAnswer, lastAsk, warnedVersion = nil, 0, 0, false

-- Forever's client has the modern API only: C_Item and C_Spell, not the
-- old globals.
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffff9933Skolverket:|r " .. text)
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

local function RequestRoster()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

-- This character's full name as the guild sees it. Forever names have two
-- words and UnitName gives only the first, so look it up by GUID in the
-- roster (as Arbetsförmedlingen does); nil until the roster has loaded.
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

local function Changed()
	if ns.RefreshWindow then ns.RefreshWindow() end
end

---------------------------------------------------------------------------
-- Sending. The server drops addon messages sent too fast, so everything
-- goes through a queue: a burst of 8, then one a second.

local outbox, tokens, lastRefill, pumping = {}, 8, 0, false

local function RawSend(msg)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(ns.PREFIX, msg, "GUILD")
	elseif SendAddonMessage then
		SendAddonMessage(ns.PREFIX, msg, "GUILD")
	end
end

local function Pump()
	local now = GetTime()
	tokens = math.min(8, tokens + (now - lastRefill))
	lastRefill = now
	while tokens >= 1 and #outbox > 0 do
		RawSend(table.remove(outbox, 1))
		tokens = tokens - 1
	end
	if #outbox > 0 then
		C_Timer.After(1, Pump)
	else
		pumping = false
	end
end

local function Send(msg)
	if not IsInGuild() then return end
	table.insert(outbox, msg)
	if not pumping then
		pumping = true
		Pump()
	end
end

---------------------------------------------------------------------------
-- Recipe names. Own scans give names directly; other members' recipes are
-- looked up in the game's item and spell data, which may need a moment.

local nameWaiting, refreshQueued = {}, false

function ns.Name(key)
	local n = db.names[key]
	if n then return n end
	local id = tonumber(key:sub(2))
	if not id then return end
	if key:sub(1, 1) == "i" then
		n = GetItemInfo(id)
		if not n then nameWaiting[id] = key end
	else
		n = SpellName(id)
	end
	if n then db.names[key] = n end
	return n
end

local function OnItemInfo(id)
	local key = nameWaiting[id]
	if not key then return end
	nameWaiting[id] = nil
	local n = GetItemInfo(id)
	if n then db.names[key] = n end
	if not refreshQueued then
		refreshQueued = true
		C_Timer.After(0.5, function()
			refreshQueued = false
			Changed()
		end)
	end
end

-- A clickable link for a recipe key.
function ns.Link(key)
	local id = tonumber(key:sub(2))
	if key:sub(1, 1) == "i" then
		local link = select(2, GetItemInfo(id))
		if link then return link end
		return string.format("|cffffffff|Hitem:%d|h[%s]|h|r", id, ns.Name(key) or ("#" .. id))
	end
	local link = C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(id)
	return link or string.format("|cff71d5ff|Hspell:%d|h[%s]|h|r", id, ns.Name(key) or ("#" .. id))
end

---------------------------------------------------------------------------
-- Own professions.

local function KeyFromLink(link)
	if not link then return end
	local id = link:match("item:(%d+)")
	if id then return "i" .. id end
	id = link:match("enchant:(%d+)") or link:match("spell:(%d+)")
	if id then return "e" .. id end
end

-- Professions from GetProfessions: name -> { rank, max }, and whether the
-- list is complete (always, with this API). nil if the client lacks it.
-- Fishing is left out: it has no recipes.
local FISHING = 356
local function SkillProfessions()
	if not GetProfessions or not GetProfessionInfo then return end
	local profs = {}
	for _, index in pairs({ GetProfessions() }) do
		local name, _, rank, max, _, _, skillLine = GetProfessionInfo(index)
		if name and skillLine ~= FISHING then profs[name] = { rank = rank, max = max } end
	end
	return profs, true
end

-- Bring char.profs in step with the skill list; true if anything changed.
local function SyncSkills()
	local skills, complete = SkillProfessions()
	if not skills then return false, false end
	local changed = false
	for name, s in pairs(skills) do
		local p = char.profs[name]
		if not p then
			p = { items = {}, cd = {}, stamp = 0 }
			char.profs[name] = p
			changed = true
		end
		if p.rank ~= s.rank or p.max ~= s.max then changed = true end
		p.rank, p.max, p.skill = s.rank, s.max, true
	end
	if complete then
		-- Drop professions that left the skill list (unlearned). Ones never
		-- seen there (a window named differently) are kept.
		for name, p in pairs(char.profs) do
			if p.skill and not skills[name] then
				char.profs[name] = nil
				changed = true
			end
		end
	end
	return changed, complete
end

local QueueHello

-- Add what the open window shows to that profession.
local function Merge(prof, rank, max, found, cds)
	if not prof or prof == "" or prof == "UNKNOWN" then return end
	local p = char.profs[prof] or { items = {}, cd = {}, stamp = 0 }
	char.profs[prof] = p
	local changed = false
	for key, name in pairs(found) do
		if not p.items[key] then
			p.items[key] = true
			changed = true
		end
		db.names[key] = db.names[key] or name
	end
	-- A recipe that ever showed a cooldown stays a cooldown recipe; with no
	-- cooldown left it is ready (0).
	for key in pairs(found) do
		local ready = cds[key] or (p.cd[key] and 0)
		if ready then
			if math.abs((p.cd[key] or -999) - ready) > 60 then changed = true end
			p.cd[key] = ready
		end
	end
	if rank and (p.rank ~= rank or p.max ~= max) then
		p.rank, p.max = rank, max
		QueueHello()
	end
	if changed then
		p.stamp = time()
		QueueHello()
		Changed()
	end
end

-- The open profession window, through C_TradeSkillUI. Recipes that make an
-- item are keyed by the item (so item tooltips can find crafters), others
-- (enchants) by the recipe's spell. Someone else's linked profession, a
-- guild profession view or an NPC's crafting is not ours and is skipped.
local function ScanTradeSkill()
	local T = C_TradeSkillUI
	if not T or not T.GetAllRecipeIDs or not T.GetBaseProfessionInfo then return end
	if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
		or (T.IsNPCCrafting and T.IsNPCCrafting()) then
		return
	end
	local base = T.GetBaseProfessionInfo()
	if not base or not base.professionName then return end
	local found, cds = {}, {}
	for _, recipeID in ipairs(T.GetAllRecipeIDs() or {}) do
		local info = T.GetRecipeInfo(recipeID)
		if info and info.learned then
			local key
			if T.GetRecipeOutputItemData then
				local ok, out = pcall(T.GetRecipeOutputItemData, recipeID)
				if ok and out and out.itemID then key = "i" .. out.itemID end
			end
			key = key or ("e" .. recipeID)
			found[key] = info.name
			if T.GetRecipeCooldown then
				local ok, cd = pcall(T.GetRecipeCooldown, recipeID)
				if ok and type(cd) == "number" and cd > 0 then cds[key] = time() + math.floor(cd) end
			end
		end
	end
	-- Rank comes from GetProfessions (SyncSkills); the window's own numbers
	-- can be a sub-profession's.
	Merge(base.professionName, nil, nil, found, cds)
end

-- The window fires many updates while opening; scan once they settle.
local scanQueued = false
local function QueueScan()
	if scanQueued then return end
	scanQueued = true
	C_Timer.After(0.5, function()
		scanQueued = false
		ScanTradeSkill()
	end)
end

---------------------------------------------------------------------------
-- Announcing and answering.

local function SendHello(force)
	if not char or not ns.InOurGuild() then return end
	local _, complete = SyncSkills()
	local list = {}
	for name, p in pairs(char.profs) do
		table.insert(list, string.format("%s=%d=%d=%d", name, p.rank or 0, p.max or 0, p.stamp or 0))
	end
	table.sort(list)
	local msg = string.format("H;%s;%d;%s", ns.VERSION, complete and 1 or 0, table.concat(list, ","))
	if msg == lastHello and not force then return end
	lastHello = msg
	Send(msg)
end

local helloQueued = false
QueueHello = function()
	if helloQueued then return end
	helloQueued = true
	C_Timer.After(5, function()
		helloQueued = false
		SendHello(false)
	end)
end

local function SendProf(prof)
	local p = char.profs[prof]
	if not p or (p.stamp or 0) == 0 then return end
	if GetTime() - (sentProf[prof] or -999) < 20 then return end
	sentProf[prof] = GetTime()
	local keys = {}
	for key in pairs(p.items) do
		local ready = p.cd[key]
		if ready then key = key .. "@" .. math.max(0, ready - time()) end
		table.insert(keys, key)
	end
	table.sort(keys)
	local parts, current, length = {}, {}, 0
	for _, key in ipairs(keys) do
		if length + #key + 1 > CHUNK and #current > 0 then
			table.insert(parts, table.concat(current, ","))
			current, length = {}, 0
		end
		table.insert(current, key)
		length = length + #key + 1
	end
	table.insert(parts, table.concat(current, ","))
	for i, part in ipairs(parts) do
		Send(string.format("P;%s;%s;%d;%d;%d;%s", ns.VERSION, prof, p.stamp, i, #parts, part))
	end
end

-- Someone has newer data than we do: ask for it, unless another member
-- asks first (everyone hears the answer).
local function Want(owner, prof)
	local id = owner .. ";" .. prof
	if GetTime() - (requested[id] or -999) < 30 then return end
	local at = GetTime()
	requested[id] = at
	C_Timer.After(1 + math.random() * 3, function()
		if (heard[id] or 0) >= at then return end   -- someone else asked meanwhile
		Send("G;" .. owner .. ";" .. prof)
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

local function CheckVersion(version)
	if not warnedVersion and VersionNumber(version) > VersionNumber(ns.VERSION) then
		warnedVersion = true
		Print("det finns en nyare Skolverket (" .. version .. "); be gildeledaren om den.")
	end
end

local function Member(name)
	local m = db.members[name]
	if not m then
		m = { profs = {} }
		db.members[name] = m
	end
	m.seen = time()
	return m
end

local function OnHello(sender, parts)
	CheckVersion(parts[2])
	local m = Member(sender)
	local listed = {}
	for entry in (parts[4] or ""):gmatch("[^,]+") do
		local prof, rank, max, stamp = entry:match("^(.-)=(%d+)=(%d+)=(%d+)$")
		if prof then
			listed[prof] = true
			local p = m.profs[prof] or { items = {}, cd = {}, stamp = 0 }
			m.profs[prof] = p
			p.rank, p.max = tonumber(rank), tonumber(max)
			stamp = tonumber(stamp)
			if stamp > 0 and stamp > (p.stamp or 0) then Want(sender, prof) end
		end
	end
	if parts[3] == "1" then
		for prof in pairs(m.profs) do
			if not listed[prof] then m.profs[prof] = nil end
		end
	end
	Changed()
end

local function OnGive(parts)
	local owner, prof = parts[2], parts[3]
	if not owner or not prof then return end
	local id = owner .. ";" .. prof
	requested[id], heard[id] = GetTime(), GetTime()
	if ns.IsMe(owner) then
		C_Timer.After(math.random(), function() SendProf(prof) end)
	end
end

local function OnProf(sender, parts)
	CheckVersion(parts[2])
	local prof, stamp, part, total = parts[3], tonumber(parts[4]), tonumber(parts[5]), tonumber(parts[6])
	if not prof or not stamp or not part or not total then return end
	incoming[sender] = incoming[sender] or {}
	if part == 1 then incoming[sender][prof] = { stamp = stamp, items = {}, cd = {}, next = 1 } end
	local got = incoming[sender][prof]
	-- A missing part means the list is incomplete; drop it and ask again later.
	if not got or got.stamp ~= stamp or got.next ~= part then
		incoming[sender][prof] = nil
		return
	end
	got.next = part + 1
	local now = time()
	for item in (parts[7] or ""):gmatch("[^,]+") do
		local key, ready = item:match("^([ie]%d+)@?(%d*)$")
		if key then
			got.items[key] = true
			if ready ~= "" then got.cd[key] = now + tonumber(ready) end
		end
	end
	if part < total then return end
	incoming[sender][prof] = nil
	local m = Member(sender)
	local p = m.profs[prof] or {}
	if stamp < (p.stamp or 0) then return end
	p.items, p.cd, p.stamp = got.items, got.cd, stamp
	m.profs[prof] = p
	Changed()
end

local function OnAddonMessage(prefix, msg, channel, sender)
	if prefix ~= ns.PREFIX or channel ~= "GUILD" or not char or not ns.InOurGuild() then return end
	sender = ns.Short(sender)
	if not sender or ns.IsMe(sender) then return end
	ns.online[sender] = true
	local parts = { strsplit(";", msg) }
	if parts[1] == "F" then
		-- Many answer at once; spread the answers and answer at most every 5 s.
		if GetTime() - lastAnswer > 5 then
			lastAnswer = GetTime()
			C_Timer.After(math.random() * 4, function() SendHello(true) end)
		end
	elseif parts[1] == "H" then
		OnHello(sender, parts)
	elseif parts[1] == "G" then
		OnGive(parts)
	elseif parts[1] == "P" then
		OnProf(sender, parts)
	end
end

-- Who is online; and with the offline members shown, forget anyone who
-- has left the guild.
local function OnRoster()
	local n = GetNumGuildMembers()
	if n == 0 then return end
	local online, all = {}, {}
	for i = 1, n do
		local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
		name = ns.Short(name)
		if name then
			all[name] = true
			if isOnline then online[name] = true end
		end
	end
	ns.online = online
	if GetGuildRosterShowOffline and GetGuildRosterShowOffline() then
		for name in pairs(db.members) do
			if not all[name] then db.members[name] = nil end
		end
	end
	Changed()
end

---------------------------------------------------------------------------
-- Lookups for the window and tooltips.

-- Everyone with professions, own character first: { name, me, online, profs }.
function ns.People()
	local people = {}
	if char and next(char.profs) then
		table.insert(people, { name = ns.Me() or UnitName("player"), me = true, online = true, profs = char.profs })
	end
	for name, m in pairs(db.members) do
		if not ns.IsMe(name) and next(m.profs) then
			table.insert(people, { name = name, online = ns.online[name] and true or false, seen = m.seen, profs = m.profs })
		end
	end
	return people
end

local function ByCrafter(a, b)
	if a.me ~= b.me then return a.me end
	if a.online ~= b.online then return a.online end
	if (a.rank or 0) ~= (b.rank or 0) then return (a.rank or 0) > (b.rank or 0) end
	return a.name < b.name
end

-- Who can craft this recipe key: { name, me, online, rank, cd }.
function ns.Crafters(key)
	local list = {}
	for _, person in ipairs(ns.People()) do
		for _, p in pairs(person.profs) do
			if p.items[key] then
				table.insert(list, { name = person.name, me = person.me, online = person.online, rank = p.rank, cd = p.cd[key] })
				break
			end
		end
	end
	table.sort(list, ByCrafter)
	return list
end

-- Recipes matching the search text: { key, name, prof, crafters }.
-- Unknown names are looked up; those rows show the number for now.
function ns.Search(text)
	text = (text or ""):lower()
	local byKey = {}
	for _, person in ipairs(ns.People()) do
		for prof, p in pairs(person.profs) do
			for key in pairs(p.items) do
				local row = byKey[key]
				if not row then
					row = { key = key, prof = prof, crafters = {} }
					byKey[key] = row
				end
				table.insert(row.crafters, { name = person.name, me = person.me, online = person.online, rank = p.rank, cd = p.cd[key] })
			end
		end
	end
	local list = {}
	for key, row in pairs(byKey) do
		row.name = ns.Name(key)
		local hay = ((row.name or "") .. " " .. row.prof):lower()
		if text == "" or hay:find(text, 1, true) then
			table.sort(row.crafters, ByCrafter)
			table.insert(list, row)
		end
	end
	table.sort(list, function(a, b)
		if (a.name ~= nil) ~= (b.name ~= nil) then return a.name ~= nil end
		return (a.name or a.key) < (b.name or b.key)
	end)
	return list
end

-- Cooldown recipes, one row per member, profession and shared cooldown:
-- { name, me, online, prof, keys, ready }. Soonest first, ready ones on top.
function ns.Cooldowns()
	local list = {}
	for _, person in ipairs(ns.People()) do
		for prof, p in pairs(person.profs) do
			local groups = {}
			for key, ready in pairs(p.cd or {}) do
				-- Recipes sharing one cooldown (transmutes) end within a minute of each other.
				local slot = math.floor(math.max(ready, time()) / 60)
				local g = groups[slot]
				if not g then
					g = { name = person.name, me = person.me, online = person.online, prof = prof, keys = {}, ready = ready }
					groups[slot] = g
					table.insert(list, g)
				end
				table.insert(g.keys, key)
			end
		end
	end
	local now = time()
	table.sort(list, function(a, b)
		local ra, rb = math.max(a.ready, now), math.max(b.ready, now)
		if ra ~= rb then return ra < rb end
		if a.online ~= b.online then return a.online end
		return a.name < b.name
	end)
	return list
end

function ns.Remaining(ready)
	local left = (ready or 0) - time()
	if left <= 0 then return "|cff40ff40redo|r" end
	local h, m = math.floor(left / 3600), math.floor(left / 60) % 60
	if h >= 24 then return string.format("om %dd %dh", math.floor(h / 24), h % 24) end
	if h > 0 then return string.format("om %dh %dm", h, m) end
	return string.format("om %dm", math.max(1, m))
end

---------------------------------------------------------------------------
-- Item tooltips: who in the guild can craft this.

local function AddCrafterLine(tooltip, link)
	if not db or not link or not ns.InOurGuild() then return end
	local key = KeyFromLink(link)
	if not key then return end
	local crafters = ns.Crafters(key)
	if #crafters == 0 then return end
	local names = {}
	for i = 1, math.min(4, #crafters) do
		local c = crafters[i]
		local name = c.me and "du" or c.name
		table.insert(names, c.online and ("|cff40ff40" .. name .. "|r") or ("|cff999999" .. name .. "|r"))
	end
	if #crafters > 4 then table.insert(names, string.format("+%d", #crafters - 4)) end
	tooltip:AddLine("Skolverket: " .. table.concat(names, ", "), 1, 0.6, 0.2)
	tooltip:Show()
end

local function HookTooltips()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
			if tooltip.GetItem then AddCrafterLine(tooltip, select(2, tooltip:GetItem())) end
		end)
		return
	end
	for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
		if tooltip then
			pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self)
				AddCrafterLine(self, select(2, self:GetItem()))
			end)
		end
	end
end

---------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({
	"ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE", "SKILL_LINES_CHANGED",
	"TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED", "GET_ITEM_INFO_RECEIVED",
}) do
	-- Not every client has every event; an unknown one would raise an error.
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "Skolverket" then
			SkolverketDB = SkolverketDB or {}
			db = SkolverketDB
			db.members = db.members or {}
			db.names = db.names or {}
			SkolverketCharDB = SkolverketCharDB or {}
			char = SkolverketCharDB
			char.profs = char.profs or {}
			HookTooltips()
		end
	elseif not char then
		return
	elseif event == "PLAYER_LOGIN" then
		local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
		if register then register(ns.PREFIX) end
		RequestRoster()
		C_Timer.After(15, function()
			SendHello(true)
			ns.Ask()
		end)
	elseif event == "CHAT_MSG_ADDON" then
		OnAddonMessage(...)
	elseif event == "GUILD_ROSTER_UPDATE" then
		OnRoster()
	elseif event == "SKILL_LINES_CHANGED" then
		if SyncSkills() then QueueHello() Changed() end
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "NEW_RECIPE_LEARNED" then
		QueueScan()
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		OnItemInfo(...)
	end
end)

SLASH_SKOLVERKET1 = "/skola"
SLASH_SKOLVERKET2 = "/skolverket"
SlashCmdList.SKOLVERKET = function(msg)
	if not ns.InOurGuild() then
		Print("den här karaktären är inte med i " .. ns.GUILD .. ".")
		return
	end
	ns.ToggleWindow(strtrim(msg or ""))
end
