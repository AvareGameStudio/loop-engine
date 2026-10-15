class_name HideoutPopup
extends CanvasLayer
## One room, twelve silhouettes. Owned items are colored; the rest stay dark.
## The next item carries its price: affordable, its silhouette breathes (6%, 0.8 s) and a
## tap on the gold button buys it - pop 1.0 -> 1.25 -> 1.0, gold burst, chips landing.

const VaultArt := preload("res://scripts/vfx/VaultSprites.gd")
const COLS := 4

@onready var root: Control = $Root
@onready var panel: Control = $Root/Panel
@onready var title: Label = $Root/Panel/Margin/VBox/Title
@onready var grid: GridContainer = $Root/Panel/Margin/VBox/Grid
@onready var close_btn: Button = $Root/Panel/Margin/VBox/Close

var _icons: Array[TextureRect] = []
var _labels: Array[Label] = []
var _buys: Array[Button] = []
var _t: float = 0.0
var _holding_pause: bool = false


func _ready() -> void:
	root.visible = false
	grid.columns = COLS
	VaultArt.ensure()
	for i in GameState.LOOT_ITEMS.size():
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.custom_minimum_size = Vector2(120, 128)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = VaultArt.loot_icon(GameState.LOOT_ITEMS[i])
		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 13)
		var buy := Button.new()
		buy.theme_type_variation = &"PrimaryButton"
		buy.custom_minimum_size = Vector2(104, 40)
		buy.add_theme_font_size_override("font_size", 15)
		buy.visible = false
		buy.pressed.connect(_buy)
		box.add_child(icon)
		box.add_child(name_label)
		box.add_child(buy)
		_buys.append(buy)
		grid.add_child(box)
		_icons.append(icon)
		_labels.append(name_label)
	close_btn.pressed.connect(close)
	$Root/Dim.gui_input.connect(func(event: InputEvent) -> void:
		if root.visible and event is InputEventMouseButton and event.pressed:
			close()
	)
	EventBus.loot_unlocked.connect(func(_id: String) -> void:
		if root.visible:
			_refresh()
	)
	EventBus.cash_changed.connect(func(_a: int, _d: int) -> void:
		if root.visible:
			_refresh()
	)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not root.visible:
		return
	_t += delta
	var slot: int = GameState.loot_unlocked_count()
	if slot >= _icons.size():
		return
	var icon: TextureRect = _icons[slot]
	icon.pivot_offset = icon.size * 0.5
	icon.scale = Vector2.ONE * (1.0 + 0.06 * maxf(0.0, sin(_t * TAU / 0.8))) if GameState.can_buy_loot() else Vector2.ONE


func _buy() -> void:
	var slot: int = GameState.loot_unlocked_count()
	if GameState.buy_next_loot() == "":
		return
	EventBus.juice_hit.emit("claim", 1.0)
	_refresh()
	var icon: TextureRect = _icons[slot]
	icon.pivot_offset = icon.size * 0.5
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(icon, "scale", Vector2(1.25, 1.25), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(icon, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and root.visible:
		_refresh()


func open() -> void:
	if root.visible:
		return
	_refresh()
	_holding_pause = GameState.run_active
	if _holding_pause:
		OverlayPause.push()
	root.visible = true
	panel.scale = Vector2(0.86, 0.86)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_ignore_time_scale(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not root.visible:
		return
	root.visible = false
	if _holding_pause:
		OverlayPause.pop()
		_holding_pause = false


func _refresh() -> void:
	var bonus: int = roundi((GameState.loot_bonus() - 1.0) * 100.0)
	title.text = tr("HIDEOUT_TITLE") + ("   " + tr("HIDEOUT_BONUS") % bonus if bonus > 0 else "")
	close_btn.text = tr("MARKET_CLOSE")
	var owned: int = GameState.loot_unlocked_count()
	for i in _icons.size():
		var unlocked: bool = i < owned
		_icons[i].modulate = Color.WHITE if unlocked else Color(0.12, 0.12, 0.14, 1.0)
		_labels[i].text = tr("LOOT_" + GameState.LOOT_ITEMS[i].to_upper()) if unlocked else "—"
		_labels[i].add_theme_color_override("font_color", Color(0.9, 0.84, 0.6, 1.0) if unlocked else Color(0.35, 0.38, 0.42, 1.0))
		# Only the next slot is for sale; its silhouette is lighter so it reads as "this one".
		var for_sale: bool = i == owned
		_buys[i].visible = for_sale
		_labels[i].visible = not for_sale
		if for_sale:
			_icons[i].modulate = Color(0.45, 0.48, 0.6, 1.0)
			_buys[i].text = tr("MARKET_COST") % GameState.next_loot_price()
			_buys[i].disabled = not GameState.can_buy_loot()
