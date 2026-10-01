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
	if Net.is_web():
		_hash_cb = JavaScriptBridge.create_callback(_on_hash_change)
		JavaScriptBridge.get_interface("window").addEventListener("hashchange", _hash_cb)
	var code := Net.code_from_location()
	if code != "":
		open_code(code)
	else:
		show_menu()


func _on_hash_change(_args: Array) -> void:
	var code := Net.code_from_location()
	if code != "":
		open_code(code)


func _clear() -> void:
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
	menu.open_entry.connect(_on_open_entry)
	menu.open_code.connect(open_code)


## A small living kingdom drifting behind the title screen.
func _show_backdrop() -> void:
	if backdrop:
		return
	var gs := GameState.create({ "players": [
		{ "name": "A", "color": 0, "ai": true }, { "name": "B", "color": 1, "ai": true },
		{ "name": "C", "color": 2, "ai": true }], "size": 1, "seed": randi() % 100000 })
	for k in 18:
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
