class_name MarketPopup
extends CanvasLayer
## Spendable marketplace for MetaUpgrade. Pauses an active run while open; between
## runs the tree keeps going, so passive income and affordability update live.

@onready var root: Control = $Root
@onready var panel: Control = $Root/Panel
@onready var balance_label: Label = $Root/Panel/Margin/VBox/Balance
@onready var passive_label: Label = $Root/Panel/Margin/VBox/Passive
@onready var items_box: VBoxContainer = $Root/Panel/Margin/VBox/Items
@onready var close_btn: Button = $Root/Panel/Margin/VBox/Close

## id -> {"name": Label, "effect": Label, "buy": Button}
var _rows: Dictionary[String, Dictionary] = {}
var _paused_run: bool = false


func _ready() -> void:
	root.visible = false
	for item: Dictionary in MetaUpgrade.CATALOG:
		_rows[String(item.id)] = _make_row(String(item.id))
	close_btn.pressed.connect(close)
	EventBus.energy_changed.connect(_on_wallet_changed)
	EventBus.coins_changed.connect(_on_wallet_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and root.visible:
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if root.visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if root.visible:
		return
	_refresh()
	_paused_run = GameState.run_active and not get_tree().paused
	if _paused_run:
		get_tree().paused = true
	root.visible = true
	_punch(panel, 0.86)


func close() -> void:
	if not root.visible:
		return
	root.visible = false
	if _paused_run:
		get_tree().paused = false
	_paused_run = false


func _make_row(id: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 20)
	var effect := Label.new()
	effect.add_theme_font_size_override("font_size", 15)
	effect.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 1))
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(name_label)
	info.add_child(effect)
	var buy := Button.new()
	buy.custom_minimum_size = Vector2(170, 56)
	buy.add_theme_font_size_override("font_size", 17)
	buy.pivot_offset = buy.custom_minimum_size * 0.5
	buy.pressed.connect(_buy.bind(id))
	row.add_child(info)
	row.add_child(buy)
	items_box.add_child(row)
	return {"name": name_label, "effect": effect, "buy": buy}


func _buy(id: String) -> void:
	if MetaUpgrade.purchase(id):
		_refresh()
		_punch(_rows[id].buy as Control, 1.15)


func _on_wallet_changed(_amount: int, _delta: int) -> void:
	if root.visible:
		_refresh()


func _refresh() -> void:
	balance_label.text = tr("MARKET_BALANCE") % [GameState.energy, GameState.coins]
	passive_label.text = tr("MARKET_PASSIVE") % MetaUpgrade.passive_rate()
	for item: Dictionary in MetaUpgrade.CATALOG:
		var id: String = String(item.id)
		var key: String = id.to_upper()
		var row: Dictionary = _rows[id]
		(row.name as Label).text = "%s  ·  %s" % [tr("MARKET_%s_NAME" % key), tr("MARKET_LEVEL") % MetaUpgrade.level(id)]
		(row.effect as Label).text = tr("MARKET_%s_EFFECT" % key) % int(item.effect_pct)
		var cost_key: String = "MARKET_COST_ENERGY" if item.currency == "energy" else "MARKET_COST_COINS"
		var buy: Button = row.buy
		buy.text = tr(cost_key) % MetaUpgrade.cost(id)
		buy.disabled = not MetaUpgrade.can_afford(id)


func _punch(target: Control, from_scale: float) -> void:
	target.scale = Vector2(from_scale, from_scale)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(target, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
