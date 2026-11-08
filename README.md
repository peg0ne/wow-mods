# THÖNDERSTÖRM addons: ideas backlog

Addons for the guild THÖNDERSTÖRM on a Classic-era client (`## Interface: 16001`).
Guild addons are named after Swedish public institutions and companies.

## Existing addons

| Addon | What it does |
|---|---|
| Arbetsformedlingen | Shared quests (`/uppdrag`) and the Platsbanken group-finder board (`/platsbanken`) |
| Skatteverket | Guild tax on looted gold, vendor and auction sales; standings in `/skatt` |
| Swedbank | Guild loans; only the guild leader sees applications |
| Gildepanel | Minimap button and panel that reads the Skatteverket and Swedbank data (sends nothing); its Addons window (`/gpanel addons`, Shift- or middle-click the minimap button) opens the other addons' windows and toggles their automatic settings |
| QuestLogSort | Puts completed quests last in the quest log and tracker; sorts the tracker by level |

Guild addons share data through `C_ChatInfo.SendAddonMessage` on the GUILD channel and store it in SavedVariables.
Arbetsformedlingen, Gildepanel and QuestLogSort are the user's own and live in this repo (moved here unchanged on 2026-11-07).
Skatteverket and Swedbank belong to someone else: they stay in the AddOns folder, and this repo only reads their behavior (for example, Skatteverket taxes vendor sales).

## This repo

New addons are built here, one folder per addon (`Name/Name.toc` + Lua files).
Run `.\link.ps1` from PowerShell to link every addon here into
`C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns` as a directory junction.
The game then loads straight from the repo, so edit, `/reload`, and test.

Releases: pushing a tag like `v1.1` (`git tag v1.1; git push origin v1.1`) runs `.github/workflows/release.yml`,
which zips every addon except ApiProbe into a GitHub release on https://github.com/peg0ne/wow-mods.
Guild members install it once in WowUp-CF (Get Addons → Install from URL → the repo link) and get updates from then on.
Don't install them through WowUp on the dev machine: it would replace the junctions from `link.ps1`.

Conventions (matching the existing addons):
- Folder and SavedVariables names are ASCII (`Atervinningscentralen`); `## Title` keeps the Swedish spelling.
- Chat output is in Swedish, starting with a colored addon name and a lowercase sentence.
- TOC `## Notes` are in English.
- Once released, never rename the folder or SavedVariables names, or saved data is lost.

## The Forever client (learned with ApiProbe, 2026-11-07)

Despite `## Interface: 16001`, the client (version 1.60.1) runs on a current retail engine. Write for the retail API:
- **Missing:** the old globals `GetItemInfo`, `GetSpellInfo`, `GetSpellLink`, `GetContainerItemInfo`, `UseContainerItem`, all Classic trade skill and craft functions, `GetSkillLineInfo`, `CombatLogGetCurrentEventInfo`, `InviteUnit`, `GuildRoster`, `SendAddonMessage`. Use `C_Item`, `C_Spell`, `C_Container`, `C_TradeSkillUI`, `GetProfessions`/`GetProfessionInfo`, `C_PartyInfo`, `C_GuildInfo` and `C_ChatInfo` instead.
- **Combat log is closed:** registering `COMBAT_LOG_EVENT_UNFILTERED` gets the addon blocked ("blocked from an action only available to the Blizzard UI"). Use `C_DeathRecap` (with `GetDeathRecapLink` for the latest ID) for what killed you.
- **Hidden values:** `issecretvalue` exists. Some values can be hidden from addons and error when compared or printed; check them with `issecretvalue` first.
- **Tooltips:** there's no `OnTooltipSetItem`/`OnTooltipSetUnit`; use `TooltipDataProcessor.AddTooltipPostCall`.
- **Vendor timing:** `MerchantFrame` isn't shown yet when `MERCHANT_SHOW` fires.
- `ApiProbe/` records which functions and events exist into `WTF/Account/<account>/SavedVariables/ApiProbe.lua` (`/probe`, then `/reload`).

## Built

