-- Lantmäteriet: gathering nodes (herbs and ore) for THÖNDERSTÖRM.
--
-- The game doesn't tell addons where the nodes around you are, so this
-- works two ways:
--   * Glow.lua lights up the node the Interact key would use (the game's
--     soft targeting, so one at a time and only nearby), in the node's
--     color when your skill is high enough and red when it isn't.
--   * Every node you gather (or try to) is saved with where it was, and
--     sent to the guild. Map.lua shows the ones the guild knows on the
--     world map and the minimap, at any distance.
--
-- A node's position is yours when you start gathering it (within a few
-- yards). A node already saved within 20 yards under the same name is the
-- same node: its time is brought up to date.
--
-- Guild channel (prefix LANTM):
--   N|map,x,y,t,name|...   nodes; x and y in 0-10000, t server time
--   S;since                 send me the nodes you found after `since`
-- An S is answered by whisper with the answerer's own finds only, so
-- nobody sends what someone else found.

local addonName, ns = ...

ns.GUILD = "THÖNDERSTÖRM"
ns.PREFIX = "LANTM"
local SAME_NODE_YARDS = 20
local MAX_PER_MAP = 3000
local MAX_ANSWER = 400

local db

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff99cc33Lantmäteriet:|r " .. text)
end
ns.Print = Print

-- A value the addon may read (not hidden by the game), or nil.
local function Plain(v)
	if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
	return v
end
ns.Plain = Plain

function ns.InOurGuild()
	return GetGuildInfo("player") == ns.GUILD
end

local function Short(name)
	if not name then return nil end
	if Ambiguate then return Ambiguate(name, "none") end
	return (name:gsub("%-.*", ""))
end

---------------------------------------------------------------------------
-- Skills and what a node needs.

local skills, skillsAt = {}, -1

-- Your skill for a kind ("herb", "ore") with racial bonuses, or nil
-- without the profession.
function ns.Skill(kind)
	if GetTime() - skillsAt > 5 then
		skillsAt = GetTime()
		wipe(skills)
		if GetProfessions and GetProfessionInfo then
			local list = { GetProfessions() }
			for i = 1, 2 do
				local index = list[i]
				if index then
					local ok, _, _, rank, _, _, _, line, modifier = pcall(GetProfessionInfo, index)
					if ok then
						for k, id in pairs(ns.SKILL_LINE) do
							if line == id then skills[k] = (tonumber(rank) or 0) + (tonumber(modifier) or 0) end
						end
					end
				end
			end
		end
	end
	return skills[kind]
end

function ns.ForgetSkills()
	skillsAt = -1
end

-- How a node stands for you: "none" (not your profession), "low" (skill
-- too low), "unknown" (it needs a skill we don't know), or the color of
-- the skill-up chance: "orange", "yellow", "green", "gray".
function ns.Status(kind, need)
	local have = ns.Skill(kind)
	if not have then return "none" end
	if not need then return "unknown" end
	if have < need then return "low" end
	if have < need + 25 then return "orange" end
	if have < need + 50 then return "yellow" end
	if have < need + 100 then return "green" end
	return "gray"
end

ns.STATUS_COLOR = {
	none = { 0.6, 0.6, 0.6 }, low = { 1, 0.15, 0.15 }, unknown = { 1, 1, 1 },
	orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 }, gray = { 0.5, 0.5, 0.5 },
}

function ns.CanGather(status)
	return status ~= "none" and status ~= "low"
end

-- "Kräver 175 (du har 160)" and the like, for tooltips.
function ns.NeedText(kind, need)
	local have = ns.Skill(kind)
	local what = kind == ns.HERB and "örtkunskap" or "gruvbrytning"
	if not have then return "Kräver " .. what .. (need and (" " .. need) or "") .. " (du har den inte)" end
	if not need then return string.format("Du har %s %d", what, have) end
	return string.format("Kräver %s %d (du har %d)", what, need, have)
end

-- Whether a kind's nodes are shown at all (pins and glow): your own
-- professions, or every kind with /lm alla.
function ns.ShowKind(kind)
	return db and (db.all or ns.Skill(kind) ~= nil)
end

---------------------------------------------------------------------------
-- Positions.

