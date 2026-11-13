class_name Player
extends Node3D
## Low-poly retro player built from primitives (no external assets).
## Skin tone and hairstyle (bald, short, long, afro, curly) come from the roster.

const SKIN := [Color("f0c8a0"), Color("d29a6a"), Color("a56a3f"), Color("5a3820")]
const HAIR := {
	"black": Color("141414"), "brown": Color("4a2c15"), "blond": Color("d9b85c"),
	"red": Color("b5441f"), "grey": Color("aaaaaa"),
}

var team_id := 0
var role := "MID"            # GK, DEF, MID, FWD
var home_pos := Vector3.ZERO
var speed_stat := 70
var shoot_stat := 70
var pass_stat := 70
var shirt_number := 1
var ai_cd := 0.0
var player_name := ""
var stamina := 1.0
var yellow := 0
var player_id := 0
var accel_stat := 70
var stamina_stat := 70
var dribble_stat := 70
var defense_stat := 70
var keeper_stat := 0         # goalkeepers only
var vel := Vector3.ZERO

static var _mats := {}
var _body: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _phase := 0.0
var _kick_t := 0.0
var _last_pos := Vector3.ZERO
var _speed_vis := 0.0
var _dive_t := 0.0
var _dive_s := 1.0
var _cel_t := 0.0


func top_speed() -> float:
	return 4.6 + 0.034 * float(speed_stat)


func step_move(desired: Vector3, delta: float) -> void:
	## Momentum: velocity eases toward the desired velocity (stopping is quicker
	## than starting) and the body can only turn at a limited rate.
	var acc := 12.0 + 0.13 * float(accel_stat)
	var diff := desired - vel
	var braking := desired.length() < vel.length()
	var max_change := acc * (1.5 if braking else 1.0) * delta
	if diff.length() > max_change:
		diff = diff.normalized() * max_change
	vel += diff
	position += vel * delta
	var sp := vel.length()
	if sp > 0.6:
		var target := atan2(vel.x, vel.z)
		var d := wrapf(target - rotation.y, -PI, PI)
		var turn := (11.0 - 0.55 * sp) * delta
		rotation.y += clampf(d, -turn, turn)


func kick() -> void:
	_kick_t = 0.28


func dive(side: float) -> void:
	## Goalkeeper save pose; side is +1 / -1 along the keeper's right hand.
	if _dive_t <= 0.0:
		_dive_t = 0.7
		_dive_s = side


func celebrate(secs: float) -> void:
	_cel_t = secs


static func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html(true)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


