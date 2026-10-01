class_name MilMeshes
extends RefCounted
## Placeholder low-poly models for the military game. Simple, readable
## shapes; replace with final art later. Keys start with "mil_".
## Units: one mesh, surface 0 fixed colours, surface 1 team-tinted.
## Buildings: "mil_b_<id>" (fixed colours) + "mil_bt_<id>" (team-tinted).

const W := Color(1, 1, 1)
const CONCRETE := Color("#c9cdd1")
const CONCRETE_D := Color("#8f969c")
const STEEL := Color("#5d6670")
const DARK := Color("#24282c")
const OLIVE := Color("#5b6b3a")
const YELLOW := Color("#f2c230")
const SKIN := Color("#f0c7a0")


static func build(key: String) -> ArrayMesh:
	if key.begins_with("mil_u_"):
		return _unit(key.substr(6))
	if key == "mil_alert":
		return _alert()
	var team := key.begins_with("mil_bt_")
	var id := key.substr(4)
	if team:
		id = key.substr(7)
	elif key.begins_with("mil_b_"):
		id = key.substr(6)
	var b := LowPoly.Builder.new()
	match id:
		"hq": _hq(b, team)
		"power_plant": _power(b, team)
		"barracks": _barracks(b, team)
		"factory": _factory(b, team)
		"drill": _drill(b, team)
		"turret": _turret(b, team)
		"wall": _wall(b, team)
		"rocks": _rocks(b)
		"scaffold": _scaffold(b)
		_: push_error("Unknown military mesh " + key)
	return b.commit()


## "No power" marker: a yellow bolt on a red disc, facing the camera.
static func _alert() -> ArrayMesh:
	var b := LowPoly.Builder.new()
	b.inside = Vector3(0, 0, -1000)
	var red := Color("#d8262b")
	var segs := 14
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		b.tri(Vector3(0, 0, -0.02), Vector3(cos(a0) * 0.62, sin(a0) * 0.62, -0.02), Vector3(cos(a1) * 0.62, sin(a1) * 0.62, -0.02), red)
	b.quad(Vector3(-0.125, 0.45, 0), Vector3(0.175, 0.45, 0), Vector3(-0.025, -0.02, 0), Vector3(-0.3, -0.02, 0), YELLOW)
	b.quad(Vector3(-0.06, 0.06, 0), Vector3(0.3, 0.06, 0), Vector3(0.06, -0.48, 0), Vector3(-0.06, -0.48, 0), YELLOW)
	return b.commit()


# ---------------------------------------------------------------- buildings

static func _pad(b: LowPoly.Builder, r: float) -> void:
	b.prism(LowPoly.hex_pts(r), 0.0, 0.06, CONCRETE_D, CONCRETE_D.darkened(0.2))


static func _hq(b: LowPoly.Builder, team: bool) -> void:
	if team:
		b.box(Vector3(0, 0.47, 0.36), Vector3(0.62, 0.08, 0.02), W)
		b.quad(Vector3(0.02, 1.3, 0), Vector3(0.3, 1.24, 0), Vector3(0.3, 1.1, 0), Vector3(0.02, 1.04, 0), W)
		return
	_pad(b, 0.85)
	b.prism(LowPoly.hex_pts(0.62), 0.06, 0.5, CONCRETE, CONCRETE_D)
	b.prism(LowPoly.hex_pts(0.42), 0.5, 0.72, CONCRETE.lightened(0.05), CONCRETE_D)
	b.box(Vector3(0, 0.2, 0.55), Vector3(0.24, 0.28, 0.06), DARK)
	b.box(Vector3(0, 1.05, 0), Vector3(0.03, 0.66, 0.03), STEEL)
	b.ball(Vector3(-0.22, 0.82, -0.1), 0.12, Color("#e8ecef"), 0.6)


static func _power(b: LowPoly.Builder, team: bool) -> void:
	if team:
		b.cylinder(Vector3(0.0, 0.42, 0.0), 0.32, 0.06, 10, W)
		return
	_pad(b, 0.8)
	b.cone(Vector3(0, 0.06, 0), 0.36, 0.78, 10, Color("#d8dde1"), 0.24)
	b.box(Vector3(0.4, 0.2, 0.2), Vector3(0.24, 0.3, 0.3), CONCRETE)
	# lightning bolt sign on the box
	b.inside = Vector3(0.4, 0.2, -1000)
	b.quad(Vector3(0.37, 0.32, 0.36), Vector3(0.43, 0.32, 0.36), Vector3(0.39, 0.2, 0.36), Vector3(0.33, 0.2, 0.36), YELLOW)
	b.quad(Vector3(0.39, 0.22, 0.36), Vector3(0.46, 0.22, 0.36), Vector3(0.41, 0.08, 0.36), Vector3(0.38, 0.08, 0.36), YELLOW)


