class_name Icons
extends RefCounted
## Vector art drawn with CanvasItem calls, shared by the board and the UI.

const INK := Color(1, 1, 1, 0.95)
const DARK := Color(0.12, 0.1, 0.09, 1)
const WOOD_C := Color("#8a5a33")
const WOOD_LIGHT := Color("#c4915a")
const STONE_C := Color("#b8b3a7")
const STONE_DARK := Color("#7d786e")
const GOLD_C := Color("#f6c445")
const GOLD_DARK := Color("#b8862b")
const WHEAT := Color("#e8c766")


static func _pts(ci_pos: Vector2, r: float, arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(ci_pos + Vector2(p[0], p[1]) * r)
	return out


# ---------------------------------------------------------------- units

static func unit_token(ci: CanvasItem, type: int, pos: Vector2, r: float, color: Color, dim: bool = false, veteran: bool = false) -> void:
	var base := color
	if dim:
		base = color.lerp(Color(0.35, 0.35, 0.35), 0.45)
	ci.draw_circle(pos + Vector2(0, r * 0.18), r * 1.02, Color(0, 0, 0, 0.35))
	ci.draw_circle(pos, r, base.darkened(0.35))
	ci.draw_circle(pos - Vector2(0, r * 0.06), r * 0.9, base)
	ci.draw_arc(pos - Vector2(0, r * 0.06), r * 0.9, 0, TAU, 32, base.lightened(0.35), maxf(1.0, r * 0.07), true)
	unit_glyph(ci, type, pos - Vector2(0, r * 0.06), r * 0.78, INK if not dim else Color(1, 1, 1, 0.6))
	if veteran:
		star(ci, pos + Vector2(r * 0.72, -r * 0.72), r * 0.32, GOLD_C)


static func unit_glyph(ci: CanvasItem, type: int, c: Vector2, r: float, col: Color) -> void:
	var lw := maxf(1.5, r * 0.13)
	match type:
		Defs.U.SPEARMAN:
			ci.draw_line(c + Vector2(-0.5, 0.6) * r, c + Vector2(0.35, -0.45) * r, col, lw, true)
			ci.draw_colored_polygon(_pts(c, r, [[0.55, -0.7], [0.18, -0.52], [0.45, -0.3]]), col)
			ci.draw_colored_polygon(_pts(c, r, [[-0.62, -0.25], [-0.12, -0.25], [-0.12, 0.15], [-0.37, 0.42], [-0.62, 0.15]]), col)
		Defs.U.ARCHER:
			ci.draw_arc(c + Vector2(-0.35, 0) * r, 0.7 * r, -1.15, 1.15, 16, col, lw, true)
			var top := c + Vector2(-0.35 + 0.7 * cos(-1.15), 0.7 * sin(-1.15)) * r
			var bot := c + Vector2(-0.35 + 0.7 * cos(1.15), 0.7 * sin(1.15)) * r
			ci.draw_line(top, bot, col, lw * 0.4, true)
			ci.draw_line(c + Vector2(-0.45, 0) * r, c + Vector2(0.5, 0) * r, col, lw * 0.7, true)
			ci.draw_colored_polygon(_pts(c, r, [[0.7, 0], [0.42, -0.16], [0.42, 0.16]]), col)
		Defs.U.SWORDSMAN:
			ci.draw_colored_polygon(_pts(c, r, [[0, -0.75], [0.12, -0.55], [0.12, 0.28], [-0.12, 0.28], [-0.12, -0.55]]), col)
			ci.draw_line(c + Vector2(-0.4, 0.3) * r, c + Vector2(0.4, 0.3) * r, col, lw, true)
			ci.draw_line(c + Vector2(0, 0.3) * r, c + Vector2(0, 0.58) * r, col, lw, true)
			ci.draw_circle(c + Vector2(0, 0.66) * r, r * 0.11, col)
		Defs.U.KNIGHT:
			ci.draw_colored_polygon(_pts(c, r, [
				[-0.42, 0.68], [0.45, 0.68], [0.38, 0.3], [0.12, 0.02], [0.5, 0.12], [0.6, -0.08],
				[0.22, -0.5], [0.12, -0.72], [-0.02, -0.55], [-0.3, -0.38], [-0.42, 0.0]]), col)
			ci.draw_circle(c + Vector2(0.18, -0.3) * r, r * 0.07, DARK)
		Defs.U.CATAPULT:
			ci.draw_line(c + Vector2(-0.55, 0.38) * r, c + Vector2(0.55, 0.38) * r, col, lw, true)
			ci.draw_line(c + Vector2(0.2, 0.38) * r, c + Vector2(-0.45, -0.5) * r, col, lw, true)
			ci.draw_line(c + Vector2(0.25, 0.38) * r, c + Vector2(0.05, -0.05) * r, col, lw * 0.8, true)
			ci.draw_circle(c + Vector2(-0.5, -0.56) * r, r * 0.17, col)
			ci.draw_circle(c + Vector2(-0.35, 0.45) * r, r * 0.2, col)
			ci.draw_circle(c + Vector2(0.35, 0.45) * r, r * 0.2, col)
		Defs.U.BANDIT:
			ci.draw_line(c + Vector2(-0.5, 0.55) * r, c + Vector2(0.45, -0.5) * r, col, lw, true)
			ci.draw_line(c + Vector2(0.5, 0.55) * r, c + Vector2(-0.45, -0.5) * r, col, lw, true)
			ci.draw_line(c + Vector2(-0.6, 0.3) * r, c + Vector2(-0.25, 0.65) * r, col, lw, true)
			ci.draw_line(c + Vector2(0.6, 0.3) * r, c + Vector2(0.25, 0.65) * r, col, lw, true)


static func star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		var a := -PI / 2 + i * PI / 5
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, col)


