class_name VariableRatioSchedule
extends RefCounted
## Skinner variable-ratio payouts. Reward after a random number of successful hits,
## not on a fixed cadence, to keep dopamine volatile.

var min_interval: int = 3
var max_interval: int = 9
var jackpot_chance: float = 0.08
var _remaining: int = 5
var rng := RandomNumberGenerator.new()

const TABLE := [
	{"w": 40, "mult": 2.0, "label": "VR_X2"},
	{"w": 28, "mult": 3.0, "label": "VR_X3"},
	{"w": 18, "mult": 5.0, "label": "VR_X5"},
	{"w": 9, "mult": 8.0, "label": "VR_X8"},
	{"w": 5, "mult": 15.0, "label": "JACKPOT"},
]


func _init() -> void:
	rng.randomize()
	_roll_interval()


func _roll_interval() -> void:
	_remaining = rng.randi_range(min_interval, max_interval)


func register_success() -> Dictionary:
	_remaining -= 1
	if _remaining > 0:
		return {"triggered": false}

	_roll_interval()
	var drop := _weighted_drop()
	if rng.randf() < jackpot_chance:
		drop = {"w": 0, "mult": float(rng.randi_range(12, 25)), "label": "JACKPOT"}
	return {
		"triggered": true,
		"multiplier": float(drop.mult),
		"label": String(drop.label),
		"next_in": _remaining,
	}


func peek_tension() -> float:
	## UI can tease "something's coming" without revealing the interval.
	return clampf(1.0 - float(_remaining) / float(max_interval), 0.0, 1.0)


func _weighted_drop() -> Dictionary:
	var total := 0
	for row in TABLE:
		total += int(row.w)
	var pick := rng.randi_range(1, total)
	var acc := 0
	for row in TABLE:
		acc += int(row.w)
		if pick <= acc:
			return row
	return TABLE[0]
