-- Polisen, the /polisen window in the same dialog style as /uppdrag.
--   Efterlysta   reported players, most reports first
--   Händelser    every incident, newest first
-- Hover a wanted player for their victims. "Glöm" forgets a player on this
-- computer only (the guild keeps its own records).

local _, ns = ...

local ROWS, ROW_H = 16, 18
local WIDTH = 740
local COLS = { 200, 150, 110, 240 }
local HEADERS = {
	wanted = { "Efterlyst", "Klass, nivå", "Anmälningar", "Senast" },
	log = { "När", "Offer", "Gärningsman", "Plats" },
}

local frame, rows, headers, list = nil, {}, {}, {}
local offset, mode, selected = 0, "wanted", nil

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

local function ShowTooltip(row)
	local item = row.item
	if not item or mode ~= "wanted" then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(ns.ClassText(item.class, item.name))
	local race = item.race and (item.race .. " ") or ""
	GameTooltip:AddLine(string.format("%s%s, nivå %s", race, ns.ClassName(item.class), ns.LevelText(item.level)), 1, 1, 1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Offer:", 1, 0.5, 0.5)
	for victim, n in pairs(item.victims) do
		GameTooltip:AddLine(n > 1 and string.format("%s (%d gånger)", victim, n) or victim, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function SetMode(newMode)
	mode, offset, selected = newMode, 0, nil
	for c, fs in ipairs(headers) do fs:SetText(HEADERS[mode][c]) end
	ns.RefreshWindow()
end

local function Build()
	frame = CreateFrame("Frame", "PolisenFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetSize(WIDTH, 480)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PolisenFrame")

	local header = frame:CreateTexture(nil, "ARTWORK")
	header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	header:SetSize(260, 64)
	header:SetPoint("TOP", 0, 12)
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", header, "TOP", 0, -14)
	title:SetText("Polisen")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	frame.heading = Text(frame, "GameFontNormal", "TOPLEFT", 24, -34)

	local x = 24
	for c = 1, #COLS do
		headers[c] = Text(frame, "GameFontNormalSmall", "TOPLEFT", x, -56)
		headers[c]:SetText(HEADERS[mode][c])
		x = x + COLS[c]
	end

	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetSize(WIDTH - 40, ROW_H)
		row:SetPoint("TOPLEFT", 20, -70 - (i - 1) * ROW_H)
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
		row:SetScript("OnEnter", ShowTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:SetScript("OnClick", function(self)
			if self.item and mode == "wanted" then
				selected = self.item.key
				ns.RefreshWindow()
			end
		end)
		rows[i] = row
	end

	frame.count = Text(frame, "GameFontDisableSmall", "TOPLEFT", 24, -366)
	frame.count:SetWidth(WIDTH - 48)

	local act = CreateFrame("Frame", nil, frame)
	act:SetPoint("TOPLEFT", 24, -398)
	act:SetSize(WIDTH - 48, 24)
	act.label = Text(act, "GameFontHighlightSmall", "LEFT", 0, 0)
	act.label:SetWidth(420)
	act.label:SetWordWrap(false)
	act.forget = Button(act, "Glöm", 100, function()
		if selected then
			ns.Forget(selected)
			selected = nil
		end
	end)
	act.forget:SetPoint("LEFT", act.label, "RIGHT", 8, 0)
	frame.act = act

	local tx
	frame.tabs = {}
	for _, spec in ipairs({ { "wanted", "Efterlysta" }, { "log", "Händelser" } }) do
		local b = Button(frame, spec[2], 120, function() SetMode(spec[1]) end)
		if tx then b:SetPoint("LEFT", tx, "RIGHT", 8, 0) else b:SetPoint("BOTTOMLEFT", 24, 18) end
		frame.tabs[spec[1]] = b
		tx = b
	end
	local closeButton = Button(frame, "Stäng", 100, function() frame:Hide() end)
	closeButton:SetPoint("BOTTOMRIGHT", -24, 18)

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta, #list - ROWS))
		ns.RefreshWindow()
	end)
	frame:Hide()
end

function ns.RefreshWindow()
	if not frame or not frame:IsShown() then return end
	for key, b in pairs(frame.tabs) do
		if key == mode then b:Disable() else b:Enable() end
	end
	if mode == "wanted" then
		frame.heading:SetText("Efterlysta: fientliga spelare som dödat medlemmar (senaste 30 dagarna)")
		list = ns.Wanted()
	else
		frame.heading:SetText("Händelser")
		list = ns.Incidents()
	end
	local found = false
	for _, item in ipairs(list) do
		if item.key and item.key == selected then found = true end
	end
	if not found then selected = nil end
	offset = math.max(0, math.min(offset, #list - ROWS))
	for i, row in ipairs(rows) do
		local item = list[i + offset]
		row.item = item
		if item then
			local c = row.cells
			if mode == "wanted" then
				c[1]:SetText(ns.ClassText(item.class, item.name))
				c[2]:SetText(string.format("%s, %s", ns.ClassName(item.class), ns.LevelText(item.level)))
				c[3]:SetText(tostring(item.count))
				c[4]:SetText(string.format("%s, %s", item.last.victim, ns.Ago(item.last.time)))
			else
				c[1]:SetText(ns.Ago(item.time))
				c[2]:SetText(item.victim)
				c[3]:SetText(ns.ClassText(item.class, item.suspect))
				c[4]:SetText(item.zone)
			end
			if item.key and item.key == selected then row:LockHighlight() else row:UnlockHighlight() end
			row:Show()
		else
			row:Hide()
		end
	end
	for _, row in ipairs(rows) do
		if row:IsShown() and GameTooltip:IsOwned(row) then ShowTooltip(row) end
	end

	local act = frame.act
	if mode == "wanted" then
		act:Show()
		act.label:SetText(selected and ("Valt: " .. (ns.suspects[selected] and ns.suspects[selected].name or ""))
			or "Klicka på en efterlyst för att kunna glömma den (bara på den här datorn).")
		if selected then act.forget:Enable() else act.forget:Disable() end
	else
		act:Hide()
	end

	local range = #list > ROWS and string.format("Visar %d-%d av %d (scrolla med mushjulet). ", offset + 1, math.min(offset + ROWS, #list), #list) or ""
	if #list == 0 then
		frame.count:SetText("Inga anmälningar. När en fientlig spelare dödar någon i gillet som har Rättsmedicinalverket hamnar den här.")
	else
		frame.count:SetText(range .. string.format("Varning på skärmen: %s (/polisen larm). Andras observationer: %s (/polisen tyst).",
			ns.db.alarm and "på" or "av", ns.db.quiet and "dolda" or "visas"))
	end
end

function ns.ToggleWindow()
	if not frame then Build() end
	if frame:IsShown() then frame:Hide() return end
	frame:Show()
	SetMode(mode)
end
