-- Skolverket: profession cooldowns and crafters on item tooltips for
-- THÖNDERSTÖRM on WoW Forever.
--
-- Until 0.2 Skolverket was a whole crafting directory. Skatteverket 0.22 has
-- one now (/skatt yrken: every member's professions and recipes, a search,
-- and a recipe window), so 0.3 keeps only what Skatteverket lacks:
--   * Item tooltips name who in the guild can craft the item, read from
--     the recipes Skatteverket keeps (SkatteverketDB.recipes). Nothing is
--     sent for this.
--   * Profession cooldowns (transmutes, Mooncloth ...): read when you open
--     a profession window, shared on the guild channel, listed in /skola.
--
-- Guild channel (prefix SKOLA; 0.2's F/H/G/P messages are ignored, and 0.2
-- ignores these):
--   Q                                   everyone: send your cooldowns
--   C;version;prof;stamp;key@secs,...   my cooldown recipes in a profession;
--                                       secs until ready (0 = ready)
-- Keys: i<itemID> for recipes that make an item, e<recipeID> for the rest.
--
-- Saved data: SkolverketCharDB.cds this character's cooldowns,
-- SkolverketDB.cds everyone else's, SkolverketDB.names recipe names.
-- Never rename these or the folder.

local _, ns = ...

ns.GUILD = "THÖNDERSTÖRM"
ns.VERSION = "0.3"
ns.PREFIX = "SKOLA"
local MAX_MESSAGE = 240

local db, char
ns.online = {}
local inGuild                -- name -> true from the last full roster, or nil before it loads
local lastAnswer, lastAsk, warnedVersion = 0, 0, false

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

local RequestRoster = Statskontoret.RequestRoster

-- This character's full name as the guild sees it. Forever names have two
-- words and UnitName gives only the first, so look it up by GUID in the
-- roster; nil until the roster has loaded.
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

-- Throttled: the server drops floods (see Statskontoret.Sender).
local Send = Statskontoret.Sender(ns.PREFIX)

---------------------------------------------------------------------------
-- Recipe names: own scans give names directly; other members' recipes are
-- looked up in the game's item and spell data.

function ns.Name(key)
	local n = db.names[key]
	if n then return n end
	local id = tonumber(key:sub(2))
	if not id then return end
	if key:sub(1, 1) == "i" then n = GetItemInfo(id) else n = SpellName(id) end
	if n then db.names[key] = n end
	return n
end

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
-- Own cooldowns, read from the open profession window.

local QueueSend

-- A recipe that ever showed a cooldown stays a cooldown recipe; with no
-- cooldown left it is ready (0).
local function Merge(prof, found, cds)
	local p = char.cds[prof] or { stamp = 0, keys = {} }
	local changed = false
	for key, name in pairs(found) do
		db.names[key] = db.names[key] or name
		local ready = cds[key] or (p.keys[key] and 0)
		if ready and math.abs((p.keys[key] or -999) - ready) > 60 then
			p.keys[key] = ready
			changed = true
		end
	end
	if changed then
		p.stamp = time()
		char.cds[prof] = p
		QueueSend(prof)
		Changed()
	end
end

-- Someone else's linked profession, a guild view or an NPC's crafting is
-- not ours and is skipped.
local function ScanTradeSkill()
	local T = C_TradeSkillUI
	if not T or not T.GetAllRecipeIDs or not T.GetRecipeCooldown then return end
	if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
		or (T.IsNPCCrafting and T.IsNPCCrafting()) then
		return
	end
	local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
	local prof = base and base.professionName
	local all = T.GetAllRecipeIDs() or {}
	if (not prof or prof == "" or prof == "UNKNOWN") and all[1] then
		-- Some clients leave the base info empty; ask a recipe instead.
		if T.GetProfessionInfoByRecipeID then
			local ok, info = pcall(T.GetProfessionInfoByRecipeID, all[1])
			if ok and info then prof = info.parentProfessionName or info.professionName end
		end
		if (not prof or prof == "") and T.GetTradeSkillLineForRecipe then
			-- Returns tradeSkillID, skillLineName, parentTradeSkillID.
			local ok, _, name = pcall(T.GetTradeSkillLineForRecipe, all[1])
			if ok then prof = name end
		end
	end
	if not prof or prof == "" or prof == "UNKNOWN" then return end
	local found, cds = {}, {}
	for _, recipeID in ipairs(all) do
		local info = T.GetRecipeInfo(recipeID)
		if info and info.learned then
			local key
			if T.GetRecipeOutputItemData then
				local ok, out = pcall(T.GetRecipeOutputItemData, recipeID)
				if ok and out and out.itemID then key = "i" .. out.itemID end
			end
			key = key or ("e" .. recipeID)
			local ok, cd = pcall(T.GetRecipeCooldown, recipeID)
			if ok and type(cd) == "number" and cd > 0 then cds[key] = time() + math.floor(cd) end
			if cds[key] or (char.cds[prof] and char.cds[prof].keys[key]) then found[key] = info.name end
		end
	end
	Merge(prof, found, cds)
