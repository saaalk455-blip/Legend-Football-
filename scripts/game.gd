extends Node3D
## Phase 1 placeholder match scene: pitch, light, camera, back button.
## Players, ball and rules arrive in later phases.

const PITCH_W := 68.0   # X
const PITCH_L := 105.0  # Z


func _ready() -> void:
	Global.apply_quality()
	_build_world()
	_build_ui()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("07122b")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.8)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_energy = 0.9
	add_child(sun)

	var pitch := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(PITCH_W, PITCH_L)
	pitch.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("1f9d3a")
	pitch.material_override = mat
	add_child(pitch)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 38, 52)
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
	l.text = "%s  (%s)" % [Global.TEAMS[Global.team_index]["name"], "Phase 1"]
	l.position = Vector2(220, 36)
	l.add_theme_font_size_override("font_size", 28)
	layer.add_child(l)