function ns.MyPosition()
	if not C_Map or not C_Map.GetBestMapForUnit then return end
	if IsInInstance and IsInInstance() then return end
	local map = C_Map.GetBestMapForUnit("player")
	if not map then return end
	local pos = C_Map.GetPlayerMapPosition(map, "player")
	if not pos then return end
	local x, y = pos:GetXY()
	if not x or (x == 0 and y == 0) then return end
	return map, x, y
end

local function World(map, x, y)
	if not C_Map.GetWorldPosFromMapPos or not CreateVector2D then return end
	local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
	if not ok or not continent or not pos then return end
	return continent, pos:GetXY()
end

-- A map's width and height in yards, or nil. Measured across the middle,
-- so it doesn't matter which way the world's axes point.
local mapSizes = {}
function ns.MapYards(map)
	local s = mapSizes[map]
	if s == nil then
		s = false
		local c1, ax, ay = World(map, 0, 0.5)
		local c2, bx, by = World(map, 1, 0.5)
		local c3, cx, cy = World(map, 0.5, 0)
		local c4, dx, dy = World(map, 0.5, 1)
		if c1 and c2 and c3 and c4 then
			local w = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
			local h = math.sqrt((cx - dx) ^ 2 + (cy - dy) ^ 2)
			if w > 0 and h > 0 then s = { w, h } end
		end
		mapSizes[map] = s
	end
	if s then return s[1], s[2] end
end

-- Yards between two points on one map, or nil when the map's size is unknown.
function ns.Yards(map, x1, y1, x2, y2)
	local w, h = ns.MapYards(map)
	if not w then return end
	return math.sqrt(((x1 - x2) * w) ^ 2 + ((y1 - y2) * h) ^ 2)
end

---------------------------------------------------------------------------
-- Saved nodes: db.nodes[map] = { { name, x, y, t, by, mine }, ... }

ns.version = 0  -- raised on every change, so the pins know to redraw

local function Clean(name)
	return (name:gsub("[|,;]", ""))
end

-- Saves a node; returns true when it is a new one.
function ns.AddNode(map, x, y, name, t, by, mine)
	if not db or not map or not x or not y or type(name) ~= "string" or name == "" then return false end
	name = Clean(name)
	db.nodes[map] = db.nodes[map] or {}
	local list = db.nodes[map]
	for _, n in ipairs(list) do
		if n.name == name then
			local d = ns.Yards(map, n.x, n.y, x, y)
			local same = d and d <= SAME_NODE_YARDS or (not d and math.abs(n.x - x) < 0.004 and math.abs(n.y - y) < 0.004)
			if same then
				if (t or 0) > (n.t or 0) then n.t = t end
				if mine then n.mine = true end
				return false
			end
		end
	end
	if #list >= MAX_PER_MAP then
		-- Full: drop the one seen longest ago.
		local oldest, at = nil, math.huge
		for i, n in ipairs(list) do
			if (n.t or 0) < at then oldest, at = i, n.t or 0 end
		end
		table.remove(list, oldest)
	end
	table.insert(list, { name = name, x = x, y = y, t = t or GetServerTime(), by = by, mine = mine or nil })
	ns.version = ns.version + 1
	return true
end

function ns.Nodes(map)
	return db and db.nodes[map]
end

function ns.Count()
	local total, maps = 0, 0
	for _, list in pairs(db.nodes) do
		maps = maps + 1
		total = total + #list
	end
	return total, maps
end

---------------------------------------------------------------------------
-- Sharing.

local send

local function Entry(map, n)
	return string.format("%d,%d,%d,%d,%s", map, math.floor(n.x * 10000), math.floor(n.y * 10000), n.t or 0, n.name)
end

-- Sends entries in as few messages as fit (255 bytes each).
local function SendEntries(entries, channel, target)
	if not send then return end
	local msg = "N"
	for _, e in ipairs(entries) do
		if #msg + 1 + #e > 250 then
			send(msg, channel, target)
			msg = "N"
		end
		msg = msg .. "|" .. e
	end
	if msg ~= "N" then send(msg, channel, target) end
end

local function Share(map, node)
	if not db.share or not ns.InOurGuild() then return end
	SendEntries({ Entry(map, node) }, "GUILD")
end

local answered = {}

