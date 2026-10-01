extends Node
## Entry point: shows the menu, or jumps straight into a game when the
## page was opened from a turn link.

var menu: Menu
var game: GameScreen
var _hash_cb = null


func _ready() -> void:
	get_window().theme = UI.theme()
	RenderingServer.set_default_clear_color(UI.BG)
	add_child(Sfx.new())
	_tune_performance()
	if Net.is_web():
		_hash_cb = JavaScriptBridge.create_callback(_on_hash_change)
		JavaScriptBridge.get_interface("window").addEventListener("hashchange", _hash_cb)
	var code := Net.code_from_location()
	if code != "":
		open_code(code)
	else:
		show_menu()


## Sharp phone screens have 3x the pixels: render the 3D world a bit lower
## (the UI stays crisp) so the game stays smooth and battery-friendly.
func _tune_performance() -> void:
	var dpr := 1.0
	if Net.is_web():
		var v = JavaScriptBridge.eval("window.devicePixelRatio || 1", true)
		if v is float or v is int:
			dpr = float(v)
	else:
		dpr = DisplayServer.screen_get_scale()
	if dpr >= 2.5:
		get_viewport().scaling_3d_scale = 0.7
	elif dpr >= 1.75:
		get_viewport().scaling_3d_scale = 0.85


func _on_hash_change(_args: Array) -> void:
	var code := Net.code_from_location()
	if code != "":
		open_code(code)


func _clear() -> void:
	if match_screen:
		match_screen.queue_free()
		match_screen = null
	if menu:
		menu.queue_free()
		menu = null
	if game:
		game.queue_free()
		game = null


var backdrop: Board


func show_menu() -> void:
	_clear()
	_show_backdrop()
	menu = Menu.new()
	add_child(menu)
	menu.start_game.connect(_on_start_game)
	menu.start_match.connect(_on_start_match)
	menu.open_entry.connect(_on_open_entry)
	menu.open_code.connect(open_code)


## A small living kingdom drifting behind the title screen.
func _show_backdrop() -> void:
	if backdrop:
		return
	var gs := GameState.create({ "players": [
		{ "name": "A", "color": 0, "ai": true }, { "name": "B", "color": 1, "ai": true },
		{ "name": "C", "color": 2, "ai": true }], "size": 1, "seed": randi() % 100000 })
	for k in 9:
		AIPlayer.play_turn(gs)
		gs.end_turn()
	backdrop = Board.new()
	add_child(backdrop)
	move_child(backdrop, 0)
	backdrop.set_state(gs, -1)
	backdrop.span = 12.0
	backdrop.drift = true


func _hide_backdrop() -> void:
	if backdrop:
		backdrop.queue_free()
		backdrop = null


func _show_game() -> GameScreen:
	_clear()
	_hide_backdrop()
	game = GameScreen.new()
	add_child(game)
	game.quit_to_menu.connect(show_menu)
	return game


var match_screen: MatchScreen


## The new military game: you against the computer.
func _on_start_match() -> void:
	_clear()
	_hide_backdrop()
	var setup := { "players": [
		{ "name": "You", "color": 0 }, { "name": "Enemy AI", "color": 1, "ai": true }] }
	if Net.is_web():
		var sd = JavaScriptBridge.eval("new URLSearchParams(location.search).get('seed') || ''", true)
		if sd is String and sd.is_valid_int():
			setup["seed"] = sd.to_int()
	var m := MatchGen.create(setup)
	match_screen = MatchScreen.new()
	add_child(match_screen)
	match_screen.quit_to_menu.connect(show_menu)
	match_screen.start(m, 0)


func _on_start_game(gs: GameState, local: int) -> void:
	var g := _show_game()
	g.start(gs, local)
	if gs.online:
		Storage.save_game(gs, local, false)


func _on_open_entry(entry: Dictionary) -> void:
	var gs := Codec.decode(entry.get("code", ""))
	if gs == null:
		menu.show_error("This saved game couldn't be read.")
		return
	_show_game().start(gs, int(entry.get("local", gs.cur)))


func open_code(text: String) -> void:
	var gs := Codec.decode(text)
	Net.clear_location_code()
	if gs == null:
		if menu == null:
			show_menu()
		menu.show_error("That doesn't look like a Hexhold turn link. Make sure you copied the whole thing.")
		return
	var entry := Storage.load_entry(gs.game_id)
	if not entry.is_empty() and int(entry.get("seq", 0)) > gs.seq:
		if menu == null:
			show_menu()
		_older_link_prompt(gs, entry)
		return
	if not entry.is_empty():
		var local := int(entry.get("local", -1))
		if local == gs.cur or (int(entry.get("seq", 0)) == gs.seq):
			_show_game().start(gs, local)
			return
	_show_game().start(gs, -1, true)


func _older_link_prompt(gs: GameState, entry: Dictionary) -> void:
	var v := UI.vbox(16)
	v.add_child(UI.label("This link is older than the game saved on this device (turn %d). Someone may have sent an old link." % int(entry.get("turn", 0)), "", true))
	var newer := UI.button("Open my newer save", func(): _on_open_entry(entry), "PrimaryButton", 80)
	var older := UI.button("Open the old link anyway", func(): _show_game().start(gs, -1, true), "", 76)
	v.add_child(newer)
	v.add_child(older)
	menu._modal(v)
