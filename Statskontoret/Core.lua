-- Statskontoret: code the THÖNDERSTÖRM addons share, so a fix lands in one
-- place. Other addons list it under ## Dependencies, which makes the game
-- load it first, and reach it through the global Statskontoret.
--
-- Keep it backwards compatible: an addon from an older pack may run against
-- a newer Statskontoret. Add functions; don't change what existing ones
-- take or return. Bump API when adding, so an addon can check for it.

local S = {}
Statskontoret = S
S.API = 2

---------------------------------------------------------------------------
-- Windows.

-- Whether the client has an XML template (Forever has the retail ones).
function S.HasTemplate(name)
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then return C_XMLUtil.GetTemplateInfo(name) ~= nil end
	return true
end

-- The look of Skatteverket's panel: the game's portrait window (like the
-- Character window) with the guild's lightning bolt from Skatteverket's
-- art, the title on the title bar and a recessed inset. Falls back to the
-- old dialog look on a client without the template, as Skatteverket does.
-- Returns the frame and whether the portrait template was used.
--
-- The window is top-level: clicking it brings it in front of the other
-- guild windows, and it comes to the front when it opens. Without this,
-- windows that share a strata and frame level draw their parts interleaved
-- (one window's background over another's text).
function S.Panel(name, titleText)
	local ok, f = false, nil
	local portraitLook = false
	if S.HasTemplate("ButtonFrameTemplate") then ok, f = pcall(CreateFrame, "Frame", name, UIParent, "ButtonFrameTemplate") end
	if ok and f then
		portraitLook = true
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
	else
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
	end
	f:SetToplevel(true)
	f:HookScript("OnShow", function(self) self:Raise() end)
	return f, portraitLook
end

-- A Panel set up the way every guild window is: centered, in the DIALOG
-- strata, kept on screen, dragged by its body and closed by Escape.
function S.Window(name, titleText, width, height)
	local f, portraitLook = S.Panel(name, titleText)
	f:SetSize(width, height)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, name)
	return f, portraitLook
end

---------------------------------------------------------------------------
-- Window parts (API 2). Drawn with plain colored textures, so they look the
-- same on every client and need no template.

local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0

local function Color(tex, r, g, b, a)
	if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a or 1) else tex:SetTexture(r, g, b, a or 1) end
end

-- A faint gold line across parent at y, from left in from the left edge to
-- right in from the right edge.
function S.Rule(parent, left, right, y, alpha)
	local line = parent:CreateTexture(nil, "ARTWORK")
	Color(line, GOLD_R, GOLD_G, GOLD_B, alpha or 0.25)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", left, y)
	line:SetPoint("TOPRIGHT", -right, y)
	return line
end

-- Tabs drawn as words, the chosen one gold and underlined, for switching
-- what a window shows. They look nothing like UIPanelButtons, which do
-- things. specs is { { key, label }, ... }; width gives every tab the same
-- width, else each fits its word. Click calls onSelect(key). Returns the
-- bar (place it with SetPoint) with bar:Select(key) to mark one without
-- calling onSelect.
function S.Tabs(parent, specs, onSelect, width)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(24)
	bar.buttons = {}
	local function Paint(b)
		local on = b.key == bar.selected
		b.mark:SetShown(on)
		b.bg:SetShown(on)
		if on then
			b.text:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
		elseif b:IsMouseOver() then
			b.text:SetTextColor(1, 1, 1)
		else
			b.text:SetTextColor(0.65, 0.65, 0.65)
		end
	end
	function bar:Select(key)
		self.selected = key
		for _, b in ipairs(self.buttons) do Paint(b) end
	end
	local x = 0
	for _, spec in ipairs(specs) do
		local b = CreateFrame("Button", nil, bar)
		b.key = spec[1]
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		b.text:SetPoint("CENTER", 0, 1)
		b.text:SetText(spec[2])
		local w = width or (b.text:GetStringWidth() + 28)
		b:SetSize(w, 24)
		b:SetPoint("BOTTOMLEFT", x, 0)
		x = x + w + (width and 0 or 2)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		Color(b.bg, GOLD_R, GOLD_G, GOLD_B, 0.07)
		local hover = b:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		Color(hover, 1, 1, 1, 0.05)
		b.mark = b:CreateTexture(nil, "OVERLAY")
		Color(b.mark, GOLD_R, GOLD_G, GOLD_B, 0.9)
		b.mark:SetHeight(2)
		b.mark:SetPoint("BOTTOMLEFT", 2, 0)
		b.mark:SetPoint("BOTTOMRIGHT", -2, 0)
		b:SetScript("OnEnter", Paint)
		b:SetScript("OnLeave", Paint)
		b:SetScript("OnClick", function(self)
			if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
			bar:Select(self.key)
			onSelect(self.key)
		end)
		table.insert(bar.buttons, b)
	end
	bar:SetWidth(math.max(x, 1))
	return bar
