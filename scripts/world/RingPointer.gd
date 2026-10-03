class_name RingPointer
extends Node2D
## Lockpick swept around the vault dial. The shaft is steel; the tip is a laser
## tooth bent along travel. RingArena drives `rotation`.

@export var length: float = 200.0

var accent := Color(0.18, 0.9, 1.0, 1)
var danger := Color(1.0, 0.28, 0.52, 1)
var gold := Color(1.0, 0.84, 0.28, 1)

var direction: float = 1.0:
	set(value):
		if value != direction:
			_flip_flash = 1.0
		direction = value
		queue_redraw()
var grade: String = "":
	set(value):
		grade = value
		queue_redraw()

var _pulse: float = 0.0
var _flip_flash: float = 0.0
var _flash_tween: Tween


func _process(delta: float) -> void:
	var real_dt: float = delta / maxf(Engine.time_scale, 0.001)
	_pulse = wrapf(_pulse + real_dt * 2.4, 0.0, TAU)
	self_modulate.a = 0.88 + 0.12 * sin(_pulse)
	if _flip_flash > 0.0:
		_flip_flash = maxf(0.0, _flip_flash - real_dt * 2.5)
		queue_redraw()


## Drives hit_flash.gdshader; runs in real time so hitstop doesn't stretch it.
## `peak` is Perfect Power: a freshly bought upgrade flashes harder on the next Perfect.
func flash(seconds: float = 0.16, peak: float = 1.0) -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	if _flash_tween:
		_flash_tween.kill()
	mat.set_shader_parameter("amount", peak)
	_flash_tween = create_tween()
	_flash_tween.set_ignore_time_scale(true)
	_flash_tween.tween_property(mat, "shader_parameter/amount", 0.0, seconds)


func _draw() -> void:
	var tip := Vector2(length, 0.0)
	# Steel stethoscope arm. The red diaphragm is the contact point.
	draw_colored_polygon(PackedVector2Array([
		Vector2(16.0, -6.0),
		Vector2(length - 20.0, -3.2),
		Vector2(length - 16.0, 3.2),
		Vector2(16.0, 6.0),
	]), Color(0.62, 0.64, 0.68, 1.0))
	draw_line(Vector2(20.0, 0.0), tip - Vector2(18.0, 0.0), Color(0.9, 0.92, 0.94, 0.9), 2.0, true)
	draw_circle(tip, 18.0, Color(0.1, 0.11, 0.13, 1.0))
	draw_arc(tip, 18.0, 0.0, TAU, 28, Color(0.78, 0.8, 0.84, 1.0), 3.0, true)
	draw_circle(tip, 8.0, Color(0.95, 0.22, 0.18, 1.0))
	draw_circle(tip, 3.0, Color(1.0, 0.85, 0.8, 1.0))
	var tooth := tip + Vector2(0.0, direction * (16.0 + 8.0 * _flip_flash))
	draw_line(tip, tooth, Color(0.9, 0.22, 0.18, 1.0), 3.0, true)
	draw_circle(Vector2.ZERO, 16.0, Color(0.2, 0.21, 0.24, 1.0))
	draw_circle(Vector2.ZERO, 7.0, Color(0.72, 0.74, 0.78, 1.0))


func _grade_color() -> Color:
	match grade:
		"perfect":
			return gold
		"near_miss", "miss":
			return danger
		_:
			return accent
