class_name MatchState
extends RefCounted
## The authoritative state of one match, and every rule.
##
## Everything a player does is a *command* (Dictionary) passed to apply().
## The match validates it, changes the state and returns *events*.
## Every event lists the hexes it touched ("at"), so the host can later send
## each player only the events they can see (fog of war).

enum Ground { VOID, LAND, WATER }

class PlayerState:
	var name := ""
	var color := 0
	var ai := false
	var alive := true
	var alloy := 0
	var fuel := 0
	var explored := PackedByteArray()
	var seen_seq := 0
	var researched: Array[String] = []
	var research := ""       # upgrade in progress
	var research_left := 0


class Building:
	var id := 0
	var type := ""
	var owner := 0
	var idx := 0
	var hp := 1
	var build_left := 0    # turns until finished (0 = working)

	func def() -> BuildingDef:
		return DB.building(type)


class UnitS:
	var id := 0
	var type := ""
	var owner := 0
	var idx := 0
	var hp := 1
	var moved := false
	var attacked := false
	var fresh := false
	var kills := 0
	var task := -1        # hex an Engineer is clearing (-1 = none)
	var task_left := 0    # turns until the clearing is done

	func def() -> UnitDef:
		return DB.unit(type)


var match_id := ""
var map_seed := 0
var radius := 5
var w := 0
var h := 0
var center := 0
var turn := 1
var cur := 0
var winner := -1
var seq := 0
var next_id := 1

var ground := PackedByteArray()
var obstacle := PackedByteArray()   # DB obstacle index (0 = none)
var amount := PackedByteArray()     # resources left in the obstacle

var players: Array[PlayerState] = []
var buildings: Array[Building] = []
var units: Array[UnitS] = []
var events: Array = []

# caches
var unit_at := {}
var building_at := {}
var _vis := {}
var _terr := PackedInt32Array()
var _terr_ok := false
var _pow := {}


# ---------------------------------------------------------------- geometry

func n_tiles() -> int:
	return w * h


func idx_of(col: int, row: int) -> int:
	if col < 0 or row < 0 or col >= w or row >= h:
		return -1
	return row * w + col


func axial(i: int) -> Vector2i:
	return Hex.offset_to_axial(i % w, i / w)


func idx_from_axial(a: Vector2i) -> int:
	var o := Hex.axial_to_offset(a)
	var i := idx_of(o.x, o.y)
	if i < 0 or ground[i] == Ground.VOID:
		return -1
	return i


func center_px(i: int) -> Vector2:
	return Hex.offset_to_pixel(i % w, i / w)


func neighbors(i: int) -> Array[int]:
	var out: Array[int] = []
	var a := axial(i)
	for d in Hex.AXIAL_DIRS:
		var j := idx_from_axial(a + d)
		if j >= 0:
			out.append(j)
	return out


func dist(a: int, b: int) -> int:
	return Hex.axial_distance(axial(a), axial(b))


func in_range(i: int, r: int) -> Array[int]:
	var out: Array[int] = []
	var c := axial(i)
	for dq in range(-r, r + 1):
		for dr in range(maxi(-r, -dq - r), mini(r, -dq + r) + 1):
			var j := idx_from_axial(c + Vector2i(dq, dr))
			if j >= 0:
				out.append(j)
	return out


## Point reflection through the map centre (the map is mirror-fair).
func mirror(i: int) -> int:
	var c := axial(center)
	return idx_from_axial(c * 2 - axial(i))


# ---------------------------------------------------------------- caches

func dirty() -> void:
	_vis.clear()
	_pow.clear()
	_terr_ok = false


func rebuild_caches() -> void:
	unit_at.clear()
	for u in units:
		unit_at[u.idx] = u
	building_at.clear()
	for b in buildings:
		building_at[b.idx] = b
	dirty()


func unit_on(i: int) -> UnitS:
	return unit_at.get(i)


func building_on(i: int) -> Building:
	return building_at.get(i)


