class_name GameScreen
extends Node
## Runs a match: touch input, camera, actions, undo, animations and the
## hand-off between players (pass & play or links).

signal quit_to_menu

enum Mode { PLAY, BUSY, WAITING, OVER, COVERED }

var gs: GameState
var local := 0           # the player using this device (-1 = unknown)
var mode: int = Mode.PLAY
var board: Board
var hud: Hud

# selection
var sel_unit: GameState.Unit = null
var sel_tile := -1
var sel_town_focus := false  # tile has unit + town: show town instead
var reach := {}
var targets: Array[int] = []
var pending_target := -1

# painting roads / walls
var paint := ""          # "", "road", "wall"
var plan: Array[int] = []

var undo_stack: Array[PackedByteArray] = []

# touch tracking
var touches := {}
var drag_moved := false
var press_pos := Vector2.ZERO
var pinch_dist := 0.0
var painting_drag := false
var mouse_pan := false

const TAP_SLOP := 14.0


var _debug_cb = null


func _ready() -> void:
	if Net.is_web() and Net._truthy(JavaScriptBridge.eval("location.search.indexOf('debug') >= 0", true)):
		_debug_cb = true
		JavaScriptBridge.eval("window.hexDebug = function() { window.__hexDebugReq = true; }", true)
	board = Board.new()
	add_child(board)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)


## Starts showing a game. local_player = whose device this is (-1 unknown).
func start(state: GameState, local_player: int, from_link: bool = false) -> void:
	gs = state
	local = local_player
	undo_stack.clear()
	_clear_selection()
	if not gs.online:
		local = gs.cur
	board.set_state(gs, _viewer())
	_center_on_home()
	if gs.winner >= 0:
		_set_mode(Mode.OVER)
		Sfx.play("victory")
		hud.show_game_over()
		return
	if gs.online:
		if from_link or local < 0:
			_set_mode(Mode.COVERED)
			hud.show_link_arrival()
		elif local == gs.cur:
			_set_mode(Mode.PLAY)
			hud.show_turn_summary()
		else:
			_set_mode(Mode.WAITING)
	else:
		_begin_local_turn()


func _viewer() -> int:
	if gs.online:
		return local if local >= 0 else gs.cur
	return gs.cur


func human_count() -> int:
	var c := 0
	for p in gs.players:
		if not p.ai:
			c += 1
	return c


func _begin_local_turn() -> void:
	if gs.winner >= 0:
		_set_mode(Mode.OVER)
		Sfx.play("victory")
		hud.show_game_over()
		return
	if human_count() > 1:
		_set_mode(Mode.COVERED, true)
		hud.show_pass_device()
	else:
		_set_mode(Mode.PLAY)
		hud.show_turn_summary()


## Called when the current player confirms it's them.
func claim_turn() -> void:
	local = gs.cur
	board.viewer = _viewer()
	board.refresh()
	_center_on_home()
	_set_mode(Mode.PLAY)
	_save()


func _set_mode(m: int, hide_board: bool = false) -> void:
	mode = m
	if m != Mode.PLAY:
		_cancel_paint()
	board.visible = not hide_board
	hud.refresh_all()


func is_my_turn() -> bool:
	return mode == Mode.PLAY and gs.winner < 0 and not gs.players[gs.cur].ai


# ---------------------------------------------------------------- camera

func screen_to_world(s: Vector2) -> Vector2:
	return board.screen_to_map(s)


func _center_on_home() -> void:
	var v := _viewer()
	var target := -1
	if v >= 0 and v < gs.players.size():
		var cap := gs.capital_of(v)
		if cap:
			target = cap.idx
		else:
			var us := gs.player_units(v)
			if not us.is_empty():
				target = us[0].idx
	if target < 0:
		target = gs.idx_of(gs.w / 2, gs.h / 2)
	board.reset_zoom()
	board.look_at_tile(target)


func focus_tile(i: int) -> void:
	board.look_at_tile(i, true)


