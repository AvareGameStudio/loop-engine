class_name Juice
extends Node
## Hitstop, camera punch, and particle bursts. Keep all juice on one node
## so time_scale restores cannot fight the input processor.

@onready var camera: Camera2D = $"../Camera2D"
@onready var burst: GPUParticles2D = $"../Arena/Burst"

var _hitstop_left := 0.0
var _shake := 0.0
var _base_zoom := Vector2.ONE


func _ready() -> void:
	if camera:
		_base_zoom = camera.zoom
	EventBus.juice_hit.connect(_on_juice)
	EventBus.jackpot.connect(func(_m: float, _l: String) -> void: _burst(48, Color(1.0, 0.85, 0.25)))
	set_process(true)


func _process(delta: float) -> void:
	if _hitstop_left > 0.0:
		_hitstop_left -= delta / max(Engine.time_scale, 0.001)
		if _hitstop_left <= 0.0 and Engine.time_scale < 0.2:
			Engine.time_scale = 1.0
	if camera == null:
		return
	if _shake > 0.01:
		_shake = lerpf(_shake, 0.0, delta * 10.0)
		camera.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	else:
		camera.offset = Vector2.ZERO


func _on_juice(grade: String, intensity: float) -> void:
	match grade:
		"perfect":
			_hitstop(0.06)
			_shake = 7.0 * intensity
			_punch(1.06)
			_burst(28, Color(0.35, 1.0, 0.85))
		"good":
			_shake = 4.0 * intensity
			_punch(1.03)
			_burst(16, Color(0.45, 0.75, 1.0))
		"near_miss":
			_hitstop(0.18)
			_shake = 14.0
			_punch(0.94)
			_burst(36, Color(1.0, 0.35, 0.55))
		"miss":
			_shake = 18.0
			_punch(0.9)
			_burst(22, Color(0.7, 0.2, 0.3))
		"jackpot":
			_hitstop(0.1)
			_shake = 12.0
			_burst(48, Color(1.0, 0.84, 0.2))


func _hitstop(seconds: float) -> void:
	_hitstop_left = seconds
	Engine.time_scale = 0.08


func _punch(scale: float) -> void:
	if camera == null:
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(camera, "zoom", _base_zoom * scale, 0.05).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(camera, "zoom", _base_zoom, 0.12).set_trans(Tween.TRANS_BACK)


func _burst(amount: int, color: Color) -> void:
	if burst == null:
		return
	burst.amount = amount
	burst.modulate = color
	burst.restart()
