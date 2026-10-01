class_name Board
extends Node3D
## The 3D map: low-poly terrain, roads, walls, towns and units, lit by a
## sun and seen through a tilted orthographic camera (Polytopia style).
## Map positions are the 2D hex pixel coordinates from Hex/GameState;
## world = Vector3(map.x / Hex.SIZE, height, map.y / Hex.SIZE).

const PITCH := 0.95  # camera tilt below horizontal (radians, ~54°)
const MIN_SPAN := 4.5
const UNIT_SCALE := 1.75
const MAX_SPAN := 26.0

const TERRAIN_COL := [
	Color("#38b6ee"),  # water (shallow)
	Color("#84e03a"),  # plains
	Color("#55cc35"),  # forest floor
	Color("#bfe052"),  # hills
	Color("#a7b0b8"),  # mountain base
]
const TERRAIN_H := [-0.16, 0.0, 0.0, 0.1, 0.14]
const FOG_TILE := Color("#cfdbe8")
const OCEAN := Color("#1f86d6")
const NEUTRAL_ROOF := Color("#c0623a")

var gs: GameState
var viewer := 0
var vis := PackedByteArray()

# highlight state, set by the game screen
var selected := -1
var reach := {}
var targets: Array[int] = []
var target_info := {}  # tile -> [damage, kills, would_lose_attacker]
var plan: Array[int] = []
var plan_kind := ""
var plan_ok := {}
var capture_hint := -1

# animation: Unit -> map position (Vector2) while it moves
var unit_pos := {}

# camera
var cam: Camera3D
var focus := Vector3.ZERO
var span := 8.5
var _cam_tween: Tween

# rendering
var mat_solid: StandardMaterial3D
var mat_water: StandardMaterial3D
var mat_overlay: StandardMaterial3D
var mat_ghost: StandardMaterial3D
var mat_blob: StandardMaterial3D
var mat_cloud: StandardMaterial3D
var team_mats := {}
var mmi := {}       # key -> MultiMeshInstance3D
var batch := {}     # key -> [Array[Transform3D], PackedColorArray]
var unit_nodes := {}  # Unit -> Node3D
var labels_root: Node3D
var preview_root: Node3D
var mat_pip: StandardMaterial3D
var fx_root: Node3D
var clouds_root: Node3D
var font: Font
var _time := 0.0
var drift := false  # slow cinematic camera (menu backdrop)


func _ready() -> void:
	font = UI.body_font if UI.body_font else ThemeDB.fallback_font
	_setup_materials()
	_setup_world()
	labels_root = Node3D.new()
	add_child(labels_root)
	preview_root = Node3D.new()
	add_child(preview_root)
	fx_root = Node3D.new()
	add_child(fx_root)
	get_viewport().size_changed.connect(_apply_camera)


func _setup_materials() -> void:
	mat_solid = StandardMaterial3D.new()
	mat_solid.vertex_color_use_as_albedo = true
	mat_solid.vertex_color_is_srgb = true
	mat_solid.roughness = 0.85
	mat_solid.metallic_specular = 0.25
	mat_solid.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_solid.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	mat_water = StandardMaterial3D.new()
	mat_water.vertex_color_use_as_albedo = true
	mat_water.vertex_color_is_srgb = true
	mat_water.roughness = 0.2
	mat_water.metallic_specular = 0.7
	mat_overlay = StandardMaterial3D.new()
	mat_overlay.vertex_color_use_as_albedo = true
	mat_overlay.vertex_color_is_srgb = true
	mat_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_overlay.no_depth_test = true
	mat_overlay.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_overlay.render_priority = 2
	mat_blob = StandardMaterial3D.new()
	mat_blob.vertex_color_use_as_albedo = true
	mat_blob.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_blob.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_blob.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_cloud = StandardMaterial3D.new()
	mat_cloud.vertex_color_use_as_albedo = true
	mat_cloud.vertex_color_is_srgb = true
	mat_cloud.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_pip = mat_overlay.duplicate()
	mat_pip.render_priority = 3
	mat_ghost = mat_overlay.duplicate()
	mat_ghost.no_depth_test = false
	mat_ghost.render_priority = 1


