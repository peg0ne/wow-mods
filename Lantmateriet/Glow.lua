-- Lantmäteriet: the glow on the node in front of you.
--
-- The game's soft targeting picks the object the Interact key would use
-- (the nearest in front of you, up to SoftTargetInteractRange yards). With
-- the glow on, Lantmäteriet turns that on for mouse and keyboard and asks
-- for a nameplate on the object; when the object is a herb or ore node it
-- puts a turning ring on that nameplate, in the node's color (green herbs,
-- orange ore) when your skill is high enough and red when it isn't, and a
-- line under the middle of the screen with its name and what it needs.
--
-- The settings it changes are saved first (db.cvarBackup) and put back
-- when the glow is turned off. The game may cap the range; /lm räckvidd
-- says what it took.

local _, ns = ...

local CVARS = {
	SoftTargetInteract = "3",           -- mouse and keyboard too, not just a gamepad
	SoftTargetIconGameObject = "1",
	SoftTargetIconInteract = "1",
	SoftTargetNameplateInteract = "1",
}
local MIN_RANGE, MAX_RANGE = 5, 40

local current       -- { guid, name, kind, need } for the soft-interact node
local ring, line

local function GetSetting(name)
	local get = C_CVar and C_CVar.GetCVar or GetCVar
	local ok, v = pcall(get, name)
	if ok then return v end
end

local function SetSetting(name, value)
	local set = C_CVar and C_CVar.SetCVar or SetCVar
	pcall(set, name, value)
end

local function Wanted()
	local want = {}
	for k, v in pairs(CVARS) do want[k] = v end
	want.SoftTargetInteractRange = tostring(ns.db.range)
	-- The nameplate has to reach as far as the soft target does.
	local plateMax = tonumber(GetSetting("nameplateGameObjectMaxDistance"))
	if plateMax and plateMax < ns.db.range then want.nameplateGameObjectMaxDistance = tostring(ns.db.range) end
	return want
end

local function Apply()
	local db = ns.db
	db.cvarBackup = db.cvarBackup or {}
	for name, value in pairs(Wanted()) do
		local now = GetSetting(name)
		if now ~= nil then
			if db.cvarBackup[name] == nil then db.cvarBackup[name] = now end
			if now ~= value then SetSetting(name, value) end
		end
	end
end

local function Restore()
	local db = ns.db
	if not db.cvarBackup then return end
	for name, value in pairs(db.cvarBackup) do SetSetting(name, value) end
	db.cvarBackup = nil
end

---------------------------------------------------------------------------
-- The ring and the line.

local function Build()
	if ring then return end
	ring = CreateFrame("Frame", nil, UIParent)
	ring:SetSize(90, 90)
	ring:Hide()
	ring.glow = ring:CreateTexture(nil, "BACKGROUND")
	ring.glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
	ring.glow:SetBlendMode("ADD")
	ring.glow:SetPoint("CENTER")
	ring.glow:SetSize(110, 110)
	ring.star = ring:CreateTexture(nil, "ARTWORK")
	ring.star:SetTexture("Interface\\Cooldown\\star4")
	ring.star:SetBlendMode("ADD")
	ring.star:SetAllPoints()
	local spin = ring:CreateAnimationGroup()
	spin:SetLooping("REPEAT")
	local turn = spin:CreateAnimation("Rotation")
	turn:SetDegrees(-360)
	turn:SetDuration(6)
	turn:SetTarget(ring.star)
	ring.spin = spin
	local pulse = ring:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.45)
	fade:SetDuration(0.8)
	fade:SetTarget(ring.glow)
	ring.pulse = pulse

	line = CreateFrame("Frame", nil, UIParent)
	line:SetSize(400, 20)
	line:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
	line:SetFrameStrata("LOW")
	line:Hide()
	line.icon = line:CreateTexture(nil, "ARTWORK")
	line.icon:SetSize(18, 18)
	line.text = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	line.text:SetPoint("CENTER", 10, 0)
	line.icon:SetPoint("RIGHT", line.text, "LEFT", -4, 0)
	line.need = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	line.need:SetPoint("TOP", line.text, "BOTTOM", 0, -2)
end

local function Plate(unit)
	if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if not ok or not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
	return plate
end

-- The nameplate showing the current node, by its token or by its GUID.
local function FindPlate()
	if not current then return end
	local plate = Plate("softinteract")
	if plate then return plate end
	if not C_NamePlate.GetNamePlates then return end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if not ok or type(plates) ~= "table" then return end
	for _, p in ipairs(plates) do
		local unit = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
		if type(unit) == "string" and ns.Plain(UnitGUID(unit)) == current.guid and not (p.IsForbidden and p:IsForbidden()) then
			return p
		end
	end
