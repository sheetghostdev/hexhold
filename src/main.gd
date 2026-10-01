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
	var join := _join_code()
	var code := Net.code_from_location()
	if join != "":
		show_menu()
		join_online(join)
	elif code != "":
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
	var join := _join_code()
	if join != "":
		_clear()
		show_menu()
		join_online(join)
		return
	var code := Net.code_from_location()
	if code != "":
		open_code(code)


func _clear() -> void:
	if net:
		net.queue_free()
		net = null
	if link:
		link.queue_free()
		link = null
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
	menu.host_online.connect(host_online)
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
	var l := AiLink.new(MatchGen.create(setup))
	_play_match(l, l.first_sync())


var net: NetPeer
var link: MatchLink


func _play_match(l: MatchLink, first: Dictionary) -> void:
	if menu:
		menu.queue_free()
		menu = null
	if match_screen:
		match_screen.queue_free()
	_hide_backdrop()
	link = l
	if link.get_parent() == null:
		add_child(link)
	match_screen = MatchScreen.new()
	add_child(match_screen)
	match_screen.quit_to_menu.connect(show_menu)
	match_screen.start(link, first)


func _my_name(default: String) -> String:
	return String(Storage.get_setting("my_name", default)).left(16)


## Online: this browser hosts the match and shares an invite link.
func host_online() -> void:
	var code := NetPeer.new_code()
	net = NetPeer.new()
	add_child(net)
	var hl := HostLink.new(net, _my_name("Player 1"))
	add_child(hl)
	link = hl
	var url := Net.base_url() + "#join=" + code
	var v := UI.vbox(16)
	var t := UI.label("Invite a friend", "Title", true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 40)
	v.add_child(t)
	var info := UI.label("Send this link to your friend (Discord works great). The match starts when they open it. Keep this page open.", "", true)
	v.add_child(info)
	var lk := UI.label(url, "Small", true)
	lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lk)
	var state := UI.label("Getting ready...", "Small", true)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.add_theme_color_override("font_color", UI.ACCENT)
	v.add_child(state)
	var share_txt := "Join my Hexhold match! %s" % url
	var share := UI.button("Share invite", func():
		if not Net.share("Hexhold match", share_txt):
			state.text = "Link copied! Paste it in Discord."
		, "PrimaryButton", 84)
	share.disabled = true
	v.add_child(share)
	var copy := UI.button("Copy link", func():
		Net.copy(share_txt)
		state.text = "Link copied! Paste it in Discord."
		, "", 76)
	copy.disabled = true
	v.add_child(copy)
	v.add_child(UI.button("Cancel", func():
		_clear()
		show_menu()
		, "GhostButton", 70))
	menu._modal(v)
	net.ready_to_host.connect(func():
		share.disabled = false
		copy.disabled = false
		state.text = "Waiting for your friend to open the link...")
	net.failed.connect(func(why: String):
		state.text = _net_error(why)
		state.add_theme_color_override("font_color", UI.BAD))
	hl.guest_joined.connect(func(): _play_match(hl, hl.first_sync()))
	net.host(code)


## Online: opened an invite link, connect to the host's browser.
func join_online(code: String) -> void:
	Net.clear_location_code()
	net = NetPeer.new()
	add_child(net)
	var gl := GuestLink.new(net, _my_name("Player 2"))
	add_child(gl)
	link = gl
	var v := UI.vbox(16)
	var state := UI.label("Joining your friend's match...", "", true)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(state)
	v.add_child(UI.button("Cancel", func():
		_clear()
		show_menu()
		, "GhostButton", 70))
	menu._modal(v)
	net.failed.connect(func(why: String):
		state.text = _net_error(why)
		state.add_theme_color_override("font_color", UI.BAD))
	gl.started_first.connect(func(rep: Dictionary): _play_match(gl, rep))
	net.join(code)


func _net_error(why: String) -> String:
	match why:
		"peer-unavailable":
			return "That match isn't open any more. Ask your friend for a new link (their page must stay open)."
		"network-library", "network", "server-error", "socket-error", "socket-closed":
			return "Couldn't reach the internet match service. Check your connection and try again."
		"browser-incompatible":
			return "This browser can't play online. Try Chrome or Safari."
		"unavailable-id":
			return "That invite code is busy. Go back and try again."
	return "Connection problem (%s). Try again." % why


func _join_code() -> String:
	if not Net.is_web():
		return ""
	var h = JavaScriptBridge.eval("window.location.hash || ''", true)
	if h is String and h.begins_with("#join="):
		return h.substr(6).strip_edges().left(12)
	return ""


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
