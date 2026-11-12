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
var controls: TouchControls
var controlled: Player
var indicator: MeshInstance3D
var _t := 0.0

const GRAVITY := 22.0
const BALL_R := 0.35
var ball_vel := Vector3.ZERO
var holder: Player = null          # player currently dribbling the ball
var hold_time := 0.0
var blocked_player: Player = null  # can't re-collect the ball for a moment
var blocked_timer := 0.0
var tackle_cd := 0.0
var goal_timer := 0.0
var score := [0, 0]
var score_label: Label
var goal_label: Label


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
	_build_controls()


func _focus_point() -> Vector3:
	# Camera focus: mostly the controlled player, a bit of the ball.
	if controlled == null:
		return ball.position
	return controlled.position.lerp(ball.position, 0.3)


func _process(delta: float) -> void:
	if cam == null or ball == null:
		return
	_t += delta
	var f := _focus_point()
	# TV-style camera: follows smoothly along the pitch.
	var target := Vector3(f.x * 0.4, 34.0, f.z * 0.75 + 30.0)
	target.z = clampf(target.z, -HALF_L + 18.0, HALF_L + 30.0)
	cam.position = cam.position.lerp(target, clampf(delta * 3.0, 0.0, 1.0))
	cam.look_at(Vector3(f.x * 0.4, 0.0, f.z * 0.75), Vector3.UP)
	if indicator != null and controlled != null:
		indicator.position = controlled.position + Vector3(0, 2.7 + sin(_t * 6.0) * 0.12, 0)
	if controls != null:
		var defending := holder != null and holder.team_id == 1
		controls.set_label("PASS", "TACKLE" if defending else "PASS")


func _physics_process(delta: float) -> void:
	if controls == null or ball == null:
		return
	_update_ball(delta)
	_update_ai(delta)
	_move_controlled(delta)


func _move_controlled(delta: float) -> void:
	if controlled == null or goal_timer > 0.0:
		return
	var v := controls.move
	if v == Vector2.ZERO:
		return
	# Camera looks toward -Z, so stick up = -Z, stick right = +X.
	var dir := Vector3(v.x, 0.0, v.y)
	var spd := 4.5 + 0.03 * float(controlled.speed_stat)
	if controls.held.get("RUN", false):
		spd *= 1.5
	var p := controlled.position + dir * spd * delta
	p.x = clampf(p.x, -HALF_W - 2.0, HALF_W + 2.0)
	p.z = clampf(p.z, -HALF_L - 3.0, HALF_L + 3.0)
	controlled.position = p
	var target_yaw := atan2(dir.x, dir.z)
	controlled.rotation.y = lerp_angle(controlled.rotation.y, target_yaw, clampf(delta * 14.0, 0.0, 1.0))


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


func _on_button_down(action: String) -> void:
	if goal_timer > 0.0 or controlled == null:
		return
	var has_ball := holder == controlled
	match action:
		"SWITCH":
			if not has_ball:
				_switch_player()
		"PASS":
			if has_ball:
				_kick_pass(false)
			else:
				_tackle()
		"LONG":
			if has_ball:
				_kick_pass(true)
		"SHOOT":
			if has_ball:
				_kick_shoot()


# ---------------------------------------------------------------- ball

func _forward(p: Player) -> Vector3:
	return Vector3(sin(p.rotation.y), 0.0, cos(p.rotation.y))


func _update_ball(delta: float) -> void:
	blocked_timer = maxf(blocked_timer - delta, 0.0)
	tackle_cd = maxf(tackle_cd - delta, 0.0)
	if goal_timer > 0.0:
		goal_timer -= delta
		_ball_physics(delta)
		# Ball rolls into the net and stops against the back.
		if absf(ball.position.z) > HALF_L + 1.9:
			ball.position.z = signf(ball.position.z) * (HALF_L + 1.9)
			ball_vel = ball_vel * 0.2
		if goal_timer <= 0.0:
			_kickoff()
		return
	if holder != null:
		ball.position = holder.position + _forward(holder) * 0.9 + Vector3(0, BALL_R, 0)
		ball_vel = Vector3.ZERO
		hold_time += delta
		if holder.team_id == 1 and hold_time > 6.0:
			_opponent_clear()   # safety net if the AI ever gets stuck
		return
	_ball_physics(delta)
	_try_pickup()
	_check_goal()


