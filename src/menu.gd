class_name Menu
extends Control
## Title screen: play a friend online, play the computer, how to play.

signal start_match
signal host_online

var content: VBoxContainer
var modal_root: Control


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
	var card := PanelContainer.new()
	var sb := UI._box(Color(UI.PANEL_SOLID, 0.9), 28, 26)
	card.add_theme_stylebox_override("panel", sb)
	card.add_child(content)
	var m := UI.margin(card, 16)
	center.add_child(m)
	modal_root = Control.new()
	modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal_root)
	show_main()


func _draw_bg(c: Control) -> void:
	var sz := c.size
	# the 3D kingdom shows through; a soft vignette keeps text readable
	var top := Color(UI.BG, 0.55)
	var mid := Color(UI.BG, 0.2)
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(sz.x, 0), Vector2(sz.x, sz.y * 0.5), Vector2(0, sz.y * 0.5)])
	c.draw_polygon(pts, PackedColorArray([top, top, mid, mid]))
	pts = PackedVector2Array([Vector2(0, sz.y * 0.5), Vector2(sz.x, sz.y * 0.5), Vector2(sz.x, sz.y), Vector2(0, sz.y)])
	c.draw_polygon(pts, PackedColorArray([mid, mid, top, top]))


func _clear() -> void:
	for ch in content.get_children():
		ch.queue_free()
	_close_modal()


func _width() -> float:
	return minf(600.0, get_viewport_rect().size.x - 84)


func _wide(b: Control) -> Control:
	b.custom_minimum_size.x = _width()
	return b


func my_name() -> String:
	return String(Storage.get_setting("my_name", "")).left(16)


func show_main() -> void:
	_clear()
	var crest := IconRect.make("castle", 150, 0, Color("#3d7be0"))
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(crest)
	var t := UI.label("HEXHOLD", "Title")
	t.add_theme_font_size_override("font_size", 86)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(t)
	var sub := UI.label("Build  ·  Power  ·  Battle", "Small")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	content.add_child(sub)
	content.add_child(UI.spacer(18, false))
	content.add_child(_wide(UI.button("Play a friend online", func(): host_online.emit(), "PrimaryButton", 96)))
	content.add_child(_wide(UI.button("Quick match vs AI", func(): start_match.emit(), "", 88)))
	content.add_child(_wide(UI.button("Your name: %s" % my_name() if my_name() != "" else "Set your name", _rename, "GhostButton", 72)))
	content.add_child(_wide(UI.button("How to play", show_help, "GhostButton", 72)))
	var snd := func():
		Sfx.set_enabled(not Sfx.is_enabled())
		show_main()
	content.add_child(_wide(UI.button("Sound: %s" % ("on" if Sfx.is_enabled() else "off"), snd, "GhostButton", 64)))
	content.add_child(UI.spacer(10, false))
	var foot := UI.label("1v1, about 10 minutes. Send your friend the invite link on Discord.", "Small", true)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_wide(foot))


func _rename() -> void:
	var r = Net.prompt("Your name (shown to your opponent):", my_name())
	if r is String and r.strip_edges() != "":
		Storage.set_setting("my_name", r.strip_edges().left(16))
	show_main()


func show_error(text: String) -> void:
	var v := UI.vbox(16)
	v.add_child(UI.label(text, "", true))
	v.add_child(UI.button("OK", _close_modal, "PrimaryButton", 80))
	_modal(v)


const HELP := """[b]Goal:[/b] destroy the enemy [b]Home Base[/b]. After 12 turns each, the higher score wins.

[b]Your turn:[/b] tap a unit, then a [b]white dot[/b] to move or a [color=#ff6b5b]red target[/color] to attack (the number is the damage you'll do). Press [b]End turn[/b] when you're done. Online, each turn has a 60 second clock.

[b]Build:[/b] tap an empty hex in your territory (the coloured area) and pick Power, Production, Economy or Defense. You see a preview first. Buildings take a few turns and grow your territory.

[b]Power:[/b] the bolt at the top shows power needed / made. If you need more than you make, your newest buildings switch off (red bolt). Power Plants are juicy targets.

[b]Resources:[/b] [color=#c9d2dc]Alloy[/color] comes from rocks, [color=#7bd389]Fuel[/color] from trees. Select an [b]Engineer[/b] and tap a [color=#ffd23f]yellow ring[/color] to clear them for resources, or build a Drill next to them. Clearing also frees the hex for building.

[b]Units:[/b] Riflemen hold the line, Snipers shoot from 3 hexes, Tanks crush buildings, Engineers gather and can build outside your territory. Research upgrades at the Home Base.

[b]Fog of war:[/b] you only see what your units and buildings see. At the start of your turn you watch a replay of what you saw the enemy do."""


func show_help() -> void:
	var v := UI.vbox(14)
	var t := UI.label("How to play", "Title", true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 40)
	v.add_child(t)
	var r := UI.rich(HELP)
	r.add_theme_font_size_override("normal_font_size", 21)
	r.add_theme_font_size_override("bold_font_size", 21)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(_width() - 40, minf(900.0, get_viewport_rect().size.y - 360))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(r)
	v.add_child(sc)
	v.add_child(UI.button("Got it", _close_modal, "PrimaryButton", 80))
	_modal(v)


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
