class_name QuestRing
extends Control
## Circular "Unfinished Quest Bar" for one Zeigarnik loop. The focus ring (the
## unfinished loop closest to done) pulses gold so the gap is what the eye lands on.

const TRACK := Color(0.12, 0.18, 0.28, 1)
const OPEN := Color(0.45, 0.9, 1.0, 1)
const FOCUS := Color(1.0, 0.84, 0.3, 1)
const DONE := Color(0.3, 0.95, 0.45, 1)

@export var thickness: float = 10.0
@export var font_size: int = 20

var progress: float = 0.0
var complete: bool = false
var focused: bool = false
var _pulse: float = 0.0
var _tween: Tween


func _ready() -> void:
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


func set_state(value: float, is_complete: bool, is_focus: bool) -> void:
	complete = is_complete
	focused = is_focus
	set_process(focused)
	value = clampf(value, 0.0, 1.0)
	if is_equal_approx(value, progress):
		queue_redraw()
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_progress, progress, value, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_progress(value: float) -> void:
	progress = value
	queue_redraw()


func _process(delta: float) -> void:
	_pulse = wrapf(_pulse + delta * 3.0, 0.0, TAU)
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - thickness * 1.5
	var color: Color = DONE if complete else (FOCUS if focused else OPEN)
	draw_arc(center, radius, 0.0, TAU, 64, TRACK, thickness, true)
	if progress > 0.001:
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 64, color, thickness, true)
	if focused:
		var alpha: float = 0.2 + 0.4 * (0.5 + 0.5 * sin(_pulse))
		draw_arc(center, radius + thickness, 0.0, TAU, 64, Color(FOCUS, alpha), 2.0, true)
	var font: Font = get_theme_default_font()
	var text: String = tr("QUEST_PERCENT") % roundi(progress * 100.0)
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline: float = center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(center.x - width * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
