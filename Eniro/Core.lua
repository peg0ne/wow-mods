-- Eniro: where the guild is, for THÖNDERSTÖRM on WoW Forever.
-- The member list (level, class, zone) comes from the guild roster and
-- needs nothing from anyone. Position sharing is opt-in per character
-- (/eniro dela, or the box in the window): while it is on, your map
-- position goes out on the guild channel every 10 s when you move (every
-- 60 s when you stand still), never from inside an instance. Positions
-- not refreshed for 90 s are forgotten.
--
-- Guild channel:
--   F                          everyone sharing: send your position now
--   P;version;mapID;x;y        my position, x and y in 0-10000 on that map
--   X                          I stopped sharing (or entered an instance)

local _, ns = ...

ns.GUILD = "THÖNDERSTÖRM"
ns.VERSION = "0.1"
ns.PREFIX = "ENIRO"
local MOVE_EVERY, IDLE_EVERY, EXPIRE = 10, 60, 90

local char
ns.members = {}     -- name -> { name, level, class, classFile, zone, online }
ns.positions = {}   -- name -> { map, x, y, t }
local lastSent, lastAnswer, lastAsk, warnedVersion = nil, 0, 0, false

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff3399ffEniro:|r " .. text)
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
ns.RequestRoster = RequestRoster

-- This character's full name as the guild sees it (two-word Forever names;
-- see Arbetsförmedlingen). nil until the roster has loaded.
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

local function Send(msg)
	if not IsInGuild() then return end
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(ns.PREFIX, msg, "GUILD")
	elseif SendAddonMessage then
		SendAddonMessage(ns.PREFIX, msg, "GUILD")
	end
end

local function Changed()
	if ns.RefreshWindow then ns.RefreshWindow() end
	if ns.RefreshPins then ns.RefreshPins() end
end
ns.Changed = Changed

---------------------------------------------------------------------------
-- Positions.

-- This character's map, x, y (0-1), or nil when unknown (in an instance).
function ns.MyPosition()
	if not C_Map or not C_Map.GetBestMapForUnit then return end
	local map = C_Map.GetBestMapForUnit("player")
	if not map then return end
	local pos = C_Map.GetPlayerMapPosition(map, "player")
	if not pos then return end
	local x, y = pos:GetXY()
	if not x or (x == 0 and y == 0) then return end
	return map, x, y
end

-- Continent and world coordinates (yards) of a map position, or nil.
local function World(map, x, y)
	if not C_Map.GetWorldPosFromMapPos or not CreateVector2D then return end
	local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
	if not ok or not continent or not pos then return end
	return continent, pos:GetXY()
end

-- Distance in yards from you to a shared position, or nil (other continent,
-- or no position).
function ns.Distance(p)
	local map, x, y = ns.MyPosition()
	if not map or not p then return end
	local c1, x1, y1 = World(map, x, y)
	local c2, x2, y2 = World(p.map, p.x, p.y)
	if not c1 or c1 ~= c2 then return end
	return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

local function SendPosition(force)
	if not char or not char.share or not ns.InOurGuild() then return end
	local map, x, y = ns.MyPosition()
	if not map then
		if lastSent and lastSent.map then
			Send("X")
			lastSent = { t = GetTime() }
		end
		return
	end
	local now = GetTime()
	local moved = not lastSent or lastSent.map ~= map
		or math.abs(lastSent.x - x) > 0.002 or math.abs(lastSent.y - y) > 0.002
	local age = lastSent and (now - lastSent.t) or 999
	if force or (moved and age >= MOVE_EVERY) or age >= IDLE_EVERY then
		Send(string.format("P;%s;%d;%d;%d", ns.VERSION, map, math.floor(x * 10000), math.floor(y * 10000)))
		lastSent = { map = map, x = x, y = y, t = now }
	end
end

function ns.SetSharing(on)
	char.share = on and true or false
	if on then
		Print("du delar nu din position med gillet (bara medlemmar med Eniro ser den).")
		lastSent = nil
		SendPosition(true)
	else
		Send("X")
		lastSent = nil
		Print("du delar inte längre din position.")
	end
	Changed()
end

function ns.Sharing()
	return char and char.share
end

function ns.Ask()
	if GetTime() - lastAsk < 10 then return end
	lastAsk = GetTime()
	Send("F")
	RequestRoster()
end

---------------------------------------------------------------------------
-- Messages and roster.

local function VersionNumber(v)
	local major, minor = tostring(v or ""):match("^(%d+)%.(%d+)")
	return major and (tonumber(major) * 1000 + tonumber(minor)) or 0
end

