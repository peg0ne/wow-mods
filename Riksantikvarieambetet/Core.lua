-- Riksantikvarieämbetet: every dungeon (and raid) is an excavation, and when
-- you leave it the board files its report in chat:
--   time inside, enemies killed (the kills that gave experience: the
--   combat log is closed to addons), bosses (ENCOUNTER_END / BOSS_KILL),
--   experience and gold gained, what your loot is worth at a vendor and
--   the best find, and who in the group died (yours with what killed you,
--   from Rättsmedicinalverket when it is on).
--
-- A run is kept in RiksantikvarieambetetDB.run, so a /reload inside loses
-- nothing. Dying and releasing puts you outside as a ghost: that isn't
-- leaving, and the report waits. Coming back into the same dungeon within
-- 15 minutes (a repair trip) carries on the same run, and its next report
-- covers all of it. Very short visits with nothing done get no report.
--
-- /raa shows the last report again, /raa lista the latest runs, /raa grupp
-- (off by default) also puts a one-line summary in party chat, /raa av
-- turns the reports off.

local ADDON = ...
local RESUME = 15 * 60   -- back in the same dungeon within this: the same run
local KEEP = 20          -- reports kept

local db

local function Plain(v)
	if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
	return v
end

local function Say(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffd9b38cRiksantikvarieämbetet:|r " .. text)
end

local function Num(n)
	local s = tostring(math.floor(n or 0))
	local k
	repeat s, k = s:gsub("^(%d+)(%d%d%d)", "%1 %2") until k == 0
	return s
end

local function Money(copper)
	copper = math.floor(copper or 0)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then return string.format("%dg %ds", g, s) end
	if s > 0 then return string.format("%ds %dc", s, c) end
	return string.format("%dc", c)
end

local function Minutes(seconds)
	local m = math.floor((seconds or 0) / 60 + 0.5)
	if m >= 60 then return string.format("%d h %d min", math.floor(m / 60), m % 60) end
	return string.format("%d min", math.max(m, 1))
end

local function Short(name)
	if not name then return nil end
	if Ambiguate then return Ambiguate(name, "none") end
	return (name:gsub("%-.*", ""))
end

local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)

---------------------------------------------------------------------------
-- The run.

local function InDungeon()
	local inside, kind = IsInInstance()
	if not inside or (kind ~= "party" and kind ~= "raid") then return nil end
	local name, _, _, diffName, _, _, _, mapID = GetInstanceInfo()
	return Plain(name), Plain(mapID), Plain(diffName)
end

local function Active()
	return db and db.on and db.run and not db.run.left
end

local function NewRun(name, mapID, diffName)
	return {
		name = name, mapID = mapID, diff = diffName ~= "" and diffName or nil, start = time(),
		kills = 0, bosses = {}, xp = 0, levels = 0, money = 0,
		lootValue = 0, lootCount = 0, quests = 0, deaths = {}, myKillers = {},
	}
end

local function DeathCount(run)
	local n = 0
	for _, c in pairs(run.deaths) do n = n + c end
	return n
end

-- One closing remark, from what stands out.
local function Remark(run, duration, deaths)
	if deaths == 0 and run.kills >= 30 then return "Inga skadade under utgrävningen. Föredömligt." end
	if deaths >= 6 then return "Utgrävningen krävde fler offer än den gav fynd." end
	if run.levels > 0 then return "Utgrävaren har vuxit med uppgiften." end
	if duration < 20 * 60 and #run.bosses >= 2 then return "Snabbare än byråkratin brukar tillåta." end
	if duration > 90 * 60 then return "Ärendet har haft en lång handläggningstid." end
	if deaths == 0 then return "Inga dödsfall att rapportera." end
	return nil
end