| Addon | Version | Status |
|---|---|---|
| Atervinningscentralen | 0.1 | Works in game (sells grays, repairs) |
| Skolverket | 0.1 | Works in game for your own recipes and the item tooltip; guild sync not yet tested (needs a second member) |
| Eniro | 0.1 | Works in game (member list); position sharing not yet tested (needs a second member) |
| Rattsmedicinalverket | 0.1 | Works in game (killer, level, ability, position from the Death Recap) |
| Polisen | 0.1 | Loads without errors; reports need a death to a hostile player |
| Dodsannonser | 0.1 | Built, not yet tested in game |
| Handlaggaren | 0.1 | Built, not yet tested in game |
| SCB | 0.1 | Built, not yet tested in game |
| Kolapp | 0.1 | Built, not yet tested in game |

## Accepted ideas

### Skolverket: guild crafting directory (built, v0.1)
- Opening a profession window saves its recipes, only ever adding (recipes are never unlearned, so collapsed headers and filters lose nothing). Enchanting is read through the Craft API.
- Professions and ranks come from the skill list, so they show before the window has been opened. A profession that disappears from the skill list (unlearned) is dropped, but only if no skill headers are collapsed.
- Sync (prefix `SKOLA`, protocol documented at the top of `Core.lua`): members announce each profession's rank and the time it last changed. Anyone with older data asks for it, and everyone who's online hears the answer. All data is kept between sessions, so offline crafters can be found.
- Outgoing messages are queued: a burst of 8, then 1 per second, because the server drops addon messages sent too fast.
- `/skola [search]` opens a window with three views: Recept (search, Shift-click to link, "Fråga" whispers the best online crafter), Cooldowns (shared cooldowns such as transmutes grouped), and Medlemmar (everyone's professions and when they were last seen).
- Item tooltips get a line: "Skolverket: Pelle, Kalle" (green online, grey offline).
- Limitations for now: a member's data spreads only while that member is online (nobody passes on someone else's data). Cooldowns only update when the owner opens the profession window.

### Eniro: where guild members are (built, v0.1)
- `/eniro` (or `/hitta`): online members from the guild roster with class color, level (colored by difficulty) and zone. Same zone first, then nearest, then closest in level. Filters: all, my zone, my level ±5. Whisper and invite buttons.
- Position sharing is opt-in per character (`/eniro dela` or the checkbox). While it's on, your position is sent every 10 s when you move and every 60 s when you stand still, never from inside an instance. Positions expire after 90 s.
- Members who share appear as class-colored dots on the world map, including on the continent map (through `C_Map.GetMapRectOnMap`). The list shows distance in metres (through `C_Map.GetWorldPosFromMapPos`).
- Ideas for later: dots on the minimap, a "nearby" column in Platsbanken.

### Rättsmedicinalverket: shared death detection (built, v0.1)
- A library addon for everything that needs to know who died and what killed them: Polisen now; Dödsannonser, SCB and Utmärkelser later.
- Each player reads their own combat log and keeps the damage they took in the last 10 s. On `PLAYER_DEAD` it builds a record: the killing blow (player, pet, NPC or environment such as falling or drowning), the killer's level, class and race if known, the zone and the position. If a pet or guard landed the killing blow, it also blames the hostile player who did the most damage.
- Sends the record to the guild (prefix `RMV`), keeps the last 500 deaths in `RattsmedicinalverketDB.deaths`, and calls listeners registered with `Rattsmedicinalverket.Register(fn)`. The record format is documented at the top of `Core.lua`.
- Only deaths of members running the addon are known.

### Polisen: shared PvP incident log (built, v0.1)
- Requires Rättsmedicinalverket. Every death to a hostile player (or blamed on one) becomes an incident. Incidents are kept for 30 days.
- Members who were offline catch up on login: one online member sends them up to 40 newer incidents (prefix `POLIS`).
- Warns you when a reported player appears on a nameplate, your target, mouseover, or in the combat log: a chat line, plus a raid-warning text and sound (`/polisen larm` toggles the warning and sound). It tells the guild once every 5 minutes per player, and `/polisen tyst` hides other members' sightings.
- Reported players' tooltips show their number of reports and their latest victim.
- `/polisen` window: Efterlysta (wanted, with "Glöm" to forget a player locally) and Händelser (incidents).

