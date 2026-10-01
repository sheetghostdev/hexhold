extends SceneTree
## A position one capture away from victory, for testing the game-over flow.
func _init() -> void:
	var gs := GameState.create({ "players": [
		{ "name": "Jonathan", "color": 0 }, { "name": "Nate", "color": 1 }], "size": 0, "seed": 77, "online": true })
	# give the enemy a single town close to our capital
	var old := gs.capital_of(1)
	old.owner = -1
	old.capital = false
	var mine := gs.capital_of(0)
	var enemy_cap: GameState.Town = null
	for t in gs.towns:
		if t.owner == -1 and t != old and (enemy_cap == null or gs.dist(t.idx, mine.idx) < gs.dist(enemy_cap.idx, mine.idx)):
			enemy_cap = t
	enemy_cap.owner = 1
	enemy_cap.capital = true
	for u in gs.player_units(1):
		gs._kill(u)
	var u := gs.spawn_unit(Defs.U.SWORDSMAN, enemy_cap.idx, 0)
	for i in gs.tiles_in_range(enemy_cap.idx, 2):
		gs.players[0].explored[i] = 1
	gs.rebuild_caches()
	# camera centres on our capital, so move the capital marker next to the action:
	# simplest is to print the CSS position relative to that camera.
	var scale := 412.0 / 720.0
	var vp := Vector2(720, 860.0 / scale)
	var z := clampf(vp.x / (Hex.SIZE * Hex.SQRT3 * 7.5), 0.4, 1.8)
	var cam := gs.center(gs.capital_of(0).idx) + Vector2(0, 90 / z)
	var a := Hex.offset_to_pixel(0, 0) - Vector2(Hex.SIZE, Hex.SIZE)
	var b := Hex.offset_to_pixel(gs.w - 1, gs.h - 1) + Vector2(Hex.SIZE * 2, Hex.SIZE + 11)
	cam = cam.clamp(a, b)
	print("UNIT ", (((gs.center(u.idx) - cam) * z + vp / 2.0) * scale).round())
	print("LINK http://localhost:8060/index.html#g=" + Codec.encode(gs))
	quit()
