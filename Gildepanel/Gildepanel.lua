-- Gildepanel: the Addons window for THÖNDERSTÖRM, and an early warning
-- before your tax standing drops.
--
-- /gpanel opens the Addons window: buttons for the other guild addons'
-- windows, and their automatic settings as checkboxes. The settings are
-- written straight into each addon's saved table, which is the same table
-- the addon reads, so a change takes effect at once. Settings with side
-- effects (Eniro's position sharing) go through the addon's own slash
-- command instead.
--
-- Until 1.3 Gildepanel also had a panel and a minimap button showing your
-- Skatteverket standing, the favourites and your Swedbank loans. Skatteverket
-- 0.22 has all of that itself (/skatt, with a Swedbank tab, and its own
-- minimap button), so they were removed in 2.0. Skatteverket reminds you
-- once the standing has dropped; the warning here comes 6 hours before. It
-- only reads SkatteverketCharDB and never writes to it.

local ADDON = ...
local GUILD = "THÖNDERSTÖRM"
local GOOD, NEGATIVE = 48 * 3600, 7 * 86400
local PAD = 14
local floor, format = math.floor, string.format

local db
local hub

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Gildepanel:|r " .. text)
end

local function Money(copper)
	copper = floor(math.max(copper or 0, 0))
	local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
	local G, S, C = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"
	if g > 0 then return format("%d%s %d%s %d%s", g, G, s, S, c, C) end
	if s > 0 then return format("%d%s %d%s", s, S, c, C) end
	return format("%d%s", c, C)
end

local function Duration(sec)
	sec = math.max(0, floor(sec))
	if sec >= 86400 then return format("%d d %d h", floor(sec / 86400), floor(sec / 3600) % 24) end
	if sec >= 3600 then return format("%d h %d min", floor(sec / 3600), floor(sec / 60) % 60) end
	return format("%d min", floor(sec / 60))
end

local function InGuild()
	return GetGuildInfo("player") == GUILD
end

local function SetVisible(region, on)
	if on then region:Show() else region:Hide() end
end

local function SetColor(tex, r, g, b, a)
	if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a or 1) else tex:SetTexture(r, g, b, a or 1) end
end

local function RunSlash(key, msg, title)
	local fn = SlashCmdList and SlashCmdList[key]
	if fn then fn(msg or "") return true end
	Print((title or key) .. " är inte på.")
end

local function Text(parent, template, ...)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetPoint(...)
	fs:SetJustifyH("LEFT")
	return fs
end

local function Section(parent, label, y)
	Text(parent, "GameFontNormal", "TOPLEFT", PAD, y):SetText(label)
	local line = parent:CreateTexture(nil, "ARTWORK")
	SetColor(line, 1, 0.82, 0, 0.25)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", PAD, y - 16)
	line:SetPoint("TOPRIGHT", -PAD, y - 16)
end

local function Button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

------------------------------------------------------------------------
-- The Addons window.

local WINDOWS = {
	{ "Skatteverket", "Skatteverket", "SKATTEVERKET" },
	{ "Skatteverket", "Yrkesregister", "SKATTEVERKET", "yrken" },
	{ "Skatteverket", "Anmälan", "SKATTEVERKET", "anmälan" },
	{ "Swedbank", "Swedbank", "SWEDBANK" },
	{ "Arbetsformedlingen", "Uppdrag", "ARBETSFORMEDLINGEN" },
	{ "Arbetsformedlingen", "Platsbanken", "PLATSBANKEN" },
	{ "Skolverket", "Cooldowns", "SKOLVERKET" },
	{ "Eniro", "Eniro", "ENIRO" },
	{ "Polisen", "Polisen", "POLISEN" },
	{ "SCB", "SCB", "SCB" },
	{ "Dodsannonser", "Dödsannonser", "DODSANNONSER" },
}

