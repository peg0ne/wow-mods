-- Gildepanel: a panel for THÖNDERSTÖRM, with a minimap button that is off by default.
-- It only reads what Skatteverket (SkatteverketDB, SkatteverketCharDB) and
-- Swedbank (SwedbankCharDB) keep in their saved data, which those addons
-- update while you play. It never writes to them and sends no messages;
-- the buttons run the addons' own slash commands.
--
-- The Addons window (/gpanel addons) opens the windows of the repo's other
-- addons and turns their automatic settings on and off. It also sets how far
-- out the camera zooms (/gpanel kamera).
--
-- The panel shows as a compact bar and opens to the full panel while the
-- mouse is over it (/gpanel kompakt turns that off). Your own tax is read
-- twice a second; the guild figures are worked out again only when the
-- roster changes, after a payment, or every 30 seconds.
--
-- 2.0 removed the panel because Skatteverket 0.22 shows the same figures in
-- /skatt; 2.2 brought it back, since the compact bar that drops open is
-- quicker to glance at than a full window.
--
-- 2.5 celebrates a tax payment on screen and in sound (/gpanel firande).
--
-- 2.7 turns your minimap tracking (Find Herbs, Find Minerals) back on after
-- login, since the game drops it (/gpanel spårning).
--
-- 2.8 lists Revisorsinspektionen's settings in the Addons window, which is
-- now wider, with its settings in two columns.
--
-- 2.3 follows Skatteverket 0.28: standing is counted in play time on the
-- whole account (8 h unpaid neutral, 12 h negative), and the best character
-- on the account counts for all of them.

local ADDON = ...
local GUILD = "THÖNDERSTÖRM"
-- Play time since the debt (Skatteverket 0.28 and later).
local GOOD, NEGATIVE = 8 * 3600, 12 * 3600
-- Real time since the debt, for members still on older Skatteverkets.
local OLD_GOOD, OLD_NEGATIVE = 48 * 3600, 7 * 86400
local WEEK = 7 * 86400
local WARN_BEFORE = 3600
local W, PAD = 300, 14
local COMPACT_H = 52
local MOTD_Y, SWEDBANK_H = -370, 114
local TICK, GUILD_EVERY, COLLAPSE_DELAY = 0.5, 30, 0.6
local floor, format = math.floor, string.format

local db
local frame, mini
local bankOpen, expanded = false, true
local guildDirty = true

local COLORS = {
	good = { 0.25, 0.85, 0.3 },
	neutral = { 1, 0.82, 0 },
	negative = { 0.9, 0.25, 0.25 },
	none = { 0.5, 0.5, 0.5 },
}
local LABELS = {
	good = "|cff40ff40God|r",
	neutral = "|cffffd100Neutral|r",
	negative = "|cffff4040Negativ|r",
}

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Gildepanel:|r " .. text)
end

local function Money(copper)
	copper = floor(math.max(copper or 0, 0))
	local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
	local G, S, C = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"
	if g > 0 then return format("%d%s %d%s %d%s", g, G, s, S, c, C) end
	if s > 0 then return format("%d%s %d%s", s, S, c, C) end
	return format("%d%s", c, C)
end

local function Duration(sec)
	sec = math.max(0, floor(sec))
	if sec >= 86400 then return format("%d d %d h", floor(sec / 86400), floor(sec / 3600) % 24) end
	if sec >= 3600 then return format("%d h %d min", floor(sec / 3600), floor(sec / 60) % 60) end
	return format("%d min", floor(sec / 60))
end

local function Day(t)
	return (t and t > 0) and date("%d/%m", t) or "aldrig"
end

local function Short(name)
	if not name then return nil end
	if Ambiguate then return Ambiguate(name, "none") end
	return (name:gsub("%-.*", ""))
end

local function InGuild()
	return GetGuildInfo("player") == GUILD
end

local function SetVisible(region, on)
	if on then region:Show() else region:Hide() end
end

-- A debt's age in play time as a standing, the way Skatteverket 0.28 counts.
local function PlayStanding(age)
	if not age or age <= GOOD then return "good" end
	if age < NEGATIVE then return "neutral" end
	return "negative"
end

-- Another member's standing. From 0.28 they report the account's debt age in
-- play time (frozen while offline); older clients only the date of the debt.
local function Standing(m)
	if not m then return "good" end
	if m.debtAge ~= nil then return PlayStanding(m.debtAge) end
	if not m.debtSince then return "good" end
	local age = time() - m.debtSince
	if age <= OLD_GOOD then return "good" end
	if age < OLD_NEGATIVE then return "neutral" end
	return "negative"
end

-- Your account's standing, worked out from Skatteverket's saved data the way
-- it does: every character on the account in SkatteverketDB.chars, the
-- youngest debt among those that have paid tax (all of them if none has),
-- aged by the account's play clock. Returns the debt's age in play time (0
-- for none), or nil before Skatteverket 0.28.
local function AccountDebt()
	local sv = SkatteverketDB
	if not sv or not sv.clock or type(sv.chars) ~= "table" then return nil end
	local now = sv.clock
	local function Best(paidOnly)
		local debt
		for _, c in pairs(sv.chars) do
			if type(c) == "table" and (not paidOnly or (c.paid or 0) > 0) then
				local age = (c.owed or 0) >= 1 and c.debtAt and math.max(0, now - c.debtAt) or 0
				if not debt or age < debt then debt = age end
			end
		end
		return debt
	end
	return Best(true) or Best(false) or 0
end

-- Names in the guild now, or nil before the roster loads.
local function Roster()
	local n = GetNumGuildMembers()
	if not n or n == 0 then return nil end
	local names = {}
	for i = 1, n do
		local name = Short(GetGuildRosterInfo(i))
		if name then names[name] = true end
	end
	return names
end

-- This character's full guild name (Forever names have two words), by GUID.
local myName
local function Me()
	if myName then return myName end
	local guid, first = UnitGUID("player"), UnitName("player")
	local match, count = nil, 0
	for i = 1, GetNumGuildMembers() do
		local info = { GetGuildRosterInfo(i) }
		local name = Short(info[1])
		if name and guid and info[17] == guid then
			myName = name
			return name
		end
		if name and name:match("^(%S+)") == first then match, count = name, count + 1 end
	end
	if count == 1 then myName = match end
	return myName
end

-- Skatteverkets favoriter: longest unbroken runs in good standing among
-- members who have paid, as Skatteverket ranks them.
local function Favorites(members, roster)
	local list = {}
	for name, m in pairs(members or {}) do
		if m.hasPaid and m.goodSince and Standing(m) == "good" and (not roster or roster[name]) then
			table.insert(list, name)
		end
	end
	-- The longest run first: in play time where reported (0.28), else days.
	-- Worked out once before sorting: a time() read inside the comparator can
	-- tick over mid-sort and make the order inconsistent.
	local now, run = time(), {}
	for _, name in ipairs(list) do
		local m = members[name]
		run[name] = m.goodAge or (now - m.goodSince)
	end
	table.sort(list, function(a, b)
		local ra, rb = run[a], run[b]
		if ra ~= rb then return ra > rb end
		local ga, gb = members[a].goodSince, members[b].goodSince
		if ga ~= gb then return ga < gb end
		return a < b
	end)
	return list
end

-- What a loan costs now, the way Swedbank's "Mina lån" counts it.
local function DueNow(loan)
	if loan.status ~= "approved" or not loan.sentAt then return loan.amount or 0 end
	local unconfirmed = 0
	for _, p in pairs(loan.outbox or {}) do unconfirmed = unconfirmed + (p.amount or 0) end
	local extra = (loan.left or 0) * (loan.rate or 0) * (time() - (loan.asOf or time())) / WEEK
	return math.max(0, (loan.left or 0) + (loan.interest or 0) + floor(extra) - unconfirmed - (loan.unverified or 0))
end

local function LoanStatus(loan)
	if loan.status == "approved" then
		if not loan.sentAt then return "|cffffd100Godkänt, guldet på väg|r" end
		if (loan.repayBy or 0) > 0 and time() > loan.repayBy then return "|cffff4040Försenat|r" end
		if next(loan.outbox or {}) or (loan.unverified or 0) > 0 then return "|cffffd100Betalning kontrolleras|r" end
		return "|cff40ff40Aktivt|r"
	elseif loan.status == "pending" then
		return "Väntar på godkännande"
	elseif loan.status == "sending" then
		return "Väntar på gildeledaren"
	end