func unit_by_id(id: int) -> UnitS:
	for u in units:
		if u.id == id:
			return u
	return null


func building_by_id(id: int) -> Building:
	for b in buildings:
		if b.id == id:
			return b
	return null


func hq_of(p: int) -> Building:
	for b in buildings:
		if b.owner == p and b.type == "hq":
			return b
	return null


func player_units(p: int) -> Array[UnitS]:
	var out: Array[UnitS] = []
	for u in units:
		if u.owner == p:
			out.append(u)
	return out


func player_buildings(p: int) -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if b.owner == p:
			out.append(b)
	return out


func obstacle_def(i: int) -> ObstacleDef:
	return DB.obstacle_at(obstacle[i])


# ---------------------------------------------------------------- stats

## Research bonus for a unit/building type of player p.
func bonus(p: int, type: String, stat: String) -> float:
	if p < 0 or p >= players.size():
		return 0.0
	var total := 0.0
	var is_unit := DB.unit(type) != null
	for id in players[p].researched:
		var fx: Dictionary = DB.upgrade(id).effects
		total += float(fx.get(type + "." + stat, 0.0))
		if is_unit:
			total += float(fx.get("units." + stat, 0.0))
	return total


## A unit's stat including research (attack, defense, move, attack_range, vision).
func ustat(u: UnitS, stat: String) -> float:
	return float(u.def().get(stat)) + bonus(u.owner, u.type, stat)


func bstat(b: Building, stat: String) -> float:
	return float(b.def().get(stat)) + bonus(b.owner, b.type, stat)


# ---------------------------------------------------------------- territory

## Owner of each hex: the nearest building that covers it wins;
## a tie between two players leaves the hex contested (-1).
func territory() -> PackedInt32Array:
	if _terr_ok:
		return _terr
	_terr = PackedInt32Array()
	_terr.resize(n_tiles())
	_terr.fill(-1)
	var best := PackedInt32Array()
	best.resize(n_tiles())
	best.fill(999)
	for b in buildings:
		var r := b.def().territory
		for j in in_range(b.idx, r):
			var d := dist(b.idx, j)
			if d < best[j]:
				best[j] = d
				_terr[j] = b.owner
			elif d == best[j] and _terr[j] != b.owner:
				_terr[j] = -2  # contested
	for j in n_tiles():
		if _terr[j] == -2:
			_terr[j] = -1
	_terr_ok = true
	return _terr


func owner_of(i: int) -> int:
	return territory()[i]


# ---------------------------------------------------------------- power

## Power for a player: {supply, demand, off}. Finished buildings only.
## Rule: when demand is higher than supply, the NEWEST buildings switch
## off ("off" = {building id: true}) until the rest fits.
## planned = true also counts buildings under construction (for previews).
func power(p: int, planned := false) -> Dictionary:
	if not planned and _pow.has(p):
		return _pow[p]
	var supply := 0
	var demand := 0
	var users: Array[Building] = []
	for b in buildings:
		if b.owner == p and (b.build_left == 0 or planned):
			supply += int(bstat(b, "power_supply"))
			demand += b.def().power_use
			if b.def().power_use > 0:
				users.append(b)
	var off := {}
	var load := demand
	for k in range(users.size() - 1, -1, -1):  # buildings are kept oldest-first
		if load <= supply:
			break
		off[users[k].id] = true
		load -= users[k].def().power_use
	var res := { "supply": supply, "demand": demand, "off": off }
	if not planned:
		_pow[p] = res
	return res


## Finished and supplied with power.
func powered(b: Building) -> bool:
	return b.build_left == 0 and not power(b.owner)["off"].has(b.id)


# ---------------------------------------------------------------- vision

