class_name Board
extends Node2D
## Draws the map: terrain, borders, roads, walls, towns, units, fog,
## highlights and floating combat numbers.

const R := Hex.SIZE
const DEPTH := 11.0

const TERRAIN_COL := [
	Color("#3f8fc9"),  # water
	Color("#8cc265"),  # plains
	Color("#5f9e4a"),  # forest
	Color("#a9b55e"),  # hills
	Color("#8f8a83"),  # mountain
]
const SIDE_COL := Color("#6b5137")
const FOG_COL := Color("#2a3c4a")
const ROAD_DARK := Color("#6b4a2b")
const ROAD_LIGHT := Color("#d2ae76")
const WALL_STONE := Color("#d6cfbf")
const WALL_DARK := Color("#8c8576")

var gs: GameState
var viewer := 0
var vis := PackedByteArray()

# highlight state, set by the game screen
var selected := -1
var reach := {}
var targets: Array[int] = []
var pending_target := -1
var plan: Array[int] = []
var plan_kind := ""
var plan_ok := {}
var capture_hint := -1

# animation
var unit_pos := {}  # Unit -> Vector2 (only while animating)
var fx: Array = []  # floating texts
var _time := 0.0

var terrain_layer: Node2D
var overlay_layer: Node2D
var unit_layer: Node2D
var fx_layer: Node2D
var font: Font


func _ready() -> void:
	font = UI.body_font if UI.body_font else ThemeDB.fallback_font
	terrain_layer = _layer(_draw_terrain)
	overlay_layer = _layer(_draw_overlay)
	unit_layer = _layer(_draw_units)
	fx_layer = _layer(_draw_fx)


func _layer(cb: Callable) -> Node2D:
	var n := Node2D.new()
	add_child(n)
	n.draw.connect(cb.bind(n))
	return n


func set_state(state: GameState, view_player: int) -> void:
	gs = state
	viewer = view_player
	refresh()


func refresh() -> void:
	if gs == null:
		return
	vis = gs.visible_for(viewer)
	terrain_layer.queue_redraw()
	overlay_layer.queue_redraw()
	unit_layer.queue_redraw()


func refresh_overlay() -> void:
	overlay_layer.queue_redraw()
	unit_layer.queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if selected >= 0 or not targets.is_empty() or not plan.is_empty():
		overlay_layer.queue_redraw()
	if not fx.is_empty():
		for f in fx:
			f["t"] += delta
		fx = fx.filter(func(f): return f["t"] < f["life"])
		fx_layer.queue_redraw()
	if not unit_pos.is_empty():
		unit_layer.queue_redraw()


func explored(i: int) -> bool:
	return viewer < 0 or gs.players[viewer].explored[i] == 1


func seen(i: int) -> bool:
	return viewer < 0 or vis[i] == 1


func map_rect() -> Rect2:
	var a := Hex.offset_to_pixel(0, 0) - Vector2(R, R)
	var b := Hex.offset_to_pixel(gs.w - 1, gs.h - 1) + Vector2(R * 2, R + DEPTH)
	return Rect2(a, b - a)


func tile_at(world: Vector2) -> int:
	var o := Hex.pixel_to_offset(world)
	return gs.idx_of(o.x, o.y)


# ---------------------------------------------------------------- terrain

func _shade(i: int) -> float:
	return float(GameState.mix(gs.map_seed, i, 3) % 1000) / 1000.0


func _draw_terrain(ci: Node2D) -> void:
	if gs == null:
		return
	var n := gs.n_tiles()
	# 1. tiles, row by row so lower rows overlap the depth of upper ones
	for i in n:
		if not explored(i):
			continue
		_draw_tile(ci, i)
	# 2. territory tint + borders
	for i in n:
		if explored(i):
			_draw_territory(ci, i)
	# 3. roads
	_draw_roads(ci, func(i): return gs.road[i] != 0, 1.0)
	# 4. buildings, walls, towns
	for i in n:
		if not explored(i):
			continue
		var b := gs.building[i]
		if b == Defs.B.WALL or b == Defs.B.TOWER:
			_draw_structure(ci, i)
		elif b != Defs.B.NONE:
			var owner := gs.tile_owner(i)
			Icons.building(ci, b, gs.center(i) + Vector2(0, 6), R * 0.95, Defs.player_color(_color_of(owner)))
		var t := gs.town_on(i)
		if t:
			_draw_town(ci, t)
	# 5. fog
	for i in n:
		if not explored(i):
			_draw_cloud(ci, i)
		elif not seen(i):
			ci.draw_colored_polygon(Hex.corners(gs.center(i), R + 0.5), Color(0.08, 0.12, 0.18, 0.38))
	# 6. town labels on top of fog edges
	for t in gs.towns:
		if explored(t.idx):
			_draw_town_label(ci, t)


