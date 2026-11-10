"""Builds Kolapp/Data.lua (quest chains) and Kolapp/ItemData.lua (which quests
each item belongs to) from Questie's Classic quest database.

Usage:
    pip install lupa
    python tools/kolapp_data.py <download dir>

Downloads Questie's Classic quest data, its quest fixes and its blacklist
(tag below) into <download dir>, runs them in a sandboxed Lua 5.1 with the
Questie modules they need stubbed out, and writes Kolapp/Data.lua and
Kolapp/ItemData.lua.

Questie (https://github.com/Questie/Questie) is GPLv3; the chain data in
Data.lua is derived from it.
"""

import os
import sys
import urllib.request

import lupa.lua51 as lua51

TAG = "v11.38.0"  # the last tag that still ships the Classic quest database
FILES = {
    "classicQuestDB.lua": "Database/Classic/classicQuestDB.lua",
    "classicQuestFixes.lua": "Database/Corrections/classicQuestFixes.lua",
    "QuestieQuestBlacklist.lua": "Database/Corrections/QuestieQuestBlacklist.lua",
    "classicItemDB.lua": "Database/Classic/classicItemDB.lua",
}
QUEST_ITEM_CLASS = 12
CLASSES = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"]

# Stubs for the parts of Questie the data files touch. Unknown module fields
# become a "whatever" value that can be indexed, called and added to, so
# fixes we don't care about (zones, NPCs, professions) load without errors.
STUBS = r"""
local whatever
whatever = setmetatable({}, {
    __index = function() return whatever end,
    __newindex = function() end,
    __call = function() return whatever end,
    __add = function() return whatever end,
    __sub = function() return whatever end,
    __unm = function() return whatever end,
    __concat = function() return "" end,
})
WHATEVER = whatever

local modules = {}
local function module(name)
    if not modules[name] then
        modules[name] = setmetatable({}, {
            __index = function() return whatever end,
            __call = function(_, text) return text end, -- l10n("text")
        })
    end
    return modules[name]
end
QuestieLoader = {
    CreateModule = function(_, name) return module(name) end,
    ImportModule = function(_, name) return module(name) end,
}
Questie = { IsClassic = true }
setmetatable(Questie, { __index = function(_, k)
    if k == "Debug" then return function() end end
    return false
end })

local Expansions = module("Expansions")
Expansions.Era, Expansions.Tbc, Expansions.Wotlk, Expansions.Cata, Expansions.MoP = 1, 2, 3, 4, 5
Expansions.Current = 1

local DB = module("QuestieDB")
DB.raceKeys = setmetatable({
    ALL_ALLIANCE = 77, ALL_HORDE = 178, NONE = 0,
    HUMAN = 1, ORC = 2, DWARF = 4, NIGHT_ELF = 8, UNDEAD = 16, TAUREN = 32, GNOME = 64, TROLL = 128,
}, { __index = function(_, k) error("unknown race key " .. tostring(k)) end })
DB.classKeys = setmetatable({
    ALL_CLASSES = 1503, NONE = 0, WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}, { __index = function(_, k) error("unknown class key " .. tostring(k)) end })
DB.specialFlags = { NONE = 0, REPEATABLE = 1 }

FACTION, CLASS = "Alliance", "WARRIOR"
function UnitFactionGroup() return FACTION end
function UnitClassBase() return CLASS end
"""


def download(directory):
    os.makedirs(directory, exist_ok=True)
    for name, path in FILES.items():
        target = os.path.join(directory, name)
        if not os.path.exists(target):
            url = f"https://raw.githubusercontent.com/Questie/Questie/{TAG}/{path}"
            print("downloading", url)
            urllib.request.urlretrieve(url, target)


def run(lua, directory, name):
    with open(os.path.join(directory, name), "rb") as f:
        src = f.read()
    result = lua.globals().loadstring(src, name)
    if isinstance(result, tuple):  # (nil, error)
        sys.exit(f"{name}: {result[1]}")
    result()


def to_list(value):
    if value is None or lua51.lua_type(value) != "table":
        return []
    return [int(v) for v in value.values() if isinstance(v, (int, float))]


def to_int(value):
    return int(value) if isinstance(value, (int, float)) else 0