func _setup_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = OCEAN.darkened(0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#cfe3ff")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-58), deg_to_rad(-38), 0)
	sun.light_energy = 1.2
	sun.light_color = Color("#fff4e0")
	sun.shadow_enabled = false  # blob shadows instead: cheaper on phones
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.0
	add_child(sun)
	var ocean := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ocean.mesh = pm
	var om := StandardMaterial3D.new()
	om.albedo_color = OCEAN
	om.roughness = 0.25
	om.metallic_specular = 0.6
	ocean.material_override = om
	ocean.position = Vector3(10, -0.3, 12)
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.5
	cam.far = 120.0
	add_child(cam)
	cam.make_current()
	clouds_root = Node3D.new()
	add_child(clouds_root)


func _team_mat(color: Color, dim: bool) -> StandardMaterial3D:
	var key := "%s%s" % [color.to_html(), dim]
	if team_mats.has(key):
		return team_mats[key]
	var m := mat_solid.duplicate() as StandardMaterial3D
	m.albedo_color = color if not dim else color.lerp(Color(0.45, 0.45, 0.45), 0.55)
	team_mats[key] = m
	return m


func _solid_dim() -> StandardMaterial3D:
	return _team_mat(Color(1, 1, 1), true)


# ---------------------------------------------------------------- state

func set_state(state: GameState, view_player: int) -> void:
	gs = state
	viewer = view_player
	for n in unit_nodes.values():
		n.queue_free()
	unit_nodes.clear()
	refresh()


func refresh() -> void:
	if gs == null:
		return
	vis = gs.visible_for(viewer)
	_build_static()
	_sync_units()
	refresh_overlay()


func refresh_overlay() -> void:
	if gs == null:
		return
	_build_overlay()
	_update_units()


func explored(i: int) -> bool:
	return viewer < 0 or gs.players[viewer].explored[i] == 1


func seen(i: int) -> bool:
	return viewer < 0 or vis[i] == 1


func tile_at(map: Vector2) -> int:
	var o := Hex.pixel_to_offset(map)
	return gs.idx_of(o.x, o.y)


func height(i: int) -> float:
	if i < 0:
		return 0.0
	return TERRAIN_H[gs.terrain[i]] if explored(i) else 0.05


func world(i: int) -> Vector3:
	var c := gs.center(i) / Hex.SIZE
	return Vector3(c.x, height(i), c.y)


func map_to_world(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x / Hex.SIZE, y, p.y / Hex.SIZE)


## Where a unit stands on a tile (map coords): beside the keep on towns.
func rest_pos(i: int) -> Vector2:
	if gs.town_at.has(i):
		return gs.center(i) + Vector2(Hex.SIZE * 0.32, Hex.SIZE * 0.22)
	return gs.center(i)


func _color_of(p: int) -> Color:
	if p < 0 or p >= gs.players.size():
		return Defs.NEUTRAL_COLOR
	return Defs.player_color(gs.players[p].color)


# ---------------------------------------------------------------- batching

func _add(key: String, xf: Transform3D, col: Color = Color.WHITE) -> void:
	if not batch.has(key):
		batch[key] = [[], PackedColorArray()]
	batch[key][0].append(xf)
	batch[key][1].append(col)


func _flush(keys_prefix: String) -> void:
	# empty every multimesh with this prefix that got no instances this time
	for key in mmi:
		if key.begins_with(keys_prefix) and not batch.has(key):
			mmi[key].multimesh.instance_count = 0
	for key in batch:
		if not key.begins_with(keys_prefix):
			continue
		var inst: MultiMeshInstance3D = mmi.get(key)
		if inst == null:
			inst = MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			var mesh_key: String = key.split(":")[1]
			mm.mesh = LowPoly.get_mesh(mesh_key)
			inst.multimesh = mm
			match key.split(":")[0]:
				"o":
					inst.material_override = mat_overlay
					inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				"g":
					inst.material_override = mat_ghost
					inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				"p":
					inst.material_override = mat_pip
					inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				"c":
					inst.material_override = mat_cloud
					inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				"b":
					inst.material_override = mat_blob
					inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				"w":
					inst.material_override = mat_water
					inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_:
					inst.material_override = mat_solid
			add_child(inst)
			mmi[key] = inst
		var xfs: Array = batch[key][0]
		var cols: PackedColorArray = batch[key][1]
		var mm2 := inst.multimesh
		mm2.instance_count = xfs.size()
		for k in xfs.size():
			mm2.set_instance_transform(k, xfs[k])
			mm2.set_instance_color(k, cols[k])
	for key in batch.keys():
		if key.begins_with(keys_prefix):
			batch.erase(key)


static func _xf(pos: Vector3, yaw: float = 0.0, s: float = 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), pos)