func _color_of(p: int) -> int:
	if p < 0 or p >= gs.players.size():
		return -1
	return gs.players[p].color


func _draw_tile(ci: Node2D, i: int) -> void:
	var c := gs.center(i)
	var ter := gs.terrain[i]
	var base: Color = TERRAIN_COL[ter]
	var v := _shade(i)
	base = base.lightened(v * 0.08) if v > 0.5 else base.darkened((0.5 - v) * 0.12)
	if ter == Defs.T.WATER:
		var wc := c + Vector2(0, 5)
		ci.draw_colored_polygon(Hex.corners(wc, R + 0.6), base)
		var cols := PackedColorArray()
		var pts := Hex.corners(wc, R * 0.98)
		for k in 6:
			cols.append(base.lightened(0.12) if pts[k].y < wc.y else base.darkened(0.05))
		ci.draw_polygon(pts, cols)
		var wl := Color(1, 1, 1, 0.28)
		var off := (v - 0.5) * R * 0.4
		ci.draw_arc(wc + Vector2(-R * 0.25 + off, -R * 0.15), R * 0.18, PI * 1.15, PI * 1.85, 8, wl, 2.5, true)
		ci.draw_arc(wc + Vector2(R * 0.2 - off, R * 0.25), R * 0.15, PI * 1.15, PI * 1.85, 8, wl, 2.5, true)
		return
	# depth side
	var side := PackedVector2Array()
	var top := Hex.corners(c, R + 0.6)
	side.append(top[1])
	side.append(top[1] + Vector2(0, DEPTH))
	side.append(top[2] + Vector2(0, DEPTH))
	side.append(top[3] + Vector2(0, DEPTH))
	side.append(top[3])
	side.append(top[2])
	ci.draw_colored_polygon(side, SIDE_COL.darkened(0.1 + v * 0.1))
	var cols := PackedColorArray()
	for k in 6:
		cols.append(base.lightened(0.1) if top[k].y < c.y else base.darkened(0.06))
	ci.draw_polygon(top, cols)
	ci.draw_polyline(top + PackedVector2Array([top[0]]), base.darkened(0.15), 1.5, true)
	match ter:
		Defs.T.FOREST:
			var big := gs.feature[i] == Defs.F.OLD_GROWTH
			var spots := [Vector2(-0.32, 0.12), Vector2(0.3, 0.18), Vector2(0.0, -0.22), Vector2(-0.05, 0.42)]
			for k in spots.size():
				if k == 3 and gs.building[i] != Defs.B.NONE:
					continue
				var p: Vector2 = c + spots[k] * R + Vector2((v - 0.5) * 8, 0)
				_tree(ci, p, R * (0.36 if big else 0.28), base)
		Defs.T.HILLS:
			_hill(ci, c + Vector2(-R * 0.25, R * 0.12), R * 0.42, base)
			_hill(ci, c + Vector2(R * 0.28, R * 0.3), R * 0.34, base)
		Defs.T.MOUNTAIN:
			_mountain(ci, c + Vector2(-R * 0.18, R * 0.35), R * 0.75)
			_mountain(ci, c + Vector2(R * 0.35, R * 0.45), R * 0.5)
	_draw_feature(ci, i, c)


func _tree(ci: Node2D, p: Vector2, s: float, base: Color) -> void:
	ci.draw_line(p + Vector2(0, s * 0.3), p + Vector2(0, s * 0.75), Color("#6b4a2b"), s * 0.18)
	var dark := Color("#2f6b34")
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.62, s * 0.4), p + Vector2(-s * 0.62, s * 0.4)]), dark)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.05, s * 0.4), p + Vector2(-s * 0.62, s * 0.4)]), dark.lightened(0.12))


