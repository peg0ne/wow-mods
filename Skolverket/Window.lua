-- Skolverket, the /skola window in the same dialog style as /uppdrag.
-- Three views, switched with the buttons at the bottom:
--   Recept       every recipe someone in the guild knows, with a search box
--   Cooldowns    profession cooldowns (transmutes, Mooncloth ...)
--   Medlemmar    everyone's professions and ranks
-- Green names are online, grey offline. Hover a recipe for the item and
-- all crafters; Shift-click links it in chat. Click a row to select it,
-- then "Fråga" whispers the best online crafter.

local _, ns = ...

local ROWS, ROW_H = 16, 18
local WIDTH = 770
local COLS = { 270, 150, 300 }
local HEADERS = {
	recept = { "Recept", "Yrke", "Kan tillverka" },
	cd = { "Recept", "Medlem", "Redo" },
	folk = { "Medlem", "Yrken", "Senast sedd" },
}
local TITLES = {
	recept = "Vem i gillet kan tillverka vad",
	cd = "Cooldowns i gillet",
	folk = "Gillets yrken",
}

local frame, rows, headers, list = nil, {}, {}, {}
local offset, mode = 0, "recept"
local selected   -- the selected row's item

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

local function PersonText(p)
	local name = p.me and "du" or p.name
	if p.me then return "|cffffd100" .. name .. "|r" end
	return p.online and ("|cff40ff40" .. name .. "|r") or ("|cff999999" .. name .. "|r")
end

local function Ago(seen)
	if not seen then return "okänt" end
	local s = time() - seen
	if s < 3600 then return "nyss" end
	if s < 86400 then return string.format("för %d h sedan", math.floor(s / 3600)) end
	return string.format("för %d d sedan", math.floor(s / 86400))
end

local function RecipeName(key)
	return ns.Name(key) or ("#" .. key:sub(2))
end

-- The online crafter to ask (not yourself), or nil.
local function BestOnline(people)
	for _, p in ipairs(people or {}) do
		if p.online and not p.me then return p.name end
	end
end

local function Whisper(name, key)
	if not name then return end
	if ChatFrame_SendTell then ChatFrame_SendTell(name) end
	local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
	if box and key then box:Insert("Hej! Kan du tillverka " .. ns.Link(key) .. "? ") end
end

local function ShowTooltip(row)
	local item = row.item
	if not item then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if mode == "recept" then
		local kind = item.key:sub(1, 1) == "i" and "item" or "spell"
		if not pcall(GameTooltip.SetHyperlink, GameTooltip, kind .. ":" .. item.key:sub(2)) then
			GameTooltip:AddLine(RecipeName(item.key))
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Kan tillverkas av:", 1, 0.6, 0.2)
		for _, c in ipairs(item.crafters) do
			local extra = c.rank and (" (" .. c.rank .. ")") or ""
			if c.cd then extra = extra .. ", " .. ns.Remaining(c.cd) end
			GameTooltip:AddLine(PersonText(c) .. extra, 1, 1, 1)
		end
		GameTooltip:AddLine("Shift-klick: länka i chatten. Klicka för att välja.", 0.6, 0.6, 0.6)
	elseif mode == "cd" then
		GameTooltip:AddLine(item.prof .. ", " .. (item.me and "du" or item.name))
		for _, key in ipairs(item.keys) do GameTooltip:AddLine(RecipeName(key), 1, 1, 1) end
		GameTooltip:AddLine("Delar samma cooldown.", 0.6, 0.6, 0.6)
	else
		GameTooltip:AddLine(item.me and "du" or item.name)
		for prof, p in pairs(item.profs) do
			if item.registry then
				GameTooltip:AddLine(string.format("%s %d", prof, p.rank or 0), 1, 1, 1)
			else
				local n = 0
				for _ in pairs(p.items) do n = n + 1 end
				GameTooltip:AddLine(string.format("%s %d/%d, %d recept", prof, p.rank or 0, p.max or 0, n), 1, 1, 1)
			end
		end
		if item.registry then
			GameTooltip:AddLine("Nivåer från Skatteverkets yrkesregister; har inte Skolverket, så recepten är okända.", 0.6, 0.6, 0.6, true)
		end
	end
	GameTooltip:Show()
end

local function OnRowClick(row)
	local item = row.item
	if not item then return end
	if mode == "recept" and IsShiftKeyDown() and ChatEdit_InsertLink then
		ChatEdit_InsertLink(ns.Link(item.key))
		return
	end
	selected = item
	ns.RefreshWindow()
