class_name RingPointer
extends Node2D
## Rotating pointer, travel-direction chevron, and hub. Drawn along +X;
## RingArena drives `rotation`, so steady spinning costs no redraw.

@export var length: float = 188.0

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
	_pulse = wrapf(_pulse + delta * 2.4, 0.0, TAU)
	self_modulate.a = 0.8 + 0.2 * sin(_pulse)
	if _flip_flash > 0.0:
		_flip_flash = maxf(0.0, _flip_flash - delta * 2.5)
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
	var col: Color = _grade_color()
	var tip := Vector2(length, 0.0)
	draw_line(Vector2.ZERO, tip, col * Color(1, 1, 1, 0.6), 8.0, true)
	draw_circle(tip, 11.0, col)

	# Local +Y is the direction of increasing angle, i.e. travel for direction = +1.
	var reach: float = direction * (18.0 + 10.0 * _flip_flash)
	var arrow_col: Color = col.lerp(Color.WHITE, _flip_flash)
	draw_colored_polygon(PackedVector2Array([
		tip + Vector2(-7.0, reach * 0.55),
		tip + Vector2(0.0, reach * 1.25),
		tip + Vector2(7.0, reach * 0.55),
	]), arrow_col)

	draw_circle(Vector2.ZERO, 16.0, Color(0.08, 0.1, 0.16))
	draw_circle(Vector2.ZERO, 10.0, col)


func _grade_color() -> Color:
	match grade:
		"perfect":
			return gold
		"near_miss", "miss":
			return danger
		_:
			return accent