-- invert: the addon stores "quiet", the box shows the opposite.
-- default: the value when the addon has not saved one yet.
local SETTINGS = {
	{ addon = "Atervinningscentralen", title = "Återvinningscentralen", db = "AtervinningscentralenDB", items = {
		{ key = "sell", label = "Sälj grått hos handlare", default = true },
		{ key = "repair", label = "Laga utrustningen", default = true },
	} },
	{ addon = "Handlaggaren", title = "Handläggaren", db = "HandlaggarenDB", items = {
		{ key = "on", label = "Ta och lämna in uppdrag", default = true },
		{ key = "pickBest", label = "Välj dyraste belöningen själv" },
		{ key = "share", label = "Dela nya uppdrag med gruppen" },
		{ key = "gossip", label = "Välj NPC:ns enda pratval" },
		{ key = "trivial", label = "Ta gråa uppdrag" },
	} },
	{ addon = "Kolapp", title = "Kölapp", db = "KolappDB", items = {
		{ key = "chat", label = "Questkedjor i chatten", default = true },
	} },
	{ addon = "Dodsannonser", title = "Dödsannonser", db = "DodsannonserDB", items = {
		{ key = "quiet", label = "Visa nya i chatten", invert = true },
		{ key = "guildChat", label = "Skriv min egen i gillechatten", default = true },
	} },
	{ addon = "Polisen", title = "Polisen", db = "PolisenDB", items = {
		{ key = "alarm", label = "Varning på skärmen och ljud", default = true },
		{ key = "quiet", label = "Visa andras observationer", invert = true },
	} },
	{ addon = "Arbetsformedlingen", title = "Arbetsförmedlingen", db = "ArbetsformedlingenCharDB", items = {
		{ key = "quiet", label = "Visa nya annonser i chatten", invert = true },
	} },
	{ addon = "Eniro", title = "Eniro", db = "EniroCharDB", items = {
		{ key = "share", label = "Dela min position med gillet", slash = { "ENIRO", "dela" } },
	} },
	{ addon = ADDON, title = "Gildepanel", db = "GildepanelDB", items = {
		{ key = "warn", label = "Förvarna innan skatteställningen sjunker", default = true },
	} },
}

local function Loaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
	return IsAddOnLoaded and IsAddOnLoaded(name)
end

local function SettingValue(group, item)
	local t = _G[group.db]
	if type(t) ~= "table" then return false end
	local v = t[item.key]
	if v == nil then v = item.default or false end
	v = v and true or false
	if item.invert then v = not v end
	return v
end

local function SetSetting(group, item, on)
	if item.slash then
		-- The command toggles; run it only if the value is not already right.
		if SettingValue(group, item) ~= on then RunSlash(item.slash[1], item.slash[2], group.title) end
		return
	end
	local t = _G[group.db]
	if type(t) ~= "table" then return end
	if item.invert then on = not on end
	t[item.key] = on
end

local function RefreshHub()
	for _, b in ipairs(hub.windows) do
		if Loaded(b.addon) and SlashCmdList[b.key] then b:Enable() else b:Disable() end
	end
	for _, row in ipairs(hub.groups) do
		local loaded = Loaded(row.group.addon) and type(_G[row.group.db]) == "table"
		row.header:SetText(row.group.title .. (loaded and "" or "  |cff808080(inte på)|r"))
		for _, cb in ipairs(row.boxes) do
			cb:SetChecked(loaded and SettingValue(row.group, cb.item))
			if loaded then
				cb:Enable()
				cb.label:SetTextColor(1, 1, 1)
			else
				cb:Disable()
				cb.label:SetTextColor(0.5, 0.5, 0.5)
			end
		end
	end
end

-- The look of Skatteverket's panel: the game's portrait window (like the
-- Character window) with the guild's lightning bolt from Skatteverket's
-- art, the title on the title bar, a recessed inset and tabs along the
-- bottom edge. Falls back to the old dialog look on a client without the
-- template, as Skatteverket does.
local function HasTemplate(name)
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then return C_XMLUtil.GetTemplateInfo(name) ~= nil end
	return true
