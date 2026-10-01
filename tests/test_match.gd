extends SceneTree
## Headless checks for the new military ruleset:
## godot --headless --script res://tests/test_match.gd

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	DB.load_all()
	test_data()
	test_setup()
	test_commands()
	test_build()
	test_power()
	test_gather()
	test_ai_games()
	print("ALL MATCH TESTS PASSED" if failures == 0 else "%d MATCH FAILURES" % failures)
	quit(1 if failures > 0 else 0)


func new_match(seed: int, ai := true) -> MatchState:
	return MatchGen.create({ "seed": seed, "players": [
		{ "name": "Blue", "color": 0, "ai": ai }, { "name": "Red", "color": 1, "ai": ai }] })


func test_data() -> void:
	for id in ["rifleman", "sniper", "tank", "engineer"]:
		check(DB.unit(id) != null, "unit data: " + id)
	for id in ["hq", "power_plant", "barracks", "factory", "drill", "turret", "wall"]:
		check(DB.building(id) != null, "building data: " + id)
	check(DB.obstacles.has("trees") and DB.obstacles.has("rocks"), "obstacle data")
	check(DB.rules != null and DB.rules.map_radius > 0, "rules data")


func test_setup() -> void:
	var m := new_match(7)
	var hexes := 0
	for i in m.n_tiles():
		if m.ground[i] != MatchState.Ground.VOID:
			hexes += 1
			check(m.mirror(i) >= 0, "every hex has a mirror twin")
			check(m.ground[i] == m.ground[m.mirror(i)] and m.obstacle[i] == m.obstacle[m.mirror(i)], "map is mirror-symmetric")
	var r := m.radius
	check(hexes == 3 * r * (r + 1) + 1, "hexagon map has %d hexes" % hexes)
	for p in 2:
		var hq := m.hq_of(p)
		check(hq != null, "player %d has a home base" % p)
		var types := []
		for b in m.player_buildings(p):
			types.append(b.type)
			check(m.dist(b.idx, hq.idx) <= 1, "start buildings next to the base")
		check(types.has("power_plant") and types.has("barracks"), "power plant + barracks at start")
		var utypes := []
		for u in m.player_units(p):
			utypes.append(u.type)
		check(utypes.has("engineer") and utypes.has("rifleman"), "starting engineer + rifleman")
		var expect := DB.rules.start_alloy + (DB.rules.hq_income_alloy if p == 0 else 0)
		check(m.players[p].alloy == expect, "starting stockpile (+ first-turn income for player 1)")
	check(m.dist(m.hq_of(0).idx, m.hq_of(1).idx) >= 2 * r - 2, "bases far apart")
	var pw := m.power(0)
	check(pw["supply"] > pw["demand"], "start with enough power")
	check(m.owner_of(m.hq_of(0).idx) == 0, "base is in own territory")


func test_commands() -> void:
	var m := new_match(3, false)
	var rif: MatchState.UnitS = null
	for u in m.player_units(0):
		if u.type == "rifleman":
			rif = u
	var reach := m.reachable(rif)
	check(not reach.is_empty(), "rifleman can move")
	var r1 := m.apply(1, { "type": "end_turn" })
	check(not r1["ok"], "out-of-turn command rejected")
	var to: int = reach.keys()[0]
	var res := m.apply(0, { "type": "move", "unit": rif.id, "to": to })
	check(res["ok"] and rif.idx == to, "move command")
	check(res["events"].size() == 1 and res["events"][0]["type"] == "move", "move event")
	check(not m.apply(0, { "type": "move", "unit": rif.id, "to": to })["ok"], "can't move twice")
	var brk: MatchState.Building = null
	for b in m.player_buildings(0):
		if b.type == "barracks":
			brk = b
	var alloy := m.players[0].alloy
	var tr := m.apply(0, { "type": "train", "building": brk.id, "unit": "rifleman" })
	check(tr["ok"], "train rifleman: " + tr["error"])
	check(m.players[0].alloy == alloy - DB.unit("rifleman").cost_alloy, "training costs alloy")
	check(not m.apply(0, { "type": "train", "building": brk.id, "unit": "tank" })["ok"], "barracks can't train tanks")
	var et := m.apply(0, { "type": "end_turn" })
	check(et["ok"] and m.cur == 1, "end turn passes to player 2")


