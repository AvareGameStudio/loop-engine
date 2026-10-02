extends Node2D
## Core session loop: spin → tap → grade → payout → DDA → stage/meta.

@onready var arena: RingArena = $Arena
@onready var input_proc: InputProcessor = $InputProcessor
@onready var idle_timer: Timer = $IdleTick

var timing := TimingEngine.new()
var vr := VariableRatioSchedule.new()
var dda := DynamicDifficulty.new()
var _busy := false
var _auto_cd := 0.0


func _ready() -> void:
	dda.seed_from_state()
	timing.configure(dda.windows())
	arena.rpm = dda.rpm
	arena.windows = dda.windows()
	input_proc.committed.connect(_on_commit)
	idle_timer.timeout.connect(_idle_tick)
	EventBus.revive_resolved.connect(_on_revive)
	EventBus.ad_finished.connect(_on_ad)
	if not GameState.run_active:
		call_deferred("start_run")


func _process(delta: float) -> void:
	if GameState.auto_tap and GameState.run_active and not _busy:
		_auto_cd -= delta
		if _auto_cd <= 0.0:
			_auto_cd = 0.42 / max(dda.rpm, 0.2)
			_on_commit("auto", 0.0)


func start_run() -> void:
	GameState.reset_run()
	_busy = false
	input_proc.arm(true)
	arena.spinning = true
	arena.randomize_target(true)
	EventBus.run_started.emit()
	EventBus.multiplier_changed.emit(GameState.session_multiplier)
	_push_zeigarnik()


func _on_commit(_mode: String, _held: float) -> void:
	if _busy or not GameState.run_active:
		return
	_busy = true
	arena.spinning = false
	var result := timing.evaluate(arena.pointer_angle, arena.target_angle)
	result["mode"] = _mode
	arena.last_grade = String(result.grade_name)
	EventBus.tap_evaluated.emit(result)
	match int(result.grade):
		TimingEngine.Grade.PERFECT:
			_apply_success(result, 1.35)
			EventBus.perfect.emit(result)
			EventBus.juice_hit.emit("perfect", 1.0)
		TimingEngine.Grade.GOOD:
			_apply_success(result, 1.0)
			EventBus.juice_hit.emit("good", 0.7)
		TimingEngine.Grade.NEAR_MISS:
			EventBus.near_miss.emit(result)
			EventBus.juice_hit.emit("near_miss", 1.0)
			EventBus.revive_offered.emit(result)
			input_proc.arm(false)
			return
		_:
			EventBus.miss.emit(result)
			EventBus.juice_hit.emit("miss", 1.0)
			_fail_run("miss", result)
			return
	_after_hit()


func _apply_success(result: Dictionary, grade_mult: float) -> void:
	GameState.session_combo += 1
	GameState.session_hits += 1
	GameState.hits_in_stage += 1
	if int(result.grade) == TimingEngine.Grade.PERFECT:
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
		float(TimingEngine.grade_score(int(result.grade)))
		* grade_mult
		* combo_mult
		* GameState.session_multiplier
		* GameState.global_multiplier()
	)
	GameState.session_score += payout
	var energy_gain: int = int(ceil(float(payout) * 0.12 * GameState.generator_rate()))
	GameState.add_energy(energy_gain)
	GameState.add_coins(maxi(1, payout / 20))
	var profile: Dictionary = dda.record(result)
	timing.configure(dda.windows())
	arena.rpm = dda.rpm
	arena.windows = dda.windows()
	EventBus.dda_changed.emit(profile)


func _after_hit() -> void:
	if GameState.hits_in_stage >= GameState.hits_needed:
		var bonus := 25 * GameState.current_stage
		GameState.add_energy(bonus)
		EventBus.stage_cleared.emit(GameState.current_stage, bonus)
		GameState.current_stage += 1
		GameState.hits_in_stage = 0
		GameState.hits_needed = mini(8 + GameState.current_stage, 14)
		if GameState.current_stage == 3 and not GameState.unlocked_themes.has("aurora"):
			GameState.unlocked_themes.append("aurora")
			GameState.save_game()
	_push_zeigarnik()
	await get_tree().create_timer(0.22).timeout
	if not GameState.run_active:
		return
	arena.randomize_target(false)
	arena.spinning = true
	_busy = false
	input_proc.arm(true)
	Engine.time_scale = 1.0


func _fail_run(reason: String, result: Dictionary) -> void:
	input_proc.arm(false)
	arena.spinning = false
	GameState.end_run()
	_push_zeigarnik()
	EventBus.run_ended.emit(reason, {
		"score": GameState.session_score,
		"combo": GameState.session_combo,
		"hits": GameState.session_hits,
		"result": result,
	})
	_busy = false
	Engine.time_scale = 1.0


func _on_revive(success: bool) -> void:
	if success:
		GameState.revive_used = true
		GameState.run_active = true
		_busy = false
		arena.spinning = true
		arena.randomize_target(false)
		input_proc.arm(true)
		Engine.time_scale = 1.0
		return
	_fail_run("near_miss", {})


func _on_ad(placement: String, rewarded: bool) -> void:
	if placement == "end_multiplier" and rewarded:
		GameState.add_energy(int(GameState.session_score * 0.08 * 2.0))
		GameState.add_coins(int(GameState.session_score * 0.05))


func _idle_tick() -> void:
	if GameState.run_active:
		return
	var drip := int(ceil(2.0 * GameState.generator_rate()))
	GameState.add_energy(drip)
	_push_zeigarnik()


func _push_zeigarnik() -> void:
	var tracker := ZeigarnikTracker.new()
	EventBus.zeigarnik_updated.emit(tracker.loops())
