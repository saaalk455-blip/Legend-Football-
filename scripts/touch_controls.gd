class_name TouchControls
extends CanvasLayer
## Floating virtual stick (left side) + action buttons (right side).
##
## Raw multi-touch: every finger is bound to ONE control when it goes down
## (a button or the stick) and keeps that binding until it lifts, so fingers
## never "slide" from one control to another and several fingers work at once.
##
## Public API used by the rest of the game (unchanged):
##   signals button_down / button_up, vars move / held, set_label()
## Added: hold_time(), release_all(), run_selftest(), edit-mode helpers.

signal button_down(action: String)
signal button_up(action: String)

const STICK_R := 110.0          # stick travel in virtual pixels (divided by sensitivity)
const DEADZONE := 0.12
const SNAP := 0.92              # above this the stick counts as fully pushed
const HIT_MARGIN := 10.0
const STICK_ZONE := 0.45        # left 45 % of the screen starts the stick
const STICK_TOP := 0.2          # top 20 % is reserved for the HUD (pause button)

## Console-style cluster for the right thumb: SHOOT is the big main button,
## PASS sits next to it, LONG above, SWITCH further out, RUN to the left.
## "off" is the centre relative to the bottom-right corner at scale 1.0.
const ACTIONS := {
	"SHOOT": {"r": 84.0, "color": Color("e63946"), "off": Vector2(-130.0, -150.0)},
	"PASS": {"r": 72.0, "color": Color("2a9d3f"), "off": Vector2(-305.0, -100.0)},
	"LONG": {"r": 62.0, "color": Color("2a6fdb"), "off": Vector2(-205.0, -300.0)},
	"SWITCH": {"r": 56.0, "color": Color("f4a100"), "off": Vector2(-360.0, -255.0)},
	"RUN": {"r": 66.0, "color": Color("8a4fd6"), "off": Vector2(-470.0, -95.0)},
}
const HIDEABLE := ["SWITCH", "LONG"]

var move := Vector2.ZERO
var held := {}                       # action -> bool
var edit_mode := false               # layout editor: buttons are dragged, stick off

var _stick_touch := -1
var _stick_center := Vector2.ZERO
var _stick_r := STICK_R
var _base: Panel
var _knob: Panel
var _dir_mark: Polygon2D
var _btn_nodes := {}                 # action -> Panel
var _btn_pos := {}                   # action -> Vector2 (centre)
var _btn_rad := {}                   # action -> float
var _labels := {}                    # action -> Label
var _style_n := {}                   # action -> StyleBoxFlat (normal)
var _style_p := {}                   # action -> StyleBoxFlat (pressed)
var _style_on := {}                  # action -> bool (pressed style active)
var _vis := {}                       # action -> 0..1 press animation
var _touch_action := {}              # touch index -> action ("" = ignored finger)
var _drag_action := {}               # touch index -> action (edit mode)
var _down_ms := {}                   # action -> press start (ms)
var _down_count := {}                # counters, used by the self-test
var _up_count := {}
var _muted := false                  # self-test: count presses without emitting


func set_label(action: String, text: String) -> void:
	if _labels.has(action):
		var l: Label = _labels[action]
		if l.text != text:
			l.text = text


func hold_time(action: String) -> float:
	## Seconds the button has been held (0 when it is not down). Prepared for
	## shot charging in a later stage.
	if not held.get(action, false) or not _down_ms.has(action):
		return 0.0
	return float(Time.get_ticks_msec() - int(_down_ms[action])) / 1000.0


