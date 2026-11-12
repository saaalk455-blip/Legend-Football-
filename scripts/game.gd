extends Node3D
## PHASE 2: pitch, goals, TV camera, 22 players, ball.
## Movement, rules and AI arrive in later phases.

const PITCH_W := 68.0   # X
const PITCH_L := 105.0  # Z
const HALF_L := PITCH_L / 2.0
const HALF_W := PITCH_W / 2.0
const GOAL_W := 7.32
const GOAL_H := 2.44

# role, x (-1..1 across pitch), depth (0 = own goal line, 1 = opposite goal line)
const FORMATION := [
	["GK", 0.0, 0.02],
	["DEF", -0.7, 0.18], ["DEF", -0.25, 0.16], ["DEF", 0.25, 0.16], ["DEF", 0.7, 0.18],
	["MID", -0.7, 0.34], ["MID", -0.25, 0.32], ["MID", 0.25, 0.32], ["MID", 0.7, 0.34],
	["FWD", -0.25, 0.44], ["FWD", 0.25, 0.44],
]

var players: Array[Player] = []
var ball: MeshInstance3D
var cam: Camera3D
var team_a := 0
var team_b := 1


func _ready() -> void:
	Global.apply_quality()
	team_a = Global.team_index
	team_b = (team_a + 1) % Global.TEAMS.size()
	_build_environment()
	_build_pitch()
	_build_goals()
	_build_teams()
	_build_ball()
	_build_camera()
	_build_ui()


func _process(delta: float) -> void:
	if cam == null or ball == null:
		return
	# TV-style camera: follows the ball smoothly along the pitch.
	var target := Vector3(ball.position.x * 0.4, 34.0, ball.position.z * 0.75 + 30.0)
	target.z = clampf(target.z, -HALF_L + 18.0, HALF_L + 30.0)
	cam.position = cam.position.lerp(target, clampf(delta * 3.0, 0.0, 1.0))
	cam.look_at(Vector3(ball.position.x * 0.4, 0.0, ball.position.z * 0.75), Vector3.UP)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	add_child(mi)
	return mi


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("07122b")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.85)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 25, 0)
	sun.light_energy = 0.9
	add_child(sun)


func _build_pitch() -> void:
	# Mowing stripes: alternating green bands across the length.
	var bands := 10
	var band_len := PITCH_L / bands
	for i in bands:
		var c := Color("1f9d3a") if i % 2 == 0 else Color("23aa40")
		_box(Vector3(PITCH_W, 0.1, band_len), Vector3(0, -0.05, -HALF_L + band_len * (i + 0.5)), c)

	# Surrounding ground
	_box(Vector3(PITCH_W + 40, 0.1, PITCH_L + 40), Vector3(0, -0.2, 0), Color("14602a"))

	var white := Color("f2f2f2")
	var t := 0.25
	var y := 0.02
	# Outer lines
	_box(Vector3(PITCH_W, 0.02, t), Vector3(0, y, -HALF_L), white)
	_box(Vector3(PITCH_W, 0.02, t), Vector3(0, y, HALF_L), white)
	_box(Vector3(t, 0.02, PITCH_L), Vector3(-HALF_W, y, 0), white)
	_box(Vector3(t, 0.02, PITCH_L), Vector3(HALF_W, y, 0), white)
	# Halfway line
	_box(Vector3(PITCH_W, 0.02, t), Vector3(0, y, 0), white)
	# Penalty boxes (16.5 deep, 40.3 wide) and 6-yard boxes (5.5 deep, 18.3 wide)
	for s in [-1, 1]:
		var gz: float = s * HALF_L
		var pz: float = gz - s * 16.5
		_box(Vector3(40.3, 0.02, t), Vector3(0, y, pz), white)
		_box(Vector3(t, 0.02, 16.5), Vector3(-20.15, y, gz - s * 8.25), white)
		_box(Vector3(t, 0.02, 16.5), Vector3(20.15, y, gz - s * 8.25), white)
		var sz: float = gz - s * 5.5
		_box(Vector3(18.3, 0.02, t), Vector3(0, y, sz), white)
		_box(Vector3(t, 0.02, 5.5), Vector3(-9.15, y, gz - s * 2.75), white)
		_box(Vector3(t, 0.02, 5.5), Vector3(9.15, y, gz - s * 2.75), white)
	# Centre circle (approximated with a ring of small segments)
	var seg := 28
	for i in seg:
		var a := TAU * i / seg
		var seg_len := TAU * 9.15 / seg + 0.1
		var b := _box(Vector3(seg_len, 0.02, t), Vector3(cos(a) * 9.15, y, sin(a) * 9.15), white)
		b.rotation.y = -a + PI / 2.0
	# Centre spot
	_box(Vector3(0.6, 0.02, 0.6), Vector3(0, y, 0), white)


