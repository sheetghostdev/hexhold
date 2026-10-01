class_name MatchAI
extends RefCounted
## Computer opponent. It only ever talks to the match through commands,
## exactly like a human (or a remote player) does.


static func play_turn(m: MatchState) -> void:
	var p := m.cur
	if m.winner >= 0 or not m.players[p].alive:
		return
	var enemy_hq := _enemy_hq(m, p)
	for u in m.player_units(p):
		if m.winner >= 0:
			return
		if not m.units.has(u) or u.def().attack <= 0.0:
			continue
		if _attack(m, p, u):
			continue
		var dest := _advance(m, u, enemy_hq)
		if dest >= 0:
			m.apply(p, { "type": "move", "unit": u.id, "to": dest })
			if m.units.has(u):
				_attack(m, p, u)
	_build(m, p)
	_train(m, p)


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
	var reach := m.reachable(u)
	var best := -1
	var best_d := m.dist(u.idx, goal)
	var keep_range := u.def().attack_range > 1
	for t in reach:
		var d := m.dist(t, goal)
		if keep_range and d < u.def().attack_range:
			continue
		if d < best_d:
			best_d = d
			best = t
	return best


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
		if m.build_problem(p, want, i) != "":
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
