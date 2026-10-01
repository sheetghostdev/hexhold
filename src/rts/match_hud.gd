class_name MatchHud
extends CanvasLayer
## UI for a military match: resources + power always on top, a context
## card for whatever is selected, and a big End Turn button.

var s: MatchScreen
var root: Control
var turn_label: Label
var alloy_label: Label
var fuel_label: Label
var power_label: Label
var power_box: PanelContainer
var card_wrap: MarginContainer
var card_box: VBoxContainer
var bottom_box: HBoxContainer
var toasts: VBoxContainer
var alert_box: PanelContainer
var alert_label: RichTextLabel
var _last_off := {}
var modal_root: Control


func setup(screen: MatchScreen) -> void:
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

	col.add_child(_top_bar())
	alert_box = PanelContainer.new()
	alert_box.add_theme_stylebox_override("panel", UI._box(Color("#7a1c1c"), 0, 10))
	alert_label = UI.rich("")
	alert_label.add_theme_font_size_override("normal_font_size", 20)
	alert_label.add_theme_font_size_override("bold_font_size", 20)
	alert_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_box.add_child(alert_label)
	alert_box.visible = false
	alert_box.gui_input.connect(_on_power_input)
	col.add_child(alert_box)
	toasts = UI.vbox(8)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tm := UI.margin(toasts, 12)
	tm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tm)
	var sp := UI.spacer()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp)

	var card := PanelContainer.new()
	card_box = UI.vbox(10)
	card.add_child(card_box)
	card_wrap = UI.margin(card, 10)
	card_wrap.add_theme_constant_override("margin_bottom", 6)
	card_wrap.visible = false
	col.add_child(card_wrap)

	var bottom := PanelContainer.new()
	bottom.theme_type_variation = "Bar"
	bottom_box = UI.hbox(10)
	bottom.add_child(bottom_box)
	col.add_child(bottom)

	modal_root = Control.new()
	modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(modal_root)


func _chip(kind: String) -> Array:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI._box(Color(0, 0, 0, 0.28), 14, 8))
	var h := UI.hbox(6)
	h.add_child(IconRect.make(kind, 30))
	var l := UI.label("0")
	l.add_theme_font_size_override("font_size", 25)
	h.add_child(l)
	p.add_child(h)
	return [p, l]


func _top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = "Bar"
	var row := UI.hbox(8)
	bar.add_child(row)
	var menu := UI.button("", _show_menu, "GhostButton", 60)
	menu.custom_minimum_size.x = 60
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(IconRect.make("menu", 30, 0, UI.TEXT))
	menu.add_child(cc)
	row.add_child(menu)
	turn_label = UI.label("", "Small")
	turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn_label.add_theme_font_size_override("font_size", 20)
	row.add_child(turn_label)
	var a := _chip("alloy")
	row.add_child(a[0])
	alloy_label = a[1]
	var f := _chip("fuel")
	row.add_child(f[0])
	fuel_label = f[1]
	var pw := _chip("power")
	power_box = pw[0]
	power_box.mouse_filter = Control.MOUSE_FILTER_STOP
	power_box.gui_input.connect(_on_power_input)
	row.add_child(power_box)
	power_label = pw[1]
	return bar


# ---------------------------------------------------------------- refresh

func refresh_all() -> void:
	var m := s.m
	if m == null:
		return
	var pl := m.players[s.me]
	turn_label.text = "Turn %d/%d\n%s" % [m.turn, DB.rules.turn_limit, "Your turn" if m.cur == s.me else "Enemy turn"]
	alloy_label.text = str(pl.alloy)
	fuel_label.text = str(pl.fuel)
	var pw := m.power(s.me)
	power_label.text = "%d/%d" % [pw["demand"], pw["supply"]]
	var short: bool = pw["demand"] > pw["supply"]
	power_label.add_theme_color_override("font_color", UI.BAD if short else UI.TEXT)
	var off: Dictionary = pw["off"]
	alert_box.visible = not off.is_empty()
	if not off.is_empty():
		var names := []
		for b in m.player_buildings(s.me):
			if off.has(b.id):
				names.append(b.def().name)
		alert_label.text = "[b]Low power (%d needed, %d made):[/b] %s switched off. Build a Power Plant." % [pw["demand"], pw["supply"], ", ".join(names)]
		for id in off:
			if not _last_off.has(id):
				toast("Power shortage! A building switched off.", UI.BAD)
				break
	_last_off = off
	_refresh_bottom()
	show_selection()