func visible_for(p: int) -> PackedByteArray:
	if _vis.has(p):
		return _vis[p]
	var v := PackedByteArray()
	v.resize(n_tiles())
	if p < 0:
		v.fill(1)
	else:
		for u in units:
			if u.owner == p:
				for j in in_range(u.idx, int(ustat(u, "vision"))):
					v[j] = 1
		for b in buildings:
			if b.owner == p:
				for j in in_range(b.idx, b.def().vision):
					v[j] = 1
		var t := territory()
		for j in n_tiles():
			if t[j] == p:
				v[j] = 1
	_vis[p] = v
	return v


func update_explored(p: int) -> void:
	if p < 0 or p >= players.size():
		return
	var v := visible_for(p)
	var ex := players[p].explored
	for j in n_tiles():
		if v[j]:
			ex[j] = 1
	players[p].explored = ex


# ---------------------------------------------------------------- movement

func passable(i: int, p: int) -> bool:
	if ground[i] != Ground.LAND:
		return false
	var o := obstacle_def(i)
	if o != null and o.blocks_move:
		return false
	if building_on(i) != null:
		return false
	return true


func _adjacent_enemy(i: int, p: int) -> bool:
	for j in neighbors(i):
		var o := unit_on(j)
		if o != null and o.owner != p:
			return true
	return false


## {idx: {"from": idx}} for every hex the unit can end its move on.
func reachable(u: UnitS) -> Dictionary:
	var out := {}
	if u.moved or u.fresh or u.attacked:
		return out
	var pts := int(ustat(u, "move")) * 2
	var best := { u.idx: pts }
	var parent := { u.idx: -1 }
	var open: Array[int] = [u.idx]
	while not open.is_empty():
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
			if not passable(b, u.owner):
				continue
			var occ := unit_on(b)
			if occ != null and occ.owner != u.owner:
				continue
			if rem < 2:
				continue
			var nrem := rem - 2
			if obstacle[b] != 0:
				nrem = 0  # trees slow you down: entering them ends the move
			if _adjacent_enemy(b, u.owner):
				nrem = 0
			if not best.has(b) or best[b] < nrem:
				best[b] = nrem
				parent[b] = a
				open.append(b)
	for k in best:
		if k != u.idx and unit_on(k) == null:
			out[k] = { "from": parent[k] }
	return out


func path_to(reach: Dictionary, start: int, target: int) -> Array[int]:
	var path: Array[int] = []
	var c := target
	var guard := 0
	while c != start and c >= 0 and guard < 100:
		path.push_front(c)
		if not reach.has(c):
			break
		c = reach[c]["from"]
		guard += 1
	path.push_front(start)
	return path


# ---------------------------------------------------------------- combat

func attack_targets(u: UnitS) -> Array[int]:
	var out: Array[int] = []
	var d := u.def()
	if u.attacked or u.fresh or d.attack <= 0.0:
		return out
	var vis := visible_for(u.owner)
	for j in in_range(u.idx, int(ustat(u, "attack_range"))):
		if j == u.idx or not vis[j]:
			continue
		var o := unit_on(j)
		if o != null and o.owner != u.owner:
			out.append(j)
			continue
		var b := building_on(j)
		if b != null and b.owner != u.owner:
			out.append(j)
	return out


func defence_bonus(t: UnitS) -> float:
	var o := obstacle_def(t.idx)
	return o.defense_bonus if o != null else 1.0


## Predicts an attack without changing anything.
func forecast(att: UnitS, target: int) -> Dictionary:
	var ad := att.def()
	var a_atk := ustat(att, "attack")
	var d := unit_on(target)
	if d == null:
		var b := building_on(target)
		var bdmg := maxi(1, int(roundf(a_atk * 1.5 * ad.vs_buildings)))
		return { "kind": "building", "dmg": bdmg, "ret": 0, "kill": bdmg >= b.hp, "ret_kill": false }
	var dd := d.def()
	var d_def := ustat(d, "defense")
	var af := a_atk * (float(att.hp) / ad.hp)
	var df := d_def * (float(d.hp) / dd.hp) * defence_bonus(d)
	var total := af + df
	var dmg := maxi(1, int(roundf(af / total * a_atk * 4.5))) if total > 0.0 else 1
	var kill := dmg >= d.hp
	var ret := 0
	if not kill and dist(att.idx, target) <= int(ustat(d, "attack_range")) and dd.attack > 0.0:
		var df2 := d_def * (float(d.hp - dmg) / dd.hp) * defence_bonus(d)
		ret = int(roundf(df2 / total * d_def * 4.5))
	return { "kind": "unit", "dmg": dmg, "ret": ret, "kill": kill, "ret_kill": ret >= att.hp }


