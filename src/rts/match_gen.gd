class_name MatchGen
extends RefCounted
## Builds a new 1v1 match: a small hexagon map, mirror-symmetric so both
## sides are equally fair, with trees, rocks and a few ponds, plus each
## player's starting base.


## setup: {players: [{name, color, ai}], seed}
static func create(setup: Dictionary) -> MatchState:
	DB.load_all()
	var m := MatchState.new()
	m.map_seed = int(setup.get("seed", randi() % 1000000))
	var rng := RandomNumberGenerator.new()
	rng.seed = m.map_seed
	const ALPHA := "abcdefghjkmnpqrstuvwxyz23456789"
	for i in 6:
		m.match_id += ALPHA[rng.randi_range(0, ALPHA.length() - 1)]
	m.radius = DB.rules.map_radius
	_shape(m)
	for ps in setup["players"]:
		var pl := MatchState.PlayerState.new()
		pl.name = ps["name"]
		pl.color = ps.get("color", 0)
		pl.ai = ps.get("ai", false)
		pl.alloy = DB.rules.start_alloy
		pl.fuel = DB.rules.start_fuel
		pl.explored.resize(m.n_tiles())
		m.players.append(pl)
	_terrain(m, rng)
	_bases(m)
	m.look_seed = rng.randi() % 1000000
	m.rebuild_caches()
	for p in m.players.size():
		m.update_explored(p)
	m._event(-1, "turn", [], { "player": 0 })
	m._start_turn(0)
	return m


## A hexagon of the given radius stored in a w x h offset grid.
static func _shape(m: MatchState) -> void:
	var r := m.radius
	var c_off := Vector2i(r + 2, r)
	var c_ax := Hex.offset_to_axial(c_off.x, c_off.y)
	var cells: Array[Vector2i] = []
	for dq in range(-r, r + 1):
		for dr in range(maxi(-r, -dq - r), mini(r, -dq + r) + 1):
			cells.append(Hex.axial_to_offset(c_ax + Vector2i(dq, dr)))
	var minc := 999
	var maxc := -999
	for o in cells:
		minc = mini(minc, o.x)
		maxc = maxi(maxc, o.x)
	m.w = maxc - minc + 1
	m.h = 2 * r + 1
	var n := m.w * m.h
	m.ground.resize(n)
	m.obstacle.resize(n)
	m.amount.resize(n)
	m.ground.fill(MatchState.Ground.VOID)
	for o in cells:
		m.ground[m.idx_of(o.x - minc, o.y)] = MatchState.Ground.LAND
	m.center = m.idx_of(c_off.x - minc, c_off.y)


static func _hq_spot(m: MatchState) -> int:
	return m.idx_from_axial(m.axial(m.center) + Vector2i(0, -(m.radius - 1)))


static func _terrain(m: MatchState, rng: RandomNumberGenerator) -> void:
	var hq0 := _hq_spot(m)
	var hq1 := m.mirror(hq0)
	var trees := DB.obstacle_index("trees")
	var rocks := DB.obstacle_index("rocks")
	for i in m.n_tiles():
		if m.ground[i] == MatchState.Ground.VOID:
			continue
		var j := m.mirror(i)
		if j < i:
			continue  # set together with its mirror twin
		if i == m.center or m.dist(i, hq0) <= 2 or m.dist(i, hq1) <= 2:
			continue
		var roll := rng.randf()
		var g := MatchState.Ground.LAND
		var ob := 0
		if roll < DB.rules.water_share:
			g = MatchState.Ground.WATER
		elif roll < DB.rules.water_share + DB.rules.trees_share:
			ob = trees
		elif roll < DB.rules.water_share + DB.rules.trees_share + DB.rules.rocks_share:
			ob = rocks
		for k in [i, j]:
			m.ground[k] = g
			m.obstacle[k] = ob
			m.amount[k] = DB.obstacle_at(ob).amount if ob > 0 else 0
	# a guaranteed tree and rock hex near each base, for the engineers
	var a0 := m.axial(hq0)
	var near_t := m.idx_from_axial(a0 + Vector2i(2, 0))
	var near_r := m.idx_from_axial(a0 + Vector2i(-2, 1))
	for pair in [[near_t, trees], [near_r, rocks]]:
		if pair[0] < 0:
			continue
		for k in [pair[0], m.mirror(pair[0])]:
			m.ground[k] = MatchState.Ground.LAND
			m.obstacle[k] = pair[1]
			m.amount[k] = DB.obstacle_at(pair[1]).amount
	_ensure_path(m, hq0, hq1)


## Make sure the two bases can reach each other on foot.
static func _ensure_path(m: MatchState, a: int, b: int) -> void:
	var line := Hex.axial_line(m.axial(a), m.axial(b))
	var seen := { a: true }
	var stack := [a]
	while not stack.is_empty():
		var x: int = stack.pop_back()
		for y in m.neighbors(x):
			if seen.has(y) or m.ground[y] != MatchState.Ground.LAND:
				continue
			var o := m.obstacle_def(y)
			if o != null and o.blocks_move:
				continue
			seen[y] = true
			stack.append(y)
	if seen.has(b):
		return
	for ax in line:
		var i := m.idx_from_axial(ax)
		if i < 0:
			continue
		for k in [i, m.mirror(i)]:
			m.ground[k] = MatchState.Ground.LAND
			var o := m.obstacle_def(k)
			if o != null and o.blocks_move:
				m.obstacle[k] = 0
				m.amount[k] = 0


## Home Base, starting buildings and units, mirrored for player 2.
static func _bases(m: MatchState) -> void:
	var hq0 := _hq_spot(m)
	# neighbours behind the base (away from the centre) get the buildings,
	# the ones in front get the units
	var ring := m.neighbors(hq0)
	ring.sort_custom(func(x, y): return m.dist(x, m.center) > m.dist(y, m.center) or (m.dist(x, m.center) == m.dist(y, m.center) and x < y))
	var spots: Array[int] = []
	for j in ring:
		if m.ground[j] == MatchState.Ground.LAND:
			spots.append(j)
	for p in m.players.size():
		var flip := p == 1
		var hq := m.mirror(hq0) if flip else hq0
		m.place_building("hq", hq, p, true)
		var k := 0
		for btype in DB.rules.start_buildings:
			var s: int = spots[k]
			m.place_building(btype, m.mirror(s) if flip else s, p, true)
			k += 1
		var front := spots.slice(k)
		front.reverse()
		var ui := 0
		for utype in DB.rules.start_units:
			var s: int = front[ui]
			m.spawn_unit(utype, m.mirror(s) if flip else s, p)
			ui += 1
