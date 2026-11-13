extends Node
## Autoload: settings, save data, national-team data, roster generation, tiny translation helper.

const SAVE_PATH := "user://legend_football.cfg"

# name, name-pool region, shirt colour, shorts colour, speed, attack, defense
const RAW_TEAMS := [
	["Brazil", "latam", "f2c500", "1f5fbf", 92, 93, 83],
	["Argentina", "latam", "7fc4ec", "ffffff", 86, 90, 82],
	["France", "french", "1d4ed8", "ffffff", 87, 88, 86],
	["Italy", "italian", "2f7fd1", "ffffff", 80, 84, 92],
	["Germany", "german", "f2f2f2", "111111", 80, 83, 88],
	["Spain", "iberia", "d62828", "1d3557", 85, 85, 80],
	["England", "english", "f2f2f2", "1d3557", 81, 82, 82],
	["Netherlands", "dutch", "f28c00", "ffffff", 85, 87, 78],
	["Portugal", "iberia", "b00020", "1f8a3a", 85, 86, 77],
	["Egypt", "arabic", "c1121f", "ffffff", 78, 76, 74],
	["Japan", "japanese", "1d4ed8", "ffffff", 82, 74, 72],
	["South Korea", "korean", "d62828", "ffffff", 83, 76, 76],
	["Nigeria", "westafrican", "2a9d3f", "ffffff", 86, 78, 72],
	["Cameroon", "westafrican", "2a9d3f", "d62828", 85, 77, 74],
	["Mexico", "latam", "2a9d3f", "ffffff", 80, 78, 76],
	["USA", "english", "f2f2f2", "1d3557", 80, 74, 76],
	["Uruguay", "latam", "7fc4ec", "111111", 80, 80, 80],
	["Turkey", "turkish", "d62828", "ffffff", 80, 80, 76],
	["Croatia", "slavic", "d62828", "ffffff", 79, 82, 78],
	["Senegal", "westafrican", "f2f2f2", "2a9d3f", 85, 78, 73],
	["Sweden", "nordic", "f5d000", "1d4ed8", 78, 78, 80],
	["Denmark", "nordic", "d62828", "ffffff", 79, 78, 80],
	["Saudi Arabia", "arabic", "2a9d3f", "ffffff", 77, 70, 68],
	["Morocco", "arabic", "c1121f", "1f8a3a", 82, 76, 74],
]

const CODES := {
	"Brazil": "BRA", "Argentina": "ARG", "France": "FRA", "Italy": "ITA", "Germany": "GER",
	"Spain": "ESP", "England": "ENG", "Netherlands": "NED", "Portugal": "POR", "Egypt": "EGY",
	"Japan": "JPN", "South Korea": "KOR", "Nigeria": "NGA", "Cameroon": "CMR", "Mexico": "MEX",
	"USA": "USA", "Uruguay": "URU", "Turkey": "TUR", "Croatia": "CRO", "Senegal": "SEN",
	"Sweden": "SWE", "Denmark": "DEN", "Saudi Arabia": "KSA", "Morocco": "MAR",
}

