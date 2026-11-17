-- Polisen, the /polisen window, in the style of Skatteverket's panel, with
-- two tabs at the top (0.4.1; they were under the window):
--   Efterlysta   reported players, most reports first
--   Händelser    every incident, newest first
-- Hover a wanted player for their victims. "Glöm" forgets a player on this
-- computer only (the guild keeps its own records).

local _, ns = ...

local ROWS, ROW_H = 16, 18
local WIDTH = 740
-- Column widths per tab: the incidents need room for the killer's name.
local COLS = {
	wanted = { 200, 150, 110, 240 },
	log = { 120, 180, 200, 200 },
}
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

-- Moves the headings and cells to the tab's column widths.
local function PlaceColumns()
	local x = 24
	for c, fs in ipairs(headers) do
		fs:SetText(HEADERS[mode][c])
		fs:SetPoint("TOPLEFT", x, fs.y)
		x = x + COLS[mode][c]
	end
	for _, row in ipairs(rows) do
		local cx = 4
		for c, fs in ipairs(row.cells) do
			fs:SetPoint("LEFT", cx, 0)
			fs:SetWidth(COLS[mode][c] - 6)
			cx = cx + COLS[mode][c]
		end
	end
end

local function SetMode(newMode)
	mode, offset, selected = newMode, 0, nil
	frame.tabs:Select(mode)
	PlaceColumns()
	ns.RefreshWindow()
end

local function Build()
	local classic
	frame, classic = Statskontoret.Window("PolisenFrame", "Polisen", WIDTH, 480)
	-- Below the portrait and title bar; buttons in the strip under the inset.
	local dy, left = classic and -12 or 0, classic and 66 or 24

	-- Tabs beside the portrait, where the other windows have their heading.
	frame.tabs = Statskontoret.Tabs(frame, { { "wanted", "Efterlysta" }, { "log", "Händelser" } }, SetMode)
	frame.tabs:SetPoint("TOPLEFT", left - 4, -28)

	for c = 1, #HEADERS.wanted do
		headers[c] = Text(frame, "GameFontNormalSmall", "TOPLEFT", 24, -56 + dy)
		headers[c].y = -56 + dy
	end
	Statskontoret.Rule(frame, 20, 20, -68 + dy, 0.2)

	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetSize(WIDTH - 40, ROW_H)
		row:SetPoint("TOPLEFT", 20, -70 + dy - (i - 1) * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		Statskontoret.Stripe(row, i)
		row.cells = {}
		for c = 1, #HEADERS.wanted do
			local fs = Text(row, "GameFontHighlightSmall", "LEFT", 4, 0)
			fs:SetWordWrap(false)
			row.cells[c] = fs
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

	frame.scroll = Statskontoret.ScrollMark(frame)
	frame.scroll:SetPoint("TOPRIGHT", -12, -72 + dy)
	frame.scroll:SetHeight(ROWS * ROW_H - 4)

	frame.count = Text(frame, "GameFontDisableSmall", "TOPLEFT", 24, -366 + dy)
	frame.count:SetWidth(WIDTH - 48)

	local act = CreateFrame("Frame", nil, frame)
	act:SetPoint("TOPLEFT", 24, -398 + dy)
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

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta, #list - ROWS))
		ns.RefreshWindow()
	end)
	frame:Hide()
end

function ns.RefreshWindow()
	if not frame or not frame:IsShown() then return end
	list = mode == "wanted" and ns.Wanted() or ns.Incidents()
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

	frame.scroll:Update(offset, ROWS, #list)
	if #list == 0 then
		frame.count:SetText("Inga anmälningar. När en fientlig spelare dödar någon i gillet som har Rättsmedicinalverket hamnar den här.")
	else
		local what = mode == "wanted" and "Fientliga spelare som dödat medlemmar de senaste 30 dagarna, flest anmälningar först."
			or "Varje gång en fientlig spelare dödat en medlem, nyast först."
		local range = #list > ROWS and string.format("  Visar %d-%d av %d.", offset + 1, math.min(offset + ROWS, #list), #list) or ""
		frame.count:SetText(what .. range)
	end
end

function ns.ToggleWindow()
	if not frame then Build() end
	if frame:IsShown() then frame:Hide() return end
	frame:Show()
	SetMode(mode)
end
