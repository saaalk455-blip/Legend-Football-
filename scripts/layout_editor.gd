extends Control
## Drag the touch buttons where you want them, then SAVE. The layout is
## stored in the settings file and used by every match.

var _tc: TouchControls


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("0b3d1e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var hint := Label.new()
	hint.text = Global.t("EDIT LAYOUT")
	hint.add_theme_font_size_override("font_size", 40)
	hint.position = Vector2(40, 24)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	var row := HBoxContainer.new()
	row.position = Vector2(40, 90)
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	row.add_child(_btn(Global.t("SAVE"), _on_save))
	row.add_child(_btn(Global.t("RESET"), _on_reset))
	row.add_child(_btn(Global.t("BACK"), _back))
	_tc = TouchControls.new()
	_tc.edit_mode = true
	add_child(_tc)


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(190, 76)
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(cb)
	return b


func _on_save() -> void:
	_tc.save_layout()
	_back()


func _on_reset() -> void:
	_tc.reset_layout()


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