# ---------------------------------------------------------------- resources

static func resource(ci: CanvasItem, kind: String, c: Vector2, r: float) -> void:
	match kind:
		"gold":
			ci.draw_circle(c, r, GOLD_DARK)
			ci.draw_circle(c, r * 0.8, GOLD_C)
			ci.draw_arc(c, r * 0.55, 0, TAU, 20, GOLD_DARK, maxf(1.0, r * 0.12), true)
		"wood":
			ci.draw_colored_polygon(_pts(c, r, [[-0.9, -0.35], [0.6, -0.35], [0.6, 0.45], [-0.9, 0.45]]), WOOD_C)
			ci.draw_circle(c + Vector2(0.6, 0.05) * r, r * 0.42, WOOD_LIGHT)
			ci.draw_arc(c + Vector2(0.6, 0.05) * r, r * 0.22, 0, TAU, 12, WOOD_C, maxf(1.0, r * 0.08), true)
		"stone":
			ci.draw_colored_polygon(_pts(c, r, [[-0.85, 0.55], [-0.6, -0.4], [0.05, -0.75], [0.75, -0.3], [0.85, 0.55]]), STONE_DARK)
			ci.draw_colored_polygon(_pts(c, r, [[-0.6, 0.35], [-0.42, -0.3], [0.05, -0.55], [0.55, -0.2], [0.6, 0.35]]), STONE_C)
		"food":
			for k in 3:
				var off := Vector2((k - 1) * 0.42, 0.1 * absf(k - 1)) * r
				ci.draw_line(c + off + Vector2(0, 0.85 * r), c + off + Vector2(0, -0.2 * r), Color("#b08a2e"), maxf(1.0, r * 0.12), true)
				ci.draw_colored_polygon(_ellipse(c + off + Vector2(0, -0.35 * r), r * 0.2, r * 0.45), WHEAT)
		"army":
			unit_glyph(ci, Defs.U.SWORDSMAN, c, r, Color("#e6e1d6"))
		"star":
			star(ci, c, r, GOLD_C)
		"castle":
			castle(ci, c + Vector2(0, r * 0.2), r * 1.1, Color("#d8d1c2"), Color("#3d7be0"))


static func _ellipse(c: Vector2, rx: float, ry: float, seg: int = 12) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in seg:
		var a := TAU * i / seg
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


# ---------------------------------------------------------------- buildings

