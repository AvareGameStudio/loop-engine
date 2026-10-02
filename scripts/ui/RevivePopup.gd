extends CanvasLayer
## Near-miss revive: loss-aversion copy + rewarded placement.

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
	_result = result
	_open = true
	root.visible = true
	var delta := float(result.get("delta_deg", 0.0))
	var pct := float(result.get("full_circle_pct", 0.0))
	title.text = tr("REVIVE_TITLE")
	body.text = "%s\n%s" % [tr("REVIVE_BODY") % [delta, pct], tr("REVIVE_PROMPT")]
	watch.text = tr("REVIVE_WATCH")
	skip.text = tr("REVIVE_SKIP")
	watch.disabled = GameState.revive_used
	if GameState.revive_used:
		watch.text = tr("REVIVE_USED")
		body.text += "\n" + tr("REVIVE_LAST")
	_punch()


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
