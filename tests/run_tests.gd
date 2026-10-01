extends SceneTree
## Headless checks: godot --headless --script res://tests/run_tests.gd

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	test_hex()
	test_codec_roundtrip()
	test_rules()
	test_ai_games()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(1 if failures > 0 else 0)


func make_game(np: int, size: int, seed: int) -> GameState:
	var ps := []
	for i in np:
		ps.append({ "name": "P%d" % i, "color": i, "ai": true })
	return GameState.create({ "players": ps, "size": size, "seed": seed, "online": true })


func test_hex() -> void:
	for col in 10:
		for row in 10:
			var a := Hex.offset_to_axial(col, row)
			var o := Hex.axial_to_offset(a)
			check(o == Vector2i(col, row), "offset roundtrip %d,%d" % [col, row])
			var px := Hex.offset_to_pixel(col, row)
			check(Hex.pixel_to_offset(px + Vector2(5, -7)) == Vector2i(col, row), "pixel roundtrip %d,%d" % [col, row])
	var gs := make_game(2, 1, 5)
	for i in gs.n_tiles():
		for j in gs.neighbors(i):
			check(gs.dist(i, j) == 1, "neighbor distance")
			check(gs.center(i).distance_to(gs.center(j)) < Hex.SIZE * 1.8, "neighbor pixel distance")


func test_codec_roundtrip() -> void:
	var gs := make_game(3, 1, 1234)
	var code := Codec.encode(gs)
	var back := Codec.decode("https://example.com/hexhold/#g=" + code)
	check(back != null, "decode link")
	if back == null:
		return
	check(Codec.encode(back) == code, "re-encode identical")
	check(back.towns.size() == gs.towns.size(), "towns preserved")
	check(back.units.size() == gs.units.size(), "units preserved")
	check(back.players[1].name == "P1", "names preserved")
	print("fresh game code length: ", code.length())


func test_rules() -> void:
	var gs := make_game(2, 1, 99)
	check(gs.towns.size() >= 4, "has villages (%d towns)" % gs.towns.size())
	var cap0 := gs.capital_of(0)
	var cap1 := gs.capital_of(1)
	check(cap0 != null and cap1 != null, "capitals exist")
	check(gs.dist(cap0.idx, cap1.idx) >= 4, "capitals apart")
	var u := gs.unit_on(cap0.idx)
	check(u != null and u.owner == 0, "starting unit")
	var reach := gs.reachable(u)
	check(not reach.is_empty(), "unit can move")
	# road travel doubles movement
	var gs2 := make_game(2, 1, 7)
	var cap := gs2.capital_of(0)
	var su := gs2.unit_on(cap.idx)
	var before := gs2.reachable(su).size()
	for j in gs2.tiles_in_range(cap.idx, 2):
		if gs2.terrain[j] != Defs.T.MOUNTAIN and gs2.terrain[j] != Defs.T.WATER:
			gs2.road[j] = 1
	var after := gs2.reachable(su).size()
	check(after > before, "roads extend movement (%d -> %d)" % [before, after])
	# income positive
	var inc := gs.income(0)
	check(inc["gold"] > 0, "gold income")
	# building
	var built := false
	for i in gs.n_tiles():
		if gs.tile_owner(i) == 0 and gs.terrain[i] == Defs.T.PLAINS and gs.build_problem(0, i, Defs.B.FARM) == "":
			check(gs.build(0, i, Defs.B.FARM), "build farm")
			built = true
			break
	check(built, "found farm spot")


func test_ai_games() -> void:
	var max_len := 0
	var wins := 0
	for g in 6:
		var np := 2 + g % 3
		var gs := make_game(np, g % 3, 1000 + g)
		var safety := 0
		while gs.winner < 0 and gs.turn <= 60 and safety < 2000:
			AIPlayer.play_turn(gs)
			gs.end_turn()
			safety += 1
			if gs.cur == 0 and (gs.turn == 10 or gs.turn == 20 or gs.turn == 30):
				var st := []
				for p in gs.players.size():
					var inc := gs.income(p)
					st.append("P%d g%d(+%d) w%d(+%d) s%d u%d t%d k%d" % [p, gs.players[p].gold, inc["gold"], gs.players[p].wood, inc["wood"], gs.players[p].stone, gs.player_units(p).size(), gs.player_towns(p).size(), gs.players[p].keep])
				print("   turn %d: %s" % [gs.turn, " | ".join(st)])
			if safety % 7 == 0:
				var code := Codec.encode(gs)
				max_len = maxi(max_len, code.length())
				var back := Codec.decode(code)
				check(back != null and Codec.encode(back) == code, "mid-game roundtrip")
			# invariants
			for u in gs.units:
				check(gs.unit_at.get(u.idx) == u, "unit cache consistent")
				check(u.hp > 0, "no dead units on board")
		if gs.winner >= 0:
			wins += 1
		var summary := []
		for p in gs.players.size():
			summary.append("%s towns=%d units=%d keep=%d score=%d" % [gs.players[p].name, gs.player_towns(p).size(), gs.player_units(p).size(), gs.players[p].keep, gs.score(p)])
		print("game %d (%dp size %d): turn %d winner %d | %s" % [g, np, g % 3, gs.turn, gs.winner, " ; ".join(summary)])
	print("longest code: ", max_len, " chars; decisive games: ", wins, "/6")
	check(max_len < 1800, "codes fit in a Discord message")