### Återvinningscentralen: auto-sell junk and auto-repair (built, v0.1)
- On `MERCHANT_SHOW`, sells all gray items with a sell price, 6 items every 0.2 s. It stops immediately if the vendor closes, because using an item away from a vendor would equip it.
- Then repairs everything if the vendor can and you can afford it, so the junk money helps pay.
- Prints "sålde 7 saker för 1g 23s, lagade utrustningen för 45s."
- Holding Shift while opening the vendor skips everything. `/avc` shows settings, `/avc sälj` and `/avc laga` toggle selling and repairing.
- Supports both `C_Container` and the older global bag functions, because it's unknown which one this client has.
- Tax: Skatteverket counts gold gained at an open vendor, so gray sales are taxed exactly like selling by hand. Repairs don't affect the tax.
- Ideas for later: personal never-sell list, guild-funded repairs, vendor restocking.

### Combined bags (interface)
- Replaces the separate bag frames with one window: a search box, item quality borders, a free-slot counter, and junk greyed out (shares the gray-item logic with Återvinningscentralen).
- Hook `ToggleBackpack` / `OpenAllBags` and read items with `C_Container` (or the older `GetContainerItemInfo`, depending on what this client has; check first).
- Bag frames aren't secure, but using an item from a custom button needs a `SecureActionButtonTemplate` (`type=item`) so it still works in combat.

### Bag sorting (interface)
- Classic has no sort button. Sort by moving one item at a time (`PickupContainerItem`), waiting for `ITEM_LOCK_CHANGED` / `BAG_UPDATE` between moves.
- Order: quality, then type, then name. Stop if combat starts. Hardest item in the backlog; build after Combined bags.

### Chat cleanup (interface)
- Shorter channel names ("[1. General]" becomes "[G]") and class-colored names.
- Copyable links: detect URLs and open a copy box when clicked.
- Spam filter for trade and LFG chat with a keyword list (`ChatFrame_AddMessageEventFilter`).

### Action bars (interface)
- Hide the gryphon art and shorten hotkey labels ("Mouse Button 4" becomes "M4", "Shift-" becomes "s").
- Cooldown numbers on buttons.
- Turn the whole icon red when out of range and blue when out of mana (hook the action button update, `IsActionInRange` / `IsUsableAction`).
- Only visual changes. Don't move secure bars in combat.

### Handläggaren: quest automation (built, v0.1)
- At a quest giver it hands in finished quests first, then picks up new ones (through `C_GossipInfo`, or the older quest greeting window), accepts them and completes them. Holding Shift when the window opens skips that conversation.
- Never hands in a quest that costs gold. Gray quests are skipped unless `/hl grå`.
- With several rewards it marks the one with the highest sell price with a coin icon. `/hl belöning` picks it automatically and prints what was chosen.
- `/hl dela` shares newly accepted quests with your group (off by default). `/hl prat` chooses an NPC's only chat option (off by default, because some single options set your hearthstone or open a vendor).
- `/hl` shows the settings, `/hl av` / `/hl på` turns the whole addon off or on.

### Kölapp: quest chain position (built, v0.1)
- Shows where a quest sits in its chain, like a queue ticket: the quest window title gets "(2/4)" when the quest is offered, in progress, at the reward screen and in the quest log's details. Hovering a quest in the quest log shows "Questkedja: del 2 av 4" and the next quests.
- Chat says "nummer 2 av 4 i kedjan: …" when you accept a chain quest (useful with Handläggaren, which accepts without showing the window) and "nästa i kedjan: … (3/4)" or "kedjan är klar" when you hand one in. `/kolapp tyst` turns the chat lines off.
- The client has no quest chain data, so `Kolapp/Data.lua` (about 2,700 quests) is generated from Questie's Classic database, fixes and blacklist (Questie v11.38.0, the last tag with that database; GPLv3) by `tools/kolapp_data.py`. Re-run it to refresh the data.
- Number = longest run of earlier quests + 1; total = number + longest run of later quests. Quests your race or class can't take are dropped, so class-quest branches only count for that class. Hub quests that open several branches count the longest one.
- Ideas for later: numbers in the NPC's quest list (gossip frame) and the quest tracker.

