-- Skolverket: item tooltips naming who in THÖNDERSTÖRM can craft the item,
-- on WoW Forever.
--
-- Until 0.2 Skolverket was a whole crafting directory; Skatteverket 0.22 has
-- one now (/skatt yrken). 0.3-0.5 also shared profession cooldowns on the
-- guild channel and listed them in /skola; 0.6 drops that (nobody used it),
-- so it sends nothing and has no window. What's left is read from the
-- recipes Skatteverket keeps (SkatteverketDB.recipes).
--
-- SkolverketDB and SkolverketCharDB held the cooldowns; 0.6 empties them.
-- Never rename these or the folder.

local _, ns = ...

ns.GUILD = "THÖNDERSTÖRM"

local ready = false
ns.online = {}
local inGuild                -- name -> true from the last full roster, or nil before it loads

function ns.Short(name)
	if not name then return nil end
	if Ambiguate then return Ambiguate(name, "none") end
	return (name:gsub("%-.*", ""))
end

function ns.InOurGuild()
	return GetGuildInfo("player") == ns.GUILD
end

-- This character's full name as the guild sees it. Forever names have two
-- words and UnitName gives only the first, so look it up by GUID in the
-- roster; nil until the roster has loaded.
local myName
function ns.Me()
	if myName then return myName end
	local guid, first = UnitGUID("player"), UnitName("player")
	local match, count = nil, 0
	for i = 1, GetNumGuildMembers() do
		local info = { GetGuildRosterInfo(i) }
		local name = ns.Short(info[1])
		if name and guid and info[17] == guid then
			myName = name
			return name
		end
		if name and name:match("^(%S+)") == first then match, count = name, count + 1 end
	end
	if count == 1 then
		myName = match
		return match
	end
end

function ns.IsMe(name)
	local me = ns.Me()
	if me then return name == me end
	return name == UnitName("player") or (name and name:match("^(%S+)") == UnitName("player"))
end

-- Who is online (green on the tooltip), and with the offline members shown,
-- who is still in the guild: lists of members who left are skipped.
local function OnRoster()
	local n = GetNumGuildMembers()
	if n == 0 then return end
	local online, all = {}, {}
	for i = 1, n do
		local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
		name = ns.Short(name)
		if name then
			all[name] = true
			if isOnline then online[name] = true end
		end
	end
	ns.online = online
	if ns.InOurGuild() and GetGuildRosterShowOffline and GetGuildRosterShowOffline() then inGuild = all end
end

---------------------------------------------------------------------------
-- Item tooltips: who in the guild can craft this, from Skatteverket's
-- recipe lists. On Forever they hold recipe numbers ("s<recipeID>" plus a
-- difficulty letter); the item a recipe makes is looked up once per recipe.
-- The index is rebuilt when any list's time stamp changes.

local recipeItem = {}        -- recipeID -> itemID, or false if it makes none
local crafters, signature = {}, nil   -- itemID -> { name = true }

local function ItemOfRecipe(id)
	local v = recipeItem[id]
	if v ~= nil then return v end
	v = false
	local T = C_TradeSkillUI
	if T and T.GetRecipeSchematic then
		local ok, s = pcall(T.GetRecipeSchematic, id, false)
		if ok and s and s.outputItemID then v = s.outputItemID end
	end
	if not v and T and T.GetRecipeOutputItemData then
		local ok, out = pcall(T.GetRecipeOutputItemData, id)
		if ok and out and out.itemID then v = out.itemID end
	end
	recipeItem[id] = v
	return v
end

local function RecipeLists()
	local recipes = SkatteverketDB and SkatteverketDB.recipes
	return type(recipes) == "table" and recipes or nil
end

local function Signature(recipes)
	local sum, count = 0, 0
	for _, lists in pairs(recipes) do
		if type(lists) == "table" then
			for _, list in pairs(lists) do
				if type(list) == "table" then
					sum, count = sum + (tonumber(list.at) or 0), count + 1
				end
			end
		end
	end
	return sum .. ":" .. count
end

local function Crafters(itemID)
	local recipes = RecipeLists()
	if not recipes then return nil end
	local sig = Signature(recipes)
	if sig ~= signature then
		signature, crafters = sig, {}
		for name, lists in pairs(recipes) do
			if type(lists) == "table" and (not inGuild or inGuild[name]) then
				for _, list in pairs(lists) do
					for _, key in ipairs(type(list) == "table" and type(list.keys) == "table" and list.keys or {}) do
						local kind, id = tostring(key):match("^([si])(%d+)")
						local item = kind == "i" and tonumber(id) or (kind == "s" and ItemOfRecipe(tonumber(id)))
						if item then
							crafters[item] = crafters[item] or {}
							crafters[item][name] = true
						end
					end
				end
			end
		end
	end
	return crafters[itemID]
end

local function AddCrafterLine(tooltip, link)
	-- The client may hide values from addons (in combat, for instance);
	-- a hidden link cannot be read, so add nothing.
	if issecretvalue and issecretvalue(link) then return end
	if not ready or type(link) ~= "string" or not ns.InOurGuild() then return end
	local itemID = tonumber(link:match("item:(%d+)"))
	local who = itemID and Crafters(itemID)
	if not who then return end
	local list = {}
	for name in pairs(who) do
		table.insert(list, { name = name, me = ns.IsMe(name), online = ns.online[name] and true or false })
	end
	table.sort(list, function(a, b)
		if a.me ~= b.me then return a.me end
		if a.online ~= b.online then return a.online end
		return a.name < b.name
	end)
	local names = {}
	for i = 1, math.min(4, #list) do
		local c = list[i]
		local name = c.me and "du" or c.name
		table.insert(names, (c.me or c.online) and ("|cff40ff40" .. name .. "|r") or ("|cff999999" .. name .. "|r"))
	end
	if #list > 4 then table.insert(names, string.format("+%d", #list - 4)) end
	tooltip:AddLine("Kan tillverkas av: " .. table.concat(names, ", "), 1, 0.6, 0.2)
	tooltip:Show()
end

local function HookTooltips()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
			if tooltip.GetItem then pcall(AddCrafterLine, tooltip, select(2, tooltip:GetItem())) end
		end)
		return
	end
	for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
		if tooltip then
			pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self)
				pcall(AddCrafterLine, self, select(2, self:GetItem()))
			end)
		end
	end
end

---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		if name == "Skolverket" then
			-- The old cooldown lists: nothing reads them any more.
			SkolverketDB, SkolverketCharDB = nil, nil
			ready = true
			HookTooltips()
		end
	elseif event == "PLAYER_LOGIN" then
		Statskontoret.RequestRoster()
	elseif event == "GUILD_ROSTER_UPDATE" then
		OnRoster()
	end
end)