func _zoom_at(screen: Vector2, factor: float) -> void:
	board.zoom_at(screen, factor)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if gs == null or mode == Mode.COVERED:
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_mouse_motion(event)
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		var mid := get_viewport().get_visible_rect().size / 2.0
		board.pan(mid, mid - event.delta * 12.0)


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		touches[e.index] = e.position
		if touches.size() == 1:
			press_pos = e.position
			drag_moved = false
			painting_drag = paint != "" and is_my_turn()
			if painting_drag:
				_paint_at(screen_to_world(e.position), true)
		elif touches.size() == 2:
			painting_drag = false
			drag_moved = true
			var ps := touches.values()
			pinch_dist = ps[0].distance_to(ps[1])
	else:
		touches.erase(e.index)
		if touches.is_empty():
			if not drag_moved and not painting_drag:
				_tap(screen_to_world(e.position))
			painting_drag = false


func _on_drag(e: InputEventScreenDrag) -> void:
	touches[e.index] = e.position
	if touches.size() >= 2:
		var ps := touches.values()
		var d: float = ps[0].distance_to(ps[1])
		var mid: Vector2 = (ps[0] + ps[1]) / 2.0
		if pinch_dist > 0.0:
			_zoom_at(mid, d / pinch_dist)
		pinch_dist = d
		board.pan(e.position - e.relative / 2.0, e.position)
		return
	if painting_drag:
		_paint_at(screen_to_world(e.position), false)
		return
	if not drag_moved and e.position.distance_to(press_pos) > TAP_SLOP:
		drag_moved = true
	if drag_moved:
		board.pan(e.position - e.relative, e.position)


