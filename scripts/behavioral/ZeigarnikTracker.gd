class_name ZeigarnikTracker
extends RefCounted
## Leaves loops visibly unfinished (~80% full) so exit screens create return tension.

const TEASE := 0.82

func loops() -> Array:
	var gen_cost := GameState.upgrade_cost("generator")
	var mult_cost := GameState.upgrade_cost("global_mult")
	var gen_fill := _teased(float(GameState.energy) / max(float(gen_cost), 1.0))
	var mult_fill := _teased(float(GameState.energy) / max(float(mult_cost), 1.0))
	var stage_fill := 0.0
	if GameState.hits_needed > 0:
		stage_fill = float(GameState.hits_in_stage) / float(GameState.hits_needed)
	var theme_goal := 5
	var theme_fill := _teased(float(GameState.unlocked_themes.size()) / float(theme_goal))

	return [
		{
			"id": "generator",
			"title": tr("LOOP_GENERATOR_TITLE"),
			"subtitle": tr("LOOP_GENERATOR_SUB") % [GameState.generator_level, GameState.energy, gen_cost],
			"progress": gen_fill,
			"complete": GameState.energy >= gen_cost,
		},
		{
			"id": "global_mult",
			"title": tr("LOOP_MULT_TITLE"),
			"subtitle": tr("LOOP_MULT_SUB") % [GameState.global_mult_level, mult_cost],
			"progress": mult_fill,
			"complete": GameState.energy >= mult_cost,
		},
		{
			"id": "stage",
			"title": tr("LOOP_RING_TITLE") % GameState.current_stage,
			"subtitle": tr("LOOP_RING_SUB") % [GameState.hits_in_stage, GameState.hits_needed],
			# Not teased: the HUD stage bar shows the same value, and they must agree.
			"progress": clampf(stage_fill, 0.0, 1.0),
			"complete": stage_fill >= 1.0,
		},
		{
			"id": "collection",
			"title": tr("LOOP_THEMES_TITLE"),
			"subtitle": tr("LOOP_THEMES_SUB") % [GameState.unlocked_themes.size(), theme_goal],
			"progress": theme_fill,
			"complete": GameState.unlocked_themes.size() >= theme_goal,
		},
	]


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
