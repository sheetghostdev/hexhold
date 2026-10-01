class_name MatchBoard
extends Node3D
## 3D view of a MatchState: hexes, obstacles, buildings, units, fog,
## highlights and effects. Map positions are hex pixel coordinates;
## world = Vector3(px.x / Hex.SIZE, height, px.y / Hex.SIZE).

const PITCH := 0.95
const MIN_SPAN := 5.0
const MAX_SPAN := 22.0
const UNIT_SCALE := 1.6
const LAND := Color("#93bb62")
const WATER := Color("#3aa3d6")
const FOG := Color("#c6d1dc")
const SEA := Color("#22465c")

var m: MatchState
var viewer := 0
var vis := PackedByteArray()

# highlights (set by the screen)
var selected := -1
var reach := {}
var targets: Array[int] = []
var target_info := {}
var preview_idx := -1
var preview_type := ""

# animation: unit -> map position while moving
var unit_pos := {}

var cam: Camera3D
var focus := Vector3.ZERO
var span := 12.0
var _cam_tween: Tween

var mat_solid: StandardMaterial3D
var mat_water: StandardMaterial3D
var mat_overlay: StandardMaterial3D
var mat_ghost: StandardMaterial3D
var mat_preview: StandardMaterial3D
var mat_blob: StandardMaterial3D
var mat_cloud: StandardMaterial3D
var team_mats := {}
var mmi := {}
var batch := {}
var unit_nodes := {}
var labels_root: Node3D
var preview_root: Node3D
var fx_root: Node3D
var font: Font
var _time := 0.0


func _ready() -> void:
	font = UI.body_font if UI.body_font else ThemeDB.fallback_font
	_materials()
	_world()
	labels_root = Node3D.new()
	add_child(labels_root)
	preview_root = Node3D.new()
	add_child(preview_root)
	fx_root = Node3D.new()
	add_child(fx_root)
	get_viewport().size_changed.connect(_apply_camera)


func _vc(m2: StandardMaterial3D) -> StandardMaterial3D:
	m2.vertex_color_use_as_albedo = true
	m2.vertex_color_is_srgb = true
	return m2


func _materials() -> void:
	mat_solid = _vc(StandardMaterial3D.new())
	mat_solid.roughness = 0.85
	mat_solid.metallic_specular = 0.25
	mat_solid.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_solid.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	mat_water = _vc(StandardMaterial3D.new())
	mat_water.roughness = 0.2
	mat_water.metallic_specular = 0.7
	mat_overlay = _vc(StandardMaterial3D.new())
	mat_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_overlay.no_depth_test = true
	mat_overlay.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_overlay.render_priority = 2
	mat_ghost = mat_overlay.duplicate()
	mat_ghost.no_depth_test = false
	mat_ghost.render_priority = 1
	mat_preview = mat_ghost.duplicate()
	mat_preview.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat_blob = _vc(StandardMaterial3D.new())
	mat_blob.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_blob.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_cloud = _vc(StandardMaterial3D.new())
	mat_cloud.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = SEA.darkened(0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#d6e4f5")
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-58), deg_to_rad(-38), 0)
	sun.light_energy = 1.15
	sun.light_color = Color("#fff6e8")
	add_child(sun)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	sea.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = SEA
	sm.roughness = 0.4
	sea.material_override = sm
	sea.position = Vector3(8, -0.35, 8)
	add_child(sea)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.5
	cam.far = 120.0
	add_child(cam)
	cam.make_current()


func _team_mat(c: Color, dim: bool) -> StandardMaterial3D:
	var key := "%s%s" % [c.to_html(), dim]
	if not team_mats.has(key):
		var tm := mat_solid.duplicate() as StandardMaterial3D
		tm.albedo_color = c if not dim else c.lerp(Color(0.45, 0.45, 0.45), 0.55)
		team_mats[key] = tm
	return team_mats[key]


func color_of(p: int) -> Color:
	if p < 0 or p >= m.players.size():
		return Color("#9a9a9a")
	return Defs.player_color(m.players[p].color)


# ---------------------------------------------------------------- state

func set_match(state: MatchState, view_player: int) -> void:
	m = state
	viewer = view_player
	for n in unit_nodes.values():
		n.queue_free()
	unit_nodes.clear()
	refresh()


func refresh() -> void:
	if m == null:
		return
	vis = m.visible_for(viewer)
	_build_static()
	_sync_units()
	refresh_overlay()