func _refresh_bottom() -> void:
	for c in bottom_box.get_children():
		c.queue_free()
	var m := s.m
	var army := UI.label("Army %d/%d" % [m.player_units(s.me).size(), DB.rules.unit_cap], "Small")
	army.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	army.add_theme_font_size_override("font_size", 21)
	bottom_box.add_child(army)
	var end := UI.button("End turn", s.end_turn, "PrimaryButton", 92)
	end.custom_minimum_size.x = 300
	end.add_theme_font_size_override("font_size", 30)
	end.disabled = not s.my_turn()
	if m.cur != s.me and m.winner < 0:
		end.text = "Enemy turn..."
	bottom_box.add_child(end)


# ---------------------------------------------------------------- context card

func show_selection() -> void:
	for c in card_box.get_children():
		c.queue_free()
	var m := s.m
	card_wrap.visible = s.sel_tile >= 0
	if s.sel_tile < 0:
		return
	if s.sel_unit != null and m.units.has(s.sel_unit):
		_unit_card(s.sel_unit)
	elif s.sel_building != null and m.buildings.has(s.sel_building):
		_building_card(s.sel_building)
	else:
		_tile_card(s.sel_tile)


func _header(icon: Control, title: String, sub: String) -> void:
	var row := UI.hbox(14)
	icon.custom_minimum_size = Vector2(58, 58)
	row.add_child(icon)
	var v := UI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UI.label(title, "Heading")
	t.add_theme_font_size_override("font_size", 27)
	v.add_child(t)
	if sub != "":
		var l := UI.rich(sub)
		l.add_theme_font_size_override("normal_font_size", 20)
		l.add_theme_color_override("default_color", UI.MUTED)
		v.add_child(l)
	row.add_child(v)
	var close := UI.button("×", s.deselect, "GhostButton", 54)
	close.custom_minimum_size.x = 54
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(close)
	card_box.add_child(row)


func _note(text: String) -> RichTextLabel:
	var r := UI.rich(text)
	r.add_theme_font_size_override("normal_font_size", 21)
	r.add_theme_font_size_override("bold_font_size", 21)
	r.add_theme_color_override("default_color", Color("#c9d5df"))
	return r


func _who(p: int) -> String:
	if p == s.me:
		return "[color=%s]You[/color]" % UI.color_hex(s.board.color_of(p).lightened(0.3))
	return "[color=%s]%s[/color]" % [UI.color_hex(s.board.color_of(p).lightened(0.3)), s.m.players[p].name]


func _icon(kind: String, tag: String, col: Color) -> IconRect:
	var ic := IconRect.make(kind, 58, 0, col)
	ic.tag = tag
	return ic


func _unit_card(u: MatchState.UnitS) -> void:
	var d := u.def()
	var m := s.m
	var stats := "%s · [color=#7bd389]%d/%d hp[/color] · move %d" % [_who(u.owner), u.hp, d.hp, int(m.ustat(u, "move"))]
	if d.attack > 0.0:
		stats += " · range %d" % int(m.ustat(u, "attack_range"))
	_header(_icon("mil_unit", u.type, s.board.color_of(u.owner)), d.name, stats)
	card_box.add_child(_note(d.role))
	if u.owner != s.me or not s.my_turn():
		return
	var status := ""
	if u.task >= 0:
		var o := m.obstacle_def(u.task)
		status = "Clearing %s: done in [b]%d turn%s[/b], then [color=#ffd23f]+%d %s[/color]. Moving cancels the job." % [o.name.to_lower() if o else "it", u.task_left, "" if u.task_left == 1 else "s", m.amount[u.task], o.resource.capitalize() if o else ""]
		card_box.add_child(_note(status))
		return
	if u.fresh:
		status = "Just arrived: ready next turn."
	elif u.attacked or (u.moved and s.targets.is_empty() and s.clears.is_empty()):
		status = "Done for this turn."
	elif u.moved and not s.clears.is_empty():
		status = "Tap a [color=#ffd23f][b]yellow ring[/b][/color] to start clearing it."
	elif u.moved:
		status = "Tap a [b]red target[/b] to attack."
	elif d.abilities.has("clear"):
		status = "Tap a [b]white dot[/b] to move."
		if not s.clears.is_empty():
			status = "Tap a [color=#ffd23f][b]yellow ring[/b][/color] to clear trees or rocks for resources, or a [b]white dot[/b] to move."
		status += " Engineers can also build on open ground next to them, even outside your territory."
	else:
		status = "Tap a [b]white dot[/b] to move" + (", or a [b]red target[/b] to attack." if not s.targets.is_empty() else ".")
	card_box.add_child(_note(status))


