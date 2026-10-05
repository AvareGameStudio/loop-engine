class_name MetaUpgrade
extends Node
## Idle meta loop. The Crew fills the stash only while the app is closed.
## Pro Gloves widen the Perfect slice and scale Perfect juice. The market sells both, in cash.
## Levels persist in GameState; economy math is static so UI can call it without a node.

signal produced(amount: int)

## Cash per second the crew steals while the app is closed, at level 1.
const PASSIVE_BASE: float = 0.67
## Cap so a week away does not dump a week's numbers onto the Claim screen.
const OFFLINE_CAP_SECONDS: int = 8 * 3600
## One minute of idle = a "full" bag. Zeigarnik teases this at 90%.
const STASH_FULL_SECONDS: float = 60.0

## `id` values are save keys. UI names live in translations (Crew / Pro Gloves).
const CATALOG := [
	{"id": "crew", "base_cost": 60, "growth": 1.35, "effect_pct": 25},
	{"id": "gloves", "base_cost": 80, "growth": 1.4, "effect_pct": 12},
]

## Pro Gloves: Perfect half-window grows this much per level (capped in GameWorld).
const GLOVES_WINDOW_PCT: float = 6.0


func _ready() -> void:
	# Foreground play, popups included, must not drip. Only a closed app does.
	set_process(false)
	accrue_offline()


func _notification(what: int) -> void:
	# Don't pop the stash over an active run or the player loses their tap.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and not GameState.run_active:
		accrue_offline()
		if GameState.unclaimed_cash > 0:
			EventBus.stash_ready.emit(GameState.unclaimed_cash)


## Credits time spent with the app closed. Returns cash added.
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
		GameState.add_stash(gain)
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
		"crew":
			return GameState.crew_level
		"gloves":
			return GameState.gloves_level
	return 1


static func cost(id: String) -> int:
	var item: Dictionary = entry(id)
	return int(float(item.base_cost) * pow(float(item.growth), level(id) - 1))


static func can_afford(id: String) -> bool:
	return GameState.cash >= cost(id)


static func affordable_count() -> int:
	var n: int = 0
	for item: Dictionary in CATALOG:
		if can_afford(String(item.id)):
			n += 1
	return n


static func purchase(id: String) -> bool:
	if not can_afford(id):
		return false
	GameState.add_cash(-cost(id))
	match id:
		"crew":
			GameState.crew_level += 1
		"gloves":
			GameState.gloves_level += 1
	GameState.save_game()
	EventBus.meta_upgraded.emit(id, level(id))
	return true


static func bonus(id: String) -> float:
	return 1.0 + (level(id) - 1) * float(entry(id).effect_pct) / 100.0


## Pro Gloves: score + juice scale for Perfect hits.
static func perfect_power() -> float:
	return bonus("gloves")


## Pro Gloves: multiplier on the Perfect half-window.
static func perfect_window_mult() -> float:
	return 1.0 + (GameState.gloves_level - 1) * GLOVES_WINDOW_PCT / 100.0


## Cash per second while idle (fills the stash, not the wallet).
static func passive_rate() -> float:
	return PASSIVE_BASE * bonus("crew")


## 0..1 fill of the stash bag. Caps at 0.9 unless actually overflowing.
static func stash_progress() -> float:
	var full: float = maxf(passive_rate() * STASH_FULL_SECONDS, 10.0)
	var raw: float = float(GameState.unclaimed_cash) / full
	if raw >= 1.0:
		return 1.0
	if raw > 0.9:
		return 0.9
	if raw <= 0.0:
		return 0.04
	return raw
