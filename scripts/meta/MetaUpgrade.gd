class_name MetaUpgrade
extends Node
## Idle meta loop. Produces passive energy whenever no run is active, and owns the
## upgrade marketplace: catalog, prices, purchases, and the multipliers they buy.
## Levels persist in GameState; everything here is derived from them, so the
## economy math is static and callable without a node reference.

signal produced(amount: int)

## Matches the old idle drip (2 energy / 3 s) at level 1.
const PASSIVE_BASE: float = 0.67
const TICK_SECONDS: float = 1.0

## `effect_pct` is both the per-level bonus and the number the market shows.
const CATALOG := [
	{"id": "generator", "currency": "energy", "base_cost": 40, "growth": 1.35, "effect_pct": 18},
	{"id": "global_mult", "currency": "energy", "base_cost": 40, "growth": 1.35, "effect_pct": 12},
	{"id": "passive_yield", "currency": "coins", "base_cost": 30, "growth": 1.45, "effect_pct": 30},
]

var _carry: float = 0.0
var _elapsed: float = 0.0


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
	# Fractions carry over so slow rates still pay out exactly over time.
	_carry -= whole
	GameState.add_energy(whole)
	produced.emit(whole)


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


static func global_multiplier() -> float:
	return bonus("global_mult")


## Energy per second while idle.
static func passive_rate() -> float:
	return PASSIVE_BASE * bonus("generator") * bonus("passive_yield")
