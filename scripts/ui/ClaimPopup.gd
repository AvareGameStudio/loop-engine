class_name ClaimPopup
extends CanvasLayer
## Idle Vault collect. Auto-Pulse earnings wait here as a piggy, not a live ticker.
## Claiming fires a gold explosion so the return-to-game moment is Instant Gratification.
## "Later" leaves the vault full (Zeigarnik: the unfinished piggy pulls the player back).

@onready var root: Control = $Root
@onready var panel: Control = $Root/Panel
@onready var amount_label: Label = $Root/Panel/Margin/VBox/Amount
@onready var body_label: Label = $Root/Panel/Margin/VBox/Body
@onready var claim_btn: Button = $Root/Panel/Margin/VBox/Claim
@onready var later_btn: Button = $Root/Panel/Margin/VBox/Later
@onready var coin_confetti: CPUParticles2D = $CoinConfetti

var _open: bool = false
var _was_paused: bool = false
var _count_tween: Tween


func _ready() -> void:
	root.visible = false
	coin_confetti.texture = _make_coin_texture()
	coin_confetti.emitting = false
	claim_btn.pressed.connect(_claim)
	later_btn.pressed.connect(_later)
	# Tapping the dim (the spinning ring behind it) used to do nothing, so
	# the game felt frozen. Treat that tap as "Later".
	$Root/Dim.gui_input.connect(_on_dim_input)
	EventBus.vault_ready.connect(open)
	EventBus.vault_changed.connect(_on_vault)


func _on_dim_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton and event.pressed:
		_later()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and root.visible:
		_refresh()


func open(_amount: int = 0) -> void:
	if GameState.unclaimed_energy <= 0:
		return
	if _open:
		_refresh()
		return
	_open = true
	# Pause the run under the piggy so Auto-Tap cannot miss while the overlay is up.
	_was_paused = get_tree().paused
	get_tree().paused = true
	root.visible = true
	_refresh()
	panel.scale = Vector2(0.86, 0.86)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_ignore_time_scale(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	coin_confetti.restart()


func _on_vault(amount: int, _delta: int) -> void:
	if _open:
		if amount <= 0:
			_close()
		else:
			_refresh()


func _refresh() -> void:
	body_label.text = tr("CLAIM_BODY")
	_count_amount(GameState.unclaimed_energy)


func _count_amount(target: int) -> void:
	if _count_tween:
		_count_tween.kill()
	amount_label.text = tr("CLAIM_AMOUNT") % 0
	_count_tween = create_tween()
	_count_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_count_tween.set_ignore_time_scale(true)
	_count_tween.tween_method(_set_counted_amount, 0.0, float(target), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_counted_amount(value: float) -> void:
	amount_label.text = tr("CLAIM_AMOUNT") % int(value)


func _claim() -> void:
	var n: int = GameState.claim_vault()
	if n > 0:
		EventBus.juice_hit.emit("claim", 1.0)
		coin_confetti.restart()
	_close()
	EventBus.vault_resolved.emit(true)


func _later() -> void:
	_close()
	EventBus.vault_resolved.emit(false)


func _make_coin_texture() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(15.5, 15.5)
	for y in 32:
		for x in 32:
			var d: float = Vector2(x, y).distance_to(center)
			if d > 14.0:
				continue
			var col := Color(1.0, 0.84, 0.28, 1)
			if d > 11.2:
				col = Color(0.62, 0.4, 0.08, 1)
			elif d < 4.5:
				col = Color(1.0, 0.96, 0.7, 1)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _close() -> void:
	if not _open and not root.visible:
		return
	_open = false
	root.visible = false
	get_tree().paused = _was_paused
	_was_paused = false