func _ball_physics(delta: float) -> void:
	ball_vel.y -= GRAVITY * delta
	ball.position += ball_vel * delta
	if ball.position.y <= BALL_R:
		ball.position.y = BALL_R
		if ball_vel.y < 0.0:
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
	if ball.position.y > 1.3:
		return
	var speed := Vector2(ball_vel.x, ball_vel.z).length()
	var best: Player = null
	var best_d := INF
	for p in players:
		if p == blocked_player and blocked_timer > 0.0:
			continue
		var is_gk := p.role == "GK"
		if speed > (40.0 if is_gk else 16.0):
			continue
		var opp_gk_reach: float = [1.3, 1.7, 2.1][Global.difficulty]
		var reach := 1.25
		if is_gk:
			reach = opp_gk_reach if p.team_id == 1 else 1.9
		var d := Vector2(p.position.x - ball.position.x, p.position.z - ball.position.z).length()
		if d < reach and d < best_d:
			best_d = d
			best = p
	if best != null:
		holder = best
		hold_time = 0.0
		if best.team_id == 0:
			controlled = best


func _check_goal() -> void:
	var p := ball.position
	if absf(p.z) >= HALF_L:
		if absf(p.x) < GOAL_W / 2.0 and p.y < GOAL_H:
			var scorer := 0 if p.z < 0.0 else 1
			score[scorer] += 1
			goal_timer = 2.5
			_update_score_ui(true)
			return
		# Missed the goal mouth / hit post or bar: rebound.
		p.z = signf(p.z) * (HALF_L - 0.05)
		ball_vel.z = -ball_vel.z * 0.5
		ball.position = p
	if absf(p.x) > HALF_W + 1.5:
		p.x = signf(p.x) * (HALF_W + 1.5)
		ball_vel.x = -ball_vel.x * 0.5
		ball.position = p


func _kickoff() -> void:
	for p in players:
		p.position = p.home_pos
	holder = null
	ball.position = Vector3(0, BALL_R, 0)
	ball_vel = Vector3.ZERO
	controlled = _nearest_player(0)
	_update_score_ui(false)


func _opponent_clear() -> void:
	# Placeholder until the Phase 5 AI: opponents just boot the ball upfield.
	var p := holder
	holder = null
	var dir := Vector3(randf_range(-0.5, 0.5), 0.0, 1.0).normalized()
	ball_vel = dir * 16.0 + Vector3(0, 4.0, 0)
	blocked_player = p
	blocked_timer = 0.6


func _release_ball(kicker: Player) -> void:
	holder = null
	blocked_player = kicker
	blocked_timer = 0.4


func _kick_pass(lofted: bool) -> void:
	var me := controlled
	var dir := _forward(me)
	if controls.move != Vector2.ZERO:
		dir = Vector3(controls.move.x, 0.0, controls.move.y).normalized()
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
	_release_ball(me)
	if lofted:
		ball_vel = flat_dir * clampf(dist_t / 0.8, 10.0, 32.0) + Vector3(0, 9.0, 0)
	else:
		var spd := clampf(dist_t * 1.5 + 7.0, 10.0, 26.0) * (0.85 + float(me.pass_stat) / 500.0)
		ball_vel = flat_dir * spd


