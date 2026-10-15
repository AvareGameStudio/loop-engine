class_name MetaUpgrade
extends Node
## Market upgrades. The Crew steals while the app is closed: about one heist's door payout
## per hour (x1.25 per level), up to 8 h, collected on the Welcome Back screen (2x with an ad).
## v1 paid $0.67/s into a hidden card button and nobody found it.
## Wide Gate adds degrees to the green Good arc. The market sells both, in cash.
## Levels persist in GameState; economy math is static so UI can call it without a node.

## Hours of theft the Crew banks at most; a night's sleep, so the morning open pays.
const OFFLINE_CAP_HOURS: float = 8.0
## Shorter absences pay nothing: no popup for a quick app switch.
const OFFLINE_MIN_SECONDS: int = 120

## `id` values are save keys. UI names live in translations (Crew / Wide Gate).
const CATALOG := [
	{"id": "crew", "base_cost": 120, "growth": 1.5, "effect_pct": 25},
	{"id": "gloves", "base_cost": 80, "growth": 1.4, "effect_pct": 12},
]

## Wide Gate: the green Good arc grows this many degrees per purchased level.
const GLOVES_DEG: float = 1.5


func _ready() -> void:
	set_process(false)
	accrue_offline()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		accrue_offline()


## Credits the gap since `last_seen_unix`. Returns cash added to the Crew's take.
func accrue_offline() -> int:
	# Tool scripts (sims, store shots) boot the game too; they are not a player coming back.
	var args := OS.get_cmdline_args()
	if args.has("-s") or args.has("--script"):
		return 0
	var now: int = int(Time.get_unix_time_from_system())
	var last: int = GameState.last_seen_unix
	GameState.last_seen_unix = now
	if last <= 0 or not GameState.crew_unlocked():
		return 0
	var dt: int = mini(now - last, int(OFFLINE_CAP_HOURS * 3600.0))
	if dt < OFFLINE_MIN_SECONDS:
		return 0
	var gain: int = floori(hourly_rate() * float(dt) / 3600.0)
	if gain <= 0:
		return 0
	GameState.unclaimed_cash += gain
	GameState.unclaimed_seconds += dt
	GameState.request_save()
	EventBus.offline_ready.emit(GameState.unclaimed_cash)
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


static func unlocked(id: String) -> bool:
	return id != "crew" or GameState.crew_unlocked()


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
		"crew":
			GameState.crew_level += 1
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


## One door's base payout x3 (a heist) at the current door, x1.25 per Crew level.
static func hourly_rate() -> float:
	return 3.0 * (40.0 + 12.0 * float(GameState.current_stage)) * bonus("crew")
