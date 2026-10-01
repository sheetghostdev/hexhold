class_name Menu
extends Control
## Title screen, new-game setup, saved games and joining from a link.

signal start_game(gs: GameState, local: int)
signal open_entry(entry: Dictionary)
signal open_code(text: String)

var content: VBoxContainer
var modal_root: Control
var setup := {}
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	var bg := Control.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.draw.connect(_draw_bg.bind(bg))
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	content = UI.vbox(16)
	var m := UI.margin(content, 24)
	center.add_child(m)
	modal_root = Control.new()
	modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal_root)
	var my_name: String = Storage.get_setting("my_name", "Player 1")
	setup = {
		"players": [
			{ "name": my_name, "color": 0, "ai": false },
			{ "name": "Brother", "color": 1, "ai": false },
		],
		"online": true,
		"size": 1,
		"mode": GameState.Mode.CONQUEST,
	}
	show_main()
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if get_child_count() > 0:
		get_child(0).queue_redraw()


func _draw_bg(c: Control) -> void:
	var sz := c.size
	c.draw_rect(Rect2(Vector2.ZERO, sz), UI.BG)
	var r := 46.0
	var cols := [Color("#22384a"), Color("#1f3344"), Color("#25404f"), Color("#203646")]
	var rows := int(sz.y / (r * 1.5)) + 3
	var colsn := int(sz.x / (r * Hex.SQRT3)) + 3
	var drift := fmod(_t * 6.0, r * 3.0)
	for row in rows:
		for col in colsn:
			var p := Hex.offset_to_pixel(col, row) + Vector2(-r, -r * 1.5 + drift)
			p *= r / Hex.SIZE
			var k := GameState.mix(col, row, 11) % 17
			var colr: Color = cols[k % 4]
			if k == 3:
				colr = Color("#2c4a3a")
			c.draw_colored_polygon(Hex.corners(p, r - 3), colr)
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(UI.BG, 0.45))


func _clear() -> void:
	for ch in content.get_children():
		ch.queue_free()
	_close_modal()


func _width() -> float:
	return minf(640.0, get_viewport_rect().size.x - 48)


func _wide(b: Control) -> Control:
	b.custom_minimum_size.x = _width()
	return b


# ---------------------------------------------------------------- main page

func show_main() -> void:
	_clear()
	var crest := IconRect.make("castle", 150)
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(crest)
	var t := UI.label("HEXHOLD", "Title")
	t.add_theme_font_size_override("font_size", 86)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(t)
	var sub := UI.label("Roads  ·  Walls  ·  Conquest", "Small")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	content.add_child(sub)
	content.add_child(UI.spacer(18, false))
	content.add_child(_wide(UI.button("New game", show_new_game, "PrimaryButton", 96)))
	var games := Storage.list_games()
	if not games.is_empty():
		content.add_child(_wide(UI.button("Continue (%d)" % games.size(), show_saved, "", 88)))
	content.add_child(_wide(UI.button("Open turn link", _ask_link, "", 88)))
	content.add_child(_wide(UI.button("How to play", show_help, "GhostButton", 80)))
	var snd := func():
		Sfx.set_enabled(not Sfx.is_enabled())
		show_main()
	content.add_child(_wide(UI.button("Sound: %s" % ("on" if Sfx.is_enabled() else "off"), snd, "GhostButton", 64)))
	content.add_child(UI.spacer(10, false))
	var foot := UI.label("Take turns whenever you like: send the link to your friends on Discord.", "Small", true)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_wide(foot))


func show_error(text: String) -> void:
	var v := UI.vbox(16)
	v.add_child(UI.label(text, "", true))
	v.add_child(UI.button("OK", _close_modal, "PrimaryButton", 80))
	_modal(v)


# ---------------------------------------------------------------- new game

