class_name Player
extends Node3D
## Low-poly retro player built from primitives (no external assets).

var team_id := 0
var role := "MID"            # GK, DEF, MID, FWD
var home_pos := Vector3.ZERO
var speed_stat := 70
var shoot_stat := 70
var pass_stat := 70
var shirt_number := 1
var ai_cd := 0.0
var player_name := ""


func setup(p_team: int, p_role: String, p_home: Vector3, shirt: Color, shorts: Color, number: int) -> void:
	team_id = p_team
	role = p_role
	home_pos = p_home
	shirt_number = number
	position = p_home

	var shirt_mat := StandardMaterial3D.new()
	shirt_mat.albedo_color = shirt
	var shorts_mat := StandardMaterial3D.new()
	shorts_mat.albedo_color = shorts
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color("d9a577")

	# Legs / shorts
	var legs := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.55, 0.8, 0.35)
	legs.mesh = lm
	legs.material_override = shorts_mat
	legs.position = Vector3(0, 0.4, 0)
	add_child(legs)

	# Torso / shirt
	var torso := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.75, 0.8, 0.4)
	torso.mesh = tm
	torso.material_override = shirt_mat
	torso.position = Vector3(0, 1.2, 0)
	add_child(torso)

	# Head
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.22
	hm.height = 0.44
	hm.radial_segments = 8
	hm.rings = 4
	head.mesh = hm
	head.material_override = skin_mat
	head.position = Vector3(0, 1.85, 0)
	add_child(head)

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