func _rand(i: int, k: int) -> float:
	return float(GameState.mix(gs.map_seed, i, k) % 10000) / 10000.0


## yaw that turns +X toward a map direction
static func _yaw_to(d: Vector3) -> float:
	return atan2(-d.z, d.x)


# ---------------------------------------------------------------- static scene

func _build_static() -> void:
	for c in labels_root.get_children():
		c.queue_free()
	for c in clouds_root.get_children():
		c.queue_free()
	var n := gs.n_tiles()
	for i in n:
		var c := world(i)
		if not explored(i):
			_add("s:hex", _xf(Vector3(c.x, 0.05, c.z)), FOG_TILE.darkened(_rand(i, 1) * 0.05))
			var cloud := _xf(Vector3(c.x + (_rand(i, 2) - 0.5) * 0.3, 0.42 + _rand(i, 3) * 0.12, c.z), _rand(i, 4) * TAU, 0.95 + _rand(i, 5) * 0.25)
			_add("c:cloud", cloud)
			continue
		var dim := 1.0 if seen(i) else 0.62
		_tile(i, c, dim)
	_flush("s:")
	_flush("w:")
	_flush("b:")
	_flush("c:")
	for t in gs.towns:
		if explored(t.idx):
			_town_label(t)
	_flush("p:")


func _tint(col: Color, dim: float) -> Color:
	return Color(col.r * dim, col.g * dim, col.b * dim, col.a)


