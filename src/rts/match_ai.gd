class_name MatchAI
extends RefCounted
## Computer opponent. It only ever talks to the match through commands,
## exactly like a human (or a remote player) does.


static func play_turn(m: MatchState) -> void:
	var p := m.cur
	if m.winner >= 0 or not m.players[p].alive:
		return
	var enemy_hq := _enemy_hq(m, p)
	# Attack in waves: gather at home until the army is big enough.
	var army := 0
	for u in m.player_units(p):
		if u.def().attack > 0.0:
			army += 1
	var push := army >= 3 or m.turn >= 6
	var home := m.hq_of(p)
	for u in m.player_units(p):
		if m.winner >= 0:
			return
		if not m.units.has(u) or u.def().attack <= 0.0:
			continue
		if _attack(m, p, u):
			continue
		var goal := enemy_hq
		if not push and home != null:
			# rally point: the edge of home territory toward the enemy
			goal = _rally(m, p, home.idx, enemy_hq)
			if m.dist(u.idx, goal) <= 1:
				continue
		var dest := _advance(m, u, goal)
		if dest >= 0:
			m.apply(p, { "type": "move", "unit": u.id, "to": dest })
			if m.units.has(u):
				_attack(m, p, u)
	for u in m.player_units(p):
		if m.units.has(u) and u.def().abilities.has("clear"):
			_engineer(m, p, u)
	_build(m, p)
	_train(m, p)
	_research(m, p)


static func _rally(m: MatchState, p: int, home: int, enemy: int) -> int:
	var best := home
	var best_d := m.dist(home, enemy)
	for i in m.in_range(home, 3):
		if m.ground[i] == MatchState.Ground.LAND and m.dist(i, enemy) < best_d and m.dist(i, home) <= 3:
			best_d = m.dist(i, enemy)
			best = i
	return best


static func _enemy_hq(m: MatchState, p: int) -> int:
	for b in m.buildings:
		if b.type == "hq" and b.owner != p:
			return b.idx
	return m.center


static func _attack(m: MatchState, p: int, u: MatchState.UnitS) -> bool:
	var best := -1
	var best_s := -INF
	for t in m.attack_targets(u):
		var fc := m.forecast(u, t)
		var s: float = fc["dmg"] - fc["ret"] * 0.8 + (8.0 if fc["kill"] else 0.0) - (15.0 if fc["ret_kill"] else 0.0)
		var b := m.building_on(t)
		if b != null:
			s += 4.0 if b.type == "hq" or b.type == "power_plant" else 1.0
		if s > best_s:
			best_s = s
			best = t
	if best >= 0 and best_s > 0.0:
		return m.apply(p, { "type": "attack", "unit": u.id, "target": best })["ok"]
	return false


static func _advance(m: MatchState, u: MatchState.UnitS, goal: int) -> int:
	var field := _field(m, goal)
	var reach := m.reachable(u)
	var best := -1
	var best_d: int = field.get(u.idx, 999)
	var keep_range := u.def().attack_range > 1
	for t in reach:
		var d: int = field.get(t, 999)
		if keep_range and m.dist(t, goal) < u.def().attack_range:
			continue
		if d < best_d:
			best_d = d
			best = t
	return best


## Walking distance to a goal hex for every hex (ignores units).
static func _field(m: MatchState, goal: int) -> Dictionary:
	var out := { goal: 0 }
	var open: Array[int] = [goal]
	var k := 0
	while k < open.size():
		var c: int = open[k]
		k += 1
		for n in m.neighbors(c):
			if out.has(n):
				continue
			if not m.passable(n, -1) and m.unit_on(n) == null:
				continue
			out[n] = out[c] + 1
			open.append(n)
	return out


static func _train(m: MatchState, p: int) -> void:
	var prefs := ["tank", "sniper", "rifleman"]
	for b in m.player_buildings(p):
		for unit_id in prefs:
			if b.def().trains.has(unit_id) and m.train_problem(p, b, unit_id) == "":
				# keep a mix: one sniper per two riflemen
				if unit_id == "sniper" and _count(m, p, "sniper") * 2 > _count(m, p, "rifleman"):
					continue
				m.apply(p, { "type": "train", "building": b.id, "unit": unit_id })
				break


static func _count(m: MatchState, p: int, type: String) -> int:
	var n := 0
	for u in m.player_units(p):
		if u.type == type:
			n += 1
	return n