static func building(ci: CanvasItem, b: int, c: Vector2, s: float, owner_col: Color) -> void:
	match b:
		Defs.B.FARM:
			for k in 3:
				var y := (k - 1) * 0.3 * s
				var pts := _pts(c + Vector2(0, y), s, [[-0.55, -0.1], [0.45, -0.1], [0.55, 0.1], [-0.45, 0.1]])
				ci.draw_colored_polygon(pts, WHEAT if k != 1 else Color("#d4ae4c"))
				ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color("#9c7a2a"), maxf(1.0, s * 0.03), true)
		Defs.B.LUMBER:
			for k in 3:
				var off := Vector2([-0.25, 0.25, 0.0][k], [0.15, 0.15, -0.18][k]) * s
				ci.draw_circle(c + off, s * 0.2, WOOD_C)
				ci.draw_circle(c + off, s * 0.15, WOOD_LIGHT)
				ci.draw_arc(c + off, s * 0.07, 0, TAU, 10, WOOD_C, maxf(1.0, s * 0.03), true)
		Defs.B.QUARRY:
			for k in 3:
				var off := Vector2([-0.24, 0.24, 0.0][k], [0.15, 0.15, -0.17][k]) * s
				var pts := _pts(c + off, s, [[-0.2, -0.14], [0.2, -0.14], [0.2, 0.14], [-0.2, 0.14]])
				ci.draw_colored_polygon(pts, STONE_C)
				ci.draw_polyline(pts + PackedVector2Array([pts[0]]), STONE_DARK, maxf(1.0, s * 0.04), true)
		Defs.B.MINE:
			var arch := PackedVector2Array()
			arch.append(c + Vector2(-0.3, 0.3) * s)
			for i in 9:
				var a := PI + PI * i / 8.0
				arch.append(c + Vector2(cos(a) * 0.3, 0.05 + sin(a) * 0.35) * s)
			arch.append(c + Vector2(0.3, 0.3) * s)
			ci.draw_colored_polygon(arch, WOOD_C)
			ci.draw_colored_polygon(_ellipse(c + Vector2(0, 0.12) * s, 0.2 * s, 0.22 * s), DARK)
			ci.draw_circle(c + Vector2(0.38, 0.3) * s, s * 0.09, GOLD_C)
			ci.draw_circle(c + Vector2(0.5, 0.18) * s, s * 0.07, GOLD_C)
		Defs.B.MARKET:
			ci.draw_colored_polygon(_pts(c, s, [[-0.42, -0.05], [0.42, -0.05], [0.42, 0.35], [-0.42, 0.35]]), WOOD_LIGHT)
			for k in 4:
				var x0 := -0.5 + k * 0.25
				var col := owner_col if k % 2 == 0 else Color.WHITE
				ci.draw_colored_polygon(_pts(c, s, [[x0, -0.35], [x0 + 0.25, -0.35], [x0 + 0.25, -0.05], [x0, -0.05]]), col)
			ci.draw_circle(c + Vector2(-0.15, 0.2) * s, s * 0.08, GOLD_C)
			ci.draw_circle(c + Vector2(0.15, 0.2) * s, s * 0.08, Color("#e45c3a"))


static func house(ci: CanvasItem, c: Vector2, s: float, wall: Color, roof: Color) -> void:
	ci.draw_colored_polygon(_pts(c, s, [[-0.5, 0], [0.5, 0], [0.5, 0.6], [-0.5, 0.6]]), wall)
	ci.draw_colored_polygon(_pts(c, s, [[-0.65, 0.05], [0, -0.55], [0.65, 0.05]]), roof)
	ci.draw_colored_polygon(_pts(c, s, [[-0.12, 0.25], [0.12, 0.25], [0.12, 0.6], [-0.12, 0.6]]), DARK)


static func castle(ci: CanvasItem, c: Vector2, s: float, stone: Color, flag: Color) -> void:
	var dark := stone.darkened(0.3)
	# keep body
	ci.draw_colored_polygon(_pts(c, s, [[-0.45, -0.3], [0.45, -0.3], [0.45, 0.45], [-0.45, 0.45]]), stone)
	for k in 4:
		var x0 := -0.45 + k * 0.26
		ci.draw_colored_polygon(_pts(c, s, [[x0, -0.48], [x0 + 0.16, -0.48], [x0 + 0.16, -0.3], [x0, -0.3]]), stone)
	ci.draw_colored_polygon(_pts(c, s, [[-0.12, 0.45], [-0.12, 0.15], [0, 0.05], [0.12, 0.15], [0.12, 0.45]]), DARK)
	ci.draw_line(c + Vector2(-0.45, -0.3) * s, c + Vector2(0.45, -0.3) * s, dark, maxf(1.0, s * 0.04))
	# flag
	ci.draw_line(c + Vector2(0, -0.48) * s, c + Vector2(0, -0.95) * s, DARK, maxf(1.0, s * 0.05))
	ci.draw_colored_polygon(_pts(c, s, [[0.02, -0.95], [0.42, -0.84], [0.02, -0.72]]), flag)
