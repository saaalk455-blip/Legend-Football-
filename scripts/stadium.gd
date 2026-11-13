class_name Stadium
extends Node3D
## Procedural stadium: tiered stands with a MultiMesh crowd, advertising
## boards, corner flags and floodlight towers. No external assets.
## Only a handful of draw calls, so it stays cheap on mid-range phones.

var half_w := 34.0
var half_l := 52.5
var excite := 0.0                  # 0 calm .. 1 goal celebration
var _crowd_nodes: Array = []
var _t := 0.0

static var _grass_tex: ImageTexture


static func grass_material(c: Color) -> StandardMaterial3D:
	if _grass_tex == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
		for y in 64:
			for x in 64:
				var v := 0.90 + rng.randf() * 0.2
				if rng.randf() < 0.04:
					v -= 0.12
				img.set_pixel(x, y, Color(v, v, v))
		_grass_tex = ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.albedo_texture = _grass_tex
	m.uv1_scale = Vector3(14.0, 3.0, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = 1.0
	return m


func _mat(c: Color, emissive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emissive:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(size: Vector3, pos: Vector3, c: Color, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c, emissive)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func build(p_half_w: float, p_half_l: float) -> void:
	half_w = p_half_w
	half_l = p_half_l
	_build_stands()
	_build_boards()
	_build_flags()
	_build_floodlights()


func _build_stands() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var shirt_cols := [Color("e63946"), Color("ffd60a"), Color("2a6fdb"), Color("f1faee"),
		Color("8a4fd6"), Color("ff8c42"), Color("2ec4b6")]
	var skins := [Color("f1c8a0"), Color("d9a578"), Color("a8714a"), Color("5b3a24")]
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.9, 0.9, 0.6)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.5, 0.5, 0.5)
	# Each stand: [origin, along-axis, depth-axis, length]; tiers climb away from the pitch.
	var stands := [
		[Vector3(half_w + 6.0, 0.0, 0.0), Vector3(0, 0, 1), Vector3(1, 0, 0), 2.0 * half_l + 8.0],
		[Vector3(-half_w - 6.0, 0.0, 0.0), Vector3(0, 0, 1), Vector3(-1, 0, 0), 2.0 * half_l + 8.0],
		[Vector3(0.0, 0.0, half_l + 7.0), Vector3(1, 0, 0), Vector3(0, 0, 1), 2.0 * half_w + 8.0],
		[Vector3(0.0, 0.0, -half_l - 7.0), Vector3(1, 0, 0), Vector3(0, 0, -1), 2.0 * half_w + 8.0],
	]
	for st in stands:
		var origin: Vector3 = st[0]
		var along: Vector3 = st[1]
		var depth: Vector3 = st[2]
		var length: float = st[3]
		var tiers := 3 if Global.quality == 0 else 6
		var per_row := int(length / 1.3)
		var body_mm := MultiMesh.new()
		body_mm.transform_format = MultiMesh.TRANSFORM_3D
		body_mm.use_colors = true
		body_mm.mesh = body_mesh
		body_mm.instance_count = tiers * per_row
		var head_mm := MultiMesh.new()
		head_mm.transform_format = MultiMesh.TRANSFORM_3D
		head_mm.use_colors = true
		head_mm.mesh = head_mesh
		head_mm.instance_count = tiers * per_row
		var idx := 0
		for t in tiers:
			var step_h := 0.5 + t * 0.9
			var d := depth * (t * 1.9)
			# concrete step
			var sc := origin + d + Vector3(0, step_h * 0.5 - 0.1, 0)
			var sz := Vector3(1.9, step_h, length) if absf(along.z) > 0.5 else Vector3(length, step_h, 1.9)
			_box(sz, sc, Color("5a6376") if t % 2 == 0 else Color("4d566a"))
			for k in per_row:
				var a := -length * 0.5 + (k + 0.5) * (length / per_row) + rng.randf_range(-0.2, 0.2)
				var pos := origin + d + along * a + Vector3(0, step_h + 0.45, 0)
				body_mm.set_instance_transform(idx, Transform3D(Basis(), pos))
				body_mm.set_instance_color(idx, shirt_cols[rng.randi() % shirt_cols.size()])
				head_mm.set_instance_transform(idx, Transform3D(Basis(), pos + Vector3(0, 0.7, 0)))
				head_mm.set_instance_color(idx, skins[rng.randi() % skins.size()])
				idx += 1
		for mm in [body_mm, head_mm]:
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_crowd_nodes.append(mi)
		# back wall
		var wall_pos := origin + depth * (tiers * 1.9 + 0.6) + Vector3(0, 4.0, 0)
		var wall_sz := Vector3(0.6, 8.0, length) if absf(along.z) > 0.5 else Vector3(length, 8.0, 0.6)
		_box(wall_sz, wall_pos, Color("22304f"))


func _build_boards() -> void:
	var cols := [Color("d62828"), Color("1d4e89"), Color("f77f00"), Color("2a9d8f"), Color("6a4c93")]
	var n := 0
	var x_off := half_w + 2.2
	var z_off := half_l + 2.2
	var seg := 7.0
	var cnt_l := int((2.0 * half_l) / seg)
	for i in cnt_l:
		var z := -half_l + seg * (i + 0.5) + (2.0 * half_l - seg * cnt_l) * 0.5
		for sx in [-1, 1]:
			_box(Vector3(0.3, 1.0, seg - 0.4), Vector3(sx * x_off, 0.5, z), cols[(i + n) % cols.size()])
			_box(Vector3(0.32, 0.12, seg - 0.4), Vector3(sx * x_off, 1.0, z), Color("f4f4f4"))
	var cnt_w := int((2.0 * half_w) / seg)
	for i in cnt_w:
		var x := -half_w + seg * (i + 0.5) + (2.0 * half_w - seg * cnt_w) * 0.5
		for sz in [-1, 1]:
			_box(Vector3(seg - 0.4, 1.0, 0.3), Vector3(x, 0.5, sz * z_off), cols[(i + 2) % cols.size()])
			_box(Vector3(seg - 0.4, 0.12, 0.32), Vector3(x, 1.0, sz * z_off), Color("f4f4f4"))


func _build_flags() -> void:
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var pos := Vector3(sx * half_w, 0.0, sz * half_l)
			_box(Vector3(0.1, 1.6, 0.1), pos + Vector3(0, 0.8, 0), Color("f2f2f2"))
			_box(Vector3(0.5, 0.35, 0.04), pos + Vector3(-sx * 0.25, 1.45, 0), Color("ffd60a"))


func _build_floodlights() -> void:
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var base := Vector3(sx * (half_w + 24.0), 0.0, sz * (half_l + 18.0))
			_box(Vector3(0.8, 34.0, 0.8), base + Vector3(0, 17.0, 0), Color("39425a"))
			for r in 3:
				for c in 3:
					_box(Vector3(1.2, 1.0, 0.4), base + Vector3((c - 1) * 1.5, 34.0 + r * 1.2, 0), Color("fffbe0"), true)


func _process(delta: float) -> void:
	_t += delta
	excite = maxf(excite - delta * 0.35, 0.0)
	var amp := 0.04 + excite * 0.35
	var spd := 2.0 + excite * 9.0
	for i in _crowd_nodes.size():
		var n: Node3D = _crowd_nodes[i]
		n.position.y = absf(sin(_t * spd + float(i / 2) * 1.7)) * amp
