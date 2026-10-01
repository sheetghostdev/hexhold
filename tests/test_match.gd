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
