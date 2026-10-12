class_name Guard
extends Node2D
## Threat is light, not a person. Strike 1 spills red off the left edge.
## Strike 2 drops a cold spotlight from above the screen. Strike 3 leaves the
## strobe to Juice. Heist 1 cuts the light on the third miss: no bust, no beam.

const SPILL := Color(0.95, 0.08, 0.1, 0.28)
const SPOT := Color(1.0, 0.92, 0.55, 0.22)
const SPOT_HARD := Color(1.0, 0.92, 0.55, 0.40)

var _level: int = 0
var _fade: float = 0.0
var _fade_tween: Tween


func _ready() -> void:
	z_index = 1
	EventBus.alarm_changed.connect(_on_alarm)
	EventBus.run_started.connect(func() -> void: _on_alarm(0, GameState.ALARM_MAX))
	queue_redraw()


func _on_alarm(level: int, _max_level: int) -> void:
	var show: int = clampi(level, 0, 3)
	# Heist 1 never catches. The third miss drops the light instead of a beam.
	if show >= 3 and GameState.is_first_heist(GameState.current_stage):
		show = 0
	_level = show
	var goal: float = 0.0 if show <= 0 else 1.0
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_ignore_time_scale(true)
	_fade_tween.tween_method(_set_fade, _fade, goal, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_fade(value: float) -> void:
	_fade = value
	queue_redraw()


func _draw() -> void:
	if _level <= 0 or _fade <= 0.01:
		return
	var spill := SPILL
	spill.a *= _fade
	# Left edge of the 720-wide portrait, in world space (camera sits at x=360).
	draw_rect(Rect2(0.0, -120.0, 72.0, 1500.0), spill)
	if _level < 2:
		return
	var spot := SPOT_HARD if _level >= 3 else SPOT
	spot.a *= _fade
	draw_set_transform(Vector2(360.0, -40.0), 0.0, Vector2(210.0, 90.0))
	draw_circle(Vector2.ZERO, 1.0, spot)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
