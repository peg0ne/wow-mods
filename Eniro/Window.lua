-- Eniro, the /eniro window, in the style of Skatteverket's panel: online
-- guild members, same zone first, then nearest and closest in level.
-- Filters: everyone, my zone, my level (±5). Click a row to select it,
-- then whisper or invite. The box at the bottom turns position sharing on.

local _, ns = ...

local ROWS, ROW_H = 16, 18
local WIDTH = 700
local COLS = { 200, 60, 220, 180 }
local HEADER = { "Medlem", "Nivå", "Zon", "Avstånd" }
local FILTERS = { { "all", "Alla online" }, { "zone", "Min zon" }, { "level", "Min nivå ±5" } }

local frame, rows, list = nil, {}, {}
local offset, selected = 0, nil

local function Text(parent, template, ...)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetPoint(...)
	fs:SetJustifyH("LEFT")
	return fs
end

local function Button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

local function ClassName(row)
	local color = row.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[row.classFile]
	if not color then return row.name end
	return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, row.name)
end

local function LevelText(level)
	local diff = (level or 0) - UnitLevel("player")
	local color = GetQuestDifficultyColor and GetQuestDifficultyColor(level or 0)
	if not color then return tostring(level or "?") end
	return string.format("|cff%02x%02x%02x%d|r", color.r * 255, color.g * 255, color.b * 255, level or 0), diff
end

local function DistanceCell(row)
	if row.distance then return ns.DistanceText(row.distance) end
	if row.pos then return "|cff999999delar, annan kontinent|r" end
	if row.sameZone then return "|cff40ff40samma zon|r" end
	return ""
end

local function SetFilter(filter)
	ns.char.filter, offset, selected = filter, 0, nil
	ns.RefreshWindow()
end

-- The look of Skatteverket's panel: the game's portrait window (like the
-- Character window) with the guild's lightning bolt from Skatteverket's
-- art, the title on the title bar, a recessed inset and tabs along the
-- bottom edge. Falls back to the old dialog look on a client without the
-- template, as Skatteverket does.
local function HasTemplate(name)
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then return C_XMLUtil.GetTemplateInfo(name) ~= nil end
	return true
end

local function Panel(name, titleText)
	local ok, f = false, nil
	if HasTemplate("ButtonFrameTemplate") then ok, f = pcall(CreateFrame, "Frame", name, UIParent, "ButtonFrameTemplate") end
	if ok and f then
		local bolt = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Skatteverket")
		local art = bolt and "Interface\\AddOns\\Skatteverket\\Media\\Bolt" or "Interface\\Icons\\Spell_Nature_Lightning"
		local portrait = f.portrait or f.Portrait or (f.PortraitContainer and f.PortraitContainer.portrait)
			or _G[name .. "Portrait"]
		if f.SetPortraitToAsset then
			f:SetPortraitToAsset(art)
		elseif portrait then
			portrait:SetTexture(art)
		end
		if portrait then portrait:Show() end
		local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
		if title then title:SetText(titleText) end
		return f, true
	end
	f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	local header = f:CreateTexture(nil, "ARTWORK")
	header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	header:SetSize(320, 64)
	header:SetPoint("TOP", 0, 12)
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", header, "TOP", 0, -14)
	title:SetText(titleText)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)
	return f, false
end

-- A tab under the window, as on the Character window; the first at the
-- left edge, the rest after it.
local function Tab(f, i, label, onClick)
	local name = f:GetName() .. "Tab" .. i
	local b
	for _, template in ipairs({ "CharacterFrameTabButtonTemplate", "PanelTabButtonTemplate" }) do
		if HasTemplate(template) then
			local ok, t = pcall(CreateFrame, "Button", name, f, template)
			if ok and t then
				b = t
				b.isTab = true
				break
			end
		end
	end
	if not b then
		b = CreateFrame("Button", name, f, "UIPanelButtonTemplate")
		b:SetSize(120, 22)
	end
	b:SetID(i)
	b:SetText(label)
	if b.isTab and PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 0) end
	b:SetScript("OnClick", function()
		onClick()
		if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
	end)
	if i == 1 then
		b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
	else
		b:SetPoint("LEFT", _G[f:GetName() .. "Tab" .. (i - 1)], "RIGHT", b.isTab and -15 or 4, 0)
	end
	return b
end

local function SelectTab(tab, on)
	if tab.isTab and PanelTemplates_SelectTab and PanelTemplates_DeselectTab then
		if on then PanelTemplates_SelectTab(tab) else PanelTemplates_DeselectTab(tab) end
	elseif on then
		tab:Disable()
	else
		tab:Enable()
	end
end

