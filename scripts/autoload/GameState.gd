extends Node
## Persistent meta-state, session flags, and save/load. Autoload.
## One level = one vault. The vault index is persistent: a bust retries the same
## vault, a crack moves to the next one, so the 200-door art progression is real.

const SAVE_PATH := "user://loop_engine_save.json"
const SAVE_VERSION := 2

## Alarm strikes before the cops arrive. Each Miss / Near-Miss adds one.
const ALARM_MAX: int = 3
## Every Nth vault is a Golden Vault: more pins, double loot, gold door.
const GOLDEN_EVERY: int = 5
## A loot item joins the hideout every N cracked vaults.
const LOOT_EVERY: int = 3

## Vault type by first vault index. Replaces the abstract Neon/Aurora colour themes.
const VAULT_TYPE_BY_STAGE := {
	1: "piggy",
	3: "office",
	6: "bank",
	11: "museum",
	26: "casino",
	51: "fort",
}

## Hideout shelf. One unlocks per LOOT_EVERY cracked vaults; names live in translations.
const LOOT_ITEMS: PackedStringArray = [
	"cash", "gold", "diamond", "painting", "trophy", "watch",
	"crown", "car", "yacht", "jet", "island", "moonrock",
]

var cash: int = 0
var best_combo: int = 0
var best_score: int = 0
var runs_played: int = 0
var crew_level: int = 1
var gloves_level: int = 1
## Unclaimed Crew earnings. Shown as a stuffed bag, never a live ticker.
var unclaimed_cash: int = 0
## Unix time of last backgrounding; used to fill the stash while the app is closed.
var last_seen_unix: int = 0
var no_ads: bool = false
var auto_tap: bool = false
var auto_tap_unlocked: bool = false
var auto_tap_purchased: bool = false
var stages_cleared: int = 0
var lifetime_hits: int = 0
var cosmetics: PackedStringArray = PackedStringArray(["default"])
var equipped_dial: String = "steel"

var session_score: int = 0
var session_combo: int = 0
var session_hits: int = 0
var session_perfects: int = 0
var session_multiplier: float = 1.0
var session_alarm: int = 0
var current_stage: int = 1
var hits_in_stage: int = 0
var hits_needed: int = 3
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
	current_stage = stages_cleared + 1


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			stamp_seen()
			if _save_pending:
				save_game()


func add_cash(delta: int) -> void:
	cash = max(0, cash + delta)
	EventBus.cash_changed.emit(cash, delta)
	request_save()


## Crew income lands here, not the wallet, until the player collects it.
func add_stash(delta: int) -> void:
	if delta == 0:
		return
	unclaimed_cash = max(0, unclaimed_cash + delta)
	EventBus.stash_changed.emit(unclaimed_cash, delta)
	request_save()


## Empties the stash into the wallet. Returns how much was claimed (0 if empty).
func claim_stash() -> int:
	var n: int = unclaimed_cash
	unclaimed_cash = 0
	if n > 0:
		add_cash(n)
		EventBus.stash_changed.emit(0, -n)
	save_game()
	return n


func stamp_seen() -> void:
	last_seen_unix = int(Time.get_unix_time_from_system())
	request_save()


# --- Level curve -------------------------------------------------------------

## Pins (hits) a vault needs. 3 at the start, 8 deep in. Golden vaults add three.
static func pins_for(stage: int) -> int:
	var s: int = maxi(stage, 1)
	var pins: int = 3
	if s >= 51:
		pins = 8
	elif s >= 26:
		pins = 7
	elif s >= 11:
		pins = 6
	elif s >= 6:
		pins = 5
	elif s >= 3:
		pins = 4
	if is_golden(s):
		pins = mini(pins + 3, 10)
	return pins


static func is_golden(stage: int) -> bool:
	return stage > 0 and stage % GOLDEN_EVERY == 0


