class_name IconRect
extends Control
## A small Control that draws one of the vector icons.

var kind := "castle"  # see _draw() for the kinds
var id := 0
var color := Color.WHITE
var tag := ""  # string id for military units/buildings


static func make(k: String, size_px: float, i: int = 0, c: Color = Color.WHITE) -> IconRect:
	var r := IconRect.new()
	r.kind = k
	r.id = i
	r.color = c
	r.custom_minimum_size = Vector2(size_px, size_px)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) * 0.42
	match kind:
		"menu":
			for k in 3:
				var y := (k - 1) * r * 0.55
				draw_line(c + Vector2(-r * 0.7, y), c + Vector2(r * 0.7, y), color, r * 0.2, true)
		"share":
			draw_circle(c + Vector2(r * 0.5, -r * 0.55), r * 0.22, color)
			draw_circle(c + Vector2(r * 0.5, r * 0.55), r * 0.22, color)
			draw_circle(c + Vector2(-r * 0.5, 0), r * 0.22, color)
			draw_line(c + Vector2(-r * 0.5, 0), c + Vector2(r * 0.5, -r * 0.55), color, r * 0.12, true)
			draw_line(c + Vector2(-r * 0.5, 0), c + Vector2(r * 0.5, r * 0.55), color, r * 0.12, true)
		"castle":
			MilIcons.castle(self, c + Vector2(0, r * 0.2), r * 1.1, Color("#e2dacb"), color)
		"alloy":
			MilIcons.alloy(self, c, r)
		"fuel":
			MilIcons.fuel(self, c, r)
		"power":
			MilIcons.power(self, c, r)
		"research":
			draw_circle(c, r, Color("#2c3e50"))
			draw_arc(c, r, 0, TAU, 24, color, r * 0.12, true)
			for k in 2:
				var y := c.y + r * (0.3 - k * 0.45)
				draw_polyline(PackedVector2Array([Vector2(c.x - r * 0.45, y + r * 0.2), Vector2(c.x, y - r * 0.2), Vector2(c.x + r * 0.45, y + r * 0.2)]), color, r * 0.18, true)
		"mil_unit":
			MilIcons.unit(self, tag, c, r, color)
		"mil_building":
			MilIcons.building(self, tag, c, r, color)
		"terrain":
			var cols := [Color("#3f8fc9"), Color("#8cc265"), Color("#5f9e4a"), Color("#a9b55e"), Color("#8f8a83")]
			draw_colored_polygon(Hex.corners(c, r * 1.1), cols[clampi(id, 0, 4)])
