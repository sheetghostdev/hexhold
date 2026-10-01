class_name GameState
extends RefCounted
## The whole game: map, kingdoms, towns, units and every rule.
## Pure data + logic (no nodes), so it can be saved into a link,
## run by the AI, and tested headless.

const VERSION := 2

enum Ev { ATTACK, CAPTURE, TOWER, BANDIT, ELIMINATED, KEEP, GROW, RUIN, CAMP, WIN, STRUCT }
enum Mode { CONQUEST, GLORY }


class Player:
	var name := ""
	var color := 0
	var gold := 0
	var keep := 1
	var ai := false
	var alive := true
	var explored := PackedByteArray()
	var seen_seq := 0
	var kills := 0


class Town:
	var idx := 0
	var owner := -1
	var level := 1
	var pop := 0        # people towards the next level
	var bonus := 0      # extra gold per turn from rewards
	var walls := false
	var capital := false
	var big := false    # bigger borders (radius 2)
	var reward := 0     # level whose reward is waiting to be picked (0 = none)
	var name := ""


class Unit:
	var id := 0
	var type := 0
	var idx := 0
	var owner := 0
	var hp := 10
	var moved := false
	var attacked := false
	var fresh := false
	var kills := 0


var game_id := ""
var map_seed := 0
var w := 0
var h := 0
var turn := 1
var cur := 0
var mode: int = Mode.CONQUEST
var turn_limit := 30
var online := false
var winner := -1
var seq := 0
var next_unit_id := 1

var terrain := PackedByteArray()
var feature := PackedByteArray()
var building := PackedByteArray()
var bhp := PackedByteArray()
var road := PackedByteArray()
var claim := PackedByteArray()  # town index + 1, 0 = unclaimed

var players: Array[Player] = []
var towns: Array[Town] = []
var units: Array[Unit] = []
var events: Array = []  # [seq, turn, type, args...]

# Derived caches
var town_at := {}
var unit_at := {}
var _vis_cache := {}


## Call after anything that can change what players see.
func _dirty() -> void:
	_vis_cache.clear()


# ---------------------------------------------------------------- geometry

func n_tiles() -> int:
	return w * h


func idx_of(col: int, row: int) -> int:
	if col < 0 or row < 0 or col >= w or row >= h:
		return -1
	return row * w + col


func col_row(idx: int) -> Vector2i:
	return Vector2i(idx % w, idx / w)


func axial(idx: int) -> Vector2i:
	return Hex.offset_to_axial(idx % w, idx / w)


func idx_from_axial(a: Vector2i) -> int:
	var o := Hex.axial_to_offset(a)
	return idx_of(o.x, o.y)


func center(idx: int) -> Vector2:
	return Hex.offset_to_pixel(idx % w, idx / w)


func neighbors(idx: int) -> Array[int]:
	var out: Array[int] = []
	var a := axial(idx)
	for d in Hex.AXIAL_DIRS:
		var j := idx_from_axial(a + d)
		if j >= 0:
			out.append(j)
	return out


## Neighbor in a given direction (0..5) or -1.
func neighbor_dir(idx: int, dir: int) -> int:
	return idx_from_axial(axial(idx) + Hex.AXIAL_DIRS[dir])


func dist(a: int, b: int) -> int:
	return Hex.axial_distance(axial(a), axial(b))


func tiles_in_range(idx: int, r: int) -> Array[int]:
	var out: Array[int] = []
	var c := axial(idx)
	for dq in range(-r, r + 1):
		for dr in range(maxi(-r, -dq - r), mini(r, -dq + r) + 1):
			var j := idx_from_axial(c + Vector2i(dq, dr))
			if j >= 0:
				out.append(j)
	return out


# ---------------------------------------------------------------- caches & queries

func rebuild_caches() -> void:
	_dirty()
	town_at.clear()
	for i in towns.size():
		town_at[towns[i].idx] = i
	unit_at.clear()
	for u in units:
		unit_at[u.idx] = u


func town_on(idx: int) -> Town:
	var i: int = town_at.get(idx, -1)
	return towns[i] if i >= 0 else null


func unit_on(idx: int) -> Unit:
	return unit_at.get(idx, null)


func unit_by_id(id: int) -> Unit:
	for u in units:
		if u.id == id:
			return u
	return null


func tile_owner(idx: int) -> int:
	var c := claim[idx]
	if c == 0:
		return -1
	return towns[c - 1].owner


