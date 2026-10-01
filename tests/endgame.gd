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
	print("LINK http://localhost:8060/index.html#g=" + Codec.encode(gs))
	quit()