func _tile(i: int, c: Vector3, dim: float) -> void:
	var ter := gs.terrain[i]
	var owner := gs.tile_owner(i)
	var base: Color = TERRAIN_COL[ter]
	var v := _rand(i, 0)
	base = base.lightened(v * 0.06) if v > 0.5 else base.darkened((0.5 - v) * 0.08)
	if owner >= 0 and ter != Defs.T.WATER:
		base = base.lerp(_color_of(owner), 0.1)
	if ter == Defs.T.WATER:
		_add("w:water", _xf(c), _tint(base, dim))
	else:
		_add("s:hex", _xf(c), _tint(base, dim))
	var white := _tint(Color.WHITE, dim)
	var b := gs.building[i]
	var f := gs.feature[i]
	var town := gs.town_on(i)
	# terrain decoration
	match ter:
		Defs.T.FOREST:
			var count := 5 if f == Defs.F.OLD_GROWTH else 4
			if b != Defs.B.NONE:
				count = 2
			var spots := [Vector2(-0.4, -0.2), Vector2(0.35, -0.3), Vector2(0.05, 0.38), Vector2(-0.25, 0.42), Vector2(0.45, 0.3)]
			if b != Defs.B.NONE:
				spots = [Vector2(-0.55, -0.25), Vector2(0.5, -0.38)]
			for k in mini(count, spots.size()):
				var p: Vector2 = spots[k] + Vector2(_rand(i, 10 + k) - 0.5, _rand(i, 20 + k) - 0.5) * 0.15
				var s := (1.1 + _rand(i, 30 + k) * 0.35) * (1.25 if f == Defs.F.OLD_GROWTH else 1.0)
				var key := "s:pine" if _rand(i, 40 + k) > 0.45 else "s:tree"
				_add(key, _xf(c + Vector3(p.x, 0, p.y), _rand(i, 50 + k) * TAU, s), white)
				_shadow(c + Vector3(p.x, 0, p.y), 0.75 * s)
		Defs.T.HILLS:
			if b == Defs.B.NONE:
				var hc := _tint(base.lightened(0.06), 1.0)
				_add("s:hill", _xf(c + Vector3(-0.28, 0, -0.12), 0.0, 1.0), hc)
				_add("s:hill", _xf(c + Vector3(0.3, 0, 0.22), 1.0, 0.75), hc)
		Defs.T.MOUNTAIN:
			_add("s:mountain", _xf(c + Vector3(-0.1, 0, 0.0), _rand(i, 6) * 0.8 - 0.4, 0.95 + _rand(i, 7) * 0.2), white)
			_shadow(c + Vector3(0.05, 0, 0.05), 2.6)
	match f:
		Defs.F.FERTILE:
			if b == Defs.B.NONE and town == null:
				_add("s:flowers", _xf(c, _rand(i, 8) * TAU), white)
		Defs.F.STONE:
			if b == Defs.B.NONE:
				_add("s:rock", _xf(c + Vector3(0.05, 0, 0.35), _rand(i, 9) * TAU), white)
		Defs.F.GOLD:
			if b == Defs.B.NONE:
				var off := Vector3(0.3, 0.02, 0.35) if ter == Defs.T.MOUNTAIN else Vector3(0.0, 0.0, 0.32)
				_add("s:nugget", _xf(c + off, _rand(i, 9) * TAU), white)
		Defs.F.RUIN:
			_add("s:ruin", _xf(c, _rand(i, 9) * TAU), white)
		Defs.F.CAMP:
			_add("s:tent", _xf(c + Vector3(-0.15, 0, -0.1), 0.3), white)
	# territory border
	if owner >= 0:
		var oc := _tint(_color_of(owner).lightened(0.1), dim)
		for d in 6:
			var j := gs.neighbor_dir(i, d)
			if j >= 0 and gs.tile_owner(j) == owner:
				continue
			var dir := _dir_vec(d)
			var pos := c + dir * 0.79 + Vector3(0, 0.005, 0)
			var edge_yaw := _yaw_to(dir) + PI / 2
			_add("s:border", Transform3D(Basis(Vector3.UP, edge_yaw).scaled(Vector3(0.9, 1, 1)), pos), oc)
	# roads
	if gs.road[i] != 0 or town != null:
		_roads(i, c, white)
	# buildings
	match b:
		Defs.B.FARM:
			_add("s:farm", _xf(c, 0.25 if v > 0.5 else -0.2), white)
		Defs.B.LUMBER:
			_add("s:lumber", _xf(c + Vector3(0.05, 0, 0.1), 0.4), white)
		Defs.B.QUARRY:
			_add("s:quarry", _xf(c, 0.2), white)
		Defs.B.MINE:
			_add("s:mine", _xf(c + Vector3(0, 0, -0.05)), white)
		Defs.B.MARKET:
			_add("s:market", _xf(c), white)
			_add("s:awning", _xf(c), _tint(_color_of(owner), dim))
		Defs.B.WALL, Defs.B.TOWER:
			_walls(i, c, owner, dim)
	if town != null:
		_town(town, c, dim)


## Soft dark disc under an object, nudged away from the sun.
func _shadow(pos: Vector3, s: float) -> void:
	_add("b:blob", Transform3D(Basis().scaled(Vector3(s, 1, s * 0.8)), pos + Vector3(0.05 * s, 0.012, 0.04 * s)), Color(0.05, 0.12, 0.05, 0.28))


func _dir_vec(d: int) -> Vector3:
	var a: Vector2i = Hex.AXIAL_DIRS[d]
	var v := Vector2(Hex.SQRT3 * (a.x + a.y * 0.5), 1.5 * a.y).normalized()
	return Vector3(v.x, 0, v.y)