func _hill(ci: Node2D, p: Vector2, s: float, base: Color) -> void:
	var pts := PackedVector2Array()
	for k in 13:
		var a := PI + PI * k / 12.0
		pts.append(p + Vector2(cos(a) * s, sin(a) * s * 0.7))
	ci.draw_colored_polygon(pts, base.darkened(0.12))
	var hl := PackedVector2Array()
	for k in 7:
		var a := PI + PI * k / 12.0
		hl.append(p + Vector2(cos(a) * s * 0.9, sin(a) * s * 0.62))
	hl.append(p + Vector2(0, -s * 0.1))
	ci.draw_colored_polygon(hl, base.lightened(0.1))


func _mountain(ci: Node2D, base_pt: Vector2, s: float) -> void:
	var peak := base_pt + Vector2(0, -s)
	var l := base_pt + Vector2(-s * 0.7, 0)
	var r := base_pt + Vector2(s * 0.7, 0)
	ci.draw_colored_polygon(PackedVector2Array([peak, r, l]), Color("#6f6a64"))
	ci.draw_colored_polygon(PackedVector2Array([peak, base_pt + Vector2(s * 0.1, 0), l]), Color("#8d8780"))
	var snow := PackedVector2Array([peak, peak.lerp(r, 0.3), peak + Vector2(0, s * 0.32), peak.lerp(l, 0.3)])
	ci.draw_colored_polygon(snow, Color("#f4f4f2"))


func _draw_feature(ci: Node2D, i: int, c: Vector2) -> void:
	match gs.feature[i]:
		Defs.F.FERTILE:
			if gs.building[i] == Defs.B.NONE:
				for k in 4:
					var p := c + Vector2(cos(k * 1.7 + 0.4), sin(k * 1.7 + 0.4)) * R * 0.45
					ci.draw_circle(p, 4.0, Color("#f7e26b"))
					ci.draw_circle(p, 1.8, Color("#e58a2e"))
		Defs.F.STONE:
			if gs.building[i] == Defs.B.NONE:
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-8, 18), c + Vector2(-2, 6), c + Vector2(9, 8), c + Vector2(12, 18)]), Color("#c7c2b8"))
		Defs.F.GOLD:
			if gs.building[i] == Defs.B.NONE:
				for k in 3:
					Icons.star(ci, c + Vector2(-10 + k * 11, 14 - (k % 2) * 8), 6.0, Icons.GOLD_C)
		Defs.F.RUIN:
			var stone := Color("#d9d2c0")
			for k in 3:
				var x := (k - 1) * 15.0
				var hgt: float = [26.0, 34.0, 18.0][k]
				ci.draw_rect(Rect2(c + Vector2(x - 5, 16 - hgt), Vector2(10, hgt)), stone)
				ci.draw_rect(Rect2(c + Vector2(x - 7, 16 - hgt - 4), Vector2(14, 5)), stone.darkened(0.1))
			ci.draw_rect(Rect2(c + Vector2(-24, 16), Vector2(48, 6)), stone.darkened(0.2))
			Icons.star(ci, c + Vector2(0, -26 + sin(_time * 2) * 2), 7.0, Icons.GOLD_C)
		Defs.F.CAMP:
			var tent := Color("#a3442f")
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-26, 18), c + Vector2(0, -20), c + Vector2(26, 18)]), tent)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-6, 18), c + Vector2(0, 2), c + Vector2(6, 18)]), Icons.DARK)
			ci.draw_line(c + Vector2(0, -20), c + Vector2(0, -32), Icons.DARK, 2)


func _draw_cloud(ci: Node2D, i: int) -> void:
	var c := gs.center(i)
	ci.draw_colored_polygon(Hex.corners(c, R + 1.5), FOG_COL)
	var v := _shade(i)
	var puff := Color("#33495a")
	var hi := Color("#3b5266")
	var o := Vector2((v - 0.5) * 14.0, 0)
	ci.draw_circle(c + o + Vector2(-R * 0.3, R * 0.12), R * 0.26, puff)
	ci.draw_circle(c + o + Vector2(R * 0.28, R * 0.14), R * 0.24, puff)
	ci.draw_circle(c + o + Vector2(0, -R * 0.02), R * 0.34, puff)
	ci.draw_circle(c + o + Vector2(-R * 0.06, -R * 0.1), R * 0.2, hi)


