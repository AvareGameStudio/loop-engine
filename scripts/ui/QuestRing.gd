class_name QuestRing
extends Control
## Unfinished circle (Zeigarnik). The filled arc is the work done; the remaining
## slice is a blinking dashed neon gap so the eye lands on what is still open.

const TRACK := Color(0.12, 0.18, 0.28, 1)
const OPEN := Color(0.45, 0.9, 1.0, 1)
const FOCUS := Color(1.0, 0.84, 0.3, 1)
const DONE := Color(0.3, 0.95, 0.45, 1)
const GAP := Color(1.0, 0.55, 1.0, 1)

@export var thickness: float = 10.0
@export var font_size: int = 20

var progress: float = 0.0
var complete: bool = false
var focused: bool = false
var _pulse: float = 0.0
var _redraw_acc: float = 0.0
var _tween: Tween


func _ready() -> void:
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


func set_state(value: float, is_complete: bool, is_focus: bool) -> void:
	complete = is_complete
	focused = is_focus
	set_process(not complete)
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
	_pulse = wrapf(_pulse + delta * 4.0, 0.0, TAU)
	_redraw_acc += delta
	if _redraw_acc < 0.05:
		return
	_redraw_acc = 0.0
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - thickness * 1.8
	var color: Color = DONE if complete else (FOCUS if focused else OPEN)
	var pins: int = 8
	var seated: int = pins if complete else clampi(roundi(progress * float(pins)), 0, pins - 1 if progress < 0.999 else pins)
	for i in pins:
		var angle: float = -PI * 0.5 + TAU * float(i) / float(pins)
		var pos: Vector2 = center + Vector2.from_angle(angle) * radius
		var locked: bool = i < seated
		draw_circle(pos, thickness * 0.95, Color(0.08, 0.09, 0.12, 1.0))
		draw_arc(pos, thickness * 0.95, 0.0, TAU, 12, Color(0.4, 0.42, 0.46, 1.0), 1.5, true)
		var pin_color: Color = color if locked else TRACK
		var pin_radius: float = thickness * (0.42 if locked else 0.72)
		draw_circle(pos, pin_radius, pin_color)
		if locked:
			draw_line(pos, center + Vector2.from_angle(angle) * (radius - thickness * 1.3), pin_color, 2.2, true)
		elif focused:
			var blink: float = 0.35 + 0.65 * (0.5 + 0.5 * sin(_pulse + float(i)))
			draw_arc(pos, thickness * 1.15, 0.0, TAU, 12, Color(GAP, blink), 1.6, true)
	var font: Font = get_theme_default_font()
	var text: String = tr("QUEST_PERCENT") % roundi(progress * 100.0)
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline: float = center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(center.x - width * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