func _build_goals() -> void:
	var post := 0.2
	for s in [-1, 1]:
		var gz: float = s * HALF_L
		_box(Vector3(post, GOAL_H, post), Vector3(-GOAL_W / 2.0, GOAL_H / 2.0, gz), Color.WHITE)
		_box(Vector3(post, GOAL_H, post), Vector3(GOAL_W / 2.0, GOAL_H / 2.0, gz), Color.WHITE)
		_box(Vector3(GOAL_W + post, post, post), Vector3(0, GOAL_H, gz), Color.WHITE)
		# Simple back net (translucent)
		var net := _box(Vector3(GOAL_W, GOAL_H, 0.05), Vector3(0, GOAL_H / 2.0, gz + s * 2.0), Color(1, 1, 1, 0.25))
		(net.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Simple crowd stands: coloured blocks behind both ends and sides
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var crowd_cols := [Color("e63946"), Color("ffd60a"), Color("2a6fdb"), Color("f1faee")]
	for i in 40:
		for side in [-1, 1]:
			var z := -HALF_L + (PITCH_L * i / 39.0)
			_box(Vector3(2.0, 1.6, 2.2), Vector3(side * (HALF_W + 6.0), 1.0, z), crowd_cols[rng.randi() % crowd_cols.size()])
	_box(Vector3(4.0, 5.0, PITCH_L + 10), Vector3(-HALF_W - 9.0, 2.5, 0), Color("22304f"))
	_box(Vector3(4.0, 5.0, PITCH_L + 10), Vector3(HALF_W + 9.0, 2.5, 0), Color("22304f"))


func _build_teams() -> void:
	var ta: Dictionary = Global.TEAMS[team_a]
	var tb: Dictionary = Global.TEAMS[team_b]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for team_id in 2:
		var td: Dictionary = ta if team_id == 0 else tb
		# Team 0 (player) defends +Z and attacks toward -Z; team 1 is mirrored.
		var dir := 1.0 if team_id == 0 else -1.0
		for i in FORMATION.size():
			var f: Array = FORMATION[i]
			var x: float = f[1] * (HALF_W - 6.0) * dir
			var z: float = dir * (HALF_L - f[2] * PITCH_L)
			var shirt: Color = td["c1"]
			var shorts: Color = td["c2"]
			if f[0] == "GK":
				shirt = Color("39ff14") if team_id == 0 else Color("ff9f1c")
				shorts = Color("222222")
			var p := Player.new()
			add_child(p)
			p.setup(team_id, f[0], Vector3(x, 0, z), shirt, shorts, i + 1)
			p.speed_stat = rng.randi_range(60, 90)
			p.shoot_stat = rng.randi_range(55, 90)
			p.pass_stat = rng.randi_range(55, 90)
			# Face the opponent goal
			p.rotation.y = 0.0 if team_id == 1 else PI
			players.append(p)


func _build_ball() -> void:
	ball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 10
	sm.rings = 6
	ball.mesh = sm
	ball.material_override = _mat(Color("fafafa"))
	ball.position = Vector3(0, 0.35, 0)
	add_child(ball)


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.position = Vector3(0, 34.0, 30.0)
	add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var b := Button.new()
	b.text = Global.t("MENU")
	b.custom_minimum_size = Vector2(180, 70)
	b.add_theme_font_size_override("font_size", 30)
	b.position = Vector2(20, 20)
	b.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	layer.add_child(b)
	var l := Label.new()
	l.text = "%s vs %s   (Phase 2)" % [Global.TEAMS[team_a]["name"], Global.TEAMS[team_b]["name"]]
	l.position = Vector2(220, 36)
	l.add_theme_font_size_override("font_size", 28)
	layer.add_child(l)