func _roads(i: int, c: Vector3, white: Color) -> void:
	var water := gs.terrain[i] == Defs.T.WATER
	var y := 0.0 if water else c.y
	var any := false
	for d in 6:
		var j := gs.neighbor_dir(i, d)
		if j < 0 or not explored(j):
			continue
		var link := gs.road[j] != 0 or gs.town_at.has(j)
		if not link or (gs.town_at.has(i) and gs.town_at.has(j)):
			continue
		if gs.town_at.has(i) and gs.road[j] == 0:
			continue
		any = true
		var key := "s:bridgeseg" if water else "s:roadseg"
		_add(key, _xf(Vector3(c.x, y + 0.001, c.z), _yaw_to(_dir_vec(d))), white)
	if not gs.town_at.has(i) and not water:
		_add("s:roadnode", _xf(Vector3(c.x, y + 0.002, c.z)), white)
	elif water and not any:
		_add("s:bridgeseg", _xf(Vector3(c.x - 0.45, y, c.z)), white)


func _wall_link(j: int, owner: int) -> bool:
	if gs.is_structure(j) and gs.tile_owner(j) == owner:
		return true
	var t := gs.town_on(j)
	return t != null and t.owner == owner


func _walls(i: int, c: Vector3, owner: int, dim: float) -> void:
	var stone := _tint(Color.WHITE, dim)
	var links := 0
	for d in 6:
		var j := gs.neighbor_dir(i, d)
		if j >= 0 and _wall_link(j, owner):
			_add("s:wallseg", _xf(c, _yaw_to(_dir_vec(d))), stone)
			links += 1
	if links == 0:
		_add("s:wallseg", _xf(c, 0.0), stone)
		_add("s:wallseg", _xf(c, PI), stone)
	if gs.building[i] == Defs.B.TOWER:
		_add("s:tower", _xf(c), stone)
		_shadow(c, 1.6)
		_add("s:flag", _xf(c + Vector3(0.0, 1.28, 0)), _tint(_color_of(owner), dim))
	else:
		_add("s:wallpost", _xf(c), stone)
	var maxhp: int = Defs.BUILDINGS[gs.building[i]]["hp"]
	if gs.bhp[i] < maxhp:
		_label(c + Vector3(0, 1.0, 0), "%d/%d" % [gs.bhp[i], maxhp], Color("#ffd7a8"), 34)


func _town(t: GameState.Town, c: Vector3, dim: float) -> void:
	var roof := _tint(_color_of(t.owner) if t.owner >= 0 else NEUTRAL_ROOF, dim)
	var white := _tint(Color.WHITE, dim)
	var spots := [Vector3(-0.42, 0, 0.18), Vector3(0.05, 0, -0.45), Vector3(-0.45, 0, -0.28),
		Vector3(0.42, 0, -0.25), Vector3(-0.1, 0, 0.5), Vector3(0.5, 0, 0.5)]
	var count := mini(t.level + 1, spots.size())
	var start := 0
	if t.capital:
		_add("s:keep", _xf(c + Vector3(-0.08, 0, -0.08)), white)
		_shadow(c + Vector3(-0.08, 0, -0.08), 1.9)
		_add("s:flag", _xf(c + Vector3(-0.08, 1.2, -0.08)), roof)
		start = 1
	for k in range(start, count + start):
		var p: Vector3 = spots[k % spots.size()]
		var yaw := (_rand(t.idx, 60 + k) - 0.5) * 0.6
		var s := 1.15 + _rand(t.idx, 70 + k) * 0.25
		_add("s:house", _xf(c + p, yaw, s), white)
		_shadow(c + p, 0.9 * s)
		_add("s:roof", _xf(c + p, yaw, s), roof)
	if t.walls:
		_add("s:townwall", _xf(c), white)
	if not t.capital and t.owner >= 0:
		# a banner pole marks owned towns
		_add("s:flag", _xf(c + Vector3(-0.05, 0.75, -0.05)), roof)
		_add("s:pole", _xf(c + Vector3(-0.05, 0.0, -0.05)), white)


