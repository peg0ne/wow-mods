-- Konsumentverket: what your crafts are worth at a vendor, for levelling a
-- profession without losing money (or while making some).
--
-- For every recipe you know in the profession window last opened, it adds
-- up what the reagents cost and what a vendor pays for what you make, after
-- Skatteverket's tax on vendor sales. Every reagent costs what you would
-- pay for it: the vendor's price or the auction house's (Auctionator's
-- latest scan), whichever is lower (0.1.1; 0.1 counted mats you farm at
-- what a vendor pays for them, which made gear look cheap).
--
-- Vendor prices are noted whenever a merchant is open: only goods for gold
-- in unlimited stock, since limited stock sells out. Bokföring's own notes
-- (BokforingDB.vendor) fill in what we have not seen yet; it is only read.
--
-- Recipes are saved per character and profession, so /konsument works at
-- the vendor too, without the profession window open. The window also
-- opens beside the profession window (/konsument auto turns that off).
--
-- 0.2 adds an equipment search by stats (/konsument sök, Search.lua).

local _, ns = ...

local defaults = { auto = true, skillOnly = true }
local db

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffKonsumentverket:|r " .. text)
end
ns.Print = Print

local function CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

---------------------------------------------------------------------------
-- Money and prices.

-- "1g 2s 3c" with the coin letters in their colors; whole copper only.
function ns.Money(copper)
	copper = math.floor((copper or 0) + 0.5)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then table.insert(parts, g .. "|cffffd700g|r") end
	if s > 0 then table.insert(parts, s .. "|cffc7c7cfs|r") end
	if c > 0 or #parts == 0 then table.insert(parts, c .. "|cffeda55fc|r") end
	return sign .. table.concat(parts, " ")
end

local ItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local waiting = {}

-- What a vendor pays for one, or nil while the game has not loaded the item.
function ns.SellPrice(item)
	if not ItemInfo then return end
	local sell = select(11, ItemInfo(item))
	if sell == nil and not waiting[item] and C_Item and C_Item.RequestLoadItemDataByID then
		waiting[item] = true
		C_Item.RequestLoadItemDataByID(item)
	end
	return sell
end

function ns.ItemName(item)
	local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)) or (ItemInfo and ItemInfo(item))
	if not name then
		ns.SellPrice(item)
		return "föremål " .. item
	end
	return name
end

-- What a vendor charges for one, or nil when no vendor selling it has been
-- open; ours first, then Bokföring's.
function ns.BuyPrice(item)
	local own = db and db.vendor[item]
	if own then return own end
	local bok = type(BokforingDB) == "table" and type(BokforingDB.vendor) == "table" and BokforingDB.vendor[item]
	return type(bok) == "number" and bok or nil
end

-- The auction house's lowest price for one, from Auctionator's latest
-- scan, or nil without Auctionator or a price.
function ns.AHPrice(item)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not api or not api.GetAuctionPriceByItemID then return end
	local ok, price = pcall(api.GetAuctionPriceByItemID, "Konsumentverket", item)
	if ok and type(price) == "number" and price > 0 then return price end
end

-- What one costs to buy, and where: the cheaper of a vendor ("handlare")
-- and the auction house ("AH"); nil when neither is known.
function ns.Cost(item)
	local v, a = ns.BuyPrice(item), ns.AHPrice(item)
	if v and (not a or v <= a) then return v, "handlare" end
	if a then return a, "AH" end
end

-- Where it was bought: "Name, Zone", or nil.
function ns.BuyWhere(item)
	local at = db and db.vendorAt[item]
	if not at and type(BokforingDB) == "table" and type(BokforingDB.vendorAt) == "table" then at = BokforingDB.vendorAt[item] end
	if type(at) ~= "table" then return end
	return (at.npc or "?") .. ", " .. (at.zone or "?")
end

-- The share Skatteverket takes of vendor sales: its API's rate, else its
-- saved one; nothing without Skatteverket.
function ns.TaxRate()
	if SkatteverketAPI and SkatteverketAPI.TaxRate then
		local ok, rate = pcall(SkatteverketAPI.TaxRate)
		if ok and type(rate) == "number" and rate > 0 then return rate end
	end
	if type(SkatteverketDB) == "table" then return SkatteverketDB.rate or 0.05 end
	return 0
