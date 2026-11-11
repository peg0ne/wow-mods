-- Revisorsinspektionen: checks Bokföring's books for Skatteverket's tax.
--
-- Bokföring (Zach's addon in the guild pack) takes the auction house's 5%
-- cut off a sale but not the guild tax. Skatteverket taxes the whole sale
-- mail (the price less the cut, plus the deposit back) at the guild's rate,
-- so a sale keeps about 0.95 x 0.95 = 90.25% of the listing price.
--
-- This addon never changes Bokföring's or Skatteverket's files or saved
-- data. It only reads them: SkatteverketDB.rate for the tax rate, and the
-- numbers Bokföring puts on each row of its window (row.data: cost, sells
-- after the cut, recipe). With Bokföring's window open it
--   * dims recipes whose markup on the auction house price is under the
--     limit (12% by default), or that lose money after tax, and
--   * adds the profit after tax to the recipe's tooltip.
--
-- Markup = listing price / material cost - 1. At 12% a sale keeps about
-- 1.1% of the cost after the cut and the tax, enough for the tax on the
-- deposit. Relisting costs a deposit each time; that is not counted.

local ADDON = ...
local AH_CUT = 0.05          -- Bokföring's ns.CUT
local DEFAULT_MIN = 0.12
local DIM_ALPHA = 0.35

local db
local rows = {}              -- Bokföring's row buttons found so far
local hooked = setmetatable({}, { __mode = "k" })
local dimmed = setmetatable({}, { __mode = "k" })

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Revisorsinspektionen:|r " .. text)
end

-- The guild's tax rate from Skatteverket's saved data, read only.
local function TaxRate()
	local sv = SkatteverketDB
	local rate = type(sv) == "table" and sv.rate
	if type(rate) == "number" and rate >= 0 and rate < 1 then return rate end
	return 0.05
end

local function Money(copper)
	local neg = copper < 0
	copper = math.floor(math.abs(copper) + 0.5)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then table.insert(parts, g .. "|cffffd700g|r") end
	if s > 0 then table.insert(parts, s .. "|cffc7c7cfs|r") end
	if c > 0 or #parts == 0 then table.insert(parts, c .. "|cffeda55fc|r") end
	return (neg and "-" or "") .. table.concat(parts, " ")
end

local function Percent(x)
	return string.format("%d%%", math.floor(x * 100 + 0.5))
end

-- A recipe row's numbers after tax; nil for rows that are not recipes with
-- a cost and a price (gathering, fold-outs, history).
local function Audit(r)
	if type(r) ~= "table" or r.learn or type(r.recipe) ~= "table" then return end
	if type(r.cost) ~= "number" or type(r.sells) ~= "number" then return end
	local rate = TaxRate()
	local a = { rate = rate }
	a.listing = r.sells / (1 - AH_CUT)
	a.tax = r.sells * rate
	a.profit = r.sells - a.tax - r.cost
	a.markup = r.cost > 0 and (a.listing / r.cost - 1) or nil
	-- The lowest listing price that breaks even after the cut and the tax.
	a.breakEven = r.cost / ((1 - AH_CUT) * (1 - rate))
	if type(r.sold) == "number" and type(r.recipe.qty) == "number" and r.recipe.qty > 0 then
		a.perDay = a.profit * r.sold / r.recipe.qty
	end
	a.below = a.profit < 0 or (a.markup ~= nil and a.markup < db.min)
	return a
end

local function OnEnter(row)
	if not db.tooltip then return end
	local r = row.data
	local a = Audit(r)
	if not a or not GameTooltip:IsOwned(row) then return end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Revisorsinspektionen", 1, 0.82, 0)
	local good = a.profit >= 0
	GameTooltip:AddDoubleLine(string.format("Vinst efter skatt (%s)", Percent(a.rate)), Money(a.profit),
		1, 1, 1, good and 0.25 or 1, good and 1 or 0.25, 0.25)
	GameTooltip:AddDoubleLine("Skatt", Money(a.tax), 1, 1, 1, 1, 1, 1)
	if a.perDay then GameTooltip:AddDoubleLine("Vinst/dag efter skatt", Money(a.perDay), 1, 1, 1, 1, 1, 1) end
	if a.markup then
		local ok = a.markup >= db.min
		GameTooltip:AddDoubleLine(string.format("Påslag (gräns %s)", Percent(db.min)), Percent(a.markup),
			1, 1, 1, ok and 0.25 or 1, ok and 1 or 0.5, 0.25)
	end
	GameTooltip:AddDoubleLine("Går jämnt ut vid", Money(a.breakEven) .. (r.recipe.qty ~= 1 and " totalt" or ""), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
	GameTooltip:AddLine("Insättningen beskattas också, och en omlistning kostar en ny insättning.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

-- Bokföring's row buttons: children of its window with .cells and .wide.
local function Find(frame, depth)
	if depth > 4 then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		if type(child.cells) == "table" and child.wide and not hooked[child] then
			hooked[child] = true
			table.insert(rows, child)
			child:HookScript("OnEnter", OnEnter)
		end
		Find(child, depth + 1)
	end
end

local function Apply()
	for _, row in ipairs(rows) do
		local a = db.dim and row:IsShown() and Audit(row.data)
		if a and a.below then
			if not dimmed[row] then row:SetAlpha(DIM_ALPHA) dimmed[row] = true end
		elseif dimmed[row] then
			row:SetAlpha(1)
			dimmed[row] = nil
		end
	end
end

-- Bokföring makes its window on the first /bok and refreshes rows on its
-- own; look a few times a second while the window is open.
local watcher = CreateFrame("Frame")
local sinceFind, sinceApply = 10, 0
watcher:SetScript("OnUpdate", function(_, elapsed)
	local f = BokforingFrame
	if not db or not f or not f:IsShown() then sinceFind = 10 return end
	sinceFind, sinceApply = sinceFind + elapsed, sinceApply + elapsed
	if sinceFind >= 2 then sinceFind = 0 Find(f, 0) end
	if sinceApply >= 0.2 then sinceApply = 0 Apply() end
end)

local function Status()
	Print(string.format("dämpar recept under %s påslag: %s. Rader i Bokföringens tips: %s. Skattesats %s.",
		Percent(db.min), db.dim and "på" or "av", db.tooltip and "på" or "av", Percent(TaxRate())))
	if not BokforingFrame and not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Bokforing")) then
		Print("Bokföring är inte på; då har jag inget att granska.")
	end
end

SLASH_REVISORSINSPEKTIONEN1 = "/revisor"
SlashCmdList.REVISORSINSPEKTIONEN = function(msg)
	msg = strtrim((msg or ""):lower())
	local limit = msg:match("^gräns%s+(%-?[%d%.,]+)%%?$") or msg:match("^min%s+(%-?[%d%.,]+)%%?$")
	if limit then
		local n = tonumber((limit:gsub(",", ".")))
		if not n or n < -100 or n > 1000 then Print("skriv till exempel /revisor gräns 12.") return end
		db.min = n / 100
		Print("dämpar recept under " .. Percent(db.min) .. " påslag.")
		Apply()
	elseif msg == "dämpa" or msg == "dampa" then
		db.dim = not db.dim
		Print("dämpning " .. (db.dim and "på." or "av."))
		Apply()
	elseif msg == "tips" then
		db.tooltip = not db.tooltip
		Print("rader i Bokföringens tips " .. (db.tooltip and "på." or "av."))
	elseif msg == "" then
		Status()
		Print("/revisor gräns 12 sätter gränsen, /revisor dämpa och /revisor tips slår av och på.")
	else
		Print("okänt kommando. /revisor visar inställningarna.")
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON then return end
	self:UnregisterEvent("ADDON_LOADED")
	RevisorsinspektionenDB = RevisorsinspektionenDB or {}
	db = RevisorsinspektionenDB
	if db.min == nil then db.min = DEFAULT_MIN end
	if db.dim == nil then db.dim = true end
	if db.tooltip == nil then db.tooltip = true end
end)
