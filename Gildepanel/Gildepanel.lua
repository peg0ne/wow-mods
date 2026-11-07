-- Gildepanel: a panel and a minimap button for THÖNDERSTÖRM.
-- It only reads what Skatteverket (SkatteverketDB, SkatteverketCharDB) and
-- Swedbank (SwedbankCharDB) keep in their saved data, which those addons
-- update while you play. It never writes to them and sends no messages;
-- the buttons run the addons' own slash commands.
--
-- The panel shows as a compact bar and opens to the full panel while the
-- mouse is over it (/gpanel kompakt turns that off). Your own tax is read
-- twice a second; the guild figures are worked out again only when the
-- roster changes, after a payment, or every 30 seconds.

local ADDON = ...
local GUILD = "THÖNDERSTÖRM"
local GOOD, NEGATIVE, WEEK = 48 * 3600, 7 * 86400, 7 * 86400
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

-- Same rule as Skatteverket: good up to 48 hours unpaid, neutral up to a week.
local function Standing(m)
	if not m or not m.debtSince then return "good" end
	local age = time() - m.debtSince
	if age <= GOOD then return "good" end
	if age < NEGATIVE then return "neutral" end
	return "negative"
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
	table.sort(list, function(a, b)
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

local function RunSlash(key, msg)
	local fn = SlashCmdList and SlashCmdList[key]
	if fn then fn(msg or "") return true end
	Print(key == "SWEDBANK" and "Swedbank är inte på." or "Skatteverket är inte på.")
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
	local s = { c = c, owed = c.owed or 0, standing = Standing(c), ok = true }
	s.debt = c.debtSince and s.owed >= 1 and (time() - c.debtSince) or nil
	if s.debt then
		if s.standing == "good" then
			s.next = GOOD - s.debt
			s.note = "Blir |cffffd100Neutral|r om " .. Duration(s.next) .. " om du inte betalar."
			s.short = "Neutral om " .. Duration(s.next)
		elseif s.standing == "neutral" then
			s.next = NEGATIVE - s.debt
			s.note = "Blir |cffff4040Negativ|r om " .. Duration(s.next) .. ". Besök gildebanken."
			s.short = "|cffff4040Negativ om " .. Duration(s.next) .. "|r"
		else
			s.note = "|cffff4040Obetald i " .. Duration(s.debt) .. ". Besök gildebanken.|r"
			s.short = "|cffff4040Obetald i " .. Duration(s.debt) .. "|r"
		end
	elseif s.owed <= -1 then
		s.note = "Inget obetalt. Kredit hos gildet: " .. Money(-s.owed)
		s.short = "Inget obetalt"
	else
		s.note = "Inget obetalt; du ligger bra till."
		s.short = "Inget obetalt"
	end
	s.bar = s.debt and math.min(s.debt / NEGATIVE, 1) or 0
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

local Refresh, ClosePanel

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
	-- its X, /gpanel or the minimap button.

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

	-- Skatteverket
	Section(body, "Skatteverket", -34)
	body.standing = Text(body, "GameFontNormalLarge", "TOPLEFT", PAD, -58)
	body.rate = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	body.rate:SetPoint("TOPRIGHT", -PAD, -61)
	body.note = Text(body, "GameFontHighlightSmall", "TOPLEFT", PAD, -82)
	body.note:SetWidth(W - 2 * PAD)
	-- Debt age: the bar fills over a week, with a mark where 48 hours ends.
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

local function RefreshTax(s)
	local compact, body = frame.compact, frame.body
	local standing = StandingText(s)
	compact.standing:SetText(standing)
	compact.owed:SetText(s.ok and (s.owed >= 1 and ("Skyldig " .. Money(s.owed)) or "") or "")
	compact.note:SetText(s.short)
	compact.bar:SetValue(s.bar or 0)
	if s.color then compact.bar:SetStatusBarColor(s.color[1], s.color[2], s.color[3]) end
	if not expanded then return end

	body.standing:SetText(standing)
	body.note:SetText(s.note)
	body.bar:SetValue(s.bar or 0)
	if s.color then body.bar:SetStatusBarColor(s.color[1], s.color[2], s.color[3]) end
	if not s.ok then
		body.rate:SetText("")
		for _, fs in ipairs({ body.owed, body.income, body.paid, body.last }) do fs:SetText("-") end
		body.pay:Disable()
		return
	end
	local c = s.c
	body.rate:SetText(format("Skattesats %g %%", ((SkatteverketDB and SkatteverketDB.rate) or 0.05) * 100))
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
	if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
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
	mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
		if button == "RightButton" then RunSlash("SKATTEVERKET", "") else Toggle() end
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
			if s.next then GameTooltip:AddDoubleLine("Nästa steg ned om", Duration(s.next), 1, 1, 1, 1, 0.82, 0) end
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Vänsterklick: panelen   Högerklick: /skatt   Dra: flytta", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
	PlaceMini()
	if db.hideMinimap then mini:Hide() end
	RefreshMini()
end

------------------------------------------------------------------------
-- A heads-up in chat 6 hours before the standing drops a step.

local warned = {}
local function CheckWarning()
	if db.warn == false then return end
	local c = SkatteverketCharDB
	if not c or not InGuild() or not c.debtSince or (c.owed or 0) < 1 then return end
	local age = time() - c.debtSince
	for _, step in ipairs({ { GOOD, "|cffffd100Neutral|r" }, { NEGATIVE, "|cffff4040Negativ|r" } }) do
		local left, key = step[1] - age, c.debtSince .. ":" .. step[1]
		if left > 0 and left <= 6 * 3600 and not warned[key] then
			warned[key] = true
			Print(format("din ställning blir %s om %s. Betala %s vid gildebanken för att behålla den.", step[2], Duration(left), Money(c.owed)))
		end
	end
end

------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({
	"ADDON_LOADED", "PLAYER_LOGIN", "GUILD_ROSTER_UPDATE", "PLAYER_MONEY", "PLAYER_GUILD_UPDATE",
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
		if db.shown then OpenPanel() end
		C_Timer.NewTicker(5, function() RefreshMini() end)
		C_Timer.NewTicker(60, CheckWarning)
		C_Timer.After(25, CheckWarning)
		return
	elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
		guildDirty = true
		return
	elseif event == "PLAYER_MONEY" then
		-- A payment changes your place among the favourites too. Skatteverket
		-- books it in the same event; look a moment later.
		guildDirty = true
		C_Timer.After(0.2, Refresh)
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
		db.hideMinimap = not db.hideMinimap
		if mini then SetVisible(mini, not db.hideMinimap) end
		Print(db.hideMinimap and "minimapknappen är dold." or "minimapknappen visas.")
	elseif cmd == "skala" or cmd == "scale" then
		local s = tonumber((rest:gsub(",", ".")))
		if not s or s < 0.5 or s > 2 then Print("så här: /gpanel skala 0.9 (mellan 0.5 och 2)") return end
		db.scale = s
		if frame then
			frame:SetScale(s)
			if frame:IsShown() then SavePosition() end
		end
	elseif cmd == "återställ" or cmd == "reset" then
		db.pos, db.scale = nil, 1
		if frame then
			frame:SetScale(1)
			DefaultPosition()
			if frame:IsShown() then SavePosition() end
		end
		Print("panelen är tillbaka på sin plats.")
	elseif cmd == "varning" or cmd == "warn" then
		db.warn = db.warn == false
		Print(db.warn and "varnar 6 timmar innan ställningen sjunker." or "inga förvarningar.")
	else
		Print("/gpanel visar panelen. /gpanel kompakt, /gpanel lås, /gpanel minimap, /gpanel skala 0.9, /gpanel återställ, /gpanel varning.")
	end
end
