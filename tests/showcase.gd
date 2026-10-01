extends SceneTree
## Builds a hand-made position showing off roads, walls, towers and units.
func _init() -> void:
	var gs := GameState.create({ "players": [
		{ "name": "Jonathan", "color": 0 }, { "name": "Nate", "color": 1 }], "size": 0, "seed": 4242, "online": true })
	var p := 0
	var pl := gs.players[p]
	pl.gold = 200; pl.wood = 200; pl.stone = 200; pl.keep = 3
	var cap := gs.capital_of(p)
	# grow the capital
	cap.level = 3
	gs.claim_around(gs.town_at[cap.idx])
	# roads: ring around capital and a spur
	for j in gs.neighbors(cap.idx):
		if gs.road_problem(p, j) == "":
			gs.road[j] = 1
	# wall line two tiles out, with a tower
	var ring := []
	for j in gs.tiles_in_range(cap.idx, 2):
		if gs.dist(j, cap.idx) == 2 and gs.tile_owner(j) == p and gs.terrain[j] != Defs.T.WATER and gs.terrain[j] != Defs.T.MOUNTAIN and not gs.town_at.has(j):
			ring.append(j)
	for k in ring.size():
		var j: int = ring[k]
		gs.building[j] = Defs.B.TOWER if k == 2 else Defs.B.WALL
		gs.bhp[j] = 15 if k == 2 else 10
		if k % 3 == 1:
			gs.road[j] = 1
	# buildings inside
	for j in gs.tiles_in_range(cap.idx, 1):
		if gs.building[j] == Defs.B.NONE and not gs.town_at.has(j):
			match gs.terrain[j]:
				Defs.T.PLAINS: gs.building[j] = Defs.B.FARM
				Defs.T.FOREST: gs.building[j] = Defs.B.LUMBER
				Defs.T.HILLS: gs.building[j] = Defs.B.QUARRY
	# one of every unit
	var spots := []
	for j in gs.tiles_in_range(cap.idx, 2):
		if gs.unit_on(j) == null and gs.passable_for(j, p) and gs.is_land(j):
			spots.append(j)
	for t in [Defs.U.ARCHER, Defs.U.SWORDSMAN, Defs.U.KNIGHT, Defs.U.CATAPULT]:
		if spots.is_empty():
			break
		var u := gs.spawn_unit(t, spots.pop_back(), p)
		if t == Defs.U.KNIGHT:
			u.kills = 3
			u.hp = 12
	gs.update_explored(p)
	print("LINK http://localhost:8060/index.html#g=" + Codec.encode(gs))
	quit()