end

local function Hide()
	if ring then
		ring:Hide()
		ring.spin:Stop()
		ring.pulse:Stop()
	end
	if line then line:Hide() end
end

local function Show()
	Build()
	if not current or not ns.db.glow then Hide() return end
	local status = ns.Status(current.kind, current.need)
	local r, g, b
	if ns.CanGather(status) then
		r, g, b = unpack(ns.KIND_COLOR[current.kind])
	else
		r, g, b = unpack(ns.STATUS_COLOR[status])
	end
	local plate = FindPlate()
	if plate then
		ring:SetParent(plate)
		ring:ClearAllPoints()
		ring:SetPoint("CENTER", plate, "CENTER", 0, -10)
		ring:SetFrameLevel(plate:GetFrameLevel())
		ring.star:SetVertexColor(r, g, b)
		ring.glow:SetVertexColor(r, g, b)
		ring:SetAlpha(ns.CanGather(status) and 1 or 0.6)
		ring:Show()
		ring.spin:Play()
		if ns.CanGather(status) then ring.pulse:Play() else ring.pulse:Stop() end
	else
		ring:Hide()
	end
	line.icon:SetTexture(ns.ICON[current.kind])
	line.text:SetText(current.name)
	line.text:SetTextColor(r, g, b)
	local c = ns.STATUS_COLOR[status]
	line.need:SetText(ns.NeedText(current.kind, current.need))
	line.need:SetTextColor(c[1], c[2], c[3])
	line:Show()
end

local function OnSoftChanged()
	current = nil
	local guid = ns.Plain(UnitGUID("softinteract"))
	local name = ns.Plain(UnitName("softinteract"))
	if guid and name then
		local kind, need = ns.NodeInfo(name)
		if kind and ns.ShowKind(kind) then
			current = { guid = guid, name = name, kind = kind, need = need }
		end
	end
	Show()
end

local events = CreateFrame("Frame")

function ns.StartGlow()
	for _, event in ipairs({ "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
		"SKILL_LINES_CHANGED", "CHAT_MSG_SKILL" }) do
		pcall(events.RegisterEvent, events, event)
	end
	if ns.db.glow then Apply() end
end

events:SetScript("OnEvent", function(_, event)
	if not ns.db or not ns.db.glow then return end
	if event == "PLAYER_SOFT_INTERACT_CHANGED" then
		OnSoftChanged()
	elseif current then
		-- A nameplate came or went, or the skill changed: draw it again
		-- after the game has set the plate up.
		C_Timer.After(0, Show)
	end
end)

function ns.SetGlow(on)
	ns.db.glow = on and true or false
	if on then
		Apply()
		ns.Print("noden framför dig lyser upp (inom " .. (GetSetting("SoftTargetInteractRange") or ns.db.range) .. " yards).")
	else
		Restore()
		current = nil
		Hide()
		ns.Print("noderna lyser inte längre upp; spelets egna inställningar är tillbaka.")
	end
end

function ns.SetRange(yards)
	if not yards then
		ns.Print("räckvidden är " .. (GetSetting("SoftTargetInteractRange") or "?") .. " yards. /lm räckvidd 20 ändrar den (" .. MIN_RANGE .. "-" .. MAX_RANGE .. ").")
		return
	end
	ns.db.range = math.max(MIN_RANGE, math.min(MAX_RANGE, math.floor(yards)))
	if ns.db.glow then Apply() end
	local took = tonumber(GetSetting("SoftTargetInteractRange"))
	if took and math.abs(took - ns.db.range) > 0.5 then
		ns.Print(string.format("spelet tog bara %d yards av %d.", took, ns.db.range))
	else
		ns.Print("räckvidden är nu " .. ns.db.range .. " yards" .. (ns.db.glow and "." or " (när glöden är på)."))
	end
end

-- /lm test: what the game tells us, to report when something doesn't work.
function ns.Test()
	local names = { "SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetNameplateInteract",
		"SoftTargetIconGameObject", "nameplateGameObjectMaxDistance" }
	local parts = {}
	for _, n in ipairs(names) do table.insert(parts, n .. "=" .. tostring(GetSetting(n))) end
	ns.Print(table.concat(parts, ", "))
	local name, guid = ns.Plain(UnitName("softinteract")), ns.Plain(UnitGUID("softinteract"))
	ns.Print("framför dig: " .. tostring(name) .. " (" .. tostring(guid) .. "), skylt: " .. (FindPlate() and "ja" or "nej")
		.. ", örtkunskap " .. tostring(ns.Skill(ns.HERB)) .. ", gruvbrytning " .. tostring(ns.Skill(ns.ORE)))
end