end

local function SetMode(newMode)
	mode, offset, selected = newMode, 0, nil
	for c, fs in ipairs(headers) do fs:SetText(HEADERS[mode][c]) end
	ns.RefreshWindow()
end

local function Build()
	frame = CreateFrame("Frame", "SkolverketFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetSize(WIDTH, 500)
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
	tinsert(UISpecialFrames, "SkolverketFrame")

	local header = frame:CreateTexture(nil, "ARTWORK")
	header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	header:SetSize(300, 64)
	header:SetPoint("TOP", 0, 12)
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", header, "TOP", 0, -14)
	title:SetText("Skolverket")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	frame.heading = Text(frame, "GameFontNormal", "TOPLEFT", 24, -34)

	local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	search:SetSize(200, 20)
	search:SetPoint("TOPRIGHT", -30, -30)
	search:SetAutoFocus(false)
	search:SetMaxLetters(40)
	search:SetScript("OnEscapePressed", search.ClearFocus)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnTextChanged", function()
		offset = 0
		ns.RefreshWindow()
	end)
	frame.search = search
	frame.searchLabel = Text(frame, "GameFontNormalSmall", "RIGHT", search, "LEFT", -10, 0)
	frame.searchLabel:SetText("Sök")

	local x = 24
	for c = 1, 3 do
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
		for c = 1, 3 do
			local fs = Text(row, "GameFontHighlightSmall", "LEFT", cx, 0)
			fs:SetWidth(COLS[c] - 6)
			fs:SetWordWrap(false)
			row.cells[c] = fs
			cx = cx + COLS[c]
		end
		row:SetScript("OnEnter", ShowTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:SetScript("OnClick", OnRowClick)
		rows[i] = row
	end

	frame.count = Text(frame, "GameFontDisableSmall", "TOPLEFT", 24, -366)
	frame.count:SetWidth(WIDTH - 48)

	local act = CreateFrame("Frame", nil, frame)
	act:SetPoint("TOPLEFT", 24, -410)
	act:SetSize(WIDTH - 48, 24)
	act.label = Text(act, "GameFontHighlightSmall", "LEFT", 0, 0)
	act.label:SetWidth(480)
	act.label:SetWordWrap(false)
	act.ask = Button(act, "Fråga", 200, function()
		if not selected then return end
		if mode == "recept" then
			Whisper(BestOnline(selected.crafters), selected.key)
		elseif not selected.me and selected.online then
			Whisper(selected.name, mode == "cd" and selected.keys[1] or nil)
		end
	end)
	act.ask:SetPoint("LEFT", act.label, "RIGHT", 8, 0)
	frame.act = act

	local refresh = Button(frame, "Uppdatera", 100, function() ns.Ask() ns.RefreshWindow() end)
	refresh:SetPoint("BOTTOMLEFT", 24, 18)
	frame.tabs = {}
	local tx = refresh
	for _, spec in ipairs({ { "recept", "Recept" }, { "cd", "Cooldowns" }, { "folk", "Medlemmar" } }) do
		local b = Button(frame, spec[2], 120, function() SetMode(spec[1]) end)
		b:SetPoint("LEFT", tx, "RIGHT", 8, 0)
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
	-- Cooldown times change with time.
	frame:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed > 30 then
			self.elapsed = 0
			if mode == "cd" then ns.RefreshWindow() end
		end
	end)
	frame:Hide()
end

