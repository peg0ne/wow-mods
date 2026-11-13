-- SCB, the /scb window, in the style of Skatteverket's panel: one row per
-- member with figures, the guild's totals, and a few facts. Click a column
-- heading to sort by it (again to reverse).

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
	local color = p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
	if not color then return name end
	return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, name)
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

local function Build()
	local classic
	frame, classic = Panel("SCBFrame", "Statistiska centralbyrån")
	frame:SetSize(WIDTH, 590)   -- room for up to 8 lines of facts
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "SCBFrame")
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

	for i = 1, ROWS + 1 do
		local row = CreateFrame("Frame", nil, frame)
		row:SetSize(WIDTH - 40, ROW_H)
		row:SetPoint("TOPLEFT", 20, -70 + dy - (i - 1) * ROW_H)
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
	-- The last row is the guild total, set apart.
	rows[ROWS + 1]:SetPoint("TOPLEFT", 20, -74 + dy - ROWS * ROW_H)

	frame.facts = Text(frame, "GameFontHighlightSmall", "TOPLEFT", 24, -110 + dy - ROWS * ROW_H)
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
		local arrow = key == sortKey and (sortDown and " v" or " ^") or ""
		h.text:SetText(h.col.label .. arrow)
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
	local t = ns.Totals(list)
	local total = rows[ROWS + 1]
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
