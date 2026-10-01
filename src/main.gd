extends Node
## Entry point: the title menu, a match against the computer, or an online
## match (hosting one, or joining from an invite link: .../#join=code).

var menu: Menu
var match_screen: MatchScreen
var backdrop: MatchBoard
var _hash_cb = null
var _t := 0.0


func _ready() -> void:
	get_window().theme = UI.theme()
	RenderingServer.set_default_clear_color(UI.BG)
	add_child(Sfx.new())
	_tune_performance()
	if Net.is_web():
		_hash_cb = JavaScriptBridge.create_callback(_on_hash_change)
		JavaScriptBridge.get_interface("window").addEventListener("hashchange", _hash_cb)
	show_menu()
	var join := _join_code()
	if join != "":
		join_online(join)


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
		show_menu()
		join_online(join)


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


func show_menu() -> void:
	_clear()
	_show_backdrop()
	menu = Menu.new()
	add_child(menu)
	menu.start_match.connect(_on_start_match)
	menu.host_online.connect(host_online)


## A computer-vs-computer battle drifting behind the title screen.
func _show_backdrop() -> void:
	if backdrop:
		return
	var m := MatchGen.create({ "players": [
		{ "name": "A", "color": 0, "ai": true }, { "name": "B", "color": 1, "ai": true }] })
	for k in 9:
		MatchAI.play_turn(m)
		m.apply(m.cur, { "type": "end_turn" })
	backdrop = MatchBoard.new()
	add_child(backdrop)
	move_child(backdrop, 0)
	backdrop.set_match(m, -1)
	backdrop.look_at_tile(m.center)


func _process(delta: float) -> void:
	if backdrop and backdrop.m:
		_t += delta
		var c := backdrop.world(backdrop.m.center)
		backdrop.focus = c + Vector3(sin(_t * 0.12) * 2.5, 0, cos(_t * 0.09) * 1.5)
		backdrop._apply_camera()


func _hide_backdrop() -> void:
	if backdrop:
		backdrop.queue_free()
		backdrop = null


func _on_start_match() -> void:
	var setup := { "players": [
		{ "name": "You", "color": 0 }, { "name": "Enemy AI", "color": 1, "ai": true }] }
	if Net.is_web():
		var sd = JavaScriptBridge.eval("new URLSearchParams(location.search).get('seed') || ''", true)
		if sd is String and sd.is_valid_int():
			setup["seed"] = sd.to_int()
	_clear()
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
