class_name WelcomePopup
extends CanvasLayer
## Welcome Back: what the Crew stole while the app was closed. Opens on launch (before the
## first tap, the door waits under it) or, if the player returns mid-heist, on the next card.
## Big gold "2x" is the rewarded ad; "Take" pays 1x. Either way coins rain into the bag.

const VaultArt := preload("res://scripts/vfx/VaultSprites.gd")
const CREW_ART := "res://assets/art/crew.png"

@onready var root: Control = $Root
@onready var panel: Control = $Root/Panel
@onready var title_label: Label = $Root/Panel/Margin/VBox/Title
@onready var amount_label: Label = $Root/Panel/Margin/VBox/Amount
@onready var body_label: Label = $Root/Panel/Margin/VBox/Body
@onready var crew_art: TextureRect = $Root/Panel/Margin/VBox/Crew
@onready var double_btn: Button = $Root/Panel/Margin/VBox/Double
@onready var take_btn: Button = $Root/Panel/Margin/VBox/Take
@onready var coin_confetti: CPUParticles2D = $CoinConfetti

var _open: bool = false
## Came back mid-heist: wait for the card instead of covering a live dial.
var _deferred: bool = false
var _count_tween: Tween


func _ready() -> void:
	root.visible = false
	VaultArt.ensure()
	if ResourceLoader.exists(CREW_ART):
		crew_art.texture = load(CREW_ART)
	else:
		crew_art.visible = false
	coin_confetti.position = Vector2(360, -28)
	coin_confetti.texture = VaultArt.gold
	coin_confetti.amount = 64
	coin_confetti.gravity = Vector2(0, 1100)
	coin_confetti.color = Color(1.0, 0.86, 0.28, 1.0)
	double_btn.pressed.connect(_double)
	take_btn.pressed.connect(_take)
	EventBus.offline_ready.connect(func(_amount: int) -> void: _try_open(false))
	EventBus.ad_finished.connect(_on_ad)
	EventBus.run_ended.connect(func(_r: String, _s: Dictionary) -> void:
		if _deferred:
			_try_open.call_deferred(true)
	)
	# Launch: MetaUpgrade already banked the night's take before this node was ready.
	_try_open.call_deferred(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and root.visible:
		_refresh(false)


## `safe`: launch or a card on screen. A focus-in mid-heist defers to the next card.
func _try_open(safe: bool) -> void:
	if GameState.unclaimed_cash <= 0 or _open:
		return
	if not safe and GameState.run_active and not _fresh_run():
		_deferred = true
		return
	_deferred = false
	_open = true
	OverlayPause.push()
	root.visible = true
	_refresh(true)
	panel.scale = Vector2(0.86, 0.86)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_ignore_time_scale(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A run nobody has tapped in yet (launch, or right after Next) can sit under the popup.
func _fresh_run() -> bool:
	var world := get_tree().get_first_node_in_group("game_world")
	return world != null and world.get("_run_cash") == 0 and GameState.session_alarm == 0


func _refresh(count: bool) -> void:
	title_label.text = tr("WELCOME_TITLE")
	body_label.text = tr("WELCOME_BODY") % _away_text(GameState.unclaimed_seconds)
	double_btn.text = tr("WELCOME_DOUBLE") % (GameState.unclaimed_cash * 2)
	double_btn.visible = not GameState.no_ads
	take_btn.text = tr("WELCOME_TAKE") % GameState.unclaimed_cash
	if count:
		_count_amount(GameState.unclaimed_cash)
	else:
		amount_label.text = "+$%d" % GameState.unclaimed_cash


func _away_text(seconds: int) -> String:
	var h: int = seconds / 3600
	var m: int = (seconds % 3600) / 60
	if h <= 0:
		return tr("WELCOME_MIN") % maxi(m, 1)
	if m == 0:
		return tr("WELCOME_HOURS") % h
	return tr("WELCOME_HOURS_MIN") % [h, m]


func _count_amount(target: int) -> void:
	if _count_tween:
		_count_tween.kill()
	_count_tween = create_tween()
	_count_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_count_tween.set_ignore_time_scale(true)
	_count_tween.tween_method(func(v: float) -> void: amount_label.text = "+$%d" % int(v), 0.0, float(target), 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _double() -> void:
	double_btn.disabled = true
	EventBus.ad_requested.emit("crew_double", {})


func _on_ad(placement: String, rewarded: bool) -> void:
	if placement != "crew_double" or not _open:
		return
	double_btn.disabled = false
	if rewarded:
		_pay(2)
	else:
		double_btn.visible = false


func _take() -> void:
	_pay(1)


func _pay(mult: int) -> void:
	var n: int = GameState.claim_offline(mult)
	if n > 0:
		EventBus.juice_hit.emit("claim", 1.0 if mult == 1 else 1.4)
		coin_confetti.restart()
		coin_confetti.emitting = true
	_open = false
	root.visible = false
	OverlayPause.pop()
