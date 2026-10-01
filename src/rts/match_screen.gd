class_name MatchScreen
extends Node
## Plays one military match: input, selection, commands to the host,
## and animations for the events that come back.

signal quit_to_menu

var host: MatchHost
var m: MatchState
var me := 0
var board: MatchBoard
var hud: MatchHud
var busy := false

var sel_unit: MatchState.UnitS = null
var sel_building: MatchState.Building = null
var sel_tile := -1
var reach := {}
var targets: Array[int] = []
var build_cat := ""        # open build-menu category on the selected hex
var preview_type := ""     # building being previewed before confirming

var touches := {}
var drag_moved := false
var press_pos := Vector2.ZERO
var pinch_dist := 0.0
var mouse_pan := false
const TAP_SLOP := 14.0


var _debug := false


func _ready() -> void:
	_debug = Net.is_web() and Net._truthy(JavaScriptBridge.eval("location.search.indexOf('debug') >= 0", true))
	if _debug:
		JavaScriptBridge.eval("window.hexDebug = function() { window.__hexDebugReq = true; }", true)
	board = MatchBoard.new()
	add_child(board)
	hud = MatchHud.new()
	add_child(hud)
	hud.setup(self)


func start(state: MatchState, local_player: int) -> void:
	m = state
	host = MatchHost.new(m)
	me = local_player
	board.set_match(m, me)
	var hq := m.hq_of(me)
	board.look_at_tile(hq.idx if hq else m.center, false, m.center)
	hud.refresh_all()
	hud.toast("Your turn! Destroy the enemy Home Base.", UI.ACCENT)


