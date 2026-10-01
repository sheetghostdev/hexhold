extends SceneTree
## Prints a turn link for a mid-game position (AI played both sides).
## godot --headless --script res://tests/make_link.gd -- <turns> <seed> <size>

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
	# for on-screen positions, open the link with ?debug and call window.hexDebug()
	quit()