end

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
-- Sharing cooldowns.

local function SendProf(prof)
	local p = char.cds[prof]
	if not p or not next(p.keys) or not ns.InOurGuild() then return end
	local head = string.format("C;%s;%s;%d;", ns.VERSION, prof, p.stamp)
	local keys, length = {}, #head
	for key, ready in pairs(p.keys) do
		local item = key .. "@" .. math.max(0, ready - time())
		if length + #item + 1 > MAX_MESSAGE then break end
		table.insert(keys, item)
		length = length + #item + 1
	end
	Send(head .. table.concat(keys, ","))
end

local function SendAll()
	for prof in pairs(char.cds) do SendProf(prof) end
end

local sendQueued = {}
QueueSend = function(prof)
	if sendQueued[prof] then return end
	sendQueued[prof] = true
	C_Timer.After(5, function()
		sendQueued[prof] = nil
		SendProf(prof)
	end)
end

function ns.Ask()
	if GetTime() - lastAsk < 10 then return end
	lastAsk = GetTime()
	Send("Q")
	RequestRoster()
end

local function VersionNumber(v)
	local major, minor = tostring(v or ""):match("^(%d+)%.(%d+)")
	return major and (tonumber(major) * 1000 + tonumber(minor)) or 0
end

local function CheckVersion(version)
	if not warnedVersion and VersionNumber(version) > VersionNumber(ns.VERSION) then
		warnedVersion = true
		Print("det finns en nyare Skolverket (" .. version .. "); uppdatera i WowUp.")
	end
end

local function OnCooldowns(sender, parts)
	CheckVersion(parts[2])
	local prof, stamp = parts[3], tonumber(parts[4])
	if not prof or not stamp then return end
	local m = db.cds[sender] or { profs = {} }
	db.cds[sender] = m
	m.seen = time()
	local old = m.profs[prof]
	if old and old.stamp > stamp then return end
	local keys, now = {}, time()
	for item in (parts[5] or ""):gmatch("[^,]+") do
		local key, secs = item:match("^([ie]%d+)@(%d+)$")
		if key then keys[key] = now + tonumber(secs) end
	end
	m.profs[prof] = { stamp = stamp, keys = keys }
	Changed()
end

local function OnAddonMessage(prefix, msg, channel, sender)
	if prefix ~= ns.PREFIX or channel ~= "GUILD" or not char or not ns.InOurGuild() then return end
	sender = ns.Short(sender)
	if not sender or ns.IsMe(sender) then return end
	ns.online[sender] = true
	local parts = { strsplit(";", msg) }
	if parts[1] == "Q" then
		-- Many answer at once; spread the answers and answer at most every 5 s.
		if GetTime() - lastAnswer > 5 then
			lastAnswer = GetTime()
			C_Timer.After(math.random() * 4, SendAll)
		end
	elseif parts[1] == "C" then
		OnCooldowns(sender, parts)
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
	-- Only prune against our own guild's roster: SkolverketDB is shared by
	-- the account, and an alt in another guild would otherwise drop every
	-- THÖNDERSTÖRM member's cooldowns.
	if ns.InOurGuild() and GetGuildRosterShowOffline and GetGuildRosterShowOffline() then
		inGuild = all
		for name in pairs(db.cds) do
			if not all[name] then db.cds[name] = nil end
		end
	end
	Changed()
end

---------------------------------------------------------------------------
-- The cooldown list for the window.

-- One row per member, profession and shared cooldown:
-- { name, me, online, prof, keys, ready }. Soonest first, ready ones on top.
function ns.Cooldowns()
	local people = { { name = ns.Me() or UnitName("player"), me = true, online = true, profs = char.cds } }
	for name, m in pairs(db.cds) do
		if not ns.IsMe(name) then
			table.insert(people, { name = name, online = ns.online[name] and true or false, profs = m.profs })
		end
	end
	local list = {}
	for _, person in ipairs(people) do
		for prof, p in pairs(person.profs) do
			local groups = {}
			for key, ready in pairs(p.keys or {}) do
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
-- Item tooltips: who in the guild can craft this, from Skatteverket's
-- recipe lists. On Forever they hold recipe numbers ("s<recipeID>" plus a
-- difficulty letter); the item a recipe makes is looked up once per recipe.
-- The index is rebuilt when any list's time stamp changes.

local recipeItem = {}        -- recipeID -> itemID, or false if it makes none
local crafters, signature = {}, nil   -- itemID -> { name = true }

local function ItemOfRecipe(id)
	local v = recipeItem[id]
	if v ~= nil then return v end
	v = false
	local T = C_TradeSkillUI
	if T and T.GetRecipeSchematic then
		local ok, s = pcall(T.GetRecipeSchematic, id, false)
		if ok and s and s.outputItemID then v = s.outputItemID end
	end
	if not v and T and T.GetRecipeOutputItemData then
		local ok, out = pcall(T.GetRecipeOutputItemData, id)
		if ok and out and out.itemID then v = out.itemID end
	end
	recipeItem[id] = v
	return v
