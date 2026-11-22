-- Lantmäteriet: the gathering nodes it knows, by the name the game gives
-- them (an English client), with the skill they need. Names it doesn't
-- know are learned from the game's tooltip when you hover one
-- ("Requires Herbalism (150)"), into LantmaterietDB.learned.

local _, ns = ...

ns.HERB, ns.ORE = "herb", "ore"

-- Skill lines (GetProfessionInfo's 7th value).
ns.SKILL_LINE = { herb = 182, ore = 186 }

local HERBS = {
	["Peacebloom"] = 1, ["Silverleaf"] = 1, ["Earthroot"] = 15, ["Mageroyal"] = 50,
	["Briarthorn"] = 70, ["Stranglekelp"] = 85, ["Bruiseweed"] = 100, ["Wild Steelbloom"] = 115,
	["Grave Moss"] = 120, ["Kingsblood"] = 125, ["Liferoot"] = 150, ["Fadeleaf"] = 160,
	["Goldthorn"] = 170, ["Khadgar's Whisker"] = 185, ["Wintersbite"] = 195, ["Firebloom"] = 205,
	["Purple Lotus"] = 210, ["Arthas' Tears"] = 220, ["Sungrass"] = 230, ["Blindweed"] = 235,
	["Ghost Mushroom"] = 245, ["Gromsblood"] = 250, ["Golden Sansam"] = 260, ["Dreamfoil"] = 270,
	["Mountain Silversage"] = 280, ["Plaguebloom"] = 285, ["Icecap"] = 290, ["Bloodvine"] = 300,
	["Black Lotus"] = 300,
}

local ORES = {
	["Copper Vein"] = 1, ["Tin Vein"] = 65, ["Incendicite Mineral Vein"] = 65,
	["Silver Vein"] = 75, ["Ooze Covered Silver Vein"] = 75, ["Lesser Bloodstone Deposit"] = 75,
	["Iron Deposit"] = 125, ["Indurium Mineral Vein"] = 150, ["Gold Vein"] = 155,
	["Ooze Covered Gold Vein"] = 155, ["Mithril Deposit"] = 175, ["Ooze Covered Mithril Deposit"] = 175,
	["Truesilver Deposit"] = 230, ["Ooze Covered Truesilver Deposit"] = 230, ["Dark Iron Deposit"] = 230,
	["Small Thorium Vein"] = 245, ["Ooze Covered Thorium Vein"] = 245, ["Rich Thorium Vein"] = 275,
	["Ooze Covered Rich Thorium Vein"] = 275, ["Hakkari Thorium Vein"] = 275,
	["Small Obsidian Chunk"] = 305, ["Large Obsidian Chunk"] = 305,
}

-- kind, skill for a node name, or nil when it isn't a known node.
function ns.NodeInfo(name)
	if type(name) ~= "string" then return end
	if HERBS[name] then return ns.HERB, HERBS[name] end
	if ORES[name] then return ns.ORE, ORES[name] end
	local learned = ns.db and ns.db.learned and ns.db.learned[name]
	if learned then return learned.kind, learned.skill end
end

-- Map pin icons by kind.
ns.ICON = {
	herb = "Interface\\Icons\\INV_Misc_Flower_02",
	ore = "Interface\\Icons\\INV_Ore_Copper_01",
}

-- The glow's color by kind when you can gather it.
ns.KIND_COLOR = {
	herb = { 0.3, 1, 0.3 },
	ore = { 1, 0.6, 0.2 },
}
