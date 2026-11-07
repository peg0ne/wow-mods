-- Eniro: guild members who share their position, as class-colored dots on
-- the world map. A position on a zone map is also shown on its continent
-- (and any other map that contains it) by placing the zone's rectangle on
-- the map being viewed. Hover a dot for name, level and zone.

local _, ns = ...

local pins, canvas = {}, nil

local function Canvas()
	if canvas then return canvas end
	local scroll = WorldMapFrame and WorldMapFrame.ScrollContainer
	canvas = scroll and scroll.Child
	return canvas
end

-- Where map position (x, y) on `map` falls on the map being viewed, or nil.
local function Place(map, x, y, viewed)
	if map == viewed then return x, y end
	if not C_Map.GetMapRectOnMap then return end
	local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, map, viewed)
	if not ok or not minX or maxX == minX then return end
	local px, py = minX + x * (maxX - minX), minY + y * (maxY - minY)
	if px < 0 or px > 1 or py < 0 or py > 1 then return end
	return px, py
end

local function Pin(i)
	local pin = pins[i]
	if pin then return pin end
	pin = CreateFrame("Frame", nil, Canvas())
	pin:SetSize(16, 16)
	pin:SetFrameLevel(Canvas():GetFrameLevel() + 500)
	pin.icon = pin:CreateTexture(nil, "OVERLAY")
	pin.icon:SetAllPoints()
	pin.icon:SetTexture("Interface\\WorldMap\\WorldMapPartyIcon")
	pin:EnableMouse(true)
	pin:SetScript("OnEnter", function(self)
		local m = self.member
		if not m then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(m.name)
		GameTooltip:AddLine(string.format("Nivå %s %s, %s", m.level or "?", m.class or "", m.zone or ""), 1, 1, 1)
		local d = ns.Distance(ns.positions[m.name])
		if d then GameTooltip:AddLine(ns.DistanceText(d), 0.6, 0.8, 1) end
		GameTooltip:Show()
	end)
	pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
	pins[i] = pin
	return pin
end

function ns.DistanceText(yards)
	local metres = yards * 0.9144
	if metres < 1000 then return string.format("%d m bort", math.floor(metres / 10 + 0.5) * 10) end
	return string.format("%.1f km bort", metres / 1000)
end

function ns.RefreshPins()
	local c = Canvas()
	if not c or not WorldMapFrame:IsShown() then return end
	local viewed = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	local w, h = c:GetSize()
	local scale = c:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local n = 0
	if viewed and w and w > 0 then
		for name, p in pairs(ns.positions) do
			local px, py = Place(p.map, p.x, p.y, viewed)
			if px then
				n = n + 1
				local pin = Pin(n)
				local m = ns.members[name] or { name = name }
				pin.member = m
				-- Same size on screen however far the map is zoomed.
				pin:SetSize(16 / scale, 16 / scale)
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", c, "TOPLEFT", px * w, -py * h)
				local color = m.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.classFile]
				if color then pin.icon:SetVertexColor(color.r, color.g, color.b) else pin.icon:SetVertexColor(1, 1, 1) end
				pin:Show()
			end
		end
	end
	for i = n + 1, #pins do pins[i]:Hide() end
end

-- The map changes zoom and zone without telling addons in every client
-- version, so refresh a few times a second while it is open. Some clients
-- load the map later than this addon; then hook it once it loads.
local hooked = false
local function HookMap()
	if hooked or not WorldMapFrame then return end
	hooked = true
	local elapsed = 0
	WorldMapFrame:HookScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed > 0.25 then
			elapsed = 0
			ns.RefreshPins()
		end
	end)
	WorldMapFrame:HookScript("OnHide", function()
		for _, pin in ipairs(pins) do pin:Hide() end
	end)
end

HookMap()
if not hooked then
	local waiter = CreateFrame("Frame")
	waiter:RegisterEvent("ADDON_LOADED")
	waiter:SetScript("OnEvent", function(self)
		HookMap()
		if hooked then self:UnregisterAllEvents() end
	end)
end
