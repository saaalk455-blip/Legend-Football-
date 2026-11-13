extends Node3D
## Match controller: world, ball physics, football rules, AI and match clock.
## Rules implemented: kick-off, throw-in, goal kick, corner, fouls + free kicks,
## penalties, yellow/red cards, offside, two halves with stoppage time and
## switching ends.

const PITCH_W := 68.0   # X
const PITCH_L := 105.0  # Z
const HALF_L := PITCH_L / 2.0
const HALF_W := PITCH_W / 2.0
const GOAL_W := 7.32
const GOAL_H := 2.44
const BOX_D := 16.5
const BOX_HW := 20.15
const GRAVITY := 22.0
const BALL_R := 0.35
const HALF_SECONDS := 2700.0   # 45 game minutes

const CAM_X := 40.0
const CAM_H := 27.0

const M_INTRO := 0
const M_KICKOFF := 1
const M_PLAY := 2
const M_THROW := 3
const M_GOALKICK := 4
const M_CORNER := 5
const M_FREEKICK := 6
const M_PENALTY := 7
const M_GOAL := 8
const M_HALFTIME := 9
const M_FULLTIME := 10

# role, x (-1..1 across pitch), depth (0 = own goal line, 1 = opposite goal line)
const FORMATION := [
	["GK", 0.0, 0.02],
	["DEF", -0.7, 0.18], ["DEF", -0.25, 0.16], ["DEF", 0.25, 0.16], ["DEF", 0.7, 0.18],
	["MID", -0.7, 0.34], ["MID", -0.25, 0.32], ["MID", 0.25, 0.32], ["MID", 0.7, 0.34],
	["FWD", -0.25, 0.44], ["FWD", 0.25, 0.44],
]

var players: Array[Player] = []
var ball: MeshInstance3D
var ball_shadow: MeshInstance3D
var cam: Camera3D
var team_a := 0
var team_b := 1
var kits: Array = []
var controls: TouchControls
var hud: Hud
var controlled: Player
var indicator: Node3D
var number_label: Label3D
var autoplay := false      # CI smoke test: AI plays both sides
var botplay := false       # CI smoke test: a bot presses the touch controls
var smoke := false
var _bot_t := 0.0
var _selftests := 0
var _auto_t := 0.0
var _loose_t := 0.0
var _adv := [-999.0, -999.0]
var _carry_frames := [0, 0]
var _t := 0.0
var _auto_switch_t := 0.0
var _mat_cache := {}

# ball
var ball_vel := Vector3.ZERO
var ball_spin := 0.0
var holder: Player = null
var hold_time := 0.0
var blocked_player: Player = null
var blocked_timer := 0.0
var tackle_cd := 0.0
var last_touch_team := 0
var last_touch_name := ""
var cam_z := 0.0
var sfx: Sfx
var stadium: Stadium
var _running := false

# match flow
var mode := M_INTRO
var mode_timer := 0.0
var conceding_team := 0
var restart_team := 0
var restart_taker: Player = null
var restart_pos := Vector3.ZERO
var restart_wait := 0.0
var restart_wait_max := 1.0
var no_offside_kick := false
var offside_list: Array[Player] = []
var offside_team := -1

var half := 1
var side := 1.0            # +1 first half: team 0 defends +Z; -1 second half
var match_time := 0.0      # game seconds
var clock_speed := 1.0
var added_minutes := 0
var half_end_reached := false
var fouls_this_half := 0
var score := [0, 0]
var stats := {
	"shots": [0, 0], "fouls": [0, 0], "yellow": [0, 0], "red": [0, 0],
	"corners": [0, 0], "offsides": [0, 0], "throws": [0, 0], "possession": [0.0, 0.0],
}


func _ready() -> void:
	autoplay = "autoplay" in OS.get_cmdline_user_args()
	botplay = "botplay" in OS.get_cmdline_user_args()
	smoke = autoplay or botplay
	if smoke:
		Global.match_minutes = 4
	Global.apply_quality()
	team_a = Global.team_index
	team_b = Global.opp_index
	if team_b == team_a:
		team_b = (team_a + 1) % Global.TEAMS.size()
	clock_speed = 5400.0 / (float(Global.match_minutes) * 60.0)
	_build_environment()
	_build_pitch()
	_build_goals()
	_build_teams()
	_build_ball()
	_build_camera()
	sfx = Sfx.new()
	add_child(sfx)
	_build_controls()
	_build_hud()
	if autoplay:
		controlled = null
		_begin_kickoff(0)
	elif botplay:
		_begin_kickoff(0)
	else:
		_place_formation()
		mode = M_INTRO
		hud.show_intro()


# ================================================================ geometry helpers

func _atk_sign(team: int) -> float:
	## +1 if the team currently attacks toward +Z.
	return -side if team == 0 else side


func _own_goal_z(team: int) -> float:
	return -_atk_sign(team) * HALF_L


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html(true)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_cache[key] = m
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


func _forward(p: Player) -> Vector3:
	return Vector3(sin(p.rotation.y), 0.0, cos(p.rotation.y))


func _yaw(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)


# ================================================================ world building

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("07122b")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.85)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color("0b1a3a")
	e.fog_density = 0.0025
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 25, 0)
	sun.light_energy = 1.0
	sun.light_color = Color("fff1d6")
	if Global.quality >= 2:
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 110.0
	add_child(sun)


func _build_pitch() -> void:
	var bands := 10
	var band_len := PITCH_L / bands
	for i in bands:
		var c := Color("3a8c35") if i % 2 == 0 else Color("46a03e")
		var band := _box(Vector3(PITCH_W, 0.1, band_len), Vector3(0, -0.05, -HALF_L + band_len * (i + 0.5)), c)
		band.material_override = Stadium.grass_material(c)
	_box(Vector3(PITCH_W + 40, 0.1, PITCH_L + 40), Vector3(0, -0.2, 0), Color("14602a"))

	var white := Color("f2f2f2")
	var t := 0.25
	var y := 0.02
	_box(Vector3(PITCH_W, 0.02, t), Vector3(0, y, -HALF_L), white)
	_box(Vector3(PITCH_W, 0.02, t), Vector3(0, y, HALF_L), white)
	_box(Vector3(t, 0.02, PITCH_L), Vector3(-HALF_W, y, 0), white)
	_box(Vector3(t, 0.02, PITCH_L), Vector3(HALF_W, y, 0), white)
	_box(Vector3(PITCH_W, 0.02, t), Vector3(0, y, 0), white)
	for s in [-1, 1]:
		var gz: float = s * HALF_L
		var pz: float = gz - s * BOX_D
		_box(Vector3(BOX_HW * 2.0, 0.02, t), Vector3(0, y, pz), white)
		_box(Vector3(t, 0.02, BOX_D), Vector3(-BOX_HW, y, gz - s * BOX_D / 2.0), white)
		_box(Vector3(t, 0.02, BOX_D), Vector3(BOX_HW, y, gz - s * BOX_D / 2.0), white)
		var sz: float = gz - s * 5.5
		_box(Vector3(18.3, 0.02, t), Vector3(0, y, sz), white)
		_box(Vector3(t, 0.02, 5.5), Vector3(-9.15, y, gz - s * 2.75), white)
		_box(Vector3(t, 0.02, 5.5), Vector3(9.15, y, gz - s * 2.75), white)
		_box(Vector3(0.5, 0.02, 0.5), Vector3(0, y, gz - s * 11.0), white)
	var seg := 28
	for i in seg:
		var a := TAU * i / seg
		var seg_len := TAU * 9.15 / seg + 0.1
		var b := _box(Vector3(seg_len, 0.02, t), Vector3(cos(a) * 9.15, y, sin(a) * 9.15), white)
		b.rotation.y = -a + PI / 2.0
	_box(Vector3(0.6, 0.02, 0.6), Vector3(0, y, 0), white)


