extends Node
## Persistent meta-state, session flags, and save/load. Autoload.

const SAVE_PATH := "user://loop_engine_save.json"
const SAVE_VERSION := 1
const THEME_GOAL: int = 5
const THEME_BY_STAGE := {
	3: "aurora",
	5: "ember",
	7: "void",
	9: "prism",
}

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
## Granted when the first ring is cracked, from the reward popup. Off until then, so a miss still ends the run.
var auto_tap_unlocked: bool = false
var auto_tap_purchased: bool = false
var stages_cleared: int = 0
var lifetime_hits: int = 0
var _announce_auto_tap: bool = false
var cosmetics: PackedStringArray = PackedStringArray(["default"])
var equipped_dial: String = "steel"

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


func unlock_theme_for_stage(stage: int) -> void:
	if not THEME_BY_STAGE.has(stage):
		return
	var theme_id: String = String(THEME_BY_STAGE[stage])
	if unlocked_themes.has(theme_id):
		return
	unlocked_themes.append(theme_id)
	save_game()


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


const SHELL_COUNT := 200


## 0 at the first ring, 1 once the door has climbed from iron to gem ore.
func shell_progress(stage: int) -> float:
	return clampf(float(clampi(stage, 1, SHELL_COUNT) - 1) / float(SHELL_COUNT - 1), 0.0, 1.0)


const RUST_RINGS := 10


## Full crust on ring 1. Nothing left on ring 10.
func shell_rust(stage: int) -> float:
	if stage >= RUST_RINGS:
		return 0.0
	return 1.0 - float(maxi(stage, 1) - 1) / float(RUST_RINGS - 1)


## 0 while the rust is on. After ring 10, a new look every two rings.
func shell_step(stage: int) -> int:
	if stage < RUST_RINGS:
		return 0
	return (stage - RUST_RINGS) / 2


## Iron, then a clearly different metal every two rings, then gem-set gold.
func shell_metal(stage: int) -> Color:
	var stops: Array[Color] = [
		Color(0.42, 0.40, 0.36),
		Color(0.62, 0.66, 0.70),
		Color(0.72, 0.40, 0.24),
		Color(0.70, 0.48, 0.22),
		Color(0.78, 0.60, 0.24),
		Color(0.76, 0.78, 0.80),
		Color(0.86, 0.68, 0.22),
		Color(0.90, 0.88, 0.80),
	]
	var step := shell_step(stage)
	return stops[mini(step, stops.size() - 1)]


func shell_gems(stage: int) -> int:
	var step := shell_step(stage)
	if step < 4:
		return 0
	if step < 8:
		return step - 3
	return mini(3 + (step % 8), 10)


func shell_inlay(stage: int) -> int:
	return shell_step(stage) % 4


## Gem inlays start only after the door is already precious metal.
func shell_ore(stage: int) -> float:
	return 1.0 if shell_gems(stage) > 0 else 0.0


func shell_color(stage: int) -> Color:
	return shell_metal(stage).lerp(Color(0.52, 0.26, 0.10), shell_rust(stage) * 0.82)


func _shell_smooth(edge0: float, edge1: float, x: float) -> float:
	var u := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func _shell_ramp(stops: Array, u: float) -> Color:
	var x := clampf(u, 0.0, 1.0) * float(stops.size() - 1)
	var i := mini(int(floor(x)), stops.size() - 2)
	return (stops[i] as Color).lerp(stops[i + 1], x - float(i))


func note_landed_hit() -> void:
	lifetime_hits += 1


func note_stage_cleared() -> void:
	var first_ring := current_stage == 1
	stages_cleared += 1
	if first_ring:
		consider_auto_tap_unlock()


## Popup offers the reward. Tapping stays off until they accept, so this ring can still be missed.
func consider_auto_tap_unlock() -> void:
	if auto_tap_unlocked or auto_tap_purchased or _announce_auto_tap:
		return
	_announce_auto_tap = true


func accept_auto_tap_reward() -> void:
	auto_tap_unlocked = true
	auto_tap = true
	_announce_auto_tap = false
	save_game()


func has_auto_tap_announce() -> bool:
	return _announce_auto_tap


func take_auto_tap_announce() -> bool:
	var announce := _announce_auto_tap
	_announce_auto_tap = false
	return announce


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
		"auto_tap_unlocked": auto_tap_unlocked,
		"auto_tap_earned": auto_tap_unlocked,
		"auto_tap_from_ring": auto_tap_unlocked,
		"auto_tap_purchased": auto_tap_purchased,
		"stages_cleared": stages_cleared,
		"lifetime_hits": lifetime_hits,
		"cosmetics": Array(cosmetics),
		"equipped_dial": equipped_dial,
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
	lifetime_hits = int(data.get("lifetime_hits", 0))
	stages_cleared = int(data.get("stages_cleared", 0))
	auto_tap_purchased = bool(data.get("auto_tap_purchased", false))
	# An earlier build turned this on when a run ended. Only the first-ring reward counts.
	auto_tap_unlocked = auto_tap_purchased or bool(data.get("auto_tap_from_ring", false))
	auto_tap = bool(data.get("auto_tap", false)) and auto_tap_unlocked
	dda_rpm = float(data.get("dda_rpm", 0.55))
	dda_perfect_deg = float(data.get("dda_perfect_deg", 7.0))
	dda_good_deg = float(data.get("dda_good_deg", 16.0))
	dda_near_deg = float(data.get("dda_near_deg", 22.0))
	var themes: Array = data.get("unlocked_themes", ["neon"])
	unlocked_themes = PackedStringArray(themes)
	var skins: Array = data.get("cosmetics", ["default"])
	cosmetics = PackedStringArray(skins)
	equipped_dial = String(data.get("equipped_dial", "steel"))


func owns_dial(id: String) -> bool:
	return id == "steel" or cosmetics.has(id)


func buy_dial(id: String) -> bool:
	if not ["steel", "gold", "obsidian"].has(id):
		return false
	if owns_dial(id):
		equip_dial(id)
		return true
	var cost: int = 80 if id == "gold" else 140
	if coins < cost:
		return false
	add_coins(-cost)
	cosmetics.append(id)
	equip_dial(id)
	save_game()
	return true


func equip_dial(id: String) -> void:
	if not owns_dial(id):
		return
	equipped_dial = id
	EventBus.cosmetic_equipped.emit(id)
	request_save()


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
