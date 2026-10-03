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
@onready var pin: LockPin = $LockPin

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
		if is_node_ready() and pin:
			pin.place(value)
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
			if pin:
				pin.set_locked(value == "perfect" or value == "good")

var danger := Color(1.0, 0.28, 0.42, 1)
## Outside the near window is a Miss, so this band stays dull steel, never "safe".
var outer_band_color := Color(0.34, 0.36, 0.39, 0.45)
var _rim := Color(0.15, 0.17, 0.22, 1.0)
var _gate := Color(0.2, 0.95, 0.4, 0.85)
var _bezel_flash: float = 0.0
var _door: float = 0.0


func _ready() -> void:
	pointer.direction = direction
	EventBus.direction_flipped.connect(func(_d: float) -> void: _bezel_flash = 1.0)
	EventBus.stage_cleared.connect(func(_index: int, _payout: int) -> void: _door = 1.0)
	EventBus.cosmetic_equipped.connect(_apply_skin)
	_apply_skin(GameState.equipped_dial)
	randomize_target(true)
	if pin:
		pin.place(target_angle)


func _process(delta: float) -> void:
	if spinning:
		pointer_angle = wrapf(pointer_angle + direction * rpm * TAU * delta, 0.0, TAU)
	pointer.rotation = pointer_angle
	var real_dt: float = delta / maxf(Engine.time_scale, 0.001)
	if _bezel_flash > 0.0 or _door > 0.0:
		_bezel_flash = maxf(0.0, _bezel_flash - real_dt * 4.0)
		_door = maxf(0.0, _door - real_dt * 1.4)
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
	if pin:
		pin.set_locked(false)


func _apply_skin(id: String) -> void:
	match id:
		"gold":
			_rim = Color(0.46, 0.32, 0.1, 1.0)
			_gate = Color(1.0, 0.78, 0.22, 0.9)
		"obsidian":
			_rim = Color(0.05, 0.06, 0.08, 1.0)
			_gate = Color(0.35, 0.86, 1.0, 0.9)
		_:
			_rim = Color(0.15, 0.17, 0.22, 1.0)
			_gate = Color(0.2, 0.95, 0.4, 0.85)
	queue_redraw()


func _draw() -> void:
	var center := Vector2.ZERO
	# Face plate and bolt ring: a machined vault door, not a neon circle.
	draw_circle(center, radius + 48.0, Color(0.1, 0.11, 0.14, 1.0))
	draw_arc(center, radius + 40.0, -0.8, 1.1, 40, Color(0.55, 0.58, 0.62, 0.45), 8.0, true)
	for i in 8:
		var bolt: Vector2 = Vector2.from_angle(float(i) * TAU / 8.0) * (radius + 34.0)
		draw_circle(bolt, 7.0, Color(0.28, 0.3, 0.34, 1.0))
		draw_circle(bolt, 2.4, Color(0.06, 0.06, 0.08, 1.0))
	draw_circle(center, radius - 28.0, Color(0.08, 0.09, 0.12, 1.0))
	if _door > 0.0:
		draw_circle(center, 26.0, Color(1.0, 0.78, 0.25, _door))
	var rim: Color = _rim.lerp(Color.WHITE, _bezel_flash)
	draw_arc(center, radius, 0.0, TAU, 96, rim, 16.0 + 2.0 * _bezel_flash, true)
	draw_arc(center, radius - 18.0, 0.0, TAU, 64, Color(0.05, 0.05, 0.07, 1.0), 4.0, true)
	_draw_ticks()
	draw_circle(center, 36.0, Color(0.16, 0.17, 0.2, 1.0))
	draw_arc(center, 36.0, 0.0, TAU, 28, Color(0.45, 0.47, 0.52, 1.0), 2.0, true)

	var near: float = float(windows.near)
	var red_band: float = near - float(windows.good)
	_draw_side_bands(near, near + red_band * outer_band_ratio, outer_band_color, 8.0)
	_draw_window_arc(near, danger.lerp(Color(0.25, 0.08, 0.1, 0.55), 0.4), 12.0)
	# The gate the pick has to hit.
	_draw_window_arc(float(windows.good), _gate, 20.0)
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
