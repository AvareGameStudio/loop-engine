extends Node2D
## Ad-only tutorial finger: hovers by the dial and presses on every tap the director makes,
## with a white ring rippling out from the fingertip. Never part of the game itself.

const HAND := "res://assets/art/tap_hand.png"
## Fingertip as a fraction of the hand texture (index finger points straight down).
const TIP := Vector2(0.56, 0.94)
const HEIGHT: float = 150.0

var _tex: Texture2D = load(HAND) if ResourceLoader.exists(HAND) else null
var _press: float = 0.0
var _ripple: float = 0.0
var _ripple_tween: Tween
var _press_tween: Tween


func tap() -> void:
	if _press_tween:
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.set_ignore_time_scale(true)
	_press_tween.tween_property(self, "_press", 1.0, 0.05)
	_press_tween.tween_property(self, "_press", 0.0, 0.07)
	if _ripple_tween:
		_ripple_tween.kill()
	_ripple = 0.0
	_ripple_tween = create_tween()
	_ripple_tween.set_ignore_time_scale(true)
	_ripple_tween.tween_property(self, "_ripple", 1.0, 0.35).set_ease(Tween.EASE_OUT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _ripple > 0.0 and _ripple < 1.0:
		draw_arc(Vector2.ZERO, 14.0 + 46.0 * _ripple, 0.0, TAU, 40, Color(1, 1, 1, 0.9 * (1.0 - _ripple)), 5.0, true)
	if _tex == null:
		draw_circle(Vector2.ZERO, 18.0 * (1.0 - 0.15 * _press), Color(1, 1, 1, 0.85))
		return
	# 1.0 -> 0.85 press, pivoting on the fingertip so the tip stays on the spot.
	var s: float = 1.0 - 0.15 * _press
	var h: float = HEIGHT * s
	var w: float = h * float(_tex.get_width()) / float(_tex.get_height())
	draw_texture_rect(_tex, Rect2(-Vector2(w, h) * TIP, Vector2(w, h)), false)