local function Build()
	local classic
	frame, classic = Panel("EniroFrame", "Eniro")
	frame:SetSize(WIDTH, 500)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "EniroFrame")
	-- Below the portrait and title bar; buttons in the strip under the inset.
	local dy, bottom, left = classic and -12 or 0, classic and 4 or 18, classic and 66 or 24

	frame.heading = Text(frame, "GameFontNormal", "TOPLEFT", left, -34)
	frame.heading:SetText("Var är gillet?")

	local x = 24
	for c = 1, #COLS do
		Text(frame, "GameFontNormalSmall", "TOPLEFT", x, -56 + dy):SetText(HEADER[c])
		x = x + COLS[c]
	end

	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetSize(WIDTH - 40, ROW_H)
		row:SetPoint("TOPLEFT", 20, -70 + dy - (i - 1) * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.cells = {}
		local cx = 4
		for c = 1, #COLS do
			local fs = Text(row, "GameFontHighlightSmall", "LEFT", cx, 0)
			fs:SetWidth(COLS[c] - 6)
			fs:SetWordWrap(false)
			row.cells[c] = fs
			cx = cx + COLS[c]
		end
		row:SetScript("OnClick", function(self)
			if self.item then
				selected = self.item.name
				ns.RefreshWindow()
			end
		end)
		rows[i] = row
	end

	frame.count = Text(frame, "GameFontDisableSmall", "TOPLEFT", 24, -366 + dy)
	frame.count:SetWidth(WIDTH - 48)

	local act = CreateFrame("Frame", nil, frame)
	act:SetPoint("TOPLEFT", 24, -396 + dy)
	act:SetSize(WIDTH - 48, 24)
	act.label = Text(act, "GameFontHighlightSmall", "LEFT", 0, 0)
	act.label:SetWidth(330)
	act.label:SetWordWrap(false)
	act.whisper = Button(act, "Viska", 100, function()
		if selected and ChatFrame_SendTell then ChatFrame_SendTell(selected) end
	end)
	act.whisper:SetPoint("LEFT", act.label, "RIGHT", 8, 0)
	act.invite = Button(act, "Bjud in", 100, function()
		if selected then ns.Invite(selected) end
	end)
	act.invite:SetPoint("LEFT", act.whisper, "RIGHT", 8, 0)
	frame.act = act

	local share = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	share:SetSize(24, 24)
	share:SetPoint("TOPLEFT", 20, -424 + dy)
	share:SetScript("OnClick", function(self) ns.SetSharing(self:GetChecked()) end)
	frame.share = share
	Text(frame, "GameFontHighlightSmall", "LEFT", share, "RIGHT", 4, 0)
		:SetText("Dela min position med gillet (syns på världskartan för medlemmar med Eniro)")

	local refresh = Button(frame, "Uppdatera", 100, function() ns.Ask() ns.RefreshWindow() end)
	refresh:SetPoint("BOTTOMLEFT", 24, bottom)
	frame.filters = {}
	local tx = refresh
	for _, spec in ipairs(FILTERS) do
		local b = Button(frame, spec[2], 120, function() SetFilter(spec[1]) end)
		b:SetPoint("LEFT", tx, "RIGHT", 8, 0)
		frame.filters[spec[1]] = b
		tx = b
	end

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta, #list - ROWS))
		ns.RefreshWindow()
	end)
	-- Distances change as you move.
	frame:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed > 2 then
			self.elapsed = 0
			ns.RefreshWindow()
		end
	end)
	frame:Hide()
end

function ns.RefreshWindow()
	if not frame or not frame:IsShown() then return end
	local filter = ns.char.filter
	for key, b in pairs(frame.filters) do
		if key == filter then b:Disable() else b:Enable() end
	end
	frame.share:SetChecked(ns.Sharing())
	list = ns.Rows(filter)
	local stillThere = false
	for _, row in ipairs(list) do
		if row.name == selected then stillThere = true end
	end
	if not stillThere then selected = nil end
	offset = math.max(0, math.min(offset, #list - ROWS))
	for i, row in ipairs(rows) do
		local item = list[i + offset]
		row.item = item
		if item then
			row.cells[1]:SetText(ClassName(item))
			row.cells[2]:SetText((LevelText(item.level)))
			row.cells[3]:SetText(item.sameZone and ("|cff40ff40" .. (item.zone or "") .. "|r") or (item.zone or ""))
			row.cells[4]:SetText(DistanceCell(item))
			if item.name == selected then row:LockHighlight() else row:UnlockHighlight() end
			row:Show()
		else
			row:Hide()
		end
	end

	local act = frame.act
	act.label:SetText(selected and ("Valt: " .. selected) or "Klicka på en medlem för att viska eller bjuda in.")
	if selected then act.whisper:Enable() act.invite:Enable() else act.whisper:Disable() act.invite:Disable() end

	local sharing = 0
	for _ in pairs(ns.positions) do sharing = sharing + 1 end
	if #list == 0 then
		frame.count:SetText(filter == "all" and "Ingen annan i gillet är online just nu." or "Ingen online matchar filtret.")
	else
		local range = #list > ROWS and string.format("Visar %d-%d av %d. ", offset + 1, math.min(offset + ROWS, #list), #list) or ""
		frame.count:SetText(range .. string.format("%d online, %d delar sin position. Nivåfärgen visar hur långt ifrån din nivå de är.", #list, sharing))
	end
end

function ns.ToggleWindow()
	if not frame then Build() end
	if frame:IsShown() then frame:Hide() return end
	frame:Show()
	ns.Ask()
	ns.RefreshWindow()
end