local function OnAddonMessage(prefix, msg, channel, sender)
	if prefix ~= ns.PREFIX or channel ~= "GUILD" or not char or not ns.InOurGuild() then return end
	sender = ns.Short(sender)
	if not sender or ns.IsMe(sender) then return end
	local parts = { strsplit(";", msg) }
	if parts[1] == "P" then
		if not warnedVersion and VersionNumber(parts[2]) > VersionNumber(ns.VERSION) then
			warnedVersion = true
			Print("det finns en nyare Eniro (" .. parts[2] .. "); be gildeledaren om den.")
		end
		local map, x, y = tonumber(parts[3]), tonumber(parts[4]), tonumber(parts[5])
		if map and x and y then
			ns.positions[sender] = { map = map, x = x / 10000, y = y / 10000, t = GetTime() }
			Changed()
		end
	elseif parts[1] == "X" then
		ns.positions[sender] = nil
		Changed()
	elseif parts[1] == "F" then
		if char.share and GetTime() - lastAnswer > 5 then
			lastAnswer = GetTime()
			C_Timer.After(math.random() * 3, function() SendPosition(true) end)
		end
	end
end

local function OnRoster()
	local n = GetNumGuildMembers()
	if n == 0 then return end
	local members = {}
	for i = 1, n do
		local name, _, _, level, class, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
		name = ns.Short(name)
		if name and online then
			members[name] = { name = name, level = level, class = class, classFile = classFile, zone = zone, online = true }
		end
	end
	ns.members = members
	for name in pairs(ns.positions) do
		if not members[name] then ns.positions[name] = nil end
	end
	Changed()
end

-- Online members other than you, as rows for the window:
-- { name, level, class, classFile, zone, sameZone, pos, distance }.
function ns.Rows(filter)
	local myZone = GetRealZoneText and GetRealZoneText() or GetZoneText()
	local myLevel = UnitLevel("player")
	local list = {}
	for name, m in pairs(ns.members) do
		if not ns.IsMe(name) then
			local row = {
				name = name, level = m.level, class = m.class, classFile = m.classFile, zone = m.zone,
				sameZone = m.zone == myZone, pos = ns.positions[name],
			}
			row.distance = ns.Distance(row.pos)
			local keep = filter == "zone" and row.sameZone
				or filter == "level" and math.abs((m.level or 0) - myLevel) <= 5
				or filter ~= "zone" and filter ~= "level"
			if keep then table.insert(list, row) end
		end
	end
	table.sort(list, function(a, b)
		if a.sameZone ~= b.sameZone then return a.sameZone end
		if (a.distance ~= nil) ~= (b.distance ~= nil) then return a.distance ~= nil end
		if a.distance and b.distance and a.distance ~= b.distance then return a.distance < b.distance end
		local da, db = math.abs((a.level or 0) - myLevel), math.abs((b.level or 0) - myLevel)
		if da ~= db then return da < db end
		return a.name < b.name
	end)
	return list
end

function ns.Invite(name)
	if C_PartyInfo and C_PartyInfo.InviteUnit then
		C_PartyInfo.InviteUnit(name)
	elseif InviteUnit then
		InviteUnit(name)
	end
end

---------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE",
	"ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "Eniro" then
			EniroCharDB = EniroCharDB or {}
			char = EniroCharDB
			if char.share == nil then char.share = false end
			char.filter = char.filter or "all"
			ns.char = char
		end
	elseif not char then
		return
	elseif event == "PLAYER_LOGIN" then
		local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
		if register then register(ns.PREFIX) end
		RequestRoster()
		C_Timer.After(15, function() ns.Ask() end)
		-- Send when due, forget stale positions, and keep the roster's zones fresh.
		local ticks = 0
		C_Timer.NewTicker(2, function()
			SendPosition(false)
			local now, changed = GetTime(), false
			for name, p in pairs(ns.positions) do
				if now - p.t > EXPIRE then
					ns.positions[name] = nil
					changed = true
				end
			end
			ticks = ticks + 1
			if ticks % 15 == 0 then RequestRoster() end
			if changed then Changed() end
		end)
	elseif event == "CHAT_MSG_ADDON" then
		OnAddonMessage(...)
	elseif event == "GUILD_ROSTER_UPDATE" then
		OnRoster()
	else
		-- Zoning: send the new position (or X for an instance) right away.
		C_Timer.After(2, function() SendPosition(true) end)
		Changed()
	end
end)

SLASH_ENIRO1 = "/eniro"
SLASH_ENIRO2 = "/hitta"
SlashCmdList.ENIRO = function(msg)
	if not ns.InOurGuild() then
		Print("den här karaktären är inte med i " .. ns.GUILD .. ".")
		return
	end
	local cmd = strtrim(msg or ""):lower()
	if cmd == "dela" then
		ns.SetSharing(not char.share)
	elseif cmd == "" then
		ns.ToggleWindow()
	else
		Print("/eniro öppnar fönstret, /eniro dela slår på eller av delning av din position.")
	end
end