func show_new_game() -> void:
	_clear()
	var head := UI.label("New game", "Title")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(head)

	content.add_child(_section("How will you play?"))
	content.add_child(_choice_row([["Send turns by link", true], ["Pass & play here", false]], setup["online"], _set_option.bind("online")))
	var hint := "Everyone plays on their own phone. After each turn you get a link to post in Discord." if setup["online"] else "Everyone takes turns on this device. The screen hides between turns."
	content.add_child(_wide(UI.label(hint, "Small", true)))

	content.add_child(_section("Players"))
	var players: Array = setup["players"]
	for i in players.size():
		content.add_child(_player_row(i))
	if players.size() < 4:
		content.add_child(_wide(UI.button("+ Add player", _add_player, "GhostButton", 72)))

	content.add_child(_section("Map size"))
	var sizes := []
	for k in Defs.MAP_SIZES.size():
		sizes.append([Defs.MAP_SIZES[k]["name"], k])
	content.add_child(_choice_row(sizes, setup["size"], _set_option.bind("size")))

	content.add_child(_section("Victory"))
	content.add_child(_choice_row([["Conquest", GameState.Mode.CONQUEST], ["Glory (30 turns)", GameState.Mode.GLORY]], setup["mode"], _set_option.bind("mode")))
	var mh := "Take every enemy town." if setup["mode"] == GameState.Mode.CONQUEST else "Highest score after 30 turns wins. Good for shorter games."
	content.add_child(_wide(UI.label(mh, "Small", true)))

	content.add_child(UI.spacer(8, false))
	content.add_child(_wide(UI.button("Start game", _start, "PrimaryButton", 96)))
	content.add_child(_wide(UI.button("Back", show_main, "GhostButton", 72)))


func _set_option(value: Variant, key: String) -> void:
	setup[key] = value
	show_new_game()


func _section(text: String) -> Label:
	var l := UI.label(text, "Heading")
	l.add_theme_font_size_override("font_size", 28)
	return l


func _choice_row(options: Array, current: Variant, cb: Callable) -> Control:
	var row := UI.hbox(8)
	row.custom_minimum_size.x = _width()
	for o in options:
		var b := UI.button(o[0], cb.bind(o[1]), "ChoiceButton", 76)
		b.toggle_mode = true
		b.button_pressed = o[1] == current
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		row.add_child(b)
	return row


func _player_row(i: int) -> Control:
	var p: Dictionary = setup["players"][i]
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.custom_minimum_size.x = _width()
	var row := UI.hbox(10)
	var swatch := Button.new()
	swatch.custom_minimum_size = Vector2(64, 64)
	swatch.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Defs.player_color(p["color"])
	sb.set_corner_radius_all(32)
	for st in ["normal", "hover", "pressed"]:
		swatch.add_theme_stylebox_override(st, sb)
	swatch.pressed.connect(_cycle_color.bind(i))
	row.add_child(swatch)
	var name := UI.button(p["name"], _rename.bind(i), "GhostButton", 64)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name.clip_text = true
	row.add_child(name)
	if i > 0:
		var ai := UI.button("Computer" if p["ai"] else "Human", _toggle_ai.bind(i), "", 64)
		ai.custom_minimum_size.x = 150
		row.add_child(ai)
		var rm := UI.button("×", _remove_player.bind(i), "GhostButton", 64)
		rm.custom_minimum_size.x = 56
		rm.disabled = setup["players"].size() <= 2
		row.add_child(rm)
	else:
		var me := UI.label("you", "Small")
		row.add_child(me)
	card.add_child(row)
	return card


func _cycle_color(i: int) -> void:
	var used := {}
	for p in setup["players"]:
		used[p["color"]] = true
	var c: int = setup["players"][i]["color"]
	for k in Defs.PLAYER_COLORS.size():
		c = (c + 1) % Defs.PLAYER_COLORS.size()
		if not used.has(c):
			break
	setup["players"][i]["color"] = c
	show_new_game()


func _toggle_ai(i: int) -> void:
	var p: Dictionary = setup["players"][i]
	p["ai"] = not p["ai"]
	if p["ai"] and p["name"] in ["Brother", "Player 3", "Player 4"]:
		p["name"] = "Sir Bot %s" % ["", "", "Alaric", "Baldwin", "Cedric"][i + 1] if i + 1 < 5 else "Sir Bot"
		p["name"] = p["name"].strip_edges()
	show_new_game()


func _add_player() -> void:
	var used := {}
	for p in setup["players"]:
		used[p["color"]] = true
	var c := 0
	while used.has(c):
		c += 1
	setup["players"].append({ "name": "Player %d" % (setup["players"].size() + 1), "color": c, "ai": false })
	show_new_game()


func _remove_player(i: int) -> void:
	if setup["players"].size() > 2:
		setup["players"].remove_at(i)
		show_new_game()


