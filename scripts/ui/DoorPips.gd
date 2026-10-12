class_name DoorPips
extends Control
## Three small vault doors at the top of the HUD: where you are in the heist.
## Cracked = gold and swung open, current = steel with a breathing white rim, ahead = dark.
## Square doors, not circles, so they never read as the round alarm lamps.

const AHEAD := Color(0.14, 0.15, 0.18, 1.0)
const STEEL := Color(0.42, 0.45, 0.5, 1.0)
const RIM := Color(0.38, 0.4, 0.44, 1.0)
const CURRENT_RIM := Color(1.0, 1.0, 1.0, 1.0)
const GOLD := Color(1.0, 0.84, 0.3, 1.0)
const GOLD_DARK := Color(0.62, 0.46, 0.12, 1.0)
const DOOR_SIZE := Vector2(34, 44)
const GAP: float = 16.0
## Crack pop: 1.0 → 1.25 → 1.0 over 150 ms.
const POP_PEAK: float = 1.25
const POP_SEC: float = 0.15

var doors: int = 3
var cracked: int = 0
var golden: bool = false
var _pulse: float = 0.0
## Per-door scale, so only the door that just cracked bounces.
var _scale: PackedFloat32Array = [1.0, 1.0, 1.0]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_state(cracked_count: int, door_count: int, is_golden: bool) -> void:
	doors = maxi(door_count, 1)
	cracked = clampi(cracked_count, 0, doors)
	golden = is_golden
	_scale.resize(doors)
	for i in doors:
		_scale[i] = 1.0
	queue_redraw()


## The door at `index` just cracked: fill it gold and bounce it.
func crack(index: int) -> void:
	cracked = clampi(maxi(cracked, index + 1), 0, doors)
	if index < 0 or index >= doors:
		queue_redraw()
		return
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_method(_set_scale.bind(index), 1.0, POP_PEAK, POP_SEC * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_scale.bind(index), POP_PEAK, 1.0, POP_SEC * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_scale(value: float, index: int) -> void:
	if index < _scale.size():
		_scale[index] = value
	queue_redraw()


func _process(delta: float) -> void:
	_pulse = wrapf(_pulse + delta / maxf(Engine.time_scale, 0.001) * 5.0, 0.0, TAU)
	queue_redraw()


func _draw() -> void:
	var total: float = DOOR_SIZE.x * float(doors) + GAP * float(doors - 1)
	var x: float = size.x * 0.5 - total * 0.5
	for i in doors:
		var centre := Vector2(x + DOOR_SIZE.x * 0.5, size.y * 0.5)
		_draw_door(i, centre, _scale[i] if i < _scale.size() else 1.0)
		x += DOOR_SIZE.x + GAP


func _draw_door(i: int, centre: Vector2, s: float) -> void:
	var half: Vector2 = DOOR_SIZE * 0.5 * s
	var rect := Rect2(centre - half, half * 2.0)
	var rim_color: Color = GOLD if golden else RIM
	if i < cracked:
		# Swung open: the frame shows the gold hoard, the door leaf hangs off the left hinge.
		draw_rect(rect, GOLD)
		draw_rect(rect.grow(-4.0 * s), Color(1.0, 0.95, 0.7, 1.0))
		var leaf := PackedVector2Array([
			rect.position, rect.position + Vector2(-10.0 * s, 6.0 * s),
			rect.position + Vector2(-10.0 * s, rect.size.y - 6.0 * s), rect.position + Vector2(0.0, rect.size.y),
		])
		draw_colored_polygon(leaf, GOLD_DARK)
		draw_rect(rect, GOLD_DARK, false, 2.0)
		return
	var current: bool = i == cracked
	draw_rect(rect, STEEL if current else AHEAD)
	# Dial in the middle of the door.
	draw_circle(centre, 7.0 * s, AHEAD if current else Color(0.09, 0.1, 0.12, 1.0))
	draw_arc(centre, 7.0 * s, 0.0, TAU, 16, rim_color, 1.5, true)
	if current:
		var breath: float = 0.55 + 0.45 * sin(_pulse)
		draw_rect(rect.grow(3.0), Color(CURRENT_RIM, 0.25 * breath), false, 4.0)
		draw_rect(rect, Color(CURRENT_RIM, 0.6 + 0.4 * breath), false, 2.0)
	else:
		draw_rect(rect, rim_color, false, 1.6)