# ---------------------------------------------------------------- commands

## The only way to change a match. Returns {ok, error, events}.
func apply(p: int, cmd: Dictionary) -> Dictionary:
	if winner >= 0:
		return _fail("The match is over")
	if p != cur:
		return _fail("Not your turn")
	var before := events.size()
	var err := ""
	match cmd.get("type", ""):
		"move":
			err = _cmd_move(p, cmd)
		"attack":
			err = _cmd_attack(p, cmd)
		"train":
			err = _cmd_train(p, cmd)
		"build":
			err = _cmd_build(p, cmd)
		"clear":
			err = _cmd_clear(p, cmd)
		"research":
			err = _cmd_research(p, cmd)
		"end_turn":
			err = _cmd_end_turn(p)
		_:
			err = "Unknown command"
	if err != "":
		return _fail(err)
	return { "ok": true, "error": "", "events": events.slice(before) }


func _fail(msg: String) -> Dictionary:
	return { "ok": false, "error": msg, "events": [] }


func _cmd_move(p: int, cmd: Dictionary) -> String:
	var u := unit_by_id(cmd.get("unit", -1))
	if u == null or u.owner != p:
		return "No such unit"
	var to: int = cmd.get("to", -1)
	var reach := reachable(u)
	if not reach.has(to):
		return "Can't move there"
	var path := path_to(reach, u.idx, to)
	u.task = -1
	unit_at.erase(u.idx)
	u.idx = to
	unit_at[to] = u
	u.moved = true
	dirty()
	update_explored(p)
	_event(p, "move", path, { "unit": u.id, "path": path })
	return ""


func _cmd_attack(p: int, cmd: Dictionary) -> String:
	var u := unit_by_id(cmd.get("unit", -1))
	if u == null or u.owner != p:
		return "No such unit"
	var t: int = cmd.get("target", -1)
	if not attack_targets(u).has(t):
		return "Can't attack that"
	var fc := forecast(u, t)
	u.attacked = true
	u.moved = true
	var from := u.idx
	if fc["kind"] == "building":
		var b := building_on(t)
		b.hp -= fc["dmg"]
		_event(p, "attack", [from, t], { "unit": u.id, "target": t, "dmg": fc["dmg"], "ret": 0, "kill": b.hp <= 0 })
		if b.hp <= 0:
			_destroy_building(b, p)
		return ""
	var d := unit_on(t)
	d.hp -= fc["dmg"]
	if d.hp > 0 and fc["ret"] > 0:
		u.hp -= fc["ret"]
	_event(p, "attack", [from, t], { "unit": u.id, "target": t, "dmg": fc["dmg"], "ret": fc["ret"], "kill": d.hp <= 0 })
	if d.hp <= 0:
		_remove_unit(d)
		u.kills += 1
	if u.hp <= 0:
		_remove_unit(u)
	update_explored(p)
	return ""


func train_problem(p: int, b: Building, unit_id: String) -> String:
	if b == null or b.owner != p:
		return "Not your building"
	if b.build_left > 0:
		return "Still under construction"
	if not powered(b):
		return "No power: build a Power Plant"
	if not b.def().trains.has(unit_id):
		return "Can't train that here"
	var d := DB.unit(unit_id)
	if player_units(p).size() >= DB.rules.unit_cap:
		return "Army is full (%d units)" % DB.rules.unit_cap
	if spawn_spot(b) < 0:
		return "No free space next to it"
	return cost_problem(p, d.cost_alloy, d.cost_fuel)