local function Answer(sender, since)
	if not db.share then return end
	local key = Short(sender)
	if answered[key] and GetTime() - answered[key] < 300 then return end
	answered[key] = GetTime()
	local found = {}
	for map, list in pairs(db.nodes) do
		for _, n in ipairs(list) do
			if n.mine and (n.t or 0) > since then table.insert(found, { map = map, n = n }) end
		end
	end
	if #found == 0 then return end
	table.sort(found, function(a, b) return (a.n.t or 0) > (b.n.t or 0) end)
	local entries = {}
	for i = 1, math.min(#found, MAX_ANSWER) do
		entries[i] = Entry(found[i].map, found[i].n)
	end
	-- To the guild, not a whisper: on Forever the sender is a two-word name
	-- ("First Last") that whispers can't reach. Members who already have
	-- these finds just skip them.
	SendEntries(entries, "GUILD")
end

local function OnAddonMessage(prefix, msg, channel, sender)
	if prefix ~= ns.PREFIX or not db or not ns.InOurGuild() then return end
	msg, sender = Plain(msg), Plain(sender)
	if not msg or not sender then return end
	local who = Short(sender)
	-- Our own guild messages come back to us. UnitName gives only our first
	-- name; the sender is our full "First Last".
	local me = UnitName("player")
	if who == me or who:match("^(%S+)") == me then return end
	if channel ~= "GUILD" and channel ~= "WHISPER" then return end
	local kind = msg:sub(1, 1)
	if kind == "N" then
		local added = 0
		for e in msg:gmatch("|([^|]+)") do
			local map, x, y, t, name = e:match("^(%d+),(%d+),(%d+),(%d+),(.+)$")
			map, x, y, t = tonumber(map), tonumber(x), tonumber(y), tonumber(t)
			if map and x and y and name and ns.NodeInfo(name) then
				if ns.AddNode(map, x / 10000, y / 10000, name, t, who, false) then added = added + 1 end
			end
		end
		if added > 0 and ns.RefreshPins then ns.RefreshPins() end
	elseif kind == "S" and channel == "GUILD" then
		local since = tonumber(msg:match("^S;(%d+)"))
		if since then C_Timer.After(1 + math.random() * 4, function() Answer(sender, since) end) end
	end
end

---------------------------------------------------------------------------
-- Gathering: the Herb Gathering and Mining spells name the node they are
-- cast on (UNIT_SPELLCAST_SENT's target). Herb Gathering 2366 and Mining
-- 2575 give the names; the ranks share them.

local GATHER = { [2366] = ns.HERB, [2575] = ns.ORE }
local gatherNames

local function GatherKind(spellID)
	if GATHER[spellID] then return GATHER[spellID] end
	if not gatherNames then
		gatherNames = {}
		local get = C_Spell and C_Spell.GetSpellName
		for id, kind in pairs(GATHER) do
			local name = get and get(id)
			if name then gatherNames[name] = kind end
		end
	end
	local get = C_Spell and C_Spell.GetSpellName
	local name = get and spellID and get(spellID)
	return name and gatherNames[name]
end

local function OnCastSent(unit, target, _, spellID)
	if unit ~= "player" then return end
	local kind = GatherKind(Plain(spellID))
	target = Plain(target)
	if not kind or type(target) ~= "string" or target == "" then return end
	local known = ns.NodeInfo(target)
	if not known then
		-- A node we hadn't heard of: its kind from the spell, its skill later from the tooltip.
		db.learned[target] = db.learned[target] or { kind = kind }
	end
	local map, x, y = ns.MyPosition()
	if not map then return end
	if ns.AddNode(map, x, y, target, GetServerTime(), UnitName("player"), true) then
		local list = db.nodes[map]
		Share(map, list[#list])
		if ns.RefreshPins then ns.RefreshPins() end
	end
end

---------------------------------------------------------------------------
-- Tooltips: hovering a node in the world shows its tooltip, with a line
-- "Requires Herbalism (150)" (or Mining). Names we don't know are learned
-- from it, and a line of ours says how it stands for you.

local tipDone = false

local function OnTooltip(tooltip)
	if tooltip ~= GameTooltip or not db or tipDone then return end
	-- Units, items (the herb Peacebloom is also an item) and spells aren't nodes.
	if tooltip.GetUnit and Plain(tooltip:GetUnit()) then return end
	if tooltip.GetItem and Plain(tooltip:GetItem()) then return end
	if tooltip.GetSpell and Plain(tooltip:GetSpell()) then return end
	local first = _G.GameTooltipTextLeft1
	local name = first and Plain(first:GetText())
	if type(name) ~= "string" or name == "" then return end
	local kind, need = ns.NodeInfo(name)
	if not kind or not need then
		for i = 2, math.min(tooltip:NumLines(), 6) do
			local line = _G["GameTooltipTextLeft" .. i]
			local text = line and Plain(line:GetText())
			if type(text) == "string" then
				local k = text:find("Herbalism") and ns.HERB or text:find("Mining") and ns.ORE
				if k then
					kind = k
					need = tonumber(text:match("(%d+)")) or need
					db.learned[name] = { kind = kind, skill = need }
					break
				end
			end
		end
	end
	if not kind or not ns.ShowKind(kind) then return end
	local status = ns.Status(kind, need)
	local c = ns.STATUS_COLOR[status]
	tipDone = true
	tooltip:AddLine(ns.NeedText(kind, need), c[1], c[2], c[3])
	tooltip:Show()
end

---------------------------------------------------------------------------

local function Toggle(key, on, off)
	db[key] = not db[key]
	Print(db[key] and on or off)
	if ns.RefreshPins then ns.RefreshPins() end
end

local function Help()
	local total, maps = ns.Count()
	Print(string.format("känner till %d fyndplatser på %d kartor.", total, maps))
	Print("/lm glöd (lys upp noden framför dig), /lm räckvidd 15, /lm minimap, /lm karta, /lm alla (även andra yrkens noder), /lm dela, /lm test.")
end

SLASH_LANTMATERIET1 = "/lm"
SLASH_LANTMATERIET2 = "/lantmateriet"
SlashCmdList.LANTMATERIET = function(msg)
	if not db then return end
	local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
	if cmd == "glöd" or cmd == "glod" or cmd == "glow" then
		ns.SetGlow(not db.glow)
	elseif cmd == "räckvidd" or cmd == "rackvidd" or cmd == "range" then
		ns.SetRange(tonumber(arg))
	elseif cmd == "minimap" then
		Toggle("minimap", "fyndplatserna visas på minikartan.", "fyndplatserna visas inte på minikartan.")
	elseif cmd == "karta" then
		Toggle("map", "fyndplatserna visas på världskartan.", "fyndplatserna visas inte på världskartan.")
	elseif cmd == "alla" then
		Toggle("all", "alla noder visas, även för yrken du inte har.", "bara noder för dina egna yrken visas.")
	elseif cmd == "dela" then
		Toggle("share", "dina fynd delas med gillet.", "dina fynd delas inte längre med gillet.")
	elseif cmd == "test" then
		ns.Test()
	else
		Help()
	end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_ADDON", "UNIT_SPELLCAST_SENT",
	"SKILL_LINES_CHANGED", "CHAT_MSG_SKILL" }) do
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= addonName then return end
		LantmaterietDB = LantmaterietDB or {}
		db = LantmaterietDB
		ns.db = db
		db.nodes = db.nodes or {}
		db.learned = db.learned or {}
		for _, key in ipairs({ "glow", "minimap", "map", "share" }) do
			if db[key] == nil then db[key] = true end
		end
		db.range = db.range or 15
		return
	end
	if not db then return end
	if event == "PLAYER_LOGIN" then
		local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
		if register then register(ns.PREFIX) end
		send = Statskontoret.Sender(ns.PREFIX)
		if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipDataProcessor.AllTypes then
			TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip)
				pcall(OnTooltip, tooltip)
			end)
		end
		-- World objects may not go through the processor on every client.
		GameTooltip:HookScript("OnShow", function(tooltip) pcall(OnTooltip, tooltip) end)
		GameTooltip:HookScript("OnTooltipCleared", function() tipDone = false end)
		GameTooltip:HookScript("OnHide", function() tipDone = false end)
		if ns.StartGlow then ns.StartGlow() end
		-- Catch up on what the guild found while you were away, then keep
		-- note of how far we are complete (we hear new finds while online).
		C_Timer.After(20, function()
			if not ns.InOurGuild() then return end
			Statskontoret.SendAddon(ns.PREFIX, "S;" .. (db.syncedUntil or 0), "GUILD")
			C_Timer.NewTicker(60, function()
				if ns.InOurGuild() then db.syncedUntil = GetServerTime() - 120 end
			end)
		end)
	elseif event == "CHAT_MSG_ADDON" then
		OnAddonMessage(...)
	elseif event == "UNIT_SPELLCAST_SENT" then
		OnCastSent(...)
	else
		ns.ForgetSkills()
	end
end)
