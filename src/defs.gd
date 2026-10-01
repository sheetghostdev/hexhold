class_name Defs
extends RefCounted
## Static game data. Everything costs gold; towns grow from people.

enum T { WATER, PLAINS, FOREST, HILLS, MOUNTAIN }
enum F { NONE, FERTILE, OLD_GROWTH, STONE, GOLD, RUIN, CAMP }
enum B { NONE, FARM, LUMBER, QUARRY, MINE, MARKET, WALL, TOWER }
enum U { SPEARMAN, ARCHER, SWORDSMAN, KNIGHT, CATAPULT, BANDIT, CHAMPION }

const TERRAIN_NAMES := ["Water", "Plains", "Forest", "Hills", "Mountains"]
const FEATURE_NAMES := ["", "Fertile soil", "Old forest", "Ore vein", "Gold vein", "Ancient ruins", "Bandit camp"]

const UNITS := [
	{ "name": "Spearman", "hp": 10, "atk": 2.0, "def": 2.0, "move": 2, "range": 1, "cost": 3, "keep": 1,
		"role": "Cheap defender. Double defence against knights." },
	{ "name": "Archer", "hp": 10, "atk": 2.0, "def": 1.0, "move": 2, "range": 2, "cost": 4, "keep": 1,
		"role": "Shoots 2 tiles away. 3 tiles from a wall or tower." },
	{ "name": "Swordsman", "hp": 15, "atk": 3.0, "def": 3.0, "move": 1, "range": 1, "cost": 6, "keep": 2,
		"role": "Tough front-line fighter." },
	{ "name": "Knight", "hp": 15, "atk": 3.5, "def": 1.0, "move": 3, "range": 1, "cost": 7, "keep": 2,
		"role": "Fast. Can attack first and still move after." },
	{ "name": "Catapult", "hp": 10, "atk": 4.0, "def": 0.0, "move": 1, "range": 3, "cost": 8, "keep": 3,
		"role": "Hits from 3 tiles, ignores walls, wrecks buildings." },
	{ "name": "Bandit", "hp": 10, "atk": 2.0, "def": 2.0, "move": 0, "range": 1, "cost": 0, "keep": 99,
		"role": "Guards its camp and ambushes anyone nearby." },
	{ "name": "Champion", "hp": 30, "atk": 4.5, "def": 4.0, "move": 2, "range": 1, "cost": 0, "keep": 99,
		"role": "A legendary hero. Only from a town reward." },
]
const TRAINABLE := [U.SPEARMAN, U.ARCHER, U.SWORDSMAN, U.KNIGHT, U.CATAPULT]

## pop: people added to the owning town ("rich" tiles add one more).
const BUILDINGS := [
	{ "name": "", "cost": 0 },
	{ "name": "Farm", "cost": 3, "pop": 1, "terrain": [T.PLAINS], "rich": F.FERTILE, "keep": 1 },
	{ "name": "Lumber Hut", "cost": 2, "pop": 1, "terrain": [T.FOREST], "rich": F.OLD_GROWTH, "keep": 1 },
	{ "name": "Quarry", "cost": 0, "pop": 0, "terrain": [], "keep": 99 },  # retired (kept for save layout)
	{ "name": "Mine", "cost": 5, "pop": 2, "terrain": [T.HILLS, T.MOUNTAIN], "rich": F.GOLD, "keep": 1 },
	{ "name": "Market", "cost": 6, "pop": 0, "terrain": [T.PLAINS, T.HILLS], "keep": 2 },
	{ "name": "Wall", "cost": 2, "pop": 0, "terrain": [T.PLAINS, T.FOREST, T.HILLS], "keep": 1, "hp": 10 },
	{ "name": "Tower", "cost": 6, "pop": 0, "terrain": [T.PLAINS, T.FOREST, T.HILLS], "keep": 2, "hp": 15 },
]
const BUILD_ORDER := [B.FARM, B.LUMBER, B.MINE, B.MARKET, B.WALL, B.TOWER]

const ROAD_COST := 1
const BRIDGE_COST := 3
const KEEP_COST := [0, 0, 10, 20]
const KEEP_NAMES := ["", "Wooden Keep", "Stone Keep", "Castle"]
const KEEP_UNLOCKS := ["", "Spearmen, archers, farms, huts, mines, walls", "Swordsmen, knights, markets, towers", "Catapults"]

const START_GOLD := 8
const MAX_TOWN_LEVEL := 8
const VETERAN_KILLS := 3
const VETERAN_BONUS_HP := 5
const TOWER_DAMAGE := 3
const TOWER_RANGE := 2
const CAMP_LOOT := 8

## Town level-up rewards: two choices per level (levels 5+ repeat the last pair).
enum R { WORKSHOP, EXPLORER, WALLS, TREASURE, BORDERS, BOOM, CHAMPION, GUILD }
const REWARDS := {
	R.WORKSHOP: { "name": "Workshop", "desc": "+1 gold every turn", "icon": "gold" },
	R.EXPLORER: { "name": "Scouts", "desc": "Reveal the land far around this town", "icon": "eye" },
	R.WALLS: { "name": "Town Walls", "desc": "Defenders here get triple defence", "icon": "walls" },
	R.TREASURE: { "name": "Treasure", "desc": "+8 gold right now", "icon": "chest" },
	R.BORDERS: { "name": "Bigger Borders", "desc": "Claim land 2 tiles out: more room to build", "icon": "border" },
	R.BOOM: { "name": "Baby Boom", "desc": "+3 people right away", "icon": "people" },
	R.CHAMPION: { "name": "Champion", "desc": "A free hero with 30 health", "icon": "champion" },
	R.GUILD: { "name": "Guild Hall", "desc": "+2 gold every turn", "icon": "gold" },
}
const LEVEL_REWARDS := { 2: [R.WORKSHOP, R.EXPLORER], 3: [R.WALLS, R.TREASURE], 4: [R.BORDERS, R.BOOM], 5: [R.CHAMPION, R.GUILD] }

const PLAYER_COLORS := [
	Color("#3d7be0"), Color("#e04848"), Color("#f2b632"), Color("#9b5de5"),
	Color("#20b2aa"), Color("#f07c32"),
]
const NEUTRAL_COLOR := Color("#9a9a9a")
const BANDIT_COLOR := Color("#4a3b33")

const MAP_SIZES := [
	{ "name": "Small", "w": 9, "h": 12 },
	{ "name": "Medium", "w": 11, "h": 15 },
	{ "name": "Large", "w": 14, "h": 19 },
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


static func rewards_for(level: int) -> Array:
	return LEVEL_REWARDS[mini(level, 5)] if level >= 2 else []


static func player_color(c: int) -> Color:
	if c < 0:
		return NEUTRAL_COLOR
	return PLAYER_COLORS[c % PLAYER_COLORS.size()]