## Free hex next to a building for a new unit (prefers facing the enemy).
func spawn_spot(b: Building) -> int:
	var best := -1
	var best_d := 999
	var enemy_hq := -1
	for o in buildings:
		if o.type == "hq" and o.owner != b.owner:
			enemy_hq = o.idx
	for j in neighbors(b.idx):
		if unit_on(j) != null or not passable(j, b.owner):
			continue
		var d := dist(j, enemy_hq) if enemy_hq >= 0 else 0
		if d < best_d:
			best_d = d
			best = j
	return best


func _cmd_train(p: int, cmd: Dictionary) -> String:
	var b := building_by_id(cmd.get("building", -1))
	var unit_id: String = cmd.get("unit", "")
	var err := train_problem(p, b, unit_id)
	if err != "":
		return err
	var d := DB.unit(unit_id)
	players[p].alloy -= d.cost_alloy
	players[p].fuel -= d.cost_fuel
	var u := spawn_unit(unit_id, spawn_spot(b), p)
	u.fresh = true
	update_explored(p)
	_event(p, "spawn", [u.idx], { "unit": u.id, "what": unit_id, "from": b.idx })
	return ""


## Why a building can't go on hex i right now ("" = it can).
func build_problem(p: int, type: String, i: int) -> String:
	var d := DB.building(type)
	if d == null or not d.buildable:
		return "Can't build that"
	if i < 0 or i >= n_tiles() or ground[i] != Ground.LAND:
		return "Not buildable land"
	var t := owner_of(i)
	if t != p:
		if t >= 0:
			return "Inside enemy territory"
		if builder_for(p, i) == null:
			return "Outside your territory"
	if obstacle[i] != 0:
		return "Clear the %s first" % obstacle_def(i).name.to_lower()
	if building_on(i) != null:
		return "Something is already built here"
	if unit_on(i) != null:
		return "A unit is standing here"
	return cost_problem(p, d.cost_alloy, d.cost_fuel)


## An Engineer next to hex i that can still act this turn (builds outside territory).
func builder_for(p: int, i: int) -> UnitS:
	for j in neighbors(i):
		var u := unit_on(j)
		if u != null and u.owner == p and u.def().abilities.has("build") and not u.attacked and not u.fresh:
			return u
	return null


## Obstacle hexes this Engineer can start clearing right now.
func clear_targets(u: UnitS) -> Array[int]:
	var out: Array[int] = []
	if not u.def().abilities.has("clear") or u.attacked or u.fresh or u.task >= 0:
		return out
	for j in in_range(u.idx, 1):
		if obstacle[j] != 0 and amount[j] > 0 and not _being_cleared(j):
			out.append(j)
	return out


func _being_cleared(i: int) -> bool:
	for u in units:
		if u.task == i:
			return true
	return false


func _cmd_clear(p: int, cmd: Dictionary) -> String:
	var u := unit_by_id(cmd.get("unit", -1))
	if u == null or u.owner != p:
		return "No such unit"
	var t: int = cmd.get("target", -1)
	if not clear_targets(u).has(t):
		return "Can't clear that"
	u.task = t
	u.task_left = obstacle_def(t).clear_turns
	u.moved = true
	u.attacked = true
	_event(p, "clear", [u.idx, t], { "unit": u.id, "target": t, "turns": u.task_left })
	return ""


func research_problem(p: int, id: String) -> String:
	var d := DB.upgrade(id)
	if d == null:
		return "Unknown research"
	var pl := players[p]
	if pl.researched.has(id):
		return "Already researched"
	if pl.research != "":
		return "Busy researching %s" % DB.upgrade(pl.research).name
	if hq_of(p) == null:
		return "You need a Home Base"
	return cost_problem(p, d.cost_alloy, d.cost_fuel)