end

-- A faint band behind every other row of a list, so a line is easy to
-- follow across the columns.
function S.Stripe(row, i)
	if i % 2 == 1 then return end
	local band = row:CreateTexture(nil, "BACKGROUND")
	band:SetAllPoints()
	Color(band, 1, 1, 1, 0.035)
end

-- A thin bar beside a list that shows which part of it is in view (the
-- list scrolls with the mouse wheel). Place and size it with SetPoint and
-- SetHeight; mark:Update(offset, shown, total) after each scroll. Hidden
-- when everything fits.
function S.ScrollMark(parent)
	local m = CreateFrame("Frame", nil, parent)
	m:SetWidth(4)
	local track = m:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	Color(track, 1, 1, 1, 0.08)
	local thumb = m:CreateTexture(nil, "ARTWORK")
	Color(thumb, GOLD_R, GOLD_G, GOLD_B, 0.6)
	thumb:SetWidth(4)
	function m:Update(offset, shown, total)
		if total <= shown then self:Hide() return end
		self:Show()
		local h = self:GetHeight()
		local size = math.max(12, h * shown / total)
		thumb:SetHeight(size)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", 0, -(h - size) * offset / (total - shown))
	end
	m:Hide()
	return m
end

-- A small arrow for a sorted column heading, as an inline texture: pointing
-- down for largest first.
function S.SortArrow(down)
	if down then return "|TInterface\\Buttons\\UI-SortArrow:10:10:2:0:16:16:0:9:0:16|t" end
	return "|TInterface\\Buttons\\UI-SortArrow:10:10:2:0:16:16:0:9:16:0|t"
end

---------------------------------------------------------------------------
-- Guild.

-- Asks the server for a fresh guild roster (GUILD_ROSTER_UPDATE follows).
function S.RequestRoster()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

-- Sends an addon message; channel defaults to GUILD. Returns what the game
-- returns (on Forever a result code), or nil when it can't send at all.
function S.SendAddon(prefix, msg, channel, target)
	channel = channel or "GUILD"
	if channel == "GUILD" and not IsInGuild() then return end
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		return C_ChatInfo.SendAddonMessage(prefix, msg, channel, target)
	elseif SendAddonMessage then
		return SendAddonMessage(prefix, msg, channel, target)
	end
end

-- In a battleground or arena: deaths and enemy players there are part of
-- the game, not something to report to the guild.
function S.InPvPInstance()
	if not IsInInstance then return false end
	local _, kind = IsInInstance()
	return kind == "pvp" or kind == "arena"
end

-- A throttled sender for one prefix. The server allows a short burst of
-- addon messages per prefix and then about one a second; the rest are
-- dropped without a word. Messages wait in a queue and go out at that pace,
-- in order. check, if given, is called just before sending: return false to
-- drop a message that is no longer needed (say, someone else answered).
-- Returns send(msg, channel, target, check); channel defaults to GUILD.
local BURST = 8
function S.Sender(prefix)
	local queue, tokens, lastRefill, pumping = {}, BURST, 0, false
	local function Pump()
		local now = GetTime()
		tokens = math.min(BURST, tokens + (now - lastRefill))
		lastRefill = now
		while tokens >= 1 and #queue > 0 do
			local m = table.remove(queue, 1)
			if not m.check or m.check() then
				S.SendAddon(prefix, m.msg, m.channel, m.target)
				tokens = tokens - 1
			end
		end
		if #queue > 0 then C_Timer.After(1, Pump) else pumping = false end
	end
	return function(msg, channel, target, check)
		channel = channel or "GUILD"
		if channel == "GUILD" and not IsInGuild() then return end
		table.insert(queue, { msg = msg, channel = channel, target = target, check = check })
		if not pumping then
			pumping = true
			Pump()
		end
	end
end

function S.Invite(name)
	if C_PartyInfo and C_PartyInfo.InviteUnit then
		C_PartyInfo.InviteUnit(name)
	elseif InviteUnit then
		InviteUnit(name)
	end
end

-- An addon's ## Version from its .toc, or fallback if the client can't say.
function S.AddonVersion(addon, fallback)
	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local v = meta and meta(addon, "Version")
	return v or fallback
end

---------------------------------------------------------------------------
-- Text.

-- text in the color of a class ("WARRIOR", ...); plain text if unknown.
function S.ClassText(classFile, text)
	local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if not color then return text end
	return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, text)
end