func tile_town(idx: int) -> Town:
	var c := claim[idx]
	return towns[c - 1] if c > 0 else null


func is_land(idx: int) -> bool:
	return terrain[idx] != Defs.T.WATER


func has_road(idx: int) -> bool:
	return road[idx] != 0 or town_at.has(idx)


func is_structure(idx: int) -> bool:
	var b := building[idx]
	return b == Defs.B.WALL or b == Defs.B.TOWER


func player_towns(p: int) -> Array[Town]:
	var out: Array[Town] = []
	for t in towns:
		if t.owner == p:
			out.append(t)
	return out


func player_units(p: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.owner == p:
			out.append(u)
	return out


func capital_of(p: int) -> Town:
	for t in towns:
		if t.owner == p and t.capital:
			return t
	return null


func town_radius(t: Town) -> int:
	return 2 if t.big else 1


func unit_cap(p: int) -> int:
	var cap := 0
	for t in towns:
		if t.owner == p:
			cap += town_unit_cap(t)
	return cap


func town_unit_cap(t: Town) -> int:
	return t.level + 1


func can_afford(p: int, cost: int) -> bool:
	return players[p].gold >= cost


func pay(p: int, cost: int) -> void:
	players[p].gold -= cost


func alive_players() -> Array[int]:
	var out: Array[int] = []
	for i in players.size():
		if players[i].alive:
			out.append(i)
	return out


# ---------------------------------------------------------------- territory

func claim_around(town_i: int) -> void:
	_dirty()
	var t := towns[town_i]
	for j in tiles_in_range(t.idx, town_radius(t)):
		if claim[j] == 0 and (not town_at.has(j) or j == t.idx):
			claim[j] = town_i + 1
	claim[t.idx] = town_i + 1


# ---------------------------------------------------------------- visibility

func visible_for(p: int) -> PackedByteArray:
	if _vis_cache.has(p):
		return _vis_cache[p]
	var vis := PackedByteArray()
	vis.resize(n_tiles())
	if p < 0:
		vis.fill(1)
		_vis_cache[p] = vis
		return vis
	for t in towns:
		if t.owner == p:
			for j in tiles_in_range(t.idx, town_radius(t) + 1):
				vis[j] = 1
	for u in units:
		if u.owner == p:
			for j in tiles_in_range(u.idx, 2):
				vis[j] = 1
	for i in n_tiles():
		if building[i] == Defs.B.TOWER and tile_owner(i) == p:
			for j in tiles_in_range(i, 3):
				vis[j] = 1
		elif claim[i] != 0 and tile_owner(i) == p:
			vis[i] = 1
	_vis_cache[p] = vis
	return vis


func update_explored(p: int) -> void:
	if p < 0 or p >= players.size():
		return
	var vis := visible_for(p)
	var ex := players[p].explored
	for i in n_tiles():
		if vis[i]:
			ex[i] = 1
	players[p].explored = ex


func reveal(p: int, idx: int, r: int) -> void:
	var ex := players[p].explored
	for j in tiles_in_range(idx, r):
		ex[j] = 1
	players[p].explored = ex


# ---------------------------------------------------------------- movement

func move_points(u: Unit) -> int:
	return int(Defs.UNITS[u.type]["move"]) * 2


func is_enemy_unit(u: Unit, p: int) -> bool:
	return u != null and u.owner != p


func passable_for(idx: int, p: int) -> bool:
	var t := terrain[idx]
	if t == Defs.T.MOUNTAIN:
		return false
	if t == Defs.T.WATER and road[idx] == 0:
		return false
	if is_structure(idx) and tile_owner(idx) != p:
		return false
	return true


func _adjacent_enemy(idx: int, p: int) -> bool:
	for j in neighbors(idx):
		var o := unit_on(j)
		if o != null and o.owner != p:
			return true
	return false


## Returns {idx: {"rem": int, "from": int}} for every tile the unit can end on.
func reachable(u: Unit) -> Dictionary:
	var out := {}
	if u.moved or u.fresh or u.owner < 0:
		return out
	# knights can still ride off after attacking
	if u.attacked and u.type != Defs.U.KNIGHT:
		return out
	var best := { u.idx: move_points(u) }
	var parent := { u.idx: -1 }
	var open: Array[int] = [u.idx]
	while not open.is_empty():
		# pop the entry with the most remaining points
		var bi := 0
		for k in open.size():
			if best[open[k]] > best[open[bi]]:
				bi = k
		var a: int = open[bi]
		open.remove_at(bi)
		var rem: int = best[a]
		if rem <= 0:
			continue
		for b in neighbors(a):
			if not passable_for(b, u.owner):
				continue
			var occ := unit_on(b)
			if occ != null and occ.owner != u.owner:
				continue
			var cost := 1 if (has_road(a) and has_road(b)) else 2
			if cost > rem:
				continue
			var nrem := rem - cost
			var ter := terrain[b]
			if (ter == Defs.T.FOREST or ter == Defs.T.HILLS) and not has_road(b):
				nrem = 0
			if is_structure(b):
				nrem = 0
			if feature[b] == Defs.F.RUIN or feature[b] == Defs.F.CAMP:
				nrem = 0
			var tw := town_on(b)
			if tw != null and tw.owner != u.owner:
				nrem = 0
			if _adjacent_enemy(b, u.owner):
				nrem = 0
			if not best.has(b) or best[b] < nrem:
				best[b] = nrem
				parent[b] = a
				open.append(b)
	for k in best:
		if k != u.idx and unit_on(k) == null:
			out[k] = { "rem": best[k], "from": parent[k] }
	return out


func path_to(reach: Dictionary, start: int, target: int) -> Array[int]:
	var path: Array[int] = []
	var cur_i := target
	var guard := 0
	while cur_i != start and cur_i >= 0 and guard < 200:
		path.push_front(cur_i)
		if not reach.has(cur_i):
			break
		cur_i = reach[cur_i]["from"]
		guard += 1
	path.push_front(start)
	return path


## Moves the unit; returns a list of notable happenings ({"kind":..., ...}).
func move_unit(u: Unit, target: int) -> Array:
	var reach := reachable(u)
	if not reach.has(target):
		return []
	unit_at.erase(u.idx)
	u.idx = target
	unit_at[target] = u
	u.moved = true
	_dirty()
	var notes: Array = []
	# grey villages join you as soon as you walk in
	var tw := town_on(target)
	if tw != null and tw.owner == -1 and not u.attacked:
		capture(u)
		notes.append({ "kind": "capture", "text": "%s joins your kingdom!" % tw.name })
	if feature[target] == Defs.F.RUIN:
		notes.append(_explore_ruin(u))
	elif feature[target] == Defs.F.CAMP:
		feature[target] = Defs.F.NONE
		players[u.owner].gold += Defs.CAMP_LOOT
		_log(Ev.CAMP, [u.owner, Defs.CAMP_LOOT])
		notes.append({ "kind": "camp", "text": "Bandit camp looted: +%d gold" % Defs.CAMP_LOOT })
	update_explored(u.owner)
	return notes


func _explore_ruin(u: Unit) -> Dictionary:
	var i := u.idx
	feature[i] = Defs.F.NONE
	var roll := mix(map_seed, i, 7) % 5
	var p := players[u.owner]
	var text := ""
	match roll:
		0:
			p.gold += 10
			text = "Buried treasure! +10 gold"
		1:
			var best: Town = null
			for t in towns:
				if t.owner == u.owner and (best == null or dist(t.idx, i) < dist(best.idx, i)):
					best = t
			if best != null:
				add_pop(best, 2)
				text = "Lost villagers settle in %s: +2 people" % best.name
			else:
				p.gold += 8
				text = "Old coins! +8 gold"
		2:
			var spot := -1
			for j in neighbors(i):
				if unit_on(j) == null and passable_for(j, u.owner) and is_land(j):
					spot = j
					break
			if spot >= 0:
				var nu := spawn_unit(Defs.U.SWORDSMAN, spot, u.owner)
				nu.kills = Defs.VETERAN_KILLS
				nu.hp = Defs.unit_max_hp(nu.type, nu.kills)
				nu.fresh = true
				text = "A veteran swordsman joins your cause!"
			else:
				p.gold += 8
				text = "Old coins! +8 gold"
		3:
			reveal(u.owner, i, 5)
			text = "An old map reveals the land around!"
		_:
			u.kills += 1
			if u.kills == Defs.VETERAN_KILLS:
				u.hp = Defs.unit_max_hp(u.type, u.kills)
			p.gold += 4
			text = "Ancient training scrolls! Unit gains experience, +4 gold"
	_log(Ev.RUIN, [u.owner, roll])
	return { "kind": "ruin", "text": text }


# ---------------------------------------------------------------- combat

func unit_range(u: Unit) -> int:
	var r: int = Defs.UNITS[u.type]["range"]
	if u.type == Defs.U.ARCHER and is_structure(u.idx) and tile_owner(u.idx) == u.owner:
		r += 1
	return r


func can_see(p: int, idx: int) -> bool:
	if p < 0:
		return true
	return visible_for(p)[idx] == 1


func attack_targets(u: Unit) -> Array[int]:
	var out: Array[int] = []
	if u.attacked or u.fresh or u.owner < 0:
		return out
	if u.type == Defs.U.CATAPULT and u.moved:
		return out
	var vis := visible_for(u.owner)
	for j in tiles_in_range(u.idx, unit_range(u)):
		if j == u.idx or not vis[j]:
			continue
		var o := unit_on(j)
		if o != null:
			if o.owner != u.owner:
				out.append(j)
		elif is_structure(j) and tile_owner(j) != u.owner:
			out.append(j)
	return out


func defence_bonus(def: Unit, att: Unit) -> float:
	var bonus := 1.0
	var i := def.idx
	var siege := att != null and att.type == Defs.U.CATAPULT
	var tw := town_on(i)
	if is_structure(i) and tile_owner(i) == def.owner:
		bonus = 1.0 if siege else 2.0
	elif tw != null and tw.owner == def.owner:
		if tw.walls and not siege:
			bonus = 3.0
		else:
			bonus = 1.5
	elif terrain[i] == Defs.T.FOREST or terrain[i] == Defs.T.HILLS:
		bonus = 1.5
	if def.type == Defs.U.SPEARMAN and att != null and att.type == Defs.U.KNIGHT:
		bonus *= 2.0
	return bonus


func _unit_atk(u: Unit) -> float:
	return float(Defs.UNITS[u.type]["atk"])


func _unit_def(u: Unit) -> float:
	return float(Defs.UNITS[u.type]["def"])


## Predicts an attack without changing anything.
func forecast(att: Unit, tidx: int) -> Dictionary:
	var d := unit_on(tidx)
	if d == null:
		var dmg := structure_damage(att)
		return { "kind": "structure", "dmg": dmg, "ret": 0, "kill": dmg >= bhp[tidx], "target_hp": bhp[tidx] }
	var a_max := float(Defs.unit_max_hp(att.type, att.kills))
	var d_max := float(Defs.unit_max_hp(d.type, d.kills))
	var af := _unit_atk(att) * (att.hp / a_max)
	var df := _unit_def(d) * (d.hp / d_max) * defence_bonus(d, att)
	var total := af + df
	var dmg := 0
	if total > 0.0:
		dmg = int(roundf(af / total * _unit_atk(att) * 4.5))
	dmg = maxi(dmg, 1)
	var kill := dmg >= d.hp
	var ret := 0
	if not kill and dist(att.idx, tidx) <= unit_range(d) and total > 0.0:
		var d_after := float(d.hp - dmg)
		var df2 := _unit_def(d) * (d_after / d_max) * defence_bonus(d, att)
		ret = int(roundf(df2 / total * _unit_def(d) * 4.5))
	return { "kind": "unit", "dmg": dmg, "ret": ret, "kill": kill, "ret_kill": ret >= att.hp, "target_hp": d.hp }


func structure_damage(att: Unit) -> int:
	var mult := 2.0
	if att.type == Defs.U.ARCHER:
		mult = 1.0
	elif att.type == Defs.U.CATAPULT:
		mult = 4.0
	return int(roundf(_unit_atk(att) * mult))


## Resolves an attack. Returns the forecast plus "advanced" if the attacker moved in.
func attack(att: Unit, tidx: int) -> Dictionary:
	if not attack_targets(att).has(tidx):
		return {}
	var fc := forecast(att, tidx)
	att.attacked = true
	if att.type != Defs.U.KNIGHT:
		att.moved = true
	_dirty()
	if fc["kind"] == "structure":
		var owner := tile_owner(tidx)
		bhp[tidx] = maxi(0, bhp[tidx] - fc["dmg"])
		if bhp[tidx] == 0:
			building[tidx] = Defs.B.NONE
		_log(Ev.STRUCT, [att.owner, owner, fc["dmg"], 1 if bhp[tidx] == 0 else 0, tidx])
		return fc
	var d := unit_on(tidx)
	d.hp -= fc["dmg"]
	var d_owner := d.owner
	var d_type := d.type
	if d.hp <= 0:
		_kill(d)
		_award_kill(att)
		# melee units storm into the tile
		if unit_range(att) == 1 and passable_for(tidx, att.owner) and dist(att.idx, tidx) == 1:
			unit_at.erase(att.idx)
			att.idx = tidx
			unit_at[tidx] = att
			att.moved = true
			fc["advanced"] = true
			if feature[tidx] == Defs.F.CAMP:
				feature[tidx] = Defs.F.NONE
				players[att.owner].gold += Defs.CAMP_LOOT
	elif fc["ret"] > 0:
		att.hp -= fc["ret"]
		if att.hp <= 0:
			_kill(att)
			if d.owner >= 0:
				_award_kill(d)
	_log(Ev.ATTACK, [att.owner, att.type, d_owner, d_type, fc["dmg"], 1 if fc["kill"] else 0, fc["ret"], 1 if fc.get("ret_kill", false) else 0])
	if att.owner >= 0 and att.hp > 0:
		update_explored(att.owner)
	return fc


func _kill(u: Unit) -> void:
	_dirty()
	units.erase(u)
	if unit_at.get(u.idx) == u:
		unit_at.erase(u.idx)


func _award_kill(u: Unit) -> void:
	if u.owner < 0:
		return
	u.kills += 1
	players[u.owner].kills += 1
	if u.kills == Defs.VETERAN_KILLS:
		u.hp = Defs.unit_max_hp(u.type, u.kills)


# ---------------------------------------------------------------- capture

func can_capture(u: Unit) -> bool:
	var t := town_on(u.idx)
	if t == null or t.owner == u.owner or u.owner < 0 or u.fresh:
		return false
	if u.attacked:
		return false
	if t.owner == -1:
		return true
	return not u.moved


func capture(u: Unit) -> void:
	if not can_capture(u):
		return
	var t := town_on(u.idx)
	var ti: int = town_at[u.idx]
	var old := t.owner
	t.owner = u.owner
	if old >= 0:
		t.capital = false
		t.reward = 0
	elif capital_of(u.owner) == null:
		t.capital = true
	u.moved = true
	u.attacked = true
	claim_around(ti)
	_log(Ev.CAPTURE, [u.owner, ti, old])
	if old >= 0:
		_check_elimination(old)
		_ensure_capital(old)
	update_explored(u.owner)
	_check_victory()


func _ensure_capital(p: int) -> void:
	if not players[p].alive or capital_of(p) != null:
		return
	var best: Town = null
	for t in towns:
		if t.owner == p and (best == null or t.level > best.level):
			best = t
	if best != null:
		best.capital = true


## Deterministic integer hash (same result on every platform).
static func mix(a: int, b: int, c: int) -> int:
	var x := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	x = (x ^ (x >> 13)) * 1274126177
	x = x ^ (x >> 16)
	return x & 0x7fffffff


func _check_elimination(p: int) -> void:
	if not players[p].alive:
		return
	if player_towns(p).is_empty():
		players[p].alive = false
		for u in player_units(p):
			_kill(u)
		_log(Ev.ELIMINATED, [p])


func _check_victory() -> void:
	if winner >= 0:
		return
	var alive := alive_players()
	if alive.size() == 1:
		winner = alive[0]
		_log(Ev.WIN, [winner])


# ---------------------------------------------------------------- building

## People a building would add to its town on this tile.
func build_pop(idx: int, b: int) -> int:
	var data: Dictionary = Defs.BUILDINGS[b]
	var pop: int = data.get("pop", 0)
	if pop > 0 and data.has("rich"):
		var f := feature[idx]
		if f == data["rich"] or (b == Defs.B.MINE and f == Defs.F.STONE):
			pop += 1
	return pop


## Returns "" if allowed, otherwise a short reason.
func build_problem(p: int, idx: int, b: int) -> String:
	if town_at.has(idx):
		return "Can't build on a town"
	var f := feature[idx]
	if f == Defs.F.RUIN or f == Defs.F.CAMP:
		return "Explore this tile first"
	var occ := unit_on(idx)
	if occ != null and occ.owner != p:
		return "An enemy is standing here"
	if tile_owner(idx) != p:
		return "Only inside your borders"
	if building[idx] != Defs.B.NONE:
		return "Already built here"
	var data: Dictionary = Defs.BUILDINGS[b]
	if not data["terrain"].has(terrain[idx]):
		return "Wrong terrain"
	if players[p].keep < data["keep"]:
		return "Needs %s" % Defs.KEEP_NAMES[data["keep"]]
	if not can_afford(p, data["cost"]):
		return "Not enough gold"
	return ""


func build(p: int, idx: int, b: int) -> bool:
	if build_problem(p, idx, b) != "":
		return false
	pay(p, Defs.BUILDINGS[b]["cost"])
	building[idx] = b
	bhp[idx] = Defs.BUILDINGS[b].get("hp", 0)
	_dirty()
	var pop := build_pop(idx, b)
	if pop > 0:
		add_pop(tile_town(idx), pop)
	return true


func road_cost(idx: int) -> int:
	return Defs.BRIDGE_COST if terrain[idx] == Defs.T.WATER else Defs.ROAD_COST


func road_problem(p: int, idx: int) -> String:
	if road[idx] != 0 or town_at.has(idx):
		return "Already has a road"
	if terrain[idx] == Defs.T.MOUNTAIN:
		return "No roads on mountains"
	var owner := tile_owner(idx)
	if owner != p and owner != -1:
		return "Enemy land"
	if p < players.size() and players[p].explored[idx] == 0:
		return "Unexplored"
	if terrain[idx] == Defs.T.WATER:
		var ok := false
		for j in neighbors(idx):
			if is_land(j) or road[j] != 0:
				ok = true
		if not ok:
			return "Bridges must touch land"
	var occ := unit_on(idx)
	if occ != null and occ.owner != p:
		return "An enemy is standing here"
	return ""


func build_road(p: int, idx: int) -> bool:
	if road_problem(p, idx) != "":
		return false
	var c := road_cost(idx)
	if not can_afford(p, c):
		return false
	pay(p, c)
	road[idx] = 1
	return true


func recruit_problem(t: Town, type: int) -> String:
	var p := cur
	if t.owner != p:
		return "Not your town"
	if unit_on(t.idx) != null:
		return "Move the unit off first"
	var data: Dictionary = Defs.UNITS[type]
	if players[p].keep < data["keep"]:
		return "Needs %s" % Defs.KEEP_NAMES[data["keep"]]
	if player_units(p).size() >= unit_cap(p):
		return "Army full: grow your towns"
	if not can_afford(p, data["cost"]):
		return "Not enough gold"
	return ""


func recruit(t: Town, type: int) -> Unit:
	if recruit_problem(t, type) != "":
		return null
	pay(cur, Defs.UNITS[type]["cost"])
	var u := spawn_unit(type, t.idx, cur)
	u.fresh = true
	return u


func spawn_unit(type: int, idx: int, owner: int) -> Unit:
	var u := Unit.new()
	u.id = next_unit_id
	next_unit_id += 1
	u.type = type
	u.idx = idx
	u.owner = owner
	u.hp = Defs.unit_max_hp(type, 0)
	units.append(u)
	unit_at[idx] = u
	_dirty()
	return u


func disband(u: Unit) -> void:
	if u.owner == cur:
		_kill(u)


func keep_problem(p: int) -> String:
	var k := players[p].keep
	if k >= 3:
		return "Already a Castle"
	if not can_afford(p, Defs.KEEP_COST[k + 1]):
		return "Not enough gold"
	return ""


func upgrade_keep(p: int) -> bool:
	if keep_problem(p) != "":
		return false
	pay(p, Defs.KEEP_COST[players[p].keep + 1])
	players[p].keep += 1
	_log(Ev.KEEP, [p, players[p].keep])
	return true


# ---------------------------------------------------------------- towns grow

func pop_need(level: int) -> int:
	return level + 1


## Adds people to a town; a full town levels up and earns a reward choice.
func add_pop(t: Town, n: int) -> void:
	if t == null or t.owner < 0:
		return
	t.pop += n
	while t.level < Defs.MAX_TOWN_LEVEL and t.pop >= pop_need(t.level):
		t.pop -= pop_need(t.level)
		t.level += 1
		if t.reward > 0:
			# an older choice was never made: take its first option
			choose_reward(t, 0)
		t.reward = t.level
		_log(Ev.GROW, [t.owner, town_at[t.idx], t.level])
	if t.level >= Defs.MAX_TOWN_LEVEL:
		t.pop = mini(t.pop, pop_need(t.level))


func pending_reward(p: int) -> Town:
	for t in towns:
		if t.owner == p and t.reward > 0:
			return t
	return null


func choose_reward(t: Town, option: int) -> int:
	if t.reward <= 0:
		return -1
	var opts := Defs.rewards_for(t.reward)
	t.reward = 0
	if opts.is_empty():
		return -1
	var r: int = opts[clampi(option, 0, opts.size() - 1)]
	var ti: int = town_at[t.idx]
	match r:
		Defs.R.WORKSHOP:
			t.bonus += 1
		Defs.R.GUILD:
			t.bonus += 2
		Defs.R.EXPLORER:
			reveal(t.owner, t.idx, 4)
		Defs.R.WALLS:
			t.walls = true
		Defs.R.TREASURE:
			players[t.owner].gold += 8
		Defs.R.BORDERS:
			t.big = true
			claim_around(ti)
		Defs.R.BOOM:
			add_pop(t, 3)
		Defs.R.CHAMPION:
			var spot := t.idx if unit_on(t.idx) == null else -1
			if spot < 0:
				for j in neighbors(t.idx):
					if unit_on(j) == null and passable_for(j, t.owner) and is_land(j):
						spot = j
						break
			if spot >= 0:
				var c := spawn_unit(Defs.U.CHAMPION, spot, t.owner)
				c.fresh = true
			else:
				players[t.owner].gold += 8
	_dirty()
	return r


# ---------------------------------------------------------------- economy

func town_gold_base(t: Town) -> int:
	return t.level + (1 if t.capital else 0) + t.bonus


func connected_towns(p: int) -> Dictionary:
	## Towns linked to the capital by roads (trade routes).
	var out := {}
	var cap := capital_of(p)
	if cap == null:
		return out
	var seen := { cap.idx: true }
	var stack: Array[int] = [cap.idx]
	while not stack.is_empty():
		var a: int = stack.pop_back()
		for b in neighbors(a):
			if seen.has(b) or not has_road(b):
				continue
			seen[b] = true
			stack.append(b)
	for t in towns:
		if t.owner == p and not t.capital and seen.has(t.idx):
			out[t.idx] = true
	return out


func market_value(idx: int) -> int:
	var v := 0
	var p := tile_owner(idx)
	for j in neighbors(idx):
		if tile_owner(j) != p:
			continue
		var b := building[j]
		if b == Defs.B.FARM or b == Defs.B.LUMBER or b == Defs.B.MINE:
			v += 1
	return mini(v, 4)


## Gold per turn, with a breakdown for the UI.
func income(p: int) -> Dictionary:
	var towns_gold := 0
	var trade := connected_towns(p)
	for t in towns:
		if t.owner == p:
			towns_gold += town_gold_base(t)
	var markets := 0
	for i in n_tiles():
		if building[i] == Defs.B.MARKET and tile_owner(i) == p:
			markets += market_value(i)
	var gold := towns_gold + markets + trade.size()
	return { "gold": gold, "towns": towns_gold, "markets": markets, "trade": trade.size() }


func _start_turn(p: int) -> void:
	var pl := players[p]
	pl.gold += income(p)["gold"]
	for u in player_units(p):
		if not u.moved and not u.attacked and not u.fresh:
			var heal := 4 if tile_owner(u.idx) == p else 2
			if town_on(u.idx) != null and town_on(u.idx).owner == p:
				heal = 5
			u.hp = mini(Defs.unit_max_hp(u.type, u.kills), u.hp + heal)
		u.moved = false
		u.attacked = false
		u.fresh = false
	_dirty()
	update_explored(p)


func _towers_fire(p: int) -> void:
	for i in n_tiles():
		if building[i] != Defs.B.TOWER or tile_owner(i) != p:
			continue
		var target: Unit = null
		for j in tiles_in_range(i, Defs.TOWER_RANGE):
			var o := unit_on(j)
			if o != null and o.owner != p and (target == null or o.hp < target.hp):
				target = o
		if target == null:
			continue
		target.hp -= Defs.TOWER_DAMAGE
		var killed := target.hp <= 0
		_log(Ev.TOWER, [p, target.owner, target.type, Defs.TOWER_DAMAGE, 1 if killed else 0])
		if killed:
			_kill(target)


func _bandits_act() -> void:
	for b in units.duplicate():
		if b.owner != -1 or not units.has(b):
			continue
		var target: Unit = null
		for j in neighbors(b.idx):
			var o := unit_on(j)
			if o != null and o.owner >= 0 and (target == null or o.hp < target.hp):
				target = o
		if target == null:
			continue
		var fc := forecast(b, target.idx)
		target.hp -= fc["dmg"]
		var killed := target.hp <= 0
		_log(Ev.BANDIT, [target.owner, target.type, fc["dmg"], 1 if killed else 0])
		if killed:
			_kill(target)
		elif fc["ret"] > 0:
			b.hp -= fc["ret"]
			if b.hp <= 0:
				_kill(b)


func end_turn() -> void:
	if winner >= 0:
		return
	var p := cur
	# a reward left unpicked is taken automatically
	var pend := pending_reward(p)
	while pend != null:
		choose_reward(pend, 0)
		pend = pending_reward(p)
	players[p].seen_seq = seq
	_towers_fire(p)
	_dirty()
	var np := players.size()
	var nxt := p
	for step in range(1, np + 1):
		nxt = (p + step) % np
		if nxt == 0:
			turn += 1
			_bandits_act()
			if mode == Mode.GLORY and turn > turn_limit:
				_glory_end()
				return
		if players[nxt].alive:
			break
	cur = nxt
	_start_turn(cur)


func _glory_end() -> void:
	var best := -1
	var best_score := -1
	for i in players.size():
		if players[i].alive:
			var s := score(i)
			if s > best_score:
				best_score = s
				best = i
	winner = best
	turn = turn_limit
	_log(Ev.WIN, [winner])


func score(p: int) -> int:
	var s := 0
	for t in towns:
		if t.owner == p:
			s += 20 * t.level + (30 if t.capital else 10)
	for u in units:
		if u.owner == p:
			s += 4 + int(Defs.UNITS[u.type]["cost"])
	for i in n_tiles():
		if building[i] != Defs.B.NONE and tile_owner(i) == p:
			s += 4
		if road[i] != 0 and tile_owner(i) == p:
			s += 1
	var ex := 0
	for v in players[p].explored:
		ex += v
	s += ex / 2
	s += players[p].keep * 25
	s += players[p].kills * 6
	return s


# ---------------------------------------------------------------- events

func _log(type: int, args: Array) -> void:
	seq += 1
	var e := [seq, turn, type]
	e.append_array(args)
	events.append(e)
	# prune events everybody has seen
	var min_seen := seq
	for pl in players:
		if pl.alive and not pl.ai:
			min_seen = mini(min_seen, pl.seen_seq)
	while events.size() > 0 and (events[0][0] <= min_seen or events.size() > 60):
		events.pop_front()


func events_since(s: int) -> Array:
	var out: Array = []
	for e in events:
		if e[0] > s:
			out.append(e)
	return out


# ---------------------------------------------------------------- setup

## setup: {players:[{name, color, ai}], size, mode, turn_limit, online, seed}
static func create(setup: Dictionary) -> GameState:
	var gs := GameState.new()
	var rng := RandomNumberGenerator.new()
	gs.map_seed = int(setup.get("seed", randi()))
	rng.seed = gs.map_seed
	var size: Dictionary = Defs.MAP_SIZES[setup.get("size", 0)]
	gs.w = size["w"]
	gs.h = size["h"]
	gs.mode = setup.get("mode", Mode.CONQUEST)
	gs.turn_limit = setup.get("turn_limit", 30)
	gs.online = setup.get("online", false)
	const ALPHA := "abcdefghjkmnpqrstuvwxyz23456789"
	for i in 6:
		gs.game_id += ALPHA[rng.randi_range(0, ALPHA.length() - 1)]
	for ps in setup["players"]:
		var pl := Player.new()
		pl.name = ps["name"]
		pl.color = ps["color"]
		pl.ai = ps.get("ai", false)
		pl.gold = Defs.START_GOLD
		pl.explored.resize(gs.w * gs.h)
		gs.players.append(pl)
	MapGen.generate(gs, rng)
	gs.rebuild_caches()
	for i in gs.towns.size():
		if gs.towns[i].owner >= 0:
			gs.claim_around(i)
			gs.spawn_unit(Defs.U.SPEARMAN, gs.towns[i].idx, gs.towns[i].owner)
	for p in gs.players.size():
		gs.update_explored(p)
	gs._start_turn(0)
	return gs


func clone() -> GameState:
	return Codec.decode_bytes(Codec.encode_bytes(self))