static func _barracks(b: LowPoly.Builder, team: bool) -> void:
	if team:
		b.box(Vector3(0, 0.12, 0.36), Vector3(0.18, 0.22, 0.02), W)
		return
	_pad(b, 0.8)
	# quonset hut: a row of slabs approximating a half-cylinder
	var segs := 6
	for k in segs:
		var a0 := PI * k / segs
		var a1 := PI * (k + 1) / segs
		var p0 := Vector3(cos(a0) * 0.42, 0.06 + sin(a0) * 0.36, 0)
		var p1 := Vector3(cos(a1) * 0.42, 0.06 + sin(a1) * 0.36, 0)
		var col := OLIVE.lightened(0.05 * (k % 2))
		b.inside = Vector3(0, 0.06, 0)
		b.quad(p0 + Vector3(0, 0, -0.35), p1 + Vector3(0, 0, -0.35), p1 + Vector3(0, 0, 0.35), p0 + Vector3(0, 0, 0.35), col)
	for z in [-0.35, 0.35]:
		var pts: Array[Vector3] = []
		for k in segs + 1:
			var a := PI * k / segs
			pts.append(Vector3(cos(a) * 0.42, 0.06 + sin(a) * 0.36, z))
		b.inside = Vector3(0, 0.15, 0)
		for k in segs:
			b.tri(Vector3(0, 0.06, z), pts[k], pts[k + 1], OLIVE.darkened(0.15))


static func _factory(b: LowPoly.Builder, team: bool) -> void:
	if team:
		b.box(Vector3(0, 0.38, 0.33), Vector3(0.7, 0.06, 0.02), W)
		return
	_pad(b, 0.85)
	b.box(Vector3(-0.05, 0.28, 0), Vector3(0.8, 0.44, 0.62), Color("#a7b0b8"), 0.0, Color("#8b959e"))
	for k in 3:
		b.box(Vector3(-0.35 + k * 0.27, 0.56, 0), Vector3(0.24, 0.12, 0.6), Color("#9aa4ad"), 0.0, Color("#c3cbd1"))
	b.cylinder(Vector3(0.3, 0.5, -0.18), 0.07, 0.5, 8, STEEL)
	b.box(Vector3(-0.1, 0.18, 0.32), Vector3(0.3, 0.26, 0.02), DARK)


static func _drill(b: LowPoly.Builder, team: bool) -> void:
	if team:
		b.box(Vector3(0, 0.12, 0), Vector3(0.36, 0.12, 0.36), W)
		return
	_pad(b, 0.6)
	for k in 3:
		var a := TAU * k / 3.0
		var foot := Vector3(cos(a) * 0.3, 0.06, sin(a) * 0.3)
		var top := Vector3(0, 0.85, 0)
		var mid := (foot + top) / 2.0
		var d := top - foot
		b.box(mid, Vector3(0.05, d.length(), 0.05), STEEL, -a)
	b.cylinder(Vector3(0, 0.0, 0), 0.05, 0.9, 6, YELLOW)
	b.box(Vector3(0, 0.85, 0), Vector3(0.14, 0.08, 0.14), STEEL)


static func _turret(b: LowPoly.Builder, team: bool) -> void:
	if team:
		b.cylinder(Vector3(0, 0.3, 0), 0.25, 0.05, 8, W)
		return
	_pad(b, 0.55)
	b.cylinder(Vector3(0, 0.06, 0), 0.3, 0.24, 8, CONCRETE)
	b.box(Vector3(0, 0.45, 0), Vector3(0.36, 0.2, 0.36), STEEL)
	b.box(Vector3(0, 0.47, 0.33), Vector3(0.07, 0.07, 0.42), DARK)


static func _wall(b: LowPoly.Builder, team: bool) -> void:
	if team:
		b.box(Vector3(0, 0.36, 0), Vector3(0.7, 0.04, 0.32), W)
		return
	for k in 3:
		b.box(Vector3(-0.3 + k * 0.3, 0.17, 0), Vector3(0.28, 0.34, 0.3), CONCRETE.darkened(0.05 * (k % 2)))


static func _scaffold(b: LowPoly.Builder) -> void:
	# yellow-and-black frame shown while a building is under construction
	for x in [-0.4, 0.4]:
		for z in [-0.4, 0.4]:
			b.box(Vector3(x, 0.3, z), Vector3(0.05, 0.6, 0.05), YELLOW)
	for z in [-0.4, 0.4]:
		b.box(Vector3(0, 0.6, z), Vector3(0.85, 0.05, 0.05), YELLOW)
	for x in [-0.4, 0.4]:
		b.box(Vector3(x, 0.6, 0), Vector3(0.05, 0.05, 0.85), YELLOW)
	b.box(Vector3(0, 0.03, 0), Vector3(0.9, 0.06, 0.9), DARK)


