extends CanvasLayer
## Near-miss revive: loss-aversion copy + rewarded placement.
## The trigger is dynamic: the closer the run is to the player's record, the wider
## the slice of the near-miss band that earns a second chance. Far from the record
## only razor-thin misses qualify; below `min_record_pct` the run just ends.

## Runs scoring under this share of the record never get a revive.
@export_range(0.0, 100.0) var min_record_pct: float = 50.0
## Share of the near-miss band (measured past the Good edge) that qualifies at
## `min_record_pct`. It widens linearly to the whole band at 100% of the record.
@export_range(0.0, 100.0) var tight_band_pct: float = 35.0

@onready var root: Control = $Root
@onready var title: Label = $Root/Panel/VBox/Title
@onready var body: Label = $Root/Panel/VBox/Body
@onready var watch: Button = $Root/Panel/VBox/Watch
@onready var skip: Button = $Root/Panel/VBox/Skip
@onready var dim: ColorRect = $Root/Dim

var _open := false
var _result: Dictionary = {}


func _ready() -> void:
	root.visible = false
	watch.pressed.connect(_watch)
	skip.pressed.connect(_skip)
	EventBus.revive_offered.connect(present)
	EventBus.ad_finished.connect(_on_ad)


func present(result: Dictionary) -> void:
	var ratio: float = record_ratio()
	if not should_offer(result, ratio):
		# Deferred so the near-miss hitstop and juice land before the run-over sheet.
		EventBus.revive_resolved.emit.call_deferred(false)
		return
	_result = result
	_open = true
	root.visible = true
	title.text = tr("REVIVE_TITLE")
	body.text = "\n".join([
		tr("REVIVE_BODY") % float(result.get("overshoot_deg", 0.0)),
		_record_line(ratio),
		tr("REVIVE_PROMPT"),
	])
	watch.text = tr("REVIVE_WATCH")
	skip.text = tr("REVIVE_SKIP")
	watch.disabled = GameState.revive_used
	if GameState.revive_used:
		watch.text = tr("REVIVE_USED")
		body.text += "\n" + tr("REVIVE_LAST")
	_punch()


## Session score as a share of the record. With no record yet, every run is on record pace.
static func record_ratio() -> float:
	if GameState.best_score <= 0:
		return 1.0
	return float(GameState.session_score) / float(GameState.best_score)


## Widest `near_miss_margin` (0 = Good edge, 1 = band edge) that still earns a revive.
func allowed_margin(ratio: float) -> float:
	var t: float = clampf(inverse_lerp(min_record_pct / 100.0, 1.0, ratio), 0.0, 1.0)
	return lerpf(tight_band_pct / 100.0, 1.0, t)


func should_offer(result: Dictionary, ratio: float) -> bool:
	if ratio < min_record_pct / 100.0:
		return false
	return float(result.get("near_miss_margin", 1.0)) <= allowed_margin(ratio)


func _record_line(ratio: float) -> String:
	if GameState.best_score <= 0:
		return tr("REVIVE_FIRST_RECORD")
	if ratio >= 1.0:
		return tr("REVIVE_NEW_RECORD")
	return tr("REVIVE_RECORD") % [roundi(ratio * 100.0), GameState.best_score]


func _punch() -> void:
	var panel: Control = $Root/Panel
	panel.scale = Vector2(0.86, 0.86)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _watch() -> void:
	if GameState.revive_used:
		_skip()
		return
	watch.disabled = true
	watch.text = tr("REVIVE_LOADING")
	EventBus.ad_requested.emit("near_miss_revive", _result)


func _skip() -> void:
	_close()
	EventBus.revive_resolved.emit(false)


func _on_ad(placement: String, rewarded: bool) -> void:
	if not _open or placement != "near_miss_revive":
		return
	_close()
	EventBus.revive_resolved.emit(rewarded)


func _close() -> void:
	_open = false
	root.visible = false
	watch.disabled = false
