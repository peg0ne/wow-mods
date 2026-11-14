-- Eniro: a search box on the world map. Type part of a zone, city or
-- dungeon name, or a guildmate's name, and pick a result (or press Enter for
-- the top one; arrow keys move between them) to open that map. Guildmates
-- come first: one who shares their position opens on their map with their
-- dot pulsing, one who doesn't opens on the zone the guild roster says they
-- are in. The zone list is read once from C_Map, everything below the world
-- map you have open.
-- With OpenMap's stitched map (OpenMapAPI) picking a result glides its view
-- there instead (dungeons, which aren't on it, still open their own map).

local _, ns = ...

local MAX_RESULTS, ROW_H, WIDTH = 8, 18, 240
-- Enum.UIMapType: continent 2, zone 3, dungeon 4, micro 5. A micro map
-- (a building, a cave) is only listed when no bigger map has its name.
local KEEP = { [2] = 1, [3] = 1, [4] = 1, [5] = 2 }

local box, list, rows = nil, nil, {}
local results, chosen = {}, 1
local zones -- { { id, name, lower, parent, rank } }, built on first search

---------------------------------------------------------------------------
-- Finding things.

-- The top map above the one you are looking at (Azeroth on this client).
local function Root()
	local id = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	if not id and C_Map.GetBestMapForUnit then id = C_Map.GetBestMapForUnit("player") end
	if not id and C_Map.GetFallbackWorldMapID then id = C_Map.GetFallbackWorldMapID() end
	for _ = 1, 10 do
		local info = id and C_Map.GetMapInfo(id)
		if not info or not info.parentMapID or info.parentMapID == 0 then break end
		id = info.parentMapID
	end
	return id
end

local function BuildZones()
	local root = Root()
	if not root or not C_Map.GetMapChildrenInfo then return end
	local ok, children = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
	if not ok or type(children) ~= "table" then return end
	local byName = {}
	for _, info in ipairs(children) do
		local rank = KEEP[info.mapType]
		if rank and info.name and info.name ~= "" then
			local old = byName[info.name]
			if not old or rank < old.rank then
				local parent = info.parentMapID and C_Map.GetMapInfo(info.parentMapID)
				byName[info.name] = {
					id = info.mapID, name = info.name, lower = info.name:lower(),
					parent = parent and parent.name, rank = rank,
				}
			end
		end
	end
	local found = {}
	for _, z in pairs(byName) do table.insert(found, z) end
	-- Empty means the maps weren't ready; try again on the next search.
	if #found > 0 then zones = found end
end

local function Zones()
	if not zones then BuildZones() end
	return zones or {}
end

-- 0 for a match at the start, 1 at the start of a later word, 2 anywhere.
local function Score(lower, q)
	local at = lower:find(q, 1, true)
	if not at then return end
	if at == 1 then return 0 end
	if lower:sub(at - 1, at - 1):match("[%s%-'%(]") then return 1 end
	return 2
end

local function Search(text)
	local q = strtrim(text or ""):lower()
	local found = {}
	if q == "" then return found end
	for name, m in pairs(ns.members) do
		local s = not ns.IsMe(name) and Score(name:lower(), q)
		if s then table.insert(found, { member = m, name = name, score = s }) end
	end
	for _, z in ipairs(Zones()) do
		local s = Score(z.lower, q)
		if s then table.insert(found, { zone = z, name = z.name, score = s }) end
	end
	table.sort(found, function(a, b)
		if (a.member ~= nil) ~= (b.member ~= nil) then return a.member ~= nil end
		if a.score ~= b.score then return a.score < b.score end
		if #a.name ~= #b.name then return #a.name < #b.name end
		return a.name < b.name
	end)
	for i = #found, MAX_RESULTS + 1, -1 do found[i] = nil end
	return found
end

local function ZoneNamed(name)
	if not name then return end
	for _, z in ipairs(Zones()) do
		if z.name == name then return z end
	end
end

---------------------------------------------------------------------------
-- The box and its list.

local function Close()
	box:SetText("")
	box:ClearFocus()
	list:Hide()
end

-- On OpenMap's stitched map: glide its view to a shared position, at least
-- as close as OpenMap's own search goes to a point. False if it can't.
local function Glide(p)
	if not ns.Stitched() or not OpenMapAPI.WorldFromMap or not OpenMapAPI.ShowWorld then return false end
	local ok, u, v = pcall(OpenMapAPI.WorldFromMap, p.map, p.x, p.y)
	if not ok or not u then return false end
	local zoom = OpenMapAPI.GetView and select(3, OpenMapAPI.GetView())
	local done
	ok, done = pcall(OpenMapAPI.ShowWorld, u, v, math.max(type(zoom) == "number" and zoom or 1, 14))
	return ok and done
end

-- On OpenMap's stitched map: glide its view so a whole map fits (zoom 1 is
-- the whole world). False if it can't (a dungeon isn't on the stitched map).
local function GlideToMap(id)
	if not ns.Stitched() or not OpenMapAPI.WorldFromMap or not OpenMapAPI.ShowWorld then return false end
	local ok, u0, v0 = pcall(OpenMapAPI.WorldFromMap, id, 0, 0)
	local ok2, u1, v1 = pcall(OpenMapAPI.WorldFromMap, id, 1, 1)
	if not ok or not ok2 or not u0 or not u1 then return false end
	local span = math.max(math.abs(u1 - u0), math.abs(v1 - v0))
	if span <= 0 then return false end
	local done
	ok, done = pcall(OpenMapAPI.ShowWorld, (u0 + u1) / 2, (v0 + v1) / 2, 0.9 / span)
	return ok and done
