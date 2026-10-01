class_name MapGen
extends RefCounted
## Procedural map: noise terrain, fair capital placement, villages,
## resources, ruins and bandit camps. The result is stored in the save,
## so it never has to be regenerated identically on another device.


static func generate(gs: GameState, rng: RandomNumberGenerator) -> void:
	for attempt in 12:
		_terrain(gs, rng)
		if _place_towns(gs, rng, 4 if attempt < 8 else 2):
			break
	_features(gs, rng)


static func _terrain(gs: GameState, rng: RandomNumberGenerator) -> void:
	var n := gs.w * gs.h
	gs.terrain.resize(n)
	gs.feature.resize(n)
	gs.building.resize(n)
	gs.bhp.resize(n)
	gs.road.resize(n)
	gs.claim.resize(n)
	gs.feature.fill(0)
	gs.building.fill(0)
	gs.bhp.fill(0)
	gs.road.fill(0)
	gs.claim.fill(0)
	gs.towns.clear()
	gs.units.clear()

	var elev := FastNoiseLite.new()
	elev.seed = rng.randi()
	elev.frequency = 0.11
	elev.fractal_octaves = 3
	var wet := FastNoiseLite.new()
	wet.seed = rng.randi()
	wet.frequency = 0.16
	var heights: Array[float] = []
	var cx := (gs.w - 1) / 2.0
	var cy := (gs.h - 1) / 2.0
	for i in n:
		var c := i % gs.w
		var r := i / gs.w
		var e := elev.get_noise_2d(c * 1.0 + 0.5 * (r & 1), r * 0.87)
		# gentle falloff toward the map edge, so the coast frames the land
		var dx := (c - cx) / (gs.w * 0.5)
		var dy := (r - cy) / (gs.h * 0.5)
		var edge := maxf(absf(dx), absf(dy))
		e -= maxf(0.0, edge - 0.72) * 1.6
		heights.append(e)
	var sorted := heights.duplicate()
	sorted.sort()
	var water_cut: float = sorted[int(n * 0.2)]
	var mountain_cut: float = sorted[int(n * 0.94)]
	var hill_cut: float = sorted[int(n * 0.78)]
	for i in n:
		var e: float = heights[i]
		var c := i % gs.w
		var r := i / gs.w
		var m := wet.get_noise_2d(c * 1.0, r * 1.0)
		if e < water_cut:
			gs.terrain[i] = Defs.T.WATER
		elif e > mountain_cut:
			gs.terrain[i] = Defs.T.MOUNTAIN
		elif e > hill_cut:
			gs.terrain[i] = Defs.T.HILLS
		elif m > 0.12:
			gs.terrain[i] = Defs.T.FOREST
		else:
			gs.terrain[i] = Defs.T.PLAINS


static func _main_land(gs: GameState) -> Dictionary:
	## Largest connected set of walkable tiles.
	var n := gs.w * gs.h
	var comp := {}
	var best := {}
	for i in n:
		if comp.has(i) or not _walkable(gs, i):
			continue
		var cur := { i: true }
		comp[i] = true
		var stack: Array[int] = [i]
		while not stack.is_empty():
			var a: int = stack.pop_back()
			for b in gs.neighbors(a):
				if not comp.has(b) and _walkable(gs, b):
					comp[b] = true
					cur[b] = true
					stack.append(b)
		if cur.size() > best.size():
			best = cur
	return best


static func _walkable(gs: GameState, i: int) -> bool:
	var t := gs.terrain[i]
	return t != Defs.T.WATER and t != Defs.T.MOUNTAIN