# ---------------------------------------------------------------- territory

func _draw_territory(ci: Node2D, i: int) -> void:
	var owner := gs.tile_owner(i)
	if owner < 0:
		return
	var col := Defs.player_color(_color_of(owner))
	var c := gs.center(i)
	ci.draw_colored_polygon(Hex.corners(c, R), Color(col, 0.13))
	for d in 6:
		var j := gs.neighbor_dir(i, d)
		if j >= 0 and gs.tile_owner(j) == owner:
			continue
		var edge := _edge(c, d, R - 4.0)
		ci.draw_line(edge[0], edge[1], col.darkened(0.15), 6.0, true)
		ci.draw_line(edge[0], edge[1], col.lightened(0.15), 3.0, true)


## The two corners of the edge facing direction d.
func _edge(c: Vector2, d: int, size: float) -> Array:
	var nb_ax: Vector2i = Hex.AXIAL_DIRS[d]
	# direction vector from axial step (pointy-top)
	var v := Vector2(Hex.SQRT3 * (nb_ax.x + nb_ax.y * 0.5), 1.5 * nb_ax.y).normalized()
	var ang := v.angle()
	var p1 := c + Vector2.from_angle(ang - PI / 6) * size
	var p2 := c + Vector2.from_angle(ang + PI / 6) * size
	return [p1, p2]


# ---------------------------------------------------------------- roads & walls

func _road_link(i: int) -> bool:
	return gs.road[i] != 0 or gs.town_at.has(i)


func _draw_roads(ci: Node2D, is_road: Callable, alpha: float) -> void:
	var segs: Array = []
	var nodes: Array = []
	for i in gs.n_tiles():
		if not is_road.call(i) or not explored(i):
			continue
		var c := gs.center(i)
		nodes.append(c)
		for j in gs.neighbors(i):
			if is_road.call(j) or gs.town_at.has(j) or (_road_link(j) and alpha < 1.0):
				segs.append([c, (c + gs.center(j)) * 0.5])
				if gs.town_at.has(j):
					segs.append([gs.center(j), (c + gs.center(j)) * 0.5])
	var dark := Color(ROAD_DARK, alpha)
	var light := Color(ROAD_LIGHT, alpha)
	for s in segs:
		ci.draw_line(s[0], s[1], dark, 17.0)
	for p in nodes:
		ci.draw_circle(p, 8.5, dark)
	for s in segs:
		ci.draw_line(s[0], s[1], light, 10.0)
		ci.draw_circle(s[1], 5.0, light)
	for p in nodes:
		ci.draw_circle(p, 5.0, light)
	# bridge planks over water
	for i in gs.n_tiles():
		if is_road.call(i) and gs.terrain[i] == Defs.T.WATER and explored(i):
			var c := gs.center(i)
			for k in 5:
				var off := Vector2((k - 2) * 7.0, 0)
				ci.draw_line(c + off + Vector2(0, -9), c + off + Vector2(0, 9), Color(ROAD_DARK, alpha * 0.8), 2.0)


func _wall_link(i: int, owner: int) -> bool:
	if gs.is_structure(i) and gs.tile_owner(i) == owner:
		return true
	var t := gs.town_on(i)
	return t != null and t.owner == owner