## Town name, level badge and a bar of people (pips) toward the next level.
func _town_label(t: GameState.Town) -> void:
	var c := world(t.idx)
	var col := _color_of(t.owner) if t.owner >= 0 else Color("#e8e2d6")
	var l := _label(c + Vector3(0, 0.05, 0.74), t.name, Color.WHITE, 42)
	l.outline_modulate = col.darkened(0.45) if t.owner >= 0 else Color("#4a4038")
	l.outline_size = 16
	if t.owner < 0:
		return
	var need := gs.pop_need(t.level)
	var step := 0.15
	var width := need * step + 0.3
	var base := c + Vector3(-width / 2.0, -0.04, 0.98)
	var lv := _label(base + Vector3(0.1, 0.02, 0), str(t.level), Icons.GOLD_C, 40)
	lv.outline_size = 14
	lv.outline_modulate = Color(0.15, 0.1, 0.02)
	var face := Basis(Vector3.RIGHT, -PITCH)
	for k in need:
		var pos := base + Vector3(0.32 + k * step, 0, 0)
		var on := k < t.pop
		_add("p:pip", Transform3D(face, pos), Color("#7bd389") if on else Color(0.1, 0.12, 0.15, 0.75))


func _label(pos: Vector3, text: String, col: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = 0.006
	l.modulate = col
	l.outline_size = 12
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
	for i in reach:
		_add("o:dot", _xf(world(i) + Vector3(0, lift, 0)), Color(1, 1, 1, 0.9))
	for c in preview_root.get_children():
		c.queue_free()
	for i in targets:
		_add("o:ring", _xf(world(i) + Vector3(0, lift, 0), 0.0, 0.95), Color("#ff3b3b"))
		_add("o:hexfill", _xf(world(i) + Vector3(0, lift, 0)), Color(1, 0.2, 0.2, 0.18))
		if target_info.has(i):
			var info: Array = target_info[i]
			var text := "-%d" % info[0]
			if info[1]:
				text += " KO"
			var pl := Label3D.new()
			pl.text = text
			pl.font = font
			pl.font_size = 50
			pl.pixel_size = 0.006
			pl.modulate = Color("#ffffff")
			pl.outline_size = 18
			pl.outline_modulate = Color("#c0262b") if not info[2] else Color("#5a1010")
			pl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			pl.no_depth_test = true
			pl.render_priority = 6
			pl.outline_render_priority = 5
			pl.position = world(i) + Vector3(0.05, 1.75, 0)
			preview_root.add_child(pl)
	if capture_hint >= 0:
		_add("o:ring", _xf(world(capture_hint) + Vector3(0, lift, 0), 0.0, 1.15), Color(Icons.GOLD_C, 0.95))
	if selected >= 0:
		_add("o:hexline", _xf(world(selected) + Vector3(0, lift, 0)), Color(1, 1, 1, 0.95))
	if not plan.is_empty():
		var plan_set := {}
		for i in plan:
			plan_set[i] = true
		for i in plan:
			var c := world(i)
			var ok: bool = plan_ok.get(i, false)
			if not ok:
				_add("o:cross", _xf(c + Vector3(0, lift, 0)), Color("#ff3b3b"))
				continue
			if plan_kind == "road":
				var water := gs.terrain[i] == Defs.T.WATER
				var y := 0.0 if water else c.y
				_add("g:roadnode", _xf(Vector3(c.x, y + 0.01, c.z)), Color(1, 1, 1, 0.85))
				for d in 6:
					var j := gs.neighbor_dir(i, d)
					if j >= 0 and (plan_set.has(j) or gs.has_road(j)):
						_add("g:roadseg", _xf(Vector3(c.x, y + 0.01, c.z), _yaw_to(_dir_vec(d))), Color(1, 1, 1, 0.75))
			else:
				_add("g:wallpost", _xf(c), Color(1, 1, 1, 0.7))
				for d in 6:
					var j := gs.neighbor_dir(i, d)
					if j >= 0 and (plan_set.has(j) or _wall_link(j, viewer)):
						_add("g:wallseg", _xf(c, _yaw_to(_dir_vec(d))), Color(1, 1, 1, 0.7))
	_flush("o:")
	_flush("g:")


# ---------------------------------------------------------------- units

func _sync_units() -> void:
	var alive := {}
	for u in gs.units:
		alive[u] = true
		if not unit_nodes.has(u):
			unit_nodes[u] = _make_unit(u)
	for u in unit_nodes.keys():
		if not alive.has(u):
			_unit_death(unit_nodes[u])
			unit_nodes.erase(u)


func _make_unit(u: GameState.Unit) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = LowPoly.get_mesh("unit_%d" % u.type)
	mi.name = "Body"
	root.add_child(mi)
	var hp := Label3D.new()
	hp.name = "HP"
	hp.font = font
	hp.font_size = 34
	hp.pixel_size = 0.006
	hp.outline_size = 12
	hp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp.no_depth_test = true
	hp.render_priority = 4
	hp.outline_render_priority = 3
	hp.position = Vector3(0.0, 0.8, 0)
	root.add_child(hp)
	var blob := MeshInstance3D.new()
	blob.mesh = LowPoly.get_mesh("blob")
	var bm := mat_blob.duplicate() as StandardMaterial3D
	bm.albedo_color = Color(0.05, 0.12, 0.05, 0.3)
	blob.material_override = bm
	blob.position = Vector3(0.02, 0.015, 0.02)
	blob.scale = Vector3(1.0, 1, 0.8)
	root.add_child(blob)
	var star := MeshInstance3D.new()
	star.name = "Star"
	star.mesh = LowPoly.get_mesh("star")
	star.material_override = mat_solid
	star.position = Vector3(-0.2, 0.8, 0)
	root.add_child(star)
	root.rotation.y = deg_to_rad(-20)
	var p := rest_pos(u.idx)
	root.position = map_to_world(p, height(u.idx))
	add_child(root)
	# pop in
	root.scale = Vector3(0.2, 0.2, 0.2)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3.ONE * UNIT_SCALE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


func _unit_death(n: Node3D) -> void:
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3(0.01, 0.01, 0.01), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(n.queue_free)


func _update_units() -> void:
	for u in unit_nodes:
		var n: Node3D = unit_nodes[u]
		var animating := unit_pos.has(u)
		var show: bool = u.owner == viewer or (seen(u.idx) and explored(u.idx)) or animating
		n.visible = show
		if not show:
			continue
		var col := Defs.BANDIT_COLOR if u.owner < 0 else _color_of(u.owner)
		var spent: bool = u.owner == gs.cur and u.owner == viewer and _spent(u)
		var body: MeshInstance3D = n.get_node("Body")
		body.set_surface_override_material(0, _solid_dim() if spent else mat_solid)
		if body.mesh.get_surface_count() > 1:
			body.set_surface_override_material(1, _team_mat(col, spent))
		var maxhp := Defs.unit_max_hp(u.type, u.kills)
		var hp: Label3D = n.get_node("HP")
		hp.text = str(u.hp)
		hp.modulate = Color.WHITE if u.hp * 2 > maxhp else (Color("#ffcf5c") if u.hp * 4 > maxhp else Color("#ff6b5b"))
		hp.outline_modulate = col.darkened(0.5)
		n.get_node("Star").visible = u.kills >= Defs.VETERAN_KILLS
		var small := gs.town_at.has(u.idx) and not animating
		var s := UNIT_SCALE * (0.85 if small else 1.0)
		if not animating and n.scale.x > 0.5 * UNIT_SCALE:
			n.scale = Vector3(s, s, s)
		if not animating:
			n.position = map_to_world(rest_pos(u.idx), height(u.idx))


func _spent(u: GameState.Unit) -> bool:
	if u.fresh or u.attacked:
		return true
	if u.moved and gs.attack_targets(u).is_empty() and not gs.can_capture(u):
		return true
	return false


func _process(delta: float) -> void:
	_time += delta
	if gs == null:
		return
	mat_overlay.albedo_color.a = 0.8 + 0.2 * sin(_time * 5.0)
	if mmi.has("c:cloud"):
		mmi["c:cloud"].position = Vector3(sin(_time * 0.3) * 0.05, sin(_time * 0.8) * 0.03, 0)
	if mmi.has("w:water"):
		mmi["w:water"].position.y = sin(_time * 1.3) * 0.012
	if drift:
		var mid := Vector3((gs.w - 0.5) * Hex.SQRT3 * 0.5, 0, (gs.h - 1) * 0.75)
		focus = mid + Vector3(sin(_time * 0.07) * gs.w * 0.45, 0, cos(_time * 0.05) * gs.h * 0.4)
		_apply_camera()
	for u in unit_pos:
		var n: Node3D = unit_nodes.get(u)
		if n == null:
			continue
		var p: Vector2 = unit_pos[u]
		var i := tile_at(p)
		var target := map_to_world(p, height(i))
		var hop := absf(sin(_time * 16.0)) * 0.12
		n.position = Vector3(target.x, lerpf(n.position.y, target.y, 0.35) + hop, target.z)
		n.visible = true
	# gentle idle bob for units that can still act
	for u in unit_nodes:
		var n: Node3D = unit_nodes[u]
		var body: Node3D = n.get_node("Body")
		if u.owner == gs.cur and u.owner == viewer and not u.moved and not u.fresh and not u.attacked:
			body.position.y = absf(sin(_time * 3.0 + u.id)) * 0.05
		else:
			body.position.y = 0.0


# ---------------------------------------------------------------- effects

func float_text(map: Vector2, text: String, col: Color, big: bool = false) -> void:
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
	var i := tile_at(map)
	l.position = map_to_world(map, height(i) + 0.9)
	fx_root.add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 0.8, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.8)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.5).set_delay(0.8)
	tw.chain().tween_callback(l.queue_free)


