-- Lantmäteriet: the nodes the guild knows, as pins on the world map and the
-- minimap. A pin is the node's icon, bright when you can gather it and dim
-- when your skill is too low; hover it for the name, what it needs and who
-- found it when. Only your own professions' nodes unless /lm alla.
--
-- World map: like Eniro's dots, a node on a zone map also shows on the
-- continent (through C_Map.GetMapRectOnMap), and on OpenMap's stitched map
-- through OpenMapAPI. Minimap: nodes on the map you are on, placed by their
-- distance in yards; the minimap's size in yards depends on its zoom and
-- on whether you are indoors.

local _, ns = ...

---------------------------------------------------------------------------
-- Shared.

local function Look(icon, node)
	local kind, need = ns.NodeInfo(node.name)
	icon:SetTexture(ns.ICON[kind])
	local can = ns.CanGather(ns.Status(kind, need))
	icon:SetDesaturated(not can)
	icon:SetAlpha(can and 1 or 0.5)
end

local function Ago(t)
	local days = math.floor((GetServerTime() - (t or 0)) / 86400)
	if days <= 0 then return "i dag" end
	if days == 1 then return "i går" end
	return days .. " dagar sedan"
end

local function Tip(self)
	local node = self.node
	if not node then return end
	local kind, need = ns.NodeInfo(node.name)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(node.name)
	local c = ns.STATUS_COLOR[ns.Status(kind, need)]
	GameTooltip:AddLine(ns.NeedText(kind, need), c[1], c[2], c[3])
	local who = node.mine and "dig" or (node.by or "någon i gillet")
	GameTooltip:AddLine("Senast sedd av " .. who .. ", " .. Ago(node.t), 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function Shown(node)
	local kind = ns.NodeInfo(node.name)
	return kind and ns.ShowKind(kind)
end

---------------------------------------------------------------------------
-- World map.

local mapPins, canvas = {}, nil

local function Canvas()
	if canvas then return canvas end
	local scroll = WorldMapFrame and WorldMapFrame.ScrollContainer
	canvas = scroll and scroll.Child
	return canvas
end

-- Where a map's rectangle falls on the map being viewed: minX, maxX,
-- minY, maxY, or nil when it isn't on it.
local function Rect(map, viewed)
	if map == viewed then return 0, 1, 0, 1 end
	if not C_Map.GetMapRectOnMap then return end
	local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, map, viewed)
	if not ok or not minX or maxX == minX then return end
	return minX, maxX, minY, maxY
end

local function Stitched()
	local api = OpenMapAPI
	if not api or not api.IsStitched or not api.WorldFromMap or not api.MapFromWorld then return false end
	local ok, on = pcall(api.IsStitched)
	return ok and on or false
end

-- On OpenMap's stitched map: where a node falls, past the map's edges too.
local function StitchedSpot(map, x, y, viewed)
	local ok, u, v = pcall(OpenMapAPI.WorldFromMap, map, x, y)
	if not ok or not u then return end
	local ok2, px, py = pcall(OpenMapAPI.MapFromWorld, viewed, u, v)
	if ok2 and px and px > -3 and px < 4 and py > -3 and py < 4 then return px, py end
end

local function PinLevel(c)
	local level = c:GetFrameLevel() + 400
	local art = OpenMapAPI and OpenMapAPI.ArtTopLevel and OpenMapAPI.ArtTopLevel()
	if type(art) == "number" and art + 4 > level then level = art + 4 end
	return level
end

local function MapPin(i)
	local pin = mapPins[i]
	if pin then return pin end
	pin = CreateFrame("Frame", nil, Canvas())
	pin.icon = pin:CreateTexture(nil, "OVERLAY")
	pin.icon:SetAllPoints()
	pin:EnableMouse(true)
	pin:SetScript("OnEnter", Tip)
	pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
	mapPins[i] = pin
	return pin
end

local MAX_MAP_PINS = 600

