class_name Hud
extends CanvasLayer
## Match HUD: score bar, clock, player cards, mini-map, banners,
## and the intro / full-time / pause overlays. Original design, built in code.

signal start_pressed
signal replay_pressed
signal menu_pressed

const TAGS := {
	"GK": ["GK", Color("e8920a")],
	"DEF": ["DF", Color("2f6fe0")],
	"MID": ["MF", Color("2faa4a")],
	"FWD": ["FW", Color("d62828")],
}

var _root: Control
var _score_l: Label
var _clock_l: Label
var _msg: Label
var _sub: Label
var _msg_t := 0.0
var _card_l := {}
var _card_r := {}
var _map: MiniMap
var _intro: Control
var _full: Control
var _full_score: Label
var _full_stats: Label
var _pause: Control


class MiniMap extends Control:
	var dots_a := PackedVector2Array()
	var dots_b := PackedVector2Array()
	var ball := Vector2(0.5, 0.5)
	var hi := Vector2(-1, -1)
	var col_a := Color("27e0ff")
	var col_b := Color("ff4d4d")

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.32, 0.12, 0.7))
		var line := Color(1, 1, 1, 0.85)
		draw_rect(Rect2(Vector2.ZERO, size), line, false, 2.0)
		draw_line(Vector2(size.x * 0.5, 0), Vector2(size.x * 0.5, size.y), line, 1.5)
		draw_arc(size * 0.5, size.y * 0.15, 0.0, TAU, 24, line, 1.5)
		draw_rect(Rect2(0, size.y * 0.2, size.x * 0.16, size.y * 0.6), line, false, 1.5)
		draw_rect(Rect2(size.x * 0.84, size.y * 0.2, size.x * 0.16, size.y * 0.6), line, false, 1.5)
		for d in dots_a:
			draw_circle(d * size, 4.0, col_a)
		for d in dots_b:
			draw_circle(d * size, 4.0, col_b)
		if hi.x >= 0.0:
			draw_arc(hi * size, 7.0, 0.0, TAU, 16, Color("ffd60a"), 2.0)
		draw_circle(ball * size, 3.0, Color.WHITE)
		draw_arc(ball * size, 3.0, 0.0, TAU, 10, Color.BLACK, 1.0)


func setup(name_a: String, code_a: String, kit_a: Array, name_b: String, code_b: String, kit_b: Array) -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.offset_top = 34.0   # keep clear of the phone status bar
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_score(name_a, kit_a, name_b, kit_b)
	_build_clock()
	_card_l = _build_card(false, 74.0)
	_card_r = _build_card(true, 74.0)
	_build_map()
	_build_banner()
	_build_pause_button()
	_build_intro(name_a, kit_a, name_b, kit_b)
	_build_full()
	_build_pause()


# ------------------------------------------------------------ helpers

func _style(bg: Color, border: Color, radius: int = 8, bw: int = 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _label(text: String, size: int, color: Color = Color.WHITE, outline: int = 6) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _swatch(kit: Array, w: float = 30.0) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(w, 30)
	p.add_theme_stylebox_override("panel", _style(kit[0], kit[1], 4, 4))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _button(text: String, cb: Callable, w: float = 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 80)
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_stylebox_override("normal", _style(Color("1d4ed8"), Color("ffd60a"), 10, 4))
	b.add_theme_stylebox_override("hover", _style(Color("e63946"), Color("ffd60a"), 10, 4))
	b.add_theme_stylebox_override("pressed", _style(Color("e63946"), Color("ffd60a"), 10, 4))
	b.pressed.connect(cb)
	return b


# ------------------------------------------------------------ top bars

func _build_score(code_a: String, kit_a: Array, code_b: String, kit_b: Array) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Color(0.02, 0.05, 0.14, 0.85), Color("ffd60a")))
	p.position = Vector2(16, 12)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	h.add_child(_swatch(kit_a))
	h.add_child(_label(code_a, 24, Color("27e0ff")))
	_score_l = _label("0 - 0", 38, Color("ffd60a"), 8)
	h.add_child(_score_l)
	h.add_child(_label(code_b, 24, Color("ff7b7b")))
	h.add_child(_swatch(kit_b))


func _build_clock() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Color(0.02, 0.05, 0.14, 0.85), Color("ffd60a")))
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.offset_left = -16.0
	p.offset_right = -16.0
	p.offset_top = 12.0
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(p)
	_clock_l = _label("1ST  00:00", 36, Color("ffd60a"), 8)
	p.add_child(_clock_l)


func _build_pause_button() -> void:
	var b := Button.new()
	b.text = "II"
	b.custom_minimum_size = Vector2(76, 64)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_stylebox_override("normal", _style(Color(0.02, 0.05, 0.14, 0.8), Color.WHITE, 8, 3))
	b.add_theme_stylebox_override("pressed", _style(Color("e63946"), Color.WHITE, 8, 3))
	b.anchor_left = 0.5
	b.anchor_right = 0.5
	b.grow_horizontal = Control.GROW_DIRECTION_BOTH
	b.offset_top = 12.0
	b.pressed.connect(func(): _set_pause(true))
	_root.add_child(b)