## One construction per turn: enough power first, then a Factory, then turrets.
static func _build(m: MatchState, p: int) -> void:
	var pw := m.power(p, true)
	var want := ""
	if pw["demand"] + 2 > pw["supply"]:
		want = "power_plant"
	elif _bcount(m, p, "factory") == 0:
		want = "factory"
	elif _bcount(m, p, "turret") < 2:
		want = "turret"
	elif _bcount(m, p, "drill") < 2:
		want = "drill"
	if want == "":
		return
	var d := DB.building(want)
	if m.cost_problem(p, d.cost_alloy, d.cost_fuel) != "":
		return
	var enemy := _enemy_hq(m, p)
	var best := -1
	var best_s := -INF
	for i in m.n_tiles():
		if m.ground[i] != MatchState.Ground.LAND or m.owner_of(i) != p:
			continue
		if m.build_problem(p, want, i) != "" or not _keeps_path(m, p, i):
			continue
		var s := 0.0
		match want:
			"turret": s = -m.dist(i, enemy)
			"power_plant": s = m.dist(i, enemy)
			"drill":
				for j in m.neighbors(i):
					if m.obstacle[j] != 0:
						s += 1.0
			_: s = -absf(m.dist(i, enemy) - m.dist(m.hq_of(p).idx, enemy))
		if s > best_s:
			best_s = s
			best = i
	if best >= 0:
		m.apply(p, { "type": "build", "building": want, "at": best })


static func _bcount(m: MatchState, p: int, type: String) -> int:
	var n := 0
	for b in m.player_buildings(p):
		if b.type == type:
			n += 1
	return n


## Engineers clear the nearest trees/rocks near home, favouring whichever
## resource is lower.
static func _engineer(m: MatchState, p: int, u: MatchState.UnitS) -> void:
	if u.task >= 0 or u.fresh:
		return
	var want := "alloy" if m.players[p].alloy <= m.players[p].fuel else "fuel"
	if _clear_best(m, p, u, want):
		return
	var hq := m.hq_of(p)
	if hq == null:
		return
	var goal := -1
	var goal_d := 999
	for i in m.n_tiles():
		var o := m.obstacle_def(i)
		if o == null or m.amount[i] == 0 or m.dist(i, hq.idx) > 4 or m._being_cleared(i):
			continue
		var d := m.dist(i, u.idx) + (0 if o.resource == want else 2)
		if d < goal_d:
			goal_d = d
			goal = i
	if goal < 0:
		return
	var reach := m.reachable(u)
	var best := -1
	var best_d := m.dist(u.idx, goal)
	for t in reach:
		var d := m.dist(t, goal)
		if d < best_d:
			best_d = d
			best = t
	if best >= 0:
		m.apply(p, { "type": "move", "unit": u.id, "to": best })
		_clear_best(m, p, u, want)


static func _clear_best(m: MatchState, p: int, u: MatchState.UnitS, want: String) -> bool:
	var best := -1
	var best_s := -INF
	for t in m.clear_targets(u):
		var o := m.obstacle_def(t)
		var s: float = m.amount[t] + (4.0 if o.resource == want else 0.0)
		if s > best_s:
			best_s = s
			best = t
	if best < 0:
		return false
	return m.apply(p, { "type": "clear", "unit": u.id, "target": best })["ok"]


## True if building on hex i still leaves a walkable route from every
## building that trains units to the enemy base (don't wall yourself in).
static func _keeps_path(m: MatchState, p: int, blocked: int) -> bool:
	var enemy := _enemy_hq(m, p)
	var goal := {}
	for j in m.neighbors(enemy):
		goal[j] = true
	for b in m.player_buildings(p):
		if b.def().trains.is_empty():
			continue
		var seen := { blocked: true }
		var open: Array[int] = []
		for j in m.neighbors(b.idx):
			if j != blocked and m.passable(j, p):
				open.append(j)
				seen[j] = true
		var found := false
		while not open.is_empty() and not found:
			var c: int = open.pop_back()
			if goal.has(c):
				found = true
				break
			for n in m.neighbors(c):
				if not seen.has(n) and m.passable(n, p):
					seen[n] = true
					open.append(n)
		if not found:
			return false
	return true


## Spend leftovers on research once the army is going.
static func _research(m: MatchState, p: int) -> void:
	var pl := m.players[p]
	if pl.alloy < 8 or pl.fuel < 8:
		return
	for id in ["ap_rounds", "composite_armor", "power_grid", "recon_drones"]:
		if m.research_problem(p, id) == "":
			m.apply(p, { "type": "research", "upgrade": id })
			return
