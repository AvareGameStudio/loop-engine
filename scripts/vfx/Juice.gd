class_name Juice
extends Node
## Hitstop, camera punch, particle bursts, pointer flash, jackpot glow, haptics.
## Time scale goes through the TimeScale autoload.

@export var camera: Camera2D
@export var burst: GPUParticles2D
@export var pointer: RingPointer
@export var glow: CanvasItem
## Particle buffer size; individual bursts scale down via amount_ratio.
@export var max_burst: int = 48

var _shake: float = 0.0
var _base_zoom: Vector2 = Vector2.ONE
var _zoom_tween: Tween
var _glow_tween: Tween


func _ready() -> void:
	if camera:
		_base_zoom = camera.zoom
	if burst:
		burst.amount = max_burst
	EventBus.juice_hit.connect(_on_juice)


func _process(delta: float) -> void:
	if camera == null:
		return
	var real_dt: float = delta / maxf(Engine.time_scale, 0.001)
	if _shake > 0.01:
		_shake *= exp(-10.0 * real_dt)
		camera.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	elif camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO


func _on_juice(grade: String, intensity: float) -> void:
	match grade:
		"perfect":
			TimeScale.hitstop(0.06)
			_add_shake(7.0 * intensity)
			_punch(1.06)
			_burst(28, Color(0.35, 1.0, 0.85))
			_flash_pointer()
			Settings.vibrate(15)
		"good":
			_add_shake(4.0 * intensity)
			_punch(1.03)
			_burst(16, Color(0.45, 0.75, 1.0))
			Settings.vibrate(8)
		"near_miss":
			TimeScale.hitstop(0.18)
			_add_shake(14.0)
			_punch(0.94)
			_burst(36, Color(1.0, 0.35, 0.55))
			Settings.vibrate(40)
		"miss":
			_add_shake(18.0)
			_punch(0.9)
			_burst(22, Color(0.7, 0.2, 0.3))
			Settings.vibrate(60)
		"jackpot":
			TimeScale.hitstop(0.1)
			_add_shake(12.0)
			_burst(48, Color(1.0, 0.84, 0.2))
			_pulse_glow()
			Settings.vibrate(30)


func _add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _punch(scale: float) -> void:
	if camera == null:
		return
	if _zoom_tween:
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_ignore_time_scale(true)
	_zoom_tween.tween_property(camera, "zoom", _base_zoom * scale, 0.05).set_trans(Tween.TRANS_QUAD)
	_zoom_tween.tween_property(camera, "zoom", _base_zoom, 0.12).set_trans(Tween.TRANS_BACK)


func _burst(amount: int, color: Color) -> void:
	if burst == null:
		return
	# Changing `amount` reallocates the particle buffer; amount_ratio does not.
	burst.amount_ratio = clampf(float(amount) / float(max_burst), 0.0, 1.0)
	burst.modulate = color
	burst.restart()


func _flash_pointer() -> void:
	if pointer:
		pointer.flash()


func _pulse_glow() -> void:
	if glow == null or not (glow.material is ShaderMaterial):
		return
	var mat := glow.material as ShaderMaterial
	if _glow_tween:
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.set_ignore_time_scale(true)
	_glow_tween.tween_property(mat, "shader_parameter/intensity", 2.5, 0.08)
	_glow_tween.parallel().tween_property(mat, "shader_parameter/pulse", PI * 0.5, 0.08).from(0.0)
	_glow_tween.tween_property(mat, "shader_parameter/intensity", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

