extends CanvasLayer
## Near-miss revive, gated on record proximity (Near-Miss monetization).
## Ordinary deaths skip this and go straight to run-over. Only a death at ≥85%
## of the personal best earns the ad, so ads stay scarce and conversion stays high.

## Session score must reach this share of the record before a revive is even considered.
@export_range(0.0, 100.0) var min_record_pct: float = 85.0

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
		# Deferred so the near-miss hitstop lands before the run-over sheet.
		EventBus.revive_resolved.emit.call_deferred(false)
		return
	_result = result
	_open = true
	root.visible = true
	var band: bool = bool(result.get("in_loss_aversion_band", false))
	title.text = tr("REVIVE_TITLE" if band else "REVIVE_TITLE_FAR")
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


## Session score as a share of the record. No record yet → every run is on record pace.
static func record_ratio() -> float:
	if GameState.best_score <= 0:
		return 1.0
	return float(GameState.session_score) / float(GameState.best_score)


func should_offer(_result: Dictionary, ratio: float) -> bool:
	if GameState.revive_used:
		return false
	return ratio >= min_record_pct / 100.0


## Remaining Perfect-paced hits to beat the record. "Only 2 hits left" is the hook.
static func hits_to_record() -> int:
	if GameState.best_score <= 0:
		return 0
	var remaining: int = GameState.best_score - GameState.session_score
	if remaining <= 0:
		return 0
	var avg: float = float(GameState.session_score) / float(maxi(GameState.session_hits, 1))
	return ceili(float(remaining) / maxf(avg, 1.0))


func _record_line(ratio: float) -> String:
	if GameState.best_score <= 0:
		return tr("REVIVE_FIRST_RECORD")
	var left: int = hits_to_record()
	if left <= 0:
		return tr("REVIVE_NEW_RECORD")
	if left == 1:
		return tr("REVIVE_HITS_LEFT_ONE")
	return tr("REVIVE_HITS_LEFT") % left


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
	var ads := get_tree().root.get_node_or_null("Main/AdsManager")
	if ads and ads.has_method("show_rewarded"):
		ads.show_rewarded("near_miss_revive", _result)
	else:
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