func _building_card(b: MatchState.Building) -> void:
	var d := b.def()
	var m := s.m
	var sub := "%s · [color=#7bd389]%d/%d hp[/color]" % [_who(b.owner), b.hp, d.hp]
	if d.power_supply > 0:
		sub += " · [color=#ffd23f]+%d power[/color]" % int(m.bstat(b, "power_supply"))
	if d.power_use > 0:
		sub += " · [color=#ffd23f]uses %d power[/color]" % d.power_use
	_header(_icon("mil_building", b.type, s.board.color_of(b.owner)), d.name, sub)
	card_box.add_child(_note(d.description))
	if b.owner != s.me:
		return
	if b.build_left == 0 and not m.powered(b):
		card_box.add_child(_note("[color=#ff8a7a][b]Switched off: not enough power.[/b] When you need more power than you make, your newest buildings switch off first. Build a Power Plant.[/color]"))
	if b.build_left > 0:
		card_box.add_child(_note("[color=#ffd27a]Under construction: ready in %d turn%s.[/color]" % [b.build_left, "" if b.build_left == 1 else "s"]))
		return
	if d.trains.is_empty() or not s.my_turn():
		return
	var title := UI.label("TRAIN", "Small")
	title.add_theme_color_override("font_color", UI.ACCENT)
	card_box.add_child(title)
	for unit_id in d.trains:
		var ud := DB.unit(unit_id)
		var prob := m.train_problem(s.me, b, unit_id)
		card_box.add_child(_row("mil_unit", unit_id, s.board.color_of(s.me), ud.name, ud.role, ud.cost_alloy, ud.cost_fuel, prob, s.do_train.bind(b, unit_id)))
	if b.type == "hq":
		_research_section()


func _research_section() -> void:
	var m := s.m
	var pl := m.players[s.me]
	var title := UI.label("RESEARCH", "Small")
	title.add_theme_color_override("font_color", UI.ACCENT)
	card_box.add_child(title)
	if pl.research != "":
		var d := DB.upgrade(pl.research)
		card_box.add_child(_note("Researching [b]%s[/b]: done in %d turn%s." % [d.name, pl.research_left, "" if pl.research_left == 1 else "s"]))
	for d in DB.sorted_upgrades():
		if pl.researched.has(d.id) or pl.research == d.id:
			continue
		var prob := m.research_problem(s.me, d.id)
		var eff: String = "%s (%d turns)" % [d.description, d.turns]
		card_box.add_child(_row("research", "", UI.ACCENT, d.name, eff, d.cost_alloy, d.cost_fuel, prob, s.do_research.bind(d.id)))
	if not pl.researched.is_empty():
		var names := []
		for id in pl.researched:
			names.append(DB.upgrade(id).name)
		card_box.add_child(_note("[color=#9ff0a8]Done:[/color] " + ", ".join(names)))


func _tile_card(i: int) -> void:
	var m := s.m
	if not s.board.explored(i):
		_header(IconRect.make("terrain", 58, 0), "Unexplored", "Send a unit to scout here.")
		return
	var o := m.obstacle_def(i)
	var owner := m.owner_of(i)
	var where := "No-man's land" if owner < 0 else ("Your territory" if owner == s.me else "Enemy territory")
	if m.ground[i] == MatchState.Ground.WATER:
		_header(IconRect.make("terrain", 58, 0), "Water", where)
		card_box.add_child(_note("Units can't cross water."))
		return
	if o != null:
		var icon := IconRect.make(o.resource, 58)
		_header(icon, o.name, "%s · [color=#f6c445]%d %s left[/color]" % [where, m.amount[i], o.resource.capitalize()])
		var txt := "An Engineer clears it in %d turns and collects the %s. Then you can build here." % [o.clear_turns, o.resource.capitalize()]
		if o.blocks_move:
			txt += " Units can't walk through."
		else:
			txt += " Units inside get extra cover."
		card_box.add_child(_note(txt + " A Drill next to it pulls 1 per turn instead."))
		return
	var engineer_here := owner < 0 and m.builder_for(s.me, i) != null and s.my_turn()
	if owner != s.me and not engineer_here:
		_header(IconRect.make("terrain", 58, 1), "Open ground", where)
		card_box.add_child(_note("Build inside your territory, or next to one of your Engineers. Every building claims the hexes around it."))
		return
	if not s.my_turn():
		_header(IconRect.make("terrain", 58, 1), "Open ground", where)
		card_box.add_child(_note("Buildable land. Build here on your turn."))
		return
	if s.preview_type != "":
		_build_preview(i, s.preview_type)
	elif s.build_cat != "":
		_build_options(i, s.build_cat)
	else:
		_build_categories(i)


