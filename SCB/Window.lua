-- SCB, the /scb window, in the style of Skatteverket's panel: one row per
-- member with figures, the guild's totals, and a few facts. Click a column
-- heading to sort by it (again to reverse). The guild's total sits right
-- under the last member shown (0.4.1).

local _, ns = ...

local ROWS, ROW_H = 14, 18
local WIDTH = 760
local COLUMNS = {
	{ key = "name", label = "Medlem", width = 170 },
	{ key = "level", label = "Nivå", width = 50 },
	{ key = "deaths", label = "Döda", width = 60 },
	{ key = "fall", label = "Fall", width = 50 },
	{ key = "pvp", label = "PvP", width = 50 },
	{ key = "kills", label = "Dödat", width = 70 },
	{ key = "quests", label = "Uppdrag", width = 70 },
	{ key = "earned", label = "Guld in", width = 80 },
	{ key = "played", label = "Spelat", width = 110 },
}

local frame, rows, list = nil, {}, {}
local offset, sortKey, sortDown = 0, "deaths", true

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

local function NameText(p)
	local name = p.me and (p.name .. " (du)") or p.name
	return Statskontoret.ClassText(p.class, name)
end

local function Cell(p, key)
	if key == "name" then return NameText(p) end
	if key == "earned" then return ns.Gold(p.earned) end
	if key == "played" then return p.played and ns.Hours(p.played) or "|cff999999?|r" end
	return tostring(p[key] or 0)
end

local function Sort(people)
	table.sort(people, function(a, b)
		local x, y = a[sortKey], b[sortKey]
		if sortKey == "name" then x, y = x or "", y or "" else x, y = x or -1, y or -1 end
		if x ~= y then
			if sortDown then return x > y end
			return x < y
		end
		return (a.name or "") < (b.name or "")
	end)
end

local function Build()
	local classic
	frame, classic = Statskontoret.Window("SCBFrame", "Statistiska centralbyrån", WIDTH, 590)   -- room for up to 8 lines of facts
	-- Below the portrait and title bar; buttons in the strip under the inset.
	local dy, bottom, left = classic and -12 or 0, classic and 4 or 18, classic and 66 or 24

	frame.heading = Text(frame, "GameFontNormal", "TOPLEFT", left, -34)
	frame.heading:SetText("Gillet i siffror")

	-- Clickable column headings.
	local x = 24
	frame.headers = {}
	for _, col in ipairs(COLUMNS) do
		local h = CreateFrame("Button", nil, frame)
		h:SetSize(col.width, 16)
		h:SetPoint("TOPLEFT", x, -54 + dy)
		h.text = Text(h, "GameFontNormalSmall", "LEFT", 0, 0)
		h:SetScript("OnClick", function()
			if sortKey == col.key then sortDown = not sortDown else sortKey, sortDown = col.key, col.key ~= "name" end
			ns.RefreshWindow()
		end)
		h.col = col
		frame.headers[col.key] = h
		x = x + col.width
	end
	Statskontoret.Rule(frame, 20, 20, -68 + dy, 0.2)

	for i = 1, ROWS + 1 do
		local row = CreateFrame("Frame", nil, frame)
		row:SetSize(WIDTH - 40, ROW_H)
		row:SetPoint("TOPLEFT", 20, -70 + dy - (i - 1) * ROW_H)
		if i <= ROWS then Statskontoret.Stripe(row, i) end
		row.cells = {}
		local cx = 4
		for c, col in ipairs(COLUMNS) do
			local fs = Text(row, "GameFontHighlightSmall", "LEFT", cx, 0)
			fs:SetWidth(col.width - 6)
			fs:SetWordWrap(false)
			row.cells[c] = fs
			cx = cx + col.width
		end
		rows[i] = row
	end
	-- The last row is the guild total, right under the last member shown
	-- (see RefreshWindow), with a line above it; the facts follow.
	frame.top = -70 + dy
	local total = rows[ROWS + 1]
	total.rule = Statskontoret.Rule(total, 0, 0, 1, 0.3)

	frame.scroll = Statskontoret.ScrollMark(frame)
	frame.scroll:SetPoint("TOPRIGHT", -12, -72 + dy)
	frame.scroll:SetHeight(ROWS * ROW_H - 4)

	frame.facts = Text(frame, "GameFontHighlightSmall", "TOPLEFT", total, "BOTTOMLEFT", 4, -14)
	frame.facts:SetWidth(WIDTH - 48)
	frame.facts:SetSpacing(4)

	frame.count = Text(frame, "GameFontDisableSmall", "BOTTOMLEFT", 24, bottom + 30)
	frame.count:SetWidth(WIDTH - 48)

	local refresh = Button(frame, "Uppdatera", 100, function() ns.Ask() ns.RefreshWindow() end)
	refresh:SetPoint("BOTTOMLEFT", 24, bottom)

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta, #list - ROWS))
		ns.RefreshWindow()
	end)
	frame:Hide()
end

function ns.RefreshWindow()
	if not frame or not frame:IsShown() then return end
	for key, h in pairs(frame.headers) do
		if key == sortKey then
			h.text:SetText("|cffffffff" .. h.col.label .. "|r" .. Statskontoret.SortArrow(sortDown))
		else
			h.text:SetText(h.col.label)
		end
	end
	list = ns.People()
	Sort(list)
	offset = math.max(0, math.min(offset, #list - ROWS))
	for i = 1, ROWS do
		local row, p = rows[i], list[i + offset]
		if p then
			for c, col in ipairs(COLUMNS) do row.cells[c]:SetText(Cell(p, col.key)) end
			row:Show()
		else
			row:Hide()
		end
	end
	frame.scroll:Update(offset, ROWS, #list)
	local t = ns.Totals(list)
	local total = rows[ROWS + 1]
	local shown = math.max(1, math.min(ROWS, #list - offset))
	total:SetPoint("TOPLEFT", 20, frame.top - shown * ROW_H - 6)
	-- Play time only counts once someone has typed /played.
	local anyPlayed = false
	for _, p in ipairs(list) do
		if p.played then anyPlayed = true end
	end
	if not anyPlayed then t.played = nil end
	t.name = nil
	for c, col in ipairs(COLUMNS) do
		total.cells[c]:SetText(col.key == "name" and "|cffffd100Hela gillet|r"
			or col.key == "level" and "" or "|cffffd100" .. Cell(t, col.key) .. "|r")
	end
	frame.facts:SetText(table.concat(ns.Facts(list), "\n"))
	frame.count:SetText(string.format("%d medlemmar med SCB. Dödat räknar dödade fiender som gav erfarenhet. Spelat uppdateras när du skriver /played.", #list))
end

function ns.ToggleWindow()
	if not frame then Build() end
	if frame:IsShown() then frame:Hide() return end
	frame:Show()
	ns.Ask()
	ns.RefreshWindow()
end