func _net(size: Vector3, pos: Vector3) -> void:
	var n := _box(size, pos, Color(1, 1, 1, 0.28))
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_goals() -> void:
	var post := 0.2
	for s in [-1, 1]:
		var gz: float = s * HALF_L
		_box(Vector3(post, GOAL_H, post), Vector3(-GOAL_W / 2.0, GOAL_H / 2.0, gz), Color.WHITE)
		_box(Vector3(post, GOAL_H, post), Vector3(GOAL_W / 2.0, GOAL_H / 2.0, gz), Color.WHITE)
		_box(Vector3(GOAL_W + post, post, post), Vector3(0, GOAL_H, gz), Color.WHITE)
		_net(Vector3(GOAL_W, GOAL_H, 0.05), Vector3(0, GOAL_H / 2.0, gz + s * 2.0))
		_net(Vector3(0.05, GOAL_H, 2.0), Vector3(-GOAL_W / 2.0, GOAL_H / 2.0, gz + s * 1.0))
		_net(Vector3(0.05, GOAL_H, 2.0), Vector3(GOAL_W / 2.0, GOAL_H / 2.0, gz + s * 1.0))
		_net(Vector3(GOAL_W, 0.05, 2.0), Vector3(0, GOAL_H, gz + s * 1.0))
	stadium = Stadium.new()
	add_child(stadium)
	stadium.build(HALF_W, HALF_L)


func _build_teams() -> void:
	var ta: Dictionary = Global.TEAMS[team_a]
	var tb: Dictionary = Global.TEAMS[team_b]
	kits = [[ta["c1"], ta["c2"]], [tb["c1"], tb["c2"]]]
	# Avoid identical colours: opponent switches to its second kit.
	if _colour_close(kits[1][0], kits[0][0]):
		kits[1] = [tb["c2"], tb["c1"]]
		if _colour_close(kits[1][0], kits[0][0]):
			kits[1] = [Color("222222"), tb["c1"]]
	for team_id in 2:
		var roster: Array = Global.get_roster(team_a if team_id == 0 else team_b)
		var kit: Array = kits[team_id]
		var dir := 1.0 if team_id == 0 else -1.0
		for i in FORMATION.size():
			var f: Array = FORMATION[i]
			var x: float = f[1] * (HALF_W - 6.0) * dir
			var z: float = dir * (HALF_L - f[2] * PITCH_L)
			var shirt: Color = kit[0]
			var shorts: Color = kit[1]
			if f[0] == "GK":
				shirt = Color("39ff14") if team_id == 0 else Color("ff9f1c")
				shorts = Color("222222")
			var p := Player.new()
			add_child(p)
			var r: Dictionary = roster[i]
			p.setup(team_id, f[0], Vector3(x, 0, z), shirt, shorts, i + 1, r)
			p.scale = Vector3(1.3, 1.3, 1.3)
			p.player_name = r["name"]
			p.speed_stat = r["speed"]
			p.shoot_stat = r["shoot"]
			p.pass_stat = r["pass"]
			p.player_id = r["id"]
			p.accel_stat = r["accel"]
			p.stamina_stat = r["stamina"]
			p.dribble_stat = r["dribble"]
			p.defense_stat = r["defense"]
			p.keeper_stat = r["keeper"]
			p.rotation.y = _yaw(Vector3(0, 0, _atk_sign(team_id)))
			players.append(p)


func _colour_close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.6


func _build_ball() -> void:
	ball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	ball.mesh = sm
	ball.scale = Vector3(1.5, 1.5, 1.5)
	ball.material_override = _mat(Color("fafafa"))
	ball.position = Vector3(0, BALL_R, 0)
	add_child(ball)
	ball_shadow = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.4
	cm.bottom_radius = 0.4
	cm.height = 0.01
	cm.radial_segments = 10
	ball_shadow.mesh = cm
	ball_shadow.material_override = _mat(Color(0, 0, 0, 0.4))
	add_child(ball_shadow)


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 32.0
	cam.far = 400.0
	cam.position = Vector3(CAM_X, CAM_H, 0)
	add_child(cam)
	cam.look_at(Vector3(4.0, 0, 0), Vector3.UP)
	cam.current = true


func _build_controls() -> void:
	controls = TouchControls.new()
	add_child(controls)
	if smoke:
		controls.run_selftest()
	controls.button_down.connect(_on_button_down)
	controlled = _nearest_player(0)
	indicator = Node3D.new()
	var arrow := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.0
	cm.height = 0.8
	cm.radial_segments = 4
	arrow.mesh = cm
	var im := StandardMaterial3D.new()
	im.albedo_color = Color("27e0ff")
	im.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow.material_override = im
	indicator.add_child(arrow)
	number_label = Label3D.new()
	number_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	number_label.font_size = 64
	number_label.pixel_size = 0.012
	number_label.position = Vector3(0, 0.9, 0)
	number_label.modulate = Color("27e0ff")
	number_label.outline_size = 12
	number_label.no_depth_test = true
	indicator.add_child(number_label)
	add_child(indicator)


func _build_hud() -> void:
	hud = Hud.new()
	add_child(hud)
	var ta: Dictionary = Global.TEAMS[team_a]
	var tb: Dictionary = Global.TEAMS[team_b]
	hud.setup(ta["name"], ta["code"], kits[0], tb["name"], tb["code"], kits[1])
	hud.start_pressed.connect(_on_start_pressed)
	hud.replay_pressed.connect(_on_replay)
	hud.menu_pressed.connect(_on_menu)
	hud.set_score(0, 0)


func _on_start_pressed() -> void:
	hud.hide_intro()
	_begin_kickoff(0)


func _on_replay() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ================================================================ per-frame

func _process(delta: float) -> void:
	if cam == null or ball == null or hud == null:
		return
	_t += delta
	if smoke:
		_auto_t += delta
		if _auto_t >= 30.0:
			_auto_t = 0.0
			print("SMOKE_STATUS t=%.0f mode=%d clock=%s score=%d-%d holder=%s ball=%s" % [_t, mode, _clock_text(), score[0], score[1], holder.player_name if holder != null and is_instance_valid(holder) else "none", ball.position])
	if smoke and holder != null and is_instance_valid(holder) and mode == M_PLAY:
		var tm: int = holder.team_id
		_adv[tm] = maxf(_adv[tm], ball.position.z * _atk_sign(tm))
		_carry_frames[tm] += 1
	if smoke:
		if mode == M_PLAY and holder == null:
			_loose_t += delta
			if _loose_t > 8.0:
				_loose_t = 0.0
				print("SMOKE_LOOSE half=%d ball=%s vel=%s y_ok=%s blocked=%s" % [half, ball.position, ball_vel, ball.position.y <= 1.3, blocked_player.player_name if blocked_player != null and is_instance_valid(blocked_player) else "none"])
				var near: Array = []
				for q in players:
					near.append([q.position.distance_to(ball.position), q])
				near.sort_custom(func(x, y): return x[0] < y[0])
				for i in 3:
					var q: Player = near[i][1]
					print("   near%d d=%.1f team=%d role=%s pos=%s" % [i, near[i][0], q.team_id, q.role, q.position])
		else:
			_loose_t = 0.0
	# Side-line TV camera following the ball along the pitch.
	var f := ball.position
	var look_z := clampf(f.z + ball_vel.z * 0.12, -HALF_L + 12.0, HALF_L - 12.0)
	cam_z = lerpf(cam_z, look_z, clampf(delta * 3.0, 0.0, 1.0))
	var look_x := f.x * 0.15
	cam.position = Vector3(CAM_X + look_x, CAM_H, cam_z)
	cam.look_at(Vector3(4.0 + look_x, 0.0, cam_z), Vector3.UP)
	ball_shadow.position = Vector3(ball.position.x, 0.03, ball.position.z)
	var sh := clampf(1.0 - (ball.position.y - BALL_R) * 0.08, 0.4, 1.0)
	ball_shadow.scale = Vector3(sh, 1.0, sh)
	_gk_dive_fx()
	_update_hud()


