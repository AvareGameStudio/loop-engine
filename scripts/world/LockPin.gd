class_name LockPin
extends Node2D
## Tumbler sitting in the combination notch. A hit seats it; the flash shader
## is what the player reads as the pin catching.

@export var radius: float = 210.0

var locked: bool = false
var _flash_tween: Tween


func place(angle: float) -> void:
	rotation = angle
	queue_redraw()


func set_locked(is_locked: bool) -> void:
	if locked == is_locked:
		queue_redraw()
		return
	locked = is_locked
	queue_redraw()


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
	var seat := radius - 8.0
	draw_rect(Rect2(seat - 30.0, -14.0, 36.0, 28.0), Color(0.04, 0.045, 0.06, 1.0), true)
	draw_rect(Rect2(seat - 30.0, -14.0, 36.0, 28.0), Color(0.35, 0.37, 0.4, 1.0), false, 2.0)
	var sunk: float = 16.0 if locked else 0.0
	var body := Color(0.92, 0.74, 0.28, 1.0) if locked else Color(0.78, 0.8, 0.84, 1.0)
	draw_rect(Rect2(seat - 18.0 - sunk, -7.0, 22.0, 14.0), body, true)
	draw_circle(Vector2(seat - sunk, 0.0), 9.0, body)
	draw_circle(Vector2(seat - sunk, 0.0), 3.5, Color(0.12, 0.1, 0.08, 1.0))