const CATEGORIES := [["Power", "power_plant"], ["Production", "barracks"], ["Economy", "drill"], ["Defense", "turret"]]


func _build_categories(i: int) -> void:
	var where := "Your territory" if s.m.owner_of(i) == s.me else "Your Engineer can build here"
	_header(IconRect.make("terrain", 58, 1), "Open ground", where + " · what do you want to build?")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for c in CATEGORIES:
		var b := UI.button("", s.open_category.bind(c[0]), "", 76)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := UI.hbox(10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 12
		var ic := IconRect.make("mil_building", 50, 0, s.board.color_of(s.me))
		ic.tag = c[1]
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var l := UI.label(c[0])
		l.add_theme_font_size_override("font_size", 24)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
		b.add_child(h)
		grid.add_child(b)
	card_box.add_child(grid)


func _build_options(i: int, cat: String) -> void:
	_header(IconRect.make("terrain", 58, 1), "Build: %s" % cat, "Pick a building to preview it.")
	for d in DB.sorted_buildings():
		if d.category != cat or not d.buildable:
			continue
		var prob := s.m.build_problem(s.me, d.id, i)
		var pw: int = d.power_supply if d.power_supply > 0 else -d.power_use
		card_box.add_child(_row("mil_building", d.id, s.board.color_of(s.me), d.name, _build_effect(d), d.cost_alloy, d.cost_fuel, prob, s.preview_build.bind(d.id), pw))
	card_box.add_child(_back_row(null))


func _build_effect(d: BuildingDef) -> String:
	return "%d turn%s to build" % [d.build_turns, "" if d.build_turns == 1 else "s"]


func _build_preview(i: int, type: String) -> void:
	var d := DB.building(type)
	var m := s.m
	var sub := _build_effect(d)
	if d.power_supply > 0:
		sub += " · [color=#ffd23f]+%d power[/color]" % d.power_supply
	if d.power_use > 0:
		sub += " · [color=#ffd23f]uses %d power[/color]" % d.power_use
	_header(_icon("mil_building", type, s.board.color_of(s.me)), d.name, sub)
	card_box.add_child(_note(d.description))
	var pw := m.power(s.me, true)
	var dem: int = pw["demand"] + d.power_use
	var sup: int = pw["supply"] + d.power_supply
	if d.power_use > 0 or d.power_supply > 0:
		var txt := "Power after: [b]%d used / %d made[/b]." % [dem, sup]
		if dem > sup:
			txt = "[color=#ff8a7a]" + txt + " Not enough power: your newest buildings will switch off. Build a Power Plant.[/color]"
		card_box.add_child(_note(txt))
	var gain := 0
	var terr := m.territory()
	for j in m.in_range(i, d.territory):
		if terr[j] != s.me and m.ground[j] == MatchState.Ground.LAND:
			gain += 1
	if gain > 0:
		card_box.add_child(_note("Claims [b]%d new hex%s[/b] of territory (highlighted)." % [gain, "" if gain == 1 else "es"]))
	var prob := m.build_problem(s.me, type, i)
	var confirm := UI.button("Build", s.confirm_build, "PrimaryButton", 84)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.add_theme_font_size_override("font_size", 28)
	confirm.disabled = prob != ""
	if prob != "":
		confirm.text = prob
	card_box.add_child(_back_row(confirm))


func _back_row(extra: Control) -> HBoxContainer:
	var h := UI.hbox(10)
	var back := UI.button("Back", s.build_back, "GhostButton", 84)
	back.custom_minimum_size.x = 150
	h.add_child(back)
	if extra != null:
		h.add_child(extra)
	return h


## A full-width option: icon · name + what it does · costs.
func _row(kind: String, tag: String, col: Color, title: String, effect: String, alloy: int, fuel: int, problem: String, cb: Callable, power := 0) -> Button:
	var b := UI.button("", cb, "", 86)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = problem != ""
	var h := UI.hbox(12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -14
	var ic := IconRect.make(kind, 52, 0, col)
	ic.tag = tag
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := UI.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := UI.label(title)
	t.add_theme_font_size_override("font_size", 24)
	v.add_child(t)
	var e := UI.label(effect if problem == "" else problem, "Small")
	e.add_theme_font_size_override("font_size", 18)
	e.clip_text = true
	e.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if problem != "":
		e.add_theme_color_override("font_color", Color("#ffb37a"))
	v.add_child(e)
	h.add_child(v)
	var have := s.m.players[s.me]
	for pair in [["alloy", alloy, have.alloy], ["fuel", fuel, have.fuel]]:
		if pair[1] <= 0:
			continue
		var c := UI.hbox(3)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(IconRect.make(pair[0], 26))
		var cl := UI.label(str(pair[1]))
		cl.add_theme_font_size_override("font_size", 24)
		if pair[2] < pair[1]:
			cl.add_theme_color_override("font_color", UI.BAD)
		c.add_child(cl)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(c)
	if power != 0:
		var c := UI.hbox(0)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(IconRect.make("power", 26))
		var cl := UI.label(("+%d" % power) if power > 0 else str(-power))
		cl.add_theme_font_size_override("font_size", 24)
		cl.add_theme_color_override("font_color", Color("#9ff0a8") if power > 0 else Color("#ffd23f"))
		c.add_child(cl)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(c)
	b.add_child(h)
	if b.disabled:
		b.modulate = Color(1, 1, 1, 0.8)
	return b


func _on_power_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton or e is InputEventScreenTouch) and not e.pressed:
		_show_power()


func _show_power() -> void:
	var pw := s.m.power(s.me)
	var v := UI.vbox(14)
	_title(v, "Power", "%d needed / %d made" % [pw["demand"], pw["supply"]], Color("#ffd23f"))
	var txt := "Power Plants (and a little from your Home Base) make power. Most other buildings need it.\n\nIf you need more than you make, your [b]newest[/b] buildings switch off until the rest fits. They show a [color=#ff6b5b]red bolt[/color]: they can't train, shoot or drill.\n\nEnemy Power Plants are worth attacking!"
	var r := UI.rich(txt)
	r.add_theme_font_size_override("normal_font_size", 22)
	r.add_theme_font_size_override("bold_font_size", 22)
	v.add_child(r)
	v.add_child(UI.button("Got it", close_modal, "PrimaryButton", 80))
	modal(v)


# ---------------------------------------------------------------- toasts & modals

func toast(text: String, col: Color = UI.TEXT) -> void:
	var p := PanelContainer.new()
	p.theme_type_variation = "Card"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := UI.label(text)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 23)
	p.add_child(l)
	toasts.add_child(p)
	while toasts.get_child_count() > 3:
		toasts.get_child(0).free()
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.4)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func modal(content: Control) -> void:
	close_modal()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minf(640, root.get_viewport_rect().size.x - 32)
	panel.add_child(UI.margin(content, 6))
	center.add_child(panel)


