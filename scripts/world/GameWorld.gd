extends Node2D
## Core level loop: spin → tap → grade → pin seats → last pin cracks the vault → loot → next vault.
## One run = one vault. A Miss raises the alarm; the third strike brings the cops.

const RESPAWN_DELAY: float = 0.22
## Real seconds between the last pin and the end-of-vault card: door flies, loot rains.
const CRACK_BEAT: float = 1.25
const REVIVE_STEP: float = 0.45
## DDA may only bend the stage curve this far either way.
const DDA_BAND: float = 0.15
const NEAR_BAND_DEG: float = 5.0

@onready var arena: RingArena = $Arena
@onready var input_proc: InputProcessor = $InputProcessor
@onready var meta: MetaUpgrade = $MetaUpgrade

var timing := TimingEngine.new()
var vr := VariableRatioSchedule.new()
var dda := DynamicDifficulty.new()
var zeigarnik := ZeigarnikTracker.new()
var _busy: bool = false
## Cash actually banked this vault. The end ad adds twice this (3x total).
var _run_cash: int = 0
## Frozen at run end so Retry during the ad cannot zero the 3x grant.
var _boost_cash: int = 0


func _ready() -> void:
	dda.seed_from_state()
	_apply_difficulty()
	input_proc.arm(false)
	input_proc.committed.connect(_on_commit)
	EventBus.revive_resolved.connect(_on_revive)
	EventBus.ad_finished.connect(_on_ad)
	if not GameState.run_active:
		start_run.call_deferred()


func _process(delta: float) -> void:
	if not GameState.run_active or _busy:
		return
	var err: float = absf(rad_to_deg(angle_difference(arena.pointer_angle, arena.target_angle)))
	# A single frame of travel can be wider than a window, so both gates below decide from
	# where the needle will be next frame. Nothing may depend on landing inside a window.
	var next_err: float = _next_error(delta)
	var closest: bool = next_err > err
	# Early tap during respawn: fire at the Good gate, or at the closest approach if the
	# needle is about to sweep past without ever entering it.
	if input_proc.peek_buffer() and (err <= timing.good_deg or closest):
		input_proc.take_buffer()
		_on_commit("buffer", 0.0)
		return
	if arena.spinning and zeigarnik.passed_pin(err, float(arena.windows.get("near", 22.0))):
		TimeScale.pulse_slowmo(0.25, 0.3)
		EventBus.juice_hit.emit("tension", 1.0)
	if not GameState.auto_tap or not arena.spinning or err > timing.good_deg:
		return
	# The player owns the Perfect slice, so Auto-Tap waits for the way out of the gate.
	# Unless this is the last frame inside it: keeping the run alive comes first.
	var past_perfect: bool = closest and err > timing.perfect_deg
	var last_chance: bool = next_err > timing.good_deg
	if past_perfect or last_chance:
		_on_commit("auto", 0.0)


## Where the pointer error lands next frame, mirroring how RingArena advances it.
func _next_error(delta: float) -> float:
	var step: float = arena.direction * arena.rpm * TAU * minf(delta, 1.0 / 30.0)
	return absf(rad_to_deg(angle_difference(arena.pointer_angle + step, arena.target_angle)))


func start_run() -> void:
	GameState.stamp_seen()
	GameState.reset_run()
	TimeScale.reset()
	_busy = false
	_run_cash = 0
	input_proc.clear_buffer()
	input_proc.arm(true)
	arena.last_grade = ""
	arena.flips_enabled = GameState.flips_enabled(GameState.current_stage)
	arena.set_vault(GameState.current_stage)
	_apply_difficulty()
	arena.spinning = true
	arena.randomize_target(true)
	zeigarnik.arm_gate()
	EventBus.run_started.emit()
	EventBus.alarm_changed.emit(GameState.session_alarm, GameState.ALARM_MAX)
	EventBus.multiplier_changed.emit(GameState.session_multiplier)
	EventBus.session_changed.emit()


