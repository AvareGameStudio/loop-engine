class_name TimingEngine
extends RefCounted
## Measures pointer-vs-target angle error and maps it to Perfect / Good / Near-Miss / Miss.
## Windows are expressed in degrees and tuned live by DynamicDifficulty.
## Also decides the feedback for each hit (pitch, haptic); SoundManager and Juice only render it.

enum Grade { PERFECT, GOOD, NEAR_MISS, MISS }

const GRADE_NAMES := {
	Grade.PERFECT: "perfect",
	Grade.GOOD: "good",
	Grade.NEAR_MISS: "near_miss",
	Grade.MISS: "miss",
}

## Major pentatonic: any two steps sound consonant, so a streak climbs as a melody, not a siren.
const PENTATONIC: PackedInt32Array = [0, 2, 4, 7, 9]
## Ladder plateaus here (14 semitones, ~2.2x) so long combos never turn shrill.
const MAX_PITCH_STEP: int = 6

## [duration_ms, amplitude]. Failures buzz longer and harder than wins: loss must be felt.
const HAPTICS := {
	Grade.PERFECT: [18, 0.7],
	Grade.GOOD: [10, 0.4],
	Grade.NEAR_MISS: [45, 0.85],
	Grade.MISS: [65, 1.0],
}

var perfect_deg: float = 7.0
var good_deg: float = 16.0
var near_deg: float = 22.0


func configure(windows: Dictionary) -> void:
	perfect_deg = float(windows.get("perfect", perfect_deg))
	good_deg = float(windows.get("good", good_deg))
	near_deg = float(windows.get("near", near_deg))


## `streak` is the number of consecutive hits before this one; it drives the pitch ladder.
func evaluate(pointer_rad: float, target_rad: float, streak: int = 0) -> Dictionary:
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
	# How far past the Good edge the pointer stopped; the real "missed by" distance.
	var overshoot_deg := 0.0
	if grade == Grade.NEAR_MISS:
		overshoot_deg = delta_deg - good_deg
		near_miss_margin = overshoot_deg / max(near_deg - good_deg, 0.001)
	var overshoot_pct := (overshoot_deg / 360.0) * 100.0
	var haptic: Array = HAPTICS[grade]

	return {
		"grade": grade,
		"grade_name": GRADE_NAMES[grade],
		"delta_deg": delta_deg,
		"delta_rad": delta_rad,
		"signed_deg": rad_to_deg(delta_rad),
		"full_circle_pct": full_circle_pct,
		"accuracy": accuracy,
		"near_miss_margin": near_miss_margin,
		"overshoot_deg": overshoot_deg,
		"overshoot_pct": overshoot_pct,
		"in_loss_aversion_band": grade == Grade.NEAR_MISS and overshoot_pct <= 3.0,
		"pitch": pitch_for(grade, streak),
		"haptic_ms": int(haptic[0]),
		# Successes scale with accuracy, so a dead-center Perfect lands harder than an edge one.
		"haptic_amplitude": float(haptic[1]) * (lerpf(0.6, 1.0, accuracy) if grade <= Grade.GOOD else 1.0),
		"pointer": pointer_rad,
		"target": target_rad,
		"windows": {
			"perfect": perfect_deg,
			"good": good_deg,
			"near": near_deg,
		},
	}


## Hits climb the pentatonic ladder one step per streak; failures play at base pitch.
static func pitch_for(grade: Grade, streak: int) -> float:
	if grade > Grade.GOOD:
		return 1.0
	var step: int = clampi(streak, 0, MAX_PITCH_STEP)
	var octave: int = floori(float(step) / PENTATONIC.size())
	var semitones: int = 12 * octave + PENTATONIC[step % PENTATONIC.size()]
	return pow(2.0, semitones / 12.0)


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