func _kick_shoot() -> void:
	var me := controlled
	var aim_x := randf_range(-2.8, 2.8)
	if absf(controls.move.x) > 0.2:
		aim_x = controls.move.x * 3.0
	var to_goal := Vector3(aim_x, 0.0, -HALF_L) - me.position
	to_goal.y = 0.0
	var dist := to_goal.length()
	var dir := to_goal.normalized()
	dir.x += randf_range(-0.04, 0.04) * dist / 10.0
	dir = dir.normalized()
	_release_ball(me)
	ball_vel = dir * (24.0 + float(me.shoot_stat) * 0.12) + Vector3(0, 1.5 + randf() * 2.0, 0)


func _tackle() -> void:
	if holder == null or holder.team_id != 1 or tackle_cd > 0.0:
		return
	if holder.position.distance_to(controlled.position) > 2.4:
		return
	tackle_cd = 0.6
	if randf() < 0.7:
		blocked_player = holder
		blocked_timer = 0.8
		holder = controlled
		hold_time = 0.0


func _update_score_ui(goal: bool) -> void:
	if score_label != null:
		score_label.text = "%s  %d - %d  %s" % [Global.TEAMS[team_a]["name"], score[0], score[1], Global.TEAMS[team_b]["name"]]
	if goal_label != null:
		goal_label.visible = goal


# ---------------------------------------------------------------- AI

func _update_ai(delta: float) -> void:
	if goal_timer > 0.0:
		return
	var diff := Global.difficulty
	var spd_mult: float = [0.75, 0.9, 1.05][diff]
	var react: float = [0.9, 0.55, 0.3][diff]
	for p in players:
		p.ai_cd = maxf(p.ai_cd - delta, 0.0)
	for team_id in 2:
		var chaser := _chaser(team_id)
		var has_ball := holder != null and holder.team_id == team_id
		for p in players:
			if p.team_id != team_id or p == controlled:
				continue
			var mult := spd_mult if team_id == 1 else 0.95
			if p.role == "GK":
				mult = 1.3
			if p == holder:
				_ai_with_ball(p, react, mult, delta)
				continue
			_move_toward(p, _ai_target(p, chaser, has_ball), mult, delta)
			if p == chaser and holder != null and holder.team_id != team_id:
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


func _ai_target(p: Player, chaser: Player, has_ball: bool) -> Vector3:
	if p.role == "GK":
		var gz := HALF_L if p.team_id == 0 else -HALF_L
		var out := clampf((22.0 - absf(ball.position.z - gz)) / 22.0, 0.0, 1.0) * 4.0
		return Vector3(clampf(ball.position.x * 0.45, -3.4, 3.4), 0.0, gz - signf(gz) * (1.5 + out))
	if p == chaser:
		if holder != null:
			return holder.position
		return ball.position + Vector3(ball_vel.x, 0.0, ball_vel.z) * 0.25
	var atk := -1.0 if p.team_id == 0 else 1.0
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
	if p.role == "DEF":
		if p.team_id == 0:
			t.z = maxf(t.z, -4.0)
		else:
			t.z = minf(t.z, 4.0)
	return t


func _move_toward(p: Player, target: Vector3, mult: float, delta: float) -> void:
	var to := target - p.position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.4:
		return
	var spd := (4.5 + 0.03 * float(p.speed_stat)) * mult
	if dist > 12.0:
		spd *= 1.25
	var dir := to / dist
	p.position += dir * minf(spd * delta, dist)
	p.rotation.y = lerp_angle(p.rotation.y, atan2(dir.x, dir.z), clampf(delta * 10.0, 0.0, 1.0))


func _ai_try_tackle(p: Player, diff: int) -> void:
	if holder == null or holder.team_id == p.team_id or p.ai_cd > 0.0:
		return
	if p.position.distance_to(holder.position) > 1.9 or hold_time < 0.5:
		return
	p.ai_cd = 1.0
	var chance: float = [0.2, 0.35, 0.5][diff]
	if p.team_id == 0:
		chance = 0.6   # teammates help the human
	if randf() < chance:
		blocked_player = holder
		blocked_timer = 0.8
		holder = p
		hold_time = 0.0
		if p.team_id == 0:
			controlled = p