end

local function RecipeLists()
	local recipes = SkatteverketDB and SkatteverketDB.recipes
	return type(recipes) == "table" and recipes or nil
end

local function Signature(recipes)
	local sum, count = 0, 0
	for _, lists in pairs(recipes) do
		if type(lists) == "table" then
			for _, list in pairs(lists) do
				if type(list) == "table" then
					sum, count = sum + (tonumber(list.at) or 0), count + 1
				end
			end
		end
	end
	return sum .. ":" .. count
end

local function Crafters(itemID)
	local recipes = RecipeLists()
	if not recipes then return nil end
	local sig = Signature(recipes)
	if sig ~= signature then
		signature, crafters = sig, {}
		for name, lists in pairs(recipes) do
			if type(lists) == "table" and (not inGuild or inGuild[name]) then
				for _, list in pairs(lists) do
					for _, key in ipairs(type(list) == "table" and type(list.keys) == "table" and list.keys or {}) do
						local kind, id = tostring(key):match("^([si])(%d+)")
						local item = kind == "i" and tonumber(id) or (kind == "s" and ItemOfRecipe(tonumber(id)))
						if item then
							crafters[item] = crafters[item] or {}
							crafters[item][name] = true
						end
					end
				end
			end
		end
	end
	return crafters[itemID]
end

local function AddCrafterLine(tooltip, link)
	-- The client may hide values from addons (in combat, for instance);
	-- a hidden link cannot be read, so add nothing.
	if issecretvalue and issecretvalue(link) then return end
	if not db or type(link) ~= "string" or not ns.InOurGuild() then return end
	local itemID = tonumber(link:match("item:(%d+)"))
	local who = itemID and Crafters(itemID)
	if not who then return end
	local list = {}
	for name in pairs(who) do
		table.insert(list, { name = name, me = ns.IsMe(name), online = ns.online[name] and true or false })
	end
	table.sort(list, function(a, b)
		if a.me ~= b.me then return a.me end
		if a.online ~= b.online then return a.online end
		return a.name < b.name
	end)
	local names = {}
	for i = 1, math.min(4, #list) do
		local c = list[i]
		local name = c.me and "du" or c.name
		table.insert(names, (c.me or c.online) and ("|cff40ff40" .. name .. "|r") or ("|cff999999" .. name .. "|r"))
	end
	if #list > 4 then table.insert(names, string.format("+%d", #list - 4)) end
	tooltip:AddLine("Kan tillverkas av: " .. table.concat(names, ", "), 1, 0.6, 0.2)
	tooltip:Show()
end

local function HookTooltips()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
			if tooltip.GetItem then pcall(AddCrafterLine, tooltip, select(2, tooltip:GetItem())) end
		end)
		return
	end
	for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
		if tooltip then
			pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self)
				pcall(AddCrafterLine, self, select(2, self:GetItem()))
			end)
		end
	end
end

---------------------------------------------------------------------------

-- 0.2 kept everyone's whole recipe lists; keep only the cooldowns.
local function Migrate()
	for prof, p in pairs(char.profs or {}) do
		if type(p.cd) == "table" and next(p.cd) then
			char.cds[prof] = char.cds[prof] or { stamp = p.stamp or 0, keys = p.cd }
		end
	end
	for name, m in pairs(db.members or {}) do
		for prof, p in pairs(m.profs or {}) do
			if type(p.cd) == "table" and next(p.cd) then
				db.cds[name] = db.cds[name] or { seen = m.seen, profs = {} }
				db.cds[name].profs[prof] = { stamp = p.stamp or 0, keys = p.cd }
			end
		end
	end
	char.profs, db.members = nil, nil
end

local events = CreateFrame("Frame")
for _, event in ipairs({
	"ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE",
	"TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED",
}) do
	-- Not every client has every event; an unknown one would raise an error.
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "Skolverket" then
			SkolverketDB = SkolverketDB or {}
			db = SkolverketDB
			db.cds = db.cds or {}
			db.names = db.names or {}
			SkolverketCharDB = SkolverketCharDB or {}
			char = SkolverketCharDB
			char.cds = char.cds or {}
			Migrate()
			HookTooltips()
		end
	elseif not char then
		return
	elseif event == "PLAYER_LOGIN" then
		local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
		if register then register(ns.PREFIX) end
		RequestRoster()
		C_Timer.After(15, function()
			SendAll()
			ns.Ask()
		end)
	elseif event == "CHAT_MSG_ADDON" then
		OnAddonMessage(...)
	elseif event == "GUILD_ROSTER_UPDATE" then
		OnRoster()
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "NEW_RECIPE_LEARNED" then
		QueueScan()
	end
end)

SLASH_SKOLVERKET1 = "/skola"
SLASH_SKOLVERKET2 = "/skolverket"
SlashCmdList.SKOLVERKET = function()
	if not ns.InOurGuild() then
		Print("den här karaktären är inte med i " .. ns.GUILD .. ".")
		return
	end
	ns.ToggleWindow()
end