func close_modal() -> void:
	for c in modal_root.get_children():
		c.queue_free()


func has_modal() -> bool:
	for c in modal_root.get_children():
		if not c.is_queued_for_deletion():
			return true
	return false


func _title(v: VBoxContainer, text: String, sub: String, col: Color = UI.ACCENT) -> void:
	var t := UI.label(text, "Title", true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", col)
	t.add_theme_font_size_override("font_size", 38)
	v.add_child(t)
	if sub != "":
		var l := UI.label(sub, "Small", true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)


func show_game_over() -> void:
	var m := s.m
	var v := UI.vbox(16)
	var won := m.winner == s.me
	var last: Dictionary = m.events[m.events.size() - 1]
	var why := "Enemy Home Base destroyed." if last.get("reason", "") == "hq" else "Turn limit reached: highest score wins."
	if not won and last.get("reason", "") == "hq":
		why = "Your Home Base was destroyed."
	_title(v, "Victory!" if won else "Defeat", why, UI.ACCENT if won else UI.BAD)
	for p in m.players.size():
		v.add_child(UI.label("%s: %d points" % [m.players[p].name, m.score(p)], "", true))
	v.add_child(UI.button("Back to menu", func(): s.quit_to_menu.emit(), "PrimaryButton", 84))
	v.add_child(UI.button("Look at the map", close_modal, "GhostButton", 70))
	modal(v)


func _show_menu() -> void:
	var v := UI.vbox(14)
	_title(v, "Paused", "Quick match vs AI")
	v.add_child(UI.button("Resume", close_modal, "PrimaryButton", 84))
	var snd := func():
		Sfx.set_enabled(not Sfx.is_enabled())
		_show_menu()
	v.add_child(UI.button("Sound: %s" % ("on" if Sfx.is_enabled() else "off"), snd, "GhostButton", 72))
	v.add_child(UI.button("Quit to menu", func(): s.quit_to_menu.emit(), "", 80))
	modal(v)
