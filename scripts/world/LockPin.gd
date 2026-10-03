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
	var seat := radius - 6.0
	# Brass collar set into the dial, then a steel bolt that sinks when it catches.
	draw_rect(Rect2(seat - 34.0, -16.0, 40.0, 32.0), Color(0.28, 0.2, 0.08, 1.0), true)
	draw_rect(Rect2(seat - 34.0, -16.0, 40.0, 32.0), Color(0.72, 0.58, 0.22, 1.0), false, 2.0)
	var sunk: float = 18.0 if locked else 0.0
	var body := Color(0.55, 0.58, 0.62, 1.0) if not locked else Color(0.95, 0.78, 0.28, 1.0)
	draw_rect(Rect2(seat - 22.0 - sunk, -6.0, 28.0, 12.0), body, true)
	draw_circle(Vector2(seat + 8.0 - sunk, 0.0), 10.0, body)
	draw_line(Vector2(seat + 4.0 - sunk, -4.0), Vector2(seat + 12.0 - sunk, 4.0), Color(0.12, 0.1, 0.08, 1.0), 2.0, true)
	if locked:
		draw_line(Vector2(seat - 8.0, -12.0), Vector2(seat + 6.0, 12.0), Color(1.0, 0.9, 0.5, 0.9), 2.0, true)
