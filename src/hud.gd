class_name Hud
extends CanvasLayer
## All in-game UI: resource bar, context card, toolbar and pop-ups.

var s: GameScreen
var root: Control
var top_bar: PanelContainer
var name_label: Label
var sub_label: Label
var res := {}       # kind -> [amount Label, income Label]
var card_wrap: MarginContainer
var card: PanelContainer
var card_box: VBoxContainer
var bottom_wrap: MarginContainer
var bottom: PanelContainer
var bottom_box: VBoxContainer
var toasts: VBoxContainer
var modal_root: Control


func setup(screen: GameScreen) -> void:
	s = screen
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	add_child(root)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	root.add_child(col)

	_build_top_bar()
	col.add_child(top_bar)

	toasts = UI.vbox(8)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	var tm := UI.margin(toasts, 14)
	tm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tm)

	var sp := UI.spacer()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp)

	card = PanelContainer.new()
	card_box = UI.vbox(12)
	card.add_child(card_box)
	card_wrap = UI.margin(card, 10)
	card_wrap.add_theme_constant_override("margin_bottom", 6)
	col.add_child(card_wrap)
	card_wrap.visible = false

	bottom = PanelContainer.new()
	bottom.theme_type_variation = "Bar"
	bottom_box = UI.vbox(10)
	bottom.add_child(bottom_box)
	bottom_wrap = UI.margin(bottom, 0)
	col.add_child(bottom_wrap)

	modal_root = Control.new()
	modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(modal_root)

	get_viewport().size_changed.connect(_on_resize)
	_on_resize()


func _on_resize() -> void:
	var w := root.get_viewport_rect().size.x
	var side := maxi(10, int((w - 760) / 2))
	card_wrap.add_theme_constant_override("margin_left", side)
	card_wrap.add_theme_constant_override("margin_right", side)
	var bside := maxi(0, int((w - 900) / 2))
	bottom_wrap.add_theme_constant_override("margin_left", bside)
	bottom_wrap.add_theme_constant_override("margin_right", bside)


# ---------------------------------------------------------------- top bar

func _build_top_bar() -> void:
	top_bar = PanelContainer.new()
	top_bar.theme_type_variation = "Bar"
	var row := UI.hbox(10)
	top_bar.add_child(row)
	var menu := _icon_only_button("menu", _show_menu)
	row.add_child(menu)
	var names := UI.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label = UI.label("")
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub_label = UI.label("", "Small")
	sub_label.clip_text = true
	names.add_child(name_label)
	names.add_child(sub_label)
	row.add_child(names)
	for kind in ["gold", "wood", "stone"]:
		var chip := UI.hbox(4)
		chip.add_child(IconRect.make(kind, 36))
		var v := UI.vbox(-6)
		var amt := UI.label("0")
		amt.add_theme_font_size_override("font_size", 26)
		var inc := UI.label("", "Small")
		inc.add_theme_font_size_override("font_size", 17)
		inc.add_theme_color_override("font_color", UI.GOOD)
		v.add_child(amt)
		v.add_child(inc)
		chip.add_child(v)
		chip.custom_minimum_size.x = 92
		row.add_child(chip)
		res[kind] = [amt, inc]


func _icon_only_button(kind: String, cb: Callable, variant: String = "GhostButton") -> Button:
	var b := UI.button("", cb, variant, 64)
	b.custom_minimum_size.x = 64
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(IconRect.make(kind, 34, 0, UI.TEXT))
	b.add_child(cc)
	return b


func _tool_button(kind: String, text: String, cb: Callable, variant: String = "") -> Button:
	var b := UI.button("", cb, variant, 96)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.x = 80
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := IconRect.make(kind, 40, 0, Color("#2a1d05") if variant == "PrimaryButton" else UI.TEXT)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := UI.label(text)
	l.add_theme_font_size_override("font_size", 19)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if variant == "PrimaryButton":
		l.add_theme_color_override("font_color", Color("#2a1d05"))
	v.add_child(l)
	b.add_child(v)
	return b


func refresh_all() -> void:
	if s.gs == null:
		return
	_refresh_top()
	refresh_bottom()
	show_selection()