end

local function Choose(r)
	if not r then return end
	if r.zone then
		if not GlideToMap(r.zone.id) then WorldMapFrame:SetMapID(r.zone.id) end
	else
		local p = ns.positions[r.name]
		local z = ZoneNamed(r.member.zone)
		if p then
			if not Glide(p) then WorldMapFrame:SetMapID(p.map) end
			if ns.Highlight then ns.Highlight(r.name) end
		elseif z then
			WorldMapFrame:SetMapID(z.id)
			ns.Print(r.name .. " delar inte sin position; kartan visar zonen " .. z.name .. ".")
		else
			ns.Print(r.name .. " delar inte sin position och är i " .. (r.member.zone or "okänd zon") .. ".")
		end
	end
	Close()
end

local function Note(r)
	if r.zone then return r.zone.parent or "" end
	local m = r.member
	local where = m.zone or ""
	if ns.positions[r.name] then
		local d = ns.Distance(ns.positions[r.name])
		where = d and ns.DistanceText(d) or where
	end
	return string.format("nivå %s, %s", m.level or "?", where)
end

local function Row(i)
	if rows[i] then return rows[i] end
	local row = CreateFrame("Button", nil, list)
	row:SetSize(WIDTH - 8, ROW_H)
	row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_H)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetAllPoints()
	row.selected:SetColorTexture(1, 1, 1, 0.12)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 4, 0)
	row.text:SetWidth(WIDTH * 0.5)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.note = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.note:SetPoint("RIGHT", -4, 0)
	row.note:SetWidth(WIDTH * 0.5 - 16)
	row.note:SetJustifyH("RIGHT")
	row.note:SetWordWrap(false)
	row:SetScript("OnClick", function(self) Choose(self.result) end)
	row:SetScript("OnEnter", function(self)
		chosen = self.index
		for _, other in ipairs(rows) do other.selected:SetShown(other == self) end
	end)
	rows[i] = row
	return row
end

