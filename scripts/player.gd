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


func _part(mesh: Mesh, color: Color, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	mi.material_override = m
	mi.position = pos
	mi.scale = scl
	add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _ball(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 8
	s.rings = 4
	return s


func setup(p_team: int, p_role: String, p_home: Vector3, shirt: Color, shorts: Color, number: int, look: Dictionary = {}) -> void:
	team_id = p_team
	role = p_role
	home_pos = p_home
	shirt_number = number
	position = p_home

	var skin: Color = SKIN[clampi(int(look.get("skin", 1)), 0, 3)]
	var hair_style: String = look.get("hair", "short")
	var hair_col: Color = HAIR.get(look.get("hcol", "black"), HAIR["black"])

	# Socks (kit colour), bare knees, shorts
	_part(_box(Vector3(0.24, 0.4, 0.26)), shirt, Vector3(-0.16, 0.2, 0))
	_part(_box(Vector3(0.24, 0.4, 0.26)), shirt, Vector3(0.16, 0.2, 0))
	_part(_box(Vector3(0.22, 0.12, 0.24)), skin, Vector3(-0.16, 0.46, 0))
	_part(_box(Vector3(0.22, 0.12, 0.24)), skin, Vector3(0.16, 0.46, 0))
	_part(_box(Vector3(0.62, 0.42, 0.4)), shorts, Vector3(0, 0.74, 0))
	# Torso / shirt and arms
	_part(_box(Vector3(0.74, 0.66, 0.4)), shirt, Vector3(0, 1.28, 0))
	_part(_box(Vector3(0.17, 0.62, 0.2)), skin, Vector3(-0.47, 1.28, 0))
	_part(_box(Vector3(0.17, 0.62, 0.2)), skin, Vector3(0.47, 1.28, 0))
	# Head
	_part(_ball(0.23), skin, Vector3(0, 1.82, 0))

	match hair_style:
		"short":
			_part(_ball(0.25), hair_col, Vector3(0, 1.9, -0.01), Vector3(1.0, 0.62, 1.0))
		"long":
			_part(_ball(0.25), hair_col, Vector3(0, 1.9, -0.01), Vector3(1.0, 0.62, 1.0))
			_part(_box(Vector3(0.42, 0.5, 0.14)), hair_col, Vector3(0, 1.7, -0.19))
		"afro":
			_part(_ball(0.34), hair_col, Vector3(0, 1.92, -0.02))
		"curly":
			_part(_ball(0.28), hair_col, Vector3(0, 1.91, -0.02), Vector3(1.0, 0.8, 1.0))
		_:
			pass   # bald

	# Simple blob shadow
	var shadow := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.6
	sm.bottom_radius = 0.6
	sm.height = 0.01
	sm.radial_segments = 12
	shadow.mesh = sm
	var sh_mat := StandardMaterial3D.new()
	sh_mat.albedo_color = Color(0, 0, 0, 0.35)
	sh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow.material_override = sh_mat
	shadow.position = Vector3(0, 0.02, 0)
	add_child(shadow)
