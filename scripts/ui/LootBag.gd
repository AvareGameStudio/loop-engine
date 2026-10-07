class_name LootBag
extends Control
## The thief's duffel bag at the bottom of the screen. Cash is shown as a number
## on the bag and as a gold fill inside it; loot "lands" here with a bounce.
## Fill is relative to the cheapest market upgrade, so a full bag means "go spend".

const LEATHER := Color(0.16, 0.12, 0.1, 1.0)
const LEATHER_HI := Color(0.26, 0.2, 0.16, 1.0)
const STITCH := Color(0.62, 0.5, 0.32, 0.8)
const GOLD := Color(1.0, 0.82, 0.3, 1.0)
const GOLD_DEEP := Color(0.85, 0.6, 0.15, 1.0)

var shown_cash: int = 0
var fill: float = 0.0
var _count_tween: Tween
var _bounce_tween: Tween
var _fill_tween: Tween


func _ready() -> void:
	pivot_offset = size * 0.5
	resized.connect(func() -> void:
		pivot_offset = size * 0.5
		queue_redraw()
	)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


## Rolls the number to `target` and eases the fill. `instant` skips both tweens.
func set_cash(target: int, instant: bool = false) -> void:
	var goal_fill: float = _fill_for(target)
	if _count_tween:
		_count_tween.kill()
	if _fill_tween:
		_fill_tween.kill()
	if instant:
		shown_cash = target
		fill = goal_fill
		queue_redraw()
		return
	_count_tween = create_tween()
	_count_tween.set_ignore_time_scale(true)
	_count_tween.tween_method(_set_shown, float(shown_cash), float(target), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fill_tween = create_tween()
	_fill_tween.set_ignore_time_scale(true)
	_fill_tween.tween_method(_set_fill, fill, goal_fill, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Loot landed: 1.0 → `peak` → 1.0 with a back ease.
func bounce(peak: float = 1.08) -> void:
	if _bounce_tween:
		_bounce_tween.kill()
	scale = Vector2.ONE
	_bounce_tween = create_tween()
	_bounce_tween.set_ignore_time_scale(true)
	_bounce_tween.tween_property(self, "scale", Vector2(peak, peak), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_bounce_tween.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _fill_for(cash: int) -> float:
	var reference: int = maxi(MetaUpgrade.cost("crew"), 1)
	return clampf(float(cash) / float(reference), 0.0, 1.0)


func _set_shown(value: float) -> void:
	shown_cash = int(round(value))
	queue_redraw()


func _set_fill(value: float) -> void:
	fill = value
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var body := Rect2(Vector2(w * 0.08, h * 0.3), Vector2(w * 0.84, h * 0.62))
	# Handles: two arcs above the body.
	var handle_y: float = body.position.y + 6.0
	draw_arc(Vector2(w * 0.36, handle_y), h * 0.2, PI, TAU, 20, STITCH, 5.0, true)
	draw_arc(Vector2(w * 0.64, handle_y), h * 0.2, PI, TAU, 20, STITCH, 5.0, true)
	# Body with a lighter top face.
	_rounded(body, LEATHER, h * 0.14)
	_rounded(Rect2(body.position, Vector2(body.size.x, body.size.y * 0.28)), LEATHER_HI, h * 0.14)
	# Gold inside: fill rises from the bottom of the bag.
	if fill > 0.01:
		var inner := body.grow(-8.0)
		var gold_h: float = inner.size.y * clampf(fill, 0.0, 1.0)
		var gold_rect := Rect2(Vector2(inner.position.x, inner.end.y - gold_h), Vector2(inner.size.x, gold_h))
		_rounded(gold_rect, GOLD_DEEP, 10.0)
		if gold_h > 14.0:
			draw_rect(Rect2(gold_rect.position + Vector2(10.0, 4.0), Vector2(gold_rect.size.x - 20.0, 5.0)), GOLD)
	# Zipper line.
	var zip_y: float = body.position.y + body.size.y * 0.3
	draw_line(Vector2(body.position.x + 14.0, zip_y), Vector2(body.end.x - 14.0, zip_y), STITCH, 2.0, true)
	# Cash number.
	var font: Font = get_theme_default_font()
	var font_size: int = 30
	var text: String = "$%d" % shown_cash
	var text_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline: float = body.position.y + body.size.y * 0.66 + font.get_ascent(font_size) * 0.35
	draw_string_outline(font, Vector2(w * 0.5 - text_w * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0.05, 0.04, 0.03, 1.0))
	draw_string(font, Vector2(w * 0.5 - text_w * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, GOLD)


func _rounded(rect: Rect2, color: Color, radius: float) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(radius))
	draw_style_box(style, rect)