func _gk_dive_fx() -> void:
	if mode != M_PLAY or ball_vel.length() < 14.0:
		return
	for q in players:
		if q.role != "GK":
			continue
		var rel := ball.position - q.position
		rel.y = 0.0
		if rel.length() > 7.0:
			continue
		var right := Vector3(cos(q.rotation.y), 0.0, -sin(q.rotation.y))
		var lat := rel.dot(right)
		if absf(lat) > 0.8:
			q.dive(signf(lat))


func _update_hud() -> void:
	hud.set_clock(_clock_text())
	var valid_c := controlled != null and is_instance_valid(controlled)
	indicator.visible = valid_c
	if valid_c:
		indicator.position = controlled.position + Vector3(0, 3.4 + sin(_t * 6.0) * 0.12, 0)
		number_label.text = str(controlled.shirt_number)
		hud.set_card(false, controlled.role, controlled.player_name, controlled.stamina)
	var opp := _card_opponent()
	if opp != null:
		hud.set_card(true, opp.role, opp.player_name, 1.0, false)
	if controls != null:
		var defending := holder != null and is_instance_valid(holder) and holder.team_id == 1 and mode == M_PLAY
		controls.set_label("PASS", "TACKLE" if defending else "PASS")
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	for p in players:
		var v := Vector2(0.5 - p.position.z / PITCH_L, 0.5 + p.position.x / PITCH_W)
		if p.team_id == 0:
			a.append(v)
		else:
			b.append(v)
	var hv := Vector2(-1, -1)
	if valid_c:
		hv = Vector2(0.5 - controlled.position.z / PITCH_L, 0.5 + controlled.position.x / PITCH_W)
	hud.update_map(a, b, Vector2(0.5 - ball.position.z / PITCH_L, 0.5 + ball.position.x / PITCH_W), hv)


