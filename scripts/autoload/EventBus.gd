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
## The last pin seated: the vault at `stage_index` is cracked and `payout` cash spilled.
signal stage_cleared(stage_index: int, payout: int)
signal run_started()
## reason: "cracked" (vault opened) or "caught" (alarm maxed, no bribe).
signal run_ended(reason: String, stats: Dictionary)
## The cops arrived. The player can bribe them (rewarded ad) or get caught.
signal revive_offered(result: Dictionary)
signal revive_resolved(success: bool)
signal cash_changed(amount: int, delta: int)
## Strikes on the wall lamp. `level` 0..`max_level`.
signal alarm_changed(level: int, max_level: int)
signal dda_changed(profile: Dictionary)
signal juice_hit(grade: String, intensity: float)
signal multiplier_changed(value: float)
signal meta_upgraded(stat: String, level: int)
signal ad_requested(placement: String, payload: Dictionary)
signal ad_finished(placement: String, rewarded: bool)
signal countdown(step: int)
signal direction_flipped(direction: float)
signal session_changed()
## Crew stash: unclaimed offline earnings waiting to be collected.
signal stash_changed(amount: int, delta: int)
signal stash_ready(amount: int)
signal stash_resolved(claimed: bool)
signal cosmetic_equipped(id: String)
## A new hideout item joined the shelf.
signal loot_unlocked(loot_id: String)
## 0..1 tease for the next variable-ratio drop.
signal vr_tension(value: float)


func _ready() -> void:
	# The bus only forwards signals. It should not sit in the process or physics lists.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
