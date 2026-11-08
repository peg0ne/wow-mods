-- Arbetsförmedlingen, the /uppdrag window, in the style of Skatteverket's
-- panel. Three views, switched with the tabs at the bottom:
--   Delade        quests in your log that online members also have
--   Andras        quests online members have that you do not
--   Platsbanken   group listings: post your own, apply to others'
-- Green names have finished the objectives. Hover a row for details.
-- Clicking a quest selects it, and "Annonsera i Platsbanken" turns it
-- into a listing.

local _, ns = ...

local ROWS, ROW_H = 16, 18
local WIDTH = 770
local HEADERS = {
	quests = { { "Uppdrag", 250 }, { "Zon", 140 }, { "Medlemmar", 330 } },
	plats = { { "Annons", 250 }, { "Söker", 140 }, { "Annonsör", 330 } },
}
local TITLES = {
	shared = "Uppdrag du delar med medlemmar online",
	others = "Uppdrag medlemmar online har som du inte har",
	plats = "Platsbanken: grupper som söker folk",
}

local frame, rows, headers, list = nil, {}, {}, {}
local offset, mode = 0, "shared"
local selectedQuest, selectedPoster, draftQuest

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

local function Input(parent, width, numeric)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	if numeric then
		box:SetNumeric(true)
		box:SetMaxLetters(1)
	else
		box:SetMaxLetters(80)
	end
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	return box
end

local function SetShown(region, shown)
	if shown then region:Show() else region:Hide() end
end

local function MemberText(m)
	return m.done and ("|cff40ff40" .. m.name .. "|r") or m.name
end

function ns.QuestLabel(q)
	if not q.title then return string.format("Uppdrag #%d (hämtar namn ...)", q.id) end
	return string.format("[%s] %s", q.level or "?", q.title)
end

-- Members on a quest, one tooltip line each.
function ns.AddMemberLines(tooltip, members)
	for _, m in ipairs(members) do
		if m.done then
			tooltip:AddLine(m.name .. ": klart", 0.25, 1, 0.25)
		else
			tooltip:AddLine(m.name .. ": pågår", 1, 1, 1)
		end
	end
end

local function QuestName(id)
	local q = id and ns.QuestInfo(id)
	return q and q.title or (id and ("uppdrag #" .. id))
end

local function ShowTooltip(row)
	local item = row.item
	if not item then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if mode ~= "plats" then
		GameTooltip:AddLine(ns.QuestLabel(item))
		if mode == "shared" then
			GameTooltip:AddLine(item.done and "Du: klart, lämna in" or "Du: pågår", 1, 1, 1)
		else
			GameTooltip:AddLine("Du har inte det här uppdraget.", 0.7, 0.7, 0.7)
		end
		ns.AddMemberLines(GameTooltip, item.members)
		GameTooltip:AddLine("Klicka för att välja, sedan Annonsera i Platsbanken.", 0.6, 0.6, 0.6)
	elseif item.kind == "applicant" then
		GameTooltip:AddLine(item.name)
		GameTooltip:AddLine("Vill vara med som " .. ns.ROLE_NAMES[item.app.role] .. " (" .. ns.Minutes(item.app.at) .. ")", 1, 1, 1)
		if item.app.invited then GameTooltip:AddLine("Inbjuden.", 0.25, 1, 0.25) end
		GameTooltip:AddLine("Vänsterklick: bjud in. Högerklick: ta bort.", 0.6, 0.6, 0.6)
	else
		local l = item.listing
		GameTooltip:AddLine(l.text)
		GameTooltip:AddLine("Söker " .. ns.NeedsText(l), 1, 1, 1)
		if item.kind == "listing" then
			GameTooltip:AddLine(string.format("%s, nivå %s, lagd %s", item.name, l.level or "?", ns.Minutes(l.posted)), 1, 1, 1)
		else
			GameTooltip:AddLine("Din annons, lagd " .. ns.Minutes(l.posted), 1, 1, 1)
		end
		if l.quest then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Uppdrag: " .. QuestName(l.quest), 0.4, 0.8, 1)
			if ns.mine[l.quest] then GameTooltip:AddLine("Du har uppdraget.", 0.25, 1, 0.25) end
			ns.AddMemberLines(GameTooltip, ns.MembersOn(l.quest))
		end
		if item.kind == "listing" then GameTooltip:AddLine("Klicka för att välja, sedan Sök som ...", 0.6, 0.6, 0.6) end
	end
	GameTooltip:Show()