func test_build() -> void:
	var m := new_match(5, false)
	var terr := m.territory()
	var spot := -1
	var outside := -1
	var blocked := -1
	for i in m.n_tiles():
		if m.ground[i] != MatchState.Ground.LAND:
			continue
		if terr[i] == 0 and m.obstacle[i] == 0 and m.building_on(i) == null and m.unit_on(i) == null and spot < 0:
			spot = i
		if terr[i] == 0 and m.obstacle[i] != 0:
			blocked = i
		if terr[i] != 0 and m.obstacle[i] == 0 and outside < 0:
			outside = i
	check(spot >= 0 and blocked >= 0 and outside >= 0, "found build test hexes")
	check(m.build_problem(0, "turret", outside) == "Outside your territory", "can't build outside territory")
	check(m.build_problem(0, "turret", blocked).begins_with("Clear the"), "must clear obstacles first")
	check(m.build_problem(0, "hq", spot) != "", "can't build a second home base")
	var keep := m.players[0].alloy
	m.players[0].alloy = 1
	check(m.build_problem(0, "factory", spot).begins_with("Need"), "unaffordable building explains why")
	m.players[0].alloy = keep
	var owned_before := 0
	for t in m.territory():
		if t == 0:
			owned_before += 1
	var alloy := m.players[0].alloy
	var res := m.apply(0, { "type": "build", "building": "drill", "at": spot })
	check(res["ok"], "build a drill: " + res["error"])
	check(m.players[0].alloy == alloy - DB.building("drill").cost_alloy, "building costs alloy")
	var b := m.building_on(spot)
	check(b != null and b.build_left == DB.building("drill").build_turns, "construction started")
	check(res["events"][0]["type"] == "build" and res["events"][0]["at"] == [spot], "build event")
	var owned_after := 0
	for t in m.territory():
		if t == 0:
			owned_after += 1
	check(owned_after >= owned_before, "territory grows as you build")
	check(m.power(0)["demand"] == m.power(0, false)["demand"], "unfinished buildings use no power")
	for k in DB.building("drill").build_turns * 2:
		m.apply(m.cur, { "type": "end_turn" })
	check(b.build_left == 0, "construction finishes")


func free_land(m: MatchState, p: int) -> Array[int]:
	var out: Array[int] = []
	var terr := m.territory()
	for i in m.n_tiles():
		if terr[i] == p and m.ground[i] == MatchState.Ground.LAND and m.obstacle[i] == 0 and m.building_on(i) == null and m.unit_on(i) == null:
			out.append(i)
	return out


func test_power() -> void:
	var m := new_match(11, false)
	var spots := free_land(m, 0)
	var pw := m.power(0)
	check(pw["off"].is_empty(), "everything powered at start")
	var fac := m.place_building("factory", spots[0], 0, true)
	var tur := m.place_building("turret", spots[1], 0, true)
	var brk2 := m.place_building("barracks", spots[2], 0, true)
	pw = m.power(0)
	# supply 9 (plant 6 + base 3); demand 2 + 3 + 2 + 2 = 9: still fits
	check(pw["demand"] == 9 and pw["supply"] == 9 and pw["off"].is_empty(), "demand == supply fits: %s" % [pw])
	var drl := m.place_building("drill", spots[3], 0, true)
	pw = m.power(0)
	check(pw["off"].size() == 1 and pw["off"].has(drl.id), "newest building switches off first")
	check(m.powered(fac) and not m.powered(drl), "powered() follows the rule")
	var plant: MatchState.Building = null
	for b in m.player_buildings(0):
		if b.type == "power_plant":
			plant = b
	m._destroy_building(plant, 1)
	pw = m.power(0)
	check(not m.powered(drl) and not m.powered(brk2) and not m.powered(tur), "losing a power plant switches newer buildings off")
	check(pw["supply"] == 3, "home base still makes a little power")
	check(m.train_problem(0, fac, "tank").begins_with("No power"), "unpowered factory can't train")
	var unbuilt := m.place_building("power_plant", free_land(m, 0)[0], 0, false)
	check(m.power(0, true)["supply"] == 9 and m.power(0)["supply"] == 3, "planned power counts construction")
	check(unbuilt.build_left > 0, "power plant under construction")