func refresh_overlay() -> void:
	if m == null:
		return
	_build_overlay()
	_update_units()


func explored(i: int) -> bool:
	return viewer < 0 or m.players[viewer].explored[i] == 1


func seen(i: int) -> bool:
	return viewer < 0 or vis[i] == 1


func tile_at(px: Vector2) -> int:
	var o := Hex.pixel_to_offset(px)
	var i := m.idx_of(o.x, o.y)
	if i < 0 or m.ground[i] == MatchState.Ground.VOID:
		return -1
	return i


func height(i: int) -> float:
	if i < 0:
		return 0.0
	if not explored(i):
		return 0.05
	return -0.16 if m.ground[i] == MatchState.Ground.WATER else 0.0


func world(i: int) -> Vector3:
	var c := m.center_px(i) / Hex.SIZE
	return Vector3(c.x, height(i), c.y)


func px_to_world(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x / Hex.SIZE, y, p.y / Hex.SIZE)


func rest_pos(i: int) -> Vector2:
	return m.center_px(i)


# ---------------------------------------------------------------- batching

func _add(key: String, xf: Transform3D, col: Color = Color.WHITE) -> void:
	if not batch.has(key):
		batch[key] = [[], PackedColorArray()]
	batch[key][0].append(xf)
	batch[key][1].append(col)


func _flush(prefix: String) -> void:
	for key in mmi:
		if key.begins_with(prefix) and not batch.has(key):
			mmi[key].multimesh.instance_count = 0
	for key in batch:
		if not key.begins_with(prefix):
			continue
		var inst: MultiMeshInstance3D = mmi.get(key)
		if inst == null:
			inst = MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = LowPoly.get_mesh(key.split(":")[1])
			inst.multimesh = mm
			match key.split(":")[0]:
				"o": inst.material_override = mat_overlay
				"g": inst.material_override = mat_ghost
				"q": inst.material_override = mat_preview
				"w": inst.material_override = mat_water
				"b": inst.material_override = mat_blob
				"c": inst.material_override = mat_cloud
				_: inst.material_override = mat_solid
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(inst)
			mmi[key] = inst
		var xfs: Array = batch[key][0]
		var cols: PackedColorArray = batch[key][1]
		inst.multimesh.instance_count = xfs.size()
		for k in xfs.size():
			inst.multimesh.set_instance_transform(k, xfs[k])
			inst.multimesh.set_instance_color(k, cols[k])
	for key in batch.keys():
		if key.begins_with(prefix):
			batch.erase(key)


static func _xf(pos: Vector3, yaw: float = 0.0, s: float = 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), pos)


func _rand(i: int, k: int) -> float:
	return float(GameState.mix(m.map_seed, i, k) % 10000) / 10000.0


static func _yaw_to(d: Vector3) -> float:
	return atan2(-d.z, d.x)


func _dir_vec(d: int) -> Vector3:
	var a: Vector2i = Hex.AXIAL_DIRS[d]
	var v := Vector2(Hex.SQRT3 * (a.x + a.y * 0.5), 1.5 * a.y).normalized()
	return Vector3(v.x, 0, v.y)


func _shadow(pos: Vector3, s: float) -> void:
	_add("b:blob", Transform3D(Basis().scaled(Vector3(s, 1, s * 0.8)), pos + Vector3(0.05 * s, 0.012, 0.04 * s)), Color(0.05, 0.1, 0.05, 0.28))


