extends Node
class_name GlobalEventBus
## Central signal hub. Systems talk through this bus so scenes stay decoupled.
## Signals are only emitted from other scripts, hence the warning suppression.
@warning_ignore_start("unused_signal")

signal tap_evaluated(result: Dictionary)
signal jackpot(multiplier: float, label: String)
signal near_miss(result: Dictionary)
signal miss(result: Dictionary)
signal perfect(result: Dictionary)
signal stage_cleared(stage_index: int, payout: int)
signal run_started()
signal run_ended(reason: String, stats: Dictionary)
signal revive_offered(result: Dictionary)
signal revive_resolved(success: bool)
signal energy_changed(amount: int, delta: int)
signal coins_changed(amount: int, delta: int)
signal dda_changed(profile: Dictionary)
signal zeigarnik_updated(loops: Array)
signal juice_hit(grade: String, intensity: float)
signal multiplier_changed(value: float)
signal meta_upgraded(stat: String, level: int)
signal ad_requested(placement: String, payload: Dictionary)
signal ad_finished(placement: String, rewarded: bool)
signal hold_started()
signal hold_released(held_seconds: float)
signal focus_changed(value: float)
signal countdown(step: int)
signal direction_flipped(direction: float)
signal session_changed()
## Idle Vault: unclaimed Auto-Pulse earnings waiting to be collected.
signal vault_changed(amount: int, delta: int)
signal vault_ready(amount: int)
signal vault_resolved(claimed: bool)
signal cosmetic_equipped(id: String)
## 0..1 tease for the next variable-ratio drop. UI pulses Focus without revealing the interval.
signal vr_tension(value: float)


func _ready() -> void:
	# The bus only forwards signals. It should not sit in the process or physics lists.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