end

local function SetColor(tex, r, g, b, a)
	if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a or 1) else tex:SetTexture(r, g, b, a or 1) end
end

local function RunSlash(key, msg, title)
	local fn = SlashCmdList and SlashCmdList[key]
	if fn then fn(msg or "") return true end
	Print((title or (key == "SWEDBANK" and "Swedbank" or "Skatteverket")) .. " är inte på.")
end

-- The guild figures, worked out only when something has changed.
local cache = { favs = {}, counts = { good = 0, neutral = 0, negative = 0 }, without = 0, at = 0 }

local function UpdateGuildCache()
	local members = SkatteverketDB and SkatteverketDB.members or {}
	local roster = Roster()
	cache.favs = Favorites(members, roster)
	cache.me = Me()
	cache.place = nil
	for i, name in ipairs(cache.favs) do
		if name == cache.me then cache.place = i break end
	end
	cache.counts = { good = 0, neutral = 0, negative = 0 }
	cache.without = 0
	for name in pairs(roster or {}) do
		local m = members[name]
		if m then
			local st = Standing(m)
			cache.counts[st] = cache.counts[st] + 1
		else
			cache.without = cache.without + 1
		end
	end
	cache.inGuild = IsInGuild()
	if cache.inGuild then
		cache.total, cache.online = GetNumGuildMembers()
		cache.motd = GetGuildRosterMOTD and GetGuildRosterMOTD() or ""
	end
	cache.at = GetTime()
	guildDirty = false
end

-- Your own tax: standing, the countdown (long and short), how far the bar is
-- filled and in which colour.
local function TaxState()
	local c = SkatteverketCharDB
	if not c then return { note = "Skatteverket är inte på.", short = "Skatteverket är inte på" } end
	if not InGuild() then
		return { note = "Den här karaktären är inte med i " .. GUILD .. "; inget beskattas.", short = "Inte med i gildet" }
	end
	local s = { c = c, owed = c.owed or 0, ok = true }
	local age = AccountDebt()
	if age then
		-- 0.28: the account's debt, in play time.
		s.standing = PlayStanding(age)
		s.debt = age > 0 and age or nil
	else
		s.standing = Standing(c)
		s.debt = c.debtSince and s.owed >= 1 and (time() - c.debtSince) or nil
		s.old = true
	end
	local good, negative = s.old and OLD_GOOD or GOOD, s.old and OLD_NEGATIVE or NEGATIVE
	local played = s.old and "" or " speltid"
	if s.debt then
		if s.standing == "good" then
			s.next = good - s.debt
			s.note = "Blir |cffffd100Neutral|r om " .. Duration(s.next) .. played .. " om du inte betalar."
			s.short = "Neutral om " .. Duration(s.next)
		elseif s.standing == "neutral" then
			s.next = negative - s.debt
			s.note = "Blir |cffff4040Negativ|r om " .. Duration(s.next) .. played .. ". Besök gildebanken."
			s.short = "|cffff4040Negativ om " .. Duration(s.next) .. "|r"
		else
			s.note = "|cffff4040Obetald i " .. Duration(s.debt) .. played .. ". Besök gildebanken.|r"
			s.short = "|cffff4040Obetald i " .. Duration(s.debt) .. "|r"
		end
	elseif s.owed >= 1 then
		-- Another character on the account has paid up, and it counts for all.
		s.note = "Skyldig " .. Money(s.owed) .. ", men kontot ligger bra till."
		s.short = "Kontot ligger bra till"
	elseif s.owed <= -1 then
		s.note = "Inget obetalt. Kredit hos gildet: " .. Money(-s.owed)
		s.short = "Inget obetalt"
	else
		s.note = "Inget obetalt; du ligger bra till."
		s.short = "Inget obetalt"
	end
	s.bar = s.debt and math.min(s.debt / negative, 1) or 0
	s.color = COLORS[s.debt and s.standing or "none"]
	return s
end

local function StandingText(s)
	if not s.ok then return "|cff808080-|r" end
	if cache.place and cache.place <= 3 then return format("|cffff8000Skatteverkets favorit #%d|r", cache.place) end
	return LABELS[s.standing]
end

------------------------------------------------------------------------
-- The panel

local function Text(parent, template, ...)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetPoint(...)
	fs:SetJustifyH("LEFT")
	return fs
end

local function Section(parent, label, y)
	Text(parent, "GameFontNormal", "TOPLEFT", PAD, y):SetText(label)
	local line = parent:CreateTexture(nil, "ARTWORK")
	SetColor(line, 1, 0.82, 0, 0.25)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", PAD, y - 16)
	line:SetPoint("TOPRIGHT", -PAD, y - 16)
end

-- A grey label on the left and a value on the right.
local function Pair(parent, y, label)
	local key = Text(parent, "GameFontHighlightSmall", "TOPLEFT", PAD, y)
	key:SetTextColor(0.75, 0.75, 0.75)
	key:SetText(label or "")
	local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	value:SetPoint("TOPRIGHT", -PAD, y)
	value:SetJustifyH("RIGHT")
	return value, key
end

local function Button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

local function Bar(parent, width, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(width, height)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetMinMaxValues(0, 1)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	SetColor(bg, 1, 1, 1, 0.08)
	local tick = bar:CreateTexture(nil, "OVERLAY")
	SetColor(tick, 1, 1, 1, 0.7)
	tick:SetSize(2, height + 4)
	tick:SetPoint("CENTER", bar, "LEFT", width * GOOD / NEGATIVE, 0)
	bar.tick, bar.width = tick, width
	return bar
end

-- Kept as a top-left corner, so the panel opens downwards from the bar and
-- the bar stays where it is.
local function SavePosition()
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left or not top then return end
	db.pos = { "TOPLEFT", "BOTTOMLEFT", left, top }
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function DefaultPosition()
	frame:ClearAllPoints()
	frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -220)
end

local Refresh, ClosePanel, ToggleHub