## Dial speed in revolutions per second before DDA. 0.38 → 0.55 @10 → 0.75 @25 → 0.9 @60.
static func base_rpm(stage: int) -> float:
	return _curve(stage, [[1, 0.38], [10, 0.55], [25, 0.75], [60, 0.9], [200, 1.0]])


## Good window half-angle in degrees before DDA. 20° → 16° @10 → 13° @25 → 11° @60.
static func base_good_deg(stage: int) -> float:
	return _curve(stage, [[1, 20.0], [10, 16.0], [25, 13.0], [60, 11.0], [200, 10.0]])


## Direction flips only once the player has two vaults under the belt.
static func flips_enabled(stage: int) -> bool:
	return stage >= 3


## Loot multiplier for a cracked vault.
static func loot_mult(stage: int) -> float:
	return 2.0 if is_golden(stage) else 1.0


static func _curve(stage: int, stops: Array) -> float:
	var s := float(maxi(stage, 1))
	if s <= float(stops[0][0]):
		return float(stops[0][1])
	for i in range(1, stops.size()):
		var x1 := float(stops[i][0])
		if s <= x1:
			var x0 := float(stops[i - 1][0])
			var t := (s - x0) / maxf(x1 - x0, 0.001)
			return lerpf(float(stops[i - 1][1]), float(stops[i][1]), t)
	return float(stops[stops.size() - 1][1])


# --- Vault type / loot collection -------------------------------------------

static func vault_type(stage: int) -> String:
	var best_key: int = 1
	for key in VAULT_TYPE_BY_STAGE.keys():
		if int(key) <= stage and int(key) >= best_key:
			best_key = int(key)
	return String(VAULT_TYPE_BY_STAGE.get(best_key, "piggy"))


## Vault types are unlocked by progress, so the list is derived, not stored.
func unlocked_vault_types() -> PackedStringArray:
	var out: PackedStringArray = []
	for key in VAULT_TYPE_BY_STAGE.keys():
		if int(key) <= current_stage:
			out.append(String(VAULT_TYPE_BY_STAGE[key]))
	return out


func loot_unlocked_count() -> int:
	return mini(stages_cleared / LOOT_EVERY, LOOT_ITEMS.size())


## 0..1 toward the next hideout item. 1.0 only when the shelf is full.
func loot_progress() -> float:
	if loot_unlocked_count() >= LOOT_ITEMS.size():
		return 1.0
	return float(stages_cleared % LOOT_EVERY) / float(LOOT_EVERY)


func next_loot_id() -> String:
	var n := loot_unlocked_count()
	if n >= LOOT_ITEMS.size():
		return ""
	return LOOT_ITEMS[n]


## True when the vault just cracked completed a shelf item.
func loot_just_unlocked() -> bool:
	if stages_cleared <= 0 or stages_cleared % LOOT_EVERY != 0:
		return false
	return stages_cleared / LOOT_EVERY <= LOOT_ITEMS.size()


# --- Session ------------------------------------------------------------------

func reset_run() -> void:
	session_score = 0
	session_combo = 0
	session_hits = 0
	session_perfects = 0
	session_multiplier = 1.0
	session_alarm = 0
	current_stage = stages_cleared + 1
	hits_in_stage = 0
	hits_needed = pins_for(current_stage)
	run_active = true
	revive_used = false
	runs_played += 1
	request_save()


## One strike. Returns true when the cops have arrived.
func raise_alarm() -> bool:
	session_alarm = mini(session_alarm + 1, ALARM_MAX)
	EventBus.alarm_changed.emit(session_alarm, ALARM_MAX)
	return session_alarm >= ALARM_MAX


func clear_alarm() -> void:
	session_alarm = 0
	EventBus.alarm_changed.emit(session_alarm, ALARM_MAX)


const SHELL_COUNT := 200


## 0 at the first vault, 1 once the door has climbed from iron to gem ore.
func shell_progress(stage: int) -> float:
	return clampf(float(clampi(stage, 1, SHELL_COUNT) - 1) / float(SHELL_COUNT - 1), 0.0, 1.0)


