extends SceneTree
## Prints a turn link for a mid-game position (AI played both sides), plus
## where things appear on a 412x860 CSS-px phone screen for UI tests.
## godot --headless --script res://tests/make_link.gd -- <turns> <seed> <size>
const CSS_W := 412.0
const CSS_H := 860.0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var turns := int(args[0]) if args.size() > 0 else 12
	var seed := int(args[1]) if args.size() > 1 else 42
	var size := int(args[2]) if args.size() > 2 else 1
	var gs := GameState.create({ "players": [
		{ "name": "Jonathan", "color": 0, "ai": true },
		{ "name": "Nate", "color": 1, "ai": true }], "size": size, "seed": seed, "online": true })
	while gs.turn < turns and gs.winner < 0:
		AIPlayer.play_turn(gs)
		gs.end_turn()
	gs.players[0].ai = false
	gs.players[1].ai = false
	print("LINK http://localhost:8060/index.html#g=" + Codec.encode(gs))
	print("cur=", gs.cur, " turn=", gs.turn, " winner=", gs.winner)
	# camera model (mirrors GameScreen._center_on_home)
	var scale := CSS_W / 720.0
	var vp := Vector2(720, CSS_H / scale)
	var z := clampf(vp.x / (Hex.SIZE * Hex.SQRT3 * 7.5), 0.4, 1.8)
	var cap := gs.capital_of(gs.cur)
	var cam := gs.center(cap.idx) + Vector2(0, 90 / z)
	var a := Hex.offset_to_pixel(0, 0) - Vector2(Hex.SIZE, Hex.SIZE)
	var b := Hex.offset_to_pixel(gs.w - 1, gs.h - 1) + Vector2(Hex.SIZE * 2, Hex.SIZE + 11)
	cam = cam.clamp(a, b)
	var css := func(i: int) -> Vector2:
		return (((gs.center(i) - cam) * z + vp / 2.0) * scale).round()
	for u in gs.player_units(gs.cur):
		var p: Vector2 = css.call(u.idx)
		if p.x < 10 or p.x > CSS_W - 10 or p.y < 60 or p.y > 600:
			continue
		var tg := []
		for t in gs.attack_targets(u):
			tg.append([css.call(t), gs.forecast(u, t)["dmg"]])
		var rc := []
		for r in gs.reachable(u):
			rc.append(css.call(r))
		print("UNIT %s at %s targets=%s reach=%s" % [Defs.UNITS[u.type]["name"], p, tg, rc.slice(0, 4)])
	for i in gs.n_tiles():
		if gs.tile_owner(i) == gs.cur and gs.building[i] == Defs.B.NONE and not gs.town_at.has(i) and gs.terrain[i] == Defs.T.PLAINS:
			var p: Vector2 = css.call(i)
			if p.x > 30 and p.x < CSS_W - 30 and p.y > 80 and p.y < 600:
				print("EMPTY_PLAINS ", p)
	quit()
