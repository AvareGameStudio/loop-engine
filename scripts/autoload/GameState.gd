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
var passive_level: int = 1
## Unclaimed Auto-Pulse earnings. Shown as a piggy bank, never a live ticker.
var unclaimed_energy: int = 0
## Unix time of last backgrounding; used to fill the vault while the app is closed.
var last_seen_unix: int = 0
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

const SAVE_DEBOUNCE: float = 1.5

var _save_pending: bool = false


func _ready() -> void:
	load_game()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			stamp_seen()
			if _save_pending:
				save_game()


func add_energy(delta: int) -> void:
	energy = max(0, energy + delta)
	EventBus.energy_changed.emit(energy, delta)
	request_save()


func add_coins(delta: int) -> void:
	coins = max(0, coins + delta)
	EventBus.coins_changed.emit(coins, delta)
	request_save()


## Instant Gratification is deferred until Claim: idle income lands here, not the wallet.
func add_vault(delta: int) -> void:
	if delta == 0:
		return
	unclaimed_energy = max(0, unclaimed_energy + delta)
	EventBus.vault_changed.emit(unclaimed_energy, delta)
	request_save()


## Empties the piggy into the wallet. Returns how much was claimed (0 if empty).
func claim_vault() -> int:
	var n: int = unclaimed_energy
	unclaimed_energy = 0
	if n > 0:
		add_energy(n)
		EventBus.vault_changed.emit(0, -n)
	save_game()
	return n


func stamp_seen() -> void:
	last_seen_unix = int(Time.get_unix_time_from_system())
	request_save()


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
	request_save()


func end_run() -> void:
	run_active = false
	best_combo = max(best_combo, session_combo)
	best_score = max(best_score, session_score)
	stamp_seen()
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
		"passive_level": passive_level,
		"unclaimed_energy": unclaimed_energy,
		"last_seen_unix": last_seen_unix,
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
	generator_level = maxi(int(data.get("generator_level", 1)), 1)
	global_mult_level = maxi(int(data.get("global_mult_level", 1)), 1)
	passive_level = maxi(int(data.get("passive_level", 1)), 1)
	unclaimed_energy = int(data.get("unclaimed_energy", 0))
	last_seen_unix = int(data.get("last_seen_unix", 0))
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


func request_save() -> void:
	if _save_pending:
		return
	_save_pending = true
	get_tree().create_timer(SAVE_DEBOUNCE, true, false, true).timeout.connect(save_game)


func save_game() -> void:
	_save_pending = false
	# Write-then-rename: a crash mid-write can never truncate the real save.
	var tmp_path: String = SAVE_PATH + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_warning("Loop Engine: could not write save file (%s)." % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(to_dict()))
	file.close()
	var err: Error = DirAccess.rename_absolute(tmp_path, SAVE_PATH)
	if err != OK:
		push_warning("Loop Engine: save rename failed (%s)." % error_string(err))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		from_dict(parsed)