func _draw_structure(ci: Node2D, i: int) -> void:
	var c := gs.center(i)
	var owner := gs.tile_owner(i)
	var col := Defs.player_color(_color_of(owner))
	var links: Array[Vector2] = []
	for j in gs.neighbors(i):
		if _wall_link(j, owner):
			links.append((c + gs.center(j)) * 0.5)
	if links.is_empty():
		links.append(c + Vector2(R * 0.42, 0))
		links.append(c - Vector2(R * 0.42, 0))
	var h := 10.0  # wall height (pseudo 3D)
	var top_c := c - Vector2(0, h)
	# side faces first, then the tops, so joints look solid
	for m in links:
		ci.draw_line(c, m, WALL_DARK.darkened(0.15), 18.0)
	ci.draw_rect(Rect2(c - Vector2(10, 10), Vector2(20, 14)), WALL_DARK.darkened(0.15))
	for m in links:
		var mt: Vector2 = m - Vector2(0, h)
		ci.draw_line(top_c, mt, WALL_STONE, 16.0)
		ci.draw_line(top_c + Vector2(0, 6), mt + Vector2(0, 6), WALL_STONE.darkened(0.12), 4.0)
	ci.draw_rect(Rect2(top_c - Vector2(11, 11), Vector2(22, 20)), WALL_STONE)
	# crenellations (merlons) along every segment
	for m in links:
		var mt: Vector2 = m - Vector2(0, h)
		var d: Vector2 = mt - top_c
		var steps := int(d.length() / 9.0)
		for k in range(1, steps):
			if k % 2 == 0:
				continue
			var p: Vector2 = top_c + d * (float(k) / steps)
			ci.draw_rect(Rect2(p - Vector2(3.5, 13), Vector2(7, 7)), WALL_STONE.lightened(0.08))
			ci.draw_rect(Rect2(p - Vector2(3.5, 7), Vector2(7, 1.5)), WALL_DARK)
	for k in 4:
		var q := top_c + Vector2(-9 + k * 6, -15)
		ci.draw_rect(Rect2(q, Vector2(5, 6)), WALL_STONE.lightened(0.08))
	if gs.building[i] == Defs.B.TOWER:
		var rw := R * 0.34
		var base := c + Vector2(0, 4)
		var top := c - Vector2(0, R * 0.62)
		ci.draw_colored_polygon(Icons._ellipse(base, rw, rw * 0.45, 16), WALL_DARK)
		ci.draw_rect(Rect2(Vector2(c.x - rw, top.y), Vector2(rw * 2, base.y - top.y)), WALL_STONE.darkened(0.05))
		ci.draw_rect(Rect2(Vector2(c.x - rw, top.y), Vector2(rw * 0.6, base.y - top.y)), WALL_STONE.lightened(0.06))
		ci.draw_colored_polygon(Icons._ellipse(top, rw * 1.12, rw * 0.5, 16), WALL_STONE.lightened(0.1))
		ci.draw_colored_polygon(Icons._ellipse(top, rw * 0.75, rw * 0.3, 16), WALL_DARK)
		for k in 7:
			var a := PI * 0.05 + PI * 0.9 * k / 6.0
			var mp := top + Vector2(cos(a) * rw * 1.0, sin(a) * rw * 0.42)
			ci.draw_rect(Rect2(mp - Vector2(4, 9), Vector2(8, 9)), WALL_STONE.lightened(0.12))
		ci.draw_rect(Rect2(c + Vector2(-5, -12), Vector2(10, 16)), Icons.DARK)
		ci.draw_line(top, top + Vector2(0, -R * 0.55), Icons.DARK, 3.0)
		ci.draw_colored_polygon(PackedVector2Array([top + Vector2(1, -R * 0.55), top + Vector2(R * 0.42, -R * 0.45), top + Vector2(1, -R * 0.35)]), col)
	else:
		ci.draw_rect(Rect2(top_c + Vector2(-3, -2), Vector2(6, 6)), col)
	var maxhp: int = Defs.BUILDINGS[gs.building[i]]["hp"]
	if gs.bhp[i] < maxhp:
		_hp_bar(ci, c + Vector2(0, R * 0.55), gs.bhp[i], maxhp, Color("#d6cfbf"))


# ---------------------------------------------------------------- towns

