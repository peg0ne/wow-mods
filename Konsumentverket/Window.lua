-- Konsumentverket's window: one tab per profession saved for this
-- character, its recipes with what they cost, what a vendor pays and the
-- difference, best first. Names are colored by difficulty (orange, yellow
-- and green still give skill). Hover a recipe for the reagents, the
-- vendors and the tax.

local _, ns = ...

local ROWS, ROW_H = 16, 18
local WIDTH = 640
local COLS = {
	{ label = "Recept", width = 230 },
	{ label = "Kostnad", width = 90 },
	{ label = "Säljs för", width = 90 },
	{ label = "Vinst", width = 90 },
	{ label = "Kan göra", width = 80 },
}
local DIFF_COLOR = { orange = "ff8040", yellow = "ffff00", green = "40c040", grey = "808080" }
local DIFF_TEXT = {
	orange = "Orange: ger alltid färdighet",
	yellow = "Gul: ger oftast färdighet",
	green = "Grön: ger ibland färdighet",
	grey = "Grå: ger ingen färdighet",
}

local frame, rows, list = nil, {}, {}
local offset, auto = 0, false

local function Text(parent, template, ...)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetPoint(...)
	fs:SetJustifyH("LEFT")
	return fs
end

local function Profit(v)
	if not v.known then return "|cff808080?|r" end
	local color = v.profit > 0.5 and "40ff40" or (v.profit < -0.5 and "ff5050" or "c0c0c0")
	return "|cff" .. color .. (v.profit > 0.5 and "+" or "") .. ns.Money(v.profit) .. "|r"
end

