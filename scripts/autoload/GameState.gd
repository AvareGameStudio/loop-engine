extends Node
## Persistent meta-state, session flags, and save/load. Autoload.
## One level = one vault. The vault index is persistent: a bust retries the same
## vault, a crack moves to the next one, so the 200-door art progression is real.

const SAVE_PATH := "user://loop_engine_save.json"
const SAVE_VERSION := 5

## Alarm strikes before the cops arrive. Each Miss / Near-Miss adds one.
const ALARM_MAX: int = 3
## One heist is this many doors. The end card waits until the heist is done.
const DOORS_PER_HEIST: int = 3
## Every Nth heist is golden: wider gate, double loot, gold doors.
const GOLDEN_EVERY: int = 5
## After the first three heists, a shelf item unlocks every N heists.
const LOOT_EVERY: int = 3
## Wide Gate purchases stop here (level 1 is the free baseline).
const GLOVES_MAX: int = 5

## Vault type by first vault index. Replaces the abstract Neon/Aurora colour themes.
const VAULT_TYPE_BY_STAGE := {
	1: "piggy",
	3: "office",
	6: "bank",
	11: "museum",
	26: "casino",
	51: "fort",
	100: "moon",
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
var gloves_level: int = 1
## Unix time of last backgrounding.
var last_seen_unix: int = 0
var no_ads: bool = false
var auto_tap: bool = false
var auto_tap_unlocked: bool = false
var auto_tap_purchased: bool = false
var stages_cleared: int = 0
var lifetime_hits: int = 0
var cosmetics: PackedStringArray = PackedStringArray(["leather"])
var equipped_dial: String = "steel"
var equipped_gloves: String = "leather"

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
## Tools (ad capture, simulations) set this so they never touch the player's save.
var no_save: bool = false


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


func stamp_seen() -> void:
	last_seen_unix = int(Time.get_unix_time_from_system())
	request_save()


# --- Level curve -------------------------------------------------------------

## Heist index for a door. Door 1–3 = heist 1, 4–6 = heist 2.
static func heist_for(stage: int) -> int:
	return (maxi(stage, 1) - 1) / DOORS_PER_HEIST + 1


## 0, 1, or 2: which door of the current heist this stage is.
static func door_in_heist(stage: int) -> int:
	return (maxi(stage, 1) - 1) % DOORS_PER_HEIST


## How many doors are left in this heist, including the current door.
static func doors_left_in_heist(stage: int) -> int:
	return DOORS_PER_HEIST - door_in_heist(stage)


static func is_first_heist(stage: int) -> bool:
	return heist_for(stage) <= 1


## Pins a door needs. Heist 1 stays short; golden heists add two (cap 8).
static func pins_for(stage: int) -> int:
	var h: int = heist_for(stage)
	var pins: int = 3
	# Base stays at 4 from heist 2; door 3 adds one, golden one more. A real session ran
	# 26-38 s per heist at 5 base pins from heist 9; difficulty now comes from the dial.
	if h >= 2:
		pins = 4
	if door_in_heist(stage) == 0 and h <= 1:
		pins = 3
	elif door_in_heist(stage) >= 2:
		pins = mini(pins + 1, 6)
	# Golden is the breather: one extra pin, not two (two made it the longest heist, 27-37 s).
	if is_golden(stage):
		pins = mini(pins + 1, 8)
	return pins


## Vault tricks: one twist on the same tap. Each is introduced alone on its heist, then
## rotates with plain heists. Golden heists never carry one: they are the breather.
## slide = the gate creeps against the pick · double = two gates chained in one sweep ·
## dark = the gate only shows inside the pick's flashlight.
const TRICK_INTRO: Dictionary[int, String] = {4: "slide", 7: "double", 11: "dark"}


static func trick_for(stage: int) -> String:
	var h: int = heist_for(stage)
	if is_golden(stage):
		return ""
	if TRICK_INTRO.has(h):
		return TRICK_INTRO[h]
	var pool: Array[String] = [""]
	for intro: int in TRICK_INTRO:
		if h > intro:
			pool.append(TRICK_INTRO[intro])
	if pool.size() == 1:
		return ""
	return pool[h % pool.size()]


## The heist that introduces a trick opens the gate 2° so the new twist is learned, not punished.
static func is_trick_intro(stage: int) -> bool:
	return TRICK_INTRO.has(heist_for(stage)) and not is_golden(stage)


static func is_golden(stage: int) -> bool:
	# The daily Big Heist always plays as a golden vault.
	if GameState.daily_active:
		return true
	var h: int = heist_for(stage)
	return h > 0 and h % GOLDEN_EVERY == 0


## Sawtooth on the heist index so a golden heist breathes after a squeeze.
static func _heist_ease(heist: int) -> float:
	var base: float = _curve(heist, [[1, 0.0], [2, 0.06], [4, 0.2], [10, 0.42], [20, 0.66], [40, 0.86], [80, 1.0]])
	var slot: int = (maxi(heist, 1) - 1) % GOLDEN_EVERY
	# Gentler squeeze: at 0.12 / 0.18 heist 3 became the first wall (simulated casual players were
	# busted four times there, before the Market even opened).
	var tooth: float = [0.0, 0.02, 0.06, 0.12, -0.1][slot]
	return clampf(base + tooth, 0.0, 1.0)


## Dial speed in revolutions per second before DDA.
static func base_rpm(stage: int) -> float:
	return lerpf(0.38, 0.92, _heist_ease(heist_for(stage)))


## Good window half-angle in degrees before DDA. Golden heists open +3°.
static func base_good_deg(stage: int) -> float:
	var good: float = lerpf(20.0, 11.0, _heist_ease(heist_for(stage)))
	if is_golden(stage):
		good += 3.0
	if is_trick_intro(stage):
		good += 2.0
	# Dark hides most of the approach, so its gate is always 2 deg wider (sim: miss rate 1.5x plain).
	if trick_for(stage) == "dark":
		good += 2.0
	return good


## Direction flips from heist 2, and only on a new door (GameWorld).
static func flips_enabled(stage: int) -> bool:
	return heist_for(stage) >= 2


## Loot multiplier for a cracked door.
static func loot_mult(stage: int) -> float:
	if GameState.daily_active:
		return DAILY_LOOT_MULT
	if is_golden(stage):
		return 3.0 if GameState.glove_perk() == "royal" else 2.0
	return 1.0


# --- Glove perks -----------------------------------------------------------------
## Each glove does one small, readable thing; leather is the plain starter.
## latex: Perfect slice +10% · gold: pin cash +10% · neon: Hot Hands after 3 Perfects (not 4)
## skeleton: the first miss on each door doesn't sound the alarm · crimson: bribe countdown 1 s
## ice: dial 5% slower · royal: golden vaults pay x3 loot (not x2)
const GLOVE_PERFECT_MULT: float = 1.10
const GLOVE_CASH_MULT: float = 1.10
const GLOVE_HOT_STREAK: int = 3
const GLOVE_RPM_MULT: float = 0.95


func glove_perk() -> String:
	return equipped_gloves if equipped_gloves != "" else "leather"


# --- Daily Big Heist ------------------------------------------------------------
## Once a day (UTC) after the first heist: one golden door, 5x loot, a guaranteed glove
## (or a cash pile once every glove is owned). Retryable until cracked; it does not move
## the career door index.
const DAILY_LOOT_MULT: float = 5.0
const DAILY_CASH_FALLBACK: int = 500
var daily_active: bool = false
var daily_last_day: int = -1


static func today() -> int:
	return int(Time.get_unix_time_from_system()) / 86400


func daily_available() -> bool:
	return complete_heists() >= 1 and daily_last_day != today()


## Called when the daily door cracks. Returns the glove id granted, or "" for the cash pile.
func complete_daily() -> String:
	daily_last_day = today()
	var glove: String = grant_random_glove()
	if glove == "":
		add_cash(DAILY_CASH_FALLBACK)
	request_save()
	return glove


## Cash a seated pin drops. Perfects pay a third more. No hidden score.
static func pin_cash(stage: int, perfect: bool) -> int:
	var n: int = 2 + maxi(stage, 1) / 5
	if perfect:
		n = maxi(n + 1, ceili(float(n) * 1.35))
	return maxi(1, int(float(n) * loot_mult(stage)))


## Room color behind the door. Read as location, not as a label.
static func wall_color(stage: int) -> Color:
	if is_golden(stage):
		return Color(0.16, 0.12, 0.05, 1.0)
	match vault_type(stage):
		"office":
			return Color(0.14, 0.16, 0.18, 1.0)
		"bank":
			return Color(0.08, 0.12, 0.2, 1.0)
		"museum":
			return Color(0.18, 0.08, 0.12, 1.0)
		"casino":
			return Color(0.06, 0.16, 0.1, 1.0)
		"fort":
			return Color(0.16, 0.14, 0.1, 1.0)
		"moon":
			return Color(0.1, 0.08, 0.16, 1.0)
		_:
			return Color(0.22, 0.1, 0.14, 1.0)


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


func complete_heists() -> int:
	return stages_cleared / DOORS_PER_HEIST


## Meta opens one system at a time so the first session is dial + hideout only.
## The Market (Wide Gate, glove skins) appears on the card that closes heist 3.
const MARKET_UNLOCK_AFTER: int = 3


func market_unlocked() -> bool:
	return complete_heists() >= MARKET_UNLOCK_AFTER



## Free shelf items: one per heist for the first LOOT_FREE heists (onboarding); after that
## every item is bought in the hideout shop. Simulated: free drops every 3 heists filled the
## shelf by heist 21 and the cash pile had nothing left to buy.
const LOOT_FREE: int = 3


static func loot_count_at(cleared: int) -> int:
	return mini(cleared / DOORS_PER_HEIST, mini(LOOT_FREE, LOOT_ITEMS.size()))


## Save v3 dropped an item every 3 heists after the first three; keep what those earned.
static func _legacy_loot_count(cleared: int) -> int:
	var heists: int = cleared / DOORS_PER_HEIST
	if heists <= 3:
		return mini(heists, LOOT_ITEMS.size())
	return mini(3 + (heists - 3) / LOOT_EVERY, LOOT_ITEMS.size())


func loot_unlocked_count() -> int:
	return mini(loot_count_at(stages_cleared) + loot_bought, LOOT_ITEMS.size())


# --- Hideout shop: the cash sink ------------------------------------------------
## The next item can always be bought outright; every few heists one still drops free.
## Prices climb x1.55 per shelf slot (slot 3 ~ $1.5k, slot 11 ~ $50k), and every owned item
## adds LOOT_BONUS_STEP to all cash (12 items = +24%).
const LOOT_PRICE_BASE: float = 400.0
const LOOT_PRICE_GROWTH: float = 1.6
const LOOT_BONUS_STEP: float = 0.02
var loot_bought: int = 0


static func loot_price(slot: int) -> int:
	return int(round(LOOT_PRICE_BASE * pow(LOOT_PRICE_GROWTH, slot) / 50.0)) * 50


func next_loot_price() -> int:
	var slot: int = loot_unlocked_count()
	return loot_price(slot) if slot < LOOT_ITEMS.size() else 0


func can_buy_loot() -> bool:
	return loot_unlocked_count() < LOOT_ITEMS.size() and cash >= next_loot_price()


## Buys the next shelf item. Returns its id, or "" when it can't.
func buy_next_loot() -> String:
	if not can_buy_loot():
		return ""
	var id: String = LOOT_ITEMS[loot_unlocked_count()]
	add_cash(-next_loot_price())
	loot_bought += 1
	request_save()
	EventBus.loot_unlocked.emit(id)
	return id


func loot_bonus() -> float:
	return 1.0 + LOOT_BONUS_STEP * float(loot_unlocked_count())


## 0..1 toward the next hideout item. 1.0 only when the shelf is full.
func loot_progress() -> float:
	if loot_unlocked_count() >= LOOT_ITEMS.size():
		return 1.0
	# Past the free drops the ring fills with cash toward the next item's price.
	if complete_heists() >= LOOT_FREE:
		return clampf(float(cash) / float(maxi(next_loot_price(), 1)), 0.0, 1.0)
	var heists: int = complete_heists()
	var door_frac: float = float(stages_cleared % DOORS_PER_HEIST) / float(DOORS_PER_HEIST)
	if heists < 3:
		return door_frac
	var into: int = (heists - 3) % LOOT_EVERY
	return (float(into) + door_frac) / float(LOOT_EVERY)


func next_loot_id() -> String:
	var n := loot_unlocked_count()
	if n >= LOOT_ITEMS.size():
		return ""
	return LOOT_ITEMS[n]


## Silhouette in the door window. Gold bars once the shelf is full.
func window_loot_id() -> String:
	var id := next_loot_id()
	return id if id != "" else "gold"


## Doors toward the next shelf item, as (done, need).
func loot_step() -> Vector2i:
	if loot_unlocked_count() >= LOOT_ITEMS.size():
		return Vector2i(1, 1)
	if complete_heists() < 3:
		return Vector2i(stages_cleared % DOORS_PER_HEIST, DOORS_PER_HEIST)
	var span: int = LOOT_EVERY * DOORS_PER_HEIST
	var into: int = (stages_cleared - 3 * DOORS_PER_HEIST) % span
	return Vector2i(into, span)


## True when the door that just cracked completed a shelf item.
func loot_just_unlocked() -> bool:
	if stages_cleared <= 0:
		return false
	# Bought items fill the shelf ahead of the free drops; a free drop on a full shelf is nothing.
	var before: int = mini(loot_count_at(stages_cleared - 1) + loot_bought, LOOT_ITEMS.size())
	return loot_unlocked_count() > before


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
## Heist 1 never catches: the guard still walks in, the run does not end.
func raise_alarm() -> bool:
	session_alarm = mini(session_alarm + 1, ALARM_MAX)
	EventBus.alarm_changed.emit(session_alarm, ALARM_MAX)
	if is_first_heist(current_stage):
		return false
	return session_alarm >= ALARM_MAX


func clear_alarm() -> void:
	session_alarm = 0
	EventBus.alarm_changed.emit(session_alarm, ALARM_MAX)


## A door cracked without a single strike: one lamp goes out and the guard settles a step.
## Rewards clean play and stops one bad door from dooming the rest of the heist.
func lower_alarm() -> void:
	if session_alarm <= 0:
		return
	session_alarm -= 1
	EventBus.alarm_changed.emit(session_alarm, ALARM_MAX)


## Mercy: the same door lost twice in a row opens its gate this much wider until it cracks.
const MERCY_AFTER_BUSTS: int = 2
const MERCY_GOOD_DEG: float = 3.0
var _bust_stage: int = 0
var _bust_streak: int = 0


func note_bust() -> void:
	_bust_streak = _bust_streak + 1 if _bust_stage == current_stage else 1
	_bust_stage = current_stage


func mercy_deg() -> float:
	if _bust_stage == current_stage and _bust_streak >= MERCY_AFTER_BUSTS:
		return MERCY_GOOD_DEG
	return 0.0


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


## Next door of the same heist. Combo and alarm stay; pins reset.
func begin_door() -> void:
	hits_in_stage = 0
	hits_needed = pins_for(current_stage)
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
		"gloves_level": gloves_level,
		"last_seen_unix": last_seen_unix,
		"no_ads": no_ads,
		"auto_tap": auto_tap,
		"auto_tap_purchased": auto_tap_purchased,
		"stages_cleared": stages_cleared,
		"daily_last_day": daily_last_day,
		"loot_bought": loot_bought,
		"lifetime_hits": lifetime_hits,
		"cosmetics": Array(cosmetics),
		"equipped_dial": equipped_dial,
		"equipped_gloves": equipped_gloves,
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
	gloves_level = maxi(int(data.get("gloves_level", data.get("global_mult_level", 1))), 1)
	# v5 retired the Crew (offline stash): whatever it stole goes straight into the wallet.
	cash += maxi(int(data.get("unclaimed_cash", data.get("unclaimed_energy", 0))), 0)
	last_seen_unix = int(data.get("last_seen_unix", 0))
	no_ads = bool(data.get("no_ads", false))
	lifetime_hits = int(data.get("lifetime_hits", 0))
	stages_cleared = int(data.get("stages_cleared", 0))
	daily_last_day = int(data.get("daily_last_day", -1))
	loot_bought = int(data.get("loot_bought", 0))
	if int(data.get("v", 0)) < 4:
		loot_bought = maxi(0, _legacy_loot_count(stages_cleared) - loot_count_at(stages_cleared))
	auto_tap_purchased = bool(data.get("auto_tap_purchased", false))
	# Auto-Tap is an IAP only now. The old first-ring reward no longer grants it.
	auto_tap_unlocked = auto_tap_purchased
	auto_tap = bool(data.get("auto_tap", false)) and auto_tap_unlocked
	dda_rpm = float(data.get("dda_rpm", 0.55))
	dda_perfect_deg = float(data.get("dda_perfect_deg", 7.0))
	dda_good_deg = float(data.get("dda_good_deg", 16.0))
	dda_near_deg = float(data.get("dda_near_deg", 22.0))
	var skins: Array = data.get("cosmetics", ["leather"])
	cosmetics = PackedStringArray(skins)
	equipped_dial = String(data.get("equipped_dial", "steel"))
	equipped_gloves = String(data.get("equipped_gloves", ""))
	_migrate_gloves()


const GLOVE_IDS: PackedStringArray = [
	"leather", "latex", "gold", "neon", "skeleton", "crimson", "ice", "royal",
]
const GLOVE_COST := {
	"leather": 0, "latex": 150, "gold": 400, "neon": 350, "crimson": 280, "ice": 320,
}
const GLOVE_COLOR := {
	"leather": Color(0.42, 0.24, 0.12, 1.0),
	"latex": Color(0.08, 0.08, 0.09, 1.0),
	"gold": Color(0.92, 0.72, 0.22, 1.0),
	"neon": Color(0.2, 0.95, 0.85, 1.0),
	"skeleton": Color(0.9, 0.88, 0.8, 1.0),
	"crimson": Color(0.62, 0.1, 0.16, 1.0),
	"ice": Color(0.7, 0.88, 1.0, 1.0),
	"royal": Color(0.48, 0.28, 0.82, 1.0),
}
const DIAL_COST := {"steel": 0, "gold": 200, "obsidian": 600}


func _migrate_gloves() -> void:
	var mapped: PackedStringArray = PackedStringArray()
	for id in cosmetics:
		var key: String = String(id)
		match key:
			"steel", "default":
				key = "leather"
			"obsidian":
				key = "neon"
		if GLOVE_IDS.has(key) and not mapped.has(key):
			mapped.append(key)
	if mapped.is_empty():
		mapped.append("leather")
	if not mapped.has("leather"):
		mapped.insert(0, "leather")
	cosmetics = mapped
	if equipped_gloves == "" or not GLOVE_IDS.has(equipped_gloves):
		match equipped_dial:
			"gold":
				equipped_gloves = "gold"
			"obsidian":
				equipped_gloves = "neon"
			_:
				equipped_gloves = "leather"
	if not cosmetics.has(equipped_gloves):
		cosmetics.append(equipped_gloves)


static func glove_cost(id: String) -> int:
	return int(GLOVE_COST.get(id, 0))


static func glove_tint(id: String) -> Color:
	if GLOVE_COLOR.has(id):
		return GLOVE_COLOR[id]
	return GLOVE_COLOR["leather"]


func owns_glove(id: String) -> bool:
	return id == "leather" or cosmetics.has(id)


func unowned_gloves() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id in GLOVE_IDS:
		if not owns_glove(id):
			out.append(id)
	return out


func buy_glove(id: String) -> bool:
	# Owned first: skeleton / royal have no price (drops only) but must still be equippable.
	if owns_glove(id):
		equip_glove(id)
		return true
	if not GLOVE_COST.has(id):
		return false
	var cost: int = glove_cost(id)
	if cash < cost:
		return false
	add_cash(-cost)
	if not cosmetics.has(id):
		cosmetics.append(id)
	equip_glove(id)
	save_game()
	return true


func grant_glove(id: String) -> bool:
	if not GLOVE_IDS.has(id):
		return false
	if not cosmetics.has(id):
		cosmetics.append(id)
	equip_glove(id)
	save_game()
	EventBus.glove_granted.emit(id)
	return true


func grant_random_glove() -> String:
	var pool: PackedStringArray = unowned_gloves()
	if pool.is_empty():
		return ""
	var id: String = pool[randi() % pool.size()]
	grant_glove(id)
	return id


func should_offer_glove() -> bool:
	if unowned_gloves().is_empty():
		return false
	var heists: int = complete_heists()
	return heists > 0 and heists % 4 == 0


func equip_glove(id: String) -> void:
	if not owns_glove(id):
		return
	equipped_gloves = id
	EventBus.cosmetic_equipped.emit(id)
	request_save()


static func dial_cost(id: String) -> int:
	return int(DIAL_COST.get(id, 0))


func owns_dial(id: String) -> bool:
	return id == "steel" or id == equipped_dial


func buy_dial(id: String) -> bool:
	return buy_glove("gold" if id == "gold" else ("neon" if id == "obsidian" else "leather"))


func equip_dial(id: String) -> void:
	equipped_dial = id
	request_save()


func request_save() -> void:
	if _save_pending or no_save:
		return
	_save_pending = true
	get_tree().create_timer(SAVE_DEBOUNCE, true, false, true).timeout.connect(save_game)


func save_game() -> void:
	_save_pending = false
	if no_save:
		return
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
