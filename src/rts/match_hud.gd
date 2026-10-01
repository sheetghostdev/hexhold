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
	var stats := "%s · [color=#7bd389]%d/%d hp[/color] · move %d" % [_who(u.owner), u.hp, d.hp, d.move]
	if d.attack > 0.0:
		stats += " · range %d" % d.attack_range
	_header(_icon("mil_unit", u.type, s.board.color_of(u.owner)), d.name, stats)
	card_box.add_child(_note(d.role))
	if u.owner != s.me or not s.my_turn():
		return
	var status := ""
	if u.fresh:
		status = "Just arrived: ready next turn."
	elif u.attacked or (u.moved and s.targets.is_empty()):
		status = "Done for this turn."
	elif u.moved:
		status = "Tap a [b]red target[/b] to attack."
	elif d.attack <= 0.0:
		status = "Tap a [b]white dot[/b] to move. (Clearing trees and rocks arrives in milestone 4.)"
	else:
		status = "Tap a [b]white dot[/b] to move" + (", or a [b]red target[/b] to attack." if not s.targets.is_empty() else ".")
	card_box.add_child(_note(status))


func _building_card(b: MatchState.Building) -> void:
	var d := b.def()
	var m := s.m
	var sub := "%s · [color=#7bd389]%d/%d hp[/color]" % [_who(b.owner), b.hp, d.hp]
	if d.power_supply > 0:
		sub += " · [color=#ffd23f]+%d power[/color]" % d.power_supply
	if d.power_use > 0:
		sub += " · [color=#ffd23f]uses %d power[/color]" % d.power_use
	_header(_icon("mil_building", b.type, s.board.color_of(b.owner)), d.name, sub)
	card_box.add_child(_note(d.description))
	if b.owner != s.me:
		return
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
		card_box.add_child(_note(txt + " [color=#9fb0bf](Coming in milestone 4.)[/color]"))
		return
	_header(IconRect.make("terrain", 58, 1), "Open ground", where)
	if owner == s.me:
		card_box.add_child(_note("Buildable land. [color=#9fb0bf](The build menu arrives in milestone 2.)[/color]"))


## A full-width option: icon · name + what it does · costs.
func _row(kind: String, tag: String, col: Color, title: String, effect: String, alloy: int, fuel: int, problem: String, cb: Callable) -> Button:
	var b := UI.button("", cb, "", 86)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = problem != ""
	var poor := problem == "Not enough resources"
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
	var e := UI.label(effect if problem == "" or poor else problem, "Small")
	e.add_theme_font_size_override("font_size", 18)
	e.clip_text = true
	e.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if problem != "" and not poor:
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
	b.add_child(h)
	if b.disabled:
		b.modulate = Color(1, 1, 1, 0.8)
	return b


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
