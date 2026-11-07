-- Arbetsförmedlingen in the game's own tooltips: hovering a quest in the
-- quest log, or a quest link in chat, adds "N i gildet har det här" and
-- who, from the lists of online members. Works with the Classic-style
-- quest log (QuestLogTitle1..n); clients without it just get no lines.

local _, ns = ...

local function AddLines(tooltip, id)
	if not id or id <= 0 then return end
	local members = ns.MembersOn(id)
	if #members == 0 then return end
	tooltip:AddLine(" ")
	tooltip:AddLine(string.format("Arbetsförmedlingen: %d i gildet har det här", #members), 0.4, 0.8, 1)
	ns.AddMemberLines(tooltip, members)
	tooltip:Show()
end

local function QuestIdAt(index)
	if not index or index < 1 then return nil end
	if GetQuestLogTitle then return (select(8, GetQuestLogTitle(index))) end
	if C_QuestLog and C_QuestLog.GetInfo then
		local info = C_QuestLog.GetInfo(index)
		return info and not info.isHeader and info.questID or nil
	end
end

-- The game may already show a tooltip here (party members on the quest);
-- add to that one, otherwise open our own.
local function OnEnterTitle(button)
	-- Button IDs are row numbers; the game adds the scroll offset to get the log index.
	local offset = QuestLogListScrollFrame and FauxScrollFrame_GetOffset(QuestLogListScrollFrame) or 0
	local id = QuestIdAt(button:GetID() + offset)
	if not id or #ns.MembersOn(id) == 0 then return end
	if not GameTooltip:IsOwned(button) then
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		local info = ns.QuestInfo(id)
		GameTooltip:AddLine(info and info.title or ("#" .. id))
	end
	AddLines(GameTooltip, id)
end

local hooked = {}
local function HookTitles()
	for i = 1, (QUESTS_DISPLAYED or 30) do
		local button = _G["QuestLogTitle" .. i]
		if button and not hooked[button] then
			hooked[button] = true
			button:HookScript("OnEnter", OnEnterTitle)
			button:HookScript("OnLeave", function() GameTooltip:Hide() end)
		end
	end
end

if QuestLog_Update then hooksecurefunc("QuestLog_Update", HookTitles) end
HookTitles()

-- Quest links in chat.
local function OnHyperlink(tooltip, link)
	local id = type(link) == "string" and tonumber(link:match("quest:(%d+)"))
	if id then AddLines(tooltip, id) end
end
for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
	if tooltip and tooltip.SetHyperlink then hooksecurefunc(tooltip, "SetHyperlink", OnHyperlink) end
end