end

local function Panel(name, titleText)
	local ok, f = false, nil
	if HasTemplate("ButtonFrameTemplate") then ok, f = pcall(CreateFrame, "Frame", name, UIParent, "ButtonFrameTemplate") end
	if ok and f then
		local bolt = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Skatteverket")
		local art = bolt and "Interface\\AddOns\\Skatteverket\\Media\\Bolt" or "Interface\\Icons\\Spell_Nature_Lightning"
		local portrait = f.portrait or f.Portrait or (f.PortraitContainer and f.PortraitContainer.portrait)
			or _G[name .. "Portrait"]
		if f.SetPortraitToAsset then
			f:SetPortraitToAsset(art)
		elseif portrait then
			portrait:SetTexture(art)
		end
		if portrait then portrait:Show() end
		local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
		if title then title:SetText(titleText) end
		return f, true
	end
	f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	local header = f:CreateTexture(nil, "ARTWORK")
	header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	header:SetSize(320, 64)
	header:SetPoint("TOP", 0, 12)
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", header, "TOP", 0, -14)
	title:SetText(titleText)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)
	return f, false
end

-- A tab under the window, as on the Character window; the first at the
-- left edge, the rest after it.
local function Tab(f, i, label, onClick)
	local name = f:GetName() .. "Tab" .. i
	local b
	for _, template in ipairs({ "CharacterFrameTabButtonTemplate", "PanelTabButtonTemplate" }) do
		if HasTemplate(template) then
			local ok, t = pcall(CreateFrame, "Button", name, f, template)
			if ok and t then
				b = t
				b.isTab = true
				break
			end
		end
	end
	if not b then
		b = CreateFrame("Button", name, f, "UIPanelButtonTemplate")
		b:SetSize(120, 22)
	end
	b:SetID(i)
	b:SetText(label)
	if b.isTab and PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 0) end
	b:SetScript("OnClick", function()
		onClick()
		if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
	end)
	if i == 1 then
		b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
	else
		b:SetPoint("LEFT", _G[f:GetName() .. "Tab" .. (i - 1)], "RIGHT", b.isTab and -15 or 4, 0)
	end
	return b
end

local function SelectTab(tab, on)
	if tab.isTab and PanelTemplates_SelectTab and PanelTemplates_DeselectTab then
		if on then PanelTemplates_SelectTab(tab) else PanelTemplates_DeselectTab(tab) end
	elseif on then
		tab:Disable()
	else
		tab:Enable()
	end
end