func _cmd_research(p: int, cmd: Dictionary) -> String:
	var id: String = cmd.get("upgrade", "")
	var err := research_problem(p, id)
	if err != "":
		return err
	var d := DB.upgrade(id)
	var pl := players[p]
	pl.alloy -= d.cost_alloy
	pl.fuel -= d.cost_fuel
	pl.research = id
	pl.research_left = d.turns
	_event(p, "research", [hq_of(p).idx], { "upgrade": id })
	return ""


func cost_problem(p: int, alloy: int, fuel: int) -> String:
	var need := []
	if players[p].alloy < alloy:
		need.append("%d more Alloy" % (alloy - players[p].alloy))
	if players[p].fuel < fuel:
		need.append("%d more Fuel" % (fuel - players[p].fuel))
	return "" if need.is_empty() else "Need " + " and ".join(need)


func _cmd_build(p: int, cmd: Dictionary) -> String:
	var type: String = cmd.get("building", "")
	var i: int = cmd.get("at", -1)
	var err := build_problem(p, type, i)
	if err != "":
		return err
	var d := DB.building(type)
	if owner_of(i) != p:
		var eng := builder_for(p, i)
		eng.moved = true
		eng.attacked = true
		eng.task = -1
	players[p].alloy -= d.cost_alloy
	players[p].fuel -= d.cost_fuel
	var b := place_building(type, i, p, false)
	update_explored(p)
	_event(p, "build", [i], { "building": b.id, "what": type, "owner": p })
	return ""


func _cmd_end_turn(p: int) -> String:
	players[p].seen_seq = seq
	_turrets_fire(p)
	var np := players.size()
	var nxt := p
	for step in range(1, np + 1):
		nxt = (p + step) % np
		if nxt == 0:
			turn += 1
			if turn > DB.rules.turn_limit:
				_decide_by_score()
				return ""
		if players[nxt].alive:
			break
	cur = nxt
	_event(-1, "turn", [], { "player": cur })
	_start_turn(cur)
	return ""


# ---------------------------------------------------------------- turn flow

func _start_turn(p: int) -> void:
	var pl := players[p]
	if hq_of(p) != null:
		pl.alloy += DB.rules.hq_income_alloy
		pl.fuel += DB.rules.hq_income_fuel
	for b in player_buildings(p):
		if b.build_left > 0:
			b.build_left -= 1
			if b.build_left == 0:
				_event(p, "built", [b.idx], { "building": b.id, "what": b.type })
	_work(p)
	if pl.research != "":
		pl.research_left -= 1
		if pl.research_left <= 0:
			var id := pl.research
			pl.research = ""
			pl.researched.append(id)
			var hq := hq_of(p)
			_event(p, "researched", [hq.idx] if hq else [], { "upgrade": id })
	for u in player_units(p):
		if not u.moved and not u.attacked and not u.fresh:
			u.hp = mini(u.def().hp, u.hp + (3 if owner_of(u.idx) == p else 1))
		u.moved = false
		u.attacked = false
		u.fresh = false
	dirty()
	update_explored(p)


## Start-of-turn gathering: Engineers progress their clearing, Drills pull
## 1 from every neighbouring obstacle. Emptied obstacles become open land.
func _work(p: int) -> void:
	for u in player_units(p):
		if u.task < 0:
			continue
		u.task_left -= 1
		if u.task_left > 0:
			continue
		var i := u.task
		u.task = -1
		var o := obstacle_def(i)
		var got := 0
		var res := ""
		if o != null:
			got = amount[i]
			res = o.resource
			_gain(p, res, got)
			_remove_obstacle(i)
		_event(p, "cleared", [u.idx, i], { "unit": u.id, "target": i, "resource": res, "amount": got })
	for b in player_buildings(p):
		if b.type != "drill" or not powered(b):
			continue
		var gain := { "alloy": 0, "fuel": 0 }
		var touched: Array = [b.idx]
		for j in neighbors(b.idx):
			var o := obstacle_def(j)
			if o == null or amount[j] == 0:
				continue
			amount[j] -= 1
			gain[o.resource] += 1
			_gain(p, o.resource, 1)
			if amount[j] == 0:
				_remove_obstacle(j)
				touched.append(j)
		if gain["alloy"] + gain["fuel"] > 0:
			_event(p, "drill", touched, { "building": b.id, "alloy": gain["alloy"], "fuel": gain["fuel"] })