func _card_opponent() -> Player:
	if holder != null and is_instance_valid(holder) and holder.team_id == 1:
		return holder
	var best: Player = null
	var best_d := INF
	for p in players:
		if p.team_id != 1:
			continue
		var d := p.position.distance_squared_to(ball.position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _clock_text() -> String:
	var secs := int(match_time)
	var txt := "%s  %02d:%02d" % ["1ST" if half == 1 else "2ND", secs / 60, secs % 60]
	if half_end_reached:
		txt += "  +%d" % added_minutes
	return txt


func _physics_process(delta: float) -> void:
	if ball == null or controls == null or hud == null:
		return
	_ensure_controlled()
	if botplay and (mode == M_PLAY or _is_restart_mode()):
		_bot_input(delta)
	match mode:
		M_INTRO, M_FULLTIME:
			pass
		M_HALFTIME:
			mode_timer -= delta
			if mode_timer <= 0.0:
				_start_second_half()
		M_GOAL:
			mode_timer -= delta
			_ball_physics(delta)
			if absf(ball.position.z) > HALF_L + 1.9:
				ball.position.z = signf(ball.position.z) * (HALF_L + 1.9)
				ball_vel *= 0.2
			if mode_timer <= 0.0:
				_begin_kickoff(conceding_team)
		_:
			_play_tick(delta)


func _play_tick(delta: float) -> void:
	if smoke:
		_selftest()
	_update_clock(delta)
	if mode == M_HALFTIME or mode == M_FULLTIME:
		return
	_update_ball(delta)
	if _is_restart_mode():
		_update_restart(delta)
	_update_ai(delta)
	_move_controlled(delta)
	_regen_stamina(delta)
	_auto_switch(delta)


func _ensure_controlled() -> void:
	if autoplay:
		return
	if controlled == null or not is_instance_valid(controlled) or controlled.is_queued_for_deletion():
		controlled = _nearest_player(0)


func _is_restart_mode() -> bool:
	return mode == M_KICKOFF or mode == M_THROW or mode == M_GOALKICK or mode == M_CORNER or mode == M_FREEKICK or mode == M_PENALTY


# ================================================================ clock / halves

func _update_clock(delta: float) -> void:
	if mode == M_KICKOFF:
		return
	match_time += delta * clock_speed
	if holder != null and is_instance_valid(holder):
		stats["possession"][holder.team_id] += delta
	var end := HALF_SECONDS * float(half)
	if not half_end_reached and match_time >= end:
		half_end_reached = true
		added_minutes = clampi(1 + int(fouls_this_half / 3.0), 1, 4)
		hud.message("+%d MIN ADDED" % added_minutes, 2.5)
	if half_end_reached and match_time >= end + float(added_minutes) * 60.0 and mode == M_PLAY:
		if half == 1:
			_begin_halftime()
		else:
			_begin_fulltime()


func _begin_halftime() -> void:
	mode = M_HALFTIME
	mode_timer = 3.5
	holder = null
	sfx.play("whistle")
	hud.message("HALF TIME", 3.0, true, "%d - %d" % [score[0], score[1]])
	if smoke:
		print("SMOKE_HALFTIME score=%d-%d" % [score[0], score[1]])


func _start_second_half() -> void:
	half = 2
	side = -1.0
	half_end_reached = false
	fouls_this_half = 0
	added_minutes = 0
	for p in players:
		p.home_pos = Vector3(-p.home_pos.x, 0.0, -p.home_pos.z)
	_begin_kickoff(1)


func _begin_fulltime() -> void:
	mode = M_FULLTIME
	holder = null
	var na: String = Global.TEAMS[team_a]["name"]
	var nb: String = Global.TEAMS[team_b]["name"]
	sfx.play("whistle")
	hud.message("FULL TIME", 3.0, true)
	hud.show_fulltime(na, nb, score[0], score[1], _stats_text())
	if smoke:
		print("SMOKE_DONE score=%d-%d" % [score[0], score[1]])
		print("SMOKE_STATS " + str(stats))
		print("SMOKE_ADV max_advance=%s carry_frames=%s" % [_adv, _carry_frames])
		get_tree().quit()


func _stats_text() -> String:
	var pa: float = stats["possession"][0]
	var pb: float = stats["possession"][1]
	var tot := maxf(pa + pb, 0.001)
	var ppa := int(round(pa / tot * 100.0))
	var lines := [
		"Possession     %d%% - %d%%" % [ppa, 100 - ppa],
		"Shots              %d - %d" % [stats["shots"][0], stats["shots"][1]],
		"Fouls              %d - %d" % [stats["fouls"][0], stats["fouls"][1]],
		"Yellow cards   %d - %d" % [stats["yellow"][0], stats["yellow"][1]],
		"Red cards       %d - %d" % [stats["red"][0], stats["red"][1]],
		"Corners          %d - %d" % [stats["corners"][0], stats["corners"][1]],
		"Offsides         %d - %d" % [stats["offsides"][0], stats["offsides"][1]],
	]
	return "\n".join(lines)


# ================================================================ restarts

func _place_formation() -> void:
	for p in players:
		p.position = p.home_pos
		p.rotation.y = _yaw(Vector3(0, 0, _atk_sign(p.team_id)))
	ball.position = Vector3(0, BALL_R, 0)


func _begin_kickoff(team: int) -> void:
	_place_formation()
	holder = null
	offside_list.clear()
	var taker := _kickoff_taker(team)
	_start_restart(M_KICKOFF, team, Vector3(0, BALL_R, 0), taker)


func _kickoff_taker(team: int) -> Player:
	var best: Player = null
	var best_d := INF
	for p in players:
		if p.team_id != team or p.role == "GK":
			continue
		var d := p.position.length() + (0.0 if p.role == "FWD" else 20.0)
		if d < best_d:
			best_d = d
			best = p
	return best


func _gk_of(team: int) -> Player:
	for p in players:
		if p.team_id == team and p.role == "GK":
			return p
	return null


func _pick_taker(kind: int, team: int, pos: Vector3) -> Player:
	if kind == M_GOALKICK:
		var gk := _gk_of(team)
		if gk != null:
			return gk
	var best: Player = null
	var best_v := INF
	for p in players:
		if p.team_id != team or p.role == "GK":
			continue
		var v := Vector2(p.position.x - pos.x, p.position.z - pos.z).length()
		if kind == M_PENALTY:
			v = 100.0 - float(p.shoot_stat)
		if v < best_v:
			best_v = v
			best = p
	return best


func _restart_facing(kind: int, team: int, pos: Vector3) -> Vector3:
	match kind:
		M_THROW:
			return Vector3(-signf(pos.x), 0.0, 0.0)
		M_GOALKICK:
			return Vector3(0.0, 0.0, -signf(pos.z))
		M_CORNER:
			return Vector3(-signf(pos.x), 0.0, -signf(pos.z)).normalized()
		M_FREEKICK:
			var to_goal := Vector3(0.0, 0.0, _atk_sign(team) * HALF_L) - pos
			to_goal.y = 0.0
			return to_goal.normalized()
	return Vector3(0.0, 0.0, _atk_sign(team))


func _start_restart(kind: int, team: int, pos: Vector3, taker: Player) -> void:
	mode = kind
	restart_team = team
	restart_pos = Vector3(pos.x, BALL_R, pos.z)
	restart_taker = taker
	restart_wait = 0.0
	if autoplay or team == 1:
		restart_wait_max = randf_range(1.8, 2.6) if kind == M_PENALTY else randf_range(0.9, 1.6)
	else:
		restart_wait_max = 12.0
	offside_list.clear()
	for q in players:
		q.vel = Vector3.ZERO
	ball_vel = Vector3.ZERO
	hold_time = 0.0
	blocked_timer = 0.0
	ball.position = restart_pos
	holder = taker
	if taker != null:
		var f := _restart_facing(kind, team, restart_pos)
		taker.position = Vector3(restart_pos.x, 0.0, restart_pos.z) - f * 0.9
		taker.rotation.y = _yaw(f)
	if kind == M_PENALTY:
		var gk := _gk_of(1 - team)
		if gk != null:
			var gz := signf(restart_pos.z)
			gk.position = Vector3(0.0, 0.0, gz * (HALF_L - 0.6))
			gk.rotation.y = _yaw(Vector3(0, 0, -gz))
	if not autoplay:
		if team == 0 and taker != null:
			controlled = taker
		else:
			controlled = _nearest_player(0)
	if kind == M_FREEKICK or kind == M_PENALTY or kind == M_KICKOFF:
		sfx.play("whistle", -6.0)
	match kind:
		M_THROW:
			hud.message("THROW-IN", 1.5)
		M_GOALKICK:
			hud.message("GOAL KICK", 1.5)
		M_CORNER:
			hud.message("CORNER", 1.5)
		M_FREEKICK:
			hud.message("FREE KICK", 1.5)
		M_PENALTY:
			hud.message("PENALTY!", 2.0, true)
		M_KICKOFF:
			if half == 1 and match_time < 1.0:
				hud.message("KICK OFF", 1.5)


func _update_restart(delta: float) -> void:
	restart_wait += delta
	if restart_taker == null or not is_instance_valid(restart_taker) or restart_taker.is_queued_for_deletion():
		var t := _pick_taker(mode, restart_team, restart_pos)
		if mode == M_KICKOFF:
			t = _kickoff_taker(restart_team)
		_start_restart(mode, restart_team, restart_pos, t)
		return
	holder = restart_taker
	_enforce_zones()
	if restart_wait >= restart_wait_max:
		_ai_take_restart()


func _push_from(p: Player, center: Vector3, r: float) -> void:
	var d := Vector2(p.position.x - center.x, p.position.z - center.z)
	if d.length() < r:
		if d.length() < 0.01:
			d = Vector2(1, 0)
		d = d.normalized() * r
		p.position.x = center.x + d.x
		p.position.z = center.z + d.y


func _push_out_of_box(p: Player, end_sign: float) -> void:
	if absf(p.position.x) < BOX_HW + 0.5 and p.position.z * end_sign > HALF_L - BOX_D - 0.5:
		p.position.z = end_sign * (HALF_L - BOX_D - 1.0)


func _enforce_zones() -> void:
	for p in players:
		if p == restart_taker:
			continue
		var other := p.team_id != restart_team
		match mode:
			M_THROW:
				if other:
					_push_from(p, restart_pos, 3.0)
			M_CORNER, M_FREEKICK:
				if other and p.role != "GK":
					_push_from(p, restart_pos, 9.3)
			M_GOALKICK:
				if other:
					_push_out_of_box(p, signf(restart_pos.z))
			M_PENALTY:
				if p.role == "GK" and other:
					continue
				_push_out_of_box(p, signf(restart_pos.z))
				_push_from(p, restart_pos, 9.3)


func _ai_take_restart() -> void:
	var p := restart_taker
	match mode:
		M_KICKOFF, M_THROW:
			if not _ai_pass(p, false):
				_force_clear(p)
		M_GOALKICK:
			if not _ai_pass(p, true):
				_force_clear(p)
		M_CORNER:
			_ai_cross(p)
		M_FREEKICK:
			var gz := _atk_sign(p.team_id) * HALF_L
			var d := Vector2(p.position.x, p.position.z - gz).length()
			if d < 30.0 and randf() < 0.7:
				_ai_shoot(p)
			elif not _ai_pass(p, false):
				_force_clear(p)
		M_PENALTY:
			_ai_shoot(p)


func _release_ball(kicker: Player) -> int:
	var prev := mode
	holder = null
	blocked_player = kicker
	blocked_timer = 0.4
	last_touch_team = kicker.team_id
	last_touch_name = kicker.player_name
	kicker.kick()
	if prev != M_PLAY:
		no_offside_kick = prev == M_KICKOFF or prev == M_THROW or prev == M_GOALKICK or prev == M_CORNER
		mode = M_PLAY
		restart_taker = null
	else:
		no_offside_kick = false
	return prev


func _launch(vel: Vector3, prev: int, curve: float = 0.0) -> void:
	ball_spin = curve
	if prev != M_THROW:
		sfx.play("kick", clampf(-14.0 + vel.length() * 0.5, -14.0, 0.0))
	if prev == M_THROW:
		var h := Vector2(vel.x, vel.z)
		if h.length() > 15.0:
			h = h.normalized() * 15.0
		vel = Vector3(h.x, 4.5, h.y)
	ball_vel = vel


func _force_clear(p: Player) -> void:
	var atk := _atk_sign(p.team_id)
	var prev := _release_ball(p)
	var dir := Vector3(randf_range(-0.5, 0.5), 0.0, atk).normalized()
	_launch(dir * 16.0 + Vector3(0, 4.0, 0), prev)


# ================================================================ out of play / goals

func _check_ball_bounds(allow_goal: bool) -> void:
	if mode != M_PLAY:
		return
	var p := ball.position
	if absf(p.z) >= HALF_L:
		var end := signf(p.z)
		if allow_goal and absf(p.x) < GOAL_W / 2.0 and p.y < GOAL_H:
			_score_goal(end)
		else:
			_ball_out_goal_line(end)
		return
	if absf(p.x) > HALF_W:
		_ball_out_side()


func _score_goal(end: float) -> void:
	var conceding := 0 if signf(_own_goal_z(0)) == end else 1
	var scorer := 1 - conceding
	score[scorer] += 1
	conceding_team = conceding
	mode = M_GOAL
	mode_timer = 3.0
	holder = null
	var who := last_touch_name
	if last_touch_team != scorer:
		who = "OWN GOAL"
	stadium.excite = 1.0
	for q in players:
		if q.team_id == scorer and q.role != "GK":
			q.celebrate(2.6)
	hud.set_score(score[0], score[1])
	hud.message("GOAL!", 3.0, true, who)
	sfx.play("whistle")
	sfx.play("cheer", -4.0)


func _ball_out_side() -> void:
	var sx := 1.0 if ball.position.x >= 0.0 else -1.0
	var team := 1 - last_touch_team
	var pos := Vector3(sx * HALF_W, BALL_R, clampf(ball.position.z, -HALF_L + 1.0, HALF_L - 1.0))
	holder = null
	stats["throws"][team] += 1
	_start_restart(M_THROW, team, pos, _pick_taker(M_THROW, team, pos))


func _ball_out_goal_line(end: float) -> void:
	var d := 0 if signf(_own_goal_z(0)) == end else 1   # defending team of that end
	var sx := 1.0 if ball.position.x >= 0.0 else -1.0
	holder = null
	if last_touch_team == d:
		var a := 1 - d
		var pos := Vector3(sx * HALF_W, BALL_R, end * HALF_L)
		stats["corners"][a] += 1
		_start_restart(M_CORNER, a, pos, _pick_taker(M_CORNER, a, pos))
	else:
		var pos := Vector3(sx * 4.0, BALL_R, end * (HALF_L - 5.5))
		_start_restart(M_GOALKICK, d, pos, _gk_of(d))


# ================================================================ ball physics

func _update_ball(delta: float) -> void:
	blocked_timer = maxf(blocked_timer - delta, 0.0)
	tackle_cd = maxf(tackle_cd - delta, 0.0)
	if holder != null and (not is_instance_valid(holder) or holder.is_queued_for_deletion()):
		holder = null
	if holder != null:
		hold_time += delta
		if mode != M_PLAY:
			# Set pieces: the ball rests at the taker's feet.
			ball.position = holder.position + _forward(holder) * 0.9 + Vector3(0, BALL_R, 0)
			ball_vel = Vector3.ZERO
			return
		_dribble(delta)
		if holder != null and (holder != controlled or autoplay) and hold_time > 8.0:
			_force_clear(holder)
		_check_ball_bounds(true)
		return
	_ball_physics(delta)
	_try_pickup()
	_check_ball_bounds(true)


func _dribble(delta: float) -> void:
	## The ball has its own velocity: a spring pulls it toward a point just ahead
	## of the carrier, so it lags, overshoots a little and can be lost.
	var h := holder
	var hv := Vector3(h.vel.x, 0.0, h.vel.z)
	var sp := hv.length()
	var lead_dir := hv / sp if sp > 0.8 else _forward(h)
	var lead := 0.85 + minf(sp, 9.0) * 0.07
	var target := h.position + lead_dir * lead
	ball_vel.x += ((target.x - ball.position.x) * 55.0 - (ball_vel.x - hv.x) * 9.0) * delta
	ball_vel.z += ((target.z - ball.position.z) * 55.0 - (ball_vel.z - hv.z) * 9.0) * delta
	ball_vel.y = 0.0
	ball.position.x += ball_vel.x * delta
	ball.position.z += ball_vel.z * delta
	ball.position.y = BALL_R
	if Vector2(ball.position.x - h.position.x, ball.position.z - h.position.z).length() > 2.4:
		holder = null   # lost control of the ball


func _ball_physics(delta: float) -> void:
	var flat_speed := Vector2(ball_vel.x, ball_vel.z).length()
	if absf(ball_spin) > 0.01 and flat_speed > 3.0 and ball.position.y > BALL_R + 0.05:
		var perp := Vector3(-ball_vel.z, 0.0, ball_vel.x).normalized()
		ball_vel += perp * ball_spin * flat_speed * 0.2 * delta
	ball_spin *= clampf(1.0 - 0.7 * delta, 0.0, 1.0)
	var air := clampf(1.0 - 0.12 * delta, 0.0, 1.0)
	ball_vel.x *= air
	ball_vel.z *= air
	ball_vel.y -= GRAVITY * delta
	ball.position += ball_vel * delta
	if ball.position.y <= BALL_R:
		ball.position.y = BALL_R
		if ball_vel.y < 0.0:
			if absf(ball_vel.y) > 3.0:
				sfx.play("bounce", clampf(-18.0 + absf(ball_vel.y), -18.0, -4.0))
			ball_vel.y = -ball_vel.y * 0.55
			if ball_vel.y < 1.5:
				ball_vel.y = 0.0
		var damp := clampf(1.0 - 1.4 * delta, 0.0, 1.0)
		ball_vel.x *= damp
		ball_vel.z *= damp
		if Vector2(ball_vel.x, ball_vel.z).length() < 0.2:
			ball_vel.x = 0.0
			ball_vel.z = 0.0


func _try_pickup() -> void:
	if mode != M_PLAY or ball.position.y > 1.3:
		return
	var speed := Vector2(ball_vel.x, ball_vel.z).length()
	var best: Player = null
	var best_d := INF
	for p in players:
		if p == blocked_player and blocked_timer > 0.0:
			continue
		var is_gk := p.role == "GK"
		if speed > (40.0 if is_gk else 11.0 + 0.08 * float(maxi(p.dribble_stat, p.defense_stat))):
			continue
		var reach := 1.25
		if is_gk:
			var diff_scale: float = [0.75, 0.92, 1.08][Global.difficulty]
			reach = (1.2 + float(p.keeper_stat) * 0.009) * (diff_scale if p.team_id == 1 else 1.0)
		var d := Vector2(p.position.x - ball.position.x, p.position.z - ball.position.z).length()
		if d < reach and d < best_d:
			best_d = d
			best = p
	if best == null:
		return
	if best.team_id == offside_team and best in offside_list:
		offside_list.clear()
		_call_offside(best)
		return
	offside_list.clear()
	holder = best
	hold_time = 0.0
	last_touch_team = best.team_id
	last_touch_name = best.player_name
	if best.team_id == 0 and not autoplay:
		controlled = best


# ================================================================ offside

func _offside_line(attacking_team: int) -> float:
	## Position (along the attack axis) of the second-last defender.
	var atk := _atk_sign(attacking_team)
	var vals: Array[float] = []
	for q in players:
		if q.team_id != attacking_team:
			vals.append(q.position.z * atk)
	if vals.size() < 2:
		return HALF_L
	vals.sort()
	return vals[vals.size() - 2]


func _would_be_offside(t: Player) -> bool:
	if mode == M_KICKOFF or mode == M_THROW or mode == M_GOALKICK or mode == M_CORNER:
		return false
	var atk := _atk_sign(t.team_id)
	var tz := t.position.z * atk
	return tz > 0.0 and tz > _offside_line(t.team_id) + 0.3 and tz > ball.position.z * atk + 0.3


func _register_pass(kicker: Player) -> void:
	offside_list.clear()
	offside_team = kicker.team_id
	if no_offside_kick:
		return
	var atk := _atk_sign(kicker.team_id)
	var line := _offside_line(kicker.team_id)
	var bz := ball.position.z * atk
	for t in players:
		if t.team_id != kicker.team_id or t == kicker:
			continue
		var tz := t.position.z * atk
		if tz > 0.0 and tz > line + 0.3 and tz > bz + 0.3:
			offside_list.append(t)


func _call_offside(p: Player) -> void:
	stats["offsides"][p.team_id] += 1
	hud.message("OFFSIDE", 1.8, false, p.player_name)
	var spot := Vector3(clampf(p.position.x, -HALF_W + 0.5, HALF_W - 0.5), BALL_R, clampf(p.position.z, -HALF_L + 0.5, HALF_L - 0.5))
	var team := 1 - p.team_id
	holder = null
	_start_restart(M_FREEKICK, team, spot, _pick_taker(M_FREEKICK, team, spot))


# ================================================================ fouls & cards

func _attempt_tackle(tackler: Player, victim: Player, win_chance: float) -> void:
	if mode != M_PLAY:
		return
	var to_t := tackler.position - victim.position
	to_t.y = 0.0
	var behind := to_t.length() > 0.01 and _forward(victim).dot(to_t.normalized()) < -0.2
	var foul_p := 0.04 + (0.07 if behind else 0.0)
	var r := randf()
	if r < foul_p:
		_call_foul(tackler, victim)
	elif r < foul_p + clampf(win_chance + float(tackler.defense_stat - victim.dribble_stat) * 0.004, 0.05, 0.9):
		blocked_player = victim
		blocked_timer = 0.8
		holder = tackler
		hold_time = 0.0
		last_touch_team = tackler.team_id
		last_touch_name = tackler.player_name
		offside_list.clear()
		if tackler.team_id == 0 and not autoplay:
			controlled = tackler


func _call_foul(off: Player, vic: Player) -> void:
	var spot := Vector3(clampf(vic.position.x, -HALF_W + 0.5, HALF_W - 0.5), BALL_R, clampf(vic.position.z, -HALF_L + 0.5, HALF_L - 0.5))
	stats["fouls"][off.team_id] += 1
	fouls_this_half += 1
	var title := "FOUL"
	var sent_off := false
	if off.role != "GK":
		var r := randf()
		if r < 0.04:
			sent_off = true
			stats["red"][off.team_id] += 1
			title = "RED CARD"
		elif r < 0.26:
			off.yellow += 1
			stats["yellow"][off.team_id] += 1
			if off.yellow >= 2:
				sent_off = true
				stats["red"][off.team_id] += 1
				title = "2ND YELLOW - RED CARD"
			else:
				title = "YELLOW CARD"
	sfx.play("whistle")
	hud.message(title, 2.2, false, off.player_name)
	var team := vic.team_id
	var end_sign := signf(_own_goal_z(off.team_id))
	var in_box := absf(spot.x) < BOX_HW and spot.z * end_sign > HALF_L - BOX_D
	if sent_off:
		_send_off(off)
	holder = null
	if in_box:
		var pen := Vector3(0.0, BALL_R, end_sign * (HALF_L - 11.0))
		_start_restart(M_PENALTY, team, pen, _pick_taker(M_PENALTY, team, pen))
	else:
		_start_restart(M_FREEKICK, team, spot, _pick_taker(M_FREEKICK, team, spot))


func _send_off(p: Player) -> void:
	players.erase(p)
	if controlled == p:
		controlled = null
	if blocked_player == p:
		blocked_player = null
	if restart_taker == p:
		restart_taker = null
	offside_list.erase(p)
	p.queue_free()


# ================================================================ human control

func _stick_dir() -> Vector3:
	## Camera sits on the +X touchline: screen-right = -Z, screen-up = -X.
	if controls == null:
		return Vector3.ZERO
	var v := controls.move
	if v == Vector2.ZERO:
		return Vector3.ZERO
	return Vector3(v.y, 0.0, -v.x)


func _move_controlled(delta: float) -> void:
	_running = false
	if controlled == null or not is_instance_valid(controlled):
		return
	var c := controlled
	var dir := _stick_dir()
	if _is_restart_mode():
		if c == restart_taker:
			c.vel = Vector3.ZERO
			if dir != Vector3.ZERO:
				c.rotation.y = lerp_angle(c.rotation.y, _yaw(dir), clampf(delta * 14.0, 0.0, 1.0))
			return
		if mode == M_KICKOFF or mode == M_PENALTY:
			c.vel = Vector3.ZERO
			return
	var desired := Vector3.ZERO
	if dir != Vector3.ZERO:
		var spd := c.top_speed()
		if controls.held.get("RUN", false) and c.stamina > 0.05:
			spd *= 1.35
			_running = true
			c.stamina = maxf(0.0, c.stamina - 0.30 * (1.6 - float(c.stamina_stat) / 100.0) * delta)
		desired = dir.limit_length(1.0) * spd
	c.step_move(desired, delta)
	c.position.x = clampf(c.position.x, -HALF_W - 2.0, HALF_W + 2.0)
	c.position.z = clampf(c.position.z, -HALF_L - 3.0, HALF_L + 3.0)


func _regen_stamina(delta: float) -> void:
	for p in players:
		if p == controlled and _running:
			continue
		p.stamina = minf(1.0, p.stamina + (0.07 + float(p.stamina_stat) * 0.0007) * delta)


func _nearest_player(team_id: int, exclude: Player = null) -> Player:
	var best: Player = null
	var best_d := INF
	for p in players:
		if p.team_id != team_id or p.role == "GK" or p == exclude:
			continue
		var d := p.position.distance_squared_to(ball.position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _switch_player() -> void:
	var n := _nearest_player(0, controlled)
	if n != null:
		controlled = n


func _auto_switch(delta: float) -> void:
	## While defending, hand control to whoever is closest to the ball.
	if autoplay or mode != M_PLAY or controlled == null:
		return
	_auto_switch_t += delta
	if _auto_switch_t < 0.5:
		return
	_auto_switch_t = 0.0
	if holder != null and holder.team_id == 0:
		return
	var n := _nearest_player(0)
	if n != null and n != controlled and n.position.distance_to(ball.position) + 3.0 < controlled.position.distance_to(ball.position):
		controlled = n


func _on_button_down(action: String) -> void:
	if controlled == null or not is_instance_valid(controlled):
		return
	if mode != M_PLAY and not _is_restart_mode():
		return
	var has_ball := holder == controlled
	match action:
		"SWITCH":
			if mode == M_PLAY and not has_ball:
				_switch_player()
		"PASS":
			if has_ball:
				_kick_pass(false)
			elif mode == M_PLAY:
				_tackle()
		"LONG":
			if has_ball:
				_kick_pass(true)
		"SHOOT":
			if has_ball:
				if mode == M_PLAY or mode == M_FREEKICK or mode == M_PENALTY:
					_kick_shoot()
				else:
					_kick_pass(true)


func _kick_pass(lofted: bool) -> void:
	var me := controlled
	var dir := _forward(me)
	var sd := _stick_dir()
	if sd != Vector3.ZERO:
		dir = sd.normalized()
	var best: Player = null
	var best_score := -INF
	for p in players:
		if p.team_id != 0 or p == me:
			continue
		var to := p.position - me.position
		to.y = 0.0
		var dist := to.length()
		if dist < 4.0 or dist > 45.0:
			continue
		var s := to.normalized().dot(dir) * 3.0 - dist / 30.0
		if lofted:
			s += minf(dist, 30.0) / 20.0
		if p.role == "GK":
			s -= 1.0
		if _would_be_offside(p):
			s -= 2.5
		if s > best_score:
			best_score = s
			best = p
	var flat_dir := dir
	var dist_t := 15.0
	if best != null:
		var to_t := best.position - me.position
		to_t.y = 0.0
		if to_t.normalized().dot(dir) > 0.3:
			flat_dir = to_t.normalized()
			dist_t = to_t.length()
	var prev := _release_ball(me)
	if lofted:
		_launch(flat_dir * clampf(dist_t / 0.8, 10.0, 32.0) + Vector3(0, 9.0, 0), prev, randf_range(-0.25, 0.25))
	else:
		var spd := clampf(dist_t * 1.5 + 7.0, 10.0, 26.0) * (0.85 + float(me.pass_stat) / 500.0)
		_launch(flat_dir * spd, prev)
	_register_pass(me)


func _kick_shoot() -> void:
	var me := controlled
	var gz := _atk_sign(me.team_id) * HALF_L
	var aim_x := randf_range(-2.8, 2.8)
	var sd := _stick_dir()
	if absf(sd.x) > 0.2:
		aim_x = clampf(sd.x, -1.0, 1.0) * 3.0
	var to_goal := Vector3(aim_x, 0.0, gz) - me.position
	to_goal.y = 0.0
	var dist := to_goal.length()
	var dir := to_goal.normalized()
	dir.x += randf_range(-0.04, 0.04) * dist / 10.0
	dir = dir.normalized()
	stats["shots"][me.team_id] += 1
	var prev := _release_ball(me)
	_launch(dir * (24.0 + float(me.shoot_stat) * 0.12) + Vector3(0, 1.5 + randf() * 2.0, 0), prev, randf_range(-0.6, 0.6))
	offside_list.clear()


func _tackle() -> void:
	if holder == null or holder.team_id != 1 or tackle_cd > 0.0 or mode != M_PLAY:
		return
	if holder.position.distance_to(controlled.position) > 2.4:
		return
	tackle_cd = 0.6
	_attempt_tackle(controlled, holder, 0.7)


# ================================================================ AI

func _update_ai(delta: float) -> void:
	if mode == M_INTRO or mode == M_GOAL or mode == M_HALFTIME or mode == M_FULLTIME:
		return
	var diff := Global.difficulty
	var spd_mult: float = [0.75, 0.9, 1.05][diff]
	var react: float = [0.9, 0.55, 0.3][diff]
	for p in players:
		p.ai_cd = maxf(p.ai_cd - delta, 0.0)
	if mode == M_KICKOFF or mode == M_PENALTY:
		return
	var snapshot := players.duplicate()
	for team_id in 2:
		var chaser := _chaser(team_id)
		var has_ball := holder != null and holder.team_id == team_id
		for p in snapshot:
			if not is_instance_valid(p) or p.is_queued_for_deletion() or p.team_id != team_id:
				continue
			if p == controlled and not autoplay:
				continue
			if p == restart_taker and _is_restart_mode():
				continue
			var mult := spd_mult if team_id == 1 else 0.95
			if p.role == "GK":
				mult = 1.3
			if p == holder:
				_ai_with_ball(p, react, mult, delta)
				continue
			_move_toward(p, _ai_target(p, chaser, has_ball), mult, delta)
			if p == chaser and mode == M_PLAY and holder != null and holder.team_id != team_id:
				_ai_try_tackle(p, diff)


func _chaser(team_id: int) -> Player:
	if holder != null and holder.team_id == team_id:
		return null
	var best: Player = null
	var best_d := INF
	for p in players:
		if p.team_id != team_id or p.role == "GK" or p == controlled:
			continue
		var d := p.position.distance_squared_to(ball.position)
		if d < best_d:
			best_d = d
			best = p
	if team_id == 0 and controlled != null and best != null:
		if controlled.position.distance_squared_to(ball.position) < best_d:
			return null   # the human is closer, let them go for it
	return best


func _corner_target(p: Player) -> Vector3:
	var e := signf(restart_pos.z)
	var slot := float(p.shirt_number % 5) - 2.0
	if p.team_id == restart_team:
		if p.role == "DEF":
			return Vector3(slot * 3.0, 0.0, e * (HALF_L - 30.0))
		return Vector3(slot * 4.0, 0.0, e * (HALF_L - 9.0 - absf(slot)))
	return Vector3(slot * 3.5, 0.0, e * (HALF_L - 6.0 - absf(slot)))


func _ai_target(p: Player, chaser: Player, has_ball: bool) -> Vector3:
	if p.role == "GK":
		var gz := _own_goal_z(p.team_id)
		var out := clampf((22.0 - absf(ball.position.z - gz)) / 22.0, 0.0, 1.0) * 4.0
		return Vector3(clampf(ball.position.x * 0.45, -3.4, 3.4), 0.0, gz - signf(gz) * (1.5 + out))
	if mode == M_CORNER:
		return _corner_target(p)
	if p == chaser and mode == M_PLAY:
		if holder != null:
			return holder.position
		return _intercept_point(p)
	var atk := _atk_sign(p.team_id)
	var shift := clampf(ball.position.z, -HALF_L, HALF_L) * 0.45
	var push := 0.0
	if has_ball:
		if p.role == "FWD":
			push = atk * 18.0
		elif p.role == "MID":
			push = atk * 10.0
		else:
			push = atk * 4.0
	var t := Vector3(p.home_pos.x + ball.position.x * 0.2, 0.0, p.home_pos.z + shift + push)
	t.x = clampf(t.x, -HALF_W + 3.0, HALF_W - 3.0)
	t.z = clampf(t.z, -HALF_L + 8.0, HALF_L - 8.0)
	if p.role == "DEF" and t.z * atk > 4.0:
		t.z = 4.0 * atk
	if has_ball:
		# Stay onside: level with the second-last defender or behind the ball.
		var lim := maxf(_offside_line(p.team_id), ball.position.z * atk) - 0.8
		if t.z * atk > lim:
			t.z = lim * atk
	return t


func _intercept_point(p: Player) -> Vector3:
	## Where a rolling ball can be met: the closest point on its remaining path.
	var v := Vector3(ball_vel.x, 0.0, ball_vel.z)
	var speed := v.length()
	if speed < 2.0:
		return ball.position
	var dir := v / speed
	var rel := p.position - ball.position
	rel.y = 0.0
	var along := clampf(rel.dot(dir), 0.0, speed / 1.4 * 0.9)
	return ball.position + dir * along


func _move_toward(p: Player, target: Vector3, mult: float, delta: float) -> void:
	var to := target - p.position
	to.y = 0.0
	var dist := to.length()
	var desired := Vector3.ZERO
	if dist > 0.4:
		var spd := p.top_speed() * mult
		if dist > 12.0:
			spd *= 1.25
		spd *= clampf(dist / 2.5, 0.25, 1.0)   # ease in near the target
		desired = to / dist * spd
	p.step_move(desired, delta)


func _ai_try_tackle(p: Player, diff: int) -> void:
	if mode != M_PLAY or holder == null or holder.team_id == p.team_id or p.ai_cd > 0.0:
		return
	if p.position.distance_to(holder.position) > 1.9 or hold_time < 0.5:
		return
	p.ai_cd = 1.0
	var chance: float = [0.2, 0.35, 0.5][diff]
	if p.team_id == 0:
		chance = 0.5   # teammates help the human
	_attempt_tackle(p, holder, chance)


func _nearest_enemy_dist(pos: Vector3, team_id: int) -> float:
	var best := INF
	for q in players:
		if q.team_id == team_id:
			continue
		best = minf(best, Vector2(q.position.x - pos.x, q.position.z - pos.z).length())
	return best


func _ai_with_ball(p: Player, react: float, mult: float, delta: float) -> void:
	var atk := _atk_sign(p.team_id)
	var gz := atk * HALF_L
	if p.role == "GK":
		if hold_time > react + 0.6:
			if not _ai_pass(p, true):
				_force_clear(p)
		return
	var dist_goal := Vector2(p.position.x, p.position.z - gz).length()
	if hold_time > react:
		if dist_goal < 31.0:
			_ai_shoot(p)
			return
		var pressure := _nearest_enemy_dist(p.position, p.team_id)
		if pressure < 3.5 or hold_time > 5.0:
			if _ai_pass(p, false):
				return
	# Dribble toward goal, drifting toward the centre of the pitch.
	_move_toward(p, Vector3(p.position.x * 0.9, 0.0, gz), mult, delta)


func _ai_pass(p: Player, lofted: bool) -> bool:
	var atk := _atk_sign(p.team_id)
	var best: Player = null
	var best_s := -INF
	for t in players:
		if t.team_id != p.team_id or t == p or t.role == "GK":
			continue
		var to := t.position - p.position
		to.y = 0.0
		var d := to.length()
		if d < 5.0 or d > 34.0:
			continue
		if _would_be_offside(t):
			continue
		var s := atk * to.z * 0.06 - d * 0.02 + _nearest_enemy_dist(t.position, p.team_id) * 0.1
		if s > best_s:
			best_s = s
			best = t
	if best == null:
		return false
	var err: float = [0.12, 0.07, 0.04][Global.difficulty]
	var flat := best.position - p.position
	flat.y = 0.0
	var d2 := flat.length()
	flat = flat.normalized().rotated(Vector3.UP, randf_range(-err, err))
	var prev := _release_ball(p)
	if lofted or d2 > 30.0:
		_launch(flat * clampf(d2 / 0.8, 10.0, 32.0) + Vector3(0, 9.0, 0), prev, randf_range(-0.25, 0.25))
	else:
		_launch(flat * clampf(d2 * 1.5 + 7.0, 10.0, 26.0) * (0.85 + float(p.pass_stat) / 500.0), prev)
	_register_pass(p)
	return true


func _ai_cross(p: Player) -> void:
	var atk := _atk_sign(p.team_id)
	var target := Vector3(randf_range(-6.0, 6.0), 0.0, atk * (HALF_L - randf_range(6.0, 11.0)))
	var flat := target - p.position
	flat.y = 0.0
	var d := flat.length()
	var prev := _release_ball(p)
	_launch(flat.normalized() * clampf(d / 0.85, 12.0, 30.0) + Vector3(0, 9.0, 0), prev, randf_range(-0.4, 0.4))
	_register_pass(p)


func _ai_shoot(p: Player) -> void:
	var gz := _atk_sign(p.team_id) * HALF_L
	var err: float = [0.1, 0.06, 0.035][Global.difficulty]
	var to := Vector3(randf_range(-3.0, 3.0), 0.0, gz) - p.position
	to.y = 0.0
	var dir := to.normalized().rotated(Vector3.UP, randf_range(-err, err) * (1.0 + to.length() / 15.0))
	stats["shots"][p.team_id] += 1
	var prev := _release_ball(p)
	_launch(dir * (22.0 + float(p.shoot_stat) * 0.12) + Vector3(0, 1.5 + randf() * 1.5, 0), prev, randf_range(-0.6, 0.6))
	offside_list.clear()


# ================================================================ CI self-tests

func _bot_input(delta: float) -> void:
	## Simulates a person on the touch controls (CI only).
	_bot_t -= delta
	if _bot_t > 0.0:
		return
	_bot_t = randf_range(0.25, 0.8)
	var tgt := Vector3(randf_range(-20.0, 20.0), 0.0, _atk_sign(0) * HALF_L)
	var from := ball.position
	if controlled != null and is_instance_valid(controlled):
		from = controlled.position
	var dir := (tgt - from)
	dir.y = 0.0
	dir = dir.normalized().rotated(Vector3.UP, randf_range(-0.8, 0.8))
	controls.move = Vector2(-dir.z, dir.x)
	controls.held["RUN"] = randf() < 0.5
	var r := randf()
	if r < 0.25:
		_on_button_down("PASS")
	elif r < 0.35:
		_on_button_down("LONG")
	elif r < 0.45:
		_on_button_down("SHOOT")
	elif r < 0.55:
		_on_button_down("SWITCH")


func _selftest() -> void:
	## Forces rare situations once so CI proves those code paths run.
	if mode != M_PLAY:
		return
	if _selftests == 0 and _t > 10.0:
		_selftests = 1
		var off: Player = null
		var vic: Player = null
		for q in players:
			if q.team_id == 1 and q.role == "DEF" and off == null:
				off = q
			if q.team_id == 0 and q.role == "FWD" and vic == null:
				vic = q
		var es := signf(_own_goal_z(1))
		vic.position = Vector3(0.0, 0.0, es * (HALF_L - 8.0))
		_call_foul(off, vic)
		print("SMOKE_SELFTEST foul_in_box mode=%d (penalty=%d)" % [mode, M_PENALTY])
	elif _selftests == 1 and _t > 40.0:
		_selftests = 2
		for q in players:
			if q.team_id == 0 and q.role == "FWD":
				_call_offside(q)
				break
		print("SMOKE_SELFTEST offside mode=%d (freekick=%d)" % [mode, M_FREEKICK])
	elif _selftests == 2 and _t > 70.0:
		_selftests = 3
		for q in players:
			if q.team_id == 1 and q.role == "MID":
				_send_off(q)
				break
		print("SMOKE_SELFTEST send_off players=%d (expect 21)" % players.size())