local function NameList(people)
	local names = {}
	for i = 1, math.min(8, #people) do table.insert(names, PersonText(people[i])) end
	if #people > 8 then table.insert(names, "+" .. (#people - 8)) end
	return string.format("(%d) %s", #people, table.concat(names, ", "))
end

local function FillRow(row, item)
	if mode == "recept" then
		row.cells[1]:SetText(item.name or ("|cff999999" .. RecipeName(item.key) .. " (hämtar namn ...)|r"))
		row.cells[2]:SetText(item.prof)
		row.cells[3]:SetText(NameList(item.crafters))
	elseif mode == "cd" then
		local label = RecipeName(item.keys[1])
		if #item.keys > 1 then label = label .. string.format(" (+%d)", #item.keys - 1) end
		row.cells[1]:SetText(label)
		row.cells[2]:SetText(PersonText(item))
		row.cells[3]:SetText(ns.Remaining(item.ready))
	else
		local profs = {}
		for prof, p in pairs(item.profs) do
			table.insert(profs, p.max and string.format("%s %d/%d", prof, p.rank or 0, p.max)
				or string.format("%s %d", prof, p.rank or 0))
		end
		table.sort(profs)
		row.cells[1]:SetText(PersonText(item))
		row.cells[2]:SetText(table.concat(profs, ", "))
		row.cells[3]:SetText(item.me and "" or (item.online and "|cff40ff40online|r" or Ago(item.seen)))
	end
	if item == selected then row:LockHighlight() else row:UnlockHighlight() end
end

local function Rows()
	if mode == "recept" then return ns.Search(frame.search:GetText()) end
	if mode == "cd" then return ns.Cooldowns() end
	local people = ns.People()
	table.sort(people, function(a, b)
		if a.me ~= b.me then return a.me end
		if a.online ~= b.online then return a.online end
		return a.name < b.name
	end)
	return people
end

-- Rows are rebuilt on every refresh; keep the selection by identity.
local function SameItem(a, b)
	if mode == "recept" then return a.key == b.key end
	if mode == "cd" then return a.name == b.name and a.prof == b.prof and a.keys[1] == b.keys[1] end
	return a.name == b.name
end

local function RefreshActions()
	local act = frame.act
	if not selected then
		act.label:SetText(mode == "recept" and "Klicka på ett recept för att fråga någon som kan tillverka det."
			or "Klicka på en rad för att viska till medlemmen.")
		act.ask:SetText("Fråga")
		act.ask:Disable()
		return
	end
	local target
	if mode == "recept" then
		act.label:SetText("Valt: " .. (selected.name or RecipeName(selected.key)))
		target = BestOnline(selected.crafters)
	else
		act.label:SetText("Valt: " .. (selected.me and "du" or selected.name))
		target = (not selected.me and selected.online) and selected.name or nil
	end
	act.ask:SetText(target and ("Fråga " .. target) or "Ingen online att fråga")
	if target then act.ask:Enable() else act.ask:Disable() end
end

function ns.RefreshWindow()
	if not frame or not frame:IsShown() then return end
	frame.heading:SetText(TITLES[mode])
	if mode == "recept" then frame.search:Show() frame.searchLabel:Show() else frame.search:Hide() frame.searchLabel:Hide() end
	for key, b in pairs(frame.tabs) do
		if key == mode then b:Disable() else b:Enable() end
	end
	list = Rows()
	if selected then
		local found
		for _, item in ipairs(list) do
			if SameItem(item, selected) then found = item break end
		end
		selected = found
	end
	offset = math.max(0, math.min(offset, #list - ROWS))
	for i, row in ipairs(rows) do
		local item = list[i + offset]
		row.item = item
		if item then
			FillRow(row, item)
			row:Show()
		else
			row:Hide()
		end
	end
	for _, row in ipairs(rows) do
		if row:IsShown() and GameTooltip:IsOwned(row) then ShowTooltip(row) end
	end
	RefreshActions()

	local range = #list > ROWS and string.format("Visar %d-%d av %d (scrolla med mushjulet). ", offset + 1, math.min(offset + ROWS, #list), #list) or ""
	if mode == "recept" then
		if #list == 0 and frame.search:GetText() == "" then
			frame.count:SetText("Inga recept än. Öppna dina yrkesfönster en gång så sparas recepten, och be gillet installera Skolverket.")
		elseif #list == 0 then
			frame.count:SetText("Ingen i gillet kan det, eller så har de inte öppnat yrkesfönstret med Skolverket än.")
		else
			frame.count:SetText(range .. "Grönt: online. Grått: offline. Håll musen över en rad för detaljer.")
		end
	elseif mode == "cd" then
		frame.count:SetText(#list == 0 and "Inga kända cooldowns. De syns när någon med en cooldown-recept öppnar yrkesfönstret."
			or range .. "Tiderna uppdateras när medlemmen öppnar yrkesfönstret.")
	else
		frame.count:SetText(range .. "Recepten för ett yrke sparas när medlemmen öppnar yrkesfönstret med Skolverket.")
	end
end

-- Toggle the window; with search text, open on Recept with that search.
function ns.ToggleWindow(text)
	if not frame then Build() end
	if text and text ~= "" then
		frame:Show()
		SetMode("recept")
		frame.search:SetText(text)
	elseif frame:IsShown() then
		frame:Hide()
		return
	else
		frame:Show()
		SetMode(mode)
	end
	ns.Ask()
	ns.RefreshWindow()
end
