class_name AIPlayer
extends RefCounted
## A straightforward computer opponent: expand, grow, build and fight.


static func play_turn(gs: GameState) -> void:
	var p := gs.cur
	if gs.winner >= 0 or not gs.players[p].alive:
		return
	_economy(gs, p)
	# Units act, nearest-to-danger first so defenders react sensibly.
	var order := gs.player_units(p)
	for u in order:
		if gs.winner >= 0:
			return
		if gs.units.has(u):
			_act(gs, u)
	_recruit(gs, p)
	_build(gs, p)
	_roads(gs, p)


# ---------------------------------------------------------------- units

static func _act(gs: GameState, u: GameState.Unit) -> void:
	if u.fresh:
		return
	if gs.can_capture(u):
		gs.capture(u)
		return
	if _try_attack(gs, u):
		return
	# Catapults and archers prefer to shoot from where they stand.
	var dest := _choose_move(gs, u)
	if dest >= 0:
		gs.move_unit(u, dest)
		if not gs.units.has(u):
			return
		if gs.can_capture(u) and gs.town_on(u.idx).owner == -1:
			gs.capture(u)
			return
		_try_attack(gs, u)


static func _try_attack(gs: GameState, u: GameState.Unit) -> bool:
	var best := -1
	var best_score := -INF
	for t in gs.attack_targets(u):
		var fc := gs.forecast(u, t)
		var s: float = fc["dmg"] - fc["ret"] * 0.8
		if fc["kill"]:
			s += 8.0
		if fc.get("ret_kill", false):
			s -= 15.0
		if fc["kind"] == "structure":
			s = fc["dmg"] * 0.6 + (6.0 if fc["kill"] else 0.0)
		var target := gs.unit_on(t)
		if target != null and target.owner == -1:
			s -= 1.0
		if s > best_score:
			best_score = s
			best = t
	if best >= 0 and best_score > 0.0:
		gs.attack(u, best)
		return true
	return false


static func _goals(gs: GameState, u: GameState.Unit) -> Array:
	## [[idx, value]] — places worth walking towards.
	var p := u.owner
	var out: Array = []
	var ex := gs.players[p].explored
	var strong := u.hp >= Defs.unit_max_hp(u.type, u.kills) * 0.6
	for t in gs.towns:
		if t.owner == p:
			# defend own towns when enemies are near
			for o in gs.units:
				if o.owner != p and gs.dist(o.idx, t.idx) <= 2 and gs.unit_on(t.idx) == null:
					out.append([t.idx, 14.0])
					break
			continue
		if not ex[t.idx]:
			continue
		var occ := gs.unit_on(t.idx)
		if occ != null and occ.owner != p and not strong:
			continue
		out.append([t.idx, 12.0 if t.owner == -1 else (16.0 if t.capital else 11.0)])
	for i in gs.n_tiles():
		if not ex[i]:
			continue
		if gs.feature[i] == Defs.F.RUIN:
			out.append([i, 9.0])
		elif gs.feature[i] == Defs.F.CAMP and gs.unit_on(i) == null:
			out.append([i, 8.0])
	if strong:
		for o in gs.units:
			if o.owner != p and ex[o.idx] and (o.owner >= 0 or u.type != Defs.U.ARCHER):
				out.append([o.idx, 6.0 if o.owner >= 0 else 4.0])
	if out.is_empty():
		# explore: nearest unexplored land
		for i in gs.n_tiles():
			if not ex[i]:
				out.append([i, 3.0])
	return out


static func _choose_move(gs: GameState, u: GameState.Unit) -> int:
	if u.type == Defs.U.CATAPULT and not gs.attack_targets(u).is_empty():
		return -1
	var reach := gs.reachable(u)
	if reach.is_empty():
		return -1
	var goals := _goals(gs, u)
	if goals.is_empty():
		return -1
	var here := _value_at(gs, u, u.idx, goals)
	var best := -1
	var best_v := here
	for t in reach:
		var v := _value_at(gs, u, t, goals)
		if v > best_v:
			best_v = v
			best = t
	return best


static func _value_at(gs: GameState, u: GameState.Unit, idx: int, goals: Array) -> float:
	var v := -INF
	for g in goals:
		var d := gs.dist(idx, g[0])
		var gv: float = g[1] - d * 1.5
		if d == 0 and gs.unit_on(g[0]) != null and gs.unit_on(g[0]) != u:
			gv -= 50.0
		v = maxf(v, gv)
	var ter := gs.terrain[idx]
	if ter == Defs.T.FOREST or ter == Defs.T.HILLS:
		v += 0.4
	if gs.is_structure(idx):
		v += 0.6
	# ranged units hang back a little
	if Defs.UNITS[u.type]["range"] > 1:
		for o in gs.units:
			if o.owner != u.owner and gs.dist(o.idx, idx) == 1:
				v -= 2.0
	return v


# ---------------------------------------------------------------- economy

