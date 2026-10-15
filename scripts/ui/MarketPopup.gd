class_name MarketPopup
extends CanvasLayer
## Spend cash on the Crew, Wide Gate, and glove skins. Pauses an active vault while
## open; between vaults the tree keeps going, so affordability updates live.

@onready var root: Control = $Root
@onready var panel: Control = $Root/Panel
@onready var balance_label: Label = $Root/Panel/Margin/VBox/Balance
@onready var passive_label: Label = $Root/Panel/Margin/VBox/Passive
@onready var items_box: VBoxContainer = $Root/Panel/Margin/VBox/Items
@onready var close_btn: Button = $Root/Panel/Margin/VBox/Close

## id -> {"name": Label, "effect": Label, "buy": Button}
var _rows: Dictionary[String, Dictionary] = {}
var _skin_rows: Dictionary[String, Dictionary] = {}
var _hideout_label: Label
var _holding_pause: bool = false
## Glove skins as a 4-wide grid of painted gloves (assets/art/glove_<id>.png), no copy.
const SKIN_COLS: int = 4
const SKIN_EQUIPPED := Color(0.3, 0.95, 0.45, 1.0)
var _skin_grid: GridContainer


func _ready() -> void:
	root.visible = false
	for item: Dictionary in MetaUpgrade.CATALOG:
		_rows[String(item.id)] = _make_row(String(item.id))
	_skin_grid = GridContainer.new()
	_skin_grid.columns = SKIN_COLS
	_skin_grid.add_theme_constant_override("h_separation", 10)
	_skin_grid.add_theme_constant_override("v_separation", 8)
	items_box.add_child(_skin_grid)
	for skin_id: String in GameState.GLOVE_IDS:
		_skin_rows[skin_id] = _make_skin_cell(skin_id)
	close_btn.pressed.connect(close)
	_hideout_label = Label.new()
	_hideout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hideout_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hideout_label.add_theme_font_size_override("font_size", 15)
	_hideout_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 1))
	_hideout_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_hideout_label.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			var ui := get_parent()
			if ui and ui.get_node_or_null("HideoutPopup"):
				ui.get_node("HideoutPopup").open()
	)
	var box: Node = items_box.get_parent()
	box.add_child(_hideout_label)
	box.move_child(_hideout_label, items_box.get_index())
	EventBus.cosmetic_equipped.connect(func(_id: String) -> void: _refresh())
	EventBus.loot_unlocked.connect(func(_id: String) -> void:
		if root.visible:
			_refresh()
	)
	EventBus.cash_changed.connect(_on_wallet_changed)


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
	_holding_pause = GameState.run_active
	if _holding_pause:
		OverlayPause.push()
	root.visible = true
	_punch(panel, 0.86)


func close() -> void:
	if not root.visible:
		return
	root.visible = false
	if _holding_pause:
		OverlayPause.pop()
		_holding_pause = false


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


func _make_skin_cell(id: String) -> Dictionary:
	var cell := VBoxContainer.new()
	cell.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(72, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var art := "res://assets/art/glove_%s.png" % id
	icon.texture = load(art) if ResourceLoader.exists(art) else VaultSprites.cuff_for(id)
	var buy := Button.new()
	buy.custom_minimum_size = Vector2(0, 40)
	buy.add_theme_font_size_override("font_size", 14)
	buy.pressed.connect(_buy_skin.bind(id))
	cell.add_child(icon)
	cell.add_child(buy)
	_skin_grid.add_child(cell)
	return {"icon": icon, "buy": buy}


func _buy_skin(id: String) -> void:
	if GameState.buy_glove(id):
		_refresh()
		_punch(_skin_rows[id].buy as Control, 1.15)


func _buy(id: String) -> void:
	if MetaUpgrade.purchase(id):
		_refresh()
		_punch(_rows[id].buy as Control, 1.15)


func _on_wallet_changed(_amount: int, _delta: int) -> void:
	if root.visible:
		_refresh()


func _refresh() -> void:
	balance_label.text = tr("MARKET_BALANCE") % GameState.cash
	passive_label.text = tr("MARKET_PASSIVE")
	passive_label.visible = GameState.crew_unlocked()
	_hideout_label.text = tr("MARKET_HIDEOUT") % [GameState.loot_unlocked_count(), GameState.LOOT_ITEMS.size()]
	for item: Dictionary in MetaUpgrade.CATALOG:
		var id: String = String(item.id)
		var key: String = id.to_upper()
		var row: Dictionary = _rows[id]
		(row.buy as Control).get_parent().visible = MetaUpgrade.unlocked(id)
		(row.name as Label).text = tr("MARKET_%s_NAME" % key)
		(row.effect as Label).text = tr("MARKET_%s_EFFECT" % key)
		var buy: Button = row.buy
		if MetaUpgrade.at_cap(id):
			buy.text = tr("MARKET_MAX")
			buy.disabled = true
		else:
			buy.text = tr("MARKET_COST") % MetaUpgrade.cost(id)
			buy.disabled = not MetaUpgrade.can_afford(id)
	for skin_id: String in GameState.GLOVE_IDS:
		var cell: Dictionary = _skin_rows[skin_id]
		var skin_buy: Button = cell.buy
		var icon: TextureRect = cell.icon
		var owned: bool = GameState.owns_glove(skin_id)
		var skin_cost: int = GameState.glove_cost(skin_id)
		icon.modulate = Color.WHITE if owned else Color(0.55, 0.58, 0.68, 1.0)
		skin_buy.theme_type_variation = &""
		if GameState.equipped_gloves == skin_id:
			skin_buy.text = tr("MARKET_SKIN_EQUIPPED")
			skin_buy.disabled = true
			skin_buy.add_theme_color_override("font_disabled_color", SKIN_EQUIPPED)
		elif owned:
			skin_buy.text = tr("MARKET_SKIN_EQUIP")
			skin_buy.disabled = false
		elif skin_cost <= 0:
			# Ad and Big Heist drops only.
			skin_buy.text = tr("MARKET_SKIN_DROP")
			skin_buy.disabled = true
		else:
			skin_buy.text = tr("MARKET_COST") % skin_cost
			skin_buy.disabled = GameState.cash < skin_cost
			skin_buy.theme_type_variation = &"PrimaryButton"


func _punch(target: Control, from_scale: float) -> void:
	target.scale = Vector2(from_scale, from_scale)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_ignore_time_scale(true)
	tw.tween_property(target, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
