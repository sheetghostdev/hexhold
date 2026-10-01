class_name UI
extends RefCounted
## Theme + tiny helpers for building touch-friendly UI in code.

const BG := Color("#1b2631")
const PANEL := Color("#14202bee")
const PANEL_SOLID := Color("#16222d")
const CARD := Color("#223443")
const ACCENT := Color("#f2b632")
const TEXT := Color("#f3efe6")
const MUTED := Color("#9fb0bf")
const GOOD := Color("#7bd389")
const BAD := Color("#ff7b72")

static var _theme: Theme
static var title_font: Font
static var body_font: Font


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	_load_fonts()
	if body_font:
		t.default_font = body_font
	t.default_font_size = 26

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_constant("h_separation", "Button", 10)
	t.set_constant("icon_max_width", "Button", 44)

	_button_styles(t, "Button", Color("#2c4153"))
	t.set_type_variation("PrimaryButton", "Button")
	_button_styles(t, "PrimaryButton", ACCENT)
	t.set_color("font_color", "PrimaryButton", Color("#2a1d05"))
	t.set_color("font_hover_color", "PrimaryButton", Color("#2a1d05"))
	t.set_color("font_pressed_color", "PrimaryButton", Color("#2a1d05"))
	t.set_color("font_focus_color", "PrimaryButton", Color("#2a1d05"))
	t.set_color("font_disabled_color", "PrimaryButton", Color(0.16, 0.11, 0.02, 0.5))
	t.set_type_variation("DangerButton", "Button")
	_button_styles(t, "DangerButton", Color("#b5443c"))
	t.set_type_variation("GhostButton", "Button")
	_button_styles(t, "GhostButton", Color(1, 1, 1, 0.06))
	t.set_type_variation("ChoiceButton", "Button")
	_button_styles(t, "ChoiceButton", Color("#2c4153"))
	var sel := _box(Color("#3e5a70"), 14)
	sel.border_color = ACCENT
	sel.set_border_width_all(3)
	t.set_stylebox("pressed", "ChoiceButton", sel)
	t.set_stylebox("hover_pressed", "ChoiceButton", sel)

	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 22))
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", _box(CARD, 16, 16))
	t.set_type_variation("Bar", "PanelContainer")
	var bar := _box(PANEL, 0, 10)
	bar.content_margin_left = 16
	bar.content_margin_right = 16
	t.set_stylebox("panel", "Bar", bar)

	t.set_stylebox("normal", "LineEdit", _box(Color("#0f1820"), 12, 14))
	t.set_stylebox("focus", "LineEdit", _box(Color("#0f1820"), 12, 14))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("panel", "PopupPanel", _box(PANEL_SOLID, 18))

	t.set_type_variation("Title", "Label")
	t.set_font_size("font_size", "Title", 44)
	t.set_color("font_color", "Title", ACCENT)
	if title_font:
		t.set_font("font", "Title", title_font)
	t.set_type_variation("Heading", "Label")
	t.set_font_size("font_size", "Heading", 32)
	if title_font:
		t.set_font("font", "Heading", title_font)
	t.set_type_variation("Small", "Label")
	t.set_font_size("font_size", "Small", 21)
	t.set_color("font_color", "Small", MUTED)

	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	_scrollbar(t)
	_theme = t
	return t


static func _load_fonts() -> void:
	title_font = _weighted("res://fonts/title.ttf", 700)
	body_font = _weighted("res://fonts/body.ttf", 700)


static func _weighted(path: String, weight: int) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var base: Font = load(path)
	var fv := FontVariation.new()
	fv.base_font = base
	var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	fv.variation_opentype = { tag: weight }
	return fv


static func _box(c: Color, radius: int, margin: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	return s


static func _button_styles(t: Theme, type: String, c: Color) -> void:
	var normal := _box(c, 14, 14)
	normal.shadow_color = Color(0, 0, 0, 0.25)
	normal.shadow_size = 3
	normal.shadow_offset = Vector2(0, 3)
	t.set_stylebox("normal", type, normal)
	var hover := _box(c.lightened(0.08), 14, 14)
	t.set_stylebox("hover", type, hover)
	var pressed := _box(c.darkened(0.18), 14, 14)
	t.set_stylebox("pressed", type, pressed)
	var dis := _box(Color(c.r, c.g, c.b, c.a * 0.35), 14, 14)
	t.set_stylebox("disabled", type, dis)
	t.set_stylebox("focus", type, StyleBoxEmpty.new())


static func _scrollbar(t: Theme) -> void:
	var grab := _box(Color(1, 1, 1, 0.25), 6, 0)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 6
	t.set_stylebox("scroll", "VScrollBar", sb)


# ---------------------------------------------------------------- builders

static func button(text: String, cb: Callable = Callable(), variant: String = "", min_h: float = 76) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = min_h
	if variant != "":
		b.theme_type_variation = variant
	if cb.is_valid():
		b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func label(text: String, variant: String = "", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if variant != "":
		l.theme_type_variation = variant
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 10
	return l


static func rich(bbcode: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bbcode
	r.add_theme_color_override("default_color", TEXT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func vbox(sep: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(h: float = 0, expand: bool = true) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func margin(child: Control, m: int) -> MarginContainer:
	var mc := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, m)
	mc.add_child(child)
	return mc


static func color_hex(c: Color) -> String:
	return "#" + c.to_html(false)


## Resource amount line for rich text: e.g. "[color=#f6c445]5 gold[/color]".
static func cost_bb(cost: Array, have: Array = []) -> String:
	var parts := PackedStringArray()
	var names := ["gold", "wood", "stone"]
	var cols := ["#f6c445", "#d29a62", "#c9c3b6"]
	for k in 3:
		if cost[k] > 0:
			var col: String = cols[k]
			if have.size() == 3 and have[k] < cost[k]:
				col = "#ff7b72"
			parts.append("[color=%s]%d %s[/color]" % [col, cost[k], names[k]])
	if parts.is_empty():
		return "free"
	return "  ".join(parts)