local function ShowTooltip(row)
	local e = row.entry
	if not e then return end
	local rec, v = e.rec, e.v
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine("|cff" .. DIFF_COLOR[rec.difficulty] .. rec.name .. "|r")
	GameTooltip:AddLine(DIFF_TEXT[rec.difficulty], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(" ")
	for _, p in ipairs(v.parts) do
		local left = p.n .. " x " .. ns.ItemName(p.item)
		local right
		if p.kind == "handlare" then
			right = ns.Money(p.each * p.n) .. " |cff80c0ffhandlare|r"
		elseif p.kind == "AH" then
			right = ns.Money(p.each * p.n) .. " |cffffc040AH|r"
		else
			right = "|cff808080pris okänt|r"
		end
		GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
		if p.kind == "handlare" then
			local where = ns.BuyWhere(p.item)
			if where then GameTooltip:AddLine("   " .. where, 0.5, 0.5, 0.5) end
		end
	end
	GameTooltip:AddDoubleLine("Kostnad", v.costKnown and ns.Money(v.cost) or "|cff808080okänd|r", 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddLine(" ")
	if rec.item then
		local qty = rec.qty ~= 1 and (" (" .. rec.qty .. " st)") or ""
		GameTooltip:AddDoubleLine("Handlaren betalar" .. qty, ns.Money(v.each * (rec.qty or 1)), 1, 0.82, 0, 1, 1, 1)
		local rate = ns.TaxRate()
		if rate > 0 then
			GameTooltip:AddDoubleLine(string.format("Skatt %g %%", rate * 100), "-" .. ns.Money(v.each * (rec.qty or 1) * rate), 0.8, 0.8, 0.8, 1, 0.5, 0.5)
		end
		if v.each == 0 and v.known then GameTooltip:AddLine("Handlare köper inte det här.", 1, 0.5, 0.5) end
	else
		GameTooltip:AddLine("Gör inget föremål att sälja.", 1, 0.5, 0.5)
	end
	GameTooltip:AddDoubleLine("Vinst", Profit(v), 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Varje reagens kostar det billigaste av |cff80c0ffhandlare|r och |cffffc040AH|r (Auctionators senaste skanning).", 0.7, 0.7, 0.7, true)
	GameTooltip:AddLine("Högerklicka för att lägga reagenserna i en inköpslista i Auctionator.", 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end

local function SetProfession(name)
	ns.current, offset = name, 0
	ns.RefreshWindow()
end

-- One tab per profession; made again when the list changes.
local function Tabs(professions)
	local key = table.concat(professions, "|")
	if frame.tabsKey == key then return end
	frame.tabsKey = key
	if frame.tabs then frame.tabs:Hide() end
	local specs = {}
	for _, name in ipairs(professions) do table.insert(specs, { name, name }) end
	frame.tabs = Statskontoret.Tabs(frame, specs, SetProfession)
	frame.tabs:SetPoint("TOPLEFT", frame.left - 4, -28)
end

local function Build()
	local portrait
	frame, portrait = Statskontoret.Window("KonsumentverketFrame", "Konsumentverket", WIDTH, 480)
	local dy = portrait and -12 or 0
	frame.left = portrait and 66 or 24

	local x = 24
	for _, col in ipairs(COLS) do
		Text(frame, "GameFontNormalSmall", "TOPLEFT", x, -56 + dy):SetText(col.label)
		x = x + col.width
	end
	Statskontoret.Rule(frame, 20, 20, -68 + dy, 0.2)

	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetSize(WIDTH - 40, ROW_H)
		row:SetPoint("TOPLEFT", 20, -70 + dy - (i - 1) * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		Statskontoret.Stripe(row, i)
		row.cells = {}
		local cx = 4
		for c, col in ipairs(COLS) do
			local fs = Text(row, "GameFontHighlightSmall", "LEFT", cx, 0)
			fs:SetWidth(col.width - 6)
			fs:SetWordWrap(false)
			row.cells[c] = fs
			cx = cx + col.width
		end
		row:SetScript("OnEnter", ShowTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, mouse)
			if mouse == "RightButton" and self.entry then ns.ShopMenu(self, self.entry.rec) end
		end)
		rows[i] = row
	end

	frame.scroll = Statskontoret.ScrollMark(frame)
	frame.scroll:SetPoint("TOPRIGHT", -12, -72 + dy)
	frame.scroll:SetHeight(ROWS * ROW_H - 4)

	frame.count = Text(frame, "GameFontDisableSmall", "TOPLEFT", 24, -366 + dy)
	frame.count:SetWidth(WIDTH - 48)

	local only = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	only:SetSize(24, 24)
	only:SetPoint("TOPLEFT", 20, -404 + dy)
	only:SetScript("OnClick", function(self)
		ns.DB().skillOnly = self:GetChecked() and true or false
		offset = 0
		ns.RefreshWindow()
	end)
	Text(frame, "GameFontHighlightSmall", "LEFT", only, "RIGHT", 4, 0):SetText("Bara recept som ger färdighet")
	frame.only = only

	local search = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	search:SetSize(140, 22)
	search:SetText("Sök utrustning")
	search:SetPoint("TOPRIGHT", -24, -404 + dy)
	search:SetScript("OnClick", function() ns.ToggleSearch() end)

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta, #list - ROWS))
		ns.RefreshWindow()
	end)
	frame:SetScript("OnHide", function() auto = false end)
	-- Moved while beside the profession window: open there from now on
	-- (0.2; it could cover the profession window's tabs).
	frame:HookScript("OnDragStop", function(self)
		if not auto then return end
		local left, top = self:GetLeft(), self:GetTop()
		if left and top then ns.DB().dockPos = { left, top } end
	end)
	frame:Hide()
end

local ORDER = { orange = 1, yellow = 2, green = 3, grey = 4 }

function ns.RefreshWindow()
	if not frame or not frame:IsShown() then return end
	local db = ns.DB()
	local professions, char = ns.Professions()
	if not ns.current or not char[ns.current] then ns.current = professions[1] end
	Tabs(professions)
	if frame.tabs and ns.current then frame.tabs:Select(ns.current) end
	frame.only:SetChecked(db.skillOnly)

	list = {}
	local saved = ns.current and char[ns.current]
	for _, rec in pairs(saved and saved.recipes or {}) do
		if not db.skillOnly or rec.difficulty ~= "grey" then
			table.insert(list, { rec = rec, v = ns.Value(rec) })
		end
	end
	-- Best profit first; unknown prices last; then by difficulty and name.
	table.sort(list, function(a, b)
		if a.v.known ~= b.v.known then return a.v.known end
		if math.abs(a.v.profit - b.v.profit) > 0.5 then return a.v.profit > b.v.profit end
		local da, dbb = ORDER[a.rec.difficulty] or 5, ORDER[b.rec.difficulty] or 5
		if da ~= dbb then return da < dbb end
		return (a.rec.name or "") < (b.rec.name or "")
	end)

	offset = math.max(0, math.min(offset, #list - ROWS))
	for i, row in ipairs(rows) do
		local e = list[i + offset]
		row.entry = e
		if e then
			local rec, v, c = e.rec, e.v, row.cells
			c[1]:SetText("|cff" .. (DIFF_COLOR[rec.difficulty] or "ffffff") .. (rec.name or "?") .. "|r")
			c[2]:SetText(v.costKnown and (ns.Money(v.cost) .. (v.vendorOnly and "" or " |cffffc040AH|r")) or "|cff808080?|r")
			c[3]:SetText(rec.item and ns.Money(v.out) or "|cff808080-|r")
			c[4]:SetText(Profit(v))
			c[5]:SetText(v.canMake > 0 and tostring(v.canMake) or "|cff8080800|r")
			row:Show()
		else
			row:Hide()
		end
	end
	for _, row in ipairs(rows) do
		if row:IsShown() and GameTooltip:IsOwned(row) then ShowTooltip(row) end
	end
	frame.scroll:Update(offset, ROWS, #list)

	if not ns.current then
		frame.count:SetText("Inga recept än. Öppna ett yrkesfönster en gång så läses recepten in.")
		return
	end
	local parts = {}
	local rank, max = ns.Skill(ns.current)
	if rank then table.insert(parts, string.format("%s %d/%d.", ns.current, rank, max or rank)) end
	local rate = ns.TaxRate()
	if rate > 0 then table.insert(parts, string.format("Skatten (%g %%) är dragen.", rate * 100)) end
	table.insert(parts, "Reagenserna kostar det billigaste av handlaren och AH (märkt AH när något köps där).")
	table.insert(parts, "Öppna handlare och skanna AH med Auctionator för priserna.")
	frame.count:SetText(table.concat(parts, " "))
end

function ns.ToggleWindow()
	if not frame then Build() end
	if frame:IsShown() then frame:Hide() return end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER")
	frame:Show()
	ns.RefreshWindow()
end

-- Opened by the profession window: beside it, and closed with it.
function ns.ShowBesideProfession()
	local pf = ProfessionsFrame or TradeSkillFrame
	if not pf or not pf:IsShown() then return end
	if not frame then Build() end
	if frame:IsShown() then ns.RefreshWindow() return end
	frame:ClearAllPoints()
	local db = ns.DB()
	if db.dockPos then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.dockPos[1], db.dockPos[2])
	else
		-- Beside it where there is room (the screen would push a window that
		-- doesn't fit back over the profession window); else at the screen's
		-- right edge, top aligned.
		local scale = pf:GetEffectiveScale() / frame:GetEffectiveScale()
		local right, left = (pf:GetRight() or 0) * scale, (pf:GetLeft() or 0) * scale
		local w = frame:GetWidth()
		if right + 4 + w <= UIParent:GetWidth() then
			frame:SetPoint("TOPLEFT", pf, "TOPRIGHT", 4, 0)
		elseif left - 4 - w >= 0 then
			frame:SetPoint("TOPRIGHT", pf, "TOPLEFT", -4, 0)
		else
			frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -10, (pf:GetTop() or 0) * scale - UIParent:GetHeight())
		end
	end
	frame:Show()
	auto = true
	ns.RefreshWindow()
end

function ns.ProfessionClosed()
	if frame and auto then frame:Hide() end
end

-- A button above the profession window, as Bokföring has (0.3): opens the
-- window beside it, or closes it. Left of Bokföring's when that is loaded.
local profButton
function ns.ShowProfessionButton()
	local pf = ProfessionsFrame or TradeSkillFrame
	if profButton or not pf then return end
	profButton = CreateFrame("Button", nil, pf, "UIPanelButtonTemplate")
	profButton:SetSize(120, 22)
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Bokforing")
	profButton:SetPoint("BOTTOMRIGHT", pf, "TOPRIGHT", loaded and -94 or 0, 2)
	profButton:SetText("Konsumentverket")
	profButton:SetScript("OnClick", function()
		if frame and frame:IsShown() then frame:Hide() else ns.ShowBesideProfession() end
	end)
end

---------------------------------------------------------------------------
-- Shopping list (as Bokföring does it): right-click a recipe, say how many
-- crafts, and the reagents the auction house sells cheapest go into an
-- Auctionator shopping list; what a vendor sells cheaper is printed with
-- where to buy it. Buying stays one click per purchase in Auctionator, as
-- the game demands. What is in the bags is taken off unless unticked.

local CALLER = "Konsumentverket"

local function SearchString(name, count)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.ConvertToSearchString then
		local ok, text = pcall(api.ConvertToSearchString, CALLER, { searchString = name, isExact = true, quantity = count })
		if ok and text then return text end
		ok, text = pcall(api.ConvertToSearchString, CALLER, { searchString = name, isExact = true })
		if ok and text then return text end
	end
	return "\"" .. name .. "\""
end

local function Loaded(item)
	return C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)
end

function ns.Shop(rec, crafts, tries)
	local useOwned = ns.DB().useOwned ~= false
	local buy, unknown = {}, false
	for _, r in ipairs(rec.reagents) do
		local n = r[2] * crafts - (useOwned and ns.Have(r[1]) or 0)
		if n > 0 then
			buy[r[1]] = (buy[r[1]] or 0) + n
			if not Loaded(r[1]) then
				unknown = true
				ns.ItemName(r[1])
			end
		end
	end
	-- Names the game has not loaded yet: ask for them and try again shortly.
	if unknown and (tries or 0) < 10 then
		C_Timer.After(0.3, function() ns.Shop(rec, crafts, (tries or 0) + 1) end)
		return
	end
	if not next(buy) then
		ns.Print(string.format("du har redan allt till %d x %s i väskorna.", crafts, rec.name or "?"))
		return
	end
	local listName = string.format("Konsumentverket: %s x%d", rec.name or "?", crafts)
	local terms, ah, vendor, total = {}, {}, {}, 0
	for item, n in pairs(buy) do
		local name = ns.ItemName(item)
		local each, kind = ns.Cost(item)
		local price = each and (" (" .. ns.Money(each * n) .. ")") or ""
		total = total + (each or 0) * n
		if kind == "handlare" then
			local where = ns.BuyWhere(item)
			table.insert(vendor, string.format("%d x %s%s%s", n, name, price, where and (", " .. where) or ""))
		else
			table.insert(terms, SearchString(name, n))
			table.insert(ah, string.format("%d x %s%s", n, name, each and price or " (pris okänt)"))
		end
	end
	table.sort(ah)
	table.sort(vendor)
	if #terms > 0 then
		local api = Auctionator and Auctionator.API and Auctionator.API.v1
		if api and api.CreateShoppingList and pcall(api.CreateShoppingList, CALLER, listName, terms) then
			ns.Print(string.format("Auctionator-listan \"%s\": öppna Shopping i Auctionator, välj listan och köp med ett klick per sak.", listName))
		else
			ns.Print("kunde inte göra en Auctionator-lista; köp det här själv:")
		end
		for _, line in ipairs(ah) do ns.Print("  AH: " .. line) end
	end
	for _, line in ipairs(vendor) do ns.Print("  handlare: " .. line) end
	ns.Print(string.format("ungefär %s i allt%s.", ns.Money(total), useOwned and ", det du har i väskorna avdraget" or ""))
end

StaticPopupDialogs.KONSUMENTVERKET_CRAFTS = {
	text = "Hur många av %s?",
	button1 = OKAY,
	button2 = CANCEL,
	hasEditBox = true,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function(self, data)
		local box = self.editBox or self.EditBox
		local n = tonumber(box:GetText())
		if n and n >= 1 and n <= 1000 then ns.Shop(data, math.floor(n)) else ns.Print("skriv ett antal, 1 till 1000.") end
	end,
	EditBoxOnEnterPressed = function(box)
		local popup = box:GetParent()
		StaticPopupDialogs.KONSUMENTVERKET_CRAFTS.OnAccept(popup, popup.data)
		popup:Hide()
	end,
	EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
}

local function Ask(rec)
	local dialog = StaticPopup_Show("KONSUMENTVERKET_CRAFTS", rec.name or "?", nil, rec)
	local box = dialog and (dialog.editBox or dialog.EditBox)
	if box then
		box:SetText("1")
		box:HighlightText()
	end
end

-- The right-click menu on a recipe (here and in the gear search).
function ns.ShopMenu(owner, rec)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		Ask(rec)
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(rec.name or "?")
		root:CreateButton("Köp reagenserna för N st...", function() Ask(rec) end)
		root:CreateCheckbox("Räkna av det jag har i väskorna", function() return ns.DB().useOwned ~= false end,
			function() ns.DB().useOwned = ns.DB().useOwned == false end)
	end)
end