func _on_commit(mode: String, _held: float) -> void:
	if _busy or not GameState.run_active:
		return
	_busy = true
	zeigarnik.note_tap()
	input_proc.clear_buffer()
	# Disarmed until respawn: the new target is ≥90° away, so any tap in between is a sure miss.
	input_proc.arm(false)
	arena.spinning = false
	var result: Dictionary = timing.evaluate(arena.pointer_angle, arena.target_angle, GameState.session_combo)
	result["mode"] = mode
	arena.last_grade = String(result.grade_name)
	EventBus.tap_evaluated.emit(result)
	# DDA must see failures too, and must not learn from Auto-Tap or the early-tap buffer.
	if mode != "auto" and mode != "buffer":
		EventBus.dda_changed.emit(dda.record(result))
		_apply_difficulty()

	match int(result.grade):
		TimingEngine.Grade.PERFECT:
			_apply_success(result, 1.35)
			EventBus.perfect.emit(result)
			EventBus.juice_hit.emit("perfect", MetaUpgrade.perfect_power())
		TimingEngine.Grade.GOOD:
			_apply_success(result, 1.0)
			EventBus.juice_hit.emit("good", 0.7)
		TimingEngine.Grade.NEAR_MISS:
			EventBus.near_miss.emit(result)
			EventBus.juice_hit.emit("near_miss", 1.0)
			_strike(result)
			return
		_:
			EventBus.miss.emit(result)
			EventBus.juice_hit.emit("miss", 1.0)
			_strike(result)
			return
	_after_hit()


## Stage curve first, DDA as a ±15% bend on top, Pro Gloves widen the Perfect slice.
func _apply_difficulty() -> void:
	var stage: int = GameState.current_stage
	var w: Dictionary = dda.windows()
	var rpm_bend: float = clampf(dda.rpm / 0.55, 1.0 - DDA_BAND, 1.0 + DDA_BAND)
	var win_bend: float = clampf(float(w["perfect"]) / 7.0, 1.0 - DDA_BAND, 1.0 + DDA_BAND)
	var good: float = GameState.base_good_deg(stage) * win_bend
	var perfect: float = clampf(good * 0.42 * MetaUpgrade.perfect_window_mult(), 3.5, good * 0.7)
	var windows := {
		"good": good,
		"perfect": perfect,
		"near": good + NEAR_BAND_DEG,
	}
	timing.configure(windows)
	arena.rpm = clampf(GameState.base_rpm(stage) * rpm_bend, dda.rpm_min, dda.rpm_max)
	arena.windows = windows


func _apply_success(result: Dictionary, grade_mult: float) -> void:
	var grade: TimingEngine.Grade = int(result.grade) as TimingEngine.Grade
	GameState.session_combo += 1
	GameState.session_hits += 1
	GameState.hits_in_stage += 1
	GameState.note_landed_hit()
	if grade == TimingEngine.Grade.PERFECT:
		GameState.session_perfects += 1
	var combo_mult: float = 1.0 + float(mini(GameState.session_combo, 25)) * 0.06
	var drop: Dictionary = vr.register_success()
	if bool(drop.get("triggered", false)):
		GameState.session_multiplier = float(drop.multiplier)
		EventBus.jackpot.emit(float(drop.multiplier), String(drop.label))
		EventBus.juice_hit.emit("jackpot", 1.2)
	else:
		GameState.session_multiplier = maxf(1.0, GameState.session_multiplier * 0.92)
		if GameState.session_multiplier < 1.08:
			GameState.session_multiplier = 1.0
	EventBus.multiplier_changed.emit(GameState.session_multiplier)
	EventBus.vr_tension.emit(vr.peek_tension())
	# Pro Gloves are felt on Perfects (score + juice). Other grades get a whisper of it.
	var power: float = MetaUpgrade.perfect_power()
	var power_mult: float = power if grade == TimingEngine.Grade.PERFECT else lerpf(1.0, power, 0.15)
	var payout: int = int(
		float(TimingEngine.grade_score(grade))
		* grade_mult
		* combo_mult
		* GameState.session_multiplier
		* power_mult
	)
	GameState.session_score += payout
	# Each seated pin drops a little cash; the vault itself pays on the last pin.
	_bank_cash(maxi(1, ceili(float(payout) * 0.04 * GameState.loot_mult(GameState.current_stage))))