local function Lines(run)
	local duration = (run.left or time()) - run.start
	local deaths = DeathCount(run)
	local lines = {}
	table.insert(lines, string.format("utgrävningen av |cffffd100%s|r%s är %s.", run.name or "?",
		run.diff and (" (" .. run.diff .. ")") or "", run.resumed and "klar (med uppehåll)" or "klar"))
	local bosses = #run.bosses > 0 and string.format("%d (%s)", #run.bosses, table.concat(run.bosses, ", ")) or "inga"
	table.insert(lines, string.format("Tid: %s · fiender: %d · bossar: %s", Minutes(duration), run.kills, bosses))
	local parts = {}
	if run.xp > 0 then
		table.insert(parts, "erfarenhet: +" .. Num(run.xp) .. (run.levels > 0 and string.format(" (+%d %s)", run.levels, run.levels == 1 and "nivå" or "nivåer") or ""))
	end
	if run.money > 0 then table.insert(parts, "guld: +" .. Money(run.money)) end
	if run.lootCount > 0 then
		table.insert(parts, string.format("bytet: %d %s värda %s hos handlare", run.lootCount, run.lootCount == 1 and "sak" or "saker", Money(run.lootValue)))
	end
	if #parts > 0 then
		local first = parts[1]:sub(1, 1):upper() .. parts[1]:sub(2)
		parts[1] = first
		table.insert(lines, table.concat(parts, " · "))
	end
	if run.best then table.insert(lines, "Bästa fyndet: " .. run.best.link) end
	if deaths > 0 then
		local who = {}
		local mine = run.deaths["du"]
		if mine then
			local why = #run.myKillers > 0 and (" (" .. table.concat(run.myKillers, ", ") .. ")") or ""
			table.insert(who, string.format("du %d%s", mine, why))
		end
		local others = {}
		for name, c in pairs(run.deaths) do
			if name ~= "du" then table.insert(others, { name = name, c = c }) end
		end
		table.sort(others, function(a, b) if a.c ~= b.c then return a.c > b.c end return a.name < b.name end)
		for _, o in ipairs(others) do table.insert(who, string.format("%s %d", o.name, o.c)) end
		table.insert(lines, "Dödsfall: " .. table.concat(who, ", "))
	else
		table.insert(lines, "Dödsfall: inga")
	end
	local remark = Remark(run, duration, deaths)
	if remark then table.insert(lines, "|cffa0a0a0" .. remark .. "|r") end

	local short = string.format("{rt3} Riksantikvarieämbetet: %s på %s, %d fiender, %d %s, %d dödsfall.",
		run.name or "?", Minutes(duration), run.kills, #run.bosses, #run.bosses == 1 and "boss" or "bossar", deaths)
	if run.best then short = short .. " Bästa fyndet: " .. run.best.link end
	local list = string.format("%s: %s, %d fiender, %d bossar, %d dödsfall", run.name or "?", Minutes(duration), run.kills, #run.bosses, deaths)
	return lines, short, list
end

local function PrintLines(lines)
	for i, line in ipairs(lines) do
		if i == 1 then Say(line) else DEFAULT_CHAT_FRAME:AddMessage("   " .. line) end
	end
end

local function Report(run)
	run.reported = true
	if not db.on then return end
	local duration = (run.left or time()) - run.start
	if duration < 120 and run.kills == 0 and #run.bosses == 0 then return end
	local lines, short, list = Lines(run)
	PrintLines(lines)
	-- A run carried on after a report replaces its earlier entry.
	if db.history[1] and db.history[1].start == run.start then table.remove(db.history, 1) end
	table.insert(db.history, 1, { start = run.start, lines = lines, list = list })
	while #db.history > KEEP do table.remove(db.history) end
	if db.party and IsInGroup(LE_PARTY_CATEGORY_HOME) then
		local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
		if send then pcall(send, short, "PARTY") end
	end
end

local function Dead()
	return Plain(UnitIsDeadOrGhost("player")) and true or false
end

-- Where you are now, against the run: start, carry on, or report.
local function Check()
	if not db then return end
	local name, mapID = InDungeon()
	local run = db.run
	if name then
		local _, _, diffName = InDungeon()
		if run and run.mapID == mapID and (not run.left or time() - run.left < RESUME) then
			if run.left then
				run.left = nil
				if run.reported then run.reported, run.resumed = false, true end
			end
		else
			if run and not run.reported then Report(run) end
			db.run = NewRun(name, mapID, diffName)
		end
	elseif run then
		if not run.left then run.left = time() end
		-- A ghost on its way back in hasn't left; the report waits.
		if not run.reported and not Dead() then Report(run) end
	end
end

---------------------------------------------------------------------------
-- Counting.

-- "%s dies, you gain %d experience." and its variants start the same way.
local killPattern
local function KillPattern()
	if killPattern ~= nil then return killPattern end
	local head = COMBATLOG_XPGAIN_FIRSTPERSON and COMBATLOG_XPGAIN_FIRSTPERSON:match("^(.-)%%d")
	if not head then
		killPattern = false
		return false
	end
	head = head:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", ".+")
	killPattern = "^" .. head
	return killPattern
end

-- A game string like "You receive loot: %sx%d." as a pattern.
local function Pattern(template)
	if type(template) ~= "string" then return nil end
	local p = template:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
	return "^" .. p .. "$"
end
local lootMulti, lootOne

local function AddLoot(link, count, tries)
	local run = db.run
	if not run or run.left then return end
	local _, _, quality, _, _, _, _, _, _, _, price = GetItemInfo(link)
	if not price then
		if (tries or 0) < 3 then
			if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, link) end
			C_Timer.After(1, function() AddLoot(link, count, (tries or 0) + 1) end)
		else
			run.lootCount = run.lootCount + count
		end
		return
	end
	run.lootCount = run.lootCount + count
	run.lootValue = run.lootValue + price * count
	local b = run.best
	if (quality or 0) >= 2 and (not b or (quality or 0) > b.quality or ((quality or 0) == b.quality and price > b.price)) then
		run.best = { link = link, quality = quality or 0, price = price }
	end
end

local function OnLoot(msg)
	msg = Plain(msg)
	if not msg or not Active() then return end
	lootMulti = lootMulti or Pattern(LOOT_ITEM_SELF_MULTIPLE)
	lootOne = lootOne or Pattern(LOOT_ITEM_SELF)
	local link, count
	if lootMulti then link, count = msg:match(lootMulti) end
	if not link and lootOne then link = msg:match(lootOne) end
	if not link or not link:find("|Hitem:") then return end
	AddLoot(link, tonumber(count) or 1)
end

local function OnXPMessage(msg)
	msg = Plain(msg)
	local pattern = KillPattern()
	if msg and pattern and Active() and msg:find(pattern) then db.run.kills = db.run.kills + 1 end
end

local function AddBoss(name)
	name = Plain(name)
	if not name or not Active() then return end
	for _, b in ipairs(db.run.bosses) do
		if b == name then return end
	end
	table.insert(db.run.bosses, name)
end

local xpLast, xpMaxLast, levelLast
local function OnXP()
	local xp, max, level = Plain(UnitXP("player")), Plain(UnitXPMax("player")), Plain(UnitLevel("player"))
	if not (xp and max and level) then return end
	if Active() and xpLast then
		local gained
		if level > levelLast then
			gained = (xpMaxLast - xpLast) + xp
			db.run.levels = db.run.levels + (level - levelLast)
		else
			gained = xp - xpLast
		end
		if gained > 0 then db.run.xp = db.run.xp + gained end
	end
	xpLast, xpMaxLast, levelLast = xp, max, level
end

local lastMoney
local function OnMoney()
	local now = GetMoney()
	if lastMoney and Active() and now > lastMoney then db.run.money = db.run.money + (now - lastMoney) end
	lastMoney = now
end

-- Deaths in the group: a unit going from alive to dead (not feigning).
local deadNow = {}
local function GroupUnit(unit)
	return unit == "player" or unit:match("^party%d$") or unit:match("^raid%d+$")
end

local function OnHealth(unit)
	if type(unit) ~= "string" or not GroupUnit(unit) then return end
	local me = UnitIsUnit(unit, "player")
	local key = me and "du" or Short(Plain(UnitName(unit)))
	if not key then return end
	local dead = Plain(UnitIsDeadOrGhost(unit)) and not (UnitIsFeignDeath and Plain(UnitIsFeignDeath(unit)))
	dead = dead and true or false
	if dead and deadNow[key] == false and Active() then
		db.run.deaths[key] = (db.run.deaths[key] or 0) + 1
	end
	deadNow[key] = dead
end

-- Everyone's state now, so a death without any health change before it
-- (one hit from full) still counts.
local function Seed()
	OnHealth("player")
	if IsInRaid and IsInRaid() then
		for i = 1, 40 do if UnitExists("raid" .. i) then OnHealth("raid" .. i) end end
	else
		for i = 1, 4 do if UnitExists("party" .. i) then OnHealth("party" .. i) end end
	end
end

local function OnDeathRecord(r)
	if not r or not r.me or not Active() then return end
	local what = r.killer or (r.env and r.env ~= "Unknown" and r.env) or nil
	if what then table.insert(db.run.myKillers, what) end
end

---------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_ALIVE",
	"PLAYER_UNGHOST", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_LOOT", "ENCOUNTER_END", "BOSS_KILL",
	"PLAYER_XP_UPDATE", "PLAYER_MONEY", "QUEST_TURNED_IN", "UNIT_HEALTH", "UNIT_FLAGS",
	"GROUP_ROSTER_UPDATE", "PLAYER_LOGOUT" }) do
	pcall(events.RegisterEvent, events, event)
