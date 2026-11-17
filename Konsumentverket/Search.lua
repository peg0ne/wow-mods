-- Konsumentverket's equipment search (0.2, /konsument sök): tick the stats
-- (stats, slots and armor types in English, as the game names them) an
-- item must have (all of them), and optionally slots and armor types,
-- and it lists the matching gear from two places:
--   Mina recept     what the recipes saved for any character on this
--                   account make, with what the reagents cost
--   Auktionshuset   armor and weapons from the latest scan of the auction
--                   house (the Skanna AH button, with the auction house
--                   open), with the lowest price then
-- The scan is saved, so the search works away from the auction house too;
-- the footer says how old it is. Searches made in the auction house's own
-- window add to it as well.
--
-- Stats come from the game (GetItemStats) when it has them, otherwise from
-- the item's tooltip lines. Click an auction house item, with the auction
-- house open, to search for it there; Shift-click links it in chat.

local _, ns = ...

local ROWS, ROW_H = 13, 18
local WIDTH = 720

local STATS = {
	{ "str", "Strength" }, { "agi", "Agility" }, { "sta", "Stamina" }, { "int", "Intellect" },
	{ "spi", "Spirit" }, { "ap", "Attack Power" }, { "sp", "Spell Power" }, { "heal", "Healing" },
	{ "crit", "Critical Strike" }, { "hit", "Hit" }, { "def", "Defense" }, { "dodge", "Dodge" },
	{ "parry", "Parry" }, { "block", "Block" }, { "mp5", "Mana per 5 sec" }, { "res", "Resistance" },
}
local STAT_SHORT = {
	str = "Str", agi = "Agi", sta = "Sta", int = "Int", spi = "Spi", ap = "AP", sp = "SP", heal = "Heal",
	crit = "Crit", hit = "Hit", def = "Def", dodge = "Dodge", parry = "Parry", block = "Block", mp5 = "MP5", res = "Res",
}

