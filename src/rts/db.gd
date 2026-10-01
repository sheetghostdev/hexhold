class_name DB
extends RefCounted
## Loads every data file under res://data once. Balancing = editing .tres files.

static var units := {}       # id -> UnitDef
static var buildings := {}   # id -> BuildingDef
static var obstacles := {}   # id -> ObstacleDef
static var upgrades := {}    # id -> UpgradeDef
static var obstacle_ids: Array[String] = []  # index + 1 is stored on the map
static var rules: RulesDef
static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	for r in _load_dir("res://data/units"):
		units[r.id] = r
	for r in _load_dir("res://data/buildings"):
		buildings[r.id] = r
	for r in _load_dir("res://data/obstacles"):
		obstacles[r.id] = r
	for r in _load_dir("res://data/upgrades"):
		upgrades[r.id] = r
	obstacle_ids.assign(obstacles.keys())
	obstacle_ids.sort()
	rules = load("res://data/rules.tres")


static func _load_dir(path: String) -> Array:
	var out := []
	var files: PackedStringArray = ResourceLoader.list_directory(path)
	for f in files:
		var name := f.trim_suffix(".remap")
		if name.ends_with(".tres") or name.ends_with(".res"):
			var r = load(path + "/" + name)
			if r != null:
				out.append(r)
	return out


static func unit(id: String) -> UnitDef:
	load_all()
	return units.get(id)


static func building(id: String) -> BuildingDef:
	load_all()
	return buildings.get(id)


static func obstacle_at(index: int) -> ObstacleDef:
	load_all()
	if index <= 0 or index > obstacle_ids.size():
		return null
	return obstacles[obstacle_ids[index - 1]]


static func obstacle_index(id: String) -> int:
	load_all()
	return obstacle_ids.find(id) + 1


static func sorted_units() -> Array:
	load_all()
	var arr := units.values()
	arr.sort_custom(func(a, b): return a.sort < b.sort)
	return arr


static func sorted_buildings() -> Array:
	load_all()
	var arr := buildings.values()
	arr.sort_custom(func(a, b): return a.sort < b.sort)
	return arr


static func upgrade(id: String) -> UpgradeDef:
	load_all()
	return upgrades.get(id)


static func sorted_upgrades() -> Array:
	load_all()
	var arr := upgrades.values()
	arr.sort_custom(func(a, b): return a.sort < b.sort)
	return arr
