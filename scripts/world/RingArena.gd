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

var accent := Color(0.55, 0.86, 0.95, 1)
var danger := Color(1.0, 0.28, 0.42, 1)
var gold := Color(1.0, 0.78, 0.28, 1)
## Outside the near window is a Miss, so this band stays dull steel, never "safe".
var outer_band_color := Color(0.34, 0.36, 0.39, 0.45)
var _steel_dark := Color(0.14, 0.15, 0.17, 1)
var _steel := Color(0.42, 0.45, 0.48, 1)
var _steel_hi := Color(0.78, 0.81, 0.84, 1)


var _tap: Label
var _show_tap: bool = false
var _blink: float = 0.0


func _ready() -> void:
	pointer.direction = direction
	_tap = Label.new()
	_tap.name = "TapPrompt"
	_tap.text = "TAP!"
	_tap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tap.size = Vector2(140, 52)
	_tap.add_theme_font_size_override("font_size", 34)
	_tap.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	_tap.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.02))
	_tap.add_theme_constant_override("outline_size", 8)
	_tap.visible = false
	_tap.z_index = 4
	_tap.pivot_offset = _tap.size * 0.5
	add_child(_tap)
	EventBus.run_started.connect(_begin_coach)
	EventBus.run_ended.connect(_end_coach)
	EventBus.tap_evaluated.connect(func(_result: Dictionary) -> void: _end_coach())
	randomize_target(true)


func _process(delta: float) -> void:
	if spinning:
		pointer_angle = wrapf(pointer_angle + direction * rpm * TAU * delta, 0.0, TAU)
	pointer.rotation = pointer_angle
	if not _show_tap or _tap == null:
		return
	var real_dt: float = delta / maxf(Engine.time_scale, 0.001)
	_blink = wrapf(_blink + real_dt * 8.0, 0.0, TAU)
	# Sit on the gate, not the needle, so the eye learns the target.
	var spot: Vector2 = Vector2.from_angle(target_angle) * (radius * 0.55)
	_tap.position = spot - _tap.size * 0.5
	_tap.modulate.a = 1.0 if sin(_blink) > 0.0 else 0.2
	var pulse: float = 1.0 + 0.08 * maxf(sin(_blink), 0.0)
	_tap.scale = Vector2(pulse, pulse)


func _begin_coach() -> void:
	_show_tap = true
	_blink = 0.0
	if _tap:
		_tap.visible = true


func _end_coach(_reason: String = "", _stats: Dictionary = {}) -> void:
	_show_tap = false
	if _tap:
		_tap.visible = false


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
	# Housing: dark well, brushed bezel, machined lip.
	draw_circle(center, radius + 52.0, Color(0.03, 0.035, 0.04, 1))
	draw_arc(center, radius + 36.0, 0.0, TAU, 96, _steel_dark, 30.0, true)
	draw_arc(center, radius + 50.0, 0.0, TAU, 96, _steel_hi, 2.5, true)
	draw_arc(center, radius + 22.0, 0.0, TAU, 80, Color(0.07, 0.08, 0.09, 1), 5.0, true)
	draw_circle(center, radius - 4.0, Color(0.18, 0.19, 0.21, 1))
	draw_arc(center, radius - 40.0, 0.0, TAU, 64, Color(_steel, 0.45), 1.5, true)
	draw_arc(center, radius - 82.0, 0.0, TAU, 48, Color(_steel_hi, 0.22), 1.2, true)
	_draw_ticks()

	var near: float = float(windows.near)
	var red_band: float = near - float(windows.good)
	_draw_side_bands(near, near + red_band * outer_band_ratio, outer_band_color, ring_width + 8.0)
	_draw_window_arc(near, danger.lerp(Color(0.25, 0.08, 0.1, 0.5), 0.35), ring_width + 12.0)
	_draw_window_arc(float(windows.good), accent, ring_width + 4.0)
	_draw_window_arc(float(windows.perfect), gold, ring_width - 2.0)
	_draw_gate_tooth()
	_draw_bolts()
	draw_circle(center, 36.0, Color(0.09, 0.1, 0.11, 1))
	draw_arc(center, 36.0, 0.0, TAU, 32, _steel_hi, 2.0, true)


func _draw_ticks() -> void:
	var steps := 72
	for i in steps:
		var angle := float(i) * TAU / float(steps)
		var major := i % 6 == 0
		var inner := radius - (28.0 if major else 14.0)
		var outer := radius + 10.0
		var col := _steel_hi if major else Color(0.5, 0.53, 0.56, 0.75)
		draw_line(Vector2.from_angle(angle) * inner, Vector2.from_angle(angle) * outer, col, 2.8 if major else 1.2, true)


func _draw_bolts() -> void:
	for i in 8:
		var p: Vector2 = Vector2.from_angle(float(i) * TAU / 8.0 + PI / 8.0) * (radius + 42.0)
		draw_circle(p, 8.0, Color(0.28, 0.3, 0.32, 1))
		draw_circle(p, 6.2, _steel)
		draw_circle(p, 2.1, Color(0.1, 0.11, 0.12, 1))


## Inward tooth at the gate: the notch the pick is aiming for.
func _draw_gate_tooth() -> void:
	var dir := Vector2.from_angle(target_angle)
	var side := dir.orthogonal() * 9.0
	var base := dir * (radius + 6.0)
	draw_colored_polygon(PackedVector2Array([
		base + side,
		base - side,
		dir * (radius - 26.0),
	]), gold)


func _draw_window_arc(half_deg: float, color: Color, width: float) -> void:
	var half: float = deg_to_rad(half_deg)
	draw_arc(Vector2.ZERO, radius, target_angle - half, target_angle + half, 32, color, width, true)


func _draw_side_bands(inner_deg: float, outer_deg: float, color: Color, width: float) -> void:
	var inner: float = deg_to_rad(inner_deg)
	var outer: float = deg_to_rad(outer_deg)
	draw_arc(Vector2.ZERO, radius, target_angle + inner, target_angle + outer, 16, color, width, true)
	draw_arc(Vector2.ZERO, radius, target_angle - outer, target_angle - inner, 16, color, width, true)
