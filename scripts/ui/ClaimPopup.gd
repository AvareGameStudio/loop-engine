class_name ClaimPopup
extends CanvasLayer

const VaultArt := preload("res://scripts/vfx/VaultSprites.gd")
## Crew stash collect. What the crew stole while the app was closed waits here as a
## stuffed bag, not a live ticker. Claiming fires a gold explosion so the return-to-game
## moment is Instant Gratification. "Later" leaves the bag full (Zeigarnik pull-back).

@onready var root: Control = $Root
@onready var panel: Control = $Root/Panel
@onready var amount_label: Label = $Root/Panel/Margin/VBox/Amount
@onready var body_label: Label = $Root/Panel/Margin/VBox/Body
@onready var claim_btn: Button = $Root/Panel/Margin/VBox/Claim
@onready var later_btn: Button = $Root/Panel/Margin/VBox/Later
@onready var market_btn: Button = $Root/Panel/Margin/VBox/Market
@onready var coin_confetti: CPUParticles2D = $CoinConfetti

var _open: bool = false
var _holding_pause: bool = false
var _count_tween: Tween
var _gems: CPUParticles2D


func _ready() -> void:
	root.visible = false
	VaultArt.ensure()
	coin_confetti.position = Vector2(360, -28)
	coin_confetti.texture = VaultArt.gold
	coin_confetti.amount = 64
	coin_confetti.gravity = Vector2(0, 1100)
	coin_confetti.color = Color(1.0, 0.86, 0.28, 1.0)
	coin_confetti.emitting = false
	_gems = coin_confetti.duplicate()
	_gems.name = "GemRain"
	_gems.texture = VaultArt.gem
	_gems.amount = 32
	_gems.color = Color(0.82, 0.95, 1.0, 1.0)
	_gems.emitting = false
	add_child(_gems)
	claim_btn.pressed.connect(_claim)
	later_btn.pressed.connect(_later)
	market_btn.pressed.connect(_open_market)
	# Tapping the dim (the spinning ring behind it) used to do nothing, so
	# the game felt frozen. Treat that tap as "Later".
	$Root/Dim.gui_input.connect(_on_dim_input)
	EventBus.stash_ready.connect(open)
	EventBus.stash_changed.connect(_on_stash)


func _on_dim_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton and event.pressed:
		_later()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and root.visible:
		_refresh()


## `from_player` is the HUD chip tap. Auto `stash_ready` never steals a live vault.
func open(_amount: int = 0, from_player: bool = false) -> void:
	if GameState.unclaimed_cash <= 0:
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
	_pour_hoard()


func _on_stash(amount: int, _delta: int) -> void:
	if _open:
		if amount <= 0:
			_close()
		else:
			_refresh()


func _refresh() -> void:
	body_label.text = tr("CLAIM_BODY")
	market_btn.text = tr("CLAIM_MARKET")
	_count_amount(GameState.unclaimed_cash)


func _count_amount(target: int) -> void:
	if _count_tween:
		_count_tween.kill()
	amount_label.text = tr("CLAIM_AMOUNT") % 0
	_count_tween = create_tween()
	_count_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_count_tween.set_ignore_time_scale(true)
	_count_tween.tween_method(_set_counted_amount, 0.0, float(target), 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_counted_amount(value: float) -> void:
	amount_label.text = tr("CLAIM_AMOUNT") % int(value)


func _claim() -> void:
	var n: int = GameState.claim_stash()
	if n > 0:
		EventBus.juice_hit.emit("claim", 1.0)
		_pour_hoard()
	_close()
	EventBus.stash_resolved.emit(true)


func _open_market() -> void:
	var ui := get_parent()
	if ui and ui.get_node_or_null("MarketPopup"):
		ui.get_node("MarketPopup").open()


func _later() -> void:
	_close()
	EventBus.stash_resolved.emit(false)


func _pour_hoard() -> void:
	coin_confetti.restart()
	coin_confetti.emitting = true
	if _gems:
		_gems.restart()
		_gems.emitting = true


func _close() -> void:
	if not _open and not root.visible:
		return
	_open = false
	root.visible = false
	if _holding_pause:
		OverlayPause.pop()
		_holding_pause = false