end

local function OnRowClick(row, button)
	local item = row.item
	if not item then return end
	if mode ~= "plats" then
		selectedQuest = item.id
	elseif item.kind == "applicant" then
		if button == "RightButton" then ns.Reject(item.name) else ns.Invite(item.name) end
	elseif item.kind == "listing" then
		selectedPoster = item.name
	end
	ns.RefreshWindow()
end

local function SetMode(newMode)
	mode, offset = newMode, 0
	local cols = HEADERS[mode == "plats" and "plats" or "quests"]
	for c, fs in ipairs(headers) do fs:SetText(cols[c][1]) end
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
	frame, classic = Panel("ArbetsformedlingenFrame", "Arbetsförmedlingen")
	frame:SetSize(WIDTH, 520)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "ArbetsformedlingenFrame")
	-- Below the portrait and title bar; buttons in the strip under the inset.
	local dy, bottom, left = classic and -12 or 0, classic and 4 or 18, classic and 66 or 24

	frame.heading = Text(frame, "GameFontNormal", "TOPLEFT", left, -34)
	local x = 24
	for c, col in ipairs(HEADERS.quests) do
		headers[c] = Text(frame, "GameFontNormalSmall", "TOPLEFT", x, -56 + dy)
		x = x + col[2]
	end

	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetSize(WIDTH - 40, ROW_H)
		row:SetPoint("TOPLEFT", 20, -70 + dy - (i - 1) * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.cells = {}
		local cx = 4
		for c, col in ipairs(HEADERS.quests) do
			local fs = Text(row, "GameFontHighlightSmall", "LEFT", cx, 0)
			fs:SetWidth(col[2] - 6)
			fs:SetWordWrap(false)
			row.cells[c] = fs
			cx = cx + col[2]
		end
		row:SetScript("OnEnter", ShowTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:SetScript("OnClick", OnRowClick)
		rows[i] = row
	end

	frame.count = Text(frame, "GameFontDisableSmall", "TOPLEFT", 24, -366 + dy)
	frame.count:SetWidth(WIDTH - 48)

	-- Platsbanken: the form for your own listing.
	local form = CreateFrame("Frame", nil, frame)
	form:SetPoint("TOPLEFT", 24, -398 + dy)
	form:SetSize(WIDTH - 48, 24)
	Text(form, "GameFontNormalSmall", "LEFT", 0, 0):SetText("Ny annons")
	form.text = Input(form, 200)
	form.text:SetPoint("LEFT", 70, 0)
	local fx, boxes = form.text, {}
	for _, spec in ipairs({ { "tank", "Tank", "1" }, { "heal", "Helare", "1" }, { "dps", "DPS", "3" } }) do
		local label = Text(form, "GameFontNormalSmall", "LEFT", fx, "RIGHT", 14, 0)
		label:SetText(spec[2])
		local box = Input(form, 22, true)
		box:SetPoint("LEFT", label, "RIGHT", 8, 0)
		box:SetText(spec[3])
		boxes[spec[1]] = box
		fx = box
	end
	form.boxes = boxes
	form.post = Button(form, "Annonsera", 100, function()
		local text = form.text:GetText()
		local quest = draftQuest and QuestName(draftQuest) and text:find(QuestName(draftQuest), 1, true) and draftQuest or nil
		if ns.Post(text, boxes.tank:GetText(), boxes.heal:GetText(), boxes.dps:GetText(), quest) then
			form.text:ClearFocus()
			draftQuest = nil
		end
	end)
	form.post:SetPoint("LEFT", fx, "RIGHT", 12, 0)
	form.remove = Button(form, "Ta bort min", 100, function() ns.Unpost("din annons har tagits bort från Platsbanken.") end)
	form.remove:SetPoint("LEFT", form.post, "RIGHT", 8, 0)
	frame.form = form

	-- What can be done with the selected row.
	local act = CreateFrame("Frame", nil, frame)
	act:SetPoint("TOPLEFT", 24, -430 + dy)
	act:SetSize(WIDTH - 48, 24)
	act.label = Text(act, "GameFontHighlightSmall", "LEFT", 0, 0)
	act.label:SetWidth(330)
	act.label:SetWordWrap(false)
	act.advertise = Button(act, "Annonsera i Platsbanken", 180, function()
		if not selectedQuest then return end
		local name = QuestName(selectedQuest)
		draftQuest = selectedQuest
		SetMode("plats")
		frame.form.text:SetText(name)
		frame.form.text:SetFocus()
	end)
	act.advertise:SetPoint("LEFT", act.label, "RIGHT", 8, 0)
	act.roles = {}
	local ax = act.label
	for _, role in ipairs({ "T", "H", "D" }) do
		local b = Button(act, "Sök som " .. ns.ROLE_NAMES[role], 120, function()
			if selectedPoster then ns.Apply(selectedPoster, role) end
		end)
		b:SetPoint("LEFT", ax, "RIGHT", 8, 0)
		act.roles[role] = b
		ax = b
	end
	frame.act = act

	local refresh = Button(frame, "Uppdatera", 100, function() ns.Ask() ns.RefreshWindow() end)
	refresh:SetPoint("BOTTOMLEFT", 24, bottom)
	frame.tabs = {}
	for i, spec in ipairs({ { "shared", "Delade uppdrag" }, { "others", "Andras uppdrag" }, { "plats", "Platsbanken" } }) do
		frame.tabs[spec[1]] = Tab(frame, i, spec[2], function() SetMode(spec[1]) end)
	end

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta, #list - ROWS))
		ns.RefreshWindow()
	end)
	-- Ages in Platsbanken change with time.
	frame:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed > 10 then
			self.elapsed = 0
			if mode == "plats" then ns.RefreshWindow() end
		end
	end)
	frame:Hide()