local function Build()
	frame = CreateFrame("Frame", "GildepanelFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetSize(W, COMPACT_H)
	if db.pos then
		frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
	else
		DefaultPosition()
	end
	frame:SetScale(db.scale or 1)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
	frame:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePosition() end)
	-- Not in UISpecialFrames: Escape must not close it. It closes only with
	-- its X, /gpanel or the minimap button (when on).

	-- The compact bar.
	local compact = CreateFrame("Frame", nil, frame)
	compact:SetPoint("TOPLEFT")
	compact:SetSize(W, COMPACT_H)
	compact.standing = Text(compact, "GameFontNormal", "TOPLEFT", PAD, -10)
	compact.owed = compact:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	compact.owed:SetPoint("TOPRIGHT", -PAD, -12)
	compact.owed:SetJustifyH("RIGHT")
	compact.note = Text(compact, "GameFontHighlightSmall", "TOPLEFT", PAD, -28)
	compact.note:SetWidth(W - 2 * PAD)
	compact.note:SetWordWrap(false)
	compact.bar = Bar(compact, W - 2 * PAD, 3)
	compact.bar:SetPoint("TOPLEFT", PAD, -43)
	frame.compact = compact

	-- The full panel.
	local body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT")
	body:SetSize(W, 1)
	frame.body = body

	Text(body, "GameFontNormalLarge", "TOPLEFT", PAD, -12):SetText(GUILD)
	local close = CreateFrame("Button", nil, body, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function() ClosePanel() end)
	local addons = Button(body, "Addons", 64, function() ToggleHub() end)
	addons:SetHeight(20)
	addons:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -8)

	-- Skatteverket
	Section(body, "Skatteverket", -34)
	-- Your skattenummer, or a way to sign up when you have not yet.
	local reg = CreateFrame("Button", nil, body)
	reg:SetSize(150, 16)
	reg:SetPoint("TOPRIGHT", -PAD, -32)
	reg.text = reg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	reg.text:SetPoint("RIGHT")
	reg.text:SetJustifyH("RIGHT")
	reg:SetScript("OnClick", function(self)
		RunSlash("SKATTEVERKET", self.signed and "yrken" or "anmälan")
	end)
	reg:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(self.signed and "Klicka: Skatteverkets yrkesregister" or "Klicka: skriv under anmälan till Skatteverket")
		GameTooltip:Show()
	end)
	reg:SetScript("OnLeave", function() GameTooltip:Hide() end)
	body.reg = reg
	body.standing = Text(body, "GameFontNormalLarge", "TOPLEFT", PAD, -58)
	body.rate = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	body.rate:SetPoint("TOPRIGHT", -PAD, -61)
	body.note = Text(body, "GameFontHighlightSmall", "TOPLEFT", PAD, -82)
	body.note:SetWidth(W - 2 * PAD)
	-- Debt age: the bar fills up to negative standing, with a mark where good
	-- standing ends (8 of 12 hours' play; 48 hours of a week on old Skatteverket).
	body.bar = Bar(body, W - 2 * PAD, 10)
	body.bar:SetPoint("TOPLEFT", PAD, -100)
	body.owed = Pair(body, -118, "Skyldig nu")
	body.income = Pair(body, -134, "Inkomst sedan senaste insättningen")
	body.paid = Pair(body, -150, "Betalt totalt")
	body.last = Pair(body, -166, "Senaste insättning")
	body.pay = Button(body, "Betala skatt", 130, function() RunSlash("SKATTEVERKET", "betala") end)
	body.pay:SetPoint("TOPLEFT", PAD - 2, -186)
	local more = Button(body, "Öppna /skatt", 130, function() RunSlash("SKATTEVERKET", "") end)
	more:SetPoint("TOPRIGHT", -PAD + 2, -186)

	-- Favourites
	Section(body, "Skatteverkets favoriter", -220)
	body.fav = {}
	for i = 1, 3 do
		body.fav[i] = Pair(body, -244 - (i - 1) * 16, format("#%d", i))
	end
	body.place = Pair(body, -292, "Din plats")

	-- The guild. The message of the day wraps to its full length; Swedbank
	-- sits below it and the panel grows to fit (see FitHeight).
	Section(body, "Gildet", -314)
	body.online = Pair(body, -338, "Online")
	body.counts = Text(body, "GameFontHighlightSmall", "TOPLEFT", PAD, -354)
	body.motd = Text(body, "GameFontHighlightSmall", "TOPLEFT", PAD, MOTD_Y)
	body.motd:SetWidth(W - 2 * PAD)
	body.motd:SetJustifyV("TOP")
	body.motd:SetWordWrap(true)

	-- Swedbank
	local swedbank = CreateFrame("Frame", nil, body)
	swedbank:SetSize(W, SWEDBANK_H)
	swedbank:SetPoint("TOPLEFT", body.motd, "BOTTOMLEFT", -PAD, -8)
	Section(swedbank, "Swedbank", 0)
	body.loans = {}
	for i = 1, 3 do
		local value, key = Pair(swedbank, -24 - (i - 1) * 16)
		body.loans[i] = { key = key, value = value }
	end
	local swed = Button(swedbank, "Öppna Swedbank", 140, function() RunSlash("SWEDBANK") end)
	swed:SetPoint("TOPLEFT", PAD - 2, -78)
	body.loanNote = swedbank:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	body.loanNote:SetPoint("LEFT", swed, "RIGHT", 10, 0)

	frame:SetScript("OnUpdate", function(self, elapsed)
		-- Open while the mouse is over it, or while you owe at the guild bank.
		if db.compact ~= false then
			local s = SkatteverketCharDB
			local hold = self:IsMouseOver(6, -6, -6, 6) or (bankOpen and s and (s.owed or 0) >= 1 and InGuild())
			if hold then
				self.leftAt = nil
				if not expanded then
					expanded = true
					Refresh()
				end
			elseif expanded then
				self.leftAt = self.leftAt or GetTime()
				if GetTime() - self.leftAt > COLLAPSE_DELAY then
					expanded = false
					Refresh()
				end
			end
		end
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed >= TICK then
			self.elapsed = 0
			Refresh()
		end
	end)
	frame:Hide()
end

local function FitHeight()
	local height = COMPACT_H
	if expanded then
		-- The font string has no fixed height, so it is always as tall as its text.
		local text = math.max(frame.body.motd:GetStringHeight() or 0, 12)
		height = -MOTD_Y + text + 8 + SWEDBANK_H
	end
	if math.abs(frame:GetHeight() - height) > 0.5 then frame:SetHeight(height) end
end

-- The mark where good standing ends; old Skatteverket counts days, not play.
local function PlaceTick(bar, s)
	local at = s.old and OLD_GOOD / OLD_NEGATIVE or GOOD / NEGATIVE
	bar.tick:ClearAllPoints()
	bar.tick:SetPoint("CENTER", bar, "LEFT", bar.width * at, 0)
end

local function RefreshTax(s)
	local compact, body = frame.compact, frame.body
	local standing = StandingText(s)
	compact.standing:SetText(standing)
	compact.owed:SetText(s.ok and (s.owed >= 1 and ("Skyldig " .. Money(s.owed)) or "") or "")
	compact.note:SetText(s.short)
	compact.bar:SetValue(s.bar or 0)
	if s.color then compact.bar:SetStatusBarColor(s.color[1], s.color[2], s.color[3]) end
	PlaceTick(compact.bar, s)
	if not expanded then return end

	body.standing:SetText(standing)
	body.note:SetText(s.note)
	body.bar:SetValue(s.bar or 0)
	PlaceTick(body.bar, s)
	if s.color then body.bar:SetStatusBarColor(s.color[1], s.color[2], s.color[3]) end
	if not s.ok then
		body.rate:SetText("")
		for _, fs in ipairs({ body.owed, body.income, body.paid, body.last }) do fs:SetText("-") end
		body.pay:Disable()
		body.reg.text:SetText("")
		return
	end
	local c = s.c
	body.rate:SetText(format("Skattesats %g %%", ((SkatteverketDB and SkatteverketDB.rate) or 0.05) * 100))
	-- Registration (Skatteverket 0.12): SkatteverketCharDB.reg once signed,
	-- with the number the guild leader hands out.
	local reg = c.reg
	body.reg.signed = reg and true or false
	if not reg then
		body.reg.text:SetText("|cffff8040Inte anmäld, klicka|r")
	elseif reg.number and reg.number > 0 then
		body.reg.text:SetText(format("|cffd0d0d0Skattenummer|r TS-%04d", reg.number))
	else
		body.reg.text:SetText("|cffd0d0d0Anmäld, väntar på nummer|r")
	end
	body.owed:SetText(Money(math.max(s.owed, 0)))
	body.income:SetText(Money(c.incomeSince))
	body.paid:SetText(Money(c.paid))
	body.last:SetText(c.lastDeposit and date("%d/%m %H:%M", c.lastDeposit) or "aldrig")
	if bankOpen and s.owed >= 1 then body.pay:Enable() else body.pay:Disable() end
end

local function RefreshGuild()
	local body = frame.body
	for i = 1, 3 do
		local name = cache.favs[i]
		body.fav[i]:SetText(name and (name == cache.me and ("|cffff8000" .. name .. " (du)|r") or name) or "|cff808080-|r")
	end
	body.place:SetText(cache.place and format("#%d av %d i god ställning", cache.place, #cache.favs)
		or (InGuild() and "inte med än (betala och håll dig God)" or "-"))
	if not cache.inGuild then
		body.online:SetText("-")
		body.counts:SetText("")
		body.motd:SetText("")
		return
	end
	body.online:SetText(format("%d av %d", cache.online or 0, cache.total or 0))
	body.counts:SetText(format("|cff40ff40%d God|r   |cffffd100%d Neutral|r   |cffff4040%d Negativ|r   |cff808080%d utan addon|r",
		cache.counts.good, cache.counts.neutral, cache.counts.negative, cache.without))
	local motd = cache.motd or ""
	body.motd:SetText(motd ~= "" and ("|cffbfbfbfMeddelande:|r |cff40c0ff" .. motd .. "|r") or "|cff808080Inget gildemeddelande.|r")
end

local LOAN_ORDER = { approved = 1, pending = 2, sending = 3 }

local function RefreshLoans()
	local body, c = frame.body, SwedbankCharDB
	for _, line in ipairs(body.loans) do
		line.key:SetText("")
		line.value:SetText("")
	end
	if not c then
		body.loans[1].key:SetText("Swedbank är inte på.")
		body.loanNote:SetText("")
		return
	end
	local open, closed = {}, 0
	for _, loan in pairs(c.loans or {}) do
		if LOAN_ORDER[loan.status] then table.insert(open, loan) else closed = closed + 1 end
	end
	table.sort(open, function(a, b)
		local oa, ob = LOAN_ORDER[a.status], LOAN_ORDER[b.status]
		if oa ~= ob then return oa < ob end
		return (a.appliedAt or 0) > (b.appliedAt or 0)
	end)
	if #open == 0 then body.loans[1].key:SetText("Inga lån igång.") end
	local total = 0
	for i, loan in ipairs(open) do
		local due = DueNow(loan)
		if loan.status == "approved" then total = total + due end
		local line = body.loans[i]
		if line then
			line.key:SetText(LoanStatus(loan))
			local when = (loan.repayBy or 0) > 0 and (" · senast " .. Day(loan.repayBy)) or ""
			line.value:SetText((loan.status == "approved" and Money(due) or Money(loan.amount)) .. when)
		end
	end
	local note = {}
	if total > 0 then table.insert(note, "Att betala: " .. Money(total)) end
	if closed > 0 then table.insert(note, closed .. " avslutade") end
	body.loanNote:SetText(table.concat(note, " · "))
end

local function RefreshMini(s)
	if not mini then return end
	s = s or TaxState()
	local color = s.ok and COLORS[s.debt and s.standing or "good"] or COLORS.none
	SetColor(mini.dot, color[1], color[2], color[3], 1)
end

Refresh = function()
	local s = TaxState()
	RefreshMini(s)
	if not frame or not frame:IsShown() then return end
	-- The guild figures: after a change (at most every 2 seconds) or every 30.
	local age = GetTime() - cache.at
	local guildChanged = (guildDirty and age > 2) or age > GUILD_EVERY
	if guildChanged then UpdateGuildCache() end
	SetVisible(frame.compact, not expanded)
	SetVisible(frame.body, expanded)
	RefreshTax(s)
	if expanded then
		RefreshGuild()
		RefreshLoans()
	end
	FitHeight()
end

local function OpenPanel()
	if not frame then Build() end
	db.shown = true
	expanded = db.compact == false
	frame:Show()
	-- Older versions kept another corner; switch to the top-left one.
	if db.pos and db.pos[1] ~= "TOPLEFT" then SavePosition() end
	Statskontoret.RequestRoster()
	guildDirty, cache.at = true, 0
	Refresh()
end

ClosePanel = function()
	db.shown = false
	if frame then frame:Hide() end
end

local function Toggle()
	if frame and frame:IsShown() then ClosePanel() else OpenPanel() end
end

------------------------------------------------------------------------
-- Minimap button: left click the panel, right click /skatt, drag to move.

local function PlaceMini()
	local a = math.rad(db.minimapAngle or 210)
	mini:ClearAllPoints()
	mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

local function BuildMini()
	mini = CreateFrame("Button", "GildepanelMinimapButton", Minimap)
	mini:SetSize(31, 31)
	mini:SetFrameStrata("MEDIUM")
	mini:SetFrameLevel(8)
	mini:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	mini:RegisterForDrag("LeftButton")
	mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local icon = mini:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
	icon:SetPoint("TOPLEFT", 7, -5)
	local border = mini:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")
	-- A small square in your standing's colour.
	mini.dot = mini:CreateTexture(nil, "OVERLAY", nil, 7)
	mini.dot:SetSize(7, 7)
	mini.dot:SetPoint("BOTTOMRIGHT", -6, 6)

	mini:SetScript("OnClick", function(_, button)
		if button == "MiddleButton" or (button == "LeftButton" and IsShiftKeyDown()) then
			ToggleHub()
		elseif button == "RightButton" then
			RunSlash("SKATTEVERKET", "")
		else
			Toggle()
		end
	end)
	mini:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
			PlaceMini()
		end)
	end)
	mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	mini:SetScript("OnEnter", function(self)
		local s = TaxState()
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Gildepanel")
		if not s.ok then
			GameTooltip:AddLine(s.note, 1, 1, 1, true)
		else
			GameTooltip:AddDoubleLine("Ställning", LABELS[s.standing], 1, 1, 1)
			GameTooltip:AddDoubleLine("Skyldig nu", Money(math.max(s.owed, 0)), 1, 1, 1, 1, 1, 1)
			if s.next then GameTooltip:AddDoubleLine(s.old and "Nästa steg ned om" or "Nästa steg ned om (speltid)", Duration(s.next), 1, 1, 1, 1, 0.82, 0) end
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Vänsterklick: panelen   Högerklick: /skatt", 0.6, 0.6, 0.6)
		GameTooltip:AddLine("Shift-klick eller mittenklick: addons   Dra: flytta", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
	PlaceMini()
	-- Hidden unless turned on (/gpanel minimap): Skatteverket has its own button.
	if db.hideMinimap ~= false then mini:Hide() end
	RefreshMini()
end

------------------------------------------------------------------------
-- Addons: one window that opens the other guild addons' windows and turns
-- their automatic settings on and off. The settings are written straight
-- into each addon's saved table, which is the same table the addon reads,
-- so a change takes effect at once. Settings with side effects (Eniro's
-- position sharing, the compact panel) go through the addon's own slash
-- command instead.

local hub

------------------------------------------------------------------------
-- Camera distance: how far out the mouse wheel zooms. The game keeps it in
-- the cameraDistanceMaxZoomFactor setting, times 15 yards; the client
-- caps it (2.6 on a retail engine), so the value is read back after it is
-- set. Kept in GildepanelDB.cameraMax and set again at login, since the
-- game can put it back; nil leaves the game's own value alone.

local CAMERA_CVAR = "cameraDistanceMaxZoomFactor"
local CAMERA_MIN, CAMERA_MAX, CAMERA_YARDS = 1, 4, 15

local function GetCamera()
	local get = C_CVar and C_CVar.GetCVar or GetCVar
	local ok, v = pcall(get, CAMERA_CVAR)
	return ok and tonumber(v) or nil
end

local function SetCamera(factor)
	local set = C_CVar and C_CVar.SetCVar or SetCVar
	pcall(set, CAMERA_CVAR, tostring(factor))
	return GetCamera()
end

local function DefaultCamera()
	local get = C_CVar and C_CVar.GetCVarDefault or GetCVarDefault
	local ok, v = pcall(get or error, CAMERA_CVAR)
	return ok and tonumber(v) or 1.9
end

local function CameraText(factor)
	if not factor then return "okänt" end
	return format("%.1f (%d yards)", factor, floor(factor * CAMERA_YARDS + 0.5))
end

-- Sets and remembers it; returns the value the game took.
local function ChooseCamera(factor)
	factor = math.max(CAMERA_MIN, math.min(CAMERA_MAX, floor(factor * 10 + 0.5) / 10))
	local got = SetCamera(factor)
	db.cameraMax = got or factor
	return got
end

local WINDOWS = {
	{ "Skatteverket", "Skatteverket", "SKATTEVERKET" },
	{ "Skatteverket", "Yrkesregister", "SKATTEVERKET", "yrken" },
	{ "Skatteverket", "Anmälan", "SKATTEVERKET", "anmälan" },
	{ "Swedbank", "Swedbank", "SWEDBANK" },
	{ "Arbetsformedlingen", "Uppdrag", "ARBETSFORMEDLINGEN" },
	{ "Arbetsformedlingen", "Platsbanken", "PLATSBANKEN" },
	{ "Skolverket", "Cooldowns", "SKOLVERKET" },
	{ "Eniro", "Eniro", "ENIRO" },
	{ "Polisen", "Polisen", "POLISEN" },
	{ "SCB", "SCB", "SCB" },
	{ "Dodsannonser", "Dödsannonser", "DODSANNONSER" },
}

-- invert: the addon stores "quiet", the box shows the opposite.
-- default: the value when the addon has not saved one yet.
local SETTINGS = {
	{ addon = "Atervinningscentralen", title = "Återvinningscentralen", db = "AtervinningscentralenDB", items = {
		{ key = "sell", label = "Sälj grått hos handlare", default = true },
		{ key = "repair", label = "Laga utrustningen", default = true },
	} },
	{ addon = "Handlaggaren", title = "Handläggaren", db = "HandlaggarenDB", items = {
		{ key = "on", label = "Ta och lämna in uppdrag", default = true },
		{ key = "pickBest", label = "Välj dyraste belöningen själv" },
		{ key = "share", label = "Dela nya uppdrag med gruppen" },
		{ key = "gossip", label = "Välj NPC:ns enda pratval" },
		{ key = "trivial", label = "Ta gråa uppdrag" },
		{ key = "shared", label = "Ta uppdrag som gruppen delar" },
		{ key = "announce", label = "Säg till gruppen när ett uppdrag är klart", default = true },
	} },
	{ addon = "Kolapp", title = "Kölapp", db = "KolappDB", items = {
		{ key = "chat", label = "Questkedjor i chatten", default = true },
	} },
	{ addon = "Dodsannonser", title = "Dödsannonser", db = "DodsannonserDB", items = {
		{ key = "quiet", label = "Visa nya i chatten", invert = true },
		{ key = "guildChat", label = "Skriv mina egna i gillechatten", default = true },
		{ key = "noLevels", label = "Annonsera nya nivåer", invert = true },
		{ key = "noPets", label = "Annonsera husdjurens nya nivåer", invert = true },
	} },
	{ addon = "Polisen", title = "Polisen", db = "PolisenDB", items = {
		{ key = "alarm", label = "Varning på skärmen och ljud", default = true },
		{ key = "quiet", label = "Visa andras observationer", invert = true },
	} },
	{ addon = "Arbetsformedlingen", title = "Arbetsförmedlingen", db = "ArbetsformedlingenCharDB", items = {
		{ key = "quiet", label = "Visa nya annonser i chatten", invert = true },
	} },
	-- The markup limit itself is a number: /revisor gräns 12.
	{ addon = "Revisorsinspektionen", title = "Revisorsinspektionen", db = "RevisorsinspektionenDB", items = {
		{ key = "dim", label = "Dämpa recept under påslagsgränsen", default = true },
		{ key = "tooltip", label = "Vinst efter skatt i Bokföringens tips", default = true },
	} },
	-- trackerMode is "zone" or nil; any value counts as checked.
	{ addon = "QuestLogSort", title = "QuestLogSort", db = "QuestLogSortDB", items = {
		{ key = "disabled", label = "Sortera questlogg och tracker", invert = true, slash = { "QUESTLOGSORT", "på", "av" } },
		{ key = "trackerMode", label = "Trackern zon för zon", slash = { "QUESTLOGSORT", "zon", "nivå" } },
	} },
	{ addon = "Eniro", title = "Eniro", db = "EniroCharDB", items = {
		{ key = "share", label = "Dela min position med gillet", slash = { "ENIRO", "dela" } },
	} },
	{ addon = ADDON, title = "Gildepanel", db = "GildepanelDB", items = {
		{ key = "warn", label = "Förvarna innan skatteställningen sjunker", default = true },
		{ key = "celebrate", label = "Fira när du betalar skatt", default = true },
		{ key = "celebrateQuiet", label = "Med ljud", invert = true },
		{ key = "compact", label = "Kompakt rad tills musen är över", default = true, slash = { "GILDEPANEL", "kompakt" } },
		{ key = "hideMinimap", label = "Visa minimapknappen", invert = true, default = true, slash = { "GILDEPANEL", "minimap" } },
		{ key = "keepTracking", label = "Behåll örter/malm-spårning vid inloggning", default = true },
	} },
}

local function Loaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
	return IsAddOnLoaded and IsAddOnLoaded(name)
end

local function SettingValue(group, item)
	local t = _G[group.db]
	if type(t) ~= "table" then return false end
	local v = t[item.key]
	if v == nil then v = item.default or false end
	v = v and true or false
	if item.invert then v = not v end
	return v
end

local function SetSetting(group, item, on)
	if item.slash then
		-- { key, toggle } or { key, turn on, turn off }. Run it only if the
		-- value is not already right.
		if SettingValue(group, item) ~= on then
			local msg = item.slash[2]
			if item.slash[3] and not on then msg = item.slash[3] end
			RunSlash(item.slash[1], msg, group.title)
		end
		return
	end
	local t = _G[group.db]
	if type(t) ~= "table" then return end
	if item.invert then on = not on end
	t[item.key] = on
end

local function RefreshHub()
	if hub.camera then hub.camera() end
	for _, b in ipairs(hub.windows) do
		if Loaded(b.addon) and SlashCmdList[b.key] then b:Enable() else b:Disable() end
	end
	for _, row in ipairs(hub.groups) do
		local loaded = Loaded(row.group.addon) and type(_G[row.group.db]) == "table"
		row.header:SetText(row.group.title .. (loaded and "" or "  |cff808080(inte på)|r"))
		for _, cb in ipairs(row.boxes) do
			cb:SetChecked(loaded and SettingValue(row.group, cb.item))
			if loaded then
				cb:Enable()
				cb.label:SetTextColor(1, 1, 1)
			else
				cb:Disable()
				cb.label:SetTextColor(0.5, 0.5, 0.5)
			end
		end
	end
end

local Panel = Statskontoret.Panel

local function BuildHub()
	-- Wide, with the settings in two columns (2.8): one column grew too tall.
	local HW = 620
	local classic
	hub, classic = Panel("GildepanelHub", GUILD)
	hub:SetWidth(HW)
	hub:SetFrameStrata("DIALOG")
	hub:SetClampedToScreen(true)
	hub:SetMovable(true)
	hub:EnableMouse(true)
	hub:RegisterForDrag("LeftButton")
	hub:SetScript("OnDragStart", function(self) self:StartMoving() end)
	hub:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local left, top = self:GetLeft(), self:GetTop()
		if left and top then
			db.hubPos = { left, top }
			self:ClearAllPoints()
			self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		end
	end)
	if db.hubPos then
		hub:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.hubPos[1], db.hubPos[2])
	else
		hub:SetPoint("CENTER")
	end
	-- Unlike the panel, Escape closes this one.
	table.insert(UISpecialFrames, "GildepanelHub")

	-- Beside the portrait, as Skatteverket's panel has its bank line; the
	-- rest starts below the portrait.
	Text(hub, "GameFontNormal", "TOPLEFT", classic and 66 or PAD, -34):SetText("Addons")
	local top = classic and -66 or -34

	-- Windows, four buttons a row.
	Section(hub, "Fönster", top)
	hub.windows = {}
	local PER_ROW = 4
	local bw = (HW - 2 * PAD - 8 * (PER_ROW - 1)) / PER_ROW
	local y = top - 24
	for i, w in ipairs(WINDOWS) do
		local b = Button(hub, w[2], bw, function() RunSlash(w[3], w[4] or "", w[2]) end)
		b.addon, b.key = w[1], w[3]
		local col = (i - 1) % PER_ROW
		b:SetPoint("TOPLEFT", PAD + col * (bw + 8), y)
		if col == PER_ROW - 1 or i == #WINDOWS then y = y - 26 end
		table.insert(hub.windows, b)
	end

	-- Camera distance.
	y = y - 10
	Section(hub, "Kamera", y)
	y = y - 24
	local camLabel = Text(hub, "GameFontHighlightSmall", "TOPLEFT", PAD, y)
	y = y - 18
	local slider = CreateFrame("Slider", nil, hub)
	slider:SetOrientation("HORIZONTAL")
	slider:SetSize(HW - 2 * PAD - 70, 14)
	slider:SetPoint("TOPLEFT", PAD + 2, y)
	slider:SetMinMaxValues(CAMERA_MIN, CAMERA_MAX)
	slider:SetValueStep(0.1)
	if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
	slider:EnableMouseWheel(true)
	local track = slider:CreateTexture(nil, "BACKGROUND")
	SetColor(track, 1, 1, 1, 0.12)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	SetColor(thumb, 1, 0.82, 0, 1)
	thumb:SetSize(8, 14)
	slider:SetThumbTexture(thumb)
	local function ShowCamera(factor)
		camLabel:SetText("Längsta kameraavstånd: " .. CameraText(factor)
			.. (db.cameraMax and "" or "  |cff808080(spelets eget)|r"))
	end
	slider:SetScript("OnValueChanged", function(self, value)
		if self.setting then return end
		ShowCamera(value)
		-- Apply when the drag stops, or now for a click or the mouse wheel.
		self.pending = value
		if not self.dragging then
			self.pending = nil
			ChooseCamera(value)
			ShowCamera(GetCamera())
		end
	end)
	slider:SetScript("OnMouseDown", function(self) self.dragging = true end)
	slider:SetScript("OnMouseUp", function(self)
		self.dragging = false
		if self.pending then
			local v = self.pending
			self.pending = nil
			ChooseCamera(v)
		end
		hub.camera()
	end)
	slider:SetScript("OnMouseWheel", function(self, delta)
		self:SetValue(self:GetValue() + delta * 0.1)
	end)
	local reset = Button(hub, "Standard", 62, function()
		db.cameraMax = nil
		SetCamera(DefaultCamera())
		hub.camera()
	end)
	reset:SetPoint("LEFT", slider, "RIGHT", 6, 0)
	hub.camera = function()
		if slider.dragging then return end
		local v = GetCamera()
		slider.setting = true
		if v then slider:SetValue(v) end
		slider.setting = false
		ShowCamera(v)
	end
	y = y - 22

	-- Automatic settings, grouped by addon, in two columns: the groups in
	-- order, the second column starting once the first holds half.
	y = y - 10
	Section(hub, "Automatik", y)
	y = y - 24
	hub.groups = {}
	local function GroupHeight(group) return 16 + 20 * #group.items + 6 end
	local total = 0
	for _, group in ipairs(SETTINGS) do total = total + GroupHeight(group) end
	local colW = (HW - 2 * PAD) / 2
	local top2, x, used, lowest = y, PAD, 0, y
	for _, group in ipairs(SETTINGS) do
		local h = GroupHeight(group)
		if x == PAD and used > 0 and used + h / 2 > total / 2 then
			x, y = PAD + colW, top2
		end
		used = used + h
		local row = { group = group, boxes = {} }
		row.header = Text(hub, "GameFontNormalSmall", "TOPLEFT", x, y)
		y = y - 16
		for _, item in ipairs(group.items) do
			local cb = CreateFrame("CheckButton", nil, hub, "UICheckButtonTemplate")
			cb:SetSize(22, 22)
			cb:SetPoint("TOPLEFT", x + 4, y + 3)
			cb.item = item
			cb.label = Text(hub, "GameFontHighlightSmall", "LEFT", cb, "RIGHT", 2, 1)
			cb.label:SetText(item.label)
			cb:SetScript("OnClick", function(self)
				SetSetting(group, item, self:GetChecked() and true or false)
				RefreshHub()
			end)
			table.insert(row.boxes, cb)
			y = y - 20
		end
		y = y - 6
		lowest = math.min(lowest, y)
		table.insert(hub.groups, row)
	end
	hub:SetHeight(-lowest + (classic and 28 or 8))

	-- Slash commands can change a setting while the window is open.
	hub:SetScript("OnShow", RefreshHub)
	hub:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed >= 1 then
			self.elapsed = 0
			RefreshHub()
		end
	end)
	hub:Hide()
