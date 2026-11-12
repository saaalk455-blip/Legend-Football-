extends Node
## Autoload: settings + save data + tiny translation helper.

const SAVE_PATH := "user://legend_football.cfg"

const TEAMS := [
	{"name": "Cairo Lions", "c1": Color("e8b100"), "c2": Color("ffffff")},
	{"name": "Tokyo Falcons", "c1": Color("d62828"), "c2": Color("ffffff")},
	{"name": "Madrid Stars", "c1": Color("f5f5f5"), "c2": Color("1d3557")},
	{"name": "London Kings", "c1": Color("1d3557"), "c2": Color("e63946")},
	{"name": "Brazil United", "c1": Color("2a9d3f"), "c2": Color("ffd60a")},
	{"name": "Egypt Warriors", "c1": Color("b00020"), "c2": Color("111111")},
]

var team_index := 0
var difficulty := 1        # 0 Easy, 1 Normal, 2 Hard
var match_minutes := 2     # short default for testing
var quality := 1           # 0 Low, 1 Medium, 2 High
var language := "en"       # "en" or "ar"
var sound_on := true

const TR := {
	"PLAY": {"ar": "العب"},
	"TEAMS": {"ar": "الفرق"},
	"SETTINGS": {"ar": "الإعدادات"},
	"ABOUT": {"ar": "حول"},
	"BACK": {"ar": "رجوع"},
	"LANGUAGE": {"ar": "اللغة"},
	"DIFFICULTY": {"ar": "الصعوبة"},
	"QUALITY": {"ar": "الجودة"},
	"MATCH LENGTH": {"ar": "مدة المباراة"},
	"SOUND": {"ar": "الصوت"},
	"Easy": {"ar": "سهل"},
	"Normal": {"ar": "عادي"},
	"Hard": {"ar": "صعب"},
	"Low": {"ar": "منخفضة"},
	"Medium": {"ar": "متوسطة"},
	"High": {"ar": "عالية"},
	"ON": {"ar": "تشغيل"},
	"OFF": {"ar": "إيقاف"},
	"MENU": {"ar": "القائمة"},
	"min": {"ar": "د"},
	"ABOUT_TEXT": {"ar": "لعبة كرة قدم أصلية بأسلوب Retro 3D.\nجميع الفرق والأسماء خيالية."},
}


func _ready() -> void:
	load_data()
	apply_quality()


func t(key: String) -> String:
	if language == "ar" and TR.has(key) and TR[key].has("ar"):
		return TR[key]["ar"]
	if key == "ABOUT_TEXT":
		return "An original Retro 3D football game.\nAll teams and names are fictional."
	return key


func apply_quality() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	match quality:
		0:
			vp.scaling_3d_scale = 0.6
			vp.msaa_3d = Viewport.MSAA_DISABLED
		1:
			vp.scaling_3d_scale = 0.8
			vp.msaa_3d = Viewport.MSAA_DISABLED
		_:
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X


func save_data() -> void:
	var c := ConfigFile.new()
	c.set_value("game", "team_index", team_index)
	c.set_value("game", "difficulty", difficulty)
	c.set_value("game", "match_minutes", match_minutes)
	c.set_value("game", "quality", quality)
	c.set_value("game", "language", language)
	c.set_value("game", "sound_on", sound_on)
	c.save(SAVE_PATH)


func load_data() -> void:
	var c := ConfigFile.new()
	if c.load(SAVE_PATH) != OK:
		return
	team_index = c.get_value("game", "team_index", team_index)
	difficulty = c.get_value("game", "difficulty", difficulty)
	match_minutes = c.get_value("game", "match_minutes", match_minutes)
	quality = c.get_value("game", "quality", quality)
	language = c.get_value("game", "language", language)
	sound_on = c.get_value("game", "sound_on", sound_on)