end

local function FillQuestRow(row, q)
	local names = {}
	for _, m in ipairs(q.members) do table.insert(names, MemberText(m)) end
	local questText = ns.QuestLabel(q)
	if q.done then questText = "|cff40ff40" .. questText .. "|r" end
	if not q.title then questText = "|cff999999" .. questText .. "|r" end
	row.cells[1]:SetText(questText)
	row.cells[2]:SetText(q.zone or "")
	row.cells[3]:SetText(string.format("(%d) %s", #q.members, table.concat(names, ", ")))
	if q.id == selectedQuest then row:LockHighlight() else row:UnlockHighlight() end
end

local function FillPlatsRow(row, item)
	row:UnlockHighlight()
	if item.kind == "applicant" then
		local a = item.app
		row.cells[1]:SetText("    |cffffd100->|r " .. item.name)
		row.cells[2]:SetText(ns.ROLE_NAMES[a.role])
		row.cells[3]:SetText(a.invited and "|cff40ff40inbjuden|r" or "vänsterklick: bjud in, högerklick: ta bort")
		return
	end
	local l = item.listing
	local text = l.text
	if l.quest and ns.mine[l.quest] then text = "|cff40ff40" .. text .. "|r" end
	row.cells[2]:SetText(ns.NeedsText(l))
	if item.kind == "mine" then
		local n = 0
		for _ in pairs(l.applicants) do n = n + 1 end
		row.cells[1]:SetText("|cffffd100Din annons:|r " .. text)
		row.cells[3]:SetText(string.format("du, %s, %d sökande", ns.Minutes(l.posted), n))
	else
		local status = ""
		local applied = ns.applied[item.name]
		if applied then
			status = applied.invited and ", |cff40ff40du är inbjuden|r" or (", du har sökt som " .. ns.ROLE_NAMES[applied.role])
		end
		row.cells[1]:SetText(text)
		row.cells[3]:SetText(string.format("%s (%s), %s%s", item.name, l.level or "?", ns.Minutes(l.posted), status))
		if item.name == selectedPoster then row:LockHighlight() end
	end
end

local function RefreshActions()
	local act, plats = frame.act, mode == "plats"
	SetShown(frame.form, plats)
	if plats then
		frame.form.post:SetText(ns.myListing and "Uppdatera min" or "Annonsera")
		if ns.myListing then frame.form.remove:Enable() else frame.form.remove:Disable() end
	end
	SetShown(act.advertise, not plats)
	for _, b in pairs(act.roles) do SetShown(b, plats) end
	if not plats then
		act.label:SetText(selectedQuest and ("Valt: " .. (QuestName(selectedQuest) or "")) or "Klicka på ett uppdrag för att annonsera efter en grupp till det.")
		if selectedQuest then act.advertise:Enable() else act.advertise:Disable() end
		return
	end
	local l = selectedPoster and ns.listings[selectedPoster]
	if not l then selectedPoster = nil end
	act.label:SetText(l and string.format("Valt: %s hos %s", l.text, selectedPoster) or "Klicka på en annons för att söka till den.")
	for role, b in pairs(act.roles) do
		local key = ({ T = "tank", H = "heal", D = "dps" })[role]
		if l and (l[key] or 0) > 0 then b:Enable() else b:Disable() end
	end
end

function ns.RefreshWindow()
	if not frame or not frame:IsShown() then return end
	frame.heading:SetText(TITLES[mode])
	for key, b in pairs(frame.tabs) do SelectTab(b, key == mode) end
	if mode == "shared" then list = ns.Shared()
	elseif mode == "others" then list = ns.Wanted()
	else list = ns.PlatsRows() end
	offset = math.max(0, math.min(offset, #list - ROWS))
	for i, row in ipairs(rows) do
		local item = list[i + offset]
		row.item = item
		if item then
			if mode == "plats" then FillPlatsRow(row, item) else FillQuestRow(row, item) end
			row:Show()
		else
			row:Hide()
		end
	end
	-- Keep a hovered row's tooltip in step with the list.
	for _, row in ipairs(rows) do
		if row:IsShown() and GameTooltip:IsOwned(row) then ShowTooltip(row) end
	end
	RefreshActions()

	local others = ns.CountOthers()
	local range = #list > 0 and string.format("Visar %d-%d av %d (scrolla med mushjulet). ", offset + 1, math.min(offset + ROWS, #list), #list) or ""
	if mode == "plats" then
		frame.count:SetText(#list == 0 and "Inga annonser just nu. Lägg ut en nedan: vad ni ska göra och vilka ni behöver."
			or range .. "Grönt: annonser för uppdrag du har. Annonser försvinner efter en timme, när gruppen är full eller när annonsören loggar ut. /uppdrag tyst stänger av chattraderna.")
	elseif others == 0 then
		frame.count:SetText("Ingen annan online har Arbetsförmedlingen än. Tryck Uppdatera eller vänta tills medlemmar loggar in.")
	elseif #list == 0 then
		frame.count:SetText(string.format(mode == "shared" and "Du delar inga uppdrag med de %d medlemmar online som har addonen."
			or "De %d medlemmar online som har addonen har inga uppdrag som du saknar.", others))
	else
		frame.count:SetText(range .. string.format("%d medlemmar online har addonen. Grönt: målen klara. Håll musen över en rad för detaljer.", others))
	end
end

-- Toggle the window; with a view given, open on that view (or switch to it).
function ns.ToggleWindow(view)
	if not frame then Build() end
	if frame:IsShown() and (not view or view == mode) then frame:Hide() return end
	SetMode(view or mode)
	frame:Show()
	ns.ReadLog()
	ns.Ask()
	ns.RefreshWindow()
end
