extends Node2D
## Core session loop: spin → tap → grade → payout → DDA → stage/meta.

const RESPAWN_DELAY: float = 0.22
const VAULT_BEAT: float = 0.55
const REVIVE_STEP: float = 0.45
const FOCUS_PERFECT: float = 0.25
const FOCUS_GOOD: float = 0.08

@onready var arena: RingArena = $Arena
@onready var input_proc: InputProcessor = $InputProcessor
@onready var meta: MetaUpgrade = $MetaUpgrade

var timing := TimingEngine.new()
var vr := VariableRatioSchedule.new()
var dda := DynamicDifficulty.new()
var zeigarnik := ZeigarnikTracker.new()
var _busy: bool = false
## Energy and coins actually banked this run. The end ad adds twice this (3x total).
var _run_energy: int = 0
var _run_coins: int = 0
## Frozen at run end so Retry during the ad cannot zero the 3x grant.
var _boost_energy: int = 0
var _boost_coins: int = 0


func _ready() -> void:
	dda.seed_from_state()
	_apply_difficulty()
	input_proc.arm(false)
	input_proc.committed.connect(_on_commit)
	if meta:
		meta.produced.connect(func(_amount: int) -> void: _push_zeigarnik())
	EventBus.meta_upgraded.connect(func(_stat: String, _level: int) -> void: _push_zeigarnik())
	EventBus.revive_resolved.connect(_on_revive)
	EventBus.ad_finished.connect(_on_ad)
	# Never block the core loop on the vault. A missing Claim popup used to
	# leave the ring spinning with taps ignored (run_active == false).
	if not GameState.run_active:
		start_run.call_deferred()
	# Cold-start vault stays a HUD peek; the full sheet waits for run-over.


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
	_run_energy = 0
	_run_coins = 0
	input_proc.reset_focus()
	input_proc.clear_buffer()
	input_proc.arm(true)
	arena.last_grade = ""
	arena.spinning = true
	_apply_difficulty()
	arena.randomize_target(true)
	zeigarnik.arm_gate()
	EventBus.run_started.emit()
	EventBus.multiplier_changed.emit(GameState.session_multiplier)
	EventBus.session_changed.emit()
	_push_zeigarnik()


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
			input_proc.add_focus(FOCUS_PERFECT)
			EventBus.perfect.emit(result)
			EventBus.juice_hit.emit("perfect", MetaUpgrade.perfect_power())
		TimingEngine.Grade.GOOD:
			_apply_success(result, 1.0)
			input_proc.add_focus(FOCUS_GOOD)
			EventBus.juice_hit.emit("good", 0.7)
		TimingEngine.Grade.NEAR_MISS:
			EventBus.near_miss.emit(result)
			EventBus.juice_hit.emit("near_miss", 1.0)
			EventBus.revive_offered.emit(result)
			return
		_:
			EventBus.miss.emit(result)
			EventBus.juice_hit.emit("miss", 1.0)
			_fail_run("miss", result)
			return
	_after_hit()


func _apply_difficulty() -> void:
	var w: Dictionary = dda.windows()
	var pressure := float(maxi(GameState.current_stage - 1, 0))
	var shrink := clampf(1.0 - pressure * 0.05, 0.74, 1.0)
	w["good"] = maxf(float(w["good"]) * shrink, 8.0)
	w["perfect"] = clampf(float(w["perfect"]) * shrink, 3.5, float(w["good"]) * 0.55)
	var near_band: float = float(dda.windows()["near"]) - float(dda.windows()["good"])
	w["near"] = float(w["good"]) + maxf(near_band * shrink, 3.0)
	timing.configure(w)
	arena.rpm = clampf(dda.rpm * (1.0 + pressure * 0.07), dda.rpm_min, dda.rpm_max)
	arena.windows = w


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
	# Perfect Power is felt on Perfects (score + juice). Other grades get a whisper of it.
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
	_bank_energy(ceili(float(payout) * 0.12 * MetaUpgrade.generator_rate()))
	_bank_coins(maxi(1, floori(payout / 20.0)))


func _after_hit() -> void:
	var cleared := GameState.hits_in_stage >= GameState.hits_needed
	if cleared:
		var bonus: int = 25 * GameState.current_stage
		var purse: int = 15 * GameState.current_stage
		_bank_energy(bonus)
		_bank_coins(purse)
		GameState.note_stage_cleared()
		EventBus.stage_cleared.emit(GameState.current_stage, bonus)
		GameState.current_stage += 1
		GameState.hits_in_stage = 0
		GameState.hits_needed = mini(8 + GameState.current_stage, 14)
		GameState.unlock_theme_for_stage(GameState.current_stage)
		_apply_difficulty()
		arena.mark_phase()
	EventBus.session_changed.emit()
	_push_zeigarnik()
	# Bake the next door while the needle is stopped, so the hitch is not the first spin frame.
	if cleared:
		arena.warm_shell()
	# Real seconds: ignore_time_scale so unlock slow-mo cannot stretch the armed window.
	await get_tree().create_timer(VAULT_BEAT if cleared else RESPAWN_DELAY, true, false, true).timeout
	if not GameState.run_active:
		return
	TimeScale.set_slowmo(1.0)
	arena.randomize_target(false)
	_begin_spin()


func _fail_run(reason: String, result: Dictionary) -> void:
	input_proc.arm(false)
	arena.spinning = false
	# Instant deaths were persisting a too-hard DDA profile and making the
	# next run feel broken (10° window at 0.73 rps, one miss → game over).
	if GameState.session_hits <= 2:
		dda.forgive()
		_apply_difficulty()
	_boost_energy = _run_energy
	_boost_coins = _run_coins
	GameState.end_run()
	if GameState.no_ads:
		_grant_end_boost()
	_push_zeigarnik()
	EventBus.run_ended.emit(reason, {
		"score": GameState.session_score,
		"combo": GameState.session_combo,
		"hits": GameState.session_hits,
		"result": result,
	})
	_busy = false
	input_proc.clear_buffer()
	TimeScale.reset()
	# Record the streak in end_run before this zeroes the counter.
	# Leave the HUD number alone; the run-over sheet already shows it.
	break_combo(false)


func _on_revive(success: bool) -> void:
	if not success:
		_fail_run("near_miss", {})
		return
	GameState.revive_used = true
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


## Adds twice the run's banked currencies. The player already holds 1x, so this makes 3x.
func _grant_end_boost() -> void:
	var energy: int = _boost_energy
	var coins: int = _boost_coins
	_boost_energy = 0
	_boost_coins = 0
	if energy > 0:
		GameState.add_energy(energy * 2)
	if coins > 0:
		GameState.add_coins(coins * 2)


func _bank_energy(amount: int) -> void:
	if amount <= 0:
		return
	_run_energy += amount
	GameState.add_energy(amount)


func _bank_coins(amount: int) -> void:
	if amount <= 0:
		return
	_run_coins += amount
	GameState.add_coins(amount)


## Zeroes the live combo after a death has already recorded it, or when a revive continues the run.
func break_combo(refresh_hud: bool = true) -> void:
	if GameState.session_combo >= 2:
		EventBus.juice_hit.emit("combo_break", 1.0)
	if GameState.session_combo == 0:
		return
	GameState.session_combo = 0
	if refresh_hud:
		EventBus.session_changed.emit()


func _push_zeigarnik() -> void:
	EventBus.zeigarnik_updated.emit(zeigarnik.loops())
