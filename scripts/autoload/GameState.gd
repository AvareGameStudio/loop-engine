extends Node
## Persistent meta-state, session flags, and save/load. Autoload.

const SAVE_PATH := "user://loop_engine_save.json"
const SAVE_VERSION := 1

var energy: int = 0
var coins: int = 0
var best_combo: int = 0
var best_score: int = 0
var runs_played: int = 0
var generator_level: int = 1
var global_mult_level: int = 1
var unlocked_themes: PackedStringArray = PackedStringArray(["neon"])
var equipped_theme: String = "neon"
var no_ads: bool = false
var auto_tap: bool = false
var cosmetics: PackedStringArray = PackedStringArray(["default"])

var session_score: int = 0
var session_combo: int = 0
var session_hits: int = 0
var session_perfects: int = 0
var session_multiplier: float = 1.0
var current_stage: int = 1
var hits_in_stage: int = 0
var hits_needed: int = 8
var run_active: bool = false
var revive_used: bool = false

var dda_rpm: float = 0.55
var dda_perfect_deg: float = 7.0
var dda_good_deg: float = 16.0
var dda_near_deg: float = 22.0

func _ready() -> void:
	load_game()
	EventBus.energy_changed.connect(func(a: int, _d: int) -> void: energy = a)
	EventBus.coins_changed.connect(func(a: int, _d: int) -> void: coins = a)


func generator_rate() -> float:
	return 1.0 + (generator_level - 1) * 0.18


func global_multiplier() -> float:
	return 1.0 + (global_mult_level - 1) * 0.12


func upgrade_cost(stat: String) -> int:
	var level := generator_level if stat == "generator" else global_mult_level
	return int(40 * pow(1.35, level - 1))


func add_energy(delta: int) -> void:
	energy = max(0, energy + delta)
	EventBus.energy_changed.emit(energy, delta)
	save_game()


func add_coins(delta: int) -> void:
	coins = max(0, coins + delta)
	EventBus.coins_changed.emit(coins, delta)
	save_game()


func try_upgrade(stat: String) -> bool:
	var cost := upgrade_cost(stat)
	if energy < cost:
		return false
	add_energy(-cost)
	if stat == "generator":
		generator_level += 1
		EventBus.meta_upgraded.emit("generator", generator_level)
	else:
		global_mult_level += 1
		EventBus.meta_upgraded.emit("global_mult", global_mult_level)
	save_game()
	return true


func reset_run() -> void:
	session_score = 0
	session_combo = 0
	session_hits = 0
	session_perfects = 0
	session_multiplier = 1.0
	current_stage = 1
	hits_in_stage = 0
	hits_needed = 8
	run_active = true
	revive_used = false
	runs_played += 1
	save_game()


func end_run() -> void:
	run_active = false
	best_combo = max(best_combo, session_combo)
	best_score = max(best_score, session_score)
	save_game()


func to_dict() -> Dictionary:
	return {
		"v": SAVE_VERSION,
		"energy": energy,
		"coins": coins,
		"best_combo": best_combo,
		"best_score": best_score,
		"runs_played": runs_played,
		"generator_level": generator_level,
		"global_mult_level": global_mult_level,
		"unlocked_themes": Array(unlocked_themes),
		"equipped_theme": equipped_theme,
		"no_ads": no_ads,
		"auto_tap": auto_tap,
		"cosmetics": Array(cosmetics),
		"dda_rpm": dda_rpm,
		"dda_perfect_deg": dda_perfect_deg,
		"dda_good_deg": dda_good_deg,
		"dda_near_deg": dda_near_deg,
	}


func from_dict(data: Dictionary) -> void:
	energy = int(data.get("energy", 0))
	coins = int(data.get("coins", 0))
	best_combo = int(data.get("best_combo", 0))
	best_score = int(data.get("best_score", 0))
	runs_played = int(data.get("runs_played", 0))
	generator_level = int(data.get("generator_level", 1))
	global_mult_level = int(data.get("global_mult_level", 1))
	equipped_theme = String(data.get("equipped_theme", "neon"))
	no_ads = bool(data.get("no_ads", false))
	auto_tap = bool(data.get("auto_tap", false))
	dda_rpm = float(data.get("dda_rpm", 0.55))
	dda_perfect_deg = float(data.get("dda_perfect_deg", 7.0))
	dda_good_deg = float(data.get("dda_good_deg", 16.0))
	dda_near_deg = float(data.get("dda_near_deg", 22.0))
	var themes: Array = data.get("unlocked_themes", ["neon"])
	unlocked_themes = PackedStringArray(themes)
	var skins: Array = data.get("cosmetics", ["default"])
	cosmetics = PackedStringArray(skins)


func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Loop Engine: could not write save file.")
		return
	file.store_string(JSON.stringify(to_dict(), "\t"))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		from_dict(parsed)