local function Render()
	local text = strtrim(box:GetText() or "")
	for i, r in ipairs(results) do
		local row = Row(i)
		row.result, row.index = r, i
		row.text:SetText(r.member and Statskontoret.ClassText(r.member.classFile, r.name) or r.name)
		row.note:SetText(Note(r))
		row.selected:SetShown(i == chosen)
		row:Show()
	end
	for i = #results + 1, #rows do rows[i]:Hide() end
	list.empty:SetShown(#results == 0)
	list:SetHeight(math.max(#results, 1) * ROW_H + 8)
	list:SetShown(text ~= "" and box:HasFocus())
end

local function Update()
	results, chosen = Search(box:GetText()), 1
	Render()
end

-- Right of whatever the map keeps in its top-left corner (the map pin
-- button on this client): the map's overlay buttons, and any other button
-- on the map frame that sits there.
local function Place()
	local scroll = WorldMapFrame.ScrollContainer or WorldMapFrame
	local left, top = scroll:GetLeft(), scroll:GetTop()
	local s = scroll:GetEffectiveScale()
	local x = 14
	if left and top then
		local function Check(f)
			if f == box or type(f) ~= "table" or not f.IsShown or not f:IsShown() or not f.GetRight then return end
			local fl, fr, ft = f:GetLeft(), f:GetRight(), f:GetTop()
			if not fl or not fr or not ft then return end
			local k = f:GetEffectiveScale() / s
			fl, fr, ft = fl * k, fr * k, ft * k
			-- (in the corner: starts near the left edge, its top near the top edge, not a wide bar)
			if fl - left < 60 and math.abs(ft - top) < 40 and fr - fl < 80 then
				x = math.max(x, fr - left + 12)
			end
		end
		for _, f in ipairs(WorldMapFrame.overlayFrames or {}) do Check(f) end
		for _, f in ipairs({ WorldMapFrame:GetChildren() }) do Check(f) end
		for _, f in ipairs({ scroll:GetChildren() }) do Check(f) end
	end
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", scroll, "TOPLEFT", x, -8)
end

local function Build()
	local scroll = WorldMapFrame.ScrollContainer or WorldMapFrame
	box = CreateFrame("EditBox", nil, WorldMapFrame, "InputBoxTemplate")
	box:SetSize(WIDTH - 10, 20)
	box:SetPoint("TOPLEFT", scroll, "TOPLEFT", 14, -8)
	-- (again each time the map opens: buttons there come and go, and the
	-- map's layout is only final a frame after it shows)
	WorldMapFrame:HookScript("OnShow", function() C_Timer.After(0, Place) end)
	if WorldMapFrame:IsShown() then C_Timer.After(0, Place) end
	box:SetFrameStrata(WorldMapFrame:GetFrameStrata())
	box:SetFrameLevel(math.min(scroll:GetFrameLevel() + 1000, 9000))
	box:SetAutoFocus(false)
	box:SetMaxLetters(40)

	box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	box.hint:SetPoint("LEFT", 2, 0)
	box.hint:SetText("Sök zon eller medlem")

	list = CreateFrame("Frame", nil, box, BackdropTemplateMixin and "BackdropTemplate")
	list:SetWidth(WIDTH)
	list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -2)
	if list.SetBackdrop then
		list:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		list:SetBackdropColor(0, 0, 0, 0.9)
	end
	list.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	list.empty:SetPoint("TOPLEFT", 8, -6)
	list.empty:SetText("inga träffar")
	list:Hide()

	box:SetScript("OnTextChanged", function(self)
		box.hint:SetShown(self:GetText() == "" and not self:HasFocus())
		Update()
	end)
	box:SetScript("OnEditFocusGained", function()
		box.hint:Hide()
		Update()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		box.hint:SetShown(self:GetText() == "")
		-- Not while the pointer is on the list: a click there is on its way.
		C_Timer.After(0, function()
			if not self:HasFocus() and not list:IsMouseOver() then list:Hide() end
		end)
	end)
	box:SetScript("OnEnterPressed", function() Choose(results[chosen]) end)
	box:SetScript("OnEscapePressed", Close)
	box:SetScript("OnArrowPressed", function(_, key)
		if #results == 0 then return end
		if key == "DOWN" then chosen = chosen % #results + 1
		elseif key == "UP" then chosen = (chosen - 2) % #results + 1 end
		Render()
	end)
	list:SetScript("OnLeave", function()
		if not box:HasFocus() and not list:IsMouseOver() then list:Hide() end
	end)
	WorldMapFrame:HookScript("OnHide", function()
		if box:GetText() ~= "" or box:HasFocus() then Close() end
	end)
end

-- /eniro sök: open the map with the cursor in the box.
function ns.FocusSearch()
	if not box then
		ns.Print("sökrutan finns inte: kartan har inte laddats. Starta om spelet om Eniro just uppdaterats.")
		return
	end
	if not WorldMapFrame:IsShown() then ShowUIPanel(WorldMapFrame) end
	C_Timer.After(0, function()
		if not box:IsVisible() then
			ns.Print("sökrutan är dold på den här kartan (något annat tillägg kan ligga över den).")
			return
		end
		box:SetFocus()
	end)
end

-- Some clients load the map after this addon; build the box once it exists.
if WorldMapFrame then
	Build()
else
	local waiter = CreateFrame("Frame")
	waiter:RegisterEvent("ADDON_LOADED")
	waiter:SetScript("OnEvent", function(self)
		if WorldMapFrame then
			self:UnregisterAllEvents()
			Build()
		end
	end)
end