func burst(map: Vector2, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = LowPoly.get_mesh("ring")
	var m := mat_overlay.duplicate() as StandardMaterial3D
	m.albedo_color = col
	mi.material_override = m
	var i := tile_at(map)
	mi.position = map_to_world(map, height(i) + 0.08)
	mi.scale = Vector3(0.3, 1, 0.3)
	fx_root.add_child(mi)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.5, 1, 1.5), 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(mi.queue_free)


# ---------------------------------------------------------------- camera

func _apply_camera() -> void:
	if cam == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x < vp.y:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
	else:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = span
	var back := Vector3(0, sin(PITCH), cos(PITCH)) * 40.0
	cam.position = focus + back
	cam.rotation = Vector3(-PITCH, 0, 0)


func _clamp_focus() -> void:
	if gs == null:
		return
	# keep the map filling the screen, allowing a little sea at the edges
	var vp := get_viewport().get_visible_rect().size
	var half_w := span / 2.0 if vp.x < vp.y else span * vp.x / vp.y / 2.0
	var half_h := span * vp.y / vp.x / 2.0 if vp.x < vp.y else span / 2.0
	var half_d := half_h / sin(PITCH)
	var lo := Vector2(-0.9, -1.0)
	var hi := Vector2((gs.w - 0.5) * Hex.SQRT3 + 0.9, (gs.h - 1) * 1.5 + 1.0)
	var slack := 0.35
	var min_x := lo.x + half_w * (1.0 - slack)
	var max_x := hi.x - half_w * (1.0 - slack)
	var min_z := lo.y + half_d * (1.0 - slack)
	var max_z := hi.y - half_d * (1.0 - slack) + half_d * 0.3
	focus.x = (lo.x + hi.x) / 2.0 if min_x > max_x else clampf(focus.x, min_x, max_x)
	focus.z = (lo.y + hi.y) / 2.0 if min_z > max_z else clampf(focus.z, min_z, max_z)
	focus.y = 0.0


func screen_to_ground(screen: Vector2, y: float = 0.0) -> Vector3:
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if absf(d.y) < 1e-4:
		return o
	var t := (y - o.y) / d.y
	return o + d * t


func screen_to_map(screen: Vector2) -> Vector2:
	# pick on the land surface, then refine with that tile's height
	var g := screen_to_ground(screen, 0.0)
	var i := tile_at(Vector2(g.x, g.z) * Hex.SIZE)
	if i >= 0 and absf(height(i)) > 0.01:
		g = screen_to_ground(screen, height(i))
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
	var after := screen_to_ground(screen)
	focus += before - after
	_clamp_focus()
	_apply_camera()


## Centres the view on a tile, leaving room for the bottom panel.
func look_at_tile(i: int, animate: bool = false) -> void:
	var target := world(i)
	target.y = 0.0
	target.z += span * 0.12
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


func reset_zoom() -> void:
	span = 8.5
	_apply_camera()


func _stop_cam_tween() -> void:
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