static func _place_towns(gs: GameState, rng: RandomNumberGenerator, min_gap: int) -> bool:
	var land := _main_land(gs)
	var n := gs.w * gs.h
	if land.size() < n * (0.45 if min_gap > 2 else 0.2):
		return false
	var np := gs.players.size()
	var cands: Array[int] = []
	for i in land:
		var cr := gs.col_row(i)
		if cr.x >= 1 and cr.y >= 1 and cr.x < gs.w - 1 and cr.y < gs.h - 1:
			cands.append(i)
	if cands.size() < np * 4:
		return false
	# Capitals: maximise the minimum distance between them (best of many tries).
	var best: Array[int] = []
	var best_score := -1
	for t in 300:
		var pick: Array[int] = []
		for p in np:
			pick.append(cands[rng.randi_range(0, cands.size() - 1)])
		var md := 999
		for a in np:
			for b in range(a + 1, np):
				md = mini(md, gs.dist(pick[a], pick[b]))
		# also prefer capitals away from the absolute edge
		if md > best_score:
			best_score = md
			best = pick
	if best_score < min_gap:
		return false
	for p in np:
		var idx := best[p]
		_add_town(gs, idx, p, true, rng)
		# make the capital's surroundings fair: walkable land with something useful
		var ring := gs.neighbors(idx)
		for j in ring:
			if not _walkable(gs, j):
				gs.terrain[j] = Defs.T.PLAINS
		gs.terrain[idx] = Defs.T.PLAINS
		var kinds := [Defs.T.FOREST, Defs.T.PLAINS, Defs.T.HILLS]
		for k in kinds.size():
			if k < ring.size():
				var has_kind := false
				for j in ring:
					if gs.terrain[j] == kinds[k]:
						has_kind = true
				if not has_kind:
					gs.terrain[ring[(k * 2 + p) % ring.size()]] = kinds[k]
	# Villages scattered over the main land.
	land = _main_land(gs)
	var target := int(n / 22.0) + np
	var shuffled: Array = land.keys()
	_shuffle(shuffled, rng)
	for i in shuffled:
		if gs.towns.size() >= target + np:
			break
		if gs.terrain[i] == Defs.T.MOUNTAIN or gs.terrain[i] == Defs.T.WATER:
			continue
		var ok := true
		for t in gs.towns:
			if gs.dist(t.idx, i) < 3:
				ok = false
				break
		if ok:
			_add_town(gs, i, -1, false, rng)
	return true


static func _add_town(gs: GameState, idx: int, owner: int, capital: bool, rng: RandomNumberGenerator) -> void:
	var t := GameState.Town.new()
	t.idx = idx
	t.owner = owner
	t.capital = capital
	t.level = 1
	var used := {}
	for o in gs.towns:
		used[o.name] = true
	var name := ""
	for k in 50:
		name = Defs.TOWN_NAMES[rng.randi_range(0, Defs.TOWN_NAMES.size() - 1)]
		if not used.has(name):
			break
	t.name = name
	gs.towns.append(t)
	if gs.terrain[idx] == Defs.T.MOUNTAIN or gs.terrain[idx] == Defs.T.WATER:
		gs.terrain[idx] = Defs.T.PLAINS


static func _features(gs: GameState, rng: RandomNumberGenerator) -> void:
	var n := gs.w * gs.h
	var town_tiles := {}
	for t in gs.towns:
		town_tiles[t.idx] = true
	for i in n:
		if town_tiles.has(i):
			continue
		var r := rng.randf()
		match gs.terrain[i]:
			Defs.T.PLAINS:
				if r < 0.22:
					gs.feature[i] = Defs.F.FERTILE
			Defs.T.FOREST:
				if r < 0.22:
					gs.feature[i] = Defs.F.OLD_GROWTH
			Defs.T.HILLS:
				if r < 0.3:
					gs.feature[i] = Defs.F.STONE
				elif r < 0.5:
					gs.feature[i] = Defs.F.GOLD
			Defs.T.MOUNTAIN:
				if r < 0.25:
					gs.feature[i] = Defs.F.GOLD
	# Ruins and bandit camps, kept away from capitals.
	var land := _main_land(gs)
	var spots: Array = land.keys()
	_shuffle(spots, rng)
	var ruins := maxi(2, int(n / 40.0))
	var camps := maxi(1, int(n / 55.0))
	var placed: Array[int] = []
	for i in spots:
		if ruins <= 0 and camps <= 0:
			break
		if town_tiles.has(i):
			continue
		var near_cap := 99
		var near_town := 99
		for t in gs.towns:
			var d := gs.dist(t.idx, i)
			near_town = mini(near_town, d)
			if t.capital:
				near_cap = mini(near_cap, d)
		var crowded := false
		for o in placed:
			if gs.dist(o, i) < 3:
				crowded = true
		if crowded or near_town < 2:
			continue
		if camps > 0 and near_cap >= 4:
			gs.feature[i] = Defs.F.CAMP
			gs.spawn_unit(Defs.U.BANDIT, i, -1)
			camps -= 1
			placed.append(i)
		elif ruins > 0 and near_cap >= 3:
			gs.feature[i] = Defs.F.RUIN
			ruins -= 1
			placed.append(i)


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