func _refresh_top() -> void:
	var gs := s.gs
	var v := s._viewer()
	var me := gs.players[gs.cur]
	var shown := v if v >= 0 else gs.cur
	var pl := gs.players[shown]
	name_label.text = pl.name if shown == gs.cur else "%s (waiting)" % pl.name
	name_label.add_theme_color_override("font_color", Defs.player_color(pl.color).lightened(0.25))
	var sub := "Turn %d" % gs.turn
	if gs.mode == GameState.Mode.GLORY:
		sub += " of %d" % gs.turn_limit
	sub += " · " + Defs.KEEP_NAMES[pl.keep]
	sub_label.text = sub
	var inc := gs.income(shown)
	res["gold"][0].text = str(pl.gold)
	res["wood"][0].text = str(pl.wood)
	res["stone"][0].text = str(pl.stone)
	res["gold"][1].text = ("+%d" if inc["gold"] >= 0 else "%d") % inc["gold"]
	res["gold"][1].add_theme_color_override("font_color", UI.GOOD if inc["gold"] >= 0 else UI.BAD)
	res["wood"][1].text = "+%d" % inc["wood"]
	res["stone"][1].text = "+%d" % inc["stone"]


# ---------------------------------------------------------------- bottom bar

func refresh_bottom() -> void:
	for c in bottom_box.get_children():
		c.queue_free()
	var gs := s.gs
	if s.mode == GameScreen.Mode.WAITING:
		var who := gs.players[gs.cur]
		var t := UI.label("Waiting for %s…" % who.name, "Heading")
		t.add_theme_font_size_override("font_size", 26)
		t.add_theme_color_override("font_color", Defs.player_color(who.color).lightened(0.3))
		bottom_box.add_child(t)
		var row := UI.hbox(10)
		var share := UI.button("Send turn link", s.share_turn, "PrimaryButton", 84)
		share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(share)
		row.add_child(UI.button("Menu", s.leave, "", 84))
		bottom_box.add_child(row)
		return
	if s.mode == GameScreen.Mode.OVER:
		var row := UI.hbox(10)
		var res_b := UI.button("Results", show_game_over, "PrimaryButton", 84)
		res_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(res_b)
		row.add_child(UI.button("Menu", s.leave, "", 84))
		bottom_box.add_child(row)
		return
	if s.paint != "":
		var hint := "Drag across tiles to draw a %s. Tap a tile to add or remove it." % ("road" if s.paint == "road" else "wall")
		var l := UI.label(hint, "Small", true)
		bottom_box.add_child(l)
		var row := UI.hbox(10)
		row.add_child(UI.button("Cancel", s.cancel_paint, "", 84))
		var n := s.plan_valid_count()
		var cost := s.plan_cost()
		var label := "Build %d %s" % [n, "tile" if n == 1 else "tiles"]
		if n > 0:
			label += " · " + Defs.cost_text(cost)
		var b := UI.button(label, s.confirm_plan, "PrimaryButton", 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = n == 0
		if n > 0 and not gs.can_afford(gs.cur, cost):
			b.text = label + " (short)"
		row.add_child(b)
		bottom_box.add_child(row)
		return
	var row := UI.hbox(8)
	var playing := s.is_my_turn()
	var road := _tool_button("road", "Road", s.start_paint.bind("road"))
	var wall := _tool_button("walls", "Wall", s.start_paint.bind("wall"))
	var kingdom := _tool_button("castle", "Kingdom", show_kingdom)
	var undo := _tool_button("undo", "Undo", s.undo)
	var idle := s.idle_units() if playing else 0
	var end := _tool_button("next", "End turn" if idle == 0 else "End (%d idle)" % idle, _confirm_end_turn, "PrimaryButton")
	end.size_flags_stretch_ratio = 1.4
	road.disabled = not playing
	wall.disabled = not playing
	undo.disabled = not s.can_undo()
	end.disabled = not playing
	for b in [road, wall, kingdom, undo, end]:
		row.add_child(b)
	bottom_box.add_child(row)


func _confirm_end_turn() -> void:
	if not s.is_my_turn():
		return
	var idle := s.idle_units()
	if idle > 0:
		confirm("%d of your units haven't done anything this turn. End your turn anyway?" % idle, "End turn", s.end_turn)
	else:
		s.end_turn()


# ---------------------------------------------------------------- context card

func show_selection() -> void:
	for c in card_box.get_children():
		c.queue_free()
	var gs := s.gs
	if gs == null or s.mode == GameScreen.Mode.COVERED or s.paint != "":
		card_wrap.visible = false
		return
	var i := s.sel_tile
	if i < 0:
		card_wrap.visible = false
		return
	card_wrap.visible = true
	if not s.board.explored(i):
		_card_header("terrain", 0, "Unexplored", "Send a unit to scout this area.")
		return
	var u := s.sel_unit
	if u != null and gs.units.has(u) and not s.sel_town_focus:
		_unit_card(u)
		return
	var t := gs.town_on(i)
	if t != null:
		_town_card(t)
		return
	_tile_card(i)


func _card_header(kind: String, id: int, title: String, sub: String, col: Color = Color.WHITE) -> HBoxContainer:
	var row := UI.hbox(14)
	row.add_child(IconRect.make(kind, 64, id, col))
	var v := UI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UI.label(title, "Heading")
	t.add_theme_font_size_override("font_size", 28)
	v.add_child(t)
	if sub != "":
		var l := UI.rich(sub)
		l.add_theme_font_size_override("normal_font_size", 21)
		l.add_theme_color_override("default_color", UI.MUTED)
		v.add_child(l)
	row.add_child(v)
	var close := UI.button("×", s.deselect, "GhostButton", 56)
	close.custom_minimum_size.x = 56
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(close)
	card_box.add_child(row)
	return row


func _owner_name(p: int) -> String:
	if p < 0:
		return "Neutral"
	var pl := s.gs.players[p]
	return "[color=%s]%s[/color]" % [UI.color_hex(Defs.player_color(pl.color).lightened(0.25)), pl.name]


func _unit_card(u: GameState.Unit) -> void:
	var gs := s.gs
	var d: Dictionary = Defs.UNITS[u.type]
	var col := Defs.BANDIT_COLOR if u.owner < 0 else Defs.player_color(gs.players[u.owner].color)
	var maxhp := Defs.unit_max_hp(u.type, u.kills)
	var title: String = d["name"] + ("  · Veteran" if u.kills >= Defs.VETERAN_KILLS else "")
	var sub := "%s · [color=#7bd389]%d/%d hp[/color] · atk %s · def %s · move %d · range %d" % [
		_owner_name(u.owner) if u.owner >= 0 else "Bandits", u.hp, maxhp, str(d["atk"]), str(d["def"]), d["move"], gs.unit_range(u)]
	_card_header("unit", u.type, title, sub, col)
	var mine := u.owner == gs.cur and s.is_my_turn()
	if not mine:
		var info := UI.rich("[color=#9fb0bf]%s[/color]" % d["desc"])
		info.add_theme_font_size_override("normal_font_size", 21)
		card_box.add_child(info)
		return
	# Pending attack forecast
	if s.pending_target >= 0:
		var fc := gs.forecast(u, s.pending_target)
		var txt := ""
		if fc["kind"] == "structure":
			txt = "Smash the %s for [color=#ff7b72]%d[/color] damage%s." % [
				Defs.BUILDINGS[gs.building[s.pending_target]]["name"].to_lower(), fc["dmg"], " — [b]destroys it![/b]" if fc["kill"] else ""]
		else:
			var tgt := gs.unit_on(s.pending_target)
			txt = "Hit the %s for [color=#ff7b72]%d[/color]%s" % [Defs.UNITS[tgt.type]["name"], fc["dmg"], " — [b]defeats it![/b]" if fc["kill"] else "."]
			if fc["ret"] > 0:
				txt += "  It strikes back for [color=#ffb347]%d[/color]%s." % [fc["ret"], " (you'd lose this unit!)" if fc["ret_kill"] else ""]
			elif not fc["kill"]:
				txt += "  No counterattack."
		var r := UI.rich(txt)
		r.add_theme_font_size_override("normal_font_size", 23)
		r.add_theme_font_size_override("bold_font_size", 23)
		card_box.add_child(r)
		var row := UI.hbox(10)
		row.add_child(UI.button("Cancel", s.cancel_attack, "", 80))
		var atk := UI.button("Attack!", s.do_attack.bind(s.pending_target), "DangerButton", 80)
		atk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(atk)
		card_box.add_child(row)
		return
	var status := ""
	if u.fresh:
		status = "Just recruited, ready next turn."
	elif u.attacked:
		status = "Done for this turn."
	elif u.moved:
		status = "Moved. Can still attack a red target." if not s.targets.is_empty() else "Moved this turn."
	else:
		status = "Tap a white dot to move" + (", or a red ring to attack." if not s.targets.is_empty() else ".")
	var st := UI.label(status, "Small", true)
	card_box.add_child(st)
	var row := UI.hbox(10)
	if gs.can_capture(u):
		var t := gs.town_on(u.idx)
		var cap := UI.button("Capture %s" % t.name, s.do_capture, "PrimaryButton", 80)
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cap)
	elif gs.town_on(u.idx) != null and gs.town_on(u.idx).owner != u.owner and gs.town_on(u.idx).owner >= 0:
		var l := UI.label("Stay here: you can capture next turn.", "Small", true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
	var t2 := gs.town_on(u.idx)
	if t2 != null and t2.owner == gs.cur:
		row.add_child(UI.button("Town", func(): s._select_tile(u.idx, true), "", 80))
	row.add_child(UI.button("Disband", func(): confirm("Disband this %s?" % d["name"], "Disband", s.do_disband), "GhostButton", 80))
	card_box.add_child(row)


func _town_card(t: GameState.Town) -> void:
	var gs := s.gs
	var col := Defs.player_color(gs.players[t.owner].color) if t.owner >= 0 else Defs.NEUTRAL_COLOR
	var title := t.name + ("  · Capital" if t.capital else "")
	var sub := "%s · level %d" % [_owner_name(t.owner), t.level]
	if t.walls:
		sub += " · walled"
	_card_header("town", 0, title, sub, col)
	var ti: int = gs.town_at[t.idx]
	if t.owner != gs.cur or not s.is_my_turn():
		var msg := "Move a unit here to claim this village." if t.owner < 0 else "To capture, start your turn with a unit standing here."
		if t.owner == gs.cur:
			msg = ""
		if msg != "":
			card_box.add_child(UI.label(msg, "Small", true))
		return
	var inc := gs.income(gs.cur)
	var food_in: int = inc["food"].get(ti, 0)
	var need := gs.food_need(t.level)
	var linked := gs.connected_towns(gs.cur).has(t.idx)
	var info := "[color=#e8c766]Food %d/%d[/color] (+%d/turn)" % [t.food, need, food_in] if t.level < Defs.MAX_TOWN_LEVEL else "[color=#e8c766]Max level[/color]"
	info += " · [color=#f6c445]%d gold[/color]" % (gs.town_gold_base(t) + (1 if linked else 0))
	if not t.capital:
		info += " · " + ("[color=#7bd389]trade route linked[/color]" if linked else "[color=#9fb0bf]no road to capital[/color]")
	info += " · army %d/%d" % [gs.player_units(gs.cur).size(), gs.unit_cap(gs.cur)]
	var r := UI.rich(info)
	r.add_theme_font_size_override("normal_font_size", 21)
	card_box.add_child(r)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var pl := gs.players[gs.cur]
	for type in [Defs.U.SPEARMAN, Defs.U.ARCHER, Defs.U.SWORDSMAN, Defs.U.KNIGHT, Defs.U.CATAPULT]:
		var d: Dictionary = Defs.UNITS[type]
		var prob := gs.recruit_problem(t, type)
		var b := _option_button("unit", type, d["name"], d["cost"], prob, s.do_recruit.bind(type), Defs.player_color(pl.color))
		if pl.keep < d["keep"]:
			b.tooltip_text = "Requires " + Defs.KEEP_NAMES[d["keep"]]
		grid.add_child(b)
	if not t.walls:
		var prob := gs.fortify_problem(t)
		grid.add_child(_option_button("walls", 0, "Town walls", Defs.TOWN_WALL_COST, prob, s.do_fortify, Color.WHITE))
	if t.level < Defs.MAX_TOWN_LEVEL:
		var fprob := gs.feast_problem(t)
		grid.add_child(_option_button("food", 0, "Feast +%d food" % Defs.FEAST_FOOD, gs.feast_cost(t), fprob, s.do_feast, Color.WHITE))
	card_box.add_child(grid)


## A compact grid button: icon, name, cost (cost goes red when unaffordable).
func _option_button(kind: String, id: int, title: String, cost: Array, problem: String, cb: Callable, col: Color) -> Button:
	var b := UI.button("", cb, "", 112)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.x = 150
	b.disabled = problem != ""
	var v := UI.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := IconRect.make(kind, 42, id, col)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := UI.label(title)
	l.add_theme_font_size_override("font_size", 19)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var have := [s.gs.players[s.gs.cur].gold, s.gs.players[s.gs.cur].wood, s.gs.players[s.gs.cur].stone]
	var cl := UI.rich("[center]%s[/center]" % UI.cost_bb(cost, have))
	cl.add_theme_font_size_override("normal_font_size", 16)
	if problem != "" and not problem.begins_with("Costs"):
		cl.text = "[center][color=#9fb0bf]%s[/color][/center]" % problem.replace("Requires ", "")
	v.add_child(cl)
	b.add_child(v)
	if b.disabled:
		b.modulate = Color(1, 1, 1, 0.75)
	return b


func _tile_card(i: int) -> void:
	var gs := s.gs
	var ter := gs.terrain[i]
	var f := gs.feature[i]
	var title: String = Defs.TERRAIN_NAMES[ter]
	var b := gs.building[i]
	if b != Defs.B.NONE:
		title = Defs.BUILDINGS[b]["name"]
	var owner := gs.tile_owner(i)
	var sub := _owner_name(owner) if owner >= 0 else "No-man's land"
	if f != Defs.F.NONE:
		sub += " · " + Defs.FEATURE_NAMES[f]
	if b != Defs.B.NONE:
		sub += " · " + Defs.TERRAIN_NAMES[ter]
		var y := gs.building_yield(i)
		var parts := PackedStringArray()
		if y[0] > 0:
			parts.append("[color=#f6c445]+%d gold[/color]" % y[0])
		if y[1] > 0:
			parts.append("[color=#d29a62]+%d wood[/color]" % y[1])
		if y[2] > 0:
			parts.append("[color=#c9c3b6]+%d stone[/color]" % y[2])
		if y[3] > 0:
			parts.append("[color=#e8c766]+%d food[/color]" % y[3])
		if gs.is_structure(i):
			parts.append("%d/%d hp" % [gs.bhp[i], Defs.BUILDINGS[b]["hp"]])
		if not parts.is_empty():
			sub += " · " + " ".join(parts)
	elif gs.road[i] != 0:
		sub += " · road" if ter != Defs.T.WATER else " · bridge"
	var kind := "building" if b != Defs.B.NONE else "terrain"
	_card_header(kind, b if b != Defs.B.NONE else ter, title, sub, Defs.player_color(gs.players[owner].color) if owner >= 0 else Color.WHITE)
	if not s.is_my_turn():
		return
	if f == Defs.F.RUIN:
		card_box.add_child(UI.label("Move a unit here to explore the ruins.", "Small", true))
		return
	if f == Defs.F.CAMP:
		card_box.add_child(UI.label("Defeat the bandit, then step in to loot the camp.", "Small", true))
		return
	if owner == gs.cur and b == Defs.B.NONE:
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		var any := false
		for kind_b in [Defs.B.FARM, Defs.B.LUMBER, Defs.B.QUARRY, Defs.B.MINE, Defs.B.MARKET, Defs.B.WALL, Defs.B.TOWER]:
			var d: Dictionary = Defs.BUILDINGS[kind_b]
			if not d["terrain"].has(ter):
				continue
			if d.has("feature") and f != d["feature"]:
				continue
			var prob := gs.build_problem(gs.cur, i, kind_b)
			grid.add_child(_option_button("building", kind_b, d["name"], d["cost"], prob, s.do_build.bind(kind_b), Defs.player_color(gs.players[gs.cur].color)))
			any = true
		if gs.road_problem(gs.cur, i) == "":
			grid.add_child(_option_button("road", 0, "Bridge" if ter == Defs.T.WATER else "Road", gs.road_cost(i), "" if gs.can_afford(gs.cur, gs.road_cost(i)) else "Costs", _build_single_road.bind(i), Color.WHITE))
			any = true
		if any:
			card_box.add_child(grid)
			var tip := _build_tip(i)
			if tip != "":
				card_box.add_child(UI.label(tip, "Small", true))
	elif owner == gs.cur and b != Defs.B.NONE:
		var d: Dictionary = Defs.BUILDINGS[b]
		card_box.add_child(UI.label(d.get("desc", ""), "Small", true))
		var row := UI.hbox(10)
		if gs.road_problem(gs.cur, i) == "":
			row.add_child(UI.button("Add road (%s)" % Defs.cost_text(gs.road_cost(i)), _build_single_road.bind(i), "", 76))
		row.add_child(UI.button("Demolish", func(): confirm("Demolish this %s?" % d["name"].to_lower(), "Demolish", s.do_demolish), "GhostButton", 76))
		card_box.add_child(row)
	elif gs.road_problem(gs.cur, i) == "":
		var b2 := UI.button("Build %s · %s" % ["bridge" if ter == Defs.T.WATER else "road", Defs.cost_text(gs.road_cost(i))], _build_single_road.bind(i), "", 80)
		b2.disabled = not gs.can_afford(gs.cur, gs.road_cost(i))
		card_box.add_child(b2)
	elif owner < 0 and ter != Defs.T.WATER:
		card_box.add_child(UI.label("Claim a nearby town to build here.", "Small", true))


func _build_tip(i: int) -> String:
	var gs := s.gs
	match gs.terrain[i]:
		Defs.T.PLAINS:
			return "Farms feed the town so it grows. Markets love neighbours."
		Defs.T.FOREST:
			return "Lumber camps give wood for roads, archers and farms."
		Defs.T.HILLS:
			return "Quarries give stone for walls, towers and your keep."
	return ""


func _build_single_road(i: int) -> void:
	s.paint = "road"
	s.plan = [i]
	s.confirm_plan()
	s._select_tile(i)


# ---------------------------------------------------------------- toasts

func toast(text: String, col: Color = UI.TEXT) -> void:
	var p := PanelContainer.new()
	p.theme_type_variation = "Card"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := UI.label(text)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 24)
	p.add_child(l)
	toasts.add_child(p)
	while toasts.get_child_count() > 3:
		toasts.get_child(0).free()
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