-- Slots, by the game's inventory types.
local SLOTS = {
	{ "head", "Head", { "INVTYPE_HEAD" } },
	{ "neck", "Neck", { "INVTYPE_NECK" } },
	{ "shoulder", "Shoulder", { "INVTYPE_SHOULDER" } },
	{ "back", "Back", { "INVTYPE_CLOAK" } },
	{ "chest", "Chest", { "INVTYPE_CHEST", "INVTYPE_ROBE" } },
	{ "wrist", "Wrist", { "INVTYPE_WRIST" } },
	{ "hands", "Hands", { "INVTYPE_HAND" } },
	{ "waist", "Waist", { "INVTYPE_WAIST" } },
	{ "legs", "Legs", { "INVTYPE_LEGS" } },
	{ "feet", "Feet", { "INVTYPE_FEET" } },
	{ "finger", "Finger", { "INVTYPE_FINGER" } },
	{ "trinket", "Trinket", { "INVTYPE_TRINKET" } },
	{ "weapon", "Weapon", { "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND" } },
	{ "offhand", "Off Hand", { "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" } },
	{ "ranged", "Ranged", { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC" } },
}
local SLOT_OF, SLOT_NAME = {}, {}
for _, s in ipairs(SLOTS) do
	SLOT_NAME[s[1]] = s[2]
	for _, loc in ipairs(s[3]) do SLOT_OF[loc] = s[1] end
end

-- Armor types: the armor class's subclasses.
local TYPES = { { 1, "Cloth" }, { 2, "Leather" }, { 3, "Mail" }, { 4, "Plate" } }
local ARMOR, WEAPON = 4, 2

local frame, rows, list = nil, {}, {}
local offset, source = 0, "all"
local picked = { stats = {}, slots = {}, types = {} }
local ahOpen = false

local function Text(parent, template, ...)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetPoint(...)
	fs:SetJustifyH("LEFT")
	return fs
end

---------------------------------------------------------------------------
-- Item stats.

local GetStats = (C_Item and C_Item.GetItemStats) or GetItemStats
local Instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local ItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- The stats a GetItemStats key counts for. "Spell power" on these items is
-- damage and healing both.
local function StatIds(key)
	key = key:upper()
	if key:find("RESISTANCE") then return { "res" } end
	if key:find("HEAL") then return { "heal" } end
	if key:find("SPELL_POWER") then return { "sp", "heal" } end
	if key:find("SPELL_DAMAGE") then return { "sp" } end
	if key:find("ATTACK_POWER") then return { "ap" } end
	if key:find("CRIT") then return { "crit" } end
	if key:find("HIT") then return { "hit" } end
	if key:find("STRENGTH") then return { "str" } end
	if key:find("AGILITY") then return { "agi" } end
	if key:find("STAMINA") then return { "sta" } end
	if key:find("INTELLECT") then return { "int" } end
	if key:find("SPIRIT") then return { "spi" } end
	if key:find("DEFENSE") then return { "def" } end
	if key:find("DODGE") then return { "dodge" } end
	if key:find("PARRY") then return { "parry" } end
	if key:find("BLOCK") then return { "block" } end
	if key:find("MANA_REGEN") or key:find("POWER_REGEN0") then return { "mp5" } end
end

-- The tooltip's lines, for a client without GetItemStats (English text).
local LINES = {
	{ "^%+(%d+) Strength", { "str" } }, { "^%+(%d+) Agility", { "agi" } }, { "^%+(%d+) Stamina", { "sta" } },
	{ "^%+(%d+) Intellect", { "int" } }, { "^%+(%d+) Spirit", { "spi" } }, { "^%+(%d+) %a+ Resistance", { "res" } },
	{ "damage and healing done by magical spells and effects by up to (%d+)", { "sp", "heal" } },
	{ "damage done by .-spells and effects by up to (%d+)", { "sp" } },
	{ "healing done by spells and effects by up to (%d+)", { "heal" } },
	{ "%+(%d+) Attack Power", { "ap" } }, { "[Aa]ttack [Pp]ower by (%d+)", { "ap" } },
	{ "critical strike.- by (%d+)%%", { "crit" } }, { "chance to hit.- by (%d+)%%", { "hit" } },
	{ "Increased Defense %+(%d+)", { "def" } }, { "dodge.- by (%d+)%%", { "dodge" } },
	{ "parry.- by (%d+)%%", { "parry" } }, { "block.- by (%d+)", { "block" } },
	{ "(%d+) mana per 5 sec", { "mp5" } },
}

local cache = {}   -- link -> { stat = value } or false while the item loads

-- The item's stats by our ids, or nil while the game has not loaded it.
local function Stats(link, id)
	local known = cache[link]
	if known then return known end
	if not ItemInfo(link) then
		if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
		return
	end
	local out = {}
	local t = GetStats and GetStats(link)
	if type(t) == "table" and next(t) then
		for key, value in pairs(t) do
			for _, s in ipairs(StatIds(key) or {}) do out[s] = (out[s] or 0) + value end
		end
	elseif C_TooltipInfo and C_TooltipInfo.GetHyperlink then
		local data = C_TooltipInfo.GetHyperlink(link)
		for _, line in ipairs(data and data.lines or {}) do
			local text = line.leftText
			if type(text) == "string" then
				for _, p in ipairs(LINES) do
					local n = text:match(p[1])
					if n then
						for _, s in ipairs(p[2]) do out[s] = (out[s] or 0) + tonumber(n) end
					end
				end
			end
		end
	end
	cache[link] = out
	return out
end

---------------------------------------------------------------------------
-- The auction house: a browse of all armor and weapons, sorted by price.

local scanning, scanItems, scanStarted = false, nil, 0

local function ItemLink(id, suffix)
	if suffix and suffix ~= 0 then return string.format("item:%d:0:0:0:0:0:%d", id, suffix) end
	return "item:" .. id
end

local function ReadBrowse()
	local ah, db = C_AuctionHouse, ns.DB()
	if not ah or not ah.GetBrowseResults or not db then return end
	local results = ah.GetBrowseResults() or {}
	local now = time()
	local into = scanning and scanItems or db.ah.items
	for _, r in ipairs(results) do
		local key = r.itemKey
		if key and key.itemID and r.minPrice then
			local k = key.itemID .. ":" .. (key.itemSuffix or 0)
			into[k] = { id = key.itemID, suffix = key.itemSuffix, price = r.minPrice, qty = r.totalQuantity, at = now }
		end
	end
	local full = not ah.HasFullBrowseResults or ah.HasFullBrowseResults()
	if scanning then
		if not full and ah.RequestMoreBrowseResults then
			ah.RequestMoreBrowseResults()
			if frame then frame.scanText:SetText(string.format("Skannar ... %d föremål", #results)) end
			return
		end
		scanning = false
		db.ah = { at = now, items = scanItems }
		scanItems = nil
		local n = 0
		for _ in pairs(db.ah.items) do n = n + 1 end
		ns.Print(string.format("auktionshuset skannat: %d sorters rustning och vapen.", n))
	end
	if ns.RefreshSearch then ns.RefreshSearch() end
end

function ns.ScanAH()
	local ah = C_AuctionHouse
	if not ahOpen or not ah or not ah.SendBrowseQuery then
		ns.Print("öppna auktionshuset först.")
		return
	end
	local price = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
	local ok, err = pcall(ah.SendBrowseQuery, {
		searchString = "",
		sorts = { { sortOrder = price, reverseSort = false } },
		filters = {},
		itemClassFilters = { { classID = ARMOR }, { classID = WEAPON } },
	})
	if not ok then
		ns.Print("auktionshuset nekade skanningen: " .. tostring(err))
		return
	end
	scanning, scanItems, scanStarted = true, {}, GetTime()
	if frame then frame.scanText:SetText("Skannar ...") end
	C_Timer.After(60, function()
		if scanning and GetTime() - scanStarted >= 59 then
			scanning, scanItems = false, nil
			ns.Print("inget svar från auktionshuset på en minut; försök igen.")
			if ns.RefreshSearch then ns.RefreshSearch() end
		end
	end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
	"AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "GET_ITEM_INFO_RECEIVED" }) do
	pcall(events.RegisterEvent, events, event)
end
local redraw = false
events:SetScript("OnEvent", function(_, event)
	local db = ns.DB()
	if not db then return end
	db.ah = db.ah or { items = {} }
	if event == "AUCTION_HOUSE_SHOW" then
		ahOpen = true
	elseif event == "AUCTION_HOUSE_CLOSED" then
		ahOpen, scanning, scanItems = false, false, nil
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if redraw or not frame or not frame:IsShown() then return end
		redraw = true
		C_Timer.After(0.5, function()
			redraw = false
			ns.RefreshSearch()
		end)
		return
	else
		ReadBrowse()
		return
	end
	if ns.RefreshSearch then ns.RefreshSearch() end
end)

---------------------------------------------------------------------------
-- What to search: recipes and the auction house.

local function ShortName(charKey)
	return (charKey:match("^([^%-]+)")) or charKey
end

local function Candidates()
	local db = ns.DB()
	local out = {}
	if source ~= "ah" then
		for charKey, professions in pairs(db.chars or {}) do
			for profession, saved in pairs(professions) do
				for _, rec in pairs(saved.recipes or {}) do
					if rec.item then
						local link = ItemLink(rec.item)
						local e = out["r" .. rec.item]
						if e then
							e.who[ShortName(charKey)] = true
						else
							out["r" .. rec.item] = { id = rec.item, link = link, rec = rec, profession = profession,
								who = { [ShortName(charKey)] = true } }
						end
					end
				end
			end
		end
	end
	if source ~= "recipes" and db.ah then
		for k, a in pairs(db.ah.items or {}) do
			out["a" .. k] = { id = a.id, link = ItemLink(a.id, a.suffix), ah = a }
		end
	end
	return out
end

local function Wanted(id)
	local _, _, _, loc, _, class, sub = Instant(id)
	if not loc or not SLOT_OF[loc] then return end
	if next(picked.slots) and not picked.slots[SLOT_OF[loc]] then return end
	if next(picked.types) and not (class == ARMOR and picked.types[sub]) then return end
	return SLOT_OF[loc]
end

function ns.RefreshSearch()
	if not frame or not frame:IsShown() then return end
	frame.sources:Select(source)
	for _, c in ipairs(frame.chips) do c:Paint() end
	frame.canUse:SetChecked(ns.DB().canUse)

	local myLevel = UnitLevel("player")
	list = {}
	local waiting = 0
	for _, e in pairs(Candidates()) do
		local slot = Wanted(e.id)
		if slot then
			local stats = Stats(e.link, e.id)
			if not stats then
				waiting = waiting + 1
			else
				local ok, score = true, 0
				for s in pairs(picked.stats) do
					if not stats[s] or stats[s] <= 0 then ok = false break end
					score = score + stats[s]
				end
				local minLevel = select(5, ItemInfo(e.link))
				if ok and ns.DB().canUse and minLevel and minLevel > myLevel then ok = false end
				if ok then
					e.slot, e.stats, e.score, e.minLevel = slot, stats, score, minLevel
					table.insert(list, e)
				end
			end
		end
	end
	-- Most of the ticked stats first, then the cheapest.
	table.sort(list, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		local pa, pb = a.ah and a.ah.price or math.huge, b.ah and b.ah.price or math.huge
		if pa ~= pb then return pa < pb end
		return a.link < b.link
	end)

	offset = math.max(0, math.min(offset, #list - ROWS))
	for i, row in ipairs(rows) do
		local e = list[i + offset]
		row.entry = e
		if e then
			local name, _, quality = ItemInfo(e.link)
			local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
			row.cells[1]:SetText((color and color.hex or "|cffffffff") .. (name or ("föremål " .. e.id)) .. "|r")
			row.cells[2]:SetText(SLOT_NAME[e.slot] or "")
			row.cells[3]:SetText(e.minLevel and tostring(e.minLevel) or "")
			local shown = {}
			for _, s in ipairs(STATS) do
				local v = e.stats[s[1]]
				if v and v > 0 then
					local txt = v .. " " .. STAT_SHORT[s[1]]
					if picked.stats[s[1]] then txt = "|cffffd100" .. txt .. "|r" end
					table.insert(shown, txt)
				end
			end
			row.cells[4]:SetText(table.concat(shown, ", "))
			if e.ah then
				row.cells[5]:SetText("|cffffc040AH|r " .. ns.Money(e.ah.price))
			else
				local v = ns.Value(e.rec)
				row.cells[5]:SetText("|cff80c0ffRecept|r " .. (v.costKnown and ("~" .. ns.Money(v.cost)) or ""))
			end
			row:Show()
		else
			row:Hide()
		end
	end
	frame.scroll:Update(offset, ROWS, #list)

	local db = ns.DB()
	local parts = { string.format("%d träffar.", #list) }
	if waiting > 0 then table.insert(parts, string.format("Läser in %d föremål ...", waiting)) end
	if db.ah and db.ah.at then
		table.insert(parts, "AH skannat " .. date("%d/%m %H:%M", db.ah.at) .. ".")
	else
		table.insert(parts, "AH inte skannat än: öppna auktionshuset och tryck Skanna AH.")
	end
	if not next(db.chars or {}) then table.insert(parts, "Öppna ett yrkesfönster för att läsa in dina recept.") end
	frame.count:SetText(table.concat(parts, " "))
	if not scanning then frame.scanText:SetText("") end
	if ahOpen and not scanning then frame.scan:Enable() else frame.scan:Disable() end
	if waiting > 0 and not frame.retry then
		frame.retry = true
		C_Timer.After(1, function()
			frame.retry = false
			ns.RefreshSearch()
		end)
	end
end

---------------------------------------------------------------------------
-- The window.

-- A word that is on or off, gold when on.
local function Chip(parent, label, width, set, key)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, 20)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	local hover = b:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	if hover.SetColorTexture then hover:SetColorTexture(1, 1, 1, 0.08) end
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("CENTER")
	b.text:SetText(label)
	function b:Paint()
		local on = set[key]
		if self.bg.SetColorTexture then
			if on then self.bg:SetColorTexture(1, 0.82, 0, 0.35) else self.bg:SetColorTexture(1, 1, 1, 0.06) end
		end
		if on then self.text:SetTextColor(1, 0.9, 0.4) else self.text:SetTextColor(0.75, 0.75, 0.75) end
	end
	b:SetScript("OnClick", function()
		set[key] = not set[key] or nil
		offset = 0
		ns.RefreshSearch()
	end)
	return b
end

local function ShowTooltip(row)
	local e = row.entry
	if not e then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(e.link)
	GameTooltip:AddLine(" ")
	if e.ah then
		GameTooltip:AddLine(string.format("Auktionshuset: %s (%d till salu, %s)", ns.Money(e.ah.price), e.ah.qty or 0,
			date("%d/%m %H:%M", e.ah.at or 0)), 1, 0.75, 0.25)
		if ahOpen then GameTooltip:AddLine("Klicka för att söka efter det i auktionshuset.", 0.7, 0.7, 0.7) end
	else
		local who = {}
		for name in pairs(e.who) do table.insert(who, name) end
		table.sort(who)
		local v = ns.Value(e.rec)
		GameTooltip:AddLine(string.format("Recept (%s): %s", e.profession, table.concat(who, ", ")), 0.5, 0.75, 1)
		if v.costKnown then GameTooltip:AddLine("Reagenserna kostar ungefär " .. ns.Money(v.cost), 0.8, 0.8, 0.8) end
		GameTooltip:AddLine("Högerklicka för att lägga reagenserna i en inköpslista i Auctionator.", 0.7, 0.7, 0.7)
	end
	GameTooltip:AddLine("Shift-klicka för att länka i chatten.", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function SearchInAH(e)
	local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
	local name = ItemInfo(e.link)
	if not bar or not name then return end
	pcall(function()
		bar.SearchBox:SetText(name)
		bar:StartSearch()
	end)
end

local function Build()
	local portrait
	frame, portrait = Statskontoret.Window("KonsumentverketSearch", "Konsumentverket: sök utrustning", WIDTH, 580)
	local dy = portrait and -12 or 0
	local left = portrait and 66 or 24

	frame.sources = Statskontoret.Tabs(frame, { { "all", "Allt" }, { "recipes", "Mina recept" }, { "ah", "Auktionshuset" } },
		function(key) source, offset = key, 0 ns.RefreshSearch() end)
	frame.sources:SetPoint("TOPLEFT", left - 4, -28)

	frame.chips = {}
	local function Row(y, items, set, label, perRow)
		Text(frame, "GameFontNormalSmall", "TOPLEFT", 24, y):SetText(label)
		local w = (WIDTH - 48 - 4 * (perRow - 1)) / perRow
		for i, it in ipairs(items) do
			local c = Chip(frame, it[2], w, set, it[1])
			local col, line = (i - 1) % perRow, math.floor((i - 1) / perRow)
			c:SetPoint("TOPLEFT", 24 + col * (w + 4), y - 16 - line * 24)
			table.insert(frame.chips, c)
		end
	end
	Row(-62 + dy, STATS, picked.stats, "Statistik (föremålet måste ha allt du väljer):", 8)
	Row(-134 + dy, SLOTS, picked.slots, "Plats (ingen vald = alla):", 8)
	Row(-206 + dy, TYPES, picked.types, "Rustningstyp (ingen vald = alla):", 8)

	local canUse = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	canUse:SetSize(22, 22)
	canUse:SetPoint("TOPLEFT", 24 + 4 * ((WIDTH - 48 - 28) / 8 + 4) + 8, -221 + dy)
	canUse:SetScript("OnClick", function(self)
		ns.DB().canUse = self:GetChecked() and true or false
		offset = 0
		ns.RefreshSearch()
	end)
	Text(frame, "GameFontHighlightSmall", "LEFT", canUse, "RIGHT", 2, 0):SetText("Bara det jag kan bära nu (nivå)")
	frame.canUse = canUse

	local COLS = { { "Föremål", 210 }, { "Plats", 90 }, { "Nivå", 40 }, { "Statistik", 210 }, { "Var", 120 } }
	local x = 24
	for _, col in ipairs(COLS) do
		Text(frame, "GameFontNormalSmall", "TOPLEFT", x, -256 + dy):SetText(col[1])
		x = x + col[2]
	end
	Statskontoret.Rule(frame, 20, 20, -268 + dy, 0.2)
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetSize(WIDTH - 40, ROW_H)
		row:SetPoint("TOPLEFT", 20, -270 + dy - (i - 1) * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		Statskontoret.Stripe(row, i)
		row.cells = {}
		local cx = 4
		for c, col in ipairs(COLS) do
			local fs = Text(row, "GameFontHighlightSmall", "LEFT", cx, 0)
			fs:SetWidth(col[2] - 6)
			fs:SetWordWrap(false)
			row.cells[c] = fs
			cx = cx + col[2]
		end
		row:SetScript("OnEnter", ShowTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, mouse)
			local e = self.entry
			if not e then return end
			if mouse == "RightButton" then
				if e.rec then ns.ShopMenu(self, e.rec) end
			elseif IsShiftKeyDown() then
				local _, link = ItemInfo(e.link)
				if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
			elseif e.ah and ahOpen then
				SearchInAH(e)
			end
		end)
		rows[i] = row
	end
	frame.scroll = Statskontoret.ScrollMark(frame)
	frame.scroll:SetPoint("TOPRIGHT", -12, -272 + dy)
	frame.scroll:SetHeight(ROWS * ROW_H - 4)

	frame.count = Text(frame, "GameFontDisableSmall", "TOPLEFT", 24, -510 + dy)
	frame.count:SetWidth(WIDTH - 48)

	local bottom = portrait and 4 or 18
	frame.scan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.scan:SetSize(110, 22)
	frame.scan:SetText("Skanna AH")
	frame.scan:SetPoint("BOTTOMLEFT", 24, bottom)
	frame.scan:SetScript("OnClick", ns.ScanAH)
	local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clear:SetSize(110, 22)
	clear:SetText("Rensa val")
	clear:SetPoint("LEFT", frame.scan, "RIGHT", 8, 0)
	clear:SetScript("OnClick", function()
		for _, set in pairs(picked) do wipe(set) end
		offset = 0
		ns.RefreshSearch()
	end)
	frame.scanText = Text(frame, "GameFontHighlightSmall", "LEFT", clear, "RIGHT", 10, 0)

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta, #list - ROWS))
		ns.RefreshSearch()
	end)
	frame:Hide()
end

function ns.ToggleSearch()
	if not frame then Build() end
	if frame:IsShown() then frame:Hide() return end
	frame:Show()
	ns.RefreshSearch()
end
