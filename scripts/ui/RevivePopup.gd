extends CanvasLayer
## "Bribe the Cops": the third alarm strike brings the police. One rewarded ad
## resets the alarm and the same vault keeps going; skipping ends the run.
## Always offered once per vault. No record gating: a bust is a bust, and the ad
## is the only thing between the player and losing the vault.

@onready var root: Control = $Root
@onready var title: Label = $Root/Panel/VBox/Title
@onready var body: Label = $Root/Panel/VBox/Body
@onready var watch: Button = $Root/Panel/VBox/Watch
@onready var skip: Button = $Root/Panel/VBox/Skip
@onready var dim: ColorRect = $Root/Dim

var _open := false
var _result: Dictionary = {}
var _holding_pause: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	watch.pressed.connect(_watch)
	skip.pressed.connect(_skip)
	dim.gui_input.connect(_on_dim)
	EventBus.revive_offered.connect(present)
	EventBus.ad_finished.connect(_on_ad)


func present(result: Dictionary) -> void:
	if GameState.revive_used:
		# Deferred so the siren hitstop lands before the card.
		EventBus.revive_resolved.emit.call_deferred(false)
		return
	_result = result
	_open = true
	root.visible = true
	title.text = tr("REVIVE_TITLE")
	body.text = "\n".join([
		tr("REVIVE_BODY") % GameState.current_stage,
		_loot_line(),
	])
	watch.text = tr("REVIVE_WATCH")
	skip.text = tr("REVIVE_SKIP")
	watch.disabled = false
	_holding_pause = true
	OverlayPause.push()
	_punch()


## The pins already seated are what the bribe protects.
func _loot_line() -> String:
	var seated: int = GameState.hits_in_stage
	if seated <= 0:
		return tr("REVIVE_PROMPT")
	return tr("REVIVE_PINS") % [seated, GameState.hits_needed]


func _punch() -> void:
	var panel: Control = $Root/Panel
	panel.scale = Vector2(0.86, 0.86)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _watch() -> void:
	watch.disabled = true
	watch.text = tr("REVIVE_LOADING")
	var ads := get_tree().root.get_node_or_null("Main/AdsManager")
	if ads and ads.has_method("show_rewarded"):
		ads.show_rewarded("near_miss_revive", _result)
	else:
		EventBus.ad_requested.emit("near_miss_revive", _result)


func _on_dim(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton and event.pressed:
		_skip()
		get_viewport().set_input_as_handled()


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
	if _holding_pause:
		OverlayPause.pop()
		_holding_pause = false