func _ready() -> void:
	layer = 10
	var sens := clampf(Global.stick_sens, 0.5, 2.0)
	_stick_r = STICK_R / sens
	_base = _circle(_stick_r, Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.5))
	_knob = _circle(46.0, Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.9))
	_base.visible = false
	_knob.visible = false
	_dir_mark = Polygon2D.new()
	_dir_mark.polygon = PackedVector2Array([Vector2(0, -15), Vector2(13, 11), Vector2(-13, 11)])
	_dir_mark.color = Color(1, 1, 1, 0.85)
	_dir_mark.visible = false
	add_child(_dir_mark)
	for a in ACTIONS:
		var info: Dictionary = ACTIONS[a]
		var col: Color = info["color"]
		var rad: float = float(info["r"]) * Global.btn_scale
		var n := _circle(rad, Color.TRANSPARENT, Color.TRANSPARENT)
		n.pivot_offset = n.size / 2.0
		var sn := _make_style(rad, col, Global.btn_opacity, 4, false)
		var sp := _make_style(rad, col, Global.btn_opacity, 8, true)
		n.add_theme_stylebox_override("panel", sn)
		_style_n[a] = sn
		_style_p[a] = sp
		_style_on[a] = false
		var l := Label.new()
		l.text = a
		l.add_theme_font_size_override("font_size", int(22.0 * Global.btn_scale))
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.add_child(l)
		_labels[a] = l
		_btn_nodes[a] = n
		_btn_rad[a] = rad
		_vis[a] = 0.0
		_down_count[a] = 0
		_up_count[a] = 0
		held[a] = false
	get_viewport().size_changed.connect(_layout)
	_layout()


func _notification(what: int) -> void:
	# A paused tree never delivers the finger-up events, so let go of
	# everything when the game pauses or the app loses focus.
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_all()


