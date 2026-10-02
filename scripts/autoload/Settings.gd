extends Node
## Player preferences (language, sound, vibration). Stored apart from game
## progress so a progress reset never wipes them.

const SETTINGS_PATH := "user://settings.cfg"
const LANGUAGES: PackedStringArray = ["en", "tr"]

var language: String = "en"
var sound_enabled: bool = true
var vibration_enabled: bool = true


func _ready() -> void:
	language = "tr" if OS.get_locale_language() == "tr" else "en"
	_load()
	TranslationServer.set_locale(language)
	_apply_sound()


func set_language(code: String) -> void:
	if code == language or not LANGUAGES.has(code):
		return
	language = code
	TranslationServer.set_locale(language)
	_save()


func set_sound_enabled(enabled: bool) -> void:
	sound_enabled = enabled
	_apply_sound()
	_save()


func set_vibration_enabled(enabled: bool) -> void:
	vibration_enabled = enabled
	_save()


func vibrate(ms: int) -> void:
	# Android exports also need the VIBRATE permission enabled in the export preset.
	if vibration_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


func _apply_sound() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), not sound_enabled)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var saved: String = String(cfg.get_value("general", "language", language))
	if LANGUAGES.has(saved):
		language = saved
	sound_enabled = bool(cfg.get_value("general", "sound", sound_enabled))
	vibration_enabled = bool(cfg.get_value("general", "vibration", vibration_enabled))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("general", "language", language)
	cfg.set_value("general", "sound", sound_enabled)
	cfg.set_value("general", "vibration", vibration_enabled)
	var err: Error = cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("Loop Engine: could not write settings (%s)." % error_string(err))