end

ToggleHub = function()
	if not hub then BuildHub() end
	SetVisible(hub, not hub:IsShown())
end

------------------------------------------------------------------------
-- Firandet: a show on screen and in your speakers when you pay your tax.
-- A payment is spotted from the outside: on PLAYER_MONEY your money went
-- down and SkatteverketCharDB.owed went down with it. A snapshot taken every
-- second (and after each check) is the "before". Paying your way out of
-- Neutral or Negativ gets the bigger show. /gpanel firande test previews it.

local FONT = "Fonts\\MORPHEUS.TTF"
local COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local STAR = "Interface\\Cooldown\\star4"
local EDGE = "Interface\\FullScreenTextures\\LowHealth"
local SHOW_FOR = 4.5
local CHEERS = {
	"Välfärden tackar dig.",
	"Gildebanken jublar.",
	"Skatteverket ser dig. Och är nöjt.",
	"Det är fint att betala skatt.",
	"Ingen restskatt här inte.",
	"Kvittot är arkiverat i tre exemplar.",
	"Ditt bidrag bygger " .. GUILD .. ".",
	"En sann förebild för gildet.",
}
local STANDING_NAMES = { good = "|cff40ff40God|r", neutral = "|cffffd100Neutral|r", negative = "|cffff4040Negativ|r" }