func _nearest_enemy_dist(pos: Vector3, team_id: int) -> float:
	var best := INF
	for q in players:
		if q.team_id == team_id:
			continue
		best = minf(best, Vector2(q.position.x - pos.x, q.position.z - pos.z).length())
	return best


func _ai_with_ball(p: Player, react: float, mult: float, delta: float) -> void:
	var atk := 1.0 if p.team_id == 1 else -1.0
	var gz := atk * HALF_L
	if p.role == "GK":
		if hold_time > react + 0.6:
			_ai_pass(p, true)
		return
	var dist_goal := Vector2(p.position.x, p.position.z - gz).length()
	if hold_time > react:
		if dist_goal < 25.0:
			_ai_shoot(p)
			return
		if _nearest_enemy_dist(p.position, p.team_id) < 4.0 or hold_time > 3.5:
			if _ai_pass(p, false):
				return
	_move_toward(p, Vector3(p.position.x * 0.8, 0.0, gz), mult * 0.85, delta)


func _ai_pass(p: Player, lofted: bool) -> bool:
	var atk := 1.0 if p.team_id == 1 else -1.0
	var best: Player = null
	var best_s := -INF
	for t in players:
		if t.team_id != p.team_id or t == p or t.role == "GK":
			continue
		var to := t.position - p.position
		to.y = 0.0
		var d := to.length()
		if d < 5.0 or d > 40.0:
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
	_release_ball(p)
	if lofted or d2 > 28.0:
		ball_vel = flat * clampf(d2 / 0.8, 10.0, 32.0) + Vector3(0, 9.0, 0)
	else:
		ball_vel = flat * clampf(d2 * 1.5 + 7.0, 10.0, 26.0) * (0.85 + float(p.pass_stat) / 500.0)
	return true


func _ai_shoot(p: Player) -> void:
	var gz := HALF_L if p.team_id == 1 else -HALF_L
	var err: float = [0.1, 0.06, 0.035][Global.difficulty]
	var to := Vector3(randf_range(-3.0, 3.0), 0.0, gz) - p.position
	to.y = 0.0
	var dir := to.normalized().rotated(Vector3.UP, randf_range(-err, err) * (1.0 + to.length() / 15.0))
	_release_ball(p)
	ball_vel = dir * (22.0 + float(p.shoot_stat) * 0.12) + Vector3(0, 1.5 + randf() * 1.5, 0)


func _build_controls() -> void:
	controls = TouchControls.new()
	add_child(controls)
	controls.button_down.connect(_on_button_down)
	controlled = _nearest_player(0)
	indicator = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.4
	cm.bottom_radius = 0.0
	cm.height = 0.7
	cm.radial_segments = 4
	indicator.mesh = cm
	var im := StandardMaterial3D.new()
	im.albedo_color = Color("ffd60a")
	im.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	indicator.material_override = im
	add_child(indicator)


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
	l.text = "%s vs %s   (Phase 5)" % [Global.TEAMS[team_a]["name"], Global.TEAMS[team_b]["name"]]
	l.position = Vector2(220, 36)
	l.add_theme_font_size_override("font_size", 28)
	layer.add_child(l)

	score_label = Label.new()
	score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	score_label.position.y = 96.0
	score_label.add_theme_font_size_override("font_size", 40)
	score_label.add_theme_color_override("font_outline_color", Color.BLACK)
	score_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(score_label)

	goal_label = Label.new()
	goal_label.text = "GOAL!"
	goal_label.set_anchors_preset(Control.PRESET_CENTER)
	goal_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	goal_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	goal_label.add_theme_font_size_override("font_size", 120)
	goal_label.add_theme_color_override("font_color", Color("ffd60a"))
	goal_label.add_theme_color_override("font_outline_color", Color("b00020"))
	goal_label.add_theme_constant_override("outline_size", 16)
	goal_label.visible = false
	layer.add_child(goal_label)
	_update_score_ui(false)
