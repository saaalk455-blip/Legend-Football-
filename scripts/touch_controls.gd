class_name TouchControls
extends CanvasLayer
## Floating virtual stick (left half of screen) + action buttons (right).
## Handles raw multi-touch so stick and buttons work at the same time.
## Works with the mouse on desktop (emulate_touch_from_mouse is on).

signal button_down(action: String)
signal button_up(action: String)

const STICK_R := 110.0
const DEADZONE := 0.15

var move := Vector2.ZERO
var edit_mode := false               # layout editor: buttons are dragged, stick off
var held := {}                       # action -> bool

var _stick_touch := -1
var _stick_center := Vector2.ZERO
var _base: Panel
var _knob: Panel
var _btn_nodes := {}                 # action -> Panel
var _btn_pos := {}                   # action -> Vector2 (centre)
var _btn_rad := {}                   # action -> float
var _touch_action := {}              # touch index -> action
var _labels := {}                    # action -> Label
var _drag_action := {}               # touch index -> action (edit mode)


func set_label(action: String, text: String) -> void:
	if _labels.has(action):
		var l: Label = _labels[action]
		if l.text != text:
			l.text = text

const ACTIONS := {
	"SHOOT": {"r": 80.0, "color": Color("e63946")},
	"PASS": {"r": 68.0, "color": Color("2a9d3f")},
	"LONG": {"r": 58.0, "color": Color("2a6fdb")},
	"SWITCH": {"r": 58.0, "color": Color("f4a100")},
	"RUN": {"r": 58.0, "color": Color("8a4fd6")},
}


func _ready() -> void:
	layer = 10
	_base = _circle(STICK_R, Color(1, 1, 1, 0.15), Color(1, 1, 1, 0.5))
	_knob = _circle(46.0, Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.9))
	_base.visible = false
	_knob.visible = false
	for a in ACTIONS:
		var info: Dictionary = ACTIONS[a]
		var col: Color = info["color"]
		var rad: float = float(info["r"]) * Global.btn_scale
		var n := _circle(rad, Color(col.r, col.g, col.b, Global.btn_opacity), Color(1, 1, 1, clampf(Global.btn_opacity + 0.3, 0.0, 1.0)))
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
		held[a] = false
	get_viewport().size_changed.connect(_layout)
	_layout()


func _circle(radius: float, fill: Color, border: Color) -> Panel:
	var p := Panel.new()
	p.size = Vector2(radius * 2.0, radius * 2.0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(int(radius))
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	_btn_pos = _default_positions(s)
	for a in _btn_nodes:
		var off: Vector2 = Global.btn_offsets.get(a, Vector2.ZERO)
		var r: float = _btn_rad[a]
		var c: Vector2 = _btn_pos[a] + off
		c.x = clampf(c.x, r, s.x - r)
		c.y = clampf(c.y, r, s.y - r)
		_btn_pos[a] = c
		var n: Panel = _btn_nodes[a]
		n.position = c - n.size / 2.0


## Edit mode: put every button back at its default place.
func reset_layout() -> void:
	Global.btn_offsets = {}
	_layout()


## Edit mode: store the dragged positions as offsets from the defaults.
func save_layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var defaults := _default_positions(s)
	var offs := {}
	for a in _btn_pos:
		offs[a] = _btn_pos[a] - defaults[a]
	Global.btn_offsets = offs
	Global.save_data()


func _default_positions(s: Vector2) -> Dictionary:
	return {
		"SHOOT": Vector2(s.x - 150.0, s.y - 160.0),
		"PASS": Vector2(s.x - 320.0, s.y - 110.0),
		"LONG": Vector2(s.x - 330.0, s.y - 260.0),
		"SWITCH": Vector2(s.x - 170.0, s.y - 320.0),
		"RUN": Vector2(s.x - 470.0, s.y - 105.0),
	}


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_touch_down(e.index, e.position)
		else:
			_touch_up(e.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if edit_mode:
			if _drag_action.has(d.index):
				var a: String = _drag_action[d.index]
				var r: float = _btn_rad[a]
				var s := get_viewport().get_visible_rect().size
				var c := Vector2(clampf(d.position.x, r, s.x - r), clampf(d.position.y, r, s.y - r))
				_btn_pos[a] = c
				(_btn_nodes[a] as Panel).position = c - Vector2(r, r)
			return
		if d.index == _stick_touch:
			_update_stick(d.position)


func _touch_down(index: int, pos: Vector2) -> void:
	if edit_mode:
		for a in _btn_pos:
			if pos.distance_to(_btn_pos[a]) <= float(_btn_rad[a]) + 12.0:
				_drag_action[index] = a
				return
		return
	for a in _btn_pos:
		var c: Vector2 = _btn_pos[a]
		if pos.distance_to(c) <= float(_btn_rad[a]) + 12.0:
			_touch_action[index] = a
			_set_button(a, true)
			return
	var s := get_viewport().get_visible_rect().size
	if _stick_touch == -1 and pos.x < s.x * 0.5 and pos.y > s.y * 0.2:
		_stick_touch = index
		_stick_center = pos
		_base.position = pos - _base.size / 2.0
		_knob.position = pos - _knob.size / 2.0
		_base.visible = true
		_knob.visible = true
		move = Vector2.ZERO


func _touch_up(index: int) -> void:
	_drag_action.erase(index)
	if _touch_action.has(index):
		_set_button(_touch_action[index], false)
		_touch_action.erase(index)
	if index == _stick_touch:
		_stick_touch = -1
		move = Vector2.ZERO
		_base.visible = false
		_knob.visible = false


func _update_stick(pos: Vector2) -> void:
	var v := pos - _stick_center
	if v.length() > STICK_R:
		v = v.normalized() * STICK_R
	_knob.position = _stick_center + v - _knob.size / 2.0
	var m := v / STICK_R
	move = Vector2.ZERO if m.length() < DEADZONE else m


func _set_button(a: String, down: bool) -> void:
	held[a] = down
	var n: Panel = _btn_nodes[a]
	n.modulate = Color(1.4, 1.4, 1.4, 1.0) if down else Color.WHITE
	if down:
		button_down.emit(a)
	else:
		button_up.emit(a)