static func _economy(gs: GameState, p: int) -> void:
	_rewards(gs, p)
	var pl := gs.players[p]
	var army := gs.player_units(p).size()
	if pl.keep < 3 and army >= 3 and gs.keep_problem(p) == "" and pl.gold >= Defs.KEEP_COST[pl.keep + 1] + 3:
		gs.upgrade_keep(p)


static func _rewards(gs: GameState, p: int) -> void:
	var t := gs.pending_reward(p)
	while t != null:
		var opts := Defs.rewards_for(t.reward)
		var pick := 0
		if opts.has(Defs.R.CHAMPION):
			pick = opts.find(Defs.R.CHAMPION)
		elif opts.has(Defs.R.WALLS) and t.capital:
			pick = opts.find(Defs.R.WALLS)
		elif opts.has(Defs.R.BORDERS):
			pick = opts.find(Defs.R.BORDERS)
		gs.choose_reward(t, pick)
		t = gs.pending_reward(p)


static func _recruit(gs: GameState, p: int) -> void:
	var pl := gs.players[p]
	var reserve: int = 0 if pl.keep >= 3 else Defs.KEEP_COST[pl.keep + 1] / 3
	for t in gs.player_towns(p):
		if gs.player_units(p).size() >= gs.unit_cap(p):
			return
		if gs.unit_on(t.idx) != null:
			continue
		var choices: Array[int] = []
		if pl.keep >= 3:
			choices = [Defs.U.CATAPULT, Defs.U.KNIGHT, Defs.U.SWORDSMAN, Defs.U.ARCHER]
		elif pl.keep >= 2:
			choices = [Defs.U.KNIGHT, Defs.U.SWORDSMAN, Defs.U.ARCHER, Defs.U.SPEARMAN]
		else:
			choices = [Defs.U.ARCHER, Defs.U.SPEARMAN]
		var start := posmod(gs.turn + t.idx, choices.size())
		for k in choices.size():
			var type := choices[(start + k) % choices.size()]
			var cost: int = Defs.UNITS[type]["cost"]
			if pl.gold - cost < reserve and gs.turn > 3:
				continue
			if gs.recruit_problem(t, type) == "":
				gs.recruit(t, type)
				break


static func _build(gs: GameState, p: int) -> void:
	var pl := gs.players[p]
	var enemy_near := {}
	for o in gs.units:
		if o.owner >= 0 and o.owner != p:
			for j in gs.tiles_in_range(o.idx, 3):
				enemy_near[j] = true
	# best-value buildings first: people per gold
	var options: Array = []
	for i in gs.n_tiles():
		if gs.tile_owner(i) != p or gs.building[i] != Defs.B.NONE or gs.town_at.has(i):
			continue
		for b in [Defs.B.FARM, Defs.B.LUMBER, Defs.B.MINE, Defs.B.MARKET, Defs.B.TOWER]:
			if gs.build_problem(p, i, b) != "":
				continue
			var cost: int = Defs.BUILDINGS[b]["cost"]
			var value := float(gs.build_pop(i, b)) / maxf(1.0, cost)
			if b == Defs.B.MARKET:
				var adj := 0
				for j in gs.neighbors(i):
					var nb := gs.building[j]
					if nb == Defs.B.FARM or nb == Defs.B.LUMBER or nb == Defs.B.MINE:
						adj += 1
				value = 0.12 * adj
			elif b == Defs.B.TOWER:
				value = 0.5 if enemy_near.has(i) else 0.0
			if value > 0.0:
				options.append([value, i, b])
	options.sort_custom(func(a, b): return a[0] > b[0])
	var spent := 0
	for o in options:
		if spent >= 4 or pl.gold < 3:
			break
		if gs.build_problem(p, o[1], o[2]) == "":
			gs.build(p, o[1], o[2])
			spent += 1
			_rewards(gs, p)


static func _roads(gs: GameState, p: int) -> void:
	var cap := gs.capital_of(p)
	if cap == null or gs.players[p].gold < 10:
		return
	var linked := gs.connected_towns(p)
	for t in gs.player_towns(p):
		if t.capital or linked.has(t.idx):
			continue
		var path := _road_path(gs, p, cap.idx, t.idx)
		if path.is_empty() or path.size() > 10:
			continue
		for i in path:
			if gs.players[p].gold < 6:
				return
			if not gs.has_road(i):
				gs.build_road(p, i)
		return


static func _road_path(gs: GameState, p: int, from: int, to: int) -> Array[int]:
	var prev := { from: -1 }
	var queue: Array[int] = [from]
	while not queue.is_empty():
		var a: int = queue.pop_front()
		if a == to:
			break
		for b in gs.neighbors(a):
			if prev.has(b):
				continue
			if gs.terrain[b] == Defs.T.MOUNTAIN or gs.terrain[b] == Defs.T.WATER:
				continue
			var o := gs.tile_owner(b)
			if o != p and o != -1:
				continue
			prev[b] = a
			queue.append(b)
	if not prev.has(to):
		return []
	var path: Array[int] = []
	var c := to
	while c != -1:
		path.push_front(c)
		c = prev[c]
	return path