def rows(value):
    """A Lua array as a Python list (nils skipped)."""
    if value is None or lua51.lua_type(value) != "table":
        return []
    return [v for _, v in sorted(value.items(), key=lambda kv: kv[0])]


def first_int(value):
    """The first number in a Lua row like {item, text, icon}."""
    if isinstance(value, (int, float)):
        return int(value)
    if value is not None and lua51.lua_type(value) == "table":
        v = value[1]
        if isinstance(v, (int, float)):
            return int(v)
    return 0


def quest_items(row, K):
    """(items the quest needs or hands out, items that start it)."""
    needs = set()
    objectives = row.get(K["objectives"])
    if objectives is not None and lua51.lua_type(objectives) == "table":
        for entry in rows(objectives[3]):  # itemObjective
            needs.add(first_int(entry))
        for entry in rows(objectives[6]):  # spellObjective: {spell, text, item}
            if lua51.lua_type(entry) == "table" and isinstance(entry[3], (int, float)):
                needs.add(int(entry[3]))
    needs.add(to_int(row.get(K["sourceItemId"])))
    needs.update(to_list(row.get(K["requiredSourceItems"])))
    starts = set()
    started_by = row.get(K["startedBy"])
    if started_by is not None and lua51.lua_type(started_by) == "table":
        starts.update(to_list(started_by[3]))  # {creatures, objects, items}
    needs.discard(0)
    starts.discard(0)
    return needs, starts


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    directory = sys.argv[1]
    download(directory)

    lua = lua51.LuaRuntime(encoding="utf-8", register_eval=False, register_builtins=False)
    g = lua.globals()
    for unsafe in ("io", "os", "require", "dofile", "loadfile", "package", "python"):
        g[unsafe] = None
    lua.execute(STUBS)

    run(lua, directory, "classicQuestDB.lua")
    loader = lua.eval("QuestieLoader")
    DB = loader.ImportModule(loader, "QuestieDB")
    keys = {k: int(v) for k, v in DB.questKeys.items()}
    data = g.loadstring(DB.questData)()

    run(lua, directory, "classicQuestFixes.lua")
    run(lua, directory, "QuestieQuestBlacklist.lua")
    Fixes = loader.ImportModule(loader, "QuestieQuestFixes")
    Blacklist = loader.ImportModule(loader, "QuestieQuestBlacklist")

    quests = {}  # id -> dict

    def apply(fixes, target):
        for qid, fix in fixes.items():
            q = target.setdefault(int(qid), {})
            for k, v in fix.items():
                q[int(k)] = v

    raw = {}
    for qid, row in data.items():
        raw[int(qid)] = {int(k): v for k, v in row.items()}
    apply(Fixes.Load(Fixes), raw)

    blacklisted = {int(q) for q, v in Blacklist.Load(Blacklist).items() if v is True}

    K = keys
    item_needs, item_starts, item_quest = {}, {}, {}  # item -> quests; quest -> (name, races)
    for qid, row in raw.items():
        if qid in blacklisted or row.get(K["name"]) is None:
            continue
        needs, starts = quest_items(row, K)
        for item in needs:
            item_needs.setdefault(item, set()).add(qid)
        for item in starts:
            item_starts.setdefault(item, set()).add(qid)
        if needs or starts:
            item_quest[qid] = (row[K["name"]], to_int(row.get(K["requiredRaces"])))

        if to_int(row.get(K["specialFlags"])) & 1:  # repeatable
            continue
        quests[qid] = {
            "name": row[K["name"]],
            "races": to_int(row.get(K["requiredRaces"])),
            "classes": to_int(row.get(K["requiredClasses"])),
            "pre": set(to_list(row.get(K["preQuestGroup"])) + to_list(row.get(K["preQuestSingle"]))),
            "next": to_int(row.get(K["nextQuestInChain"])),
        }

    # The item database adds quests an item is related to or starts, and
    # which quests reward a quest item (like Bethor's Potion, which no quest
    # needs afterwards).
    run(lua, directory, "classicItemDB.lua")
    IK = {k: int(v) for k, v in DB.itemKeys.items()}
    item_rewards = {}

    def note(qid, table, item):
        row = raw.get(qid)
        if qid in blacklisted or not row or row.get(K["name"]) is None:
            return
        table.setdefault(item, set()).add(qid)
        item_quest[qid] = (row[K["name"]], to_int(row.get(K["requiredRaces"])))

    for item, row in g.loadstring(DB.itemData)().items():
        item = int(item)
        for qid in to_list(row[IK["relatedQuests"]]):
            note(qid, item_needs, item)
        if to_int(row[IK["startQuest"]]):
            note(to_int(row[IK["startQuest"]]), item_starts, item)
        if to_int(row[IK["class"]]) == QUEST_ITEM_CLASS and item not in item_needs:
            for qid in to_list(row[IK["questRewards"]]):
                note(qid, item_rewards, item)

    # Per faction: the faction (and per class) fixes only change next-quest
    # links. Adding every class's and race's links is fine because the addon
    # drops quests the player's race or class can't take.
    def succ_for(faction):
        succ = {}

        def link(a, b):
            if a in quests and b in quests and a != b:
                succ.setdefault(a, set()).add(b)

        nexts = {qid: {q["next"]} for qid, q in quests.items() if q["next"]}
        for cls in CLASSES:
            g["FACTION"], g["CLASS"] = faction, cls
            for qid, fix in Fixes.LoadFactionFixes(Fixes).items():
                v = fix[K["nextQuestInChain"]]
                if v is not None and int(qid) in quests:
                    n = to_int(v)
                    nexts.setdefault(int(qid), set())
                    if n == 0:
                        nexts[int(qid)].discard(quests[int(qid)]["next"])
                    else:
                        nexts[int(qid)].add(n)
        for qid, q in quests.items():
            for p in q["pre"]:
                link(p, qid)
            for n in nexts.get(qid, ()):
                link(qid, n)
        return succ

    sa, sh = succ_for("Alliance"), succ_for("Horde")
    in_chain = set(sa) | set(sh)
    for s in list(sa.values()) + list(sh.values()):
        in_chain |= s

    def lua_list(ids):
        return "{" + ",".join(str(i) for i in sorted(ids)) + "}"

    def lua_string(s):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

    lines = []
    for qid in sorted(in_chain):
        q = quests[qid]
        a, h = sa.get(qid, set()), sh.get(qid, set())
        both = a & h
        fields = [lua_string(q["name"]), str(q["races"]), str(q["classes"]), lua_list(both)]
        if a - both or h - both:
            fields += [lua_list(a - both), lua_list(h - both)]
        lines.append(f"[{qid}]={{{','.join(fields)}}},")

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Kolapp", "Data.lua")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- Generated by tools/kolapp_data.py from Questie {TAG} (GPLv3,\n")
        f.write("-- https://github.com/Questie/Questie). Don't edit by hand.\n")
        f.write("-- [questID] = {name, required races, required classes (0 = any),\n")
        f.write("--   next quests, [Alliance-only next quests, Horde-only next quests]}\n")
        f.write("local _, ns = ...\n")
        f.write("ns.quests = {\n")
        f.write("\n".join(lines))
        f.write("\n}\n")
    print(f"{len(lines)} quests in chains -> {os.path.normpath(out)}")

    out = os.path.join(os.path.dirname(out), "ItemData.lua")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- Generated by tools/kolapp_data.py from Questie {TAG} (GPLv3,\n")
        f.write("-- https://github.com/Questie/Questie). Don't edit by hand.\n")
        f.write("-- ns.itemNeeds[itemID] = quests that collect, use or hand out the item\n")
        f.write("-- ns.itemStarts[itemID] = quests the item starts\n")
        f.write("-- ns.itemRewards[itemID] = quests that reward the (quest) item\n")
        f.write("-- ns.itemQuests[questID] = {name, required races (0 = any)}\n")
        f.write("local _, ns = ...\n")
        for name, table in (("itemNeeds", item_needs), ("itemStarts", item_starts), ("itemRewards", item_rewards)):
            f.write(f"ns.{name} = {{\n")
            f.write("\n".join(f"[{i}]={lua_list(table[i])}," for i in sorted(table)))
            f.write("\n}\n")
        f.write("ns.itemQuests = {\n")
        f.write("\n".join(f"[{q}]={{{lua_string(n)},{r}}}," for q, (n, r) in sorted(item_quest.items())))
        f.write("\n}\n")
    print(f"{len(item_needs)} items needed, {len(item_starts)} starting quests, "
          f"{len(item_rewards)} quest item rewards -> {os.path.normpath(out)}")


if __name__ == "__main__":
    main()
