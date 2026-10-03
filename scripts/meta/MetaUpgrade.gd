class_name MetaUpgrade
extends Node
## Idle meta loop. Auto-Pulse fills the Idle Vault while no run is active;
## Perfect Power scales Perfect juice. The market sells both.
## Levels persist in GameState; economy math is static so UI can call it without a node.

signal produced(amount: int)

## Matches the old idle drip (2 energy / 3 s) at level 1.
const PASSIVE_BASE: float = 0.67
const TICK_SECONDS: float = 1.0
## Cap so a week away does not dump a week's numbers onto the Claim screen.
const OFFLINE_CAP_SECONDS: int = 8 * 3600
## One minute of idle = a "full" piggy. Zeigarnik teases this at 90%.
const VAULT_FULL_SECONDS: float = 60.0

## `id` values are save keys. UI names live in translations (Auto-Pulse / Perfect Power).
const CATALOG := [
	{"id": "generator", "currency": "energy", "base_cost": 40, "growth": 1.35, "effect_pct": 18},
	{"id": "global_mult", "currency": "energy", "base_cost": 40, "growth": 1.35, "effect_pct": 12},
	{"id": "passive_yield", "currency": "coins", "base_cost": 30, "growth": 1.45, "effect_pct": 30},
]

var _carry: float = 0.0
var _elapsed: float = 0.0


func _ready() -> void:
	EventBus.run_started.connect(func() -> void: set_process(false))
	EventBus.run_ended.connect(func(_reason: String, _stats: Dictionary) -> void: set_process(true))
	# Offline hours become a Claim-able vault, not a silent wallet bump.
	accrue_offline()
	set_process(not GameState.run_active)


func _notification(what: int) -> void:
	# Don't pop the vault over an active run or the player loses their tap.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and not GameState.run_active:
		accrue_offline()
		if GameState.unclaimed_energy > 0:
			EventBus.vault_ready.emit(GameState.unclaimed_energy)


func _process(delta: float) -> void:
	if GameState.run_active:
		_elapsed = 0.0
		return
	_carry += passive_rate() * delta
	_elapsed += delta
	if _elapsed < TICK_SECONDS:
		return
	_elapsed = 0.0
	var whole: int = floori(_carry)
	if whole <= 0:
		return
	# Fractions carry so slow rates still pay out exactly. Vault, not wallet:
	# Instant Gratification happens at Claim, not on a live ticker.
	_carry -= whole
	GameState.add_vault(whole)
	produced.emit(whole)


## Credits time spent in the background into the vault. Returns energy added.
func accrue_offline() -> int:
	var now: int = int(Time.get_unix_time_from_system())
	var last: int = GameState.last_seen_unix
	GameState.last_seen_unix = now
	if last <= 0 or GameState.run_active:
		GameState.request_save()
		return 0
	var dt: int = clampi(now - last, 0, OFFLINE_CAP_SECONDS)
	if dt < 5:
		return 0
	var gain: int = floori(passive_rate() * float(dt))
	if gain > 0:
		GameState.add_vault(gain)
		produced.emit(gain)
	return gain


static func entry(id: String) -> Dictionary:
	for item: Dictionary in CATALOG:
		if item.id == id:
			return item
	push_error("MetaUpgrade: unknown upgrade '%s'." % id)
	return {}


static func level(id: String) -> int:
	match id:
		"generator":
			return GameState.generator_level
		"global_mult":
			return GameState.global_mult_level
		"passive_yield":
			return GameState.passive_level
	return 1


static func cost(id: String) -> int:
	var item: Dictionary = entry(id)
	return int(float(item.base_cost) * pow(float(item.growth), level(id) - 1))


static func balance(currency: String) -> int:
	return GameState.energy if currency == "energy" else GameState.coins


static func can_afford(id: String) -> bool:
	return balance(String(entry(id).currency)) >= cost(id)


static func affordable_count() -> int:
	var n: int = 0
	for item: Dictionary in CATALOG:
		if can_afford(String(item.id)):
			n += 1
	return n


static func purchase(id: String) -> bool:
	if not can_afford(id):
		return false
	var price: int = cost(id)
	if entry(id).currency == "energy":
		GameState.add_energy(-price)
	else:
		GameState.add_coins(-price)
	match id:
		"generator":
			GameState.generator_level += 1
		"global_mult":
			GameState.global_mult_level += 1
		"passive_yield":
			GameState.passive_level += 1
	GameState.save_game()
	EventBus.meta_upgraded.emit(id, level(id))
	return true


static func bonus(id: String) -> float:
	return 1.0 + (level(id) - 1) * float(entry(id).effect_pct) / 100.0


static func generator_rate() -> float:
	return bonus("generator")


## Perfect Power: score + juice scale for Perfect hits. Instant Gratification lever.
static func perfect_power() -> float:
	return bonus("global_mult")


static func global_multiplier() -> float:
	return perfect_power()


## Energy per second while idle (fills the vault, not the wallet).
static func passive_rate() -> float:
	return PASSIVE_BASE * bonus("generator") * bonus("passive_yield")


## 0..1 fill of the Idle Vault piggy. Caps at 0.9 unless actually overflowing.
static func vault_progress() -> float:
	var full: float = maxf(passive_rate() * VAULT_FULL_SECONDS, 10.0)
	var raw: float = float(GameState.unclaimed_energy) / full
	if raw >= 1.0:
		return 1.0
	if raw > 0.9:
		return 0.9
	if raw <= 0.0:
		return 0.04
	return raw
