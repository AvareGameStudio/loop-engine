class_name HideoutPopup
extends CanvasLayer
## One room, twelve silhouettes. Owned items are colored; the rest stay dark.

const VaultArt := preload("res://scripts/vfx/VaultSprites.gd")
const COLS := 4

@onready var root: Control = $Root
@onready var panel: Control = $Root/Panel
@onready var title: Label = $Root/Panel/Margin/VBox/Title
@onready var grid: GridContainer = $Root/Panel/Margin/VBox/Grid
@onready var close_btn: Button = $Root/Panel/Margin/VBox/Close

var _icons: Array[TextureRect] = []
var _labels: Array[Label] = []
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
		box.add_child(icon)
		box.add_child(name_label)
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
	title.text = tr("HIDEOUT_TITLE")
	close_btn.text = tr("MARKET_CLOSE")
	var owned: int = GameState.loot_unlocked_count()
	for i in _icons.size():
		var unlocked: bool = i < owned
		_icons[i].modulate = Color.WHITE if unlocked else Color(0.12, 0.12, 0.14, 1.0)
		_labels[i].text = tr("LOOT_" + GameState.LOOT_ITEMS[i].to_upper()) if unlocked else "—"
		_labels[i].add_theme_color_override("font_color", Color(0.9, 0.84, 0.6, 1.0) if unlocked else Color(0.35, 0.38, 0.42, 1.0))
