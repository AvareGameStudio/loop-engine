class_name SettingsPopup
extends CanvasLayer
## Language, sound, and vibration toggles. Pauses the game while open, so it
## must keep processing itself.

const VIBRATION_PREVIEW_MS: int = 30

@onready var root: Control = $Root
@onready var panel: Control = $Root/Panel
@onready var english: Button = $Root/Panel/Margin/VBox/LanguageRow/English
@onready var turkish: Button = $Root/Panel/Margin/VBox/LanguageRow/Turkish
@onready var sound: CheckButton = $Root/Panel/Margin/VBox/Sound
@onready var vibration: CheckButton = $Root/Panel/Margin/VBox/Vibration
@onready var close_btn: Button = $Root/Panel/Margin/VBox/Close

var _was_paused: bool = false


func _ready() -> void:
	root.visible = false
	var languages := ButtonGroup.new()
	english.button_group = languages
	turkish.button_group = languages
	english.pressed.connect(Settings.set_language.bind("en"))
	turkish.pressed.connect(Settings.set_language.bind("tr"))
	sound.toggled.connect(Settings.set_sound_enabled)
	vibration.toggled.connect(_on_vibration_toggled)
	close_btn.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if root.visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if root.visible:
		return
	english.set_pressed_no_signal(Settings.language == "en")
	turkish.set_pressed_no_signal(Settings.language == "tr")
	sound.set_pressed_no_signal(Settings.sound_enabled)
	vibration.set_pressed_no_signal(Settings.vibration_enabled)
	_was_paused = get_tree().paused
	get_tree().paused = true
	root.visible = true
	panel.scale = Vector2(0.86, 0.86)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not root.visible:
		return
	root.visible = false
	get_tree().paused = _was_paused


func _on_vibration_toggled(enabled: bool) -> void:
	Settings.set_vibration_enabled(enabled)
	Settings.vibrate(VIBRATION_PREVIEW_MS)
