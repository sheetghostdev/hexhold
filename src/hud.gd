class_name Hud
extends CanvasLayer
## All in-game UI: gold bar, hint banner, context card, toolbar and pop-ups.
## Design rule: every option says in plain words what it does and costs.

var s: GameScreen
var root: Control
var top_bar: PanelContainer
var name_label: Label
var sub_label: Label
var gold_label: Label
var income_label: Label
var hint_wrap: MarginContainer
var hint_label: RichTextLabel
var card_wrap: MarginContainer
var card: PanelContainer
var card_box: VBoxContainer
var bottom_wrap: MarginContainer
var bottom: PanelContainer
var bottom_box: VBoxContainer
var toasts: VBoxContainer
var modal_root: Control
var _dismissed_hint := ""


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
	_build_hint()
	col.add_child(hint_wrap)

	toasts = UI.vbox(8)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tm := UI.margin(toasts, 12)
	tm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tm)

	var sp := UI.spacer()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp)

	card = PanelContainer.new()
	card_box = UI.vbox(10)
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
	for m in [card_wrap, hint_wrap]:
		m.add_theme_constant_override("margin_left", side)
		m.add_theme_constant_override("margin_right", side)
	var bside := maxi(0, int((w - 900) / 2))
	bottom_wrap.add_theme_constant_override("margin_left", bside)
	bottom_wrap.add_theme_constant_override("margin_right", bside)


# ---------------------------------------------------------------- top bar

func _build_top_bar() -> void:
	top_bar = PanelContainer.new()
	top_bar.theme_type_variation = "Bar"
	var row := UI.hbox(12)
	top_bar.add_child(row)
	row.add_child(_icon_only_button("menu", _show_menu))
	var names := UI.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label = UI.label("")
	name_label.add_theme_font_size_override("font_size", 27)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub_label = UI.label("", "Small")
	sub_label.clip_text = true
	names.add_child(name_label)
	names.add_child(sub_label)
	row.add_child(names)
	# one resource: gold, shown big with its income
	var chip := PanelContainer.new()
	chip.theme_type_variation = "Card"
	chip.add_theme_stylebox_override("panel", UI._box(Color(0, 0, 0, 0.25), 18, 8))
	var ch := UI.hbox(8)
	ch.add_child(IconRect.make("gold", 44))
	var gv := UI.vbox(-8)
	gold_label = UI.label("0")
	gold_label.add_theme_font_size_override("font_size", 32)
	income_label = UI.label("", "Small")
	income_label.add_theme_font_size_override("font_size", 18)
	income_label.add_theme_color_override("font_color", UI.GOOD)
	gv.add_child(gold_label)
	gv.add_child(income_label)
	ch.add_child(gv)
	chip.add_child(ch)
	row.add_child(chip)


func _build_hint() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI._box(Color("#2b3f1fdd"), 16, 12))
	var row := UI.hbox(10)
	row.add_child(IconRect.make("bulb", 34))
	hint_label = UI.rich("")
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.add_theme_font_size_override("normal_font_size", 21)
	hint_label.add_theme_font_size_override("bold_font_size", 21)
	row.add_child(hint_label)
	var x := UI.button("×", _dismiss_hint, "GhostButton", 48)
	x.custom_minimum_size.x = 48
	row.add_child(x)
	p.add_child(row)
	hint_wrap = UI.margin(p, 10)
	hint_wrap.add_theme_constant_override("margin_bottom", 0)
	hint_wrap.visible = false


func _icon_only_button(kind: String, cb: Callable, variant: String = "GhostButton") -> Button:
	var b := UI.button("", cb, variant, 64)
	b.custom_minimum_size.x = 64
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(IconRect.make(kind, 34, 0, UI.TEXT))
	b.add_child(cc)
	return b


func refresh_all() -> void:
	if s.gs == null:
		return
	_refresh_top()
	refresh_bottom()
	show_selection()
	_refresh_hint()


func _refresh_top() -> void:
	var gs := s.gs
	var v := s._viewer()
	var shown := v if v >= 0 else gs.cur
	var pl := gs.players[shown]
	name_label.text = pl.name if shown == gs.cur else "%s (waiting)" % pl.name
	name_label.add_theme_color_override("font_color", Defs.player_color(pl.color).lightened(0.3))
	var sub := "Turn %d" % gs.turn
	if gs.mode == GameState.Mode.GLORY:
		sub += " of %d" % gs.turn_limit
	sub += " · " + Defs.KEEP_NAMES[pl.keep]
	sub_label.text = sub
	gold_label.text = str(pl.gold)
	income_label.text = "+%d per turn" % gs.income(shown)["gold"]


