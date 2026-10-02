class_name RingArena
extends Node2D
## Draws the ring, target arc, and rotating pointer. Pure visual + angle state.

@export var radius: float = 210.0
@export var ring_width: float = 18.0
@export var pointer_length: float = 188.0

var pointer_angle: float = -PI / 2.0
var target_angle: float = 0.0
var rpm: float = 0.55
var spinning := true
var direction: float = 1.0
var glow_pulse: float = 0.0
var last_grade: String = ""
var windows := {"perfect": 7.0, "good": 16.0, "near": 22.0}

var ring_color := Color(0.18, 0.28, 0.42, 1)
var accent := Color(0.18, 0.9, 1.0, 1)
var danger := Color(1.0, 0.28, 0.52, 1)
var gold := Color(1.0, 0.84, 0.28, 1)


func _ready() -> void:
	randomize_target(true)


func _process(delta: float) -> void:
	if spinning:
		pointer_angle += direction * rpm * TAU * delta
	glow_pulse = wrapf(glow_pulse + delta * 2.4, 0.0, TAU)
	queue_redraw()


func randomize_target(snap_pointer: bool = false) -> void:
	target_angle = randf() * TAU
	if snap_pointer:
		pointer_angle = target_angle + PI * 0.72 * direction
	direction *= -1.0 if randf() < 0.35 else 1.0


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, Color(0.05, 0.08, 0.14, 0.9), ring_width + 14.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 80, ring_color, ring_width, true)

	_draw_window_arc(float(windows.near), danger.lerp(Color(0.4, 0.1, 0.2, 0.35), 0.4), ring_width + 10.0)
	_draw_window_arc(float(windows.good), accent, ring_width + 2.0)
	_draw_window_arc(float(windows.perfect), gold, ring_width - 4.0)

	var pulse := 0.55 + 0.45 * sin(glow_pulse)
	var p_col := accent
	if last_grade == "perfect":
		p_col = gold
	elif last_grade == "near_miss":
		p_col = danger
	var tip := Vector2.from_angle(pointer_angle) * pointer_length
	draw_line(Vector2.ZERO, tip, p_col * Color(1, 1, 1, 0.35 + pulse * 0.4), 8.0, true)
	draw_circle(tip, 11.0, p_col)
	draw_circle(Vector2.ZERO, 16.0, Color(0.08, 0.1, 0.16))
	draw_circle(Vector2.ZERO, 10.0, p_col)


func _draw_window_arc(half_deg: float, color: Color, width: float) -> void:
	var half := deg_to_rad(half_deg)
	draw_arc(Vector2.ZERO, radius, target_angle - half, target_angle + half, 32, color, width, true)