func _on_mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				_zoom_at(e.position, 1.1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				_zoom_at(e.position, 1.0 / 1.1)
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			mouse_pan = e.pressed
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				press_pos = e.position
				drag_moved = false
				mouse_pan = true
				painting_drag = paint != "" and is_my_turn()
				if painting_drag:
					mouse_pan = false
					_paint_at(screen_to_world(e.position), true)
			else:
				mouse_pan = false
				if not drag_moved and not painting_drag:
					_tap(screen_to_world(e.position))
				painting_drag = false


func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	if painting_drag:
		_paint_at(screen_to_world(e.position), false)
		return
	if mouse_pan:
		if e.position.distance_to(press_pos) > TAP_SLOP:
			drag_moved = true
		if drag_moved:
			board.pan(e.position - e.relative, e.position)


# ---------------------------------------------------------------- selection

func _clear_selection() -> void:
	sel_unit = null
	sel_tile = -1
	sel_town_focus = false
	reach = {}
	targets = []
	pending_target = -1
	_push_highlights()


func _push_highlights() -> void:
	if board == null:
		return
	board.selected = sel_tile
	board.reach = reach
	board.targets = targets
	board.pending_target = pending_target
	board.plan = plan
	board.plan_kind = paint
	board.capture_hint = -1
	if sel_unit != null and gs.units.has(sel_unit) and sel_unit.owner == gs.cur and gs.can_capture(sel_unit):
		board.capture_hint = sel_unit.idx
	var ok := {}
	for i in plan:
		ok[i] = _plan_problem(i) == ""
	board.plan_ok = ok
	board.refresh_overlay()


func _select_unit(u: GameState.Unit) -> void:
	Sfx.play("tap")
	sel_unit = u
	sel_tile = u.idx
	sel_town_focus = false
	pending_target = -1
	if u.owner == gs.cur and is_my_turn():
		reach = gs.reachable(u)
		targets = gs.attack_targets(u)
	else:
		reach = {}
		targets = []
	_push_highlights()
	hud.show_selection()


func _select_tile(i: int, town_focus: bool = false) -> void:
	sel_unit = null
	sel_tile = i
	sel_town_focus = town_focus
	reach = {}
	targets = []
	pending_target = -1
	_push_highlights()
	hud.show_selection()


func reselect() -> void:
	if sel_unit != null and gs.units.has(sel_unit):
		_select_unit(sel_unit)
	elif sel_tile >= 0:
		_select_tile(sel_tile, sel_town_focus)
	else:
		_clear_selection()
		hud.show_selection()


func deselect() -> void:
	_clear_selection()
	hud.show_selection()


func _tap(world: Vector2) -> void:
	if mode == Mode.BUSY:
		return
	var i := board.tile_at(world)
	if i < 0:
		deselect()
		return
	if paint != "":
		_toggle_plan(i)
		return
	if sel_unit != null and is_my_turn() and sel_unit.owner == gs.cur:
		if targets.has(i):
			if pending_target == i:
				do_attack(i)
			else:
				pending_target = i
				_push_highlights()
				hud.show_selection()
			return
		if reach.has(i):
			do_move(sel_unit, i)
			return
	var u := gs.unit_on(i)
	var seen := board.seen(i) and board.explored(i)
	var t := gs.town_on(i)
	if u != null and (seen or u.owner == board.viewer):
		if sel_tile == i and sel_unit == u and t != null:
			_select_tile(i, true)  # second tap: show the town under the unit
			return
		_select_unit(u)
		return
	if sel_tile == i and sel_unit == null and not sel_town_focus:
		deselect()
		return
	_select_tile(i, t != null)


# ---------------------------------------------------------------- actions

func _snapshot() -> void:
	undo_stack.append(Codec.encode_bytes(gs))
	if undo_stack.size() > 30:
		undo_stack.pop_front()


func can_undo() -> bool:
	return is_my_turn() and not undo_stack.is_empty()


func undo() -> void:
	if not can_undo():
		return
	var data: PackedByteArray = undo_stack.pop_back()
	var restored := Codec.decode_bytes(data)
	if restored == null:
		return
	gs = restored
	board.set_state(gs, _viewer())
	_clear_selection()
	hud.show_selection()
	hud.refresh_all()
	_save()


func _after_action(keep_undo: bool = true) -> void:
	if not keep_undo:
		undo_stack.clear()
	board.refresh()
	hud.refresh_all()
	_save()
	if gs.winner >= 0:
		await get_tree().create_timer(0.8).timeout
		_set_mode(Mode.OVER)
		Sfx.play("victory")
		hud.show_game_over()


func do_move(u: GameState.Unit, target: int) -> void:
	if not reach.has(target):
		return
	var path := gs.path_to(reach, u.idx, target)
	_snapshot()
	var feature_before := gs.feature[target]
	mode = Mode.BUSY
	_clear_selection()
	# animate along the path
	board.unit_pos[u] = board.rest_pos(u.idx)
	var notes := gs.move_unit(u, target)
	Sfx.play("move")
	var tw := create_tween()
	for k in range(1, path.size()):
		var a: Vector2 = gs.center(path[k - 1]) if k > 1 else board.unit_pos[u]
		var b: Vector2 = board.rest_pos(path[k]) if k == path.size() - 1 else gs.center(path[k])
		tw.tween_method(func(p: Vector2): board.unit_pos[u] = p, a, b, 0.11)
	await tw.finished
	board.unit_pos.erase(u)
	mode = Mode.PLAY
	Net.vibrate(10)
	for n in notes:
		Sfx.play("coin")
		hud.toast(n["text"], UI.ACCENT)
		board.burst(gs.center(target), Icons.GOLD_C)
	var random_outcome := feature_before == Defs.F.RUIN or feature_before == Defs.F.CAMP
	_after_action(not random_outcome)
	if gs.units.has(u):
		_select_unit(u)


func do_attack(target: int) -> void:
	var u := sel_unit
	if u == null or not targets.has(target):
		return
	var defender := gs.unit_on(target)
	var from := board.rest_pos(u.idx)
	var to := board.rest_pos(target)
	mode = Mode.BUSY
	_clear_selection()
	# lunge
	board.unit_pos[u] = from
	var tw := create_tween()
	var ranged: bool = gs.dist(u.idx, target) > 1
	var reach_pt := from.lerp(to, 0.15 if ranged else 0.45)
	tw.tween_method(func(p: Vector2): board.unit_pos[u] = p, from, reach_pt, 0.12)
	await tw.finished
	var res := gs.attack(u, target)
	Net.vibrate(25)
	Sfx.play("attack")
	if res.is_empty():
		board.unit_pos.erase(u)
		mode = Mode.PLAY
		return
	board.burst(to, Color("#ff6b5b"))
	board.float_text(to, "-%d" % res["dmg"], Color("#ff6b5b"), res["kill"])
	if res.get("ret", 0) > 0 and not res["kill"]:
		board.float_text(from, "-%d" % res["ret"], Color("#ffb347"))
	if res["kill"]:
		Sfx.play("kill")
		hud.toast("%s destroyed!" % ("Structure" if res["kind"] == "structure" else Defs.UNITS[defender.type]["name"]), Color("#ff9b8f"))
	var dest: Vector2 = to if res.get("advanced", false) else from
	var tw2 := create_tween()
	tw2.tween_method(func(p: Vector2): board.unit_pos[u] = p, reach_pt, dest, 0.18)
	await tw2.finished
	board.unit_pos.erase(u)
	mode = Mode.PLAY
	_after_action(false)
	if gs.units.has(u):
		_select_unit(u)


func do_capture() -> void:
	var u := sel_unit
	if u == null or not gs.can_capture(u):
		return
	_snapshot()
	var t := gs.town_on(u.idx)
	gs.capture(u)
	Sfx.play("capture")
	board.burst(gs.center(u.idx), Icons.GOLD_C)
	hud.toast("%s is yours!" % t.name, UI.ACCENT)
	Net.vibrate(30)
	_after_action(true)
	_select_tile(u.idx, true)


func do_recruit(type: int) -> void:
	var t := gs.town_on(sel_tile)
	if t == null:
		return
	_snapshot()
	var u := gs.recruit(t, type)
	if u == null:
		undo_stack.pop_back()
		return
	Sfx.play("coin")
	board.burst(gs.center(t.idx), Defs.player_color(gs.players[gs.cur].color))
	_after_action(true)
	_select_tile(sel_tile, true)


func do_build(b: int) -> void:
	if sel_tile < 0:
		return
	_snapshot()
	if not gs.build(gs.cur, sel_tile, b):
		undo_stack.pop_back()
		return
	Sfx.play("build")
	board.burst(gs.center(sel_tile), Color.WHITE)
	_after_action(true)
	_select_tile(sel_tile)


func do_demolish() -> void:
	_snapshot()
	gs.demolish(gs.cur, sel_tile)
	_after_action(true)
	_select_tile(sel_tile)


func do_fortify() -> void:
	var t := gs.town_on(sel_tile)
	if t == null:
		return
	_snapshot()
	if gs.fortify(t):
		Sfx.play("build")
		board.burst(gs.center(t.idx), Color.WHITE)
	_after_action(true)
	_select_tile(sel_tile, true)


func do_feast() -> void:
	var t := gs.town_on(sel_tile)
	if t == null:
		return
	_snapshot()
	var lvl := t.level
	if gs.feast(t):
		Sfx.play("coin")
		board.burst(gs.center(t.idx), Icons.WHEAT)
		hud.toast("A feast in %s! %s" % [t.name, "It grew to level %d!" % t.level if t.level > lvl else "+%d food" % Defs.FEAST_FOOD], UI.GOOD)
	_after_action(true)
	_select_tile(sel_tile, true)


func do_disband() -> void:
	if sel_unit == null:
		return
	_snapshot()
	gs.disband(sel_unit)
	_after_action(true)
	deselect()


func do_upgrade_keep() -> void:
	_snapshot()
	if gs.upgrade_keep(gs.cur):
		Sfx.play("capture")
		hud.toast("Your keep is now a %s!" % Defs.KEEP_NAMES[gs.players[gs.cur].keep], UI.ACCENT)
		var cap := gs.capital_of(gs.cur)
		if cap:
			board.burst(gs.center(cap.idx), Icons.GOLD_C)
	_after_action(true)


func do_set_tax(t: int) -> void:
	_snapshot()
	gs.players[gs.cur].tax = t
	_after_action(true)


func cancel_attack() -> void:
	pending_target = -1
	_push_highlights()
	hud.show_selection()


# ---------------------------------------------------------------- painting

func start_paint(kind: String) -> void:
	if not is_my_turn():
		return
	_clear_selection()
	paint = kind
	plan.clear()
	_push_highlights()
	hud.refresh_all()


func _cancel_paint() -> void:
	paint = ""
	plan.clear()
	painting_drag = false
	_push_highlights()


func cancel_paint() -> void:
	_cancel_paint()
	hud.refresh_all()


func _plan_problem(i: int) -> String:
	if paint == "road":
		return gs.road_problem(gs.cur, i)
	if paint == "wall":
		var p := gs.build_problem(gs.cur, i, Defs.B.WALL)
		if p.begins_with("Costs"):
			return ""
		return p
	return "?"


var plan_anchor := -1  # last tile touched while dragging (may be a town or old road)


func _is_anchor(i: int) -> bool:
	## Towns and existing roads/walls join a new line without being rebuilt.
	if paint == "road":
		return gs.has_road(i)
	return gs.town_at.has(i) or (gs.building[i] == Defs.B.WALL and gs.tile_owner(i) == gs.cur)


func _paint_at(world: Vector2, first: bool) -> void:
	var i := board.tile_at(world)
	if i < 0:
		return
	if first:
		plan_anchor = -1
	if _is_anchor(i):
		if plan_anchor >= 0 and plan_anchor != i and gs.dist(plan_anchor, i) > 1:
			_fill_line(plan_anchor, i)
		plan_anchor = i
		return
	if plan.has(i):
		# dragging back over the previous tile undoes the last step
		if plan.size() >= 2 and plan[plan.size() - 2] == i:
			plan.pop_back()
			_after_plan_change()
		plan_anchor = i
		return
	var last := plan_anchor
	plan_anchor = i
	if last >= 0 and not first and gs.dist(last, i) > 1:
		_fill_line(last, i)
		return
	plan.append(i)
	_after_plan_change()


## Fast swipes skip tiles: fill the gap with a straight hex line.
func _fill_line(from: int, to: int) -> void:
	for a in Hex.axial_line(gs.axial(from), gs.axial(to)):
		var j := gs.idx_from_axial(a)
		if j >= 0 and j != from and not plan.has(j) and not _is_anchor(j):
			plan.append(j)
	_after_plan_change()


func _toggle_plan(i: int) -> void:
	if plan.has(i):
		plan.erase(i)
	else:
		plan.append(i)
	_after_plan_change()


func _after_plan_change() -> void:
	Net.vibrate(5)
	_push_highlights()
	hud.refresh_bottom()


func plan_cost() -> Array:
	var total := [0, 0, 0]
	for i in plan:
		if _plan_problem(i) != "":
			continue
		var c: Array = gs.road_cost(i) if paint == "road" else Defs.BUILDINGS[Defs.B.WALL]["cost"]
		for k in 3:
			total[k] += c[k]
	return total


func plan_valid_count() -> int:
	var n := 0
	for i in plan:
		if _plan_problem(i) == "":
			n += 1
	return n


func confirm_plan() -> void:
	if plan.is_empty():
		return
	_snapshot()
	var built := 0
	var short := false
	for i in plan:
		if _plan_problem(i) != "":
			continue
		var ok := false
		if paint == "road":
			ok = gs.build_road(gs.cur, i)
		else:
			ok = gs.build(gs.cur, i, Defs.B.WALL)
		if ok:
			built += 1
		else:
			short = true
	if built == 0:
		Sfx.play("error")
		undo_stack.pop_back()
		hud.toast("Not enough resources", UI.BAD)
		return
	hud.toast("Built %d %s%s" % [built, "road" if paint == "road" else "wall", "s" if built > 1 else ""] + (" (ran out of resources)" if short else ""), UI.GOOD)
	Net.vibrate(20)
	Sfx.play("build")
	_cancel_paint()
	_after_action(true)


# ---------------------------------------------------------------- turns

func idle_units() -> int:
	var n := 0
	for u in gs.player_units(gs.cur):
		if not u.moved and not u.attacked and not u.fresh:
			n += 1
	return n


func end_turn() -> void:
	if not is_my_turn():
		return
	_clear_selection()
	mode = Mode.BUSY
	Sfx.play("turn")
	var me := gs.cur
	gs.end_turn()
	# computer players take their turns right away
	var guard := 0
	while gs.winner < 0 and gs.players[gs.cur].ai and guard < 16:
		AIPlayer.play_turn(gs)
		gs.end_turn()
		guard += 1
	undo_stack.clear()
	if gs.winner >= 0:
		_save()
		board.refresh()
		_set_mode(Mode.OVER)
		Sfx.play("victory")
		hud.show_game_over()
		return
	if gs.online and gs.cur != me:
		local = me
		board.viewer = _viewer()
		board.refresh()
		_save()
		_set_mode(Mode.WAITING)
		hud.show_share_turn()
	elif gs.online:
		board.refresh()
		_save()
		_set_mode(Mode.PLAY)
		hud.show_turn_summary()
	else:
		board.viewer = _viewer()
		board.refresh()
		_save()
		_begin_local_turn()


func turn_message() -> String:
	if gs.winner >= 0:
		return "%s won our game of Hexhold after %d turns! See the final map:" % [gs.players[gs.winner].name, gs.turn]
	var who := gs.players[gs.cur].name
	return "Your move in Hexhold, %s! (turn %d)" % [who, gs.turn]


func share_turn() -> void:
	var link := Net.turn_link(Codec.encode(gs))
	var text := turn_message() + "\n" + link
	if Net.share("Hexhold", text):
		hud.toast("Pick Discord in the share menu", UI.ACCENT)
	else:
		hud.toast("Link copied! Paste it in Discord", UI.GOOD)


func copy_turn() -> void:
	var link := Net.turn_link(Codec.encode(gs))
	Net.copy(turn_message() + "\n" + link)
	hud.toast("Link copied! Paste it in Discord", UI.GOOD)


func _save() -> void:
	if gs == null:
		return
	var waiting := gs.online and local != gs.cur
	Storage.save_game(gs, local, waiting)


func leave() -> void:
	_save()
	quit_to_menu.emit()


## Test hook (only with ?debug in the URL): writes screen positions of
## tiles and units to window.hexDebugResult for automated UI tests.
func _process(_delta: float) -> void:
	if _debug_cb != null and gs != null and Net._truthy(JavaScriptBridge.eval("!!window.__hexDebugReq", true)):
		JavaScriptBridge.eval("window.__hexDebugReq = false", true)
		_debug_dump([])


func _debug_dump(_args: Array) -> void:
	var vp := get_viewport().get_visible_rect().size
	var tiles := {}
	for i in gs.n_tiles():
		var p := board.cam.unproject_position(board.world(i))
		tiles[str(i)] = [roundi(p.x), roundi(p.y)]
	var us := []
	for u in gs.units:
		var p := board.cam.unproject_position(board.map_to_world(board.rest_pos(u.idx), board.height(u.idx)))
		var tg := []
		var rc := []
		if u.owner == gs.cur:
			tg = gs.attack_targets(u)
			rc = gs.reachable(u).keys()
		us.append({ "type": Defs.UNITS[u.type]["name"], "owner": u.owner, "idx": u.idx, "pos": [roundi(p.x), roundi(p.y)], "targets": tg, "reach": rc })
	var info := { "vp": [vp.x, vp.y], "cur": gs.cur, "tiles": tiles, "units": us }
	JavaScriptBridge.eval("window.hexDebugResult = %s" % JSON.stringify(JSON.stringify(info)), true)
