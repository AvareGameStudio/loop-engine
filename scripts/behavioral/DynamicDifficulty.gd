class_name DynamicDifficulty
extends RefCounted
## Flow-channel tuner. Shrinks boredom (too easy) and anxiety (too hard) by
## nudging RPM and hit windows from a rolling error window.

const HISTORY := 12
const TARGET_SUCCESS := 0.72
const TARGET_PERFECT := 0.28

var rpm: float = 0.55
var perfect_deg: float = 7.0
var good_deg: float = 16.0
var near_deg: float = 22.0

var rpm_min: float = 0.32
var rpm_max: float = 1.35
var perfect_min: float = 4.0
var perfect_max: float = 12.0

var _grades: Array[int] = []
var _errors: Array[float] = []


func seed_from_state() -> void:
	rpm = clampf(GameState.dda_rpm, rpm_min, rpm_max)
	perfect_deg = clampf(GameState.dda_perfect_deg, perfect_min, perfect_max)
	good_deg = clampf(GameState.dda_good_deg, 10.0, 24.0)
	near_deg = clampf(GameState.dda_near_deg, good_deg + 3.6, good_deg + 10.8)
	# Anxiety-floor saves (tiny window + high RPM) made the first tap a coin-flip.
	if rpm >= 0.65 and perfect_deg <= 5.5:
		forgive()


## Pull difficulty back toward the flow center after a short death spiral.
func forgive() -> void:
	rpm = lerpf(rpm, 0.55, 0.6)
	perfect_deg = lerpf(perfect_deg, 7.0, 0.6)
	_sync_windows()
	_persist()


func record(result: Dictionary) -> Dictionary:
	var grade: int = int(result.get("grade", TimingEngine.Grade.MISS))
	_grades.append(grade)
	_errors.append(float(result.get("delta_deg", 180.0)))
	if _grades.size() > HISTORY:
		_grades.pop_front()
		_errors.pop_front()
	var live_good: float = float(result.get("windows", {}).get("good", good_deg))
	_retune(live_good)
	_persist()
	return profile()


func profile() -> Dictionary:
	return {
		"rpm": rpm,
		"perfect": perfect_deg,
		"good": good_deg,
		"near": near_deg,
		"success_rate": _rate_at_most(TimingEngine.Grade.GOOD),
		"perfect_rate": _rate_equals(TimingEngine.Grade.PERFECT),
		"mean_error": _mean_error(),
		"samples": _grades.size(),
	}


func windows() -> Dictionary:
	return {"perfect": perfect_deg, "good": good_deg, "near": near_deg}


func _retune(live_good: float) -> void:
	if _grades.size() < 4:
		return
	var success := _rate_at_most(TimingEngine.Grade.GOOD)
	var perfects := _rate_equals(TimingEngine.Grade.PERFECT)
	var mean_err := _mean_error()

	var ease_delta := success - TARGET_SUCCESS
	rpm = clampf(rpm + ease_delta * 0.18, rpm_min, rpm_max)

	if perfects > TARGET_PERFECT + 0.1:
		perfect_deg = maxf(perfect_min, perfect_deg - 0.35)
	elif perfects < TARGET_PERFECT - 0.1:
		perfect_deg = minf(perfect_max, perfect_deg + 0.4)

	# Compare against the window the player actually saw, after stage shrink.
	if mean_err > live_good * 1.15:
		rpm = maxf(rpm_min, rpm - 0.05)
		perfect_deg = minf(perfect_max, perfect_deg + 0.25)

	_sync_windows()


func _sync_windows() -> void:
	good_deg = clampf(perfect_deg * 2.15, 10.0, 24.0)
	## Extra 1–3% of the circle beyond the Good window (Prospect Theory band).
	var miss_band := clampf(360.0 * 0.02, 3.6, 10.8)
	near_deg = good_deg + miss_band


func _rate_at_most(grade: int) -> float:
	if _grades.is_empty():
		return 0.0
	var hits := 0
	for g in _grades:
		if g <= grade:
			hits += 1
	return float(hits) / float(_grades.size())


func _rate_equals(grade: int) -> float:
	if _grades.is_empty():
		return 0.0
	var hits := 0
	for g in _grades:
		if g == grade:
			hits += 1
	return float(hits) / float(_grades.size())


func _mean_error() -> float:
	if _errors.is_empty():
		return 0.0
	var s := 0.0
	for e in _errors:
		s += e
	return s / float(_errors.size())


func _persist() -> void:
	GameState.dda_rpm = rpm
	GameState.dda_perfect_deg = perfect_deg
	GameState.dda_good_deg = good_deg
	GameState.dda_near_deg = near_deg
	GameState.request_save()
