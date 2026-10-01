class_name IconRect
extends Control
## A small Control that draws one of the vector icons.

var kind := "gold"  # "gold" | "wood" | "stone" | "food" | "unit" | "building" | "star" | "castle" | "army"
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
		"unit":
			Icons.unit_token(self, id, c, r, color)
		"building":
			if id == Defs.B.WALL or id == Defs.B.TOWER:
				_draw_wall_icon(c, r)
			elif id == Defs.B.MINE:
				draw_colored_polygon(Hex.corners(c, r * 1.15), Color("#b5c46a"))
				Icons.building(self, id, c, r * 1.4, color)
			else:
				draw_colored_polygon(Hex.corners(c, r * 1.15), Color("#6fae4f"))
				Icons.building(self, id, c, r * 1.4, color)
		"road":
			draw_colored_polygon(Hex.corners(c, r * 1.15), Color("#6fae4f"))
			draw_line(c + Vector2(-r, r * 0.5), c + Vector2(r, -r * 0.5), Color("#6b4a2b"), r * 0.45, true)
			draw_line(c + Vector2(-r, r * 0.5), c + Vector2(r, -r * 0.5), Color("#c9a26b"), r * 0.25, true)
		"walls":
			_draw_wall_icon(c, r)
		"menu":
			for k in 3:
				var y := (k - 1) * r * 0.55
				draw_line(c + Vector2(-r * 0.7, y), c + Vector2(r * 0.7, y), color, r * 0.2, true)
		"undo":
			draw_arc(c + Vector2(r * 0.1, r * 0.1), r * 0.55, -PI * 0.9, PI * 0.6, 20, color, r * 0.2, true)
			var tip := c + Vector2(r * 0.1, r * 0.1) + Vector2.from_angle(-PI * 0.9) * r * 0.55
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-r * 0.35, -r * 0.05), tip + Vector2(r * 0.3, -r * 0.3), tip + Vector2(r * 0.12, r * 0.38)]), color)
		"next":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.7, -r * 0.6), c + Vector2(r * 0.1, 0), c + Vector2(-r * 0.7, r * 0.6)]), color)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.1, -r * 0.6), c + Vector2(r * 0.7, 0), c + Vector2(-r * 0.1, r * 0.6)]), color)
		"share":
			draw_circle(c + Vector2(r * 0.5, -r * 0.55), r * 0.22, color)
			draw_circle(c + Vector2(r * 0.5, r * 0.55), r * 0.22, color)
			draw_circle(c + Vector2(-r * 0.5, 0), r * 0.22, color)
			draw_line(c + Vector2(-r * 0.5, 0), c + Vector2(r * 0.5, -r * 0.55), color, r * 0.12, true)
			draw_line(c + Vector2(-r * 0.5, 0), c + Vector2(r * 0.5, r * 0.55), color, r * 0.12, true)
		"capital":
			Icons.castle(self, c + Vector2(0, r * 0.2), r * 1.1, Color("#e2dacb"), color)
		"town":
			Icons.house(self, c + Vector2(-r * 0.35, -r * 0.05), r * 0.6, Color("#efe6d2"), color)
			Icons.house(self, c + Vector2(r * 0.4, r * 0.1), r * 0.5, Color("#efe6d2"), color.darkened(0.15))
		"alloy":
			MilIcons.alloy(self, c, r)
		"fuel":
			MilIcons.fuel(self, c, r)
		"power":
			MilIcons.power(self, c, r)
		"mil_unit":
			MilIcons.unit(self, tag, c, r, color)
		"mil_building":
			MilIcons.building(self, tag, c, r, color)
		"terrain":
			var cols := [Color("#3f8fc9"), Color("#8cc265"), Color("#5f9e4a"), Color("#a9b55e"), Color("#8f8a83")]
			draw_colored_polygon(Hex.corners(c, r * 1.1), cols[clampi(id, 0, 4)])
		_:
			Icons.resource(self, kind, c, r)


func _draw_wall_icon(c: Vector2, r: float) -> void:
	var stone := Color("#cfc8b8")
	if kind == "building" and id == Defs.B.TOWER:
		draw_circle(c + Vector2(0, r * 0.15), r * 0.7, stone.darkened(0.25))
		draw_circle(c, r * 0.6, stone)
		for k in 6:
			var a := TAU * k / 6.0
			draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.6, r * 0.14, stone.darkened(0.1))
		draw_circle(c, r * 0.25, color)
		return
	draw_line(c + Vector2(-r, r * 0.3), c + Vector2(r, r * 0.3), stone.darkened(0.3), r * 0.7)
	draw_line(c + Vector2(-r, r * 0.15), c + Vector2(r, r * 0.15), stone, r * 0.6)
	for k in 4:
		var x := -r + r * 0.25 + k * r * 0.5
		draw_rect(Rect2(c + Vector2(x - r * 0.12, -r * 0.4), Vector2(r * 0.24, r * 0.28)), stone)
