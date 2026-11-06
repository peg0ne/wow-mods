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

## Accepted ideas (not started)

### Skolverket: guild crafting directory
- Saves each member's recipes when they open a profession window (`GetNumTradeSkills` / `GetTradeSkillInfo`). Enchanting uses the Craft API (`GetNumCrafts` / `GetCraftInfo`), so it needs separate handling.
- Re-scans when a recipe is learned and syncs the lists to the guild with addon messages.
- `/skola <search>` shows who can craft an item, whether they're online, and their profession cooldowns (`GetTradeSkillCooldown`), for example transmutes and Mooncloth.

### Eniro: where guild members are
- Basic version: zone and level come from the guild roster (`GetGuildRosterInfo`), so it sends no data.
- Optional version: an opt-in setting shares each player's exact position (`C_Map.GetBestMapForUnit` + `C_Map.GetPlayerMapPosition`) on a slow timer and shows guild members as pins on the world map.
- "Nearby and around your level" list; could be added to Platsbanken.

### Polisen: shared PvP incident log
- Reads `COMBAT_LOG_EVENT_UNFILTERED` to detect when a hostile player kills you or a guild member, then records who, where, their level and class, and the time.
- Shares those reports with the guild.
- Warns you when a reported player shows up on your nameplates (`NAME_PLATE_UNIT_ADDED`), your target or the combat log, for example "⚠ Gankarn spotted (3 reports)".

### Auto-sell junk and auto-repair (not a guild addon)
Possible name: **Återvinningscentralen** (Swedish for recycling centre).
- On `MERCHANT_SHOW`, sells all gray (quality 0) items in your bags and prints the total.
- Repairs all gear if the merchant can repair (`CanMerchantRepair`, `GetRepairAllCost`, `RepairAllItems`).
- Prints a summary like "Sold 7 items for 1g 23s, repaired for 45s".
- Possible extra: let Skatteverket count the gray sales as taxable vendor income, or keep them out of the tax. Needs a decision.

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