func _add(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _ball(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 10
	s.rings = 6
	return s


func _contrast(c: Color) -> Color:
	var lum := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	return Color("151515") if lum > 0.55 else Color("f5f5f5")


func setup(p_team: int, p_role: String, p_home: Vector3, shirt: Color, shorts: Color, number: int, look: Dictionary = {}) -> void:
	team_id = p_team
	role = p_role
	home_pos = p_home
	shirt_number = number
	position = p_home
	_last_pos = p_home

	var skin: Color = SKIN[clampi(int(look.get("skin", 1)), 0, 3)]
	var skin_dk := skin.darkened(0.14)
	var hair_style: String = look.get("hair", "short")
	var hair_col: Color = HAIR.get(look.get("hcol", "black"), HAIR["black"])
	var trim := _contrast(shirt)
	var sock_trim := _contrast(shirt)
	var hip_y := 0.78

	# ---- legs (pivot at the hip so they can swing)
	for side in [-1, 1]:
		var leg := _pivot(self, Vector3(side * 0.16, hip_y, 0))
		_add(leg, _box(Vector3(0.23, 0.16, 0.25)), skin, Vector3(0, -0.27, 0))
		_add(leg, _box(Vector3(0.23, 0.36, 0.25)), shirt, Vector3(0, -0.5, 0))
		_add(leg, _box(Vector3(0.24, 0.05, 0.26)), sock_trim, Vector3(0, -0.4, 0))
		_add(leg, _box(Vector3(0.25, 0.12, 0.4)), Color("101010"), Vector3(0, -0.73, 0.07))
		if side < 0:
			_leg_l = leg
		else:
			_leg_r = leg

	# ---- upper body (pivot at the hips: leans and bobs while running)
	_body = _pivot(self, Vector3(0, hip_y, 0))
	var o := Vector3(0, -hip_y, 0)
	_add(_body, _box(Vector3(0.64, 0.38, 0.4)), shorts, Vector3(0, 0.76, 0) + o)
	_add(_body, _box(Vector3(0.66, 0.05, 0.42)), trim, Vector3(0, 0.94, 0) + o)
	_add(_body, _box(Vector3(0.62, 0.3, 0.38)), shirt, Vector3(0, 1.12, 0) + o)
	_add(_body, _box(Vector3(0.8, 0.42, 0.42)), shirt, Vector3(0, 1.46, 0) + o)
	_add(_body, _box(Vector3(0.3, 0.05, 0.44)), trim, Vector3(0, 1.69, 0.0) + o)
	_add(_body, _box(Vector3(0.14, 0.12, 0.14)), skin_dk, Vector3(0, 1.74, 0) + o)
	for side in [-1, 1]:
		var arm := _pivot(_body, Vector3(side * 0.5, 1.58, 0) + o)
		arm.rotation.z = side * 0.1
		_add(arm, _box(Vector3(0.22, 0.26, 0.26)), shirt, Vector3(0, -0.1, 0))
		_add(arm, _box(Vector3(0.23, 0.05, 0.27)), trim, Vector3(0, -0.24, 0))
		_add(arm, _box(Vector3(0.16, 0.34, 0.18)), skin, Vector3(0, -0.44, 0))
		if side < 0:
			_arm_l = arm
		else:
			_arm_r = arm
	# Shirt number on the back
	var lab := Label3D.new()
	lab.text = str(number)
	lab.font_size = 56
	lab.pixel_size = 0.0075
	lab.modulate = trim
	lab.outline_size = 0
	lab.position = Vector3(0, 1.45, -0.215) + o
	lab.rotation.y = PI
	_body.add_child(lab)

	# ---- head with a face
	var head := _pivot(_body, Vector3(0, 1.9, 0) + o)
	_add(head, _ball(0.235), skin, Vector3(0.95, 1.08, 1.0))
	_add(head, _box(Vector3(0.06, 0.08, 0.06)), skin_dk, Vector3(0, -0.02, 0.23))
	for side in [-1, 1]:
		_add(head, _box(Vector3(0.06, 0.045, 0.03)), Color("f4f4f4"), Vector3(side * 0.085, 0.04, 0.2))
		_add(head, _box(Vector3(0.035, 0.04, 0.03)), Color("1a1208"), Vector3(side * 0.085, 0.04, 0.215))
		_add(head, _box(Vector3(0.11, 0.025, 0.03)), hair_col if hair_style != "bald" else skin_dk, Vector3(side * 0.085, 0.1, 0.205))
		_add(head, _box(Vector3(0.05, 0.1, 0.06)), skin_dk, Vector3(side * 0.23, 0.0, -0.01))
	_add(head, _box(Vector3(0.12, 0.025, 0.03)), skin_dk.darkened(0.25), Vector3(0, -0.11, 0.2))
	match hair_style:
		"short":
			_add(head, _ball(0.255), hair_col, Vector3(0, 0.08, -0.025), Vector3(1.0, 0.7, 1.02))
		"long":
			_add(head, _ball(0.255), hair_col, Vector3(0, 0.08, -0.025), Vector3(1.0, 0.7, 1.02))
			_add(head, _box(Vector3(0.46, 0.55, 0.14)), hair_col, Vector3(0, -0.12, -0.19))
		"afro":
			_add(head, _ball(0.34), hair_col, Vector3(0, 0.06, -0.03))
		"curly":
			_add(head, _ball(0.285), hair_col, Vector3(0, 0.06, -0.03), Vector3(1.0, 0.82, 1.0))
		_:
			pass   # bald

	# ---- blob shadow
	var shadow := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.65
	sm.bottom_radius = 0.65
	sm.height = 0.01
	sm.radial_segments = 12
	shadow.mesh = sm
	shadow.material_override = _mat(Color(0, 0, 0, 0.35))
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.position = Vector3(0, 0.02, 0)
	add_child(shadow)


func _process(delta: float) -> void:
	if _body == null or delta <= 0.0:
		return
	var v := (position - _last_pos) / delta
	v.y = 0.0
	_last_pos = position
	_speed_vis = lerpf(_speed_vis, minf(v.length(), 12.0), clampf(delta * 10.0, 0.0, 1.0))
	var k := clampf(_speed_vis / 7.0, 0.0, 1.0)
	_phase += _speed_vis * delta * 1.7
	var sw := sin(_phase) * 0.95 * k
	_leg_l.rotation.x = sw
	_leg_r.rotation.x = -sw
	_arm_l.rotation.x = -sw * 0.9
	_arm_r.rotation.x = sw * 0.9
	_body.rotation.x = -0.16 * k
	_body.position.y = 0.78 + absf(sin(_phase)) * 0.06 * k
	if _kick_t > 0.0:
		_kick_t = maxf(_kick_t - delta, 0.0)
		var pr := 1.0 - _kick_t / 0.28
		var f := sin(pr * PI)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -1.5, f)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.6, f)
		_body.rotation.x = lerpf(_body.rotation.x, 0.18, f)
	if _dive_t > 0.0:
		_dive_t = maxf(_dive_t - delta, 0.0)
		var f2 := sin((1.0 - _dive_t / 0.7) * PI)
		_body.rotation.z = -_dive_s * 1.15 * f2
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -2.9, f2)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -2.9, f2)
		_leg_l.rotation.z = _dive_s * 0.35 * f2
		_leg_r.rotation.z = -_dive_s * 0.35 * f2
		position.y = f2 * 0.35
	elif _body.rotation.z != 0.0:
		_body.rotation.z = 0.0
		_leg_l.rotation.z = 0.0
		_leg_r.rotation.z = 0.0
		position.y = 0.0
	if _cel_t > 0.0:
		_cel_t = maxf(_cel_t - delta, 0.0)
		var w := Time.get_ticks_msec() / 1000.0 * 9.0 + float(player_id)
		_arm_l.rotation.x = -2.8 + sin(w) * 0.3
		_arm_r.rotation.x = -2.8 - sin(w) * 0.3
		position.y = absf(sin(w * 0.8)) * 0.45
		if _cel_t == 0.0:
			position.y = 0.0