func _draw_town(ci: Node2D, t: GameState.Town) -> void:
	var c := gs.center(t.idx)
	var owner_col := Defs.player_color(_color_of(t.owner)) if t.owner >= 0 else Color("#8d6e53")
	var wall := Color("#efe6d2") if t.owner >= 0 else Color("#cdbfa6")
	if t.walls:
		var ring := PackedVector2Array()
		for k in 25:
			ring.append(c + Vector2.from_angle(TAU * k / 24.0) * Vector2(R * 0.78, R * 0.68))
		ci.draw_polyline(ring, WALL_DARK, 12.0, true)
		ci.draw_polyline(ring, WALL_STONE, 8.0, true)
	var spots := [Vector2(-0.38, 0.05), Vector2(0.38, 0.1), Vector2(-0.1, 0.32), Vector2(0.18, -0.28), Vector2(-0.45, -0.32), Vector2(0.48, -0.25)]
	var count := mini(t.level + 1, spots.size())
	if t.capital:
		for k in range(1, count):
			Icons.house(ci, c + spots[k] * R + Vector2(0, -4), R * 0.24, wall, owner_col.darkened(0.15))
		Icons.castle(ci, c + Vector2(-R * 0.08, -R * 0.06), R * 0.62, Color("#e2dacb"), owner_col)
	else:
		for k in count:
			Icons.house(ci, c + spots[k] * R + Vector2(0, -6), R * 0.26, wall, owner_col.darkened(0.1))


