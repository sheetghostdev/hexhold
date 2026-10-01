class_name Defs
extends RefCounted
## Static game data: terrain, buildings, units, costs and colors.

enum T { WATER, PLAINS, FOREST, HILLS, MOUNTAIN }
enum F { NONE, FERTILE, OLD_GROWTH, STONE, GOLD, RUIN, CAMP }
enum B { NONE, FARM, LUMBER, QUARRY, MINE, MARKET, WALL, TOWER }
enum U { SPEARMAN, ARCHER, SWORDSMAN, KNIGHT, CATAPULT, BANDIT }
enum TAX { LOW, FAIR, HIGH }

## Resource indices used in cost arrays: [gold, wood, stone]
const GOLD := 0
const WOOD := 1
const STONE := 2

const TERRAIN_NAMES := ["Water", "Plains", "Forest", "Hills", "Mountains"]
const FEATURE_NAMES := ["", "Fertile soil", "Old-growth forest", "Stone vein", "Gold vein", "Ancient ruins", "Bandit camp"]

const UNITS := [
	{ "name": "Spearman", "hp": 10, "atk": 2.0, "def": 2.0, "move": 1, "range": 1, "cost": [3, 0, 0], "keep": 1,
		"desc": "Cheap and sturdy. Double defence against knights." },
	{ "name": "Archer", "hp": 10, "atk": 2.0, "def": 1.0, "move": 1, "range": 2, "cost": [3, 2, 0], "keep": 1,
		"desc": "Shoots 2 tiles. +1 range when standing on a wall or tower." },
	{ "name": "Swordsman", "hp": 15, "atk": 3.0, "def": 3.0, "move": 1, "range": 1, "cost": [6, 0, 1], "keep": 2,
		"desc": "Heavy infantry. Hits hard, holds the line." },
	{ "name": "Knight", "hp": 15, "atk": 3.5, "def": 1.0, "move": 3, "range": 1, "cost": [8, 0, 0], "keep": 2,
		"desc": "Fast cavalry. Gallops 3 tiles, 6 on roads." },
	{ "name": "Catapult", "hp": 10, "atk": 4.0, "def": 0.0, "move": 1, "range": 3, "cost": [8, 4, 0], "keep": 3,
		"desc": "Range 3. Ignores walls and smashes structures. Can't move and fire in one turn." },
	{ "name": "Bandit", "hp": 10, "atk": 2.0, "def": 2.0, "move": 0, "range": 1, "cost": [0, 0, 0], "keep": 99,
		"desc": "Guards its camp and ambushes anyone who comes close." },
]

## terrain: allowed terrain list; feature: required feature (-1 = any non-blocking)
const BUILDINGS := [
	{ "name": "", "cost": [0, 0, 0] },
	{ "name": "Farm", "cost": [0, 2, 0], "terrain": [T.PLAINS], "keep": 1,
		"desc": "+2 food for the town (+1 on fertile soil). Food grows towns." },
	{ "name": "Lumber Camp", "cost": [2, 0, 0], "terrain": [T.FOREST], "keep": 1,
		"desc": "+2 wood per turn (+1 in old-growth forest)." },
	{ "name": "Quarry", "cost": [2, 2, 0], "terrain": [T.HILLS], "keep": 1,
		"desc": "+2 stone per turn (+1 on a stone vein)." },
	{ "name": "Gold Mine", "cost": [4, 3, 0], "terrain": [T.HILLS, T.MOUNTAIN], "feature": F.GOLD, "keep": 1,
		"desc": "+2 gold per turn. Needs a gold vein." },
	{ "name": "Market", "cost": [0, 5, 3], "terrain": [T.PLAINS, T.HILLS], "keep": 2,
		"desc": "+1 gold for every farm, camp, quarry or mine next to it (max 4)." },
	{ "name": "Wall", "cost": [0, 0, 2], "terrain": [T.PLAINS, T.FOREST, T.HILLS], "keep": 1, "hp": 10,
		"desc": "Blocks enemies. Your troops can stand on it for double defence." },
	{ "name": "Tower", "cost": [0, 3, 4], "terrain": [T.PLAINS, T.FOREST, T.HILLS], "keep": 2, "hp": 15,
		"desc": "Blocks enemies and shoots one within 2 tiles (3 dmg) every turn." },
]

const ROAD_COST := [0, 1, 0]
const BRIDGE_COST := [0, 3, 1]
const TOWN_WALL_COST := [0, 0, 5]
const KEEP_COST := [[0, 0, 0], [0, 0, 0], [8, 0, 6], [15, 0, 12]]
const KEEP_NAMES := ["", "Wooden Keep", "Stone Keep", "Castle"]

const START_GOLD := 6
const START_WOOD := 4
const START_STONE := 0
const MAX_TOWN_LEVEL := 5
const VETERAN_KILLS := 3
const VETERAN_BONUS_HP := 5
const TOWER_DAMAGE := 3
const TOWER_RANGE := 2
const CAMP_LOOT := 6
const UNIT_UPKEEP := 1
const FEAST_FOOD := 3

const TAX_NAMES := ["Generous", "Fair", "Harsh"]
const TAX_DESC := [
	"Half gold from towns, +1 food in every town.",
	"Normal gold and food.",
	"+50% gold from towns, -1 food in every town.",
]

const PLAYER_COLORS := [
	Color("#3d7be0"), Color("#e04848"), Color("#f2b632"), Color("#9b5de5"),
	Color("#20b2aa"), Color("#f07c32"),
]
const PLAYER_COLOR_NAMES := ["Blue", "Red", "Gold", "Violet", "Teal", "Orange"]
const NEUTRAL_COLOR := Color("#9a9a9a")
const BANDIT_COLOR := Color("#4a3b33")

const MAP_SIZES := [
	{ "name": "Small", "w": 9, "h": 13 },
	{ "name": "Medium", "w": 11, "h": 16 },
	{ "name": "Large", "w": 14, "h": 20 },
]

const TOWN_NAMES := [
	"Oakvale", "Ashford", "Brightwater", "Stonebridge", "Elmstead", "Ravenhold",
	"Thornbury", "Willowmere", "Highcliff", "Mossbank", "Redhill", "Foxden",
	"Coldbrook", "Ironwood", "Greenholm", "Kingsfall", "Marrowgate", "Duskmoor",
	"Amberley", "Hollowell", "Larkspur", "Northwatch", "Pinecrest", "Saltmarsh",
	"Tamworth", "Wyvernrest", "Barrowby", "Cinderfell", "Dunmore", "Eastmarch",
	"Goldmere", "Heathrow", "Lindenfield", "Oxbury", "Rookhaven", "Silverlea",
]


static func unit_max_hp(type: int, kills: int) -> int:
	var hp: int = UNITS[type]["hp"]
	if kills >= VETERAN_KILLS:
		hp += VETERAN_BONUS_HP
	return hp


static func cost_text(cost: Array) -> String:
	var parts: Array[String] = []
	if cost[GOLD] > 0:
		parts.append("%d gold" % cost[GOLD])
	if cost[WOOD] > 0:
		parts.append("%d wood" % cost[WOOD])
	if cost[STONE] > 0:
		parts.append("%d stone" % cost[STONE])
	if parts.is_empty():
		return "free"
	return ", ".join(parts)


static func player_color(c: int) -> Color:
	if c < 0:
		return NEUTRAL_COLOR
	return PLAYER_COLORS[c % PLAYER_COLORS.size()]