end

local checkPending = false
local function CheckSoon()
	if checkPending then return end
	checkPending = true
	-- The instance's details settle a moment after the loading screen.
	C_Timer.After(1, function()
		checkPending = false
		Check()
	end)
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= ADDON then return end
		RiksantikvarieambetetDB = RiksantikvarieambetetDB or {}
		db = RiksantikvarieambetetDB
		db.history = db.history or {}
		if db.on == nil then db.on = true end
		if db.party == nil then db.party = false end
		if Rattsmedicinalverket and Rattsmedicinalverket.Register then Rattsmedicinalverket.Register(OnDeathRecord) end
		return
	end
	if not db then return end
	if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
		if event == "PLAYER_ENTERING_WORLD" then
			lastMoney = GetMoney()
			xpLast = nil
			OnXP()
		end
		CheckSoon()
		C_Timer.After(1.5, Seed)
	elseif event == "GROUP_ROSTER_UPDATE" then
		Seed()
	elseif event == "PLAYER_LOGOUT" then
		-- Also a /reload: back inside within 15 minutes carries on, and a
		-- login days later doesn't count the night as time inside.
		if db.run and not db.run.left then db.run.left = time() end
	elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then OnXPMessage(...)
	elseif event == "CHAT_MSG_LOOT" then OnLoot(...)
	elseif event == "ENCOUNTER_END" then
		local _, name, _, _, success = ...
		if success == 1 or success == true then AddBoss(name) end
	elseif event == "BOSS_KILL" then
		local _, name = ...
		AddBoss(name)
	elseif event == "PLAYER_XP_UPDATE" then OnXP()
	elseif event == "PLAYER_MONEY" then OnMoney()
	elseif event == "QUEST_TURNED_IN" then
		if Active() then db.run.quests = db.run.quests + 1 end
	elseif event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
		OnHealth((...))
	end