func my_turn() -> bool:
	return m != null and m.cur == me and m.winner < 0 and not busy


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if m == null or hud.has_modal():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 1:
				press_pos = event.position
				drag_moved = false
			elif touches.size() == 2:
				drag_moved = true
				var ps := touches.values()
				pinch_dist = ps[0].distance_to(ps[1])
		else:
			touches.erase(event.index)
			if touches.is_empty() and not drag_moved:
				_tap(board.screen_to_map(event.position))
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
		if touches.size() >= 2:
			var ps := touches.values()
			var d: float = ps[0].distance_to(ps[1])
			if pinch_dist > 0.0:
				board.zoom_at((ps[0] + ps[1]) / 2.0, d / pinch_dist)
			pinch_dist = d
			board.pan(event.position - event.relative / 2.0, event.position)
			return
		if not drag_moved and event.position.distance_to(press_pos) > TAP_SLOP:
			drag_moved = true
		if drag_moved:
			board.pan(event.position - event.relative, event.position)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					board.zoom_at(event.position, 1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					board.zoom_at(event.position, 1.0 / 1.1)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if event.pressed:
					press_pos = event.position
					drag_moved = false
					mouse_pan = true
				else:
					mouse_pan = false
					if not drag_moved and event.button_index == MOUSE_BUTTON_LEFT:
						_tap(board.screen_to_map(event.position))
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and mouse_pan:
		if event.position.distance_to(press_pos) > TAP_SLOP:
			drag_moved = true
		if drag_moved:
			board.pan(event.position - event.relative, event.position)
	elif event is InputEventMagnifyGesture:
		board.zoom_at(event.position, event.factor)


# ---------------------------------------------------------------- selection

func _tap(px: Vector2) -> void:
	if busy:
		return
	var i := board.tile_at(px)
	if i < 0:
		deselect()
		return
	if sel_unit != null and my_turn() and sel_unit.owner == me:
		if targets.has(i):
			do_attack(i)
			return
		if reach.has(i):
			do_move(sel_unit, i)
			return
	var u := m.unit_on(i)
	if u != null and (u.owner == me or (board.seen(i) and board.explored(i))):
		select_unit(u)
		return
	var b := m.building_on(i)
	if b != null and board.explored(i):
		select_building(b)
		return
	select_tile(i)


func _highlights() -> void:
	board.selected = sel_tile
	board.preview_idx = sel_tile if preview_type != "" else -1
	board.preview_type = preview_type
	board.reach = reach
	board.targets = targets
	var info := {}
	if sel_unit != null and m.units.has(sel_unit):
		for t in targets:
			var fc := m.forecast(sel_unit, t)
			info[t] = [fc["dmg"], fc["kill"]]
	board.target_info = info
	board.refresh_overlay()
	hud.show_selection()


func select_unit(u: MatchState.UnitS) -> void:
	build_cat = ""
	preview_type = ""
	Sfx.play("tap")
	sel_unit = u
	sel_building = null
	sel_tile = u.idx
	reach = m.reachable(u) if (my_turn() and u.owner == me) else {}
	targets = m.attack_targets(u) if (my_turn() and u.owner == me) else []
	_highlights()


func select_building(b: MatchState.Building) -> void:
	build_cat = ""
	preview_type = ""
	Sfx.play("tap")
	sel_unit = null
	sel_building = b
	sel_tile = b.idx
	reach = {}
	targets = []
	_highlights()


func select_tile(i: int) -> void:
	if i != sel_tile:
		build_cat = ""
		preview_type = ""
	sel_unit = null
	sel_building = null
	sel_tile = i
	reach = {}
	targets = []
	_highlights()


func deselect() -> void:
	build_cat = ""
	preview_type = ""
	sel_unit = null
	sel_building = null
	sel_tile = -1
	reach = {}
	targets = []
	_highlights()


func reselect() -> void:
	if sel_unit != null and m.units.has(sel_unit):
		select_unit(sel_unit)
	elif sel_building != null and m.buildings.has(sel_building):
		select_building(sel_building)
	elif sel_tile >= 0:
		select_tile(sel_tile)
	else:
		deselect()


# ---------------------------------------------------------------- actions

func _send(cmd: Dictionary) -> Dictionary:
	var res := host.submit(me, cmd)
	if not res["ok"]:
		hud.toast(res["error"], UI.BAD)
		Sfx.play("error")
	return res


func do_move(u: MatchState.UnitS, to: int) -> void:
	var start_px := board.rest_pos(u.idx)
	var res := _send({ "type": "move", "unit": u.id, "to": to })
	if not res["ok"]:
		return
	busy = true
	reach = {}
	targets = []
	board.reach = {}
	board.targets = []
	board.refresh_overlay()
	await _animate_events(res["events"], start_px)
	busy = false
	board.refresh()
	hud.refresh_all()
	select_unit(u)


func do_attack(target: int) -> void:
	var u := sel_unit
	var res := _send({ "type": "attack", "unit": u.id, "target": target })
	if not res["ok"]:
		return
	busy = true
	await _animate_events(res["events"])
	busy = false
	board.refresh()
	hud.refresh_all()
	if m.units.has(u):
		select_unit(u)
	else:
		deselect()
	_check_over()


func do_train(b: MatchState.Building, unit_id: String) -> void:
	var res := _send({ "type": "train", "building": b.id, "unit": unit_id })
	if not res["ok"]:
		return
	Sfx.play("coin")
	board.refresh()
	for e in res["events"]:
		board.burst(m.center_px(e["at"]), board.color_of(me))
	hud.refresh_all()
	select_building(b)


## Build menu: category -> option -> preview -> confirm.
func open_category(cat: String) -> void:
	Sfx.play("tap")
	build_cat = cat
	preview_type = ""
	_highlights()


func preview_build(type: String) -> void:
	Sfx.play("tap")
	preview_type = type
	_highlights()


func build_back() -> void:
	if preview_type != "":
		preview_type = ""
	else:
		build_cat = ""
	_highlights()


func confirm_build() -> void:
	var at := sel_tile
	var res := _send({ "type": "build", "building": preview_type, "at": at })
	if not res["ok"]:
		return
	Sfx.play("coin")
	board.refresh()
	board.burst(m.center_px(at), board.color_of(me))
	hud.refresh_all()
	select_building(m.building_on(at))


func end_turn() -> void:
	if not my_turn():
		return
	deselect()
	busy = true
	Sfx.play("turn")
	host.submit(me, { "type": "end_turn" })
	hud.refresh_all()
	board.refresh()
	var enemy_events := host.run_ai_turns()
	board.refresh()
	busy = false
	hud.refresh_all()
	if _check_over():
		return
	var seen := 0
	for e in enemy_events:
		if e["type"] in ["move", "attack", "spawn", "turret", "destroyed"] and _visible_event(e):
			seen += 1
	hud.toast("Your turn! %s" % ("The enemy moved out of sight." if seen == 0 else "%d enemy actions seen." % seen), UI.ACCENT)


func _visible_event(e: Dictionary) -> bool:
	var v := m.visible_for(me)
	for i in e["at"]:
		if v[i]:
			return true
	return false


func _check_over() -> bool:
	if m.winner >= 0:
		Sfx.play("victory")
		hud.show_game_over()
		return true
	return false


# ---------------------------------------------------------------- animation

## Plays events with the same animations for everyone (used for replays later).
func _animate_events(evs: Array, move_from := Vector2.INF) -> void:
	for e in evs:
		match e["type"]:
			"move":
				var u := m.unit_by_id(e["unit"])
				if u == null:
					continue
				var path: Array = e["path"]
				Sfx.play("move")
				var tw := create_tween()
				board.unit_pos[u] = m.center_px(path[0])
				for k in range(1, path.size()):
					tw.tween_method(func(p: Vector2): board.unit_pos[u] = p, m.center_px(path[k - 1]), m.center_px(path[k]), 0.12)
				await tw.finished
				board.unit_pos.erase(u)
			"attack":
				var u := m.unit_by_id(e["unit"])
				var to := m.center_px(e["target"])
				Sfx.play("attack")
				if u != null:
					var from := board.rest_pos(u.idx)
					var tw := create_tween()
					tw.tween_method(func(p: Vector2): board.unit_pos[u] = p, from, from.lerp(to, 0.4), 0.12)
					tw.tween_method(func(p: Vector2): board.unit_pos[u] = p, from.lerp(to, 0.4), from, 0.16)
					await tw.finished
					board.unit_pos.erase(u)
				board.burst(to, Color("#ff6b5b"))
				board.float_text(to, "-%d" % e["dmg"], Color("#ff6b5b"), e["kill"])
				if e["ret"] > 0 and u != null:
					board.float_text(board.rest_pos(u.idx), "-%d" % e["ret"], Color("#ffb347"))
				if e["kill"]:
					Sfx.play("kill")
			"destroyed":
				board.burst(m.center_px(e["at"][0]), Color("#ffb347"))
				hud.toast("%s destroyed!" % DB.building(e["type"]).name, Color("#ff9b8f"))


## Test-only commands (?debug): {"cheat": n} adds resources, or any
## match command, e.g. {"type":"build","building":"factory","at":42}.
func _debug_cmd(c) -> void:
	if not c is Dictionary:
		return
	if c.has("cheat"):
		m.players[me].alloy += int(c["cheat"])
		m.players[me].fuel += int(c["cheat"])
	elif c.has("build_any"):
		# build on the n-th free hex of your territory
		var n := int(c.get("n", 0))
		for i in m.n_tiles():
			if m.build_problem(me, c["build_any"], i) == "":
				if n == 0:
					_send({ "type": "build", "building": c["build_any"], "at": i })
					break
				n -= 1
	else:
		for k in c:
			if c[k] is float:
				c[k] = int(c[k])
		_send(c)
	board.refresh()
	hud.refresh_all()


## Test hook (?debug in the URL): screen positions of tiles and units.
func _process(_delta: float) -> void:
	if not _debug or m == null:
		return
	var cmd = JavaScriptBridge.eval("window.__hexCmd || ''", true)
	if cmd is String and cmd != "":
		JavaScriptBridge.eval("window.__hexCmd = ''", true)
		_debug_cmd(JSON.parse_string(cmd))
	if not Net._truthy(JavaScriptBridge.eval("!!window.__hexDebugReq", true)):
		return
	JavaScriptBridge.eval("window.__hexDebugReq = false", true)
	var vp := get_viewport().get_visible_rect().size
	var tiles := {}
	for i in m.n_tiles():
		if m.ground[i] != MatchState.Ground.VOID:
			var p := board.cam.unproject_position(board.world(i))
			tiles[str(i)] = [roundi(p.x), roundi(p.y)]
	var us := []
	for u in m.units:
		var tg: Array = []
		var rc: Array = []
		if u.owner == m.cur:
			tg.assign(m.attack_targets(u))
			rc.assign(m.reachable(u).keys())
		us.append({ "type": u.type, "owner": u.owner, "idx": u.idx, "pos": tiles[str(u.idx)], "targets": tg, "reach": rc })
	var land := []
	var terr := m.territory()
	for i in m.n_tiles():
		if terr[i] == me and m.building_on(i) == null and m.obstacle[i] == 0 and m.ground[i] == MatchState.Ground.LAND:
			land.append([i, "Ground"])
	var bl := []
	for b in m.buildings:
		bl.append({ "type": b.type, "owner": b.owner, "pos": tiles[str(b.idx)] })
	var info := { "vp": [vp.x, vp.y], "cur": m.cur, "tiles": tiles, "units": us, "land": land, "towns": [], "buildings": bl }
	JavaScriptBridge.eval("window.hexDebugResult = %s" % JSON.stringify(JSON.stringify(info)), true)
