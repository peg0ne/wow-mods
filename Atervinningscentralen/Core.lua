-- Återvinningscentralen: sells gray items and repairs gear at vendors.
-- Selling happens a few items at a time so the server keeps up, and it
-- stops the moment the vendor closes (using an item away from a vendor
-- would equip or use it instead of selling it). Repairs come after the
-- sales, so the junk money helps pay for them.
-- Hold Shift while opening a vendor to skip everything. /avc for settings.
--
-- Skatteverket counts gold gained while a vendor is open as income, so the
-- gray sales are taxed exactly like selling by hand. Repairs are not income.

local _, ns = ...

local BATCH = 6          -- items sold per tick
local INTERVAL = 0.2     -- seconds between ticks

local defaults = { sell = true, repair = true }
local db
local merchantOpen = false
local ticker, queue, sold

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33cc66Återvinningscentralen:|r " .. text)
end

local function Money(copper)
	copper = math.floor(copper or 0)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then return string.format("%dg %ds %dc", g, s, c) end
	if s > 0 then return string.format("%ds %dc", s, c) end
	return string.format("%dc", c)
end

-- Forever's client has C_Item.GetItemInfo but not the old global.
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)

-- Bag API: C_Container on newer clients, the old globals on older ones.
local C = C_Container
local NumSlots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
local UseItem = (C and C.UseContainerItem) or UseContainerItem

-- link, count, locked, quality, noValue for one bag slot (nil if empty).
local function SlotInfo(bag, slot)
	local link, count, locked, quality, noValue
	if C and C.GetContainerItemInfo then
		local info = C.GetContainerItemInfo(bag, slot)
		if not info then return end
		link, count, locked, quality, noValue = info.hyperlink, info.stackCount, info.isLocked, info.quality, info.hasNoValue
	else
		local _
		_, count, locked, quality, _, _, link, _, noValue = GetContainerItemInfo(bag, slot)
		if not link then return end
	end
	if not quality or quality < 0 then quality = select(3, GetItemInfo(link)) end
	return link, count or 1, locked, quality, noValue
end

-- MERCHANT_SHOW and MERCHANT_CLOSED are what count: on Forever's client the
-- MerchantFrame is not yet shown when MERCHANT_SHOW arrives.
local function VendorOpen()
	return merchantOpen
end

-- Every gray item with a sell price, as { bag, slot, link, value }.
local function FindJunk()
	local list = {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, NumSlots(bag) or 0 do
			local link, count, _, quality, noValue = SlotInfo(bag, slot)
			if link and quality == 0 and not noValue then
				local price = select(11, GetItemInfo(link))
				if price and price > 0 then
					table.insert(list, { bag = bag, slot = slot, link = link, value = price * count })
				end
			end
		end
	end
	return list
end

local function Repair()
	if not db.repair or not CanMerchantRepair or not CanMerchantRepair() then return 0 end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or not cost or cost <= 0 then return 0 end
	if cost > GetMoney() then
		Print("har inte råd att laga allt (" .. Money(cost) .. ").")
		return 0
	end
	RepairAllItems()
	return cost
end

local function Finish()
	if ticker then ticker:Cancel() ticker = nil end
	if not VendorOpen() then
		if sold and sold.items > 0 then
			Print(string.format("handlaren stängdes; sålde %d saker för %s.", sold.items, Money(sold.value)))
		end
		queue, sold = nil, nil
		return
	end
	local repaired = Repair()
	local parts = {}
	if sold and sold.items > 0 then
		table.insert(parts, string.format("sålde %d saker för %s", sold.items, Money(sold.value)))
	end
	if repaired > 0 then table.insert(parts, "lagade utrustningen för " .. Money(repaired)) end
	if #parts > 0 then Print(table.concat(parts, ", ") .. ".") end
	queue, sold = nil, nil
end

local function Tick()
	if not queue then
		if ticker then ticker:Cancel() ticker = nil end
		return
	end
	for _ = 1, BATCH do
		if not VendorOpen() then Finish() return end
		local item = table.remove(queue)
		if not item then Finish() return end
		-- Sell only if the slot still holds the same, unlocked item.
		local link, _, locked = SlotInfo(item.bag, item.slot)
		if link == item.link and not locked then
			UseItem(item.bag, item.slot)
			sold.items = sold.items + 1
			sold.value = sold.value + item.value
		end
	end
end

local visit = 0   -- counts vendor openings, so a late timer from an earlier one does nothing

local function OnMerchantShow()
	visit = visit + 1
	local thisVisit = visit
	if ticker then ticker:Cancel() ticker = nil end
	queue, sold = nil, nil
	if IsShiftKeyDown() then return end
	queue = db.sell and FindJunk() or {}
	sold = { items = 0, value = 0 }
	-- Give the vendor a moment to finish opening before selling or repairing.
	C_Timer.After(0.3, function()
		if thisVisit ~= visit or not queue then return end
		if #queue == 0 then Finish() return end
		ticker = C_Timer.NewTicker(INTERVAL, Tick)
		Tick()
	end)
end

-- /avc test: what would be sold, without a vendor.
local function Test()
	local junk = FindJunk()
	local total = 0
	for _, item in ipairs(junk) do
		total = total + item.value
		Print(string.format("väska %d plats %d: %s, %s", item.bag, item.slot, item.link, Money(item.value)))
	end
	Print(string.format("skulle sälja %d saker för %s.", #junk, Money(total)))
	if CanMerchantRepair then
		local cost = GetRepairAllCost()
		Print("lagning kostar " .. Money(cost or 0) .. " (syns bara hos en handlare som lagar).")
	end
end

local function Status()
	Print(string.format("sälja grått: %s, laga: %s. Håll Shift när du öppnar en handlare för att hoppa över.",
		db.sell and "på" or "av", db.repair and "på" or "av"))
end

SLASH_ATERVINNING1 = "/avc"
SLASH_ATERVINNING2 = "/atervinning"
SlashCmdList.ATERVINNING = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "sälj" or msg == "salj" then
		db.sell = not db.sell
	elseif msg == "laga" then
		db.repair = not db.repair
	elseif msg == "test" then
		Test()
		return
	elseif msg ~= "" then
		Print("/avc visar inställningarna, /avc sälj slår på eller av försäljning, /avc laga slår på eller av lagning, /avc test visar vad som skulle säljas.")
		return
	end
	Status()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == "Atervinningscentralen" then
		AtervinningscentralenDB = AtervinningscentralenDB or {}
		db = AtervinningscentralenDB
		for k, v in pairs(defaults) do
			if db[k] == nil then db[k] = v end
		end
	elseif event == "MERCHANT_SHOW" then
		merchantOpen = true
		OnMerchantShow()
	elseif event == "MERCHANT_CLOSED" then
		merchantOpen = false
		if ticker then Finish() end
	end
end)
