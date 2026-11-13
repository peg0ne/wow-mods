-- Postnord: a chat notice when the guild's addon pack (this repo) has a newer
-- release, the way Skatteverket tells you about its own new versions.
--
-- The pack's version is the release tag: the release workflow writes it into
-- Postnord.toc (## Version: 1.6.1 for the tag v1.6.1). A copy run straight
-- from the repo says "dev"; it sends nothing and never nags, so a version
-- that isn't released yet can't tell the guild to update.
--
-- Messages on the GUILD channel, prefix POSTNORD:
--   V;<version>   at login, and as an answer to someone on an older version
-- When someone sends an older version, one member with a newer one answers
-- in the guild channel after a random few seconds; the others hear that
-- answer and stay quiet.

local ADDON = ...
local PREFIX = "POSTNORD"
local GUILD = "THÖNDERSTÖRM"

local db
local mine          -- this pack's version, or nil for "dev"
local told = nil    -- the version the notice was shown for this session
local answerAt      -- when we answer someone on an older version
local lastAnswer = 0

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Postnord:|r " .. text)
end

-- "1.6.1" as a number that compares right: 1006001.
local function Number(v)
	if type(v) ~= "string" then return 0 end
	local a, b, c = v:match("^v?(%d+)%.?(%d*)%.?(%d*)")
	if not a then return 0 end
	return tonumber(a) * 1000000 + (tonumber(b) or 0) * 1000 + (tonumber(c) or 0)
end

local function InOurGuild()
	return IsInGuild() and GetGuildInfo("player") == GUILD
end

local function Send(msg)
	if not InOurGuild() then return end
	Statskontoret.SendAddon(PREFIX, msg, "GUILD")
end

local function Announce()
	if mine then Send("V;" .. mine) end
end

local function Notice()
	-- Once per version: a release that comes out later in the session is
	-- announced too.
	if not mine or Number(db.newest) <= Number(mine) or Number(db.newest) <= Number(told) then return end
	told = db.newest
	Print(format("|cffff4040ny version av gildets addons: %s|r (du har %s). Uppdatera guild-addons i WowUp och skriv /reload.",
		db.newest, mine))
end

local function OnMessage(prefix, msg, channel)
	if prefix ~= PREFIX or channel ~= "GUILD" or not mine then return end
	local kind, version = strsplit(";", msg or "")
	if kind ~= "V" or Number(version) == 0 then return end
	local theirs, ours = Number(version), Number(mine)
	if theirs > ours then
		if theirs > Number(db.newest) then db.newest = version end
		-- A moment later, so it isn't lost in the login messages.
		C_Timer.After(3, Notice)
	elseif theirs < ours then
		-- Answer once in a while, after a random wait, unless someone else
		-- with this version or newer answers first.
		if not answerAt and GetTime() - lastAnswer > 60 then
			answerAt = GetTime() + 2 + math.random() * 8
			C_Timer.After(answerAt - GetTime(), function()
				if answerAt then
					answerAt, lastAnswer = nil, GetTime()
					Announce()
				end
			end)
		end
	elseif answerAt then
		-- Someone else told them already.
		answerAt = nil
	end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_ADDON" }) do
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= ADDON then return end
		PostnordDB = PostnordDB or {}
		db = PostnordDB
		local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
		local v = meta and meta(ADDON, "Version")
		mine = Number(v) > 0 and v or nil
		-- Updated since the newest seen: forget it.
		if mine and Number(db.newest) <= Number(mine) then db.newest = nil end
	elseif not db then
		return
	elseif event == "PLAYER_LOGIN" then
		local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
		if register then register(PREFIX) end
		-- Seen on an earlier session and still not updated.
		C_Timer.After(20, Notice)
		C_Timer.After(15, Announce)
	elseif event == "CHAT_MSG_ADDON" then
		OnMessage(...)
	end
end)

SLASH_POSTNORD1 = "/postnord"
SlashCmdList.POSTNORD = function()
	local newest = db and db.newest
	if not mine then
		Print("den här kopian körs från repot (dev); den skickar inget och varnar inte.")
	elseif newest and Number(newest) > Number(mine) then
		Print(format("du har %s; %s finns. Uppdatera guild-addons i WowUp och skriv /reload.", mine, newest))
	else
		Print(format("du har %s, den nyaste någon i gildet har visat.", mine))
	end
end