func _circle(radius: float, fill: Color, border: Color) -> Panel:
	var p := Panel.new()
	p.size = Vector2(radius * 2.0, radius * 2.0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _make_style(radius, fill, 1.0, 4, false)
	sb.bg_color = fill
	sb.border_color = border
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p


func _make_style(radius: float, col: Color, opacity: float, border_w: int, pressed: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var fill_a := clampf(opacity + (0.35 if pressed else 0.0), 0.0, 1.0)
	sb.bg_color = Color(col.r, col.g, col.b, fill_a)
	sb.border_color = Color(1, 1, 1, 1.0 if pressed else clampf(opacity + 0.3, 0.0, 1.0))
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(int(radius))
	return sb


# ------------------------------------------------------------ layout

func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size


## Default centres for a screen size and button scale. Offsets scale with the
## buttons so the gaps between them stay proportional.
static func default_positions(s: Vector2, sc: float) -> Dictionary:
	var out := {}
	for a in ACTIONS:
		var off: Vector2 = ACTIONS[a]["off"]
		out[a] = s + off * sc
	return out


func _layout() -> void:
	var s := _screen()
	var defs := default_positions(s, Global.btn_scale)
	for a in _btn_nodes:
		var off: Vector2 = Global.btn_offsets.get(a, Vector2.ZERO)
		var r: float = _btn_rad[a]
		var c: Vector2 = defs[a] + off
		c.x = clampf(c.x, r, s.x - r)
		c.y = clampf(c.y, r, s.y - r)
		_btn_pos[a] = c
		var n: Panel = _btn_nodes[a]
		n.position = c - n.size / 2.0
	_apply_visibility()


func _apply_visibility() -> void:
	for a in _btn_nodes:
		var n: Panel = _btn_nodes[a]
		n.visible = edit_mode or not _is_hidden(a)


func _is_hidden(a: String) -> bool:
	return a in HIDEABLE and bool(Global.btn_hidden.get(a, false))


## Edit mode: put every button back at its default place.
func reset_layout() -> void:
	Global.btn_offsets = {}
	_layout()


## Edit mode: store the dragged positions as offsets from the defaults.
func save_layout() -> void:
	var defs := default_positions(_screen(), Global.btn_scale)
	var offs := {}
	for a in _btn_pos:
		offs[a] = _btn_pos[a] - defs[a]
	Global.btn_offsets = offs
	Global.save_data()


# ------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed and not e.canceled:
			_touch_down(e.index, e.position)
		else:
			_touch_up(e.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touch_drag(d.index, d.position)


func _hit(pos: Vector2) -> String:
	## The button under the finger; if circles overlap the nearest centre wins.
	var best := ""
	var best_k := INF
	for a in _btn_pos:
		if not edit_mode and _is_hidden(a):
			continue
		var r: float = _btn_rad[a]
		var d := pos.distance_to(_btn_pos[a])
		if d <= r + HIT_MARGIN * Global.btn_scale:
			var k := d / r
			if k < best_k:
				best_k = k
				best = a
	return best


func _touch_down(index: int, pos: Vector2) -> void:
	if _touch_action.has(index) or _drag_action.has(index) or index == _stick_touch:
		return   # duplicate down for a finger we already track
	var a := _hit(pos)
	if edit_mode:
		if a != "":
			_drag_action[index] = a
		return
	if a != "":
		_press(a, index)
		return
	var s := _screen()
	if _stick_touch == -1 and pos.x < s.x * STICK_ZONE and pos.y > s.y * STICK_TOP:
		_stick_begin(index, pos)


func _touch_up(index: int) -> void:
	_drag_action.erase(index)
	if _touch_action.has(index):
		var a: String = _touch_action[index]
		_touch_action.erase(index)
		if a != "":
			_release(a)
	if index == _stick_touch:
		_stick_end()


func _touch_drag(index: int, pos: Vector2) -> void:
	if edit_mode:
		if _drag_action.has(index):
			var a: String = _drag_action[index]
			var r: float = _btn_rad[a]
			var s := _screen()
			var c := Vector2(clampf(pos.x, r, s.x - r), clampf(pos.y, r, s.y - r))
			_btn_pos[a] = c
			(_btn_nodes[a] as Panel).position = c - Vector2(r, r)
		return
	if index == _stick_touch:
		_update_stick(pos)


# ------------------------------------------------------------ buttons

func _press(a: String, index: int) -> void:
	if held.get(a, false):
		_touch_action[index] = ""   # a second finger on a pressed button is ignored
		return
	_touch_action[index] = a
	held[a] = true
	_down_ms[a] = Time.get_ticks_msec()
	_down_count[a] += 1
	if not _muted:
		button_down.emit(a)


func _release(a: String) -> void:
	if not held.get(a, false):
		return
	held[a] = false
	_up_count[a] += 1
	if not _muted:
		button_up.emit(a)


## Lets go of the stick and every button (pause, focus loss, cancelled touches).
func release_all() -> void:
	if _btn_nodes.is_empty():
		return
	_touch_action.clear()
	_drag_action.clear()
	for a in _btn_nodes:
		_release(a)
	_stick_end()


# ------------------------------------------------------------ stick

func _stick_begin(index: int, pos: Vector2) -> void:
	_stick_touch = index
	_stick_center = pos
	_base.position = pos - _base.size / 2.0
	_knob.position = pos - _knob.size / 2.0
	_base.visible = true
	_knob.visible = true
	move = Vector2.ZERO


func _stick_end() -> void:
	_stick_touch = -1
	move = Vector2.ZERO
	_base.visible = false
	_knob.visible = false
	_dir_mark.visible = false


func _update_stick(pos: Vector2) -> void:
	var v := pos - _stick_center
	var dist := v.length()
	if dist > _stick_r:
		# Finger ran past the edge: drag the stick centre along so the knob
		# stays inside its ring and a fast swipe never loses control.
		_stick_center += v / dist * (dist - _stick_r)
		_base.position = _stick_center - _base.size / 2.0
		v = pos - _stick_center
		dist = _stick_r
	_knob.position = _stick_center + v - _knob.size / 2.0
	var m := clampf((dist / _stick_r - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)
	if m >= SNAP:
		m = 1.0
	if m <= 0.0:
		move = Vector2.ZERO
		_dir_mark.visible = false
	else:
		var dir := v / dist
		move = dir * m
		_dir_mark.visible = true
		_dir_mark.position = _stick_center + dir * (_stick_r + 22.0)
		_dir_mark.rotation = dir.angle() + PI / 2.0


# ------------------------------------------------------------ feedback

func _process(delta: float) -> void:
	for a in _btn_nodes:
		var target := 1.0 if held.get(a, false) else 0.0
		var v: float = _vis[a]
		if v == target:
			continue
		v = move_toward(v, target, delta * 9.0)
		_vis[a] = v
		var n: Panel = _btn_nodes[a]
		n.scale = Vector2.ONE * (1.0 - 0.09 * v)
		n.modulate = Color(1.0 + 0.4 * v, 1.0 + 0.4 * v, 1.0 + 0.4 * v, 1.0)
		var on := v > 0.5
		if on != _style_on[a]:
			_style_on[a] = on
			n.add_theme_stylebox_override("panel", _style_p[a] if on else _style_n[a])
			(_labels[a] as Label).add_theme_color_override("font_color", Color("fff3a0") if on else Color.WHITE)


# ------------------------------------------------------------ CI self-test

func _ev_touch(i: int, p: Vector2, pressed: bool, cancelled: bool = false) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = p
	e.pressed = pressed
	e.canceled = cancelled
	_input(e)


func _ev_drag(i: int, p: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = i
	d.position = p
	_input(d)


## Feeds synthetic multi-touch events through the real input path and checks
## the behaviour. Prints SMOKE_TOUCH and TOUCH_FAIL lines (CI fails on the latter).
func run_selftest() -> void:
	var fails := PackedStringArray()
	var tests := 0
	var saved_hidden: Dictionary = Global.btn_hidden.duplicate()
	release_all()
	_muted = true
	var c := Vector2(200, 500)

	# 1. all eight directions, full push, then release
	for k in 8:
		var ang := k * PI / 4.0
		var dirv := Vector2(cos(ang), sin(ang))
		_ev_touch(0, c, true)
		_ev_drag(0, c + dirv * _stick_r)
		tests += 1
		if absf(move.length() - 1.0) > 0.02 or absf(move.angle_to(dirv)) > 0.03:
			fails.append("stick direction %d move=%s" % [k, move])
		_ev_touch(0, c, false)
		tests += 1
		if move != Vector2.ZERO or _base.visible:
			fails.append("stick release %d" % k)

	# 2. dead zone
	_ev_touch(0, c, true)
	_ev_drag(0, c + Vector2(5, 0))
	tests += 1
	if move != Vector2.ZERO:
		fails.append("dead zone move=%s" % move)

	# 3. fast swipe far outside the ring keeps the knob bounded and control kept
	_ev_drag(0, c + Vector2(3000, 0))
	var knob_off := (_knob.position + _knob.size / 2.0 - _stick_center).length()
	tests += 1
	if knob_off > _stick_r + 0.5 or move.length() > 1.001:
		fails.append("knob out of bounds off=%f" % knob_off)
	_ev_drag(0, c)
	tests += 1
	if move.x > -0.9:
		fails.append("lost control after fast swipe move=%s" % move)
	_ev_touch(0, c, false)

	# 4. stick + RUN + PASS at the same time
	_ev_touch(0, c, true)
	_ev_drag(0, c + Vector2(0, -_stick_r))
	_ev_touch(1, _btn_pos["RUN"], true)
	_ev_touch(2, _btn_pos["PASS"], true)
	tests += 1
	if not held["RUN"] or not held["PASS"] or move.y > -0.9:
		fails.append("multi-touch stick+RUN+PASS held=%s move=%s" % [held, move])
	if _down_count["PASS"] != 1 or _down_count["RUN"] != 1:
		fails.append("multi-touch press counts")
	_ev_touch(1, _btn_pos["RUN"], false)
	tests += 1
	if held["RUN"] or move.y > -0.9:
		fails.append("release RUN affected stick/other state")
	_ev_touch(2, _btn_pos["PASS"], false)
	_ev_touch(0, c, false)

	# 5. SHOOT while turning, SWITCH with the stick held
	_ev_touch(0, c, true)
	_ev_drag(0, c + Vector2(_stick_r, 0))
	_ev_touch(3, _btn_pos["SHOOT"], true)
	_ev_drag(0, c + Vector2(-_stick_r, 0))
	_ev_touch(4, _btn_pos["SWITCH"], true)
	tests += 1
	if not held["SHOOT"] or not held["SWITCH"] or move.x > -0.9:
		fails.append("SHOOT/SWITCH while steering")
	_ev_touch(3, _btn_pos["SHOOT"], false)
	_ev_touch(4, _btn_pos["SWITCH"], false)
	_ev_touch(0, c, false)

	# 6. two fingers on one button register once
	var shoot_down: int = _down_count["SHOOT"]
	var shoot_up: int = _up_count["SHOOT"]
	_ev_touch(5, _btn_pos["SHOOT"], true)
	_ev_touch(6, _btn_pos["SHOOT"], true)
	tests += 1
	if _down_count["SHOOT"] != shoot_down + 1:
		fails.append("double press registered twice")
	_ev_touch(5, _btn_pos["SHOOT"], false)
	_ev_touch(6, _btn_pos["SHOOT"], false)
	tests += 1
	if held["SHOOT"] or _up_count["SHOOT"] != shoot_up + 1:
		fails.append("button stuck or released twice")

	# 7. a finger sliding from PASS to SHOOT stays on PASS
	_ev_touch(7, _btn_pos["PASS"], true)
	_ev_drag(7, _btn_pos["SHOOT"])
	tests += 1
	if not held["PASS"] or held["SHOOT"]:
		fails.append("finger jumped between buttons")
	_ev_touch(7, _btn_pos["SHOOT"], false)
	tests += 1
	if held["PASS"] or held["SHOOT"]:
		fails.append("button stuck after lift")

	# 8. cancelled touch releases
	_ev_touch(8, _btn_pos["RUN"], true)
	_ev_touch(8, _btn_pos["RUN"], false, true)
	tests += 1
	if held["RUN"]:
		fails.append("cancelled touch left RUN down")

	# 9. release_all lets go of everything
	_ev_touch(0, c, true)
	_ev_drag(0, c + Vector2(_stick_r, 0))
	_ev_touch(9, _btn_pos["LONG"], true)
	release_all()
	tests += 1
	if held["LONG"] or move != Vector2.ZERO or _base.visible:
		fails.append("release_all incomplete")

	# 10. dead areas do not start anything
	var s := _screen()
	_ev_touch(10, Vector2(s.x * 0.5 + 40.0, s.y * 0.4), true)
	_ev_touch(11, Vector2(200, s.y * 0.1), true)
	tests += 1
	if _stick_touch != -1 or _base.visible:
		fails.append("stick started in a dead area")
	_ev_touch(10, Vector2.ZERO, false)
	_ev_touch(11, Vector2.ZERO, false)

	# 11. a hidden button cannot be pressed
	Global.btn_hidden = {"SWITCH": true}
	_apply_visibility()
	_ev_touch(12, _btn_pos["SWITCH"], true)
	tests += 1
	if held["SWITCH"]:
		fails.append("hidden SWITCH was pressed")
	_ev_touch(12, _btn_pos["SWITCH"], false)
	Global.btn_hidden = saved_hidden
	_apply_visibility()

	# 12. layout: no overlaps, everything on screen, clear of the stick zone
	for size in [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960), Vector2(1280, 1024)]:
		for sc in [0.8, 1.0, 1.2]:
			var pos := default_positions(size, sc)
			var keys: Array = pos.keys()
			for i in keys.size():
				var ri: float = float(ACTIONS[keys[i]]["r"]) * sc
				var pi_: Vector2 = pos[keys[i]]
				tests += 1
				if pi_.x - ri < size.x * STICK_ZONE + 20.0 or pi_.x + ri > size.x or pi_.y + ri > size.y or pi_.y - ri < size.y * STICK_TOP:
					fails.append("layout bounds %s %s scale %s" % [keys[i], size, sc])
				for j in range(i + 1, keys.size()):
					var rj: float = float(ACTIONS[keys[j]]["r"]) * sc
					if pi_.distance_to(pos[keys[j]]) < ri + rj + 10.0:
						fails.append("layout overlap %s/%s %s scale %s" % [keys[i], keys[j], size, sc])

	# clean up so the real match starts from a neutral state
	release_all()
	for a in ACTIONS:
		_down_count[a] = 0
		_up_count[a] = 0
		held[a] = false
	move = Vector2.ZERO
	_muted = false
	for f in fails:
		print("TOUCH_FAIL ", f)
	print("SMOKE_TOUCH tests=%d fails=%d" % [tests, fails.size()])