func _tint(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


# ---------------------------------------------------------------- static scene

func _build_static() -> void:
	for c in labels_root.get_children():
		c.queue_free()
	var terr := m.territory()
	for i in m.n_tiles():
		if m.ground[i] == MatchState.Ground.VOID:
			continue
		var c := world(i)
		if not explored(i):
			_add("s:hex", _xf(Vector3(c.x, 0.05, c.z)), FOG.darkened(_rand(i, 1) * 0.05))
			_add("c:cloud", _xf(Vector3(c.x, 0.42 + _rand(i, 3) * 0.1, c.z), _rand(i, 4) * TAU, 0.95 + _rand(i, 5) * 0.2))
			continue
		var dim := 1.0 if seen(i) else 0.62
		_tile(i, c, dim, terr)
	_flush("s:")
	_flush("g:")
	_flush("w:")
	_flush("b:")
	_flush("c:")


func _tile(i: int, c: Vector3, dim: float, terr: PackedInt32Array) -> void:
	var owner := terr[i]
	var v := _rand(i, 0)
	if m.ground[i] == MatchState.Ground.WATER:
		_add("w:water", _xf(c), _tint(WATER.lightened(v * 0.06), dim))
		return
	var base := LAND.lightened(v * 0.06) if v > 0.5 else LAND.darkened((0.5 - v) * 0.08)
	if owner >= 0:
		base = base.lerp(color_of(owner), 0.16)
	_add("s:hex", _xf(c), _tint(base, dim))
	var white := _tint(Color.WHITE, dim)
	# obstacles
	var o := m.obstacle_def(i)
	if o != null:
		var left := float(m.amount[i]) / maxf(1.0, o.amount)
		if o.id == "trees":
			var spots := [Vector2(-0.35, -0.2), Vector2(0.32, -0.28), Vector2(0.0, 0.32), Vector2(-0.3, 0.38), Vector2(0.42, 0.3)]
			var count := maxi(1, int(ceil(left * spots.size())))
			for k in count:
				var p: Vector2 = spots[k]
				var s := 1.05 + _rand(i, 30 + k) * 0.3
				_add("s:pine" if _rand(i, 40 + k) > 0.4 else "s:tree", _xf(c + Vector3(p.x, 0, p.y), _rand(i, 50 + k) * TAU, s), white)
				_shadow(c + Vector3(p.x, 0, p.y), 0.75 * s)
		else:
			_add("s:mil_rocks", _xf(c, _rand(i, 9) * TAU, 0.6 + 0.6 * left), white)
			_shadow(c, 1.6)
	# territory border
	if owner >= 0:
		var oc := _tint(color_of(owner).lightened(0.15), dim)
		for d in 6:
			var j := m.idx_from_axial(m.axial(i) + Hex.AXIAL_DIRS[d])
			if j >= 0 and terr[j] == owner:
				continue
			var dir := _dir_vec(d)
			_add("s:border", Transform3D(Basis(Vector3.UP, _yaw_to(dir) + PI / 2).scaled(Vector3(0.9, 1, 1)), c + dir * 0.79 + Vector3(0, 0.005, 0)), oc)
	# buildings
	var b := m.building_on(i)
	if b != null:
		_building(b, c, dim)


func _building(b: MatchState.Building, c: Vector3, dim: float) -> void:
	var d := b.def()
	var col := _tint(color_of(b.owner), dim)
	var white := _tint(Color.WHITE, dim)
	var yaw := 0.0
	if b.build_left > 0:
		_add("g:mil_b_" + b.type, _xf(c), Color(1, 1, 1, 0.45))
		_add("s:mil_b_scaffold", _xf(c), white)
	else:
		_add("s:mil_b_" + b.type, _xf(c, yaw), white)
		_add("s:mil_bt_" + b.type, _xf(c, yaw), col)
	_shadow(c, 2.2)
	# clean label: short name + state
	var text := d.short
	if b.build_left > 0:
		text += "  %d" % b.build_left
	var l := _label(c + Vector3(0, 0.05, 0.72), text, Color.WHITE, 34)
	l.outline_modulate = color_of(b.owner).darkened(0.5)
	if b.hp < d.hp and b.build_left == 0:
		var hl := _label(c + Vector3(0, 1.25, 0), "%d/%d" % [b.hp, d.hp], Color("#ffd7a8"), 30)
		hl.outline_modulate = Color(0.25, 0.05, 0.05)


func _label(pos: Vector3, text: String, col: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = 0.006
	l.modulate = col
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.75)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 3
	l.outline_render_priority = 2
	l.position = pos
	labels_root.add_child(l)
	return l


# ---------------------------------------------------------------- overlay

func _build_overlay() -> void:
	var lift := 0.06
	for c in preview_root.get_children():
		c.queue_free()
	for i in reach:
		_add("o:dot", _xf(world(i) + Vector3(0, lift, 0)), Color(1, 1, 1, 0.9))
	for i in targets:
		_add("o:ring", _xf(world(i) + Vector3(0, lift, 0), 0.0, 0.95), Color("#ff3b3b"))
		_add("o:hexfill", _xf(world(i) + Vector3(0, lift, 0)), Color(1, 0.2, 0.2, 0.18))
		if target_info.has(i):
			var info: Array = target_info[i]
			var pl := Label3D.new()
			pl.text = "-%d%s" % [info[0], " KO" if info[1] else ""]
			pl.font = font
			pl.font_size = 50
			pl.pixel_size = 0.006
			pl.outline_size = 18
			pl.outline_modulate = Color("#c0262b")
			pl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			pl.no_depth_test = true
			pl.render_priority = 6
			pl.outline_render_priority = 5
			pl.position = world(i) + Vector3(0.05, 1.7, 0)
			preview_root.add_child(pl)
	if preview_idx >= 0 and preview_type != "":
		var pc := world(preview_idx)
		var tint := color_of(viewer).lightened(0.35)
		_add("q:mil_b_" + preview_type, _xf(pc), Color(1, 1, 1, 1))
		_add("q:mil_bt_" + preview_type, _xf(pc), Color(tint.r, tint.g, tint.b, 1))
		# hexes this building would add to your territory
		var terr := m.territory()
		var d := DB.building(preview_type)
		for j in m.in_range(preview_idx, d.territory):
			if terr[j] != viewer and m.ground[j] == MatchState.Ground.LAND:
				var tc := color_of(viewer).lightened(0.2)
				_add("o:hexfill", _xf(world(j) + Vector3(0, lift, 0)), Color(tc.r, tc.g, tc.b, 0.45))
	if selected >= 0:
		_add("o:hexline", _xf(world(selected) + Vector3(0, lift, 0)), Color(1, 1, 1, 0.95))
	_flush("o:")
	_flush("q:")


# ---------------------------------------------------------------- units

func _sync_units() -> void:
	var alive := {}
	for u in m.units:
		alive[u] = true
		if not unit_nodes.has(u):
			unit_nodes[u] = _make_unit(u)
	for u in unit_nodes.keys():
		if not alive.has(u):
			var n: Node3D = unit_nodes[u]
			var tw := n.create_tween()
			tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_callback(n.queue_free)
			unit_nodes.erase(u)


func _make_unit(u: MatchState.UnitS) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = LowPoly.get_mesh("mil_u_" + u.type)
	root.add_child(mi)
	var blob := MeshInstance3D.new()
	blob.mesh = LowPoly.get_mesh("blob")
	var bm := mat_blob.duplicate() as StandardMaterial3D
	bm.albedo_color = Color(0.05, 0.1, 0.05, 0.3)
	blob.material_override = bm
	blob.position = Vector3(0.02, 0.015, 0.02)
	root.add_child(blob)
	var hp := Label3D.new()
	hp.name = "HP"
	hp.font = font
	hp.font_size = 32
	hp.pixel_size = 0.006
	hp.outline_size = 12
	hp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp.no_depth_test = true
	hp.render_priority = 4
	hp.outline_render_priority = 3
	hp.position = Vector3(0, 0.78, 0)
	root.add_child(hp)
	root.rotation.y = deg_to_rad(-20)
	root.position = px_to_world(rest_pos(u.idx), height(u.idx))
	add_child(root)
	root.scale = Vector3.ONE * 0.2
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3.ONE * UNIT_SCALE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


func _update_units() -> void:
	for u in unit_nodes:
		var n: Node3D = unit_nodes[u]
		var animating := unit_pos.has(u)
		var show: bool = u.owner == viewer or (seen(u.idx) and explored(u.idx)) or animating
		n.visible = show
		if not show:
			continue
		var col := color_of(u.owner)
		var spent: bool = u.owner == m.cur and u.owner == viewer and _spent(u)
		var body: MeshInstance3D = n.get_node("Body")
		body.set_surface_override_material(0, _team_mat(Color.WHITE, true) if spent else mat_solid)
		if body.mesh.get_surface_count() > 1:
			body.set_surface_override_material(1, _team_mat(col, spent))
		var hp: Label3D = n.get_node("HP")
		var maxhp: int = u.def().hp
		hp.text = str(u.hp)
		hp.modulate = Color.WHITE if u.hp * 2 > maxhp else (Color("#ffcf5c") if u.hp * 4 > maxhp else Color("#ff6b5b"))
		hp.outline_modulate = col.darkened(0.5)
		if not animating:
			n.position = px_to_world(rest_pos(u.idx), height(u.idx))


func _spent(u: MatchState.UnitS) -> bool:
	if u.fresh or u.attacked:
		return true
	return u.moved and m.attack_targets(u).is_empty()


func _process(delta: float) -> void:
	_time += delta
	if m == null:
		return
	mat_overlay.albedo_color.a = 0.8 + 0.2 * sin(_time * 5.0)
	mat_preview.albedo_color.a = 0.8 + 0.2 * sin(_time * 4.0)
	if mmi.has("c:cloud"):
		mmi["c:cloud"].position = Vector3(sin(_time * 0.3) * 0.05, sin(_time * 0.8) * 0.03, 0)
	for u in unit_pos:
		var n: Node3D = unit_nodes.get(u)
		if n == null:
			continue
		var p: Vector2 = unit_pos[u]
		var target := px_to_world(p, height(tile_at(p)))
		n.position = Vector3(target.x, lerpf(n.position.y, target.y, 0.35) + absf(sin(_time * 16.0)) * 0.1, target.z)
		n.visible = true
	for u in unit_nodes:
		var body: Node3D = unit_nodes[u].get_node("Body")
		var ready: bool = u.owner == m.cur and u.owner == viewer and not u.moved and not u.fresh and not u.attacked
		body.position.y = absf(sin(_time * 3.0 + u.id)) * 0.05 if ready else 0.0


# ---------------------------------------------------------------- effects

func float_text(px: Vector2, text: String, col: Color, big: bool = false) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 64 if big else 52
	l.pixel_size = 0.006
	l.modulate = col
	l.outline_size = 16
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 5
	l.outline_render_priority = 4
	l.position = px_to_world(px, height(tile_at(px)) + 0.9)
	fx_root.add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 0.8, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.8)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.5).set_delay(0.8)
	tw.chain().tween_callback(l.queue_free)


