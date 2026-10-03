class_name ZeigarnikTracker
extends RefCounted
## Leaves loops visibly unfinished so exit screens create return tension.
## Auto-Pulse shows the Idle Vault piggy (90% tease). Perfect Power shows upgrade fill.

const TEASE := 0.82
const VAULT_TEASE := 0.9

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


func loops() -> Array:
	var pulse_cost := MetaUpgrade.cost("generator")
	var power_cost := MetaUpgrade.cost("global_mult")
	var vault_n: int = GameState.unclaimed_energy
	var vault_fill := MetaUpgrade.vault_progress()
	var pulse_fill := _teased(float(GameState.energy) / max(float(pulse_cost), 1.0))
	var power_fill := _teased(float(GameState.energy) / max(float(power_cost), 1.0))
	var stage_fill := 0.0
	if GameState.hits_needed > 0:
		stage_fill = float(GameState.hits_in_stage) / float(GameState.hits_needed)
	# Prefer the piggy when it has something to collect: that's the return hook.
	var pulse_loop: Dictionary
	if vault_n > 0:
		pulse_loop = {
			"id": "generator",
			"title": tr("LOOP_GENERATOR_TITLE"),
			"subtitle": tr("LOOP_VAULT_SUB") % vault_n,
			"progress": vault_fill if vault_fill < 1.0 else VAULT_TEASE,
			"complete": false,
		}
	else:
		pulse_loop = {
			"id": "generator",
			"title": tr("LOOP_GENERATOR_TITLE"),
			"subtitle": tr("LOOP_GENERATOR_SUB") % [GameState.generator_level, GameState.energy, pulse_cost],
			"progress": pulse_fill,
			"complete": GameState.energy >= pulse_cost,
		}

	return [
		pulse_loop,
		{
			"id": "global_mult",
			"title": tr("LOOP_MULT_TITLE"),
			"subtitle": tr("LOOP_MULT_SUB") % [GameState.global_mult_level, power_cost],
			"progress": power_fill,
			"complete": GameState.energy >= power_cost,
		},
		{
			"id": "stage",
			"title": tr("LOOP_RING_TITLE") % GameState.current_stage,
			"subtitle": tr("LOOP_RING_SUB") % [GameState.hits_in_stage, GameState.hits_needed],
			"progress": clampf(stage_fill, 0.0, 1.0),
			"complete": stage_fill >= 1.0,
		},
	]


## The unfinished loop closest to done: the one the UI should nag about.
static func focus_id(loop_list: Array) -> String:
	var best_id: String = ""
	var best_progress: float = -1.0
	for loop: Dictionary in loop_list:
		if bool(loop.complete):
			continue
		if float(loop.progress) > best_progress:
			best_progress = float(loop.progress)
			best_id = String(loop.id)
	return best_id


func open_count() -> int:
	var n := 0
	for loop in loops():
		if not bool(loop.complete):
			n += 1
	return n


func _teased(raw: float) -> float:
	if raw >= 1.0:
		return 1.0
	if raw > TEASE:
		return TEASE
	if raw <= 0.0:
		return 0.04
	return raw