# ---------------------------------------------------------------- modals

func modal(content: Control, opaque: bool = false) -> Control:
	close_modal()
	var dim := ColorRect.new()
	dim.color = Color(UI.BG, 1.0) if opaque else Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var panel := PanelContainer.new()
	var vp := root.get_viewport_rect().size
	panel.custom_minimum_size.x = minf(660, vp.x - 32)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 0
	var inner := UI.margin(content, 6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	panel.add_child(scroll)
	center.add_child(panel)
	# size the scroll area to the content, capped to the screen
	await get_tree().process_frame
	if is_instance_valid(scroll) and is_instance_valid(inner):
		scroll.custom_minimum_size.y = minf(inner.get_combined_minimum_size().y, vp.y - 140)
	return dim


func close_modal() -> void:
	for c in modal_root.get_children():
		c.queue_free()


func has_modal() -> bool:
	return modal_root.get_child_count() > 0


func confirm(text: String, yes: String, cb: Callable) -> void:
	var v := UI.vbox(18)
	v.add_child(UI.label(text, "", true))
	var row := UI.hbox(10)
	var no := UI.button("Cancel", close_modal, "", 80)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(no)
	var on_yes := func():
		close_modal()
		cb.call()
	var ok := UI.button(yes, on_yes, "PrimaryButton", 80)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ok)
	v.add_child(row)
	modal(v)