# Fictional name pools: [first names, family names]
const NAMES := {
	"latam": [["Carlos", "Diego", "Mateo", "Lucas", "Rafael", "Gabriel", "Pablo", "Felipe"], ["Silva", "Santos", "Costa", "Moreno", "Rojas", "Cruz", "Lima", "Campos"]],
	"iberia": [["Javier", "Miguel", "Tiago", "Bruno", "Andre", "Sergio", "Raul", "Hugo"], ["Navarro", "Ortega", "Duarte", "Reis", "Pinto", "Vidal", "Molina", "Cardoso"]],
	"french": [["Antoine", "Julien", "Hugo", "Lucas", "Mathieu", "Olivier", "Remy", "Etienne"], ["Dubois", "Moreau", "Lambert", "Fontaine", "Girard", "Mercier", "Roux", "Blanc"]],
	"italian": [["Marco", "Luca", "Matteo", "Andrea", "Paolo", "Stefano", "Fabio", "Nicola"], ["Rossi", "Ferri", "Conti", "Galli", "Marino", "Greco", "Bruno", "Costa"]],
	"german": [["Jonas", "Lukas", "Felix", "Moritz", "Tobias", "Stefan", "Jan", "Max"], ["Weber", "Schulz", "Becker", "Hoffmann", "Koch", "Richter", "Wolf", "Lange"]],
	"english": [["James", "Tom", "Harry", "Jack", "Daniel", "Ben", "Luke", "Sam"], ["Walker", "Hughes", "Carter", "Bennett", "Cooper", "Ward", "Brooks", "Hayes"]],
	"dutch": [["Daan", "Sven", "Joost", "Bram", "Niels", "Ruben", "Thijs", "Lars"], ["de Vries", "Bakker", "Visser", "Smit", "Meijer", "Mulder", "Bos", "Vos"]],
	"arabic": [["Ahmed", "Omar", "Karim", "Youssef", "Khaled", "Hassan", "Tarek", "Samir"], ["Mansour", "Farouk", "Nasser", "Haddad", "Salem", "Rashid", "Fahmy", "Saleh"]],
	"japanese": [["Kenji", "Takeshi", "Hiroshi", "Daiki", "Ryo", "Shun", "Taro", "Yuto"], ["Tanaka", "Sato", "Ito", "Kato", "Mori", "Hayashi", "Ogawa", "Fujita"]],
	"korean": [["Minho", "Jisung", "Hyun", "Donghae", "Seojun", "Taeyang", "Woojin", "Joon"], ["Kim", "Park", "Choi", "Jung", "Kang", "Yoon", "Han", "Shin"]],
	"westafrican": [["Emeka", "Kofi", "Ibrahim", "Chidi", "Moussa", "Samuel", "Yaw", "Tunde"], ["Okafor", "Mensah", "Diallo", "Eze", "Traore", "Balogun", "Ndiaye", "Mbeki"]],
	"turkish": [["Emre", "Burak", "Mehmet", "Kerem", "Cem", "Arda", "Onur", "Selim"], ["Yilmaz", "Demir", "Kaya", "Celik", "Aksoy", "Arslan", "Polat", "Koc"]],
	"slavic": [["Ivan", "Marko", "Luka", "Stjepan", "Dario", "Nikola", "Tomas", "Petar"], ["Horvat", "Kovac", "Babic", "Juric", "Novak", "Maric", "Vukic", "Peric"]],
	"nordic": [["Erik", "Anders", "Magnus", "Mikkel", "Henrik", "Lars", "Oskar", "Nils"], ["Lindberg", "Nielsen", "Jensen", "Berg", "Holm", "Strand", "Dahl", "Ekman"]],
}

# Same order as FORMATION in game.gd
const ROLES := ["GK", "DEF", "DEF", "DEF", "DEF", "MID", "MID", "MID", "MID", "FWD", "FWD"]

var TEAMS: Array = []
var _rosters := {}

var team_index := 0
var opp_index := 1
var difficulty := 1        # 0 Easy, 1 Normal, 2 Hard
var match_minutes := 2     # short default for testing
var quality := 1           # 0 Low, 1 Medium, 2 High
var language := "en"       # "en" or "ar"
var sound_on := true
var btn_scale := 1.0       # touch button size multiplier
var btn_opacity := 0.55    # touch button fill alpha
var btn_offsets := {}      # action -> Vector2 offset from default position

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
	"BUTTON SIZE": {"ar": "حجم الأزرار"},
	"BUTTON OPACITY": {"ar": "شفافية الأزرار"},
	"EDIT LAYOUT": {"ar": "تعديل أماكن الأزرار"},
	"RESET": {"ar": "إعادة"},
	"SAVE": {"ar": "حفظ"},
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
	"YOUR TEAM": {"ar": "فريقك"},
	"OPPONENT": {"ar": "الخصم"},
	"ABOUT_TEXT": {"ar": "لعبة كرة قدم أصلية بأسلوب Retro 3D.\nأسماء اللاعبين خيالية."},
}


func _ready() -> void:
	for r in RAW_TEAMS:
		TEAMS.append({
			"name": r[0], "region": r[1],
			"c1": Color(r[2]), "c2": Color(r[3]),
			"spd": r[4], "atk": r[5], "def": r[6],
			"pwr": int(round((r[4] + r[5] + r[6]) / 3.0)),
			"code": CODES.get(r[0], str(r[0]).substr(0, 3).to_upper()),
		})
	load_data()
	team_index = clampi(team_index, 0, TEAMS.size() - 1)
	opp_index = clampi(opp_index, 0, TEAMS.size() - 1)
	if opp_index == team_index:
		opp_index = (team_index + 1) % TEAMS.size()
	apply_quality()


