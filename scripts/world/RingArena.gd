class_name RingArena
extends Node2D
## Steel vault dial. Tick marks and a machined bezel replace the neon ring;
## the colored gate is the combination notch the pick has to hit.
## The rotating pointer is a child, so the dial only redraws when the target or windows change.

@export var radius: float = 210.0
@export var ring_width: float = 18.0
## Outer approach band length relative to the visible red near-miss band, per side.
@export var outer_band_ratio: float = 1.6
@export var min_lead_deg: float = 90.0
## Seconds of pointer travel guaranteed between respawn and target.
@export var reaction_time: float = 0.35

@onready var pointer: RingPointer = $Pointer

var pointer_angle: float = -PI / 2.0
var rpm: float = 0.55
var spinning: bool = true
var direction: float = 1.0:
	set(value):
		direction = value
		if is_node_ready():
			pointer.direction = value
var target_angle: float = 0.0:
	set(value):
		target_angle = value
		queue_redraw()
var windows: Dictionary = {"perfect": 7.0, "good": 16.0, "near": 22.0}:
	set(value):
		windows = value
		queue_redraw()
var last_grade: String = "":
	set(value):
		last_grade = value
		if is_node_ready():
			pointer.grade = value

var danger := Color(1.0, 0.28, 0.42, 1)
## Outside the near window is a Miss, so this band stays dull steel, never "safe".
var outer_band_color := Color(0.34, 0.36, 0.39, 0.45)
var _rim := Color(0.15, 0.17, 0.22, 1.0)
var _bezel_flash: float = 0.0


func _ready() -> void:
	pointer.direction = direction
	EventBus.direction_flipped.connect(func(_d: float) -> void: _bezel_flash = 1.0)
	randomize_target(true)


func _process(delta: float) -> void:
	if spinning:
		pointer_angle = wrapf(pointer_angle + direction * rpm * TAU * delta, 0.0, TAU)
	pointer.rotation = pointer_angle
	var real_dt: float = delta / maxf(Engine.time_scale, 0.001)
	if _bezel_flash > 0.0:
		_bezel_flash = maxf(0.0, _bezel_flash - real_dt * 4.0)
		queue_redraw()


func randomize_target(snap_pointer: bool = false) -> void:
	if randf() < 0.35:
		direction = -direction
		EventBus.direction_flipped.emit(direction)
	if snap_pointer:
		pointer_angle = -PI / 2.0
	# Target always spawns ahead of the pointer, at least one reaction time away.
	var min_lead: float = maxf(min_lead_deg, rpm * 360.0 * reaction_time)
	var lead: float = deg_to_rad(randf_range(min_lead, 330.0))
	target_angle = wrapf(pointer_angle + lead * direction, 0.0, TAU)


func _draw() -> void:
	var center := Vector2.ZERO
	# Inner mechanism sits under the rim so the dial has depth.
	draw_circle(center, radius - 28.0, Color(0.08, 0.09, 0.12, 1.0))
	# Outer metal rim of the combination lock; flashes white on a direction flip.
	var rim: Color = _rim.lerp(Color.WHITE, _bezel_flash)
	draw_arc(center, radius, 0.0, TAU, 96, rim, 16.0 + 2.0 * _bezel_flash, true)
	_draw_ticks()

	var near: float = float(windows.near)
	var red_band: float = near - float(windows.good)
	_draw_side_bands(near, near + red_band * outer_band_ratio, outer_band_color, 8.0)
	_draw_window_arc(near, danger.lerp(Color(0.25, 0.08, 0.1, 0.55), 0.4), 12.0)
	# The gate the pick has to hit.
	_draw_window_arc(float(windows.good), Color(0.2, 0.95, 0.4, 0.85), 20.0)
	_draw_window_arc(float(windows.perfect), Color(1.0, 0.84, 0.2, 0.95), 8.0)


func _draw_ticks() -> void:
	# 15° steps: a mechanical safe dial, not a smooth neon ring.
	var step := 15
	for deg in range(0, 360, step):
		var angle := deg_to_rad(float(deg))
		var major := deg % 45 == 0
		var inner := radius - (18.0 if major else 10.0)
		var outer := radius + 8.0
		var col := Color(0.82, 0.84, 0.88, 1.0) if major else Color(0.55, 0.58, 0.62, 0.9)
		draw_line(Vector2.from_angle(angle) * inner, Vector2.from_angle(angle) * outer, col, 2.4 if major else 1.2, true)


func _draw_window_arc(half_deg: float, color: Color, width: float) -> void:
	var half: float = deg_to_rad(half_deg)
	draw_arc(Vector2.ZERO, radius, target_angle - half, target_angle + half, 32, color, width, true)


func _draw_side_bands(inner_deg: float, outer_deg: float, color: Color, width: float) -> void:
	var inner: float = deg_to_rad(inner_deg)
	var outer: float = deg_to_rad(outer_deg)
	draw_arc(Vector2.ZERO, radius, target_angle + inner, target_angle + outer, 16, color, width, true)
	draw_arc(Vector2.ZERO, radius, target_angle - outer, target_angle - inner, 16, color, width, true)
