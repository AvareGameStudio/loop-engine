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
			"title": "Generator Speed",
			"subtitle": "Lv %d  ·  %d / %d energy" % [GameState.generator_level, GameState.energy, gen_cost],
			"progress": gen_fill,
			"complete": GameState.energy >= gen_cost,
		},
		{
			"id": "global_mult",
			"title": "Global Multiplier",
			"subtitle": "Lv %d  ·  next at %d" % [GameState.global_mult_level, mult_cost],
			"progress": mult_fill,
			"complete": GameState.energy >= mult_cost,
		},
		{
			"id": "stage",
			"title": "Ring %d" % GameState.current_stage,
			"subtitle": "%d / %d locks" % [GameState.hits_in_stage, GameState.hits_needed],
			"progress": clampf(stage_fill, 0.0, TEASE if GameState.run_active else stage_fill),
			"complete": not GameState.run_active and stage_fill >= 1.0,
		},
		{
			"id": "collection",
			"title": "Theme Collection",
			"subtitle": "%d / %d rings" % [GameState.unlocked_themes.size(), theme_goal],
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