func _draw_town_label(ci: Node2D, t: GameState.Town) -> void:
	var c := gs.center(t.idx) + Vector2(0, R * 0.86)
	var fs := 17
	var text := t.name
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var col := Defs.player_color(_color_of(t.owner)) if t.owner >= 0 else Color("#6b6158")
	var rect := Rect2(c - Vector2(tw / 2 + 10, 12), Vector2(tw + 20, 24))
	ci.draw_rect(Rect2(rect.position + Vector2(0, 2), rect.size), Color(0, 0, 0, 0.35))
	ci.draw_rect(rect, col.darkened(0.2))
	ci.draw_string(font, Vector2(rect.position.x + 10, c.y + 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	# level pips
	for k in t.level:
		var px := c.x - (t.level - 1) * 6.0 + k * 12.0
		ci.draw_circle(Vector2(px, c.y + 18), 4.5, Color(0, 0, 0, 0.45))
		ci.draw_circle(Vector2(px, c.y + 17), 3.5, Icons.GOLD_C if t.capital else Color.WHITE)


# ---------------------------------------------------------------- overlay

func _draw_overlay(ci: Node2D) -> void:
	if gs == null:
		return
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	for i in reach:
		var c := gs.center(i)
		ci.draw_colored_polygon(Hex.corners(c, R * 0.92), Color(1, 1, 1, 0.16 + pulse * 0.06))
		ci.draw_circle(c, 7.0, Color(1, 1, 1, 0.8))
	for i in targets:
		var c := gs.center(i)
		var col := Color("#ff4d4d")
		var rr := R * (0.62 if i != pending_target else 0.7 + pulse * 0.05)
		ci.draw_arc(c, rr, 0, TAU, 32, col, 5.0, true)
		for k in 4:
			var a := k * PI / 2 + PI / 4
			ci.draw_line(c + Vector2.from_angle(a) * rr * 0.75, c + Vector2.from_angle(a) * rr * 1.15, col, 4.0)
	if capture_hint >= 0:
		var c := gs.center(capture_hint)
		ci.draw_arc(c, R * 0.85, 0, TAU, 32, Color(Icons.GOLD_C, 0.6 + pulse * 0.4), 5.0, true)
	if selected >= 0:
		var pts := Hex.corners(gs.center(selected), R - 2)
		pts.append(pts[0])
		ci.draw_polyline(pts, Color(1, 1, 1, 0.75 + pulse * 0.25), 5.0, true)
	if not plan.is_empty():
		var plan_set := {}
		for i in plan:
			plan_set[i] = true
		if plan_kind == "road":
			_draw_roads(ci, func(i): return plan_set.has(i) or gs.road[i] != 0, 0.75)
		for i in plan:
			var c := gs.center(i)
			var ok: bool = plan_ok.get(i, false)
			if plan_kind == "wall" and ok:
				ci.draw_circle(c, 14.0, Color(WALL_STONE, 0.85))
				for j in gs.neighbors(i):
					if plan_set.has(j) or _wall_link(j, viewer):
						ci.draw_line(c, (c + gs.center(j)) * 0.5, Color(WALL_STONE, 0.85), 16.0)
			if not ok:
				ci.draw_line(c + Vector2(-12, -12), c + Vector2(12, 12), Color("#ff4d4d"), 5.0)
				ci.draw_line(c + Vector2(12, -12), c + Vector2(-12, 12), Color("#ff4d4d"), 5.0)


# ---------------------------------------------------------------- units

func unit_draw_pos(u: GameState.Unit) -> Vector2:
	if unit_pos.has(u):
		return unit_pos[u]
	return rest_pos(u.idx)


## Where a unit stands on a tile: off to the side on towns so the town shows.
func rest_pos(i: int) -> Vector2:
	if gs.town_at.has(i):
		return gs.center(i) + Vector2(R * 0.36, R * 0.02)
	return gs.center(i) + Vector2(0, -6)


func _draw_units(ci: Node2D) -> void:
	if gs == null:
		return
	for u in gs.units:
		var animating := unit_pos.has(u)
		if u.owner != viewer and not seen(u.idx) and not animating:
			continue
		var p := unit_draw_pos(u)
		var col := Defs.BANDIT_COLOR if u.owner < 0 else Defs.player_color(_color_of(u.owner))
		var spent := u.owner == gs.cur and u.owner == viewer and _spent(u)
		var r := R * (0.36 if gs.town_at.has(u.idx) and not animating else 0.42)
		Icons.unit_token(ci, u.type, p, r, col, spent, u.kills >= Defs.VETERAN_KILLS)
		var maxhp := Defs.unit_max_hp(u.type, u.kills)
		_hp_pips(ci, p + Vector2(0, r + 4), u.hp, maxhp)


func _spent(u: GameState.Unit) -> bool:
	if u.fresh:
		return true
	if u.attacked:
		return true
	if u.moved and gs.attack_targets(u).is_empty() and not gs.can_capture(u):
		return true
	return false


## Health as a small pill under the token, with the number for clarity.
func _hp_pips(ci: Node2D, c: Vector2, hp: int, maxhp: int) -> void:
	var col := Color("#7bd389") if hp * 2 > maxhp else (Color("#ffb347") if hp * 4 > maxhp else Color("#ff6b5b"))
	var wdt := 34.0
	var rect := Rect2(c - Vector2(wdt / 2, 0), Vector2(wdt, 7))
	ci.draw_rect(rect.grow(1.5), Color(0, 0, 0, 0.65))
	ci.draw_rect(Rect2(rect.position, Vector2(wdt * clampf(float(hp) / maxhp, 0, 1), 7)), col)


func _hp_bar(ci: Node2D, c: Vector2, hp: int, maxhp: int, col: Color) -> void:
	var wdt := 40.0
	var rect := Rect2(c - Vector2(wdt / 2, 4), Vector2(wdt, 8))
	ci.draw_rect(rect.grow(2), Color(0, 0, 0, 0.6))
	ci.draw_rect(Rect2(rect.position, Vector2(wdt * clampf(float(hp) / maxhp, 0, 1), 8)), col)


# ---------------------------------------------------------------- effects

func float_text(world: Vector2, text: String, col: Color, big: bool = false) -> void:
	fx.append({ "pos": world, "text": text, "col": col, "t": 0.0, "life": 1.3, "big": big })
	fx_layer.queue_redraw()


func burst(world: Vector2, col: Color) -> void:
	fx.append({ "pos": world, "burst": true, "col": col, "t": 0.0, "life": 0.45 })
	fx_layer.queue_redraw()


func _draw_fx(ci: Node2D) -> void:
	for f in fx:
		var k: float = f["t"] / f["life"]
		if f.get("burst", false):
			var col: Color = f["col"]
			ci.draw_arc(f["pos"], R * (0.3 + k * 0.7), 0, TAU, 24, Color(col, 1.0 - k), 6.0 * (1.0 - k) + 1.0, true)
			continue
		var p: Vector2 = f["pos"] + Vector2(0, -40 * k - 20)
		var a := 1.0 - maxf(0.0, (k - 0.6) / 0.4)
		var fs := 34 if f.get("big", false) else 28
		var text: String = f["text"]
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var col: Color = f["col"]
		ci.draw_string_outline(font, p - Vector2(tw / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, a * 0.8))
		ci.draw_string(font, p - Vector2(tw / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, a))
