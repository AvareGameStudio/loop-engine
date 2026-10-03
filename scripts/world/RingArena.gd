class_name RingArena
extends Node2D

const VaultArt := preload("res://scripts/vfx/VaultSprites.gd")
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

var _door_sprite: Sprite2D
var _hand_sprite: Sprite2D

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
var _coach_hot: bool = false
var _coach_done: bool = false
var _coach_pulse: float = 0.0


func _ready() -> void:
	_build_sprites()
	pointer.direction = direction
	EventBus.direction_flipped.connect(func(_d: float) -> void: _bezel_flash = 1.0)
	EventBus.stage_cleared.connect(func(_index: int, _payout: int) -> void: _door = 1.0)
	EventBus.run_started.connect(func() -> void: _coach_done = false)
	EventBus.tap_evaluated.connect(func(_result: Dictionary) -> void: _coach_done = true)
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
	var coach_now: bool = _in_coach_window()
	if coach_now:
		_coach_pulse = wrapf(_coach_pulse + real_dt * 7.0, 0.0, TAU)
	_place_hand(coach_now)
	if _bezel_flash > 0.0 or _door > 0.0 or coach_now != _coach_hot or coach_now:
		_bezel_flash = maxf(0.0, _bezel_flash - real_dt * 4.0)
		_door = maxf(0.0, _door - real_dt * 0.7)
		_coach_hot = coach_now
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
			if _door_sprite:
				_door_sprite.modulate = Color(1.0, 0.78, 0.42, 1.0)
		"obsidian":
			_rim = Color(0.05, 0.06, 0.08, 1.0)
			_gate = Color(0.35, 0.86, 1.0, 0.9)
			if _door_sprite:
				_door_sprite.modulate = Color(0.45, 0.62, 0.78, 1.0)
		_:
			_rim = Color(0.15, 0.17, 0.22, 1.0)
			_gate = Color(0.2, 0.95, 0.4, 0.85)
			if _door_sprite:
				_door_sprite.modulate = Color.WHITE
	queue_redraw()


func _build_sprites() -> void:
	VaultArt.ensure()
	_door_sprite = Sprite2D.new()
	_door_sprite.name = "VaultDoor"
	_door_sprite.texture = VaultArt.door
	_door_sprite.z_index = -2
	# Texture dial radius is 105px. Scale it onto the gameplay ring.
	_door_sprite.scale = Vector2.ONE * (radius / 105.0)
	add_child(_door_sprite)
	move_child(_door_sprite, 0)
	_hand_sprite = Sprite2D.new()
	_hand_sprite.name = "TapHand"
	_hand_sprite.texture = VaultArt.hand
	_hand_sprite.z_index = 6
	_hand_sprite.visible = false
	add_child(_hand_sprite)


func _place_hand(show_hand: bool) -> void:
	if _hand_sprite == null:
		return
	_hand_sprite.visible = show_hand
	if not show_hand:
		return
	var dir := Vector2.from_angle(target_angle)
	var pulse: float = 0.9 + 0.14 * sin(_coach_pulse)
	_hand_sprite.position = dir * (radius + 108.0)
	_hand_sprite.rotation = target_angle + PI * 0.5
	_hand_sprite.scale = Vector2.ONE * 0.46 * pulse
	_hand_sprite.modulate = Color(1.0, 0.95, 0.55, 0.72 + 0.28 * pulse)


func _draw() -> void:
	var center := Vector2.ZERO
	if _door > 0.0:
		draw_circle(center, (radius - 20.0) * _door, Color(1.0, 0.78, 0.25, 0.2 + 0.55 * _door))
		_draw_hoard(center)

	var near: float = float(windows.near)
	var red_band: float = near - float(windows.good)
	_draw_side_bands(near, near + red_band * outer_band_ratio, outer_band_color, 8.0)
	_draw_window_arc(near, danger.lerp(Color(0.25, 0.08, 0.1, 0.55), 0.4), 12.0)
	# The gate the pick has to hit.
	_draw_window_arc(float(windows.good), _gate, 20.0)
	_draw_window_arc(float(windows.perfect), Color(1.0, 0.84, 0.2, 0.95), 8.0)
	if _bezel_flash > 0.0:
		draw_arc(center, radius, 0.0, TAU, 64, Color(1, 1, 1, 0.35 * _bezel_flash), 6.0, true)
	_draw_tap_label()


func _in_coach_window() -> bool:
	if _coach_done or GameState.current_stage != 1 or not spinning:
		return false
	var err: float = absf(rad_to_deg(angle_difference(pointer_angle, target_angle)))
	return err <= float(windows.get("good", 16.0))


func _draw_hoard(center: Vector2) -> void:
	var shine: float = 0.45 + 0.55 * _door
	for i in 3:
		draw_rect(Rect2(center.x - 16.0, center.y - 14.0 + float(i) * 8.0, 32.0, 5.0), Color(0.92, 0.68, 0.16, shine), true)
	_draw_diamond(center + Vector2(-10.0, 12.0), 5.0, Color(0.78, 0.94, 1.0, shine))
	_draw_diamond(center + Vector2(10.0, 12.0), 5.0, Color(0.9, 0.96, 1.0, shine))


func _draw_diamond(center: Vector2, extent: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -extent),
		center + Vector2(extent, 0.0),
		center + Vector2(0.0, extent),
		center + Vector2(-extent, 0.0),
	]), color)


func _draw_tap_label() -> void:
	if not _coach_hot:
		return
	var palm := Vector2.from_angle(target_angle) * (radius + 108.0)
	var font: Font = ThemeDB.fallback_font
	var text := "TAP!"
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	draw_string(font, palm + Vector2(-width * 0.5, -78.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.95, 0.7, 1.0))


func _draw_window_arc(half_deg: float, color: Color, width: float) -> void:
	var half: float = deg_to_rad(half_deg)
	draw_arc(Vector2.ZERO, radius, target_angle - half, target_angle + half, 32, color, width, true)


func _draw_side_bands(inner_deg: float, outer_deg: float, color: Color, width: float) -> void:
	var inner: float = deg_to_rad(inner_deg)
	var outer: float = deg_to_rad(outer_deg)
	draw_arc(Vector2.ZERO, radius, target_angle + inner, target_angle + outer, 16, color, width, true)
	draw_arc(Vector2.ZERO, radius, target_angle - outer, target_angle - inner, 16, color, width, true)
