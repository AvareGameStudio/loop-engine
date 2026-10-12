class_name CityStrip
extends Control
## The road of vaults across the top of the end card: piggy shop -> office -> bank ->
## museum -> casino -> Fort Knox -> moon vault. Cracked cities are in colour, the current one
## is big with a gold ring, the ones ahead are dark silhouettes. Entering a new city pops it.

const CITIES: PackedStringArray = ["piggy", "office", "bank", "museum", "casino", "fort", "moon"]
const AHEAD := Color(0.32, 0.35, 0.48, 0.85)
const ROAD := Color(1.0, 0.84, 0.3, 0.35)
const RING := Color(1.0, 0.84, 0.3, 1.0)

var current: int = 0
var _icons: Array[Texture2D] = []
var _pop: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for city: String in CITIES:
		var path := "res://assets/art/city_%s.png" % city
		_icons.append(load(path) if ResourceLoader.exists(path) else null)


static func index_for(vault_type: String) -> int:
	return maxi(CITIES.find(vault_type), 0)


func set_current(index: int, pop: bool) -> void:
	current = clampi(index, 0, CITIES.size() - 1)
	_pop = 0.0
	queue_redraw()
	if not pop:
		return
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_interval(0.35)
	tw.tween_method(_set_pop, 0.0, 1.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_pop, 1.0, 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_pop(value: float) -> void:
	_pop = value
	queue_redraw()


func _draw() -> void:
	var n: int = CITIES.size()
	var step: float = size.x / float(n)
	var base: float = minf(step * 0.9, size.y * 0.8)
	var y: float = size.y * 0.5
	draw_line(Vector2(step * 0.5, y), Vector2(size.x - step * 0.5, y), ROAD, 3.0, true)
	for i in n:
		var c := Vector2(step * (float(i) + 0.5), y)
		var s: float = base * (1.3 + 0.3 * _pop if i == current else 1.0)
		if i == current:
			draw_circle(c, s * 0.52, Color(RING, 0.18))
			draw_arc(c, s * 0.52, 0.0, TAU, 32, RING, 2.5, true)
		var tex: Texture2D = _icons[i] if i < _icons.size() else null
		if tex == null:
			draw_circle(c, s * 0.3, AHEAD if i > current else RING)
			continue
		var tint: Color = Color.WHITE if i <= current else AHEAD
		draw_texture_rect(tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, tint)
