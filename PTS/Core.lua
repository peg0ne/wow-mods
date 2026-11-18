-- PTS (Post- och telestyrelsen): the chat channels you are in.
--
-- Leaving General or Trade through the game doesn't last: every zone change
-- (and every login) joins you again. /pts lists every channel you are in,
-- and the zone's channels you aren't, each with a box. Unticking one leaves
-- it and puts it on PTSDB.blocked (by its name without the zone, "Trade"
-- for "Trade - City"), and whenever the game joins you to a blocked channel
-- PTS leaves it again. Ticking it joins it again and takes it off the list.
--
-- /pts korta (off by default) shortens the channel names in chat: [Guild]
-- to [G], [Party] to [P], [2. Trade - City] to [2. T]. The group channels
-- use the game's CHAT_*_GET strings (put back when turned off); numbered
-- channels go through a chat event filter that only changes the channel's
-- name, never the message.

local ADDON = ...
local db
local window

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffPTS:|r " .. text)
end

local function Plain(v)
	if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
	return v
end

-- "Trade - City" -> "Trade"; custom channels keep their name.
local function Base(name)
	return name and (name:match("^(.-) %- ") or name) or nil
end

-- Channels you are in: { { id, name, base } }, by number. GetChannelList
-- gives id, name, disabled on retail clients and id, name on older ones.
local function Joined()
	local t = { GetChannelList() }
	local out, i = {}, 1
	while t[i] ~= nil do
		local id, name = Plain(t[i]), Plain(t[i + 1])
		if type(id) == "number" and type(name) == "string" then
			table.insert(out, { id = id, name = name, base = Base(name) })
		end
		i = i + (type(t[i + 2]) == "boolean" and 3 or 2)
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

-- The zone's channels (General, Trade, LocalDefense ...), joined or not.
local function ServerChannels()
	local out = {}
	if EnumerateServerChannels then
		local ok, list = pcall(function() return { EnumerateServerChannels() } end)
		if ok then
			for _, name in ipairs(list) do
				name = Plain(name)
				if type(name) == "string" then table.insert(out, name) end
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Staying out.

local told = {}   -- blocked channels already named in chat this session

local function Sweep()
	if not db then return end
	for _, ch in ipairs(Joined()) do
		if ch.base and db.blocked[ch.base] then
			pcall(LeaveChannelByName, ch.name)
			if not told[ch.base] then
				told[ch.base] = true
				Print("lämnade " .. ch.base .. " igen (/pts för kanalerna).")
			end
		end
	end
end

local sweepPending = false
local function SweepSoon()
	if sweepPending then return end
	sweepPending = true
	-- The game joins several channels in a row; leave once it is done.
	C_Timer.After(1, function()
		sweepPending = false
		Sweep()
		if window and window:IsShown() then window.Refresh() end
	end)
end

local function AddToChat(name)
	local frame = DEFAULT_CHAT_FRAME
	if ChatFrame_AddChannel then
		pcall(ChatFrame_AddChannel, frame, name)
	elseif ChatFrameUtil and ChatFrameUtil.AddChannel then
		pcall(ChatFrameUtil.AddChannel, frame, name)
	end
end

local function SetChannel(base, fullName, on)
	if on then
		db.blocked[base] = nil
		told[base] = nil
		pcall(JoinChannelByName, base, nil, DEFAULT_CHAT_FRAME:GetID())
		AddToChat(base)
		Print("du är med i " .. base .. " igen.")
	else
		db.blocked[base] = true
		pcall(LeaveChannelByName, fullName or base)
		told[base] = true
		Print("lämnade " .. base .. ". PTS lämnar den igen varje gång spelet går med i den.")
	end
	SweepSoon()
end

---------------------------------------------------------------------------
-- Short names.

local SHORT_GROUP = {
	GUILD = "G", OFFICER = "O", PARTY = "P", PARTY_LEADER = "PL", PARTY_GUIDE = "PG",
	RAID = "R", RAID_LEADER = "RL", RAID_WARNING = "RW",
	INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL",
}
local SHORT_CHANNEL = {
	General = "Gen", Trade = "T", LocalDefense = "LD", WorldDefense = "WD",
	LookingForGroup = "LFG", GuildRecruitment = "GR", Services = "S", NewcomerChat = "N",
}
local saved = {}  -- CHAT_*_GET -> the game's own text, while shortened

local function ShortChannel(base)
	if SHORT_CHANNEL[base] then return SHORT_CHANNEL[base] end
	return #base > 8 and base:sub(1, 8) or base
end

-- CHAT_MSG_CHANNEL: arg4 is the shown name ("2. Trade - City"), arg8 the
-- number, arg9 the name. Only arg4 changes.
local function ChannelFilter(_, _, ...)
	if not (db and db.short) then return false end
	local n = select("#", ...)
	local args = { ... }
	local shown, number, name = Plain(args[4]), Plain(args[8]), Plain(args[9])
	if type(shown) ~= "string" or shown == "" then return false end
	local base = Base(type(name) == "string" and name ~= "" and name or shown:gsub("^%d+%.%s*", ""))
	if not base then return false end
	args[4] = (type(number) == "number" and number > 0) and (number .. ". " .. ShortChannel(base)) or ShortChannel(base)
	return false, unpack(args, 1, n)