-- Plays the first sound the client knows: SOUNDKIT names, then kit numbers.
-- PlaySound returns false for a kit it does not have, so try the next.
local function Sound(list)
	if not PlaySound or db.celebrateQuiet then return end
	for _, kit in ipairs(list) do
		local id = kit
		if type(kit) == "string" then id = SOUNDKIT and SOUNDKIT[kit] end
		if id then
			local ok, played = pcall(PlaySound, id, "SFX")
			if ok and played then return end
		end
	end
end

local show
local function BuildShow()
	show = CreateFrame("Frame", nil, UIParent)
	show:SetAllPoints(UIParent)
	show:SetFrameStrata("FULLSCREEN_DIALOG")
	show:EnableMouse(false)
	show:Hide()

	show.flash = show:CreateTexture(nil, "BACKGROUND")
	show.flash:SetAllPoints()
	SetColor(show.flash, 1, 0.78, 0.2, 1)
	show.flash:SetBlendMode("ADD")

	show.edge = show:CreateTexture(nil, "BORDER")
	show.edge:SetAllPoints()
	show.edge:SetTexture(EDGE)
	show.edge:SetVertexColor(1, 0.75, 0.1)
	show.edge:SetBlendMode("ADD")

	-- The banner: a band, a turning star behind the bolt, the big words.
	local b = CreateFrame("Frame", nil, show)
	b:SetSize(760, 150)
	show.banner = b
	b.band = b:CreateTexture(nil, "BACKGROUND")
	b.band:SetPoint("LEFT")
	b.band:SetPoint("RIGHT")
	b.band:SetHeight(112)
	SetColor(b.band, 0, 0, 0, 0.55)
	for i, point in ipairs({ "TOP", "BOTTOM" }) do
		local line = b:CreateTexture(nil, "BORDER")
		line:SetPoint(point .. "LEFT", b.band, point .. "LEFT")
		line:SetPoint(point .. "RIGHT", b.band, point .. "RIGHT")
		line:SetHeight(2)
		SetColor(line, 1, 0.82, 0.2, 0.9)
		b["line" .. i] = line
	end
	b.star = b:CreateTexture(nil, "ARTWORK")
	b.star:SetSize(220, 220)
	b.star:SetPoint("CENTER", b, "TOP", 0, 6)
	b.star:SetTexture(STAR)
	b.star:SetVertexColor(1, 0.85, 0.3)
	b.star:SetBlendMode("ADD")
	b.bolt = b:CreateTexture(nil, "OVERLAY")
	b.bolt:SetSize(64, 64)
	b.bolt:SetPoint("CENTER", b.star)
	b.bolt:SetTexture(Loaded("Skatteverket") and "Interface\\AddOns\\Skatteverket\\Media\\Bolt" or "Interface\\Icons\\Spell_Nature_Lightning")
	b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	if not pcall(b.title.SetFont, b.title, FONT, 44, "THICKOUTLINE") then b.title:SetFontObject("GameFontNormalHuge") end
	b.title:SetPoint("CENTER", b.band, "CENTER", 0, 16)
	b.title:SetTextColor(1, 0.84, 0.1)
	b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	b.sub:SetPoint("TOP", b.title, "BOTTOM", 0, -6)

	show.coins = {}
	show:SetScript("OnUpdate", function(self, elapsed)
		self.t = self.t + elapsed
		local t = self.t
		-- The flash and the glowing edge.
		self.flash:SetAlpha(t < 0.12 and t / 0.12 * 0.35 or math.max(0, 0.35 * (1 - (t - 0.12) / 0.7)))
		local fade = t > SHOW_FOR - 0.8 and math.max(0, (SHOW_FOR - t) / 0.8) or 1
		self.edge:SetAlpha((0.45 + 0.35 * math.sin(t * 6)) * fade * (self.big and 1 or 0.6))
		-- The banner bounces in from large, then sits still and fades.
		local p = math.min(t / 0.7, 1)
		local ease = p >= 1 and 1 or 1 + 2 ^ (-10 * p) * math.sin((p * 10 - 0.75) * 2 * math.pi / 3)
		local scale = math.max(0.05, 2.4 - 1.4 * ease)
		local banner = self.banner
		banner:SetScale(scale)
		banner:ClearAllPoints()
		banner:SetPoint("CENTER", UIParent, "CENTER", 0, 170 / scale)
		banner:SetAlpha(math.min(t / 0.15, 1) * fade)
		if banner.star.SetRotation then banner.star:SetRotation(t * 1.3) end
		banner.star:SetAlpha(0.6 + 0.4 * math.sin(t * 4))
		-- The coins: thrown out and pulled down, spinning.
		local alive = false
		for _, c in ipairs(self.coins) do
			if c.on then
				c.wait = c.wait - elapsed
				if c.wait <= 0 then
					c.life = c.life + elapsed
					c.vy = c.vy - 1100 * elapsed
					c.x, c.y = c.x + c.vx * elapsed, c.y + c.vy * elapsed
					c.rot = c.rot + c.spin * elapsed
					c.tex:ClearAllPoints()
					c.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", c.x, c.y)
					if c.tex.SetRotation then c.tex:SetRotation(c.rot) end
					c.tex:SetAlpha(math.min(1, (c.ttl - c.life) / 0.5))
					c.tex:Show()
					if c.life >= c.ttl or c.y < -40 then c.on = false c.tex:Hide() end
				end
				alive = alive or c.on
			end
		end
		if t >= SHOW_FOR and not alive then self:Hide() end
	end)
