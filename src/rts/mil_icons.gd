class_name MilIcons
extends RefCounted
## Flat 2D icons for the military game's UI (placeholder art).

const ALLOY := Color("#aab4c0")
const FUEL := Color("#5cc26a")
const POWER := Color("#ffd23f")


static func alloy(ci: CanvasItem, c: Vector2, r: float) -> void:
	var top := PackedVector2Array([c + Vector2(-0.9, -0.1) * r, c + Vector2(-0.45, -0.55) * r, c + Vector2(0.9, -0.55) * r, c + Vector2(0.45, -0.1) * r])
	var front := PackedVector2Array([c + Vector2(-0.9, -0.1) * r, c + Vector2(0.45, -0.1) * r, c + Vector2(0.45, 0.5) * r, c + Vector2(-0.9, 0.5) * r])
	var side := PackedVector2Array([c + Vector2(0.45, -0.1) * r, c + Vector2(0.9, -0.55) * r, c + Vector2(0.9, 0.05) * r, c + Vector2(0.45, 0.5) * r])
	ci.draw_colored_polygon(front, ALLOY)
	ci.draw_colored_polygon(top, ALLOY.lightened(0.3))
	ci.draw_colored_polygon(side, ALLOY.darkened(0.25))


static func fuel(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_rect(Rect2(c + Vector2(-0.55, -0.6) * r, Vector2(1.1, 1.4) * r), FUEL.darkened(0.2))
	ci.draw_rect(Rect2(c + Vector2(-0.45, -0.5) * r, Vector2(0.9, 1.2) * r), FUEL)
	ci.draw_rect(Rect2(c + Vector2(-0.15, -0.85) * r, Vector2(0.3, 0.3) * r), Color("#3d3d3d"))
	ci.draw_line(c + Vector2(-0.3, 0.1) * r, c + Vector2(0.3, 0.1) * r, Color(1, 1, 1, 0.6), maxf(1.0, r * 0.12))


static func power(ci: CanvasItem, c: Vector2, r: float) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0.15, -0.95) * r, c + Vector2(-0.55, 0.1) * r, c + Vector2(-0.05, 0.1) * r,
		c + Vector2(-0.2, 0.95) * r, c + Vector2(0.55, -0.15) * r, c + Vector2(0.05, -0.15) * r])
	ci.draw_colored_polygon(pts, POWER)


static func unit(ci: CanvasItem, id: String, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(0, r * 0.12), r, Color(0, 0, 0, 0.3))
	ci.draw_circle(c, r, col.darkened(0.3))
	ci.draw_circle(c, r * 0.88, col)
	var ink := Color(1, 1, 1, 0.95)
	var lw := maxf(1.5, r * 0.13)
	match id:
		"rifleman":
			ci.draw_line(c + Vector2(-0.55, 0.35) * r, c + Vector2(0.55, -0.35) * r, ink, lw * 1.2, true)
			ci.draw_line(c + Vector2(-0.1, 0.05) * r, c + Vector2(-0.05, 0.4) * r, ink, lw, true)
		"sniper":
			ci.draw_arc(c, r * 0.5, 0, TAU, 24, ink, lw, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(c + d * r * 0.25, c + d * r * 0.7, ink, lw * 0.8, true)
		"tank":
			ci.draw_rect(Rect2(c + Vector2(-0.6, 0.0) * r, Vector2(1.2, 0.4) * r), ink)
			ci.draw_rect(Rect2(c + Vector2(-0.3, -0.3) * r, Vector2(0.55, 0.3) * r), ink)
			ci.draw_line(c + Vector2(0.2, -0.15) * r, c + Vector2(0.7, -0.15) * r, ink, lw, true)
		"engineer":
			ci.draw_line(c + Vector2(-0.45, 0.45) * r, c + Vector2(0.25, -0.25) * r, ink, lw * 1.3, true)
			ci.draw_arc(c + Vector2(0.35, -0.35) * r, r * 0.25, PI * 0.8, PI * 2.2, 10, ink, lw, true)


static func building(ci: CanvasItem, id: String, c: Vector2, r: float, col: Color) -> void:
	var d := DB.building(id)
	var rect := Rect2(c - Vector2(r, r * 0.8), Vector2(r * 2, r * 1.6))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#3a444e")
	sb.set_corner_radius_all(int(r * 0.3))
	sb.border_color = col
	sb.set_border_width_all(maxi(2, int(r * 0.12)))
	ci.draw_style_box(sb, rect)
	var font: Font = UI.body_font if UI.body_font else ThemeDB.fallback_font
	var text: String = d.short if d else "?"
	var fs := int(r * 0.75)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, c + Vector2(-tw / 2.0, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