func _build_card(right: bool, top: float) -> Dictionary:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Color(0.02, 0.05, 0.14, 0.8), Color(1, 1, 1, 0.6), 6, 2))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if right:
		p.anchor_left = 1.0
		p.anchor_right = 1.0
		p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		p.offset_left = -16.0
		p.offset_right = -16.0
	else:
		p.position.x = 16.0
	p.offset_top = top
	_root.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	var tag_panel := PanelContainer.new()
	tag_panel.add_theme_stylebox_override("panel", _style(Color("d62828"), Color.WHITE, 4, 2))
	h.add_child(tag_panel)
	var tag := _label("FW", 22)
	tag_panel.add_child(tag)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var nm := _label("", 24, Color.WHITE, 5)
	nm.custom_minimum_size = Vector2(200, 0)
	v.add_child(nm)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(200, 10)
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("2a7bff")
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bar)
	p.visible = false
	return {"panel": p, "tag_panel": tag_panel, "tag": tag, "name": nm, "bar": bar}


func _build_map() -> void:
	_map = MiniMap.new()
	_map.custom_minimum_size = Vector2(200, 118)
	_map.anchor_left = 0.5
	_map.anchor_right = 0.5
	_map.anchor_top = 1.0
	_map.anchor_bottom = 1.0
	_map.offset_left = -100.0
	_map.offset_right = 100.0
	_map.offset_top = -130.0
	_map.offset_bottom = -12.0
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_map)


func _build_banner() -> void:
	_msg = _label("", 56, Color("ffd60a"), 12)
	_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_msg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_msg.offset_top = 150.0
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.visible = false
	_root.add_child(_msg)
	_sub = _label("", 32, Color.WHITE, 8)
	_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub.offset_top = 225.0
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.visible = false
	_root.add_child(_sub)


# ------------------------------------------------------------ overlays

func _overlay() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.03, 0.1, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(dim)
	c.visible = false
	_root.add_child(c)
	return c


func _centered(parent: Control, sep: int = 16) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(cc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	cc.add_child(v)
	return v


func _centered_label(text: String, size: int, color: Color) -> Label:
	var l := _label(text, size, color, 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _build_intro(name_a: String, kit_a: Array, name_b: String, kit_b: Array) -> void:
	_intro = _overlay()
	var v := _centered(_intro, 18)
	v.add_child(_centered_label("LEGEND FOOTBALL", 70, Color("ffd60a")))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.add_child(_swatch(kit_a, 44))
	row.add_child(_label(name_a, 44, Color("27e0ff")))
	row.add_child(_label("VS", 38, Color("ffd60a")))
	row.add_child(_label(name_b, 44, Color("ff7b7b")))
	row.add_child(_swatch(kit_b, 44))
	v.add_child(row)
	var b := _button("KICK OFF", func(): start_pressed.emit(), 420.0)
	v.add_child(b)


func _build_full() -> void:
	_full = _overlay()
	var v := _centered(_full, 14)
	v.add_child(_centered_label("FULL TIME", 64, Color("ffd60a")))
	_full_score = _centered_label("", 56, Color.WHITE)
	v.add_child(_full_score)
	_full_stats = _label("", 26, Color.WHITE, 4)
	_full_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_full_stats)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	row.add_child(_button("REPLAY", func(): replay_pressed.emit(), 280.0))
	row.add_child(_button("MENU", func(): menu_pressed.emit(), 280.0))
	v.add_child(row)


func _build_pause() -> void:
	_pause = _overlay()
	var v := _centered(_pause, 18)
	v.add_child(_centered_label("PAUSED", 64, Color("ffd60a")))
	v.add_child(_button("RESUME", func(): _set_pause(false), 360.0))
	v.add_child(_button("RESTART", func(): replay_pressed.emit(), 360.0))
	v.add_child(_button("MENU", func(): menu_pressed.emit(), 360.0))


func _set_pause(on: bool) -> void:
	_pause.visible = on
	get_tree().paused = on


# ------------------------------------------------------------ public API

func show_intro() -> void:
	_intro.visible = true


func hide_intro() -> void:
	_intro.visible = false


func show_fulltime(name_a: String, name_b: String, sa: int, sb: int, stats_text: String) -> void:
	_full_score.text = "%s  %d - %d  %s" % [name_a, sa, sb, name_b]
	_full_stats.text = stats_text
	_full.visible = true


func set_score(a: int, b: int) -> void:
	_score_l.text = "%d - %d" % [a, b]


func set_clock(text: String) -> void:
	_clock_l.text = text


func set_card(right: bool, role: String, player_name: String, stamina: float, show_bar: bool = true) -> void:
	var c: Dictionary = _card_r if right else _card_l
	var tag_info: Array = TAGS.get(role, TAGS["MID"])
	(c["panel"] as Control).visible = true
	if c.get("role", "") != role:
		c["role"] = role
		(c["tag"] as Label).text = tag_info[0]
		(c["tag_panel"] as PanelContainer).add_theme_stylebox_override("panel", _style(tag_info[1], Color.WHITE, 4, 2))
	(c["name"] as Label).text = player_name
	var bar: ProgressBar = c["bar"]
	bar.visible = show_bar
	bar.value = stamina


func update_map(a: PackedVector2Array, b: PackedVector2Array, ball_pos: Vector2, hi: Vector2) -> void:
	_map.dots_a = a
	_map.dots_b = b
	_map.ball = ball_pos
	_map.hi = hi
	_map.queue_redraw()


func message(text: String, secs: float = 2.0, big: bool = false, sub: String = "") -> void:
	_msg.text = text
	_msg.add_theme_font_size_override("font_size", 110 if big else 56)
	_msg.visible = true
	_sub.text = sub
	_sub.visible = sub != ""
	_msg_t = secs


func _process(delta: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			_msg.visible = false
			_sub.visible = false