func _gain(p: int, res: String, n: int) -> void:
	if res == "alloy":
		players[p].alloy += n
	elif res == "fuel":
		players[p].fuel += n


func _remove_obstacle(i: int) -> void:
	obstacle[i] = 0
	amount[i] = 0
	dirty()


func _turrets_fire(p: int) -> void:
	for b in player_buildings(p):
		var d := b.def()
		if d.attack <= 0.0 or not powered(b):
			continue
		var target: UnitS = null
		for j in in_range(b.idx, int(bstat(b, "attack_range"))):
			var o := unit_on(j)
			if o != null and o.owner != p and (target == null or o.hp < target.hp):
				target = o
		if target == null:
			continue
		var dmg := int(roundf(bstat(b, "attack")))
		target.hp -= dmg
		_event(p, "turret", [b.idx, target.idx], { "building": b.id, "target": target.idx, "dmg": dmg, "kill": target.hp <= 0 })
		if target.hp <= 0:
			_remove_unit(target)


func _remove_unit(u: UnitS) -> void:
	units.erase(u)
	if unit_at.get(u.idx) == u:
		unit_at.erase(u.idx)
	dirty()


func _destroy_building(b: Building, by: int) -> void:
	buildings.erase(b)
	building_at.erase(b.idx)
	dirty()
	_event(by, "destroyed", [b.idx], { "building": b.id, "what": b.type, "owner": b.owner })
	if b.type == "hq":
		_eliminate(b.owner)


func _eliminate(p: int) -> void:
	players[p].alive = false
	for u in player_units(p):
		_remove_unit(u)
	_event(-1, "eliminated", [], { "player": p })
	var alive := []
	for i in players.size():
		if players[i].alive:
			alive.append(i)
	if alive.size() == 1:
		winner = alive[0]
		_event(-1, "win", [], { "player": winner, "reason": "hq" })


func score(p: int) -> int:
	var s := players[p].alloy + players[p].fuel
	for b in player_buildings(p):
		s += b.def().cost_alloy + b.def().cost_fuel + 10
	for u in player_units(p):
		s += u.def().cost_alloy + u.def().cost_fuel
	return s


func _decide_by_score() -> void:
	var best := -1
	var best_s := -1
	for i in players.size():
		if players[i].alive and score(i) > best_s:
			best_s = score(i)
			best = i
	winner = best
	_event(-1, "win", [], { "player": winner, "reason": "score" })


# ---------------------------------------------------------------- creation

func spawn_unit(type: String, i: int, owner: int) -> UnitS:
	var u := UnitS.new()
	u.id = next_id
	next_id += 1
	u.type = type
	u.idx = i
	u.owner = owner
	u.hp = DB.unit(type).hp
	units.append(u)
	unit_at[i] = u
	dirty()
	return u


func place_building(type: String, i: int, owner: int, finished: bool) -> Building:
	var b := Building.new()
	b.id = next_id
	next_id += 1
	b.type = type
	b.idx = i
	b.owner = owner
	b.hp = DB.building(type).hp
	b.build_left = 0 if finished else DB.building(type).build_turns
	buildings.append(b)
	building_at[i] = b
	obstacle[i] = 0
	amount[i] = 0
	dirty()
	return b


# ---------------------------------------------------------------- events

## Every event records who did it and which hexes it touched (for fog).
func _event(p: int, type: String, at: Array, data: Dictionary) -> void:
	seq += 1
	var e := { "seq": seq, "turn": turn, "p": p, "type": type, "at": at }
	for k in data:
		assert(not e.has(k), "event data may not use the reserved key " + k)
	e.merge(data)
	events.append(e)


func events_since(s: int) -> Array:
	return events.filter(func(e): return e["seq"] > s)
