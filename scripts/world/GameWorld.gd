extends Node2D
## Core session loop: spin → tap → grade → payout → DDA → stage/meta.

const RESPAWN_DELAY: float = 0.22
const REVIVE_STEP: float = 0.45
const END_BOOST_ENERGY: float = 0.16
const END_BOOST_COINS: float = 0.05
const FOCUS_PERFECT: float = 0.25
const FOCUS_GOOD: float = 0.08

@onready var arena: RingArena = $Arena
@onready var input_proc: InputProcessor = $InputProcessor
@onready var idle_timer: Timer = $IdleTick

var timing := TimingEngine.new()
var vr := VariableRatioSchedule.new()
var dda := DynamicDifficulty.new()
var zeigarnik := ZeigarnikTracker.new()
var _busy: bool = false
## Captured at run end so a Retry during the ad cannot zero the reward.
var _last_run_score: int = 0


func _ready() -> void:
	dda.seed_from_state()
	_apply_difficulty()
	input_proc.committed.connect(_on_commit)
	idle_timer.timeout.connect(_idle_tick)
	EventBus.revive_resolved.connect(_on_revive)
	EventBus.ad_finished.connect(_on_ad)
	if not GameState.run_active:
		start_run.call_deferred()


func _process(_delta: float) -> void:
	if not GameState.auto_tap or not GameState.run_active or _busy:
		return
	# Auto-Tap only fires inside the Good window: it keeps runs alive,
	# Perfects stay a manual skill reward.
	var err: float = absf(rad_to_deg(angle_difference(arena.pointer_angle, arena.target_angle)))
	if err <= timing.good_deg:
		_on_commit("auto", 0.0)


func start_run() -> void:
	GameState.reset_run()
	TimeScale.reset()
	_busy = false
	input_proc.reset_focus()
	input_proc.arm(true)
	arena.last_grade = ""
	arena.spinning = true
	arena.randomize_target(true)
	EventBus.run_started.emit()
	EventBus.multiplier_changed.emit(GameState.session_multiplier)
	EventBus.session_changed.emit()
	_push_zeigarnik()


func _on_commit(mode: String, _held: float) -> void:
	if _busy or not GameState.run_active:
		return
	_busy = true
	# Disarmed until respawn: the new target is ≥90° away, so any tap in between is a sure miss.
	input_proc.arm(false)
	arena.spinning = false
	var result: Dictionary = timing.evaluate(arena.pointer_angle, arena.target_angle)
	result["mode"] = mode
	arena.last_grade = String(result.grade_name)
	EventBus.tap_evaluated.emit(result)
	# DDA must see failures too, and must not learn from Auto-Tap.
	if mode != "auto":
		EventBus.dda_changed.emit(dda.record(result))
		_apply_difficulty()

	match int(result.grade):
		TimingEngine.Grade.PERFECT:
			_apply_success(result, 1.35)
			input_proc.add_focus(FOCUS_PERFECT)
			EventBus.perfect.emit(result)
			EventBus.juice_hit.emit("perfect", 1.0)
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
	timing.configure(w)
	arena.rpm = dda.rpm
	arena.windows = w


func _apply_success(result: Dictionary, grade_mult: float) -> void:
	var grade: TimingEngine.Grade = int(result.grade) as TimingEngine.Grade
	GameState.session_combo += 1
	GameState.session_hits += 1
	GameState.hits_in_stage += 1
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
	var payout: int = int(
		float(TimingEngine.grade_score(grade))
		* grade_mult
		* combo_mult
		* GameState.session_multiplier
		* GameState.global_multiplier()
	)
	GameState.session_score += payout
	GameState.add_energy(ceili(float(payout) * 0.12 * GameState.generator_rate()))
	GameState.add_coins(maxi(1, floori(payout / 20.0)))


func _after_hit() -> void:
	if GameState.hits_in_stage >= GameState.hits_needed:
		var bonus: int = 25 * GameState.current_stage
		GameState.add_energy(bonus)
		EventBus.stage_cleared.emit(GameState.current_stage, bonus)
		GameState.current_stage += 1
		GameState.hits_in_stage = 0
		GameState.hits_needed = mini(8 + GameState.current_stage, 14)
		if GameState.current_stage == 3 and not GameState.unlocked_themes.has("aurora"):
			GameState.unlocked_themes.append("aurora")
			GameState.save_game()
	EventBus.session_changed.emit()
	_push_zeigarnik()
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not GameState.run_active:
		return
	arena.randomize_target(false)
	arena.spinning = true
	_busy = false
	input_proc.arm(true)


func _fail_run(reason: String, result: Dictionary) -> void:
	input_proc.arm(false)
	arena.spinning = false
	_last_run_score = GameState.session_score
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
	TimeScale.reset()


func _on_revive(success: bool) -> void:
	if not success:
		_fail_run("near_miss", {})
		return
	GameState.revive_used = true
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
	arena.spinning = true
	_busy = false
	input_proc.arm(true)


func _on_ad(placement: String, rewarded: bool) -> void:
	if placement == "end_multiplier" and rewarded:
		_grant_end_boost()


func _grant_end_boost() -> void:
	GameState.add_energy(int(_last_run_score * END_BOOST_ENERGY))
	GameState.add_coins(int(_last_run_score * END_BOOST_COINS))


func _idle_tick() -> void:
	if GameState.run_active:
		return
	GameState.add_energy(ceili(2.0 * GameState.generator_rate()))
	_push_zeigarnik()


func _push_zeigarnik() -> void:
	EventBus.zeigarnik_updated.emit(zeigarnik.loops())