end

function ns.Have(item)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(item) or 0 end
	return GetItemCount and GetItemCount(item) or 0
end

-- A recipe's figures: cost (buying the reagents), out (what the vendor
-- pays for what it makes, after tax), profit, vendorOnly (every reagent
-- cheapest at a vendor), costKnown (every reagent has a price), known
-- (costKnown and the result's price too), canMake (from your bags) and
-- parts, one per reagent { item, n, each, kind = "handlare" | "AH" | nil }.
function ns.Value(rec)
	local keep = 1 - ns.TaxRate()
	local v = { cost = 0, vendorOnly = true, costKnown = true, parts = {} }
	local canMake
	for _, r in ipairs(rec.reagents) do
		local item, n = r[1], r[2]
		local part = { item = item, n = n }
		part.each, part.kind = ns.Cost(item)
		if part.kind ~= "handlare" then v.vendorOnly = false end
		if not part.each then v.costKnown = false end
		v.cost = v.cost + (part.each or 0) * n
		table.insert(v.parts, part)
		local times = math.floor(ns.Have(item) / n)
		canMake = canMake and math.min(canMake, times) or times
	end
	v.canMake = canMake or 0
	local sell = rec.item and ns.SellPrice(rec.item)
	v.known = v.costKnown and not (sell == nil and rec.item)
	v.each = sell or 0
	v.out = (sell or 0) * (rec.qty or 1) * keep
	v.profit = v.out - v.cost
	return v
end

---------------------------------------------------------------------------
-- Merchants: note what they sell for gold, in unlimited stock.

local function ReadMerchant()
	if not db or not GetMerchantNumItems then return end
	local npc, zone = UnitName("npc") or "?", GetZoneText and GetZoneText() or "?"
	for i = 1, GetMerchantNumItems() do
		local item = GetMerchantItemID and GetMerchantItemID(i)
		local price, quantity, available, extended
		if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
			local info = C_MerchantFrame.GetItemInfo(i)
			if info then price, quantity, available, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
		elseif GetMerchantItemInfo then
			local _
			_, _, price, quantity, available, _, _, extended = GetMerchantItemInfo(i)
		end
		if item and price and price > 0 and not extended and (available or -1) < 0 then
			db.vendor[item] = price / math.max(quantity or 1, 1)
			db.vendorAt[item] = { npc = npc, zone = zone }
		end
	end
end

---------------------------------------------------------------------------
-- Recipes: read from the open profession window.

-- The API's difficulty: 0 orange, 1 yellow, 2 green, 3 grey.
local DIFFICULTY = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }

local function ProfessionName(ui, id)
	if ui.GetProfessionInfoByRecipeID then
		local ok, info = pcall(ui.GetProfessionInfoByRecipeID, id)
		if ok and info then
			local name = info.parentProfessionName or info.professionName
			if name and name ~= "" then return name end
		end
	end
	if ui.GetTradeSkillLineForRecipe then
		local ok, _, lineName = pcall(ui.GetTradeSkillLineForRecipe, id)
		if ok and lineName and lineName ~= "" then return lineName end
	end
end

local function ReadRecipes()
	local ui = C_TradeSkillUI
	if not db or not ui or not ui.GetAllRecipeIDs or not ui.GetRecipeInfo or not ui.GetRecipeSchematic then return end
	-- Someone else's linked window, or the guild's, is not yours.
	if (ui.IsTradeSkillLinked and ui.IsTradeSkillLinked()) or (ui.IsTradeSkillGuild and ui.IsTradeSkillGuild()) then return end
	local recipes, profession = {}, nil
	for _, id in ipairs(ui.GetAllRecipeIDs() or {}) do
		local r = ui.GetRecipeInfo(id)
		local ok, s = pcall(ui.GetRecipeSchematic, id, false)
		if r and r.learned and ok and type(s) == "table" then
			profession = profession or ProfessionName(ui, id)
			local reagents = {}
			for _, slot in ipairs(s.reagentSlotSchematics or {}) do
				local reagent = slot.reagents and slot.reagents[1]
				-- Basic reagents only; optional and finishing ones are left out.
				if reagent and reagent.itemID and slot.required ~= false and slot.reagentType ~= 0 and slot.reagentType ~= 2 then
					table.insert(reagents, { reagent.itemID, slot.quantityRequired or 1 })
				end
			end
			local item = s.outputItemID
			recipes[id] = {
				name = r.name,
				item = item and item > 0 and item or nil,
				qty = ((s.quantityMin or 1) + (s.quantityMax or s.quantityMin or 1)) / 2,
				reagents = reagents,
				difficulty = DIFFICULTY[r.relativeDifficulty] or DIFFICULTY[r.difficulty] or "grey",
				skillUps = r.numSkillUps,
			}
		end
	end
	if not profession or not next(recipes) then return end
	local char = db.chars[CharKey()] or {}
	db.chars[CharKey()] = char
	char[profession] = { at = time(), recipes = recipes }
	ns.current = profession
	if ns.RefreshWindow then ns.RefreshWindow() end
