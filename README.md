# THÖNDERSTÖRM addons: ideas backlog

Addons for the guild THÖNDERSTÖRM on a Classic-era client (`## Interface: 16001`).
Guild addons are named after Swedish public institutions and companies.

## Existing addons

| Addon | What it does |
|---|---|
| Skatteverket | Guild tax on looted gold, vendor and auction sales; standings in `/skatt`. 0.34 also has work orders (Arbetsorder), elections (Folkvald representant), Socialbidrag and tickets (Kontakta oss!), and a public `SkatteverketAPI` (`Standing`, `MemberStanding`, `TaxRate`, `Locked`, `Toggle(page)`) that our addons use before their own math. Since 0.32 the deposit back from an AH sale is not taxed |
| Swedbank | Guild loans; only the guild leader sees applications. Since 0.11 interest is charged per week begun (from the day after the gold is sent), and the leader can offer a loan for the member to answer |
| Bokforing | Crafting profit window. Since 0.6.4 a sale's value is after the AH's 5% cut and the guild tax (`ns.Keep`) |
| Gildepanel | A compact bar (`/gpanel`) that drops open on hover into a panel: your Skatteverket standing (from `SkatteverketAPI` when it has one) and tax, the favourites, who is online, your Swedbank loans. The Addons window (`/gpanel addons`, since 2.13 in tabs: Fönster, Uppdrag, Gillet, Spelet; it remembers the last one) opens the other addons' windows (and Skatteverket's Arbetsorder, Folkvald, Socialbidrag and Kontakta oss pages through `SkatteverketAPI.Toggle`) and toggles their automatic settings and sets the max camera distance (`/gpanel kamera`); turns herb/mineral tracking back on after login (`/gpanel spårning`); warns an hour of play before your standing drops; celebrates with a gold flash, a banner, flying coins and a fanfare when you pay your tax (`/gpanel firande`, preview with `/gpanel firande test`); since 2.15, at the account's first login of the day, opens Dagens sammanfattning: your tax standing, Swedbank loans, who is online and the guild message, and since the last summary who joined, left or levelled, Dödsannonser's obituaries and Polisen's reports (`/gpanel idag` shows it again, `/gpanel dagens` turns it off; also in the Addons window). Since 2.18 a window button of an addon that is installed but switched off in the AddOns list is greyed; clicking it offers to switch it on and reload, and Konsumentverket's gear search has a button of its own |
| QuestLogSort | Puts completed quests last in the quest log (per zone) and the tracker. The quest log's rows are only moved, never rewritten, and the zone lines are its own frames beside the tracker, so it doesn't taint Blizzard's UI (1.8). Waits until combat ends before re-sorting the tracker. The tracker has two orders: by level (`/qls nivå`, the default) or zone by zone (`/qls zon`): the zone you are in first, then the quest log's order, by level within a zone with completed last, and each zone's name beside its first quest. Clicking a zone's name folds it (its quests are unwatched, the zone stays as "+ Zone (3)" under the last quest; per character) and clicking again unfolds it; `/qls öppna` unfolds all. `/qls av` turns the whole addon off, for Questie users whose tracker fights over the order (they get a one-time hint at login). Both switches are also in Gildepanel's Addons window |
| Statskontoret | Shared code the other addons depend on: the guild window (top-level, so windows stack cleanly) and, since 0.2, its parts (word tabs with a gold underline, striped list rows, a scroll mark, rules, sort arrows), addon messages (throttled, so floods are not dropped), roster requests, invites, class colors. Shows nothing itself |
| Bolagsverket | Names on the party frames (old, retail and raid-style) in one color you pick (`/bv välj` opens the color picker; light blue until you do), or class colors with `/bv egen`; guildmates have a color of their own (since 0.4, guild-chat green until `/bv välj gille`, off with `/bv gillefärg`) on the party frames and nameplates alike; and a lightning bolt after the names of guildmates; `/bv färg` and `/bv gille` switch them. The floating names over characters can't be recolored by an addon, so `/bv gillenamn` (on by default) shows the guild's name under them instead, through the game's `UnitNameGuildTitle` setting. Since 0.3, `/bv namnskyltar` (off by default) shows friendly players as names-only nameplates instead, which can be styled: guildmates in the guild color with the bolt, your group in the party color, the other faction always red (since 0.5, flagged or not); since 0.5 also other players' pets and minions, styled as their owners (a guildmate's pet with the guild color and bolt, a stranger's and your own in the game's color; the owner of a pet outside your group is read from its tooltip), everyone else in the game's own color, `<Guild>` under the name; the nameplate settings it changes (including the nameplate range, raised to 60 yards so the game's own names don't take over at a distance) are restored when turned off. The game locks friendly nameplates in dungeons and raids, so there they stay plain (the party frames cover it). All of it except `/bv gillenamn` is also in Gildepanel's Addons window (since Gildepanel 2.17 with "Färga namnen" as the main switch and the two colors under it), where the color square opens the picker |
| FrokenUr | Fröken Ur writes the time left on every cooldown (action buttons, items, auras): seconds with one decimal under a minute (`2.9`, cut off, not rounded), red under 3 s, then `1:30`, then `2h`. The global cooldown gets no number. Values the client hides from addons are left to the game's own countdown. `/ur` switches it on and off; also in Gildepanel's Addons window |
| Konsumentverket | What your crafts are worth at a vendor, for levelling a profession cheaply (`/konsument`, `/kv`). For every recipe the character knows (read when the profession window opens, saved per character and profession): what the reagents cost, what a vendor pays for the result after Skatteverket's tax, the profit, and how many your bags can make, best first; names colored by difficulty, and "Bara recept som ger färdighet" hides the grey ones. Every reagent costs what you'd pay to buy it: the cheaper of the vendor's price (noted at merchants, unlimited stock only; Bokföring's notes fill in, read only) and the auction house's (Auctionator's latest scan); "AH" after the cost when something comes from there, "?" when a price is missing. Can open beside the profession window (off by default since 0.2.5; `/konsument auto` turns it on, also in Gildepanel's Addons window). Since 0.2 an equipment search (`/konsument sök`): tick stats an item must all have, and optionally slots, armor types and "only what I can wear now" (on by default: your level, and the armor your class can wear); it lists matching gear your recipes make (any character on the account, with the reagent cost) and armor and weapons from the auction house's latest scan (Skanna AH with the auction house open, a browse of armor and weapons; saved, so it works away from the AH; the AH's own searches add to it), most of the ticked stats first, then cheapest. Stats come from `GetItemStats`, or the tooltip's English lines without it. Right-click a recipe (in either window) to buy the reagents for N crafts, as Bokföring does: what the AH sells cheapest goes into an Auctionator shopping list ("Konsumentverket: name xN"), what a vendor sells cheaper is printed with where; what is in the bags is taken off unless unticked in the menu. |
| Postnord | Tells you in chat when a guildmate runs a newer release of this addon pack (`/postnord`). The release workflow stamps the tag into `Postnord.toc`; a copy run from the repo says `dev`, sends nothing and never warns |

Guild addons share data through `C_ChatInfo.SendAddonMessage` on the GUILD channel and store it in SavedVariables.
Gildepanel and QuestLogSort are the user's own and live in this repo (moved here unchanged on 2026-11-07).
Skatteverket, Swedbank and Bokforing belong to someone else: they stay in the AddOns folder, and this repo only reads their behavior and saved data (for example, Skatteverket taxes vendor sales). Prefer `SkatteverketAPI` where it has the answer; keep our own math only as a fallback (the API gives no debt age, so Gildepanel's countdowns stay ours).

## This repo

New addons are built here, one folder per addon (`Name/Name.toc` + Lua files).
Run `.\link.ps1` from PowerShell to link every addon here into
`C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns` as a directory junction.
The game then loads straight from the repo, so edit, `/reload`, and test.

Releases: pushing a tag like `v1.1` (`git tag v1.1; git push origin v1.1`) runs `.github/workflows/release.yml`,
which zips every addon except ApiProbe into a GitHub release on https://github.com/peg0ne/wow-mods.
Guild members install it once in WowUp-CF (Get Addons → Install from URL → the repo link) and get updates from then on.
Don't install them through WowUp on the dev machine: it would replace the junctions from `link.ps1`.

Checks: every push runs `.github/workflows/lint.yml`, which compiles each Lua file under 5.1 and runs
[luacheck](https://github.com/lunarmodules/luacheck) with `.luacheckrc`. Run `luacheck .` locally before pushing.
A new game API or SavedVariables name has to be added to `.luacheckrc` (read_globals or globals); that is
what lets the check catch typos and calls to functions this client doesn't have.

Shared code lives in `Statskontoret` (global `Statskontoret`). An addon that uses it lists it in its `.toc`
(`## Dependencies: Statskontoret`) so the game loads it first. Put code there when a second addon needs it,
keep it backwards compatible (add functions, don't change existing ones) and raise `Statskontoret.API` when adding.

Conventions (matching the existing addons):
- Folder and SavedVariables names are ASCII (`Atervinningscentralen`); `## Title` keeps the Swedish spelling.
- Chat output is in Swedish, starting with a colored addon name and a lowercase sentence.
- TOC `## Notes` are in English.
- Once released, never rename the folder or SavedVariables names, or saved data is lost.
- To retire an addon, don't delete its folder: WowUp may leave the old copy behind and members won't delete it. Ship an empty `Core.lua` that calls `C_AddOns.DisableAddOn` under the same name instead (see Revisorsinspektionen 0.2), and remove its group from Gildepanel's Addons window and its names from `.luacheckrc`.
- A setting a member can switch belongs in Gildepanel's Addons window (`SETTINGS` in `Gildepanel.lua`) as well as its slash command. An item with `slash = { key, toggle }` runs the command; `slash = { key, on, off }` runs one of two (QuestLogSort's "zon"/"nivå").

## The Forever client (learned with ApiProbe, 2026-11-07)

Despite `## Interface: 16001`, the client (version 1.60.1) runs on a current retail engine. Write for the retail API:
- **Missing:** the old globals `GetItemInfo`, `GetSpellInfo`, `GetSpellLink`, `GetContainerItemInfo`, `UseContainerItem`, all Classic trade skill and craft functions, `GetSkillLineInfo`, `CombatLogGetCurrentEventInfo`, `InviteUnit`, `GuildRoster`, `SendAddonMessage`. Use `C_Item`, `C_Spell`, `C_Container`, `C_TradeSkillUI`, `GetProfessions`/`GetProfessionInfo`, `C_PartyInfo`, `C_GuildInfo` and `C_ChatInfo` instead.
- **Combat log is closed:** registering `COMBAT_LOG_EVENT_UNFILTERED` gets the addon blocked ("blocked from an action only available to the Blizzard UI"). Use `C_DeathRecap` (with `GetDeathRecapLink` for the latest ID) for what killed you.
- **Hidden values:** `issecretvalue` exists. Some values can be hidden from addons and error when compared or printed; check them with `issecretvalue` first.
- **Tooltips:** there's no `OnTooltipSetItem`/`OnTooltipSetUnit`; use `TooltipDataProcessor.AddTooltipPostCall`.
- **Nameplate settings (2026-11-14):** the newer names: `nameplateShowFriendlyPlayers` (not `nameplateShowFriends`), `nameplateShowOnlyNameForFriendlyPlayerUnits` (not `nameplateShowOnlyNames`), `nameplateShowFriendlyNpcs`. ApiProbe saves every nameplate and unit-name setting with its value in `ApiProbeDB.nameCvars`.
- **Vendor timing:** `MerchantFrame` isn't shown yet when `MERCHANT_SHOW` fires.
- `ApiProbe/` records which functions and events exist into `WTF/Account/<account>/SavedVariables/ApiProbe.lua` (`/probe`, then `/reload`).

## Built

| Addon | Version | Status |
|---|---|---|
| Atervinningscentralen | 0.3 | Works in game (sells grays, repairs); 0.2 repairs after the money for the grays has arrived. 0.3 opens your bags at a vendor or the bank (`/avc väskor`, also in Gildepanel's Addons window); not yet tested in game |
| Skolverket | 0.6 | Works in game: the item tooltip (reads Skatteverket's recipes). 0.6 drops the guild's cooldown list (`/skola`); not yet tested in game |
| Eniro | 0.4.1 | Works in game: member list; position sharing needs a second member online to test. 0.4 adds a search box on the world map (zones and guildmates); not yet tested in game. 0.4.1: the filters are tabs at the top, and an unknown distance shows "-" |
| Rattsmedicinalverket | 0.5 | Works in game (killer, level, ability, position from the Death Recap); 0.4 stops a second "unknown cause" record when `PLAYER_DEAD` fires again for the same death |
| Polisen | 0.4.1 | Works in game; reports need a death to a hostile player. 0.4: battleground and arena deaths and sightings are ignored; catching up after login no longer misses incidents (asks from where it was last complete, pages through long gaps, server time). Full catch-up needs the answering member on 0.4 too. 0.4.1: tabs at the top, column widths per tab |
| Dodsannonser | 0.6 | Works in game (level-up notices since 0.4; hunter pet level-ups since 0.5, preview with `/dodsannons test husdjur`, off with `/dodsannons husdjur`) |
| Handlaggaren | 0.4 | Works in game; 0.3 leaves repeatable quests alone (`/hl upprepade` to take them) and never picks a reward before every choice has loaded. 0.4 says in party chat when a quest's objectives are done, like Questie (`/hl meddela` turns it off); not yet tested in game |
| SCB | 0.4.1 | Works in game; saves the whole guild roster (rank, class, level, notes, last online) to `SCBDB.roster`. 0.4.1: the total row follows the members, a sort arrow on the chosen column |
| Kolapp | 0.4 | Works in game: quest tracker numbers and the quest on item tooltips; 0.4 only changes the tracker's shown text, which stops the "blocked action" errors in combat |
| Statskontoret | 0.2 | Shared library; 0.2 adds window parts (`Tabs`, `Stripe`, `ScrollMark`, `Rule`, `SortArrow`), used by Polisen, Eniro, SCB 0.4.1 and Gildepanel 2.17; not yet tested in game |
| Bolagsverket | 0.5 | Works in game, including the nameplates (`/bv namnskyltar`; 0.3.1 uses this client's nameplate setting names). 0.2's own party color and 0.4's guild color not yet tested in game |
| Revisorsinspektionen | 0.2 | Retired in v1.17.0; 0.2 is an empty copy that switches itself off |
| Konsumentverket | 0.2.5 | New (2026-11-17); 0.2.5: no longer opens beside the profession window by default (`/konsument auto` or Gildepanel turns it on; switched off once for everyone, since the old default had been saved); "Bara det jag kan bära nu" is on by default and also hides armor your class can't wear yet (mail for hunters and shamans and plate at 40; weapons not checked); 0.2.4: armor is no longer counted as resistance (the game calls it resistance 0), an item keeps its name once read (with thousands of AH items the game forgot some), and an item that never loads is asked for once per search, not in a loop (the footer's count jumped between 1 and 244); 0.2.3: the equipment search no longer searches again every second while auction house items load (it asked for every missing item each time, without end); it asks once, counts them down in the footer and searches once when the last has come; the list changes only on your own actions (ticks, tabs, a finished scan, the Uppdatera button; the footer says when there are new matches), and the mouse wheel no longer re-sorts it; 0.2 adds the equipment search (a new file: needs a game restart) and is on by default again (0.1.2 was off by default, never released); 0.1.1 prices reagents at the cheaper of vendor and auction house, not at what a vendor pays for your own mats; not yet tested in game |
| Arbetsformedlingen | 0.8 | Retired after v1.20.0 (shared quests and Platsbanken weren't used); 0.8 is an empty copy that switches itself off |

## Accepted ideas

### Skolverket: crafters on tooltips (built, v0.3; cooldowns dropped in 0.6)
- 0.1-0.2 were a whole guild crafting directory. Skatteverket 0.22 has one now (`/skatt yrken`: professions, every member's recipes with search, a recipe window, and offline members' lists relayed by the guild leader), so 0.3 (2026-11-08) keeps only what Skatteverket lacks.
- Item tooltips get a line "Kan tillverkas av: Pelle, Kalle" (green online, grey offline), read from `SkatteverketDB.recipes`. On Forever those lists hold recipe numbers (`s<recipeID>`), so the item each recipe makes is looked up once with `C_TradeSkillUI.GetRecipeSchematic`. Nothing is sent for this.
- 0.3-0.5 also shared profession cooldowns on the guild channel (prefix `SKOLA`) and listed them in `/skola`, and Gildepanel's Dagens sammanfattning showed your own. Nobody used it, so 0.6 (2026-11-17) removes it: no window, nothing sent, and the saved cooldowns are emptied. Gildepanel 2.16 drops its Cooldowns button and the summary's line.

### Eniro: where guild members are (built, v0.1)
- `/eniro` (or `/hitta`): online members from the guild roster with class color, level (colored by difficulty) and zone. Same zone first, then nearest, then closest in level. Filters: all, my zone, my level ±5. Whisper and invite buttons.
- Position sharing is opt-in per character (`/eniro dela` or the checkbox). While it's on, your position is sent every 10 s when you move and every 60 s when you stand still, never from inside an instance. Positions expire after 90 s.
- Members who share appear as class-colored dots on the world map, including on the continent map (through `C_Map.GetMapRectOnMap`). The list shows distance in metres (through `C_Map.GetWorldPosFromMapPos`).
- Map search (0.4, `Search.lua`): a box at the top left of the world map (`/eniro sök` opens the map with the cursor in it; it says so if the box is missing or covered). A new file like this one needs a game restart, not just `/reload`. Type part of a zone, city or dungeon name, or a guildmate's name; Enter picks the top result, the arrow keys move. Guildmates come first: one who shares opens on their map with their dot pulsing for 8 s, one who doesn't opens on their roster zone. Zones come from `C_Map.GetMapChildrenInfo` under the top map, read once. With OpenMap's stitched map (`OpenMapAPI`) picking a zone or a sharing guildmate glides OpenMap's view there (`ShowWorld`), and the dots are placed through `OpenMapAPI.WorldFromMap`/`MapFromWorld` above its art (`ArtTopLevel`), so they show anywhere in its view.
- Ideas for later: dots on the minimap.

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
- Since 0.3, opens every bag at a vendor or the bank (`MERCHANT_SHOW`, `BANKFRAME_OPENED`) and on leaving closes only the bags it opened, so ones you had open stay open. On by default; `/avc väskor` toggles it. Shift doesn't skip it. Does nothing when Baganator is loaded: Baganator has its own Auto Open settings (vendor and bank on by default) and replaces the game's bag frames.
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

### Handläggaren: quest automation (built, v0.2)
- At a quest giver it hands in finished quests first, then picks up new ones (through `C_GossipInfo`, or the older quest greeting window), accepts them and completes them. Holding Shift when the window opens skips that conversation.
- Never hands in a quest that costs gold. Gray quests are skipped unless `/hl grå`.
- Quests a party member shares are left for you to accept or decline unless `/hl delade` (or the checkbox in `/gpanel addons`).
- With several rewards it marks the one with the highest sell price with a coin icon. `/hl belöning` picks it automatically and prints what was chosen.
- `/hl dela` shares newly accepted quests with your group (off by default). `/hl prat` chooses an NPC's only chat option (off by default, because some single options set your hearthstone or open a vendor).
- In a party it says in party chat when one of your quests has all its objectives done, like Questie: "{rt1} Handläggaren: klart: [Quest]". Only on the change to done, never for quests already done at login or when accepted. Not in battlegrounds or arenas. `/hl meddela` turns it off.
- `/hl` shows the settings, `/hl av` / `/hl på` turns the whole addon off or on.

### Kölapp: quest chain position (built, v0.2)
- Shows where a quest sits in its chain, like a queue ticket: the quest window title gets "(2/4)" when the quest is offered, in progress, at the reward screen, in the quest log's details and in the quest tracker. Hovering a quest in the quest log shows "Questkedja: del 2 av 4" and the next quests.
- Chat says "nummer 2 av 4 i kedjan: …" when you accept a chain quest (useful with Handläggaren, which accepts without showing the window) and "nästa i kedjan: … (3/4)" or "kedjan är klar" when you hand one in. `/kolapp tyst` turns the chat lines off.
- The client has no quest chain data, so `Kolapp/Data.lua` (about 2,700 quests) is generated from Questie's Classic database, fixes and blacklist (Questie v11.38.0, the last tag with that database; GPLv3) by `tools/kolapp_data.py`. Re-run it to refresh the data.
- Number = longest run of earlier quests + 1; total = number + longest run of later quests. Quests your race or class can't take are dropped, so class-quest branches only count for that class. Hub quests that open several branches count the longest one.
- The tracker is labelled by hooking every `*BlockMixin:SetHeader` (and older trackers' `SetBlockHeader`) and setting the title again with the number, so the tracker measures the longer line itself. Only blocks whose title contains the quest's title are changed (this client puts the level in front, "[21] Beren's Peril", and keeps the quest ID in the block's `poiQuestID`).
- Item tooltips (0.3; bags, Baganator, bank, links) name the quest an item belongs to: "Uppdrag: Wolves Across the Border (1/2) 3/8" for quests in your log, "Startar: …" for items that start a quest. A quest item that belongs to no quest in your log names its quests with "klar, kan slängas" or "inte i loggen". `/kolapp föremål` turns it off.
- Matches item objectives by name from the live quest log (`C_QuestLog.GetQuestObjectives`) and usable quest items by ID, plus `Kolapp/ItemData.lua` (item objectives, items a quest hands out, `requiredSourceItems` and quest-starting items from the same Questie data, also built by `tools/kolapp_data.py`) for items that aren't an objective, like letters to deliver. Questie's item database adds quest items a quest rewards and nothing needs ("Belöning från: Thule Ravenclaw" on Bethor's Potion).
- For a copy in the bags, `C_Container.GetContainerItemQuestInfo` names the quest the item starts or belongs to, whatever its category (Venture Co. Work Order is Miscellaneous and missing from Questie's data).
- Quest items still unexplained are looked up in the text of the quests in your log ("Nämns i: …"); reading that text selects each quest in turn and puts the old selection back. An item still unknown shows "Kölapp: okänt questföremål (ID …)".
- Ideas for later: numbers in the NPC's quest list (gossip frame).

### Revisorsinspektionen (retired 2026-11-13, after v1.16.1)
- Added Skatteverket's guild tax to Bokföring's profit and dimmed recipes under a 12% markup. Bokföring 0.6.4 now takes the tax off sales itself (`ns.Keep`), so it counted the tax twice; Skatteverket 0.32 also stopped taxing the AH deposit. Its group left Gildepanel's Addons window in 2.12. The pack still ships an empty 0.2 that writes over the old code (WowUp may leave a removed folder behind) and switches itself off with `C_AddOns.DisableAddOn`.

### Arbetsförmedlingen (retired 2026-11-17, after v1.20.0)
- Shared quests (`/uppdrag`: which of your quests online guildmates also have, and who has a quest in the quest log tooltip) and Platsbanken (`/platsbanken`), a guild board for finding group members. Nobody used them. Its group and window buttons left Gildepanel's Addons window in 2.16. The pack ships an empty 0.8 that disables itself.

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
- The guild chat copy is hidden by sender too, not only by exact text: the line can differ from ours (the death count is each member's own, long fields get shortened), which showed the obituary twice (0.4).
- Level-ups (0.4, 2026-11-09): "Familjenytt: Tungan Lingonsson (Rogue) fyller 14 i dag. Uppvaktning undanbedes." Death records don't cover levels, so on `PLAYER_LEVEL_UP` the one who levelled sends `L;<name>;<level>;<classFile>` (prefix `DODSANNONS`) and posts the notice in guild chat 2 s later (same `/dodsannons gillet` setting). Everyone with the addon writes the same notice (seeded by name and level) and hides the guild copy. Extra lines at 10, 20, 30, 40, 50 and a special notice at max level. `/dodsannons nivå` turns them off both ways (checkbox in `/gpanel addons`).

### Fun extras (social)
- **Fotoalbum:** takes a screenshot (`Screenshot()`) on level-up, epic loot or a boss kill, and keeps a list with dates.
- **Svenska Spel:** a guild lottery. Members buy tickets with gold or tax credit; the leader draws a winner and the result is shared through addon messages. Works with Skatteverket and Swedbank.
- **/fika:** invites the guild to the inn you're at and shows the location to everyone. Anyone who joins sits down and drinks with emotes.
- **Emote replies:** /hug someone back automatically when they /hug you. Prepared "grattis" messages when a guild member levels up.

## Ideas mentioned but not chosen

**Guild:** Försäkringskassan (repair and death insurance paid from tax), Kronofogden (collects overdue Swedbank loans), SMHI (world-buff timers), Folkbokföring (links mains and alts), SJ (flight timer), Systembolaget (consumables check).

**Interface:** square minimap with a button drawer, unit frames (class colors, real health numbers, draggable), tooltips (cursor anchor, guild rank, "taught by guildmate").

**Automation:** vendor restocking (reagents, ammo, food, water), gear sets, auto-greed and mail helpers, auto-accepting guild invites and declining duels, double-click fishing.

**Dropped:** Riksdagen (guild votes): Skatteverket's Folkvald representant already holds elections.

**Other non-guild ideas:** vendor prices in tooltips, map coordinates, quest XP in the quest log, XP/hour tracker, gold/hour tracker, death recap, rare spawn alert, swing timer, enemy cast bars, reagent and ammo counter.

## Testing
Claude can't run the game. Install the addon, `/reload` in game, and report errors. Turning on `/console scriptErrors 1` shows Lua errors as they happen.
