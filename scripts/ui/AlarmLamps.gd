class_name AlarmLamps
extends Control
## Three wall lamps under the vault number. Dark → lit red as strikes land.
## No text: the player reads "two left" from the lamps alone.

const OFF := Color(0.14, 0.15, 0.18, 1.0)
const RIM := Color(0.38, 0.4, 0.44, 1.0)
const LIT := Color(0.98, 0.16, 0.2, 1.0)
const LIT_HALO := Color(0.98, 0.16, 0.2, 0.35)

var level: int = 0
var max_level: int = 3
var _pulse: float = 0.0
var _pop: float = 0.0


func _ready() -> void:
	set_process(false)
	queue_redraw()


func set_level(value: int, cap: int) -> void:
	var rose: bool = value > level
	level = value
	max_level = maxi(cap, 1)
	if rose:
		_pop = 1.0
	set_process(level > 0)
	queue_redraw()


func _process(delta: float) -> void:
	var real_dt: float = delta / maxf(Engine.time_scale, 0.001)
	_pulse = wrapf(_pulse + real_dt * 6.0, 0.0, TAU)
	_pop = maxf(0.0, _pop - real_dt * 4.0)
	queue_redraw()


func _draw() -> void:
	var r: float = minf(size.y * 0.42, 11.0)
	var gap: float = r * 2.0 + 10.0
	var total: float = gap * float(max_level - 1)
	var start_x: float = size.x * 0.5 - total * 0.5
	for i in max_level:
		var at := Vector2(start_x + gap * float(i), size.y * 0.5)
		var lit: bool = i < level
		if lit:
			var breath: float = 0.75 + 0.25 * sin(_pulse + float(i))
			var grow: float = 1.0 + (0.4 * _pop if i == level - 1 else 0.0)
			draw_circle(at, r * 1.8 * grow, Color(LIT_HALO, LIT_HALO.a * breath))
			draw_circle(at, r * grow, LIT)
			draw_circle(at + Vector2(-r * 0.3, -r * 0.3), r * 0.28, Color(1, 0.85, 0.85, 0.9))
		else:
			draw_circle(at, r, OFF)
		draw_arc(at, r, 0.0, TAU, 20, RIM, 1.6, true)