func t(key: String) -> String:
	if language == "ar" and TR.has(key) and TR[key].has("ar"):
		return TR[key]["ar"]
	if key == "ABOUT_TEXT":
		return "An original Retro 3D football game.\nPlayer names are fictional."
	return key


## 11 players for a team, in formation order (GK, 4 DEF, 4 MID, 2 FWD).
## Each: {name, role, speed, shoot, pass}. Names are generated, stats follow team ratings.
func get_roster(idx: int) -> Array:
	if _rosters.has(idx):
		return _rosters[idx]
	var tm: Dictionary = TEAMS[idx]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tm["name"])
	var pool: Array = NAMES[tm["region"]]
	var firsts: Array = pool[0]
	var lasts: Array = pool[1]
	var used := {}
	var out: Array = []
	for i in 11:
		var nm := ""
		for _try in 20:
			nm = "%s %s" % [firsts[rng.randi() % firsts.size()], lasts[rng.randi() % lasts.size()]]
			if not used.has(nm):
				break
		used[nm] = true
		var look := {"skin": rng.randi_range(0, 3), "hair": "short", "hcol": "black"}
		if Rosters.DATA.has(tm["name"]):
			var line: String = Rosters.DATA[tm["name"]][i]
			var parts := line.split("|")
			nm = parts[0] + "x"   # the trailing x keeps every name fictional
			look = {"skin": int(parts[1]), "hair": parts[2], "hcol": parts[3]}
		var role: String = ROLES[i]
		var spd: int = tm["spd"] + rng.randi_range(-8, 8)
		var shoot: int = tm["atk"] + rng.randi_range(-8, 8)
		var pas: int = int((tm["atk"] + tm["def"]) / 2.0) + rng.randi_range(-8, 8)
		match role:
			"GK":
				shoot -= 35
				pas -= 15
			"DEF":
				shoot -= 12
			"MID":
				pas += 4
			"FWD":
				shoot += 5
				pas -= 2
		out.append({
			"name": nm, "role": role,
			"speed": clampi(spd, 40, 99),
			"shoot": clampi(shoot, 25, 99),
			"pass": clampi(pas, 30, 99),
			"skin": look["skin"], "hair": look["hair"], "hcol": look["hcol"],
			"id": idx * 100 + i + 1,
			"accel": clampi(tm["spd"] + rng.randi_range(-10, 10), 40, 99),
			"stamina": clampi(68 + rng.randi_range(-10, 20), 40, 99),
			"dribble": clampi(int((tm["atk"] + tm["spd"]) / 2.0) + rng.randi_range(-8, 8) + (6 if role == "MID" or role == "FWD" else -4), 30, 99),
			"defense": clampi(tm["def"] + rng.randi_range(-8, 8) + (8 if role == "DEF" else (-15 if role == "FWD" else 0)), 25, 99),
			"keeper": clampi(tm["def"] + rng.randi_range(-6, 10), 40, 99) if role == "GK" else 0,
		})
	_rosters[idx] = out
	return out


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
	c.set_value("game", "opp_index", opp_index)
	c.set_value("game", "difficulty", difficulty)
	c.set_value("game", "match_minutes", match_minutes)
	c.set_value("game", "quality", quality)
	c.set_value("game", "language", language)
	c.set_value("game", "sound_on", sound_on)
	c.set_value("controls", "scale", btn_scale)
	c.set_value("controls", "opacity", btn_opacity)
	c.set_value("controls", "offsets", btn_offsets)
	c.save(SAVE_PATH)


func load_data() -> void:
	var c := ConfigFile.new()
	if c.load(SAVE_PATH) != OK:
		return
	team_index = c.get_value("game", "team_index", team_index)
	opp_index = c.get_value("game", "opp_index", opp_index)
	difficulty = c.get_value("game", "difficulty", difficulty)
	match_minutes = c.get_value("game", "match_minutes", match_minutes)
	quality = c.get_value("game", "quality", quality)
	language = c.get_value("game", "language", language)
	sound_on = c.get_value("game", "sound_on", sound_on)
	btn_scale = c.get_value("controls", "scale", btn_scale)
	btn_opacity = c.get_value("controls", "opacity", btn_opacity)
	btn_offsets = c.get_value("controls", "offsets", btn_offsets)
