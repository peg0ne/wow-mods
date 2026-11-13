-- Skolverket, the /skola window: the guild's profession cooldowns
-- (transmutes, Mooncloth ...), soonest first. Green names are online, grey
-- offline. Click a row, then "Fråga" whispers that member with a link to
-- the recipe. Recipes and who has which profession are in Skatteverket's
-- /skatt yrken.

local _, ns = ...

local ROWS, ROW_H = 14, 18
local WIDTH = 560
local COLS = { 270, 160, 90 }

local frame, rows, list = nil, {}, {}
local offset = 0
local selected

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
	if p.me then return "|cffffd100du|r" end
	return p.online and ("|cff40ff40" .. p.name .. "|r") or ("|cff999999" .. p.name .. "|r")
end

local function RecipeName(key)
	return ns.Name(key) or ("#" .. key:sub(2))
end

local function Whisper(name, key)
	if not name then return end
	if ChatFrame_SendTell then ChatFrame_SendTell(name) end
	local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
	if box and key then box:Insert("Hej! Kan du göra " .. ns.Link(key) .. "? ") end
end

local function ShowTooltip(row)
	local item = row.item
	if not item then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(item.prof .. ", " .. (item.me and "du" or item.name))
	for _, key in ipairs(item.keys) do GameTooltip:AddLine(RecipeName(key), 1, 1, 1) end
	if #item.keys > 1 then GameTooltip:AddLine("Delar samma cooldown.", 0.6, 0.6, 0.6) end
	GameTooltip:Show()
end

local function Build()
	local classic
	frame, classic = Statskontoret.Window("SkolverketFrame", "Skolverket", WIDTH, 440)
	-- Below the portrait and title bar; buttons in the strip under the inset.
	local dy, bottom, left = classic and -12 or 0, classic and 4 or 18, classic and 66 or 24

	Text(frame, "GameFontNormal", "TOPLEFT", left, -34):SetText("Cooldowns i gillet")

	local x = 24
	for c, label in ipairs({ "Recept", "Medlem", "Redo" }) do
		Text(frame, "GameFontNormalSmall", "TOPLEFT", x, -56 + dy):SetText(label)
		x = x + COLS[c]
	end

	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetSize(WIDTH - 40, ROW_H)
		row:SetPoint("TOPLEFT", 20, -70 + dy - (i - 1) * ROW_H)
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
		row:SetScript("OnClick", function(self)
			if self.item then
				selected = self.item
				ns.RefreshWindow()
			end
		end)
		rows[i] = row
	end

	frame.count = Text(frame, "GameFontDisableSmall", "TOPLEFT", 24, -330 + dy)
	frame.count:SetWidth(WIDTH - 48)

	frame.ask = Button(frame, "Fråga", 200, function()
		if selected and not selected.me and selected.online then Whisper(selected.name, selected.keys[1]) end
	end)
	frame.ask:SetPoint("TOPRIGHT", -24, -360 + dy)
	frame.selected = Text(frame, "GameFontHighlightSmall", "RIGHT", frame.ask, "LEFT", -8, 0)

	local refresh = Button(frame, "Uppdatera", 100, function() ns.Ask() ns.RefreshWindow() end)
	refresh:SetPoint("BOTTOMLEFT", 24, bottom)

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
			ns.RefreshWindow()
		end
	end)
	frame:Hide()
end

local function SameItem(a, b)
	return a.name == b.name and a.prof == b.prof and a.keys[1] == b.keys[1]
end

function ns.RefreshWindow()
	if not frame or not frame:IsShown() then return end
	list = ns.Cooldowns()
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
			local label = RecipeName(item.keys[1])
			if #item.keys > 1 then label = label .. string.format(" (+%d)", #item.keys - 1) end
			row.cells[1]:SetText(label)
			row.cells[2]:SetText(PersonText(item))
			row.cells[3]:SetText(ns.Remaining(item.ready))
			if item == selected then row:LockHighlight() else row:UnlockHighlight() end
			row:Show()
			if GameTooltip:IsOwned(row) then ShowTooltip(row) end
		else
			row:Hide()
		end
	end

	local target = selected and not selected.me and selected.online and selected.name
	frame.selected:SetText(selected and ("Valt: " .. RecipeName(selected.keys[1])) or "Klicka på en rad för att fråga medlemmen.")
	frame.ask:SetText(target and ("Fråga " .. target) or "Fråga")
	if target then frame.ask:Enable() else frame.ask:Disable() end

	local range = #list > ROWS and string.format("Visar %d-%d av %d (scrolla med mushjulet). ", offset + 1, math.min(offset + ROWS, #list), #list) or ""
	frame.count:SetText(#list == 0 and "Inga kända cooldowns. De syns när någon med ett cooldown-recept öppnar yrkesfönstret."
		or range .. "Tiderna uppdateras när medlemmen öppnar yrkesfönstret. Recept och yrken finns i /skatt yrken.")
end

function ns.ToggleWindow()
	if not frame then Build() end
	if frame:IsShown() then
		frame:Hide()
		return
	end
	frame:Show()
	ns.Ask()
	ns.RefreshWindow()
end
