class_name MetaUpgrade
extends Node
## Market upgrades. The Crew (offline stash) was removed: unused in play data and unclear;
## save v5 pays any old stash into the wallet.
## Wide Gate adds degrees to the green Good arc. The market sells both, in cash.
## Levels persist in GameState; economy math is static so UI can call it without a node.

## `id` values are save keys. UI names live in translations (Wide Gate).
const CATALOG := [
	{"id": "gloves", "base_cost": 80, "growth": 1.4, "effect_pct": 12},
]

## Wide Gate: the green Good arc grows this many degrees per purchased level.
const GLOVES_DEG: float = 1.5


func _ready() -> void:
	set_process(false)


static func entry(id: String) -> Dictionary:
	for item: Dictionary in CATALOG:
		if item.id == id:
			return item
	push_error("MetaUpgrade: unknown upgrade '%s'." % id)
	return {}


static func level(id: String) -> int:
	match id:
		"gloves":
			return GameState.gloves_level
	return 1


## Priced off one heist's door payout (3 x (40 + 12 x door)), so an upgrade always costs about
## a heist and a half of loot: $80 flat was pocket change by heist 15 ($144k banked, unbought).
static func cost(id: String) -> int:
	var item: Dictionary = entry(id)
	var heist_pay: float = 3.0 * (40.0 + 12.0 * float(GameState.current_stage))
	var base: float = maxf(float(item.base_cost), heist_pay * 1.5)
	return int(round(base * pow(float(item.growth), level(id) - 1) / 10.0)) * 10


static func at_cap(id: String) -> bool:
	return id == "gloves" and GameState.gloves_level >= GameState.GLOVES_MAX


static func can_afford(id: String) -> bool:
	if at_cap(id):
		return false
	return GameState.cash >= cost(id)


static func unlocked(_id: String) -> bool:
	return true


static func affordable_count() -> int:
	var n: int = 0
	for item: Dictionary in CATALOG:
		if unlocked(String(item.id)) and can_afford(String(item.id)):
			n += 1
	return n


static func purchase(id: String) -> bool:
	if not unlocked(id) or at_cap(id) or not can_afford(id):
		return false
	GameState.add_cash(-cost(id))
	match id:
		"gloves":
			GameState.gloves_level += 1
	GameState.save_game()
	EventBus.meta_upgraded.emit(id, level(id))
	return true


static func bonus(id: String) -> float:
	return 1.0 + (level(id) - 1) * float(entry(id).effect_pct) / 100.0


## Juice scale for Perfect hits. Cash no longer uses this.
static func perfect_power() -> float:
	return bonus("gloves")


## Extra degrees on the Good gate from Wide Gate.
static func gate_bonus_deg() -> float:
	return float(clampi(GameState.gloves_level, 1, GameState.GLOVES_MAX) - 1) * GLOVES_DEG


## Perfect slice still tracks the Good gate; leftover callers use this.
static func perfect_window_mult() -> float:
	return 1.0
