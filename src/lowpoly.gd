class_name LowPoly
extends RefCounted
## Procedural low-poly meshes (flat shaded, vertex coloured).
## Parts coloured WHITE are meant to be tinted per instance (team colours,
## terrain colours); everything else keeps its own colour.
## World units: hex radius = 1, +Y is up, map X/Y -> world X/Z.

const W := Color(1, 1, 1)
const STONE := Color("#d9d4c7")
const STONE_D := Color("#a59e8f")
const WOOD := Color("#9a6332")
const WOOD_D := Color("#6e4320")
const LEAF := Color("#4cc35a")
const LEAF_D := Color("#2f9a45")
const PINE := Color("#2d8f4e")
const SKIN := Color("#f2c49b")
const STEEL := Color("#dfe6ee")
const GOLD := Color("#ffcc33")
const DARK := Color("#2b2320")
const ROOFLESS_WALL := Color("#f6eedc")

static var _cache := {}


class Builder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	## Faces are oriented to point away from this point (shape centre).
	var inside := Vector3(0, -1000, 0)

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			return
		n = n.normalized()
		if n.dot((a + b + c) / 3.0 - inside) < 0.0:
			var t := b
			b = c
			c = t
			n = -n
		# Godot uses clockwise winding for front faces
		verts.append_array([a, c, b])
		normals.append_array([n, n, n])
		colors.append_array([col, col, col])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		tri(a, b, c, col)
		tri(a, c, d, col)

	## Polygon (convex, counter-clockwise seen from above) extruded from y0 to y1.
	func prism(pts: PackedVector2Array, y0: float, y1: float, top: Color, side: Color, bottom := false) -> void:
		var n := pts.size()
		var c := Vector3.ZERO
		for p in pts:
			c += Vector3(p.x, y1, p.y)
		c /= n
		inside = Vector3(c.x, (y0 + y1) / 2.0, c.z)
		for i in n:
			var a := pts[i]
			var b := pts[(i + 1) % n]
			tri(c, Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), top)
			quad(Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(b.x, y0, b.y), Vector3(a.x, y0, a.y), side)
			if bottom:
				tri(Vector3(c.x, y0, c.z), Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), side)

	func box(center: Vector3, size: Vector3, col: Color, yaw := 0.0, top_col = null) -> void:
		var h := size / 2.0
		inside = center
		var b := Basis(Vector3.UP, yaw)
		var p := func(x: float, y: float, z: float) -> Vector3:
			return center + b * Vector3(x * h.x, y * h.y, z * h.z)
		var tc: Color = col if top_col == null else top_col
		var sc := col.darkened(0.08)
		quad(p.call(-1, 1, -1), p.call(1, 1, -1), p.call(1, 1, 1), p.call(-1, 1, 1), tc)  # top
		quad(p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, -1, -1), p.call(-1, -1, -1), sc)  # bottom
		quad(p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, -1, 1), p.call(-1, -1, 1), col)  # front (+z)
		quad(p.call(1, 1, -1), p.call(-1, 1, -1), p.call(-1, -1, -1), p.call(1, -1, -1), sc)  # back
		quad(p.call(1, 1, 1), p.call(1, 1, -1), p.call(1, -1, -1), p.call(1, -1, 1), sc)  # right
		quad(p.call(-1, 1, -1), p.call(-1, 1, 1), p.call(-1, -1, 1), p.call(-1, -1, -1), col)  # left

	func cone(base: Vector3, r: float, h: float, segs: int, col: Color, tip_r := 0.0, yaw := 0.0) -> void:
		var top := base + Vector3(0, h, 0)
		inside = base + Vector3(0, h * 0.3, 0)
		for i in segs:
			var a0 := yaw + TAU * i / segs
			var a1 := yaw + TAU * (i + 1) / segs
			var p0 := base + Vector3(cos(a0), 0, sin(a0)) * r
			var p1 := base + Vector3(cos(a1), 0, sin(a1)) * r
			var shade := col.darkened(0.06 * ((i % 2)))
			if tip_r <= 0.0:
				tri(top, p1, p0, shade)
			else:
				var q0 := top + Vector3(cos(a0), 0, sin(a0)) * tip_r
				var q1 := top + Vector3(cos(a1), 0, sin(a1)) * tip_r
				quad(q0, q1, p1, p0, shade)
				tri(top, q1, q0, col.lightened(0.05))
			tri(base, p0, p1, col.darkened(0.2))

	func cylinder(base: Vector3, r: float, h: float, segs: int, col: Color, top_col = null) -> void:
		var pts := PackedVector2Array()
		for i in segs:
			var a := TAU * i / segs
			pts.append(Vector2(base.x + cos(a) * r, base.z + sin(a) * r))
		prism(pts, base.y, base.y + h, col if top_col == null else top_col, col)

	## Low-poly ball (icosahedron), optionally squashed.
	func ball(c: Vector3, r: float, col: Color, squash := 1.0) -> void:
		var t := (1.0 + sqrt(5.0)) / 2.0
		var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
		var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
			[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
			[6, 2, 10], [8, 6, 7], [9, 8, 1]]
		inside = c
		for face in f:
			var pts := []
			for k in face:
				var p: Vector3 = v[k].normalized() * r
				p.y *= squash
				pts.append(c + p)
			var shade := col
			var avg_y: float = (pts[0].y + pts[1].y + pts[2].y) / 3.0 - c.y
			if avg_y < 0:
				shade = col.darkened(0.12)
			# icosahedron faces listed counter-clockwise from outside
			tri(pts[0], pts[2], pts[1], shade)

	func commit(mesh: ArrayMesh = null) -> ArrayMesh:
		var m := mesh if mesh else ArrayMesh.new()
		if verts.is_empty():
			return m
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_COLOR] = colors
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