end

local filterAdded = false
local function ApplyShort()
	if db.short then
		for key, short in pairs(SHORT_GROUP) do
			local name = "CHAT_" .. key .. "_GET"
			local text = _G[name]
			if type(text) == "string" and saved[name] == nil then
				saved[name] = text
				_G[name] = (text:gsub("%[.-%]", "[" .. short .. "]", 1))
			end
		end
		if not filterAdded then
			local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
			if add then
				add("CHAT_MSG_CHANNEL", ChannelFilter)
				filterAdded = true
			end
		end
	else
		for name, text in pairs(saved) do _G[name] = text end
		wipe(saved)
		-- The filter stays and does nothing while off.
	end
end

---------------------------------------------------------------------------
-- The window.

local ROWS, ROW_H = 14, 22

local function Build()
	local f, portrait = Statskontoret.Window("PTSFrame", "Post- och telestyrelsen", 360, 470)
	local left, dy = portrait and 66 or 24, portrait and 0 or -12
	window = f

	local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	head:SetPoint("TOPLEFT", left, -34 + dy)
	head:SetText("Chattkanaler")
	local help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", 24, -66 + dy)
	help:SetPoint("RIGHT", -24, 0)
	help:SetJustifyH("LEFT")
	help:SetText("Bocka ur en kanal för att lämna den. PTS lämnar den igen varje gång spelet går med i den, som när du byter zon.")
	Statskontoret.Rule(f, 20, 20, -96 + dy)

	local rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, f)
		row:SetSize(300, ROW_H)
		row:SetPoint("TOPLEFT", 24, -102 + dy - (i - 1) * ROW_H)
		Statskontoret.Stripe(row, i)
		row.box = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.box:SetSize(22, 22)
		row.box:SetPoint("LEFT", 0, 0)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.text:SetPoint("LEFT", row.box, "RIGHT", 4, 0)
		row.box:SetScript("OnClick", function(self)
			if row.base then SetChannel(row.base, row.full, self:GetChecked() and true or false) end
		end)
		rows[i] = row
	end

	Statskontoret.Rule(f, 20, 20, -108 + dy - ROWS * ROW_H)
	local short = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	short:SetSize(22, 22)
	short:SetPoint("TOPLEFT", 24, -114 + dy - ROWS * ROW_H)
	local shortText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	shortText:SetPoint("LEFT", short, "RIGHT", 4, 0)
	shortText:SetText("Korta kanalnamn: [G], [P], [2. T]")
	short:SetScript("OnClick", function(self)
		db.short = self:GetChecked() and true or false
		ApplyShort()
	end)

	function f.Refresh()
		local list, seen = {}, {}
		for _, ch in ipairs(Joined()) do
			if ch.base and not seen[ch.base] then
				seen[ch.base] = true
				table.insert(list, { base = ch.base, full = ch.name, label = ch.id .. ". " .. ch.name, on = true })
			end
		end
		local out = {}
		for _, name in ipairs(ServerChannels()) do
			local base = Base(name)
			if base and not seen[base] then
				seen[base] = true
				table.insert(out, base)
			end
		end
		for base in pairs(db.blocked) do
			if not seen[base] then
				seen[base] = true
				table.insert(out, base)
			end
		end
		table.sort(out)
		for _, base in ipairs(out) do
			local why = db.blocked[base] and "  |cff808080(håller dig utanför)|r" or "  |cff808080(inte med)|r"
			table.insert(list, { base = base, label = base .. why, on = false })
		end
		for i, row in ipairs(rows) do
			local e = list[i]
			row.base, row.full = e and e.base, e and e.full
			if e then
				row.text:SetText(e.label)
				row.box:SetChecked(e.on)
				row:Show()
			else
				row:Hide()
			end
		end
		short:SetChecked(db.short)
	end
	f:SetScript("OnShow", function(self) self.Refresh() end)
end

local function Toggle()
	if not window then Build() end
	if window:IsShown() then window:Hide() else window:Show() end
end

---------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
	"CHANNEL_UI_UPDATE", "CHAT_MSG_CHANNEL_NOTICE" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		PTSDB = PTSDB or {}
		db = PTSDB
		db.blocked = db.blocked or {}
		if db.short == nil then db.short = false end
		if db.short then ApplyShort() end
		return
	end
	if not db then return end
	SweepSoon()
end)

SLASH_PTS1 = "/pts"
SLASH_PTS2 = "/kanaler"
SlashCmdList.PTS = function(msg)
	if not db then return end
	msg = strtrim(msg or ""):lower()
	if msg == "korta" or msg == "kort" then
		db.short = not db.short
		ApplyShort()
		if window and window:IsShown() then window.Refresh() end
		Print(db.short and "korta kanalnamn i chatten: [G], [P], [2. T]." or "kanalnamnen är som spelets igen.")
	elseif msg == "" then
		Toggle()
	else
		Print("/pts öppnar kanalerna (bocka ur för att lämna en och hålla dig utanför), /pts korta slår på eller av korta kanalnamn i chatten.")
	end
end