static func _rocks(b: LowPoly.Builder) -> void:
	var g := Color("#9ea3a8")
	b.ball(Vector3(-0.2, 0.12, 0.05), 0.32, g, 0.75)
	b.ball(Vector3(0.25, 0.1, -0.12), 0.26, g.darkened(0.1), 0.8)
	b.ball(Vector3(0.1, 0.08, 0.3), 0.18, g.lightened(0.08), 0.8)
	b.ball(Vector3(-0.05, 0.3, -0.05), 0.16, g.lightened(0.04), 0.9)


# ---------------------------------------------------------------- units

static func _unit(id: String) -> ArrayMesh:
	var fixed := LowPoly.Builder.new()
	var team := LowPoly.Builder.new()
	var disc := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0
		disc.append(Vector2(cos(a), sin(a)) * 0.2)
	team.prism(disc, 0.0, 0.04, W, W.darkened(0.25))
	match id:
		"tank":
			fixed.box(Vector3(-0.17, 0.08, 0), Vector3(0.1, 0.13, 0.5), DARK)
			fixed.box(Vector3(0.17, 0.08, 0), Vector3(0.1, 0.13, 0.5), DARK)
			team.box(Vector3(0, 0.16, 0), Vector3(0.34, 0.12, 0.46), W, 0.0, W.lightened(0.0))
			team.box(Vector3(0, 0.27, -0.03), Vector3(0.22, 0.1, 0.24), W.darkened(0.1))
			fixed.box(Vector3(0, 0.28, 0.2), Vector3(0.05, 0.05, 0.34), STEEL)
			fixed.box(Vector3(0.06, 0.34, -0.08), Vector3(0.05, 0.04, 0.05), DARK)
		_:
			_soldier(fixed, team, id)
	var m := fixed.commit()
	team.commit(m)
	return m


static func _soldier(fixed: LowPoly.Builder, team: LowPoly.Builder, id: String) -> void:
	var base := Vector3(0, 0.04, 0)
	fixed.box(base + Vector3(-0.045, 0.07, 0), Vector3(0.065, 0.14, 0.075), DARK)
	fixed.box(base + Vector3(0.045, 0.07, 0), Vector3(0.065, 0.14, 0.075), DARK)
	var hip := base + Vector3(0, 0.14, 0)
	team.box(hip + Vector3(0, 0.11, 0), Vector3(0.2, 0.22, 0.14), W)
	fixed.box(hip + Vector3(0, 0.02, 0), Vector3(0.21, 0.035, 0.15), DARK)
	team.box(hip + Vector3(-0.125, 0.13, 0), Vector3(0.05, 0.16, 0.06), W.darkened(0.08))
	team.box(hip + Vector3(0.125, 0.13, 0), Vector3(0.05, 0.16, 0.06), W.darkened(0.08))
	var head := hip + Vector3(0, 0.31, 0)
	fixed.box(head, Vector3(0.15, 0.14, 0.14), SKIN)
	fixed.box(head + Vector3(-0.035, 0.0, 0.071), Vector3(0.025, 0.03, 0.005), DARK)
	fixed.box(head + Vector3(0.035, 0.0, 0.071), Vector3(0.025, 0.03, 0.005), DARK)
	match id:
		"engineer":
			fixed.box(head + Vector3(0, 0.085, 0), Vector3(0.19, 0.05, 0.18), YELLOW)
			fixed.box(head + Vector3(0, 0.12, 0), Vector3(0.12, 0.04, 0.12), YELLOW)
			fixed.box(hip + Vector3(0, 0.13, -0.11), Vector3(0.16, 0.18, 0.08), STEEL)
			fixed.box(hip + Vector3(0.17, 0.05, 0.05), Vector3(0.03, 0.18, 0.03), STEEL)
			fixed.box(hip + Vector3(0.17, 0.15, 0.05), Vector3(0.08, 0.04, 0.03), STEEL)
		"sniper":
			fixed.box(head + Vector3(0, 0.08, -0.01), Vector3(0.18, 0.06, 0.17), OLIVE)
			fixed.box(hip + Vector3(0.14, 0.18, 0.12), Vector3(0.03, 0.03, 0.6), DARK)
			fixed.box(hip + Vector3(0.14, 0.22, 0.05), Vector3(0.04, 0.04, 0.1), STEEL)
		_:
			fixed.box(head + Vector3(0, 0.08, -0.005), Vector3(0.18, 0.06, 0.17), OLIVE)
			fixed.box(head + Vector3(0, 0.115, -0.005), Vector3(0.12, 0.04, 0.12), OLIVE)
			fixed.box(hip + Vector3(0.14, 0.14, 0.1), Vector3(0.035, 0.035, 0.36), DARK)