func _title_block(v: VBoxContainer, title: String, sub: String = "", col: Color = UI.ACCENT) -> void:
	var t := UI.label(title, "Title", true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", col)
	t.add_theme_font_size_override("font_size", 38)
	v.add_child(t)
	if sub != "":
		var l := UI.label(sub, "Small", true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)


func _summary_list(v: VBoxContainer, viewer: int) -> void:
	var lines := EventText.summary(s.gs, viewer)
	if lines.is_empty():
		var l := UI.label("All quiet on the borders.", "Small", true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		return
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var box := UI.vbox(8)
	for line in lines.slice(maxi(0, lines.size() - 12)):
		var r := UI.rich("• " + line)
		r.add_theme_font_size_override("normal_font_size", 22)
		box.add_child(r)
	card.add_child(box)
	v.add_child(card)


func show_turn_summary() -> void:
	var gs := s.gs
	var pl := gs.players[gs.cur]
	var v := UI.vbox(16)
	var crest := IconRect.make("castle", 96)
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(crest)
	_title_block(v, "Your move, %s!" % pl.name, "Turn %d%s" % [gs.turn, " of %d" % gs.turn_limit if gs.mode == GameState.Mode.GLORY else ""], Defs.player_color(pl.color).lightened(0.3))
	_summary_list(v, gs.cur)
	var inc := gs.income(gs.cur)
	var r := UI.rich("[center]This turn: [color=#f6c445]%+d gold[/color]  [color=#d29a62]+%d wood[/color]  [color=#c9c3b6]+%d stone[/color][/center]" % [inc["gold"], inc["wood"], inc["stone"]])
	r.add_theme_font_size_override("normal_font_size", 22)
	v.add_child(r)
	var go := UI.button("Let's go!", close_modal, "PrimaryButton", 88)
	v.add_child(go)
	modal(v)


func show_pass_device() -> void:
	var gs := s.gs
	var pl := gs.players[gs.cur]
	var v := UI.vbox(22)
	var crest := IconRect.make("castle", 120)
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(crest)
	_title_block(v, "Pass to %s" % pl.name, "Hand the device over. No peeking!", Defs.player_color(pl.color).lightened(0.3))
	var start := func():
		s.claim_turn()
		show_turn_summary()
	v.add_child(UI.button("I'm %s, start my turn" % pl.name, start, "PrimaryButton", 96))
	v.add_child(UI.button("Save & exit", s.leave, "GhostButton", 72))
	modal(v, true)


func show_link_arrival() -> void:
	var gs := s.gs
	var pl := gs.players[gs.cur]
	var v := UI.vbox(16)
	var crest := IconRect.make("castle", 96)
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(crest)
	_title_block(v, "%s, it's your move!" % pl.name, "%s · turn %d" % [Storage.title_for(gs), gs.turn], Defs.player_color(pl.color).lightened(0.3))
	_summary_list(v, gs.cur)
	var play := func():
		close_modal()
		s.claim_turn()
	var look := func():
		close_modal()
		s._set_mode(GameScreen.Mode.WAITING)
	v.add_child(UI.button("Play as %s" % pl.name, play, "PrimaryButton", 92))
	v.add_child(UI.button("I'm not %s, just look" % pl.name, look, "GhostButton", 72))
	modal(v)


func show_share_turn() -> void:
	var gs := s.gs
	var pl := gs.players[gs.cur]
	var v := UI.vbox(18)
	var ic := IconRect.make("share", 80, 0, UI.ACCENT)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	_title_block(v, "Send the turn to %s" % pl.name, "Share the link in your Discord chat. When %s opens it, the game picks up right where you left off." % pl.name, Defs.player_color(pl.color).lightened(0.3))
	var label := "Share to Discord…" if Net.can_share_sheet() else "Copy link for Discord"
	v.add_child(UI.button(label, s.share_turn, "PrimaryButton", 96))
	if Net.can_share_sheet():
		v.add_child(UI.button("Copy link instead", s.copy_turn, "", 76))
	if Net.base_url() == "":
		var warn := UI.label("Tip: this build isn't hosted on the web, so the link is a code. Your friend pastes it in Hexhold under 'Open turn link'.", "Small", true)
		v.add_child(warn)
	v.add_child(UI.button("Done", close_modal, "GhostButton", 72))
	modal(v)


func show_game_over() -> void:
	var gs := s.gs
	var v := UI.vbox(16)
	var crest := IconRect.make("star", 96)
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(crest)
	var w := gs.winner
	var title := "Game over"
	var col := UI.ACCENT
	if w >= 0:
		title = "%s wins!" % gs.players[w].name
		col = Defs.player_color(gs.players[w].color).lightened(0.3)
	_title_block(v, title, "After %d turn%s" % [gs.turn, "" if gs.turn == 1 else "s"], col)
	_score_table(v)
	if gs.online:
		v.add_child(UI.button("Send the result", s.share_turn, "PrimaryButton", 84))
	v.add_child(UI.button("Back to menu", s.leave, "" if gs.online else "PrimaryButton", 80))
	v.add_child(UI.button("Look at the map", close_modal, "GhostButton", 70))
	modal(v)


func _score_table(v: VBoxContainer) -> void:
	var gs := s.gs
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var box := UI.vbox(8)
	var order: Array = range(gs.players.size())
	order.sort_custom(func(a, b): return gs.score(a) > gs.score(b))
	for p in order:
		var pl := gs.players[p]
		var row := UI.hbox(10)
		var dot := ColorRect.new()
		dot.color = Defs.player_color(pl.color)
		dot.custom_minimum_size = Vector2(18, 18)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var name := UI.label(pl.name + ("" if pl.alive else " (fallen)") + (" · CPU" if pl.ai else ""))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var nt := gs.player_towns(p).size()
		var info := UI.label("%d town%s · %d pts" % [nt, "" if nt == 1 else "s", gs.score(p)], "Small")
		row.add_child(info)
		box.add_child(row)
	card.add_child(box)
	v.add_child(card)


func show_kingdom() -> void:
	var gs := s.gs
	var p := gs.cur if s.is_my_turn() else maxi(0, s._viewer())
	var pl := gs.players[p]
	var mine := s.is_my_turn()
	var v := UI.vbox(16)
	_title_block(v, "Kingdom of %s" % pl.name, "", Defs.player_color(pl.color).lightened(0.3))

	# Keep
	var keep_card := PanelContainer.new()
	keep_card.theme_type_variation = "Card"
	var kb := UI.vbox(10)
	var kh := UI.hbox(12)
	kh.add_child(IconRect.make("castle", 64))
	var kt := UI.vbox(0)
	kt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kt.add_child(UI.label(Defs.KEEP_NAMES[pl.keep], "Heading"))
	var unlocks := ["", "Spearmen, archers, farms, camps, quarries, mines, walls", "Swordsmen, knights, towers and markets", "Catapults"]
	kt.add_child(UI.label("Unlocked: " + ", ".join(PackedStringArray(unlocks.slice(1, pl.keep + 1))), "Small", true))
	kh.add_child(kt)
	kb.add_child(kh)
	if pl.keep < 3:
		var next: int = pl.keep + 1
		var prob := gs.keep_problem(p)
		var up := func():
			s.do_upgrade_keep()
			show_kingdom()
		var b := UI.button("Upgrade to %s · %s" % [Defs.KEEP_NAMES[next], Defs.cost_text(Defs.KEEP_COST[next])], up, "PrimaryButton", 84)
		b.disabled = prob != "" or not mine
		kb.add_child(b)
		kb.add_child(UI.label("Unlocks: " + unlocks[next], "Small", true))
	keep_card.add_child(kb)
	v.add_child(keep_card)

	# Taxes
	v.add_child(UI.label("Taxes", "Heading"))
	var trow := UI.hbox(8)
	for t in 3:
		var set_tax := func():
			s.do_set_tax(t)
			show_kingdom()
		var b := UI.button(Defs.TAX_NAMES[t], set_tax, "ChoiceButton", 76)
		b.toggle_mode = true
		b.button_pressed = pl.tax == t
		b.disabled = not mine
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trow.add_child(b)
	v.add_child(trow)
	v.add_child(UI.label(Defs.TAX_DESC[pl.tax], "Small", true))

	# Income
	var inc := gs.income(p)
	var r := UI.rich("Per turn: [color=#f6c445]%+d gold[/color]  [color=#d29a62]+%d wood[/color]  [color=#c9c3b6]+%d stone[/color]\nTowns: %d · trade routes: %d · army %d/%d (wages %d gold)" % [
		inc["gold"], inc["wood"], inc["stone"], gs.player_towns(p).size(), inc["trade"], gs.player_units(p).size(), gs.unit_cap(p), inc["upkeep"]])
	r.add_theme_font_size_override("normal_font_size", 22)
	v.add_child(r)

	v.add_child(UI.label("Standings", "Heading"))
	_score_table(v)
	var row := UI.hbox(10)
	var help := UI.button("How to play", show_help, "", 76)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(help)
	var close := UI.button("Close", close_modal, "PrimaryButton", 76)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(close)
	v.add_child(row)
	modal(v)


func show_help() -> void:
	var v := UI.vbox(16)
	_title_block(v, "How to play")
	v.add_child(Help.build())
	v.add_child(UI.button("Got it", close_modal, "PrimaryButton", 80))
	modal(v)


func _show_menu() -> void:
	var v := UI.vbox(14)
	_title_block(v, "Hexhold", Storage.title_for(s.gs))
	v.add_child(UI.button("Resume", close_modal, "PrimaryButton", 84))
	if s.gs.online and s.mode == GameScreen.Mode.WAITING:
		var again := func():
			close_modal()
			show_share_turn()
		v.add_child(UI.button("Send turn link again", again, "", 80))
	v.add_child(UI.button("How to play", show_help, "", 80))
	var snd := func():
		Sfx.set_enabled(not Sfx.is_enabled())
		_show_menu()
	v.add_child(UI.button("Sound: %s" % ("on" if Sfx.is_enabled() else "off"), snd, "GhostButton", 72))
	v.add_child(UI.button("Save & exit to menu", s.leave, "", 80))
	modal(v)
