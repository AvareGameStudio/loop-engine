class_name QuestRing
extends Control
## Unfinished circle (Zeigarnik). The filled arc is the work done; the remaining
## slice is a blinking dashed neon gap so the eye lands on what is still open.

const TRACK := Color(0.12, 0.18, 0.28, 1)
const OPEN := Color(0.45, 0.9, 1.0, 1)
const FOCUS := Color(1.0, 0.84, 0.3, 1)
const DONE := Color(0.3, 0.95, 0.45, 1)
const GAP := Color(1.0, 0.55, 1.0, 1)
const DASH_RAD: float = 0.11
const GAP_RAD: float = 0.07

@export var thickness: float = 10.0
@export var font_size: int = 20

var progress: float = 0.0
var complete: bool = false
var focused: bool = false
var _pulse: float = 0.0
var _tween: Tween


func _ready() -> void:
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


func set_state(value: float, is_complete: bool, is_focus: bool) -> void:
	complete = is_complete
	focused = is_focus
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
	# Always pulse: the unfinished gap has to blink even when this ring is not the focus.
	_pulse = wrapf(_pulse + delta * 4.0, 0.0, TAU)
	if not complete and progress < 0.999:
		queue_redraw()
	elif focused:
		queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - thickness * 1.5
	var color: Color = DONE if complete else (FOCUS if focused else OPEN)
	var start: float = -PI * 0.5
	draw_arc(center, radius, 0.0, TAU, 64, TRACK, thickness, true)
	if progress > 0.001:
		draw_arc(center, radius, start, start + TAU * progress, 64, color, thickness, true)
	if not complete and progress < 0.999:
		# Zeigarnik: the missing slice is the brightest thing on the ring.
		var blink: float = 0.45 + 0.55 * (0.5 + 0.5 * sin(_pulse))
		_draw_dashed_arc(center, radius, start + TAU * progress, start + TAU, Color(GAP, blink), thickness + 1.5)
	if focused:
		var alpha: float = 0.2 + 0.4 * (0.5 + 0.5 * sin(_pulse))
		draw_arc(center, radius + thickness, 0.0, TAU, 64, Color(FOCUS, alpha), 2.0, true)
	var font: Font = get_theme_default_font()
	var text: String = tr("QUEST_PERCENT") % roundi(progress * 100.0)
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline: float = center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(center.x - width * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_dashed_arc(center: Vector2, radius: float, from_a: float, to_a: float, color: Color, width: float) -> void:
	var a: float = from_a
	while a < to_a - 0.001:
		var b: float = minf(a + DASH_RAD, to_a)
		draw_arc(center, radius, a, b, 8, color, width, true)
		a += DASH_RAD + GAP_RAD
