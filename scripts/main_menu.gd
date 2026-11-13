extends Control
## Main menu built entirely in code (no external assets).

var _bg: ColorRect
var _panel_holder: Control
var _pick_opp := false


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


func _button(text: String, cb: Callable, height: float = 84.0, font_size: int = 36) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", font_size)
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
	_clear()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel_holder.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)
	outer.add_child(_title(Global.t("TEAMS"), 44))

	# Toggle between choosing your team and the opponent
	var mode := _button("%s  >  %s" % [Global.t("OPPONENT") if _pick_opp else Global.t("YOUR TEAM"), Global.TEAMS[Global.opp_index if _pick_opp else Global.team_index]["name"]], _toggle_pick)
	mode.custom_minimum_size = Vector2(0, 64)
	mode.add_theme_font_size_override("font_size", 28)
	outer.add_child(mode)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var current: int = Global.opp_index if _pick_opp else Global.team_index
	for i in Global.TEAMS.size():
		var tm: Dictionary = Global.TEAMS[i]
		var txt := "%s%s     PWR %d   SPD %d   ATK %d   DEF %d" % ["> " if i == current else "", tm["name"], tm["pwr"], tm["spd"], tm["atk"], tm["def"]]
		var b := _button(txt, _pick_team.bind(i))
		b.custom_minimum_size = Vector2(0, 64)
		b.add_theme_font_size_override("font_size", 24)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var sb := StyleBoxFlat.new()
		sb.bg_color = tm["c1"]
		sb.border_color = tm["c2"]
		sb.set_border_width_all(5)
		sb.set_corner_radius_all(10)
		b.add_theme_stylebox_override("normal", sb)
		var light: bool = (tm["c1"] as Color).get_luminance() > 0.55
		var fc := Color("111111") if light else Color("ffffff")
		b.add_theme_color_override("font_color", fc)
		b.add_theme_color_override("font_hover_color", fc)
		b.add_theme_color_override("font_pressed_color", fc)
		list.add_child(b)
	var back := _button(Global.t("BACK"), _show_main)
	back.custom_minimum_size = Vector2(0, 70)
	outer.add_child(back)


func _toggle_pick() -> void:
	_pick_opp = not _pick_opp
	_show_teams()


func _pick_team(i: int) -> void:
	if _pick_opp:
		Global.opp_index = i
		if Global.opp_index == Global.team_index:
			Global.team_index = (i + 1) % Global.TEAMS.size()
	else:
		Global.team_index = i
		if Global.opp_index == i:
			Global.opp_index = (i + 1) % Global.TEAMS.size()
	Global.save_data()
	_show_teams()


func _show_settings() -> void:
	var box := _center_box(1120)
	box.add_theme_constant_override("separation", 12)
	box.add_child(_title(Global.t("SETTINGS"), 44))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	var diffs := ["Easy", "Normal", "Hard"]
	var quals := ["Low", "Medium", "High"]
	var sizes := ["S", "M", "L"]
	var sens_names := ["Low", "Normal", "High"]
	var on_off := func(v: bool) -> String: return Global.t("ON" if v else "OFF")
	grid.add_child(_button("%s: %s" % [Global.t("LANGUAGE"), "العربية" if Global.language == "ar" else "English"], _cycle_lang, 68, 28))
	grid.add_child(_button("%s: %s" % [Global.t("DIFFICULTY"), Global.t(diffs[Global.difficulty])], _cycle_diff, 68, 28))
	grid.add_child(_button("%s: %s" % [Global.t("QUALITY"), Global.t(quals[Global.quality])], _cycle_quality, 68, 28))
	grid.add_child(_button("%s: %d %s" % [Global.t("MATCH LENGTH"), Global.match_minutes, Global.t("min")], _cycle_minutes, 68, 28))
	grid.add_child(_button("%s: %s" % [Global.t("SOUND"), Global.t("ON" if Global.sound_on else "OFF")], _toggle_sound, 68, 28))
	grid.add_child(_button("%s: %s" % [Global.t("BUTTON SIZE"), sizes[_size_idx()]], _cycle_btn_size, 68, 28))
	grid.add_child(_button("%s: %d%%" % [Global.t("BUTTON OPACITY"), int(round(Global.btn_opacity * 100.0))], _cycle_btn_opacity, 68, 28))
	grid.add_child(_button("%s: %s" % [Global.t("STICK SENSITIVITY"), Global.t(sens_names[_sens_idx()])], _cycle_sens, 68, 28))
	grid.add_child(_button("%s: %s" % [Global.t("SWITCH BUTTON"), on_off.call(not bool(Global.btn_hidden.get("SWITCH", false)))], func(): _toggle_hidden("SWITCH"), 68, 28))
	grid.add_child(_button("%s: %s" % [Global.t("LONG BUTTON"), on_off.call(not bool(Global.btn_hidden.get("LONG", false)))], func(): _toggle_hidden("LONG"), 68, 28))
	grid.add_child(_button(Global.t("EDIT LAYOUT"), _edit_layout, 68, 28))
	grid.add_child(_button(Global.t("BACK"), _show_main, 68, 28))


func _sens_idx() -> int:
	if Global.stick_sens < 0.9:
		return 0
	return 1 if Global.stick_sens < 1.1 else 2


func _cycle_sens() -> void:
	var vals := [0.8, 1.0, 1.25]
	Global.stick_sens = vals[(_sens_idx() + 1) % 3]
	Global.save_data()
	_show_settings()


func _toggle_hidden(action: String) -> void:
	Global.btn_hidden[action] = not bool(Global.btn_hidden.get(action, false))
	Global.save_data()
	_show_settings()


func _size_idx() -> int:
	if Global.btn_scale < 0.9:
		return 0
	return 1 if Global.btn_scale < 1.1 else 2


func _cycle_btn_size() -> void:
	var vals := [0.8, 1.0, 1.2]
	Global.btn_scale = vals[(_size_idx() + 1) % 3]
	Global.save_data()
	_show_settings()


func _cycle_btn_opacity() -> void:
	var o := Global.btn_opacity + 0.15
	Global.btn_opacity = 0.25 if o > 0.85 else o
	Global.save_data()
	_show_settings()


func _edit_layout() -> void:
	get_tree().change_scene_to_file("res://scenes/layout_editor.tscn")


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