func _after_hit() -> void:
	var cleared := GameState.hits_in_stage >= GameState.hits_needed
	EventBus.session_changed.emit()
	if cleared:
		_crack_vault()
		return
	# Real seconds: ignore_time_scale so the armed window cannot stretch.
	await get_tree().create_timer(RESPAWN_DELAY, true, false, true).timeout
	if not GameState.run_active:
		return
	TimeScale.set_slowmo(1.0)
	arena.randomize_target(false)
	_begin_spin()


## Last pin: the door flies, the loot rains, then the card. The vault index moves forward now
## so the next door is already painted when the card closes.
func _crack_vault() -> void:
	var stage: int = GameState.current_stage
	var loot: int = int(float(40 + 12 * stage) * GameState.loot_mult(stage))
	_bank_cash(loot)
	GameState.note_stage_cleared()
	arena.warm_shell()
	EventBus.stage_cleared.emit(stage, loot)
	# HUD already reads the next vault number behind the card; the painted door matches it.
	EventBus.session_changed.emit()
	if GameState.loot_just_unlocked():
		EventBus.loot_unlocked.emit(GameState.LOOT_ITEMS[GameState.loot_unlocked_count() - 1])
	await get_tree().create_timer(CRACK_BEAT, true, false, true).timeout
	_finish_run("cracked", {})


## One alarm strike. The third brings the cops: bribe (rewarded ad) or get caught.
func _strike(result: Dictionary) -> void:
	var caught: bool = GameState.raise_alarm()
	# Instant deaths were persisting a too-hard DDA profile and making the
	# next run feel broken (10° window at 0.73 rps, one miss → game over).
	if caught and GameState.session_hits <= 1:
		dda.forgive()
		_apply_difficulty()
	if caught:
		input_proc.arm(false)
		EventBus.revive_offered.emit(result)
		return
	# Pin ejects, dial jams for a beat, then the same vault keeps spinning.
	break_combo()
	await get_tree().create_timer(RESPAWN_DELAY * 2.0, true, false, true).timeout
	if not GameState.run_active:
		return
	arena.last_grade = ""
	arena.randomize_target(false)
	_begin_spin()


func _finish_run(reason: String, result: Dictionary) -> void:
	input_proc.arm(false)
	arena.spinning = false
	_boost_cash = _run_cash
	GameState.end_run()
	if GameState.no_ads:
		_grant_end_boost()
	EventBus.run_ended.emit(reason, {
		"score": GameState.session_score,
		"combo": GameState.session_combo,
		"hits": GameState.session_hits,
		"stage": GameState.current_stage - (1 if reason == "cracked" else 0),
		"cash": _run_cash,
		"result": result,
	})
	_busy = false
	input_proc.clear_buffer()
	TimeScale.reset()
	# Record the streak in end_run before this zeroes the counter.
	break_combo(false)


func _on_revive(success: bool) -> void:
	if not success:
		_finish_run("caught", {})
		return
	GameState.revive_used = true
	GameState.clear_alarm()
	break_combo()
	TimeScale.reset()
	arena.last_grade = ""
	arena.randomize_target(false)
	# Grace countdown in real time: the pointer would otherwise resume the instant the popup closes.
	for step in [3, 2, 1]:
		EventBus.countdown.emit(step)
		await get_tree().create_timer(REVIVE_STEP, true, false, true).timeout
		if not GameState.run_active:
			return
	EventBus.countdown.emit(0)
	_begin_spin()


func _on_ad(placement: String, rewarded: bool) -> void:
	if placement == "end_multiplier" and rewarded:
		_grant_end_boost()


func _begin_spin() -> void:
	zeigarnik.arm_gate()
	arena.spinning = true
	_busy = false
	input_proc.arm(true)


## Adds twice the vault's banked cash. The player already holds 1x, so this makes 3x.
func _grant_end_boost() -> void:
	var cash: int = _boost_cash
	_boost_cash = 0
	if cash > 0:
		GameState.add_cash(cash * 2)


func _bank_cash(amount: int) -> void:
	if amount <= 0:
		return
	_run_cash += amount
	GameState.add_cash(amount)


## Zeroes the live combo after a strike, a bust, or a bribe.
func break_combo(refresh_hud: bool = true) -> void:
	if GameState.session_combo >= 2:
		EventBus.juice_hit.emit("combo_break", 1.0)
	if GameState.session_combo == 0:
		return
	GameState.session_combo = 0
	if refresh_hud:
		EventBus.session_changed.emit()