end

-- The professions this character has saved, and the skill in each (from
-- GetProfessions; nil when the client can't say).
function ns.Professions()
	local char = db and db.chars[CharKey()] or {}
	local list = {}
	for name in pairs(char) do table.insert(list, name) end
	table.sort(list)
	return list, char
end

function ns.Skill(profession)
	if not GetProfessions or not GetProfessionInfo then return end
	for _, index in ipairs({ GetProfessions() }) do
		if index then
			local name, _, rank, max = GetProfessionInfo(index)
			if name == profession then return rank, max end
		end
	end
end

function ns.DB() return db end

---------------------------------------------------------------------------
-- Events and the command.

local readPending = false
local function ReadSoon()
	if readPending then return end
	readPending = true
	C_Timer.After(0.3, function()
		readPending = false
		ReadRecipes()
	end)
end

local redrawPending = false
local function RedrawSoon()
	if redrawPending or not ns.RefreshWindow then return end
	redrawPending = true
	C_Timer.After(0.5, function()
		redrawPending = false
		ns.RefreshWindow()
	end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
	"TRADE_SKILL_DATA_SOURCE_CHANGED", "MERCHANT_SHOW", "MERCHANT_UPDATE", "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= "Konsumentverket" then return end
		KonsumentverketDB = KonsumentverketDB or {}
		db = KonsumentverketDB
		db.vendor = db.vendor or {}
		db.vendorAt = db.vendorAt or {}
		db.chars = db.chars or {}
		for k, v in pairs(defaults) do
			if db[k] == nil then db[k] = v end
		end
		return
	end
	if not db then return end
	if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
		ReadMerchant()
		RedrawSoon()
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if arg1 then waiting[arg1] = nil end
		RedrawSoon()
	elseif event == "BAG_UPDATE_DELAYED" then
		RedrawSoon()
	elseif event == "TRADE_SKILL_SHOW" then
		ReadSoon()
		if db.auto and ns.ShowBesideProfession then C_Timer.After(0.4, ns.ShowBesideProfession) end
	elseif event == "TRADE_SKILL_CLOSE" then
		if ns.ProfessionClosed then ns.ProfessionClosed() end
	else
		ReadSoon()
	end
end)

SLASH_KONSUMENTVERKET1 = "/konsument"
SLASH_KONSUMENTVERKET2 = "/kv"
SlashCmdList.KONSUMENTVERKET = function(msg)
	msg = strtrim(msg or ""):lower()
	if not db then return end
	if msg == "auto" then
		db.auto = not db.auto
		Print(db.auto and "öppnas bredvid yrkesfönstret." or "öppnas bara med /konsument.")
	elseif msg == "plats" then
		db.dockPos = nil
		Print("fönstret öppnas bredvid yrkesfönstret igen, där det finns plats.")
	elseif msg == "sök" or msg == "sok" then
		ns.ToggleSearch()
	elseif msg == "" then
		ns.ToggleWindow()
	else
		Print("/konsument visar vad dina recept är värda hos en handlare, /konsument sök söker utrustning med den statistik du väljer, bland det dina recept gör och i auktionshuset, /konsument auto slår på eller av att fönstret öppnas bredvid yrkesfönstret (flytta det så öppnas det där nästa gång; /konsument plats glömmer platsen). Öppna yrkesfönstret en gång för att läsa in recepten, och handlare för att lära dig vad de tar för reagenserna.")
	end
end
