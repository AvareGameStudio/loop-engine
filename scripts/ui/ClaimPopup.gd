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
@onready var coins: CPUParticles2D = $Root/Coins

var _open: bool = false
var _holding_pause: bool = false


func _ready() -> void:
	root.visible = false
	coins.texture = _make_coin_texture()
	coins.emitting = false
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


## `from_player` is the HUD peek tap. Auto `vault_ready` never steals a live run.
func open(_amount: int = 0, from_player: bool = false) -> void:
	if GameState.unclaimed_energy <= 0:
		return
	if GameState.run_active and not from_player:
		return
	if _open:
		_refresh()
		return
	_open = true
	_holding_pause = true
	OverlayPause.push()
	root.visible = true
	_refresh()
	panel.scale = Vector2(0.86, 0.86)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_ignore_time_scale(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	coins.restart()


func _on_vault(amount: int, _delta: int) -> void:
	if _open:
		if amount <= 0:
			_close()
		else:
			_refresh()


func _refresh() -> void:
	amount_label.text = tr("CLAIM_AMOUNT") % GameState.unclaimed_energy
	body_label.text = tr("CLAIM_BODY")


func _claim() -> void:
	var n: int = GameState.claim_vault()
	if n > 0:
		EventBus.juice_hit.emit("claim", 1.0)
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
	if _holding_pause:
		OverlayPause.pop()
		_holding_pause = false
