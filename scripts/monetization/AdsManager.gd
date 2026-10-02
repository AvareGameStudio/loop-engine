extends Node
## Mock mediation layer. Swap `show_rewarded` with AdMob/LevelPlay later.
## Placements: near_miss_revive, end_multiplier, extra_energy.

@export var mock_fill_rate: float = 1.0
@export var mock_latency_ms: int = 350

var _busy := false

func _ready() -> void:
	EventBus.ad_requested.connect(_on_requested)


func is_ready(placement: String) -> bool:
	if GameState.no_ads and placement != "near_miss_revive":
		return false
	return not _busy


func show_rewarded(placement: String, payload: Dictionary = {}) -> void:
	EventBus.ad_requested.emit(placement, payload)


func _on_requested(placement: String, _payload: Dictionary) -> void:
	if _busy:
		EventBus.ad_finished.emit(placement, false)
		return
	_busy = true
	await get_tree().create_timer(float(mock_latency_ms) / 1000.0).timeout
	var rewarded := randf() <= mock_fill_rate
	if GameState.no_ads:
		rewarded = true
	_busy = false
	EventBus.ad_finished.emit(placement, rewarded)