func burst(px: Vector2, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = LowPoly.get_mesh("ring")
	var bm := mat_overlay.duplicate() as StandardMaterial3D
	bm.albedo_color = col
	mi.material_override = bm
	mi.position = px_to_world(px, height(tile_at(px)) + 0.08)
	mi.scale = Vector3(0.3, 1, 0.3)
	fx_root.add_child(mi)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.5, 1, 1.5), 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_property(bm, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(mi.queue_free)


# ---------------------------------------------------------------- camera

func _apply_camera() -> void:
	if cam == null:
		return
	var vp := get_viewport().get_visible_rect().size
	cam.keep_aspect = Camera3D.KEEP_WIDTH if vp.x < vp.y else Camera3D.KEEP_HEIGHT
	cam.size = span
	cam.position = focus + Vector3(0, sin(PITCH), cos(PITCH)) * 40.0
	cam.rotation = Vector3(-PITCH, 0, 0)


func _clamp_focus() -> void:
	if m == null:
		return
	var lo := Vector2(-1.0, -1.0)
	var hi := Vector2(m.w * Hex.SQRT3 + 1.0, (m.h - 1) * 1.5 + 2.0)
	focus = Vector3(clampf(focus.x, lo.x, hi.x), 0.0, clampf(focus.z, lo.y, hi.y))


func screen_to_ground(screen: Vector2, y: float = 0.0) -> Vector3:
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if absf(d.y) < 1e-4:
		return o
	return o + d * ((y - o.y) / d.y)


func screen_to_map(screen: Vector2) -> Vector2:
	var g := screen_to_ground(screen)
	return Vector2(g.x, g.z) * Hex.SIZE


func pan(from_screen: Vector2, to_screen: Vector2) -> void:
	_stop_cam_tween()
	focus += screen_to_ground(from_screen) - screen_to_ground(to_screen)
	_clamp_focus()
	_apply_camera()


func zoom_at(screen: Vector2, factor: float) -> void:
	_stop_cam_tween()
	var before := screen_to_ground(screen)
	span = clampf(span / factor, MIN_SPAN, MAX_SPAN)
	_apply_camera()
	focus += before - screen_to_ground(screen)
	_clamp_focus()
	_apply_camera()


func look_at_tile(i: int, animate: bool = false) -> void:
	var target := world(i)
	target.y = 0.0
	target.z += span * 0.15
	var old := focus
	focus = target
	_clamp_focus()
	if not animate:
		_apply_camera()
		return
	var dest := focus
	focus = old
	_stop_cam_tween()
	_cam_tween = create_tween()
	_cam_tween.tween_method(_set_focus, old, dest, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_focus(p: Vector3) -> void:
	focus = p
	_apply_camera()


func _stop_cam_tween() -> void:
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
