class_name ZeigarnikTracker
extends RefCounted
## Two small Zeigarnik levers. The gate tracker notices when the needle sweeps
## through the pin untouched (a loss the player feels). The loot tease keeps the
## next hideout item visibly unfinished on the end-of-vault card.

const TEASE := 0.82

var _gate_hot: bool = false
var _gate_ready: bool = true
var _closest: float = 180.0


## Rearm when a new tumbler is placed. One pass per gate, so slow-mo cannot stack.
func arm_gate() -> void:
	_gate_hot = false
	_gate_ready = true
	_closest = 180.0


func note_tap() -> void:
	_gate_ready = false
	_gate_hot = false


## True once when the needle sweeps through the pin and the player never taps.
func passed_pin(error_deg: float, near_deg: float) -> bool:
	if not _gate_ready:
		return false
	var tight: float = minf(near_deg, 8.0)
	if error_deg <= tight:
		_gate_hot = true
		_closest = minf(_closest, error_deg)
		return false
	if _gate_hot and error_deg > near_deg:
		_gate_ready = false
		_gate_hot = false
		return _closest <= tight
	return false


## Fill for the "next loot item" ring. Never shows 100% unless the shelf is full.
static func loot_tease() -> float:
	var raw: float = GameState.loot_progress()
	if raw >= 1.0:
		return 1.0
	if raw > TEASE:
		return TEASE
	if raw <= 0.0:
		return 0.04
	return raw