end)

SLASH_RAA1 = "/raa"
SLASH_RAA2 = "/riksantikvarie"
SlashCmdList.RAA = function(msg)
	if not db then return end
	msg = strtrim(msg or ""):lower()
	if msg == "" then
		if Active() then
			Say("utgrävningen pågår:")
			local lines = Lines(db.run)
			table.remove(lines, 1)
			for _, line in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("   " .. line) end
		elseif db.history[1] then
			PrintLines(db.history[1].lines)
		else
			Say("inga utgrävningar än. Rapporten kommer när du lämnar en instans.")
		end
	elseif msg == "lista" or msg == "list" then
		if #db.history == 0 then Say("inga utgrävningar än.") return end
		Say("de senaste utgrävningarna:")
		for i = 1, math.min(10, #db.history) do
			local h = db.history[i]
			DEFAULT_CHAT_FRAME:AddMessage("   " .. date("%d/%m %H:%M", h.start) .. "  " .. h.list)
		end
	elseif msg == "grupp" or msg == "group" then
		db.party = not db.party
		Say(db.party and "en rad om utgrävningen går också till gruppchatten." or "rapporten visas bara för dig.")
	elseif msg == "av" or msg == "off" or msg == "på" or msg == "pa" or msg == "on" then
		db.on = not (msg == "av" or msg == "off")
		Say(db.on and "rapporterna är på." or "rapporterna är av.")
	else
		Say("/raa visar den senaste rapporten (eller hur det går nu), /raa lista de senaste utgrävningarna, /raa grupp slår på eller av en rad i gruppchatten, /raa av | på.")
	end
end