func _rename(i: int) -> void:
	ask_text("Name for player %d" % (i + 1), setup["players"][i]["name"], _set_name.bind(i))


func _set_name(t: String, i: int) -> void:
	setup["players"][i]["name"] = t
	if i == 0:
		Storage.set_setting("my_name", t)
	show_new_game()


func _start() -> void:
	var gs := GameState.create(setup)
	start_game.emit(gs, 0)


# ---------------------------------------------------------------- saved games

func show_saved() -> void:
	_clear()
	var head := UI.label("Your games", "Title")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(head)
	for e in Storage.list_games():
		content.add_child(_saved_card(e))
	content.add_child(_wide(UI.button("Back", show_main, "GhostButton", 72)))


func _saved_card(e: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.custom_minimum_size.x = _width()
	var row := UI.hbox(10)
	var v := UI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UI.label(e.get("title", "Game"))
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(t)
	var status := "Turn %d · " % int(e.get("turn", 1))
	if e.get("over", false):
		status += "finished"
	elif e.get("waiting", false):
		status += "waiting for %s" % e.get("cur_name", "the next player")
	else:
		status += "%s to move" % e.get("cur_name", "your")
	var when := Time.get_datetime_string_from_unix_time(int(e.get("time", 0))).replace("T", " ").left(16)
	v.add_child(UI.label(status, "Small"))
	v.add_child(UI.label(when, "Small"))
	row.add_child(v)
	row.add_child(UI.button("Open", open_entry.emit.bind(e), "PrimaryButton", 72))
	var del := UI.button("×", _confirm_delete.bind(e), "GhostButton", 72)
	del.custom_minimum_size.x = 56
	row.add_child(del)
	card.add_child(row)
	return card


func _confirm_delete(e: Dictionary) -> void:
	var v := UI.vbox(16)
	v.add_child(UI.label("Delete \"%s\" from this device?" % e.get("title", "game"), "", true))
	var row := UI.hbox(10)
	var no := UI.button("Keep", _close_modal, "", 80)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var yes_cb := func():
		Storage.delete_game(e["id"])
		if Storage.list_games().is_empty():
			show_main()
		else:
			show_saved()
	var yes := UI.button("Delete", yes_cb, "DangerButton", 80)
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(no)
	row.add_child(yes)
	v.add_child(row)
	_modal(v)


# ---------------------------------------------------------------- links

func _ask_link() -> void:
	ask_text("Paste the turn link from Discord", "", func(t: String): open_code.emit(t), 4000)


## Text input that works well on phones: the browser's own prompt on the
## web (supports paste), a text field elsewhere.
func ask_text(title: String, current: String, cb: Callable, max_len: int = 16) -> void:
	if Net.is_web():
		var r = Net.prompt(title, current)
		if typeof(r) == TYPE_STRING and r.strip_edges() != "":
			cb.call(r.strip_edges().left(max_len))
		return
	var v := UI.vbox(16)
	v.add_child(UI.label(title, "", true))
	var le := LineEdit.new()
	le.text = current
	le.max_length = max_len
	le.custom_minimum_size.y = 72
	v.add_child(le)
	var done := func():
		var txt := le.text.strip_edges()
		_close_modal()
		if txt != "":
			cb.call(txt)
	le.text_submitted.connect(func(_t): done.call())
	var row := UI.hbox(10)
	var cancel := UI.button("Cancel", _close_modal, "", 76)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var paste := UI.button("Paste", func(): le.text = DisplayServer.clipboard_get().strip_edges().left(max_len), "", 76)
	var ok := UI.button("OK", done, "PrimaryButton", 76)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cancel)
	if max_len > 100:
		row.add_child(paste)
	row.add_child(ok)
	v.add_child(row)
	_modal(v)
	le.grab_focus()


# ---------------------------------------------------------------- help & modal

func show_help() -> void:
	_clear()
	var head := UI.label("How to play", "Title")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(head)
	var h := Help.build()
	h.custom_minimum_size.x = _width()
	content.add_child(h)
	content.add_child(_wide(UI.button("Back", show_main, "PrimaryButton", 80)))


func _modal(content_node: Control) -> void:
	_close_modal()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = _width()
	panel.add_child(content_node)
	center.add_child(panel)


func _close_modal() -> void:
	for c in modal_root.get_children():
		c.queue_free()