static func hex_pts(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


static func get_mesh(key: String) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	var m: ArrayMesh
	if key.begins_with("unit_"):
		m = _unit(int(key.substr(5)))
	else:
		match key:
			"hex": _m_hex(b)
			"water": _m_water(b)
			"tree": _m_tree(b)
			"pine": _m_pine(b)
			"hill": _m_hill(b)
			"mountain": _m_mountain(b)
			"rock": _m_rock(b)
			"flowers": _m_flowers(b)
			"nugget": _m_nugget(b)
			"cloud": _m_cloud(b)
			"ruin": _m_ruin(b)
			"tent": _m_tent(b)
			"farm": _m_farm(b)
			"lumber": _m_lumber(b)
			"quarry": _m_quarry(b)
			"mine": _m_mine(b)
			"market": _m_market(b)
			"awning": _m_awning(b)
			"house": _m_house(b)
			"roof": _m_roof(b)
			"keep": _m_keep(b)
			"flag": _m_flag(b)
			"townwall": _m_townwall(b)
			"wallseg": _m_wallseg(b)
			"wallpost": _m_wallpost(b)
			"tower": _m_tower(b)
			"roadseg": _m_roadseg(b)
			"roadnode": _m_roadnode(b)
			"bridgeseg": _m_bridgeseg(b)
			"border": _m_border(b)
			"dot": _m_dot(b)
			"ring": _m_ring(b)
			"hexline": _m_hexline(b)
			"hexfill": _m_hexfill(b)
			"cross": _m_cross(b)
			"star": _m_star(b)
			"pole": _m_pole(b)
			"blob": _m_blob(b)
			_: push_error("Unknown mesh " + key)
		m = b.commit()
	_cache[key] = m
	return m


# ---------------------------------------------------------------- terrain

static func _m_hex(b: Builder) -> void:
	# top at y=0, white top and earthy sides for per-tile tinting;
	# a slight bevel ring makes neighbouring tiles readable
	b.prism(hex_pts(1.0), -1.2, -0.03, Color(0.9, 0.9, 0.9), Color(0.62, 0.55, 0.48))
	var outer := hex_pts(1.0)
	var inner := hex_pts(0.9)
	b.inside = Vector3(0, -1000, 0)
	for i in 6:
		var j := (i + 1) % 6
		b.quad(Vector3(outer[i].x, -0.03, outer[i].y), Vector3(outer[j].x, -0.03, outer[j].y),
			Vector3(inner[j].x, 0.0, inner[j].y), Vector3(inner[i].x, 0.0, inner[i].y), Color(0.93, 0.93, 0.93))
		b.tri(Vector3.ZERO, Vector3(inner[j].x, 0, inner[j].y), Vector3(inner[i].x, 0, inner[i].y), W)


static func _m_water(b: Builder) -> void:
	var pts := hex_pts(1.0)
	for i in 6:
		var a := pts[i]
		var c := pts[(i + 1) % 6]
		b.tri(Vector3.ZERO, Vector3(c.x, 0, c.y), Vector3(a.x, 0, a.y), W.darkened(0.04 * (i % 2)))


static func _m_tree(b: Builder) -> void:
	b.cylinder(Vector3(0, 0, 0), 0.05, 0.22, 5, WOOD_D)
	b.ball(Vector3(0, 0.34, 0), 0.2, LEAF, 1.1)
	b.ball(Vector3(0.04, 0.5, -0.02), 0.13, LEAF.lightened(0.1), 1.1)


static func _m_pine(b: Builder) -> void:
	b.cylinder(Vector3(0, 0, 0), 0.045, 0.14, 5, WOOD_D)
	b.cone(Vector3(0, 0.1, 0), 0.22, 0.32, 6, PINE)
	b.cone(Vector3(0, 0.3, 0), 0.16, 0.28, 6, PINE.lightened(0.08))


static func _m_hill(b: Builder) -> void:
	# white so it takes the tile tint
	b.ball(Vector3(0, 0, 0), 0.42, W, 0.5)


static func _m_mountain(b: Builder) -> void:
	var rock := Color("#9ba3ad")
	b.cone(Vector3(0, 0, 0), 0.62, 0.62, 5, rock, 0.18, 0.3)
	b.cone(Vector3(0, 0.62, 0), 0.18, 0.28, 5, Color("#f7f9fb"), 0.0, 0.3)
	b.cone(Vector3(0.42, 0, 0.3), 0.36, 0.42, 5, rock.darkened(0.08), 0.1, 1.0)
	b.cone(Vector3(0.42, 0.42, 0.3), 0.1, 0.14, 5, Color("#f7f9fb"), 0.0, 1.0)


static func _m_rock(b: Builder) -> void:
	b.ball(Vector3(0, 0.03, 0), 0.12, Color("#c3c0b8"), 0.7)
	b.ball(Vector3(0.14, 0.02, 0.06), 0.08, Color("#adaaa2"), 0.7)


static func _m_flowers(b: Builder) -> void:
	var cols := [Color("#ffe14d"), Color("#ff9f43"), Color("#ffffff"), Color("#ff6b9a")]
	for k in 5:
		var a := k * 2.4
		var p := Vector3(cos(a), 0, sin(a)) * (0.25 + 0.12 * (k % 2))
		b.ball(p + Vector3(0, 0.04, 0), 0.045, cols[k % 4], 0.8)


static func _m_nugget(b: Builder) -> void:
	for k in 3:
		var a := k * 2.1
		b.ball(Vector3(cos(a) * 0.12, 0.05, sin(a) * 0.12), 0.07, GOLD, 1.0)


static func _m_cloud(b: Builder) -> void:
	# unshaded: shading is baked into the colours (top faces bright)
	var c := Color("#ffffff")
	b.ball(Vector3(0, 0, 0), 0.55, c, 0.62)
	b.ball(Vector3(0.45, -0.06, 0.15), 0.4, c, 0.62)
	b.ball(Vector3(-0.45, -0.05, -0.1), 0.42, c, 0.62)
	b.ball(Vector3(0.05, 0.12, -0.35), 0.36, c, 0.62)
	for k in b.colors.size():
		var n := b.normals[k]
		var lit := clampf(0.78 + 0.22 * n.dot(Vector3(-0.3, 0.9, 0.3).normalized()), 0.7, 1.0)
		b.colors[k] = Color(lit * 0.97, lit * 0.98, lit, 1.0)


# ---------------------------------------------------------------- features

static func _m_ruin(b: Builder) -> void:
	b.prism(hex_pts(0.42), 0, 0.06, STONE, STONE_D)
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		var hgt: float = [0.42, 0.24, 0.36, 0.14][k]
		b.cylinder(Vector3(cos(a) * 0.28, 0.06, sin(a) * 0.28), 0.06, hgt, 6, STONE)
	b.box(Vector3(0.05, 0.5, -0.08), Vector3(0.5, 0.07, 0.12), STONE.darkened(0.04), 0.4)
	b.ball(Vector3(0, 0.2, 0), 0.09, GOLD, 1.0)


static func _m_tent(b: Builder) -> void:
	b.cone(Vector3(0, 0, 0), 0.32, 0.45, 4, Color("#c0392b"), 0.0, PI / 4)
	b.box(Vector3(0, 0.1, 0.2), Vector3(0.1, 0.2, 0.04), DARK)
	b.cylinder(Vector3(0.38, 0, 0.18), 0.08, 0.03, 6, Color("#555555"))
	b.cone(Vector3(0.38, 0.03, 0.18), 0.06, 0.14, 5, Color("#ff8c1a"))


# ---------------------------------------------------------------- buildings

static func _m_farm(b: Builder) -> void:
	var crops := [Color("#f5cf3a"), Color("#e9b92c"), Color("#9bd34a")]
	for k in 3:
		var z := (k - 1) * 0.3
		b.box(Vector3(0, 0.025, z), Vector3(0.95, 0.05, 0.24), Color("#8c5a2b"))
		for j in 5:
			b.box(Vector3(-0.36 + j * 0.18, 0.08, z), Vector3(0.12, 0.08, 0.2), crops[k])


static func _m_lumber(b: Builder) -> void:
	for k in 3:
		var y := 0.07 + (0.12 if k == 2 else 0.0)
		var x := (-0.08 + (k % 2) * 0.16) if k < 2 else 0.0
		b.box(Vector3(x, y, 0), Vector3(0.14, 0.14, 0.55), WOOD, 0.0, WOOD.lightened(0.1))
		b.box(Vector3(x, y, 0.276), Vector3(0.1, 0.1, 0.01), Color("#e2b47c"))
	b.cylinder(Vector3(0.38, 0, 0.2), 0.09, 0.12, 7, WOOD, Color("#e2b47c"))
	b.box(Vector3(0.38, 0.2, 0.2), Vector3(0.03, 0.18, 0.03), WOOD_D)
	b.box(Vector3(0.42, 0.27, 0.2), Vector3(0.1, 0.06, 0.02), STEEL)


static func _m_quarry(b: Builder) -> void:
	var s := Color("#cfd3d6")
	b.box(Vector3(-0.18, 0.08, 0.1), Vector3(0.26, 0.16, 0.22), s)
	b.box(Vector3(0.14, 0.08, 0.14), Vector3(0.24, 0.16, 0.2), s.darkened(0.06))
	b.box(Vector3(-0.02, 0.24, 0.12), Vector3(0.24, 0.16, 0.2), s.lightened(0.05))
	b.box(Vector3(0.2, 0.06, -0.2), Vector3(0.2, 0.12, 0.18), s.darkened(0.1), 0.5)
	b.box(Vector3(-0.3, 0.25, -0.2), Vector3(0.04, 0.5, 0.04), WOOD)
	b.box(Vector3(-0.18, 0.48, -0.2), Vector3(0.28, 0.04, 0.04), WOOD)


static func _m_mine(b: Builder) -> void:
	b.ball(Vector3(0, 0, -0.05), 0.4, Color("#8f7a5c"), 0.6)
	b.box(Vector3(0, 0.12, 0.3), Vector3(0.26, 0.24, 0.06), DARK)
	b.box(Vector3(-0.15, 0.13, 0.31), Vector3(0.04, 0.27, 0.06), WOOD)
	b.box(Vector3(0.15, 0.13, 0.31), Vector3(0.04, 0.27, 0.06), WOOD)
	b.box(Vector3(0, 0.27, 0.31), Vector3(0.34, 0.04, 0.06), WOOD)
	b.box(Vector3(0.36, 0.07, 0.35), Vector3(0.16, 0.1, 0.12), WOOD_D)
	b.ball(Vector3(0.36, 0.14, 0.35), 0.06, GOLD)


static func _m_market(b: Builder) -> void:
	b.box(Vector3(0, 0.1, 0), Vector3(0.6, 0.2, 0.36), Color("#e8c48f"))
	for x in [-0.28, 0.28]:
		for z in [-0.16, 0.16]:
			b.box(Vector3(x, 0.25, z), Vector3(0.04, 0.5, 0.04), WOOD)
	b.ball(Vector3(-0.12, 0.25, 0.05), 0.07, Color("#ff5e57"))
	b.ball(Vector3(0.05, 0.25, 0.08), 0.07, Color("#ffd23f"))
	b.ball(Vector3(0.18, 0.25, 0.02), 0.07, Color("#7bd389"))


## Awning: tinted with the owner's colour.
static func _m_awning(b: Builder) -> void:
	b.inside = Vector3(0, -1000, 0)
	b.quad(Vector3(-0.34, 0.5, -0.24), Vector3(0.34, 0.5, -0.24), Vector3(0.34, 0.42, 0.26), Vector3(-0.34, 0.42, 0.26), W)
	b.quad(Vector3(-0.34, 0.42, 0.26), Vector3(0.34, 0.42, 0.26), Vector3(0.34, 0.5, -0.24), Vector3(-0.34, 0.5, -0.24), W.darkened(0.2))


static func _m_house(b: Builder) -> void:
	b.box(Vector3(0, 0.1, 0), Vector3(0.24, 0.2, 0.2), ROOFLESS_WALL)
	b.box(Vector3(0, 0.07, 0.101), Vector3(0.06, 0.14, 0.01), WOOD_D)


## House roof: tinted with the owner's colour.
static func _m_roof(b: Builder) -> void:
	var y0 := 0.2
	var y1 := 0.36
	var hw := 0.15
	var hd := 0.13
	b.quad(Vector3(-hw, y0, hd), Vector3(hw, y0, hd), Vector3(hw, y1, 0), Vector3(-hw, y1, 0), W)
	b.quad(Vector3(hw, y0, -hd), Vector3(-hw, y0, -hd), Vector3(-hw, y1, 0), Vector3(hw, y1, 0), W.darkened(0.18))
	b.tri(Vector3(-hw, y0, -hd), Vector3(-hw, y0, hd), Vector3(-hw, y1, 0), ROOFLESS_WALL.darkened(0.08))
	b.tri(Vector3(hw, y0, hd), Vector3(hw, y0, -hd), Vector3(hw, y1, 0), ROOFLESS_WALL.darkened(0.08))


static func _m_keep(b: Builder) -> void:
	b.box(Vector3(0, 0.3, 0), Vector3(0.44, 0.6, 0.44), STONE)
	for x in [-1, 1]:
		for z in [-1, 1]:
			b.box(Vector3(x * 0.2, 0.67, z * 0.2), Vector3(0.1, 0.14, 0.1), STONE)
	b.box(Vector3(0, 0.67, 0.2), Vector3(0.1, 0.14, 0.1), STONE)
	b.box(Vector3(0, 0.67, -0.2), Vector3(0.1, 0.14, 0.1), STONE)
	b.box(Vector3(0.2, 0.67, 0), Vector3(0.1, 0.14, 0.1), STONE)
	b.box(Vector3(-0.2, 0.67, 0), Vector3(0.1, 0.14, 0.1), STONE)
	b.box(Vector3(0, 0.13, 0.221), Vector3(0.14, 0.26, 0.01), DARK)
	b.box(Vector3(0, 0.42, 0.221), Vector3(0.06, 0.1, 0.01), DARK)
	b.box(Vector3(0, 0.95, 0), Vector3(0.025, 0.5, 0.025), WOOD_D)


## Flag cloth: tinted with the owner's colour. Origin at the pole top.
static func _m_flag(b: Builder) -> void:
	b.inside = Vector3(0.1, -0.1, -1000)
	b.quad(Vector3(0, 0, 0), Vector3(0.26, -0.05, 0), Vector3(0.26, -0.15, 0), Vector3(0, -0.2, 0), W)
	b.quad(Vector3(0, -0.2, 0), Vector3(0.26, -0.15, 0), Vector3(0.26, -0.05, 0), Vector3(0, 0, 0), W.darkened(0.15))


static func _m_blob(b: Builder) -> void:
	var segs := 12
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		b.tri(Vector3.ZERO, Vector3(cos(a1), 0, sin(a1)) * 0.3, Vector3(cos(a0), 0, sin(a0)) * 0.3, W)


static func _m_pole(b: Builder) -> void:
	b.box(Vector3(0, 0.38, 0), Vector3(0.025, 0.76, 0.025), WOOD_D)


static func _m_townwall(b: Builder) -> void:
	var pts := hex_pts(0.72)
	for i in 6:
		var a := Vector3(pts[i].x, 0, pts[i].y)
		var c := Vector3(pts[(i + 1) % 6].x, 0, pts[(i + 1) % 6].y)
		if i == 1:
			continue  # gate gap toward the camera
		_wall_span(b, a, c, 0.16, 0.08)
		b.cylinder(a, 0.08, 0.26, 6, STONE.lightened(0.04))


static func _wall_span(b: Builder, a: Vector3, c: Vector3, h: float, w: float) -> void:
	var d := c - a
	var mid := (a + c) / 2.0
	var yaw := atan2(-d.z, d.x)
	b.box(mid + Vector3(0, h / 2, 0), Vector3(d.length(), h, w), STONE, yaw, STONE.lightened(0.05))
	var n := maxi(2, int(d.length() / 0.12))
	for k in n:
		if k % 2 == 1:
			continue
		var p := a + d * ((k + 0.5) / n)
		b.box(p + Vector3(0, h + 0.035, 0), Vector3(d.length() / n * 0.9, 0.07, w), STONE, yaw)


## Wall from the tile centre to an edge (length ~0.87), pointing +X.
static func _m_wallseg(b: Builder) -> void:
	_wall_span(b, Vector3(0, 0, 0), Vector3(0.9, 0, 0), 0.3, 0.2)


static func _m_wallpost(b: Builder) -> void:
	b.box(Vector3(0, 0.19, 0), Vector3(0.28, 0.38, 0.28), STONE.lightened(0.03))
	for x in [-1, 1]:
		for z in [-1, 1]:
			b.box(Vector3(x * 0.1, 0.42, z * 0.1), Vector3(0.08, 0.08, 0.08), STONE)


static func _m_tower(b: Builder) -> void:
	b.cylinder(Vector3(0, 0, 0), 0.3, 0.75, 8, STONE, STONE.lightened(0.05))
	b.cylinder(Vector3(0, 0.75, 0), 0.36, 0.08, 8, STONE_D)
	for k in 8:
		if k % 2 == 1:
			continue
		var a := TAU * k / 8.0 + TAU / 16.0
		b.box(Vector3(cos(a) * 0.31, 0.89, sin(a) * 0.31), Vector3(0.12, 0.12, 0.12), STONE, -a)
	b.box(Vector3(0, 0.16, 0.3), Vector3(0.13, 0.26, 0.04), DARK)
	b.box(Vector3(0, 0.5, 0.29), Vector3(0.05, 0.1, 0.04), DARK)
	b.box(Vector3(0, 1.08, 0), Vector3(0.025, 0.4, 0.025), WOOD_D)


## Road from centre to an edge, pointing +X. Slightly raised above the ground.
static func _m_roadseg(b: Builder) -> void:
	b.box(Vector3(0.45, 0.02, 0), Vector3(0.9, 0.04, 0.26), Color("#c99a5b"), 0.0, Color("#d9ae72"))
	b.box(Vector3(0.45, 0.03, 0), Vector3(0.9, 0.04, 0.12), Color("#e3c08a"))


static func _m_roadnode(b: Builder) -> void:
	b.prism(hex_pts(0.16), 0.0, 0.05, Color("#e3c08a"), Color("#c99a5b"))


static func _m_bridgeseg(b: Builder) -> void:
	for k in 7:
		b.box(Vector3(0.07 + k * 0.13, 0.05, 0), Vector3(0.1, 0.05, 0.36), WOOD.lightened(0.05 * (k % 2)))
	b.box(Vector3(0.45, 0.1, 0.18), Vector3(0.9, 0.04, 0.03), WOOD_D)
	b.box(Vector3(0.45, 0.1, -0.18), Vector3(0.9, 0.04, 0.03), WOOD_D)


static func _m_border(b: Builder) -> void:
	# a thin strip along an edge, length 1, pointing +X; tinted per owner
	b.box(Vector3(0, 0.02, 0), Vector3(1.0, 0.04, 0.07), W)


# ---------------------------------------------------------------- overlay

static func _m_dot(b: Builder) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0
		pts.append(Vector2(cos(a), sin(a)) * 0.13)
	b.prism(pts, 0, 0.03, W, W)


static func _m_ring(b: Builder) -> void:
	var segs := 24
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var r0 := 0.62
		var r1 := 0.74
		b.quad(Vector3(cos(a0) * r1, 0, sin(a0) * r1), Vector3(cos(a1) * r1, 0, sin(a1) * r1),
			Vector3(cos(a1) * r0, 0, sin(a1) * r0), Vector3(cos(a0) * r0, 0, sin(a0) * r0), W)


static func _m_hexline(b: Builder) -> void:
	var outer := hex_pts(0.97)
	var inner := hex_pts(0.84)
	for i in 6:
		var j := (i + 1) % 6
		b.quad(Vector3(outer[i].x, 0, outer[i].y), Vector3(outer[j].x, 0, outer[j].y),
			Vector3(inner[j].x, 0, inner[j].y), Vector3(inner[i].x, 0, inner[i].y), W)


static func _m_hexfill(b: Builder) -> void:
	var pts := hex_pts(0.94)
	for i in 6:
		var j := (i + 1) % 6
		b.tri(Vector3.ZERO, Vector3(pts[j].x, 0, pts[j].y), Vector3(pts[i].x, 0, pts[i].y), W)


static func _m_cross(b: Builder) -> void:
	b.box(Vector3.ZERO, Vector3(0.6, 0.04, 0.12), W, PI / 4)
	b.box(Vector3.ZERO, Vector3(0.6, 0.04, 0.12), W, -PI / 4)


static func _m_star(b: Builder) -> void:
	b.inside = Vector3(0, 0, -1000)
	var pts := []
	for i in 10:
		var rr := 0.14 if i % 2 == 0 else 0.06
		var a := -PI / 2 + i * PI / 5
		pts.append(Vector3(cos(a) * rr, sin(a) * rr, 0))
	for i in 10:
		b.tri(Vector3(0, 0, 0.03), pts[(i + 1) % 10], pts[i], GOLD)
		b.tri(Vector3(0, 0, -0.03), pts[i], pts[(i + 1) % 10], GOLD.darkened(0.15))


# ---------------------------------------------------------------- units

## Units have two surfaces: 0 = fixed colours, 1 = team colour (tinted).
static func _unit(type: int) -> ArrayMesh:
	var fixed := Builder.new()
	var team := Builder.new()
	# base disc
	var disc := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0
		disc.append(Vector2(cos(a), sin(a)) * 0.2)
	team.prism(disc, 0.0, 0.04, W, W.darkened(0.25))
	match type:
		Defs.U.KNIGHT:
			_horse(fixed, team)
			_person(fixed, team, Vector3(0, 0.36, 0), 0.8, true)
			fixed.box(Vector3(0.16, 0.6, 0.05), Vector3(0.03, 0.03, 0.62), WOOD, 0.0)
			fixed.cone(Vector3(0.16, 0.6, 0.36), 0.035, 0.1, 4, STEEL)
		Defs.U.CATAPULT:
			fixed.box(Vector3(0, 0.14, 0), Vector3(0.42, 0.06, 0.24), WOOD)
			for x in [-0.15, 0.15]:
				for z in [-0.14, 0.14]:
					fixed.cylinder(Vector3(x, 0.03, z), 0.07, 0.04, 6, WOOD_D)
			fixed.box(Vector3(0, 0.26, -0.06), Vector3(0.06, 0.2, 0.06), WOOD_D)
			fixed.box(Vector3(-0.05, 0.36, 0.02), Vector3(0.05, 0.05, 0.5), WOOD, 0.0)
			fixed.box(Vector3(-0.05, 0.38, 0.27), Vector3(0.12, 0.06, 0.12), WOOD_D)
			fixed.ball(Vector3(-0.05, 0.44, 0.27), 0.05, Color("#8a8a8a"))
			team.box(Vector3(0.12, 0.2, -0.12), Vector3(0.12, 0.08, 0.02), W)
		_:
			var bandit := type == Defs.U.BANDIT
			_person(fixed, team, Vector3(0, 0.04, 0), 1.0, false, bandit)
			match type:
				Defs.U.SPEARMAN:
					fixed.box(Vector3(0.15, 0.36, 0.02), Vector3(0.025, 0.66, 0.025), WOOD)
					fixed.cone(Vector3(0.15, 0.69, 0.02), 0.04, 0.12, 4, STEEL)
					team.box(Vector3(-0.13, 0.28, 0.06), Vector3(0.05, 0.22, 0.17), W, 0.3)
				Defs.U.ARCHER:
					var cx := 0.16
					for k in 5:
						var a0 := -1.1 + k * 0.44
						var a1 := a0 + 0.44
						var p0 := Vector3(cx + cos(a0) * 0.04, 0.33 + sin(a0) * 0.2, 0.08)
						var p1 := Vector3(cx + cos(a1) * 0.04, 0.33 + sin(a1) * 0.2, 0.08)
						fixed.box((p0 + p1) / 2.0, Vector3(0.025, p0.distance_to(p1) + 0.01, 0.025), WOOD_D)
					team.box(Vector3(-0.08, 0.36, -0.12), Vector3(0.08, 0.2, 0.06), W, 0.0)
				Defs.U.SWORDSMAN:
					fixed.box(Vector3(0.15, 0.42, 0.06), Vector3(0.035, 0.34, 0.02), STEEL)
					fixed.box(Vector3(0.15, 0.25, 0.06), Vector3(0.1, 0.025, 0.03), WOOD_D)
					team.cylinder(Vector3(-0.15, 0.18, 0.04), 0.11, 0.035, 6, W)
					# shield faces sideways: build a flat round shield
					fixed.ball(Vector3(-0.17, 0.3, 0.04), 0.03, GOLD)
				Defs.U.BANDIT:
					fixed.box(Vector3(0.14, 0.3, 0.06), Vector3(0.025, 0.18, 0.02), STEEL)
	var m := fixed.commit()
	team.commit(m)
	return m


static func _person(fixed: Builder, team: Builder, base: Vector3, s: float, riding: bool, bandit := false) -> void:
	var cloth := Color("#5b4636")
	var body: Builder = fixed if bandit else team
	var body_col := cloth if bandit else W
	if not riding:
		fixed.box(base + Vector3(-0.045, 0.07, 0) * s, Vector3(0.065, 0.14, 0.075) * s, Color("#4a3a2e"))
		fixed.box(base + Vector3(0.045, 0.07, 0) * s, Vector3(0.065, 0.14, 0.075) * s, Color("#4a3a2e"))
	var hip := base + Vector3(0, (0.14 if not riding else 0.02), 0) * s
	# torso: a slightly tapered hexagonal block
	body.cone(hip, 0.12 * s, 0.22 * s, 6, body_col, 0.09 * s, PI / 6)
	fixed.box(hip + Vector3(0, 0.03, 0) * s, Vector3(0.2, 0.035, 0.17) * s, Color("#3a2c22"))
	# arms
	body.box(hip + Vector3(-0.125, 0.13, 0.0) * s, Vector3(0.05, 0.16, 0.06) * s, body_col, 0.0)
	body.box(hip + Vector3(0.125, 0.13, 0.0) * s, Vector3(0.05, 0.16, 0.06) * s, body_col, 0.0)
	fixed.ball(hip + Vector3(-0.125, 0.04, 0.0) * s, 0.032 * s, SKIN)
	fixed.ball(hip + Vector3(0.125, 0.04, 0.0) * s, 0.032 * s, SKIN)
	# head with eyes
	var head := hip + Vector3(0, 0.31, 0) * s
	fixed.box(head, Vector3(0.15, 0.14, 0.14) * s, SKIN, 0.0, SKIN.lightened(0.05))
	fixed.box(head + Vector3(-0.035, 0.0, 0.071) * s, Vector3(0.025, 0.035, 0.005) * s, DARK)
	fixed.box(head + Vector3(0.035, 0.0, 0.071) * s, Vector3(0.025, 0.035, 0.005) * s, DARK)
	if bandit:
		fixed.box(head + Vector3(0, 0.08, -0.01) * s, Vector3(0.18, 0.06, 0.17) * s, Color("#2e241d"))
		fixed.box(head + Vector3(0, -0.035, 0.072) * s, Vector3(0.15, 0.05, 0.005) * s, Color("#2e241d"))
	else:
		fixed.box(head + Vector3(0, 0.085, -0.005) * s, Vector3(0.17, 0.05, 0.16) * s, STEEL, 0.0, STEEL.lightened(0.05))
		fixed.box(head + Vector3(0, 0.125, -0.005) * s, Vector3(0.1, 0.04, 0.1) * s, STEEL.darkened(0.05))


static func _horse(fixed: Builder, team: Builder) -> void:
	var c := Color("#b07a4a")
	fixed.box(Vector3(0, 0.26, 0), Vector3(0.18, 0.16, 0.42), c)
	for x in [-0.06, 0.06]:
		for z in [-0.15, 0.15]:
			fixed.box(Vector3(x, 0.12, z), Vector3(0.05, 0.18, 0.05), c.darkened(0.15))
	fixed.box(Vector3(0, 0.38, 0.22), Vector3(0.1, 0.18, 0.1), c, 0.0)
	fixed.box(Vector3(0, 0.44, 0.3), Vector3(0.09, 0.08, 0.16), c.lightened(0.05))
	fixed.box(Vector3(0, 0.36, -0.24), Vector3(0.04, 0.14, 0.04), DARK)
	team.box(Vector3(0, 0.33, 0), Vector3(0.2, 0.04, 0.24), W)