func test_gather() -> void:
	var m := new_match(13, false)
	var eng: MatchState.UnitS = null
	for u in m.player_units(0):
		if u.type == "engineer":
			eng = u
	# put a rock next to the engineer
	var rock := -1
	for j in m.neighbors(eng.idx):
		if m.ground[j] == MatchState.Ground.LAND and m.unit_on(j) == null and m.building_on(j) == null:
			rock = j
			break
	m.obstacle[rock] = DB.obstacle_index("rocks")
	m.amount[rock] = DB.obstacles["rocks"].amount
	check(m.clear_targets(eng).has(rock), "engineer can clear the rock next to it")
	check(m.build_problem(0, "drill", rock).begins_with("Clear the"), "can't build on rocks")
	var alloy := m.players[0].alloy
	var res := m.apply(0, { "type": "clear", "unit": eng.id, "target": rock })
	check(res["ok"], "clear command: " + res["error"])
	check(eng.task == rock and m.clear_targets(eng).is_empty(), "engineer is busy clearing")
	var turns: int = DB.obstacles["rocks"].clear_turns
	for k in turns:
		check(m.obstacle[rock] != 0, "rock still there before the job is done")
		m.apply(0, { "type": "end_turn" })
		m.apply(1, { "type": "end_turn" })
	check(m.obstacle[rock] == 0, "rock cleared after %d turns" % turns)
	var income: int = DB.rules.hq_income_alloy * turns
	check(m.players[0].alloy == alloy + income + DB.obstacles["rocks"].amount, "clearing pays out the alloy")
	check(m.events.any(func(e): return e["type"] == "cleared"), "cleared event")
	# moving cancels a job
	var tree := -1
	for j in m.neighbors(eng.idx):
		if m.ground[j] == MatchState.Ground.LAND and m.unit_on(j) == null and m.building_on(j) == null and j != rock:
			tree = j
			break
	m.obstacle[tree] = DB.obstacle_index("trees")
	m.amount[tree] = 6
	check(m.apply(0, { "type": "clear", "unit": eng.id, "target": tree })["ok"], "start clearing trees")
	m.apply(0, { "type": "end_turn" })
	m.apply(1, { "type": "end_turn" })
	var reach := m.reachable(eng)
	check(not reach.is_empty(), "busy engineer may still move away")
	m.apply(0, { "type": "move", "unit": eng.id, "to": reach.keys()[0] })
	check(eng.task == -1, "moving cancels clearing")
	# drill pulls 1 per neighbouring obstacle per turn
	m.apply(0, { "type": "end_turn" })
	var spot := -1
	for i in free_land(m, 1):
		var n := 0
		for j in m.neighbors(i):
			if m.obstacle[j] != 0:
				n += 1
		if n > 0:
			spot = i
			break
	if spot >= 0:
		var drl := m.place_building("drill", spot, 1, true)
		var before := 0
		for j in m.neighbors(spot):
			before += m.amount[j]
		m.apply(1, { "type": "end_turn" })
		m.apply(0, { "type": "end_turn" })
		var after := 0
		for j in m.neighbors(spot):
			after += m.amount[j]
		check(after < before, "drill drains neighbouring obstacles (%d -> %d)" % [before, after])
		check(m.events.any(func(e): return e["type"] == "drill" and e["building"] == drl.id), "drill event")
	else:
		check(false, "no drill spot found")
	# engineers build outside territory
	if m.cur == 1:
		m.apply(1, { "type": "end_turn" })
	var out := -1
	for j in m.neighbors(eng.idx):
		if m.owner_of(j) == -1 and m.ground[j] == MatchState.Ground.LAND and m.obstacle[j] == 0 and m.building_on(j) == null and m.unit_on(j) == null:
			out = j
	if out >= 0:
		m.players[0].alloy += 20
		var br := m.apply(0, { "type": "build", "building": "wall", "at": out })
		check(br["ok"], "engineer builds outside territory: " + br["error"])


func test_ai_games() -> void:
	var finished := 0
	for g in 6:
		var m := new_match(100 + g)
		var guard := 0
		while m.winner < 0 and guard < 200:
			MatchAI.play_turn(m)
			m.apply(m.cur, { "type": "end_turn" })
			guard += 1
			for u in m.units:
				check(m.unit_at.get(u.idx) == u, "unit cache consistent")
		if m.winner >= 0:
			finished += 1
		var last: Dictionary = m.events[m.events.size() - 1]
		print("match %d: winner %d (%s) on turn %d, %d events" % [g, m.winner, last.get("reason", "?"), m.turn, m.events.size()])
	check(finished == 6, "every AI match ends")