end

local function Coin(i)
	local c = show.coins[i]
	if not c then
		c = { tex = show:CreateTexture(nil, "OVERLAY") }
		c.tex:SetTexture(COIN)
		c.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		show.coins[i] = c
	end
	local size = math.random(16, 30)
	c.tex:SetSize(size, size)
	c.tex:Hide()
	c.on, c.life, c.rot = true, 0, math.random() * 6
	c.spin = (math.random() - 0.5) * 14
	return c
end

local function Celebrate(paid, before, after)
	if db.celebrate == false then return end
	if not show then BuildShow() end
	local big = before and before ~= "good" and after == "good"
	show.t, show.big = 0, big
	local b = show.banner
	b.title:SetText(big and "SKULDEN ÄR BETALD!" or "SKATTEN ÄR BETALD!")
	local sub = Money(paid)
	if big then
		sub = sub .. "   " .. STANDING_NAMES[before] .. " → " .. STANDING_NAMES.good .. "\n|cffffffffVälkommen tillbaka in i värmen!|r"
	else
		sub = sub .. "\n|cffffffff" .. CHEERS[math.random(#CHEERS)] .. "|r"
	end
	b.sub:SetText(sub)

	-- A burst from behind the banner; on the big one, a rain from the top too.
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	local cx, cy = w / 2, h / 2 + 170
	local burst = math.min(60, 18 + floor((paid or 0) / 10000) * 3)
	local n = 0
	for _ = 1, burst do
		n = n + 1
		local c = Coin(n)
		local a = math.random() * math.pi
		local speed = 300 + math.random() * 450
		c.x, c.y = cx, cy
		c.vx, c.vy = math.cos(a) * speed, math.sin(a) * speed * 0.9 + 150
		c.wait, c.ttl = math.random() * 0.15, 2.4 + math.random()
	end
	if big then
		for _ = 1, 50 do
			n = n + 1
			local c = Coin(n)
			c.x, c.y = math.random() * w, h + 30
			c.vx, c.vy = (math.random() - 0.5) * 80, -math.random() * 200
			c.wait, c.ttl = 0.4 + math.random() * 1.6, 3
		end
	end
	for i = n + 1, #show.coins do show.coins[i].on = false show.coins[i].tex:Hide() end
	show:Show()

	-- The sound: the till's coins, then a fanfare, bigger for a cleared debt.
	local COINS = { "LOOT_WINDOW_COIN_SOUND", 120 }
	for i = 0, big and 5 or 3 do
		C_Timer.After(i * 0.11, function() Sound(COINS) end)
	end
	C_Timer.After(0.25, function()
		if big then
			Sound({ "UI_LEGENDARY_LOOT_TOAST", "LEVELUPSOUND", 888, "UI_EPICLOOT_TOAST" })
		else
			Sound({ "UI_EPICLOOT_TOAST", "UI_IG_STORE_PURCHASE_DELIVERED_TOAST_01", "READY_CHECK", 8960 })
		end
	end)
	if big then C_Timer.After(1.1, function() Sound({ "UI_BNET_TOAST", "READY_CHECK", 8960 }) end) end
end

-- What a payment is measured against.
local before
local function Snapshot()
	local c = SkatteverketCharDB
	if not c or not InGuild() then before = nil return end
	local s = TaxState()
	before = { owed = c.owed or 0, money = GetMoney(), standing = s.debt and s.standing or "good" }
end

local checking = false
local function CheckPayment()
	if checking then return end
	checking = true
	local was = before
	-- Skatteverket books the payment in the same event; look a moment later.
	C_Timer.After(0.3, function()
		checking = false
		local c = SkatteverketCharDB
		if was and c and InGuild() then
			local spent = was.money - GetMoney()
			local cleared = was.owed - (c.owed or 0)
			if spent >= 1 and cleared >= 1 then
				local s = TaxState()
				Celebrate(math.max(spent, cleared), was.standing, s.debt and s.standing or "good")
			end
		end
		Snapshot()
	end)
end

------------------------------------------------------------------------
-- A heads-up in chat an hour of play before the standing drops a step.

-- Warnings already given, in GildepanelDB so a /reload doesn't repeat
-- them. Keys hold when the debt started, so a new debt warns afresh; keys
-- are dropped after two weeks.
local function Warned()
	db.warned = db.warned or {}
	local now = time()
	for key, at in pairs(db.warned) do
		if type(at) ~= "number" or now - at > 14 * 86400 then db.warned[key] = nil end
	end
	return db.warned
end
local function CheckWarning()
	if db.warn == false then return end
	local c = SkatteverketCharDB
	if not c or not InGuild() or (c.owed or 0) < 1 then return end
	local s = TaxState()
	if not s.debt then return end
	-- Old Skatteverket: real time, warned 6 hours ahead.
	local good, negative = s.old and OLD_GOOD or GOOD, s.old and OLD_NEGATIVE or NEGATIVE
	local ahead = s.old and 6 * 3600 or WARN_BEFORE
	local start = s.old and c.debtSince or floor(((SkatteverketDB and SkatteverketDB.clock) or 0) - s.debt)
	local warned = Warned()
	for _, step in ipairs({ { good, "|cffffd100Neutral|r" }, { negative, "|cffff4040Negativ|r" } }) do
		local left, key = step[1] - s.debt, floor(start / 60) .. ":" .. step[1]
		if left > 0 and left <= ahead and not warned[key] then
			warned[key] = time()
			Print(format("din ställning blir %s om %s%s. Betala %s vid gildebanken för att behålla den.", step[2], Duration(left), s.old and "" or " speltid", Money(c.owed)))
		end
	end
end

------------------------------------------------------------------------
-- Minimap tracking (Find Herbs, Find Minerals, ...): the game can drop it at
-- login. With db.keepTracking on (the default), the tracking spells you turn
-- on are saved per character in db.tracking and turned on again a few
-- seconds after login, and once more later in case the game or another
-- addon changed it in between. Changes are not saved until the restore has
-- run, so the reset state at login doesn't overwrite your choice.

local trackingReady = false

local function CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function NumTracking()
	local f = C_Minimap and C_Minimap.GetNumTrackingTypes or GetNumTrackingTypes
	local ok, n = pcall(f or error)
	return ok and tonumber(n) or 0
end

-- name, active, isSpell for tracking type i.
local function TrackingInfo(i)
	if C_Minimap and C_Minimap.GetTrackingInfo then
		local ok, a, _, c, d = pcall(C_Minimap.GetTrackingInfo, i)
		if not ok then return end
		if type(a) == "table" then
			return a.name, a.active, a.type == nil or a.type == "spell"
		end
		return a, c, d == nil or d == "spell"
	elseif GetTrackingInfo then
		local ok, name, _, active, kind = pcall(GetTrackingInfo, i)
		if ok then return name, active, kind == nil or kind == "spell" end
	end
end

local function SetTrackingOn(i)
	local f = C_Minimap and C_Minimap.SetTracking or SetTracking
	if f then pcall(f, i, true) end
end

local function SaveTracking()
	if not trackingReady or db.keepTracking == false then return end
	local on = {}
	for i = 1, NumTracking() do
		local name, active, isSpell = TrackingInfo(i)
		if name and active and isSpell then table.insert(on, name) end
	end
	db.tracking = db.tracking or {}
	db.tracking[CharKey()] = on
end

local function RestoreTracking()
	if db.keepTracking == false then return end
	local want = db.tracking and db.tracking[CharKey()]
	if not want or #want == 0 then return end
	if UnitIsDeadOrGhost("player") then return end
	for _, wanted in ipairs(want) do
		for i = 1, NumTracking() do
			local name, active = TrackingInfo(i)
			if name == wanted then
				if not active then SetTrackingOn(i) end
				break
			end
		end
	end
end

------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({
	"ADDON_LOADED", "PLAYER_LOGIN", "GUILD_ROSTER_UPDATE", "PLAYER_MONEY", "PLAYER_GUILD_UPDATE",
	"MINIMAP_UPDATE_TRACKING",
	"GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
}) do
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, arg)
	if event == "ADDON_LOADED" then
		if arg == ADDON then
			GildepanelDB = GildepanelDB or {}
			db = GildepanelDB
		end
		return
	end
	if not db then return end
	if event == "PLAYER_LOGIN" then
		BuildMini()
		if db.cameraMax then SetCamera(db.cameraMax) end
		C_Timer.After(3, RestoreTracking)
		C_Timer.After(10, function()
			RestoreTracking()
			-- Let the game catch up before saving changes again.
			C_Timer.After(2, function() trackingReady = true SaveTracking() end)
		end)
		-- Open unless closed last time; without the minimap button it is the way in.
		if db.shown ~= false then OpenPanel() end
		C_Timer.NewTicker(5, function() RefreshMini() end)
		C_Timer.NewTicker(60, CheckWarning)
		C_Timer.After(25, CheckWarning)
		Snapshot()
		C_Timer.NewTicker(1, function() if not checking then Snapshot() end end)
		return
	elseif event == "MINIMAP_UPDATE_TRACKING" then
		SaveTracking()
		return
	elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
		guildDirty = true
		return
	elseif event == "PLAYER_MONEY" then
		-- A payment changes your place among the favourites too. Skatteverket
		-- books it in the same event; look a moment later.
		guildDirty = true
		C_Timer.After(0.2, Refresh)
		CheckPayment()
		return
	elseif event == "GUILDBANKFRAME_OPENED" or event == "GUILDBANKFRAME_CLOSED" then
		bankOpen = event == "GUILDBANKFRAME_OPENED"
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
		local T = Enum and Enum.PlayerInteractionType
		if not (T and arg == T.GuildBanker) then return end
		bankOpen = event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
	end
	Refresh()
end)

