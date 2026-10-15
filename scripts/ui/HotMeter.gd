class_name HotMeter
extends Control
## Makes Hot Hands visible as a goal and as a reward.
## Under the grade word: one flame per Perfect needed. Each Perfect lights the next flame
## (pop 1.0 -> 1.35 -> 1.0); a strike breaks the row (red flash, flames drop). Hidden at 0.
## Lighting it: the "flame x2" badge slams in at 1.6x and settles over 0.35 s, then breathes
## while it burns. No text banner: the fire ring, the badge and the arpeggio already say it.

const FLAME := Color(1.0, 0.5, 0.12, 1.0)
const FLAME_CORE := Color(1.0, 0.85, 0.35, 1.0)
const FLAME_OFF := Color(0.3, 0.32, 0.42, 0.75)
const BROKEN := Color(1.0, 0.25, 0.3, 1.0)
const FLAME_W: float = 26.0
const GAP: float = 12.0

var _count: int = 0
var _needed: int = 4
var _active: bool = false
var _pop: PackedFloat32Array = []
var _break: float = 0.0
var _banner: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.hot_streak.connect(_on_streak)
	EventBus.hot_hands.connect(_on_hot)
	EventBus.run_started.connect(func() -> void:
		_count = 0
		_active = false
		_banner = 0.0
		queue_redraw()
	)


func _process(delta: float) -> void:
	_t += delta / maxf(Engine.time_scale, 0.001)
	if _active or _count > 0 or _break > 0.0 or _banner > 0.0:
		queue_redraw()


func _on_streak(count: int, needed: int, broken: bool) -> void:
	_needed = maxi(needed, 1)
	_pop.resize(_needed)
	if broken and _count >= 1:
		_break = 1.0
		var tw := create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_property(self, "_break", 0.0, 0.45)
	elif count > _count and count <= _needed:
		var i: int = count - 1
		var tw := create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_method(func(v: float) -> void: _pop[i] = v, 1.35, 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_count = count
	queue_redraw()


func _on_hot(on: bool) -> void:
	_active = on
	_count = 0
	if not on:
		_banner = 0.0
		queue_redraw()
		return
	# `_banner` is the badge's extra scale now: 0.6 -> 0 (1.6x -> 1.0x).
	_banner = 0.6
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(self, "_banner", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var cx: float = size.x * 0.5
	if _active:
		# Badge while it burns: flame + "x2" breathing 6%, slammed in at 1.6x.
		var s: float = (1.0 + 0.06 * sin(_t * 7.0)) * (1.0 + _banner)
		_flame(Vector2(cx - 30.0, 34.0), 30.0 * s, 1.0)
		_text(font, Vector2(cx + 14.0, 46.0), "x2", int(34 * s), FLAME_CORE, false)
		return
	if _count <= 0 and _break <= 0.0:
		return
	var total: float = FLAME_W * _needed + GAP * (_needed - 1)
	var x: float = cx - total * 0.5 + FLAME_W * 0.5
	for i in _needed:
		var lit: bool = i < _count
		var p: float = _pop[i] if i < _pop.size() and _pop[i] > 0.0 else 1.0
		if _break > 0.0:
			_flame(Vector2(x, 30.0 + 18.0 * (1.0 - _break)), FLAME_W * 0.9, _break, BROKEN)
		else:
			_flame(Vector2(x, 30.0), FLAME_W * p, 1.0 if lit else 0.0)
		x += FLAME_W + GAP


func _text(font: Font, at: Vector2, text: String, fs: int, color: Color, center: bool) -> void:
	fs = maxi(fs, 1)
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(at.x - (w * 0.5 if center else 0.0), at.y)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0.05, 0.02, 0.0, color.a))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## Teardrop flame; `lit` 0 = grey outline slot, 1 = burning (flickers).
func _flame(c: Vector2, w: float, lit: float, tint: Color = FLAME) -> void:
	var h: float = w * 1.35
	var flick: float = 1.0 + 0.08 * sin(_t * 18.0 + c.x) * lit
	var pts := PackedVector2Array()
	for k in 16:
		var a: float = TAU * float(k) / 16.0
		var v := Vector2(sin(a) * w * 0.5, -cos(a) * h * 0.5)
		if v.y < 0.0:
			v.x *= 1.0 + v.y / (h * 0.5) * 0.75
			v.y *= flick
		pts.append(c + v)
	if lit <= 0.0:
		draw_polyline(pts + PackedVector2Array([pts[0]]), FLAME_OFF, 2.0, true)
		return
	draw_colored_polygon(pts, Color(tint, tint.a * lit))
	var inner := PackedVector2Array()
	for v in pts:
		inner.append(c + (v - c) * 0.55 + Vector2(0, h * 0.12))
	draw_colored_polygon(inner, Color(FLAME_CORE, lit))
