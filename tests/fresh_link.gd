extends SceneTree
## A brand-new 2-player game as a link (fixed seed) for UI tests.
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := int(args[0]) if args.size() > 0 else 11
	var gs := GameState.create({ "players": [{ "name": "Jonathan", "color": 0 }, { "name": "Nate", "color": 1 }], "size": 0, "seed": seed, "online": true })
	print("LINK http://localhost:8060/index.html?debug#g=" + Codec.encode(gs))
	quit()
