extends Control
## Main menu built entirely in code (no external assets).

var _bg: ColorRect
var _panel_holder: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_panel_holder = Control.new()
	_panel_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel_holder)
	_show_main()


func _build_background() -> void:
	_bg = ColorRect.new()
	_bg.color = Color("07122b")
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	# Night pitch strip at the bottom
	var pitch := ColorRect.new()
	pitch.color = Color("145a24")
	pitch.anchor_left = 0.0
	pitch.anchor_right = 1.0
	pitch.anchor_top = 0.72
	pitch.anchor_bottom = 1.0
	add_child(pitch)
	# Floodlight glow
	for x in [0.12, 0.88]:
		var glow := ColorRect.new()
		glow.color = Color(1, 1, 0.8, 0.12)
		glow.anchor_left = x - 0.05
		glow.anchor_right = x + 0.05
		glow.anchor_top = 0.0
		glow.anchor_bottom = 0.72
		add_child(glow)


func _clear() -> void:
	for c in _panel_holder.get_children():
		c.queue_free()


func _center_box(width: float = 520.0) -> VBoxContainer:
	_clear()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_holder.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	return box


func _title(text: String, size: int = 72) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("ffd60a"))
	l.add_theme_color_override("font_outline_color", Color("b00020"))
	l.add_theme_constant_override("outline_size", 10)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 84)
	b.add_theme_font_size_override("font_size", 36)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1d4ed8")
	sb.border_color = Color("ffd60a")
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(10)
	b.add_theme_stylebox_override("normal", sb)
	var sbp := sb.duplicate()
	sbp.bg_color = Color("e63946")
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("hover", sbp)
	b.pressed.connect(cb)
	return b


func _show_main() -> void:
	var box := _center_box()
	box.add_child(_title("LEGEND"))
	var sub := _title("FOOTBALL", 56)
	box.add_child(sub)
	box.add_child(_button(Global.t("PLAY"), _on_play))
	box.add_child(_button(Global.t("TEAMS"), _show_teams))
	box.add_child(_button(Global.t("SETTINGS"), _show_settings))
	box.add_child(_button(Global.t("ABOUT"), _show_about))


func _on_play() -> void:
	Global.save_data()
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _show_teams() -> void:
	var box := _center_box(640)
	box.add_child(_title(Global.t("TEAMS"), 48))
	for i in Global.TEAMS.size():
		var tm: Dictionary = Global.TEAMS[i]
		var b := _button(tm["name"] + ("  ✔" if i == Global.team_index else ""), _pick_team.bind(i))
		b.custom_minimum_size = Vector2(0, 64)
		b.add_theme_font_size_override("font_size", 28)
		var sb := StyleBoxFlat.new()
		sb.bg_color = tm["c1"]
		sb.border_color = tm["c2"]
		sb.set_border_width_all(5)
		sb.set_corner_radius_all(10)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_color_override("font_color", tm["c2"])
		box.add_child(b)
	box.add_child(_button(Global.t("BACK"), _show_main))


func _pick_team(i: int) -> void:
	Global.team_index = i
	Global.save_data()
	_show_teams()


func _show_settings() -> void:
	var box := _center_box(640)
	box.add_child(_title(Global.t("SETTINGS"), 48))
	box.add_child(_button("%s: %s" % [Global.t("LANGUAGE"), "العربية" if Global.language == "ar" else "English"], _cycle_lang))
	var diffs := ["Easy", "Normal", "Hard"]
	box.add_child(_button("%s: %s" % [Global.t("DIFFICULTY"), Global.t(diffs[Global.difficulty])], _cycle_diff))
	var quals := ["Low", "Medium", "High"]
	box.add_child(_button("%s: %s" % [Global.t("QUALITY"), Global.t(quals[Global.quality])], _cycle_quality))
	box.add_child(_button("%s: %d %s" % [Global.t("MATCH LENGTH"), Global.match_minutes, Global.t("min")], _cycle_minutes))
	box.add_child(_button("%s: %s" % [Global.t("SOUND"), Global.t("ON" if Global.sound_on else "OFF")], _toggle_sound))
	box.add_child(_button(Global.t("BACK"), _show_main))


func _cycle_lang() -> void:
	Global.language = "ar" if Global.language == "en" else "en"
	Global.save_data()
	_show_settings()


func _cycle_diff() -> void:
	Global.difficulty = (Global.difficulty + 1) % 3
	Global.save_data()
	_show_settings()


func _cycle_quality() -> void:
	Global.quality = (Global.quality + 1) % 3
	Global.apply_quality()
	Global.save_data()
	_show_settings()


func _cycle_minutes() -> void:
	var opts := [1, 2, 3, 5, 10]
	var i := opts.find(Global.match_minutes)
	Global.match_minutes = opts[(i + 1) % opts.size()]
	Global.save_data()
	_show_settings()


func _toggle_sound() -> void:
	Global.sound_on = not Global.sound_on
	Global.save_data()
	_show_settings()


func _show_about() -> void:
	var box := _center_box(700)
	box.add_child(_title(Global.t("ABOUT"), 48))
	var l := Label.new()
	l.text = Global.t("ABOUT_TEXT")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 30)
	box.add_child(l)
	box.add_child(_button(Global.t("BACK"), _show_main))
