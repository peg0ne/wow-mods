# THÖNDERSTÖRM addons: ideas backlog

Addons for the guild THÖNDERSTÖRM on a Classic-era client (`## Interface: 16001`).
Guild addons are named after Swedish public institutions and companies.

## Existing addons

| Addon | What it does |
|---|---|
| Arbetsformedlingen | Shared quests (`/uppdrag`) and the Platsbanken group-finder board (`/platsbanken`) |
| Skatteverket | Guild tax on looted gold, vendor and auction sales; standings in `/skatt` |
| Swedbank | Guild loans; only the guild leader sees applications |
| Gildepanel | Minimap button and panel that reads the Skatteverket and Swedbank data (sends nothing) |
| QuestLogSort | Puts completed quests last in the quest log and tracker; sorts the tracker by level |

Guild addons share data through `C_ChatInfo.SendAddonMessage` on the GUILD channel and store it in SavedVariables.
Arbetsformedlingen, Gildepanel and QuestLogSort are the user's own and live in this repo (moved here unchanged on 2026-11-07).
Skatteverket and Swedbank belong to someone else: they stay in the AddOns folder, and this repo only reads their behavior (for example, Skatteverket taxes vendor sales).

## This repo

New addons are built here, one folder per addon (`Name/Name.toc` + Lua files).
Run `.\link.ps1` from PowerShell to link every addon here into
`C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns` as a directory junction.
The game then loads straight from the repo, so edit, `/reload`, and test.

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
| Atervinningscentralen | 0.1 | Built; loads in game (`/avc` works), vendor run not yet tested |
| Skolverket | 0.1 | Built, not yet tested in game |
| Eniro | 0.1 | Built, not yet tested in game |
| Rattsmedicinalverket | 0.1 | Built, not yet tested in game |
| Polisen | 0.1 | Built, not yet tested in game |

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

### Quest automation
- Accept and turn in quests automatically (`QUEST_DETAIL` → `AcceptQuest`, `QUEST_PROGRESS` → `CompleteQuest`, `QUEST_COMPLETE` → `GetQuestReward`). Holding Shift skips the automation.
- Skip the gossip dialog when it has only one option.
- With several rewards: highlight the one with the highest vendor price (from `GetItemInfo`) instead of picking it, or pick it if the user turns that setting on.
- Share new quests with the party automatically (`QuestLogPushQuest`). Works well with Arbetsförmedlingen.

### Utmärkelser: homemade achievements (social)
- This client has no achievements. Events trigger them: `PLAYER_LEVEL_UP`, looting an epic, profession reaching 300, `UPDATE_FACTION` (exalted), first mount, boss kills (`UNIT_DIED` in the combat log), a run without dying.
- Announces unlocks in guild chat, has a panel, and shares a guild leaderboard through addon messages.

### SCB: guild statistics (social)
- Totals per member and for the whole guild: kills, deaths (and their cause), gold earned, quests completed, time played (`TIME_PLAYED_MSG`).
- Fun facts, for example "THÖNDERSTÖRM has died 1,412 times; 38% of those were falling".
- Can reuse the gold counting from Skatteverket and the death detection from Polisen and Dödsannonser.

### Dödsannonser: obituaries (social)
- When a guild member dies, posts a newspaper-style obituary in guild chat: "Our beloved Pelle, level 34, was taken from us by a Murloc in Westfall."
- Gets the killer from the last damage event in the combat log. Only one player should post (the person who died) to avoid duplicates.
- Ties into Polisen: if the killer was a hostile player, it files a report there as well.

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
