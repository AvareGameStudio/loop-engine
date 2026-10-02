class_name TimingEngine
extends RefCounted
## Measures pointer-vs-target angle error and maps it to Perfect / Good / Near-Miss / Miss.
## Windows are expressed in degrees and tuned live by DynamicDifficulty.

enum Grade { PERFECT, GOOD, NEAR_MISS, MISS }

const GRADE_NAMES := {
	Grade.PERFECT: "perfect",
	Grade.GOOD: "good",
	Grade.NEAR_MISS: "near_miss",
	Grade.MISS: "miss",
}

var perfect_deg: float = 7.0
var good_deg: float = 16.0
var near_deg: float = 22.0


func configure(windows: Dictionary) -> void:
	perfect_deg = float(windows.get("perfect", perfect_deg))
	good_deg = float(windows.get("good", good_deg))
	near_deg = float(windows.get("near", near_deg))


func evaluate(pointer_rad: float, target_rad: float) -> Dictionary:
	var delta_rad := angle_difference(pointer_rad, target_rad)
	var delta_deg := absf(rad_to_deg(delta_rad))
	var full_circle_pct := (delta_deg / 360.0) * 100.0
	var grade := Grade.MISS
	if delta_deg <= perfect_deg:
		grade = Grade.PERFECT
	elif delta_deg <= good_deg:
		grade = Grade.GOOD
	elif delta_deg <= near_deg:
		grade = Grade.NEAR_MISS

	var accuracy := clampf(1.0 - (delta_deg / near_deg), 0.0, 1.0)
	var near_miss_margin := 0.0
	if grade == Grade.NEAR_MISS:
		near_miss_margin = (delta_deg - good_deg) / max(near_deg - good_deg, 0.001)

	return {
		"grade": grade,
		"grade_name": GRADE_NAMES[grade],
		"delta_deg": delta_deg,
		"delta_rad": delta_rad,
		"signed_deg": rad_to_deg(delta_rad),
		"full_circle_pct": full_circle_pct,
		"accuracy": accuracy,
		"near_miss_margin": near_miss_margin,
		"in_loss_aversion_band": grade == Grade.NEAR_MISS and full_circle_pct <= 3.0,
		"pointer": pointer_rad,
		"target": target_rad,
		"windows": {
			"perfect": perfect_deg,
			"good": good_deg,
			"near": near_deg,
		},
	}


static func grade_score(grade: Grade) -> int:
	match grade:
		Grade.PERFECT:
			return 150
		Grade.GOOD:
			return 80
		Grade.NEAR_MISS:
			return 0
		_:
			return 0