### Utmärkelser: homemade achievements (social)
- This client has no achievements. Events trigger them: `PLAYER_LEVEL_UP`, looting an epic, profession reaching 300, `UPDATE_FACTION` (exalted), first mount, boss kills (`UNIT_DIED` in the combat log), a run without dying.
- Announces unlocks in guild chat, has a panel, and shares a guild leaderboard through addon messages.

### SCB: guild statistics (built, v0.1)
- Each character counts its own deaths by cause (through Rättsmedicinalverket, if it's on), kills that gave experience (the first-person XP chat line, matched from `COMBATLOG_XPGAIN_FIRSTPERSON` so it works in any language), quests handed in (`QUEST_TURNED_IN`), gold in and out (`PLAYER_MONEY` deltas), and time played (from `TIME_PLAYED_MSG` when the player types /played, plus time logged in).
- Shares the totals on the guild channel (prefix `SCB`) at login, on level-up, on request, and every 10 minutes if they changed. Everyone keeps everyone's latest figures.
- `/scb` window: one row per member, sortable by clicking a column header, a guild total row, and generated fun facts ("THÖNDERSTÖRM har dött 52 gånger; 12% av dem var fall …").
- Limitation: counting starts when the addon is installed; there is no history before that.

### Dödsannonser: obituaries (built, v0.1)
- Requires Rättsmedicinalverket. Every member with the addon writes the obituary in their own chat from the death record they already received, so nothing extra is sent and nothing can be blocked.
- Example: "Vår kära Tungan Lingonsson (nivå 13 Rogue) har lämnat oss. Rycktes bort av en Decrepit Darkhound i Tirisfal Glades. Det var dödsfall nummer 2. Vila i frid."
- Wording is picked at random from lists in `Core.lua`, seeded by the death's id, so everyone sees the same text. It covers NPCs, abilities, hostile players ("Polisen är underrättad"), pets, falling, drowning and lava. There's an extra line when the killer was 5+ levels below the victim.
- `/dodsannons` lists the last 10, `/dodsannons tyst` hides new ones in chat. Your own obituary is also posted to guild chat 2 s after you die (on by default, for members without the addon and the guild's Discord bridge; `/dodsannons gillet` turns it off). Members with the addon hide that guild line, since they already show the notice.
- Polisen already files the report for player kills, through Rättsmedicinalverket.

### Fun extras (social)
- **Fotoalbum:** takes a screenshot (`Screenshot()`) on level-up, epic loot or a boss kill, and keeps a list with dates.
- **Svenska Spel:** a guild lottery. Members buy tickets with gold or tax credit; the leader draws a winner and the result is shared through addon messages. Works with Skatteverket and Swedbank.
- **/fika:** invites the guild to the inn you're at and shows the location to everyone. Anyone who joins sits down and drinks with emotes.
- **Emote replies:** /hug someone back automatically when they /hug you. Prepared "grattis" messages when a guild member levels up.

## Ideas mentioned but not chosen

**Guild:** Försäkringskassan (repair and death insurance paid from tax), Kronofogden (collects overdue Swedbank loans), Riksdagen (guild votes), SMHI (world-buff timers), Folkbokföring (links mains and alts), SJ (flight timer), Systembolaget (consumables check).

**Interface:** square minimap with a button drawer, unit frames (class colors, real health numbers, draggable), tooltips (cursor anchor, guild rank, "taught by guildmate").

**Automation:** vendor restocking (reagents, ammo, food, water), gear sets, auto-greed and mail helpers, auto-accepting guild invites and declining duels, double-click fishing.

**Other non-guild ideas:** vendor prices in tooltips, map coordinates, quest XP in the quest log, XP/hour tracker, gold/hour tracker, death recap, rare spawn alert, swing timer, enemy cast bars, reagent and ammo counter.

## Testing
Claude can't run the game. Install the addon, `/reload` in game, and report errors. Turning on `/console scriptErrors 1` shows Lua errors as they happen.