local function RefreshMap()
	local c = Canvas()
	if not c or not WorldMapFrame:IsShown() then return end
	local n = 0
	local viewed = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	local w, h = c:GetSize()
	if ns.db.map and viewed and w and w > 0 then
		local scale = c:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local size = 12 / scale
		local level = PinLevel(c)
		local stitched = Stitched()
		for map, list in pairs(ns.db.nodes) do
			local minX, maxX, minY, maxY
			if not stitched then minX, maxX, minY, maxY = Rect(map, viewed) end
			for _, node in ipairs((stitched or minX) and list or {}) do
				if n >= MAX_MAP_PINS then break end
				if Shown(node) then
					local px, py
					if stitched then
						px, py = StitchedSpot(map, node.x, node.y, viewed)
					else
						px, py = minX + node.x * (maxX - minX), minY + node.y * (maxY - minY)
						if px < 0 or px > 1 or py < 0 or py > 1 then px = nil end
					end
					if px then
						n = n + 1
						local pin = MapPin(n)
						pin.node = node
						pin:SetSize(size, size)
						if pin:GetFrameLevel() ~= level and not InCombatLockdown() then pin:SetFrameLevel(level) end
						pin:ClearAllPoints()
						pin:SetPoint("CENTER", c, "TOPLEFT", px * w, -py * h)
						Look(pin.icon, node)
						pin:Show()
					end
				end
			end
		end
	end
	for i = n + 1, #mapPins do mapPins[i]:Hide() end
end

local hooked = false
local function HookMap()
	if hooked or not WorldMapFrame then return end
	hooked = true
	local elapsed = 0
	WorldMapFrame:HookScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed > 0.5 then
			elapsed = 0
			RefreshMap()
		end
	end)
	WorldMapFrame:HookScript("OnHide", function()
		for _, pin in ipairs(mapPins) do pin:Hide() end
	end)
end

---------------------------------------------------------------------------
-- Minimap.

-- The minimap's diameter in yards at each zoom level (0-5).
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }
local MAX_MINI_PINS = 60

local miniPins = {}

local function MiniPin(i)
	local pin = miniPins[i]
	if pin then return pin end
	pin = CreateFrame("Frame", nil, Minimap)
	pin:SetSize(12, 12)
	pin:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	pin.icon = pin:CreateTexture(nil, "OVERLAY")
	pin.icon:SetAllPoints()
	pin:EnableMouse(true)
	pin:SetScript("OnEnter", Tip)
	pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
	miniPins[i] = pin
	return pin
end

local function GetSetting(name)
	local get = C_CVar and C_CVar.GetCVar or GetCVar
	local ok, v = pcall(get, name)
	if ok then return v end
end

local function RefreshMinimap()
	local n = 0
	local map, x, y
	if ns.db and ns.db.minimap and Minimap:IsVisible() then map, x, y = ns.MyPosition() end
	local list = map and ns.Nodes(map)
	local w, h
	if map then w, h = ns.MapYards(map) end
	if list and w then
		local zoom = Minimap:GetZoom() or 0
		local indoors = IsIndoors and IsIndoors()
		local yards = (indoors and INDOOR or OUTDOOR)[zoom] or 400
		local radius = Minimap:GetWidth() / 2
		local perYard = radius * 2 / yards
		local facing = GetSetting("rotateMinimap") == "1" and GetPlayerFacing and GetPlayerFacing()
		local cosF, sinF = 1, 0
		if facing then cosF, sinF = math.cos(-facing), math.sin(-facing) end
		for _, node in ipairs(list) do
			if n >= MAX_MINI_PINS then break end
			if Shown(node) then
				-- East and north of you, in yards.
				local east, north = (node.x - x) * w, (y - node.y) * h
				if east * east + north * north < (yards / 2) ^ 2 then
					if facing then east, north = east * cosF - north * sinF, east * sinF + north * cosF end
					local px, py = east * perYard, north * perYard
					if px * px + py * py <= (radius - 4) ^ 2 then
						n = n + 1
						local pin = MiniPin(n)
						pin.node = node
						pin:ClearAllPoints()
						pin:SetPoint("CENTER", Minimap, "CENTER", px, py)
						Look(pin.icon, node)
						pin:Show()
					end
				end
			end
		end
	end
	for i = n + 1, #miniPins do miniPins[i]:Hide() end
end

---------------------------------------------------------------------------

function ns.RefreshPins()
	if not ns.db then return end
	RefreshMap()
	RefreshMinimap()
end

local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, dt)
	since = since + dt
	if since < 0.1 then return end
	since = 0
	if ns.db then RefreshMinimap() end
end)

HookMap()
if not hooked then
	local waiter = CreateFrame("Frame")
	waiter:RegisterEvent("ADDON_LOADED")
	waiter:SetScript("OnEvent", function(self)
		HookMap()
		if hooked then self:UnregisterAllEvents() end
	end)
end
