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
	var tip_color := Color(1.0, 0.2, 0.2)
	var beam := tip_color.lerp(_grade_color(), 0.2)
	# Soft beam, then a sharp core from the hub out to the dial.
	draw_line(Vector2(16.0, 0.0), tip, Color(beam, 0.35), 16.0, true)
	draw_line(Vector2(16.0, 0.0), tip, beam, 3.2, true)
	draw_line(Vector2(16.0, 0.0), tip, Color(1.0, 0.92, 0.92, 1.0), 1.2, true)
	# Precision tip. A short tooth still shows travel direction.
	var tooth := tip + Vector2(4.0, direction * (14.0 + 6.0 * _flip_flash))
	draw_line(tip, tooth, tip_color, 3.0, true)
	draw_circle(tip, 8.0, tip_color)
	draw_circle(tip, 3.2, Color(1.0, 0.9, 0.9))
	# Hub at the base of the needle.
	draw_circle(Vector2.ZERO, 16.0, Color(0.1, 0.11, 0.14))
	draw_circle(Vector2.ZERO, 7.0, Color(0.72, 0.76, 0.82))


func _grade_color() -> Color:
	match grade:
		"perfect":
			return gold
		"near_miss", "miss":
			return danger
		_:
			return accent