SLASH_GILDEPANEL1 = "/gildepanel"
SLASH_GILDEPANEL2 = "/gpanel"
SlashCmdList.GILDEPANEL = function(msg)
	local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "" then
		Toggle()
	elseif cmd == "kompakt" or cmd == "compact" then
		db.compact = db.compact == false
		expanded = db.compact == false
		Print(db.compact and "panelen visar en kompakt rad och öppnas när musen är över den." or "panelen är alltid helt öppen.")
		Refresh()
	elseif cmd == "lås" or cmd == "lock" then
		db.locked = not db.locked
		Print(db.locked and "panelen är låst." or "panelen kan flyttas.")
	elseif cmd == "minimap" then
		db.hideMinimap = db.hideMinimap == false
		if mini then SetVisible(mini, not db.hideMinimap) end
		Print(db.hideMinimap and "minimapknappen är dold." or "minimapknappen visas.")
	elseif cmd == "skala" or cmd == "scale" then
		local s = tonumber((rest:gsub(",", ".")))
		if not s or s < 0.5 or s > 2 then Print("så här: /gpanel skala 0.9 (mellan 0.5 och 2)") return end
		local old = db.scale or 1
		db.scale = s
		-- The saved corner is in the frame's own scaled units: convert it so
		-- the panel stays on the same spot of the screen.
		if db.pos and db.pos[1] == "TOPLEFT" and db.pos[2] == "BOTTOMLEFT" then
			db.pos[3], db.pos[4] = db.pos[3] * old / s, db.pos[4] * old / s
		end
		if frame then
			frame:SetScale(s)
			if db.pos then
				frame:ClearAllPoints()
				frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
			end
		end
	elseif cmd == "återställ" or cmd == "reset" then
		db.pos, db.scale = nil, 1
		if frame then
			frame:SetScale(1)
			DefaultPosition()
			if frame:IsShown() then SavePosition() end
		end
		Print("panelen är tillbaka på sin plats.")
	elseif cmd == "addons" or cmd == "mods" then
		ToggleHub()
	elseif cmd == "kamera" or cmd == "camera" then
		if rest == "" then
			Print("längsta kameraavstånd: " .. CameraText(GetCamera()) .. ". Ändra med /gpanel kamera 2.6, /gpanel kamera max eller /gpanel kamera standard.")
		elseif rest == "standard" or rest == "default" or rest == "reset" then
			db.cameraMax = nil
			Print("längsta kameraavstånd tillbaka på spelets eget: " .. CameraText(SetCamera(DefaultCamera())) .. ".")
		else
			local v = rest == "max" and CAMERA_MAX or tonumber((rest:gsub(",", ".")))
			if not v then Print("så här: /gpanel kamera 2.6 (mellan 1 och 4), max eller standard.") return end
			local got = ChooseCamera(v)
			Print("längsta kameraavstånd: " .. CameraText(got) .. ".")
		end
		if hub and hub:IsShown() then RefreshHub() end
	elseif cmd == "firande" or cmd == "fanfare" then
		if rest == "test" then
			local was = db.celebrate
			db.celebrate = true
			Celebrate(123456, "neutral", "good")
			db.celebrate = was
		elseif rest == "test2" then
			local was = db.celebrate
			db.celebrate = true
			Celebrate(4321, "good", "good")
			db.celebrate = was
		elseif rest == "ljud" or rest == "sound" then
			db.celebrateQuiet = not db.celebrateQuiet
			Print(db.celebrateQuiet and "firandet är tyst." or "firandet har ljud.")
		else
			db.celebrate = db.celebrate == false
			Print(db.celebrate and "firar när du betalar skatt. Prova med /gpanel firande test." or "inget firande när du betalar skatt.")
		end
	elseif cmd == "spårning" or cmd == "tracking" then
		db.keepTracking = db.keepTracking == false
		if db.keepTracking then SaveTracking() end
		Print(db.keepTracking and "spårningen (örter, malm ...) slås på igen när du loggar in." or "spårningen lämnas som spelet sätter den vid inloggning.")
		if hub and hub:IsShown() then RefreshHub() end
	elseif cmd == "varning" or cmd == "warn" then
		db.warn = db.warn == false
		Print(db.warn and "varnar en timme speltid innan ställningen sjunker." or "inga förvarningar.")
	else
		Print("/gpanel visar panelen. /gpanel addons, /gpanel kompakt, /gpanel lås, /gpanel minimap, /gpanel kamera 2.6, /gpanel skala 0.9, /gpanel återställ, /gpanel varning, /gpanel spårning.")
	end
end