const RUST_RINGS := 10


## Full crust on vault 1. Nothing left on vault 10.
func shell_rust(stage: int) -> float:
	if stage >= RUST_RINGS:
		return 0.0
	return 1.0 - float(maxi(stage, 1) - 1) / float(RUST_RINGS - 1)


## 0 while the rust is on. After vault 10, a new look every two vaults.
func shell_step(stage: int) -> int:
	if stage < RUST_RINGS:
		return 0
	return (stage - RUST_RINGS) / 2


## Iron, then a clearly different metal every two vaults, then gem-set gold.
func shell_metal(stage: int) -> Color:
	if is_golden(stage):
		return Color(0.92, 0.72, 0.22)
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
	# Golden vaults never wear rust, even in the first ten.
	var rust := 0.0 if is_golden(stage) else shell_rust(stage)
	return shell_metal(stage).lerp(Color(0.52, 0.26, 0.10), rust * 0.82)


func note_landed_hit() -> void:
	lifetime_hits += 1


## Called when the last pin seats. Moves the persistent vault index forward.
func note_stage_cleared() -> void:
	stages_cleared += 1
	current_stage = stages_cleared + 1
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
		"cash": cash,
		"best_combo": best_combo,
		"best_score": best_score,
		"runs_played": runs_played,
		"crew_level": crew_level,
		"gloves_level": gloves_level,
		"unclaimed_cash": unclaimed_cash,
		"last_seen_unix": last_seen_unix,
		"no_ads": no_ads,
		"auto_tap": auto_tap,
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
	# v1 saves had energy + coins. Fold both into cash so nobody loses a wallet.
	if data.has("cash"):
		cash = int(data.get("cash", 0))
	else:
		cash = int(data.get("energy", 0)) + int(data.get("coins", 0))
	best_combo = int(data.get("best_combo", 0))
	best_score = int(data.get("best_score", 0))
	runs_played = int(data.get("runs_played", 0))
	crew_level = maxi(int(data.get("crew_level", data.get("generator_level", 1))), 1)
	gloves_level = maxi(int(data.get("gloves_level", data.get("global_mult_level", 1))), 1)
	unclaimed_cash = int(data.get("unclaimed_cash", data.get("unclaimed_energy", 0)))
	last_seen_unix = int(data.get("last_seen_unix", 0))
	no_ads = bool(data.get("no_ads", false))
	lifetime_hits = int(data.get("lifetime_hits", 0))
	stages_cleared = int(data.get("stages_cleared", 0))
	auto_tap_purchased = bool(data.get("auto_tap_purchased", false))
	# Auto-Tap is an IAP only now. The old first-ring reward no longer grants it.
	auto_tap_unlocked = auto_tap_purchased
	auto_tap = bool(data.get("auto_tap", false)) and auto_tap_unlocked
	dda_rpm = float(data.get("dda_rpm", 0.55))
	dda_perfect_deg = float(data.get("dda_perfect_deg", 7.0))
	dda_good_deg = float(data.get("dda_good_deg", 16.0))
	dda_near_deg = float(data.get("dda_near_deg", 22.0))
	var skins: Array = data.get("cosmetics", ["default"])
	cosmetics = PackedStringArray(skins)
	equipped_dial = String(data.get("equipped_dial", "steel"))


const DIAL_COST := {"steel": 0, "gold": 200, "obsidian": 600}


static func dial_cost(id: String) -> int:
	return int(DIAL_COST.get(id, 0))


func owns_dial(id: String) -> bool:
	return id == "steel" or cosmetics.has(id)


func buy_dial(id: String) -> bool:
	if not DIAL_COST.has(id):
		return false
	if owns_dial(id):
		equip_dial(id)
		return true
	var cost: int = dial_cost(id)
	if cash < cost:
		return false
	add_cash(-cost)
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