# ---------------------------------------------------------------- hints

func _refresh_hint() -> void:
	var text := ""
	if s.is_my_turn() and Storage.get_setting("hints", true) and s.paint == "":
		text = Hints.next(s.gs, s.gs.cur)
	if text == _dismissed_hint:
		text = ""
	hint_wrap.visible = text != ""
	hint_label.text = text


func _dismiss_hint() -> void:
	_dismissed_hint = hint_label.text
	hint_wrap.visible = false


# ---------------------------------------------------------------- toolbar

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


func refresh_bottom() -> void:
	for c in bottom_box.get_children():
		c.queue_free()
	var gs := s.gs
	if s.mode == GameScreen.Mode.WAITING:
		var who := gs.players[gs.cur]
		var t := UI.label("Waiting for %s..." % who.name, "Heading")
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
		var what := "road" if s.paint == "road" else "wall"
		var price := "%d gold per tile" % (Defs.ROAD_COST if s.paint == "road" else Defs.BUILDINGS[Defs.B.WALL]["cost"])
		var l := UI.rich("[b]Drag your finger[/b] across tiles to draw a %s (%s). Tap a tile to add or remove it." % [what, price])
		l.add_theme_font_size_override("normal_font_size", 21)
		l.add_theme_font_size_override("bold_font_size", 21)
		bottom_box.add_child(l)
		var row := UI.hbox(10)
		row.add_child(UI.button("Cancel", s.cancel_paint, "", 84))
		var n := s.plan_valid_count()
		var cost := s.plan_cost()
		var label := "Build %d tile%s · %d gold" % [n, "" if n == 1 else "s", cost] if n > 0 else "Draw on the map"
		var b := UI.button(label, s.confirm_plan, "PrimaryButton", 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = n == 0 or not gs.can_afford(gs.cur, cost)
		if n > 0 and not gs.can_afford(gs.cur, cost):
			b.text = "Need %d gold (have %d)" % [cost, gs.players[gs.cur].gold]
		row.add_child(b)
		bottom_box.add_child(row)
		return
	var row := UI.hbox(8)
	var playing := s.is_my_turn()
	var road := _tool_button("road", "Roads", s.start_paint.bind("road"))
	var wall := _tool_button("walls", "Walls", s.start_paint.bind("wall"))
	var kingdom := _tool_button("castle", "Castle", show_kingdom)
	var undo := _tool_button("undo", "Undo", s.undo)
	var end := _tool_button("next", "End turn", s.end_turn, "PrimaryButton")
	end.size_flags_stretch_ratio = 1.4
	road.disabled = not playing
	wall.disabled = not playing
	undo.disabled = not s.can_undo()
	end.disabled = not playing
	for b in [road, wall, kingdom, undo, end]:
		row.add_child(b)
	bottom_box.add_child(row)


# ---------------------------------------------------------------- building blocks

## A full-width option: icon · title + what it does · price.
func _row(kind: String, id: int, col: Color, title: String, effect: String, cost: int, problem: String, cb: Callable) -> Button:
	var b := UI.button("", cb, "", 86)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var poor := problem == "Not enough gold"
	b.disabled = problem != ""
	var h := UI.hbox(12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -14
	var ic := IconRect.make(kind, 54, id, col)
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
	e.add_theme_font_size_override("font_size", 19)
	if problem != "" and not poor:
		e.add_theme_color_override("font_color", Color("#ffb37a"))
	e.clip_text = true
	e.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(e)
	h.add_child(v)
	if cost >= 0:
		var price := UI.hbox(4)
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price.add_child(IconRect.make("gold", 28))
		var pl := UI.label(str(cost) if cost > 0 else "free")
		pl.add_theme_font_size_override("font_size", 26)
		if poor:
			pl.add_theme_color_override("font_color", UI.BAD)
		price.add_child(pl)
		price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(price)
	b.add_child(h)
	if b.disabled:
		b.modulate = Color(1, 1, 1, 0.8)
	return b


func _note(text: String) -> RichTextLabel:
	var r := UI.rich(text)
	r.add_theme_font_size_override("normal_font_size", 21)
	r.add_theme_font_size_override("bold_font_size", 21)
	r.add_theme_color_override("default_color", Color("#c9d5df"))
	return r


func _section(text: String) -> Label:
	var l := UI.label(text.to_upper(), "Small")
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", UI.ACCENT)
	return l


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
		_card_header("terrain", 0, "Unexplored", "Send a soldier to scout here.")
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


func _card_header(kind: String, id: int, title: String, sub: String, col: Color = Color.WHITE) -> void:
	var row := UI.hbox(14)
	row.add_child(IconRect.make(kind, 60, id, col))
	var v := UI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UI.label(title, "Heading")
	t.add_theme_font_size_override("font_size", 28)
	v.add_child(t)
	if sub != "":
		var l := UI.rich(sub)
		l.add_theme_font_size_override("normal_font_size", 20)
		l.add_theme_color_override("default_color", UI.MUTED)
		v.add_child(l)
	row.add_child(v)
	var close := UI.button("×", s.deselect, "GhostButton", 56)
	close.custom_minimum_size.x = 56
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(close)
	card_box.add_child(row)


func _who(p: int) -> String:
	if p < 0:
		return "Neutral"
	var pl := s.gs.players[p]
	return "[color=%s]%s[/color]" % [UI.color_hex(Defs.player_color(pl.color).lightened(0.3)), pl.name]


func _unit_card(u: GameState.Unit) -> void:
	var gs := s.gs
	var d: Dictionary = Defs.UNITS[u.type]
	var col := Defs.BANDIT_COLOR if u.owner < 0 else Defs.player_color(gs.players[u.owner].color)
	var maxhp := Defs.unit_max_hp(u.type, u.kills)
	var sub := "%s · [color=#7bd389]%d/%d health[/color]%s" % [_who(u.owner) if u.owner >= 0 else "Bandits", u.hp, maxhp, " · [color=#f6c445]veteran[/color]" if u.kills >= Defs.VETERAN_KILLS else ""]
	_card_header("unit", u.type, d["name"], sub, col)
	card_box.add_child(_note(d["role"]))
	var mine := u.owner == gs.cur and s.is_my_turn()
	if not mine:
		return
	var status := ""
	if u.fresh:
		status = "Just trained: ready next turn."
	elif u.attacked and u.moved:
		status = "Done for this turn."
	elif u.attacked:
		status = "Hit and run: tap a white dot to ride away."
	elif u.moved:
		status = "Moved. Tap a red target to attack." if not s.targets.is_empty() else "Done for this turn."
	else:
		status = "Tap a [b]white dot[/b] to move" + (" or a [b]red target[/b] to attack (the number is the damage you'll deal)." if not s.targets.is_empty() else ".")
	card_box.add_child(_note(status))
	var row := UI.hbox(10)
	if gs.can_capture(u):
		var t := gs.town_on(u.idx)
		var cap := UI.button("Capture %s" % t.name, s.do_capture, "PrimaryButton", 80)
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cap)
	var here := gs.town_on(u.idx)
	if here != null and here.owner >= 0 and here.owner != u.owner and not gs.can_capture(u):
		card_box.add_child(_note("[color=#ffd27a]Stay here: next turn you can capture %s.[/color]" % here.name))
	if here != null and here.owner == gs.cur:
		var tb := UI.button("Town", func(): s._select_tile(u.idx, true), "", 72)
		row.add_child(tb)
	var dis := UI.button("Disband", func(): confirm("Send this %s home? You won't get the gold back." % d["name"].to_lower(), "Disband", s.do_disband), "GhostButton", 72)
	row.add_child(dis)
	card_box.add_child(row)


func _town_card(t: GameState.Town) -> void:
	var gs := s.gs
	var col := Defs.player_color(gs.players[t.owner].color) if t.owner >= 0 else Defs.NEUTRAL_COLOR
	var kind := "capital" if t.capital else "town"
	if t.owner < 0:
		_card_header("town", 0, t.name, "Free village", col)
		card_box.add_child(_note("Walk a soldier in to claim it. Every town makes gold and can train soldiers."))
		return
	var linked := gs.connected_towns(t.owner).has(t.idx)
	var gold := gs.town_gold_base(t) + (1 if linked else 0)
	_card_header(kind, 0, t.name, "%s · level %d %s · [color=#f6c445]+%d gold/turn[/color]" % [_who(t.owner), t.level, kind, gold], col)
	if t.owner != gs.cur or not s.is_my_turn():
		if t.owner != gs.cur:
			card_box.add_child(_note("Enemy town. To capture it, have a soldier [b]start a turn[/b] standing on it."))
		return
	# growth: the people bar
	var grow := UI.hbox(10)
	var pl := UI.label("People")
	pl.add_theme_font_size_override("font_size", 21)
	grow.add_child(pl)
	var bar := PipBar.new()
	bar.filled = t.pop
	bar.total = gs.pop_need(t.level)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.add_child(bar)
	card_box.add_child(grow)
	var left := gs.pop_need(t.level) - t.pop
	if t.level < Defs.MAX_TOWN_LEVEL:
		card_box.add_child(_note("[b]%d more %s[/b] to reach level %d: +1 gold, +1 soldier slot and a reward. Add people by building farms, lumber huts and mines on %s's land." % [left, "person" if left == 1 else "people", t.level + 1, t.name]))
	card_box.add_child(_section("Train soldiers · army %d/%d" % [gs.player_units(gs.cur).size(), gs.unit_cap(gs.cur)]))
	if gs.unit_on(t.idx) != null:
		card_box.add_child(_note("[color=#ffd27a]A soldier is standing in the town. Move it out to train here.[/color]"))
		return
	var pcol := Defs.player_color(gs.players[gs.cur].color)
	var shown_locked := false
	for type in Defs.TRAINABLE:
		var d: Dictionary = Defs.UNITS[type]
		var locked: bool = gs.players[gs.cur].keep < d["keep"]
		if locked and shown_locked:
			continue
		if locked:
			shown_locked = true
		var prob := gs.recruit_problem(t, type)
		card_box.add_child(_row("unit", type, pcol, d["name"], d["role"], d["cost"], prob, s.do_recruit.bind(type)))


func _tile_card(i: int) -> void:
	var gs := s.gs
	var ter := gs.terrain[i]
	var f := gs.feature[i]
	var b := gs.building[i]
	var owner := gs.tile_owner(i)
	var town := gs.tile_town(i)
	var title: String = Defs.TERRAIN_NAMES[ter] if b == Defs.B.NONE else Defs.BUILDINGS[b]["name"]
	var sub := "No-man's land"
	if town != null:
		sub = "%s's land" % town.name if owner == gs.cur else "%s's land (%s)" % [town.name, _who(owner)]
	if f == Defs.F.FERTILE or f == Defs.F.OLD_GROWTH or f == Defs.F.GOLD or f == Defs.F.STONE:
		sub += " · [color=#f6c445]%s: +1 extra person[/color]" % Defs.FEATURE_NAMES[f]
	if b != Defs.B.NONE and gs.road[i] != 0:
		sub += " · road"
	elif gs.road[i] != 0:
		sub += " · " + ("bridge" if ter == Defs.T.WATER else "road")
	var kind := "building" if b != Defs.B.NONE else "terrain"
	_card_header(kind, b if b != Defs.B.NONE else ter, title, sub, Defs.player_color(gs.players[owner].color) if owner >= 0 else Color.WHITE)
	if f == Defs.F.RUIN:
		card_box.add_child(_note("Ancient ruins! Move a soldier here to search them for treasure."))
		return
	if f == Defs.F.CAMP:
		card_box.add_child(_note("A bandit camp. Defeat the bandit, then step in to loot it."))
		return
	if not s.is_my_turn():
		return
	if b != Defs.B.NONE:
		card_box.add_child(_note(_building_effect(i, b, town)))
	elif owner == gs.cur:
		var any := false
		for kind_b in Defs.BUILD_ORDER:
			var d: Dictionary = Defs.BUILDINGS[kind_b]
			if not d["terrain"].has(ter):
				continue
			# keep the list short: walls have their own tool, locked things stay hidden
			if kind_b == Defs.B.WALL or gs.players[gs.cur].keep < d["keep"]:
				continue
			var prob := gs.build_problem(gs.cur, i, kind_b)
			card_box.add_child(_row("building", kind_b, Defs.player_color(gs.players[gs.cur].color), d["name"], _build_promise(i, kind_b, town), d["cost"], prob, s.do_build.bind(kind_b)))
			any = true
		if not any and ter == Defs.T.WATER:
			card_box.add_child(_note("Water. You can build a bridge with Roads."))
	elif owner < 0 and ter != Defs.T.WATER:
		card_box.add_child(_note("Nobody's land. Claim a nearby village to build here, or lay a road through it."))
	if gs.road_problem(gs.cur, i) == "" and (owner == gs.cur or owner < 0):
		var rc := gs.road_cost(i)
		var rp := "" if gs.can_afford(gs.cur, rc) else "Not enough gold"
		card_box.add_child(_row("road", 0, Color.WHITE, "Bridge" if ter == Defs.T.WATER else "Road", "Move twice as fast · links towns for +1 gold", rc, rp, _build_single_road.bind(i)))


func _build_promise(i: int, b: int, town: GameState.Town) -> String:
	var gs := s.gs
	match b:
		Defs.B.MARKET:
			return "+1 gold per turn for each farm, hut or mine next to it (now %d)" % _market_preview(i)
		Defs.B.WALL:
			return "Blocks enemies · your soldiers on it defend ×2"
		Defs.B.TOWER:
			return "Blocks enemies and shoots one nearby each turn"
	var pop := gs.build_pop(i, b)
	return "+%d %s for %s" % [pop, "person" if pop == 1 else "people", town.name if town else "the town"]


func _market_preview(i: int) -> int:
	var gs := s.gs
	var v := 0
	for j in gs.neighbors(i):
		if gs.tile_owner(j) != gs.cur:
			continue
		var nb := gs.building[j]
		if nb == Defs.B.FARM or nb == Defs.B.LUMBER or nb == Defs.B.MINE:
			v += 1
	return mini(v, 4)


func _building_effect(i: int, b: int, town: GameState.Town) -> String:
	var gs := s.gs
	match b:
		Defs.B.MARKET:
			return "Earns [color=#f6c445]+%d gold[/color] every turn from the buildings around it." % gs.market_value(i)
		Defs.B.WALL, Defs.B.TOWER:
			var maxhp: int = Defs.BUILDINGS[b]["hp"]
			return "%s · %d/%d strength. Your soldiers standing here defend ×2%s." % ["Tower" if b == Defs.B.TOWER else "Wall", gs.bhp[i], maxhp, ", and it shoots nearby enemies" if b == Defs.B.TOWER else ""]
	var pop := gs.build_pop(i, b)
	return "Gave %s [b]%d %s[/b]. More people make the town level up." % [town.name if town else "its town", pop, "person" if pop == 1 else "people"]


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

func modal(content: Control, opaque: bool = false) -> void:
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
	var inner := UI.margin(content, 6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	panel.add_child(scroll)
	center.add_child(panel)
	await get_tree().process_frame
	if is_instance_valid(scroll) and is_instance_valid(inner):
		scroll.custom_minimum_size.y = minf(inner.get_combined_minimum_size().y, vp.y - 140)


func close_modal() -> void:
	for c in modal_root.get_children():
		c.queue_free()


func has_modal() -> bool:
	for c in modal_root.get_children():
		if not c.is_queued_for_deletion():
			return true
	return false


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


## Level-up: pick one of two rewards (no closing without choosing).
func show_reward(t: GameState.Town) -> void:
	var gs := s.gs
	var v := UI.vbox(16)
	var crest := IconRect.make("star", 84)
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(crest)
	_title_block(v, "%s reached level %d!" % [t.name, t.reward], "It now makes more gold and supports one more soldier. Pick a bonus:")
	var opts := Defs.rewards_for(t.reward)
	for k in opts.size():
		var r: Dictionary = Defs.REWARDS[opts[k]]
		var b := _row(r["icon"], 0, Defs.player_color(gs.players[gs.cur].color), r["name"], r["desc"], -1, "", s.do_choose_reward.bind(t, k))
		b.custom_minimum_size.y = 104
		v.add_child(b)
	modal(v)


func show_turn_summary() -> void:
	var gs := s.gs
	var pl := gs.players[gs.cur]
	var lines := EventText.summary(gs, gs.cur)
	var inc: int = gs.income(gs.cur)["gold"]
	if lines.is_empty():
		# nothing happened: don't block the player, just say hi
		close_modal()
		toast("Your turn, %s! +%d gold" % [pl.name, inc], Defs.player_color(pl.color).lightened(0.4))
		return
	var v := UI.vbox(16)
	_title_block(v, "Your move, %s!" % pl.name, "Turn %d · +%d gold" % [gs.turn, inc], Defs.player_color(pl.color).lightened(0.3))
	_summary_list(v, lines)
	v.add_child(UI.button("Let's go!", close_modal, "PrimaryButton", 88))
	modal(v)


func _summary_list(v: VBoxContainer, lines: Array[String]) -> void:
	if lines.is_empty():
		var l := UI.label("All quiet on the borders.", "Small", true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		return
	var c := PanelContainer.new()
	c.theme_type_variation = "Card"
	var box := UI.vbox(8)
	for line in lines.slice(maxi(0, lines.size() - 10)):
		var r := UI.rich("• " + line)
		r.add_theme_font_size_override("normal_font_size", 22)
		box.add_child(r)
	c.add_child(box)
	v.add_child(c)


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
	_summary_list(v, EventText.summary(gs, gs.cur))
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
	_title_block(v, "Send the turn to %s" % pl.name, "Post the link in your Discord chat. When %s taps it, the game opens right where you left off." % pl.name, Defs.player_color(pl.color).lightened(0.3))
	var label := "Share to Discord..." if Net.can_share_sheet() else "Copy link for Discord"
	v.add_child(UI.button(label, s.share_turn, "PrimaryButton", 96))
	if Net.can_share_sheet():
		v.add_child(UI.button("Copy link instead", s.copy_turn, "", 76))
	if Net.base_url() == "":
		v.add_child(UI.label("Tip: this build isn't on the web, so the link is a code. Paste it in Hexhold under 'Open turn link'.", "Small", true))
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
	var c := PanelContainer.new()
	c.theme_type_variation = "Card"
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
		row.add_child(UI.label("%d town%s · %d pts" % [nt, "" if nt == 1 else "s", gs.score(p)], "Small"))
		box.add_child(row)
	c.add_child(box)
	v.add_child(c)


## The Castle screen: upgrade your keep, see your income, standings.
func show_kingdom() -> void:
	var gs := s.gs
	var p := gs.cur if s.is_my_turn() else maxi(0, s._viewer())
	var pl := gs.players[p]
	var mine := s.is_my_turn()
	var v := UI.vbox(14)
	_title_block(v, "Your Castle", pl.name, Defs.player_color(pl.color).lightened(0.3))
	var kc := PanelContainer.new()
	kc.theme_type_variation = "Card"
	var kb := UI.vbox(10)
	var kh := UI.hbox(12)
	kh.add_child(IconRect.make("castle", 64))
	var kt := UI.vbox(0)
	kt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kt.add_child(UI.label(Defs.KEEP_NAMES[pl.keep], "Heading"))
	var unlocked := PackedStringArray()
	for k in range(1, pl.keep + 1):
		unlocked.append(Defs.KEEP_UNLOCKS[k])
	kt.add_child(UI.label("You can build: " + "; ".join(unlocked), "Small", true))
	kh.add_child(kt)
	kb.add_child(kh)
	if pl.keep < 3:
		var next: int = pl.keep + 1
		var up := func():
			s.do_upgrade_keep()
			show_kingdom()
		var prob := gs.keep_problem(p) if mine else "Wait for your turn"
		kb.add_child(_row("castle", 0, Color.WHITE, "Upgrade to %s" % Defs.KEEP_NAMES[next], "Unlocks " + Defs.KEEP_UNLOCKS[next].to_lower(), Defs.KEEP_COST[next], prob, up))
	kc.add_child(kb)
	v.add_child(kc)

	var inc := gs.income(p)
	v.add_child(_section("Gold per turn: +%d" % inc["gold"]))
	var r := _note("Towns [color=#f6c445]+%d[/color] · markets [color=#f6c445]+%d[/color] · trade routes [color=#f6c445]+%d[/color]\nBigger towns pay more. Roads between your capital and other towns are trade routes." % [inc["towns"], inc["markets"], inc["trade"]])
	v.add_child(r)
	v.add_child(_section("Standings"))
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
	var hints := func():
		Storage.set_setting("hints", not Storage.get_setting("hints", true))
		_refresh_hint()
		_show_menu()
	v.add_child(UI.button("Hints: %s" % ("on" if Storage.get_setting("hints", true) else "off"), hints, "GhostButton", 72))
	var snd := func():
		Sfx.set_enabled(not Sfx.is_enabled())
		_show_menu()
	v.add_child(UI.button("Sound: %s" % ("on" if Sfx.is_enabled() else "off"), snd, "GhostButton", 72))
	v.add_child(UI.button("Save & exit to menu", s.leave, "", 80))
	modal(v)


## A row of pips showing people in a town.
class PipBar:
	extends Control
	var filled := 0
	var total := 2

	func _init() -> void:
		custom_minimum_size = Vector2(120, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var n := maxi(1, total)
		var gap := 6.0
		var w := minf(46.0, (size.x - gap * (n - 1)) / n)
		for k in n:
			var r := Rect2(Vector2(k * (w + gap), 4), Vector2(w, size.y - 8))
			draw_style_box(UI._box(Color("#7bd389") if k < filled else Color(1, 1, 1, 0.12), 6, 0), r)
