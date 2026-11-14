-- Fröken Ur: the speaking clock. Writes the time left on every cooldown
-- (action buttons, items, auras) on top of it: seconds with one decimal under
-- a minute ("2.9", cut off rather than rounded, so 2.93 is 2.9), then
-- "1:30" up to an hour and "2h" above that.
--
-- Every cooldown swipe in the game is a Cooldown widget, and they share one
-- method table, so hooking its setters after Blizzard's calls finds them all.
-- The hooks only read the cooldown (GetCooldownTimes); the text is our own
-- FontString, kept in our own table, never a field on Blizzard's frame.
-- The global cooldown (1.5 s or less) is left without a number.
-- /ur switches it on and off.

local ADDON = ...

local MIN_DURATION = 1.5  -- the global cooldown and shorter get no number
local MIN_WIDTH = 16      -- tiny swipes (nameplate auras) are too small for text

local db
local texts = setmetatable({}, { __mode = "k" })   -- Cooldown -> FontString
local active = {}                                   -- Cooldown -> end time (GetTime)
local hidNumbers = setmetatable({}, { __mode = "k" }) -- Cooldowns whose own countdown we hid

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffFröken Ur:|r " .. text)
end

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

local function Format(left)
	if left < 60 then
		return string.format("%.1f", math.floor(left * 10) / 10), left < 3
	elseif left < 3600 then
		local s = math.floor(left)
		return string.format("%d:%02d", math.floor(s / 60), s % 60), false
	end
	return string.format("%dh", math.floor(left / 3600)), false
end

local function Stop(cd)
	active[cd] = nil
	local fs = texts[cd]
	if fs then fs:Hide() end
	if hidNumbers[cd] then
		hidNumbers[cd] = nil
		if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
	end
end

local function Text(cd)
	local fs = texts[cd]
	if not fs then
		fs = cd:CreateFontString(nil, "OVERLAY")
		fs:SetPoint("CENTER", 0, 0)
		texts[cd] = fs
	end
	local size = math.max(8, math.floor((cd:GetWidth() or 36) * 0.36 + 0.5))
	fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
	fs.shown = nil
	return fs
end

-- After any setter: read what the cooldown now shows and follow it.
local function Refresh(cd)
	if not db or not db.on then return end
	if cd.IsForbidden and cd:IsForbidden() then return end
	local ok, start, duration = pcall(cd.GetCooldownTimes, cd)
	if not ok or Secret(start) or Secret(duration) or type(start) ~= "number" or type(duration) ~= "number" then
		-- Hidden from addons: leave the game's own countdown numbers to it.
		Stop(cd)
		return
	end
	start, duration = start / 1000, duration / 1000
	local width = cd:GetWidth()
	if duration <= MIN_DURATION or start <= 0 or Secret(width) or (width or 0) < MIN_WIDTH then
		Stop(cd)
		return
	end
	local finish = start + duration
	if finish <= GetTime() then Stop(cd) return end
	active[cd] = finish
	Text(cd):Show()
	if cd.SetHideCountdownNumbers and not hidNumbers[cd] then
		hidNumbers[cd] = true
		cd:SetHideCountdownNumbers(true)
	end
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
	local now = GetTime()
	for cd, finish in pairs(active) do
		local left = finish - now
		if left <= 0 then
			Stop(cd)
		elseif cd:IsVisible() then
			local fs = texts[cd]
			local text, soon = Format(left)
			if fs.shown ~= text then
				fs.shown = text
				fs:SetText(text)
				if soon then fs:SetTextColor(1, 0.3, 0.3) else fs:SetTextColor(1, 1, 1) end
			end
		end
	end
end)

local function StopAll()
	for cd in pairs(active) do Stop(cd) end
end

local function Hook()
	local probe = CreateFrame("Cooldown", nil, UIParent)
	local methods = getmetatable(probe).__index
	probe:Hide()
	for _, name in ipairs({ "SetCooldown", "SetCooldownDuration", "SetCooldownUNIX", "SetCooldownFromDurationObject", "Clear" }) do
		if type(methods[name]) == "function" then hooksecurefunc(methods, name, Refresh) end
	end
end

SLASH_FROKENUR1 = "/ur"
SLASH_FROKENUR2 = "/frokenur"
SlashCmdList.FROKENUR = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "" or msg == "på" or msg == "pa" or msg == "av" then
		if msg == "" then db.on = not db.on else db.on = (msg ~= "av") end
		if not db.on then StopAll() end
		Print(db.on and "tiden visas på nedkylningarna (från nästa som startar)." or "tiden på nedkylningarna är avstängd.")
	else
		Print("/ur slår på eller av tiden på nedkylningarna (/ur på, /ur av).")
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, name)
	if name ~= ADDON then return end
	events:UnregisterEvent("ADDON_LOADED")
	if type(FrokenUrDB) ~= "table" then FrokenUrDB = {} end
	db = FrokenUrDB
	if db.on == nil then db.on = true end
	Hook()
end)