local function BuildHub()
	local HW = 320
	local classic
	hub, classic = Panel("GildepanelHub", GUILD)
	hub:SetWidth(HW)
	hub:SetFrameStrata("DIALOG")
	hub:SetClampedToScreen(true)
	hub:SetMovable(true)
	hub:EnableMouse(true)
	hub:RegisterForDrag("LeftButton")
	hub:SetScript("OnDragStart", function(self) self:StartMoving() end)
	hub:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local left, top = self:GetLeft(), self:GetTop()
		if left and top then
			db.hubPos = { left, top }
			self:ClearAllPoints()
			self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		end
	end)
	if db.hubPos then
		hub:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.hubPos[1], db.hubPos[2])
	else
		hub:SetPoint("CENTER")
	end
	table.insert(UISpecialFrames, "GildepanelHub")

	-- Beside the portrait, as Skatteverket's panel has its bank line; the
	-- rest starts below the portrait.
	Text(hub, "GameFontNormal", "TOPLEFT", classic and 66 or PAD, -34):SetText("Addons")
	local top = classic and -66 or -34

	-- Windows, two buttons a row.
	Section(hub, "Fönster", top)
	hub.windows = {}
	local bw = (HW - 2 * PAD - 8) / 2
	local y = top - 24
	for i, w in ipairs(WINDOWS) do
		local b = Button(hub, w[2], bw, function() RunSlash(w[3], w[4] or "", w[2]) end)
		b.addon, b.key = w[1], w[3]
		local col = (i - 1) % 2
		b:SetPoint("TOPLEFT", PAD + col * (bw + 8), y)
		if col == 1 or i == #WINDOWS then y = y - 26 end
		table.insert(hub.windows, b)
	end

	-- Automatic settings, grouped by addon.
	y = y - 10
	Section(hub, "Automatik", y)
	y = y - 24
	hub.groups = {}
	for _, group in ipairs(SETTINGS) do
		local row = { group = group, boxes = {} }
		row.header = Text(hub, "GameFontNormalSmall", "TOPLEFT", PAD, y)
		y = y - 16
		for _, item in ipairs(group.items) do
			local cb = CreateFrame("CheckButton", nil, hub, "UICheckButtonTemplate")
			cb:SetSize(22, 22)
			cb:SetPoint("TOPLEFT", PAD + 4, y + 3)
			cb.item = item
			cb.label = Text(hub, "GameFontHighlightSmall", "LEFT", cb, "RIGHT", 2, 1)
			cb.label:SetText(item.label)
			cb:SetScript("OnClick", function(self)
				SetSetting(group, item, self:GetChecked() and true or false)
				RefreshHub()
			end)
			table.insert(row.boxes, cb)
			y = y - 20
		end
		y = y - 6
		table.insert(hub.groups, row)
	end
	hub:SetHeight(-y + (classic and 28 or 8))

	-- Slash commands can change a setting while the window is open.
	hub:SetScript("OnShow", RefreshHub)
	hub:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed >= 1 then
			self.elapsed = 0
			RefreshHub()
		end
	end)
	hub:Hide()
end

local function ToggleHub()
	if not hub then BuildHub() end
	SetVisible(hub, not hub:IsShown())
end

------------------------------------------------------------------------
-- A heads-up in chat 6 hours before the standing drops a step (good up to
-- 48 hours unpaid, neutral up to a week, as Skatteverket counts it).

local warned = {}
local function CheckWarning()
	if db.warn == false then return end
	local c = SkatteverketCharDB
	if not c or not InGuild() or not c.debtSince or (c.owed or 0) < 1 then return end
	local age = time() - c.debtSince
	for _, step in ipairs({ { GOOD, "|cffffd100Neutral|r" }, { NEGATIVE, "|cffff4040Negativ|r" } }) do
		local left, key = step[1] - age, c.debtSince .. ":" .. step[1]
		if left > 0 and left <= 6 * 3600 and not warned[key] then
			warned[key] = true
			Print(format("din ställning blir %s om %s. Betala %s vid gildebanken för att behålla den.", step[2], Duration(left), Money(c.owed)))
		end
	end
end

------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg)
	if event == "ADDON_LOADED" and arg == ADDON then
		GildepanelDB = GildepanelDB or {}
		db = GildepanelDB
		-- Settings of the panel and minimap button removed in 2.0.
		for _, key in ipairs({ "pos", "scale", "shown", "compact", "locked", "minimapAngle", "hideMinimap" }) do
			db[key] = nil
		end
	elseif event == "PLAYER_LOGIN" and db then
		C_Timer.NewTicker(60, CheckWarning)
		C_Timer.After(25, CheckWarning)
	end
end)

SLASH_GILDEPANEL1 = "/gildepanel"
SLASH_GILDEPANEL2 = "/gpanel"
SlashCmdList.GILDEPANEL = function(msg)
	local cmd = (msg or ""):lower():match("^%s*(%S*)")
	if cmd == "" or cmd == "addons" or cmd == "mods" then
		ToggleHub()
	elseif cmd == "varning" or cmd == "warn" then
		db.warn = db.warn == false
		Print(db.warn and "varnar 6 timmar innan skatteställningen sjunker." or "inga förvarningar.")
	else
		Print("/gpanel öppnar addonfönstret. /gpanel varning slår av eller på förvarningen innan skatteställningen sjunker. Skatten själv finns i /skatt.")
	end
end
