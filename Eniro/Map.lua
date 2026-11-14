-- Eniro: guild members who share their position, as class-colored dots on
-- the world map. A position on a zone map is also shown on its continent
-- (and any other map that contains it) by placing the zone's rectangle on
-- the map being viewed. Hover a dot for name, level and zone. A member
-- picked in the map search (Search.lua) gets a bigger, pulsing dot for a
-- few seconds. On OpenMap's stitched map the dots are placed through
-- OpenMapAPI, so they show anywhere in its view, above its art.

local _, ns = ...

local pins, canvas = {}, nil
local lit, litUntil = nil, 0

function ns.Highlight(name)
	lit, litUntil = name, GetTime() + 8
	ns.RefreshPins()
end

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

-- OpenMap's stitched map (its public OpenMapAPI): the canvas shows past
-- the edges of the map underneath, into its neighbours.
function ns.Stitched()
	local api = OpenMapAPI
	if not api or not api.IsStitched then return false end
	local ok, on = pcall(api.IsStitched)
	return ok and on or false
end

-- Where a shared position falls on the canvas of the map being viewed. On
-- OpenMap's stitched map that may be past its rectangle (still on screen);
-- otherwise only inside it.
local function Spot(p, viewed)
	if ns.Stitched() and OpenMapAPI.WorldFromMap and OpenMapAPI.MapFromWorld then
		local ok, u, v = pcall(OpenMapAPI.WorldFromMap, p.map, p.x, p.y)
		if ok and u then
			local ok2, px, py = pcall(OpenMapAPI.MapFromWorld, viewed, u, v)
			if ok2 and px and px > -3 and px < 4 and py > -3 and py < 4 then return px, py end
		end
	end
	return Place(p.map, p.x, p.y, viewed)
end

-- The canvas level a dot needs: over OpenMap's art when it has some.
local function PinLevel(c)
	local level = c:GetFrameLevel() + 500
	local art = OpenMapAPI and OpenMapAPI.ArtTopLevel and OpenMapAPI.ArtTopLevel()
	if type(art) == "number" and art + 5 > level then level = art + 5 end
	return level
end

local function Pin(i)
	local pin = pins[i]
	if pin then return pin end
	pin = CreateFrame("Frame", nil, Canvas())
	pin:SetSize(16, 16)
	pin:SetFrameLevel(PinLevel(Canvas()))
	pin.icon = pin:CreateTexture(nil, "OVERLAY")
	pin.icon:SetAllPoints()
	pin.pulse = pin:CreateAnimationGroup()
	pin.pulse:SetLooping("BOUNCE")
	local fade = pin.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.3)
	fade:SetDuration(0.4)
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
			local px, py = Spot(p, viewed)
			if px then
				n = n + 1
				local pin = Pin(n)
				local m = ns.members[name] or { name = name }
				pin.member = m
				-- Same size on screen however far the map is zoomed.
				local size = (name == lit and GetTime() < litUntil) and 30 or 16
				pin:SetSize(size / scale, size / scale)
				-- (restricted on the map in combat, OpenMap found: waits until it ends)
				local level = PinLevel(c) + (size > 16 and 1 or 0)
				if pin:GetFrameLevel() ~= level and not InCombatLockdown() then pin:SetFrameLevel(level) end
				if size > 16 then
					if not pin.pulse:IsPlaying() then pin.pulse:Play() end
				elseif pin.pulse:IsPlaying() then
					pin.pulse:Stop()
				end
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
