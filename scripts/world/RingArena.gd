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

## Vault type accent band. The piggy bank stays unmarked; bigger vaults earn a visible ring.
const _VAULT_ACCENT: Dictionary[String, Color] = {
	"office": Color(0.4, 0.95, 0.9, 0.7),
	"bank": Color(0.3, 0.6, 1.0, 0.7),
	"museum": Color(0.55, 0.35, 1.0, 0.7),
	"casino": Color(1.0, 0.45, 0.75, 0.7),
	"fort": Color(1.0, 0.42, 0.12, 0.7),
}
const _GOLDEN_ACCENT := Color(1.0, 0.84, 0.25, 0.9)

## Direction flips are a vault-3 mechanic. Off for the first two vaults.
var flips_enabled: bool = true
## 0..1 light leaking from the door seam; grows with every seated pin.
var _crack: float = 0.0
var _crack_tween: Tween
## Miss: the dial jams and shivers for a beat.
var _jam: float = 0.0
var _jam_offset: float = 0.0
var _golden: bool = false

var danger := Color(1.0, 0.28, 0.42, 1)
## Outside the near window is a Miss, so this band stays dull steel, never "safe".
var outer_band_color := Color(0.34, 0.36, 0.39, 0.45)
var _rim := Color(0.15, 0.17, 0.22, 1.0)
var _gate := Color(0.2, 0.95, 0.4, 0.85)
var _bezel_flash: float = 0.0
var _door: float = 0.0
var _door_tween: Tween
var _door_base_scale: Vector2 = Vector2.ONE
var _count_hold: bool = false
var _count_fade: float = 1.0
var _count_hits: int = 0
var _count_need: int = 8
var _coach_hot: bool = false
var _coach_done: bool = false
var _coach_pulse: float = 0.0
var _coach_age: float = 0.0
## Transparent on the piggy bank, so the opening dial is unchanged.
var _theme_accent: Color = Color(0, 0, 0, 0)


func _ready() -> void:
	_build_sprites()
	pointer.direction = direction
	EventBus.direction_flipped.connect(func(_d: float) -> void: _bezel_flash = 1.0)
	EventBus.stage_cleared.connect(_fly_door)
	EventBus.run_started.connect(func() -> void:
		_coach_done = false
		_coach_age = 0.0
		_set_crack(0.0, false)
	)
	EventBus.tap_evaluated.connect(_on_tap)
	EventBus.session_changed.connect(_refresh_count)
	EventBus.cosmetic_equipped.connect(_apply_skin)
	_apply_skin(GameState.equipped_dial)
	set_vault(GameState.current_stage)
	randomize_target(true)
	if pin:
		pin.place(target_angle)


func _process(delta: float) -> void:
	if spinning:
		# A hitch while the next door bakes must not skip the timing window.
		var step: float = minf(delta, 1.0 / 30.0)
		pointer_angle = wrapf(pointer_angle + direction * rpm * TAU * step, 0.0, TAU)
	var real_dt: float = delta / maxf(Engine.time_scale, 0.001)
	if _jam > 0.0:
		_jam = maxf(0.0, _jam - real_dt * 5.0)
		_jam_offset = deg_to_rad(randf_range(-3.0, 3.0)) * _jam
	else:
		_jam_offset = 0.0
	pointer.rotation = pointer_angle + _jam_offset
	if not _coach_done and GameState.current_stage == 1:
		_coach_age += real_dt
	var coach_now: bool = _in_coach_window()
	if coach_now:
		_coach_pulse = wrapf(_coach_pulse + real_dt * 7.0, 0.0, TAU)
	_place_hand(coach_now)
	if _count_hold:
		_count_fade = maxf(0.0, _count_fade - real_dt * 2.8)
	if _bezel_flash > 0.0 or _door > 0.0 or _count_hold or coach_now != _coach_hot:
		_bezel_flash = maxf(0.0, _bezel_flash - real_dt * 4.0)
		_door = maxf(0.0, _door - real_dt * 0.7)
		_coach_hot = coach_now
		queue_redraw()


## Paints the door, the type accent, and the golden tint for this vault.
func set_vault(stage: int) -> void:
	_golden = GameState.is_golden(stage)
	var kind: String = GameState.vault_type(stage)
	_theme_accent = _GOLDEN_ACCENT if _golden else _VAULT_ACCENT.get(kind, Color(0, 0, 0, 0))
	_paint_shell()
	queue_redraw()


## A seated pin lets more light through the seam; a miss jams the dial.
func _on_tap(result: Dictionary) -> void:
	_coach_done = true
	var grade: String = String(result.get("grade_name", ""))
	if grade == "perfect" or grade == "good":
		var need: int = maxi(GameState.hits_needed, 1)
		_set_crack(clampf(float(GameState.hits_in_stage + 1) / float(need), 0.0, 1.0), true)
	else:
		jam()
		if pin:
			pin.eject()


func jam() -> void:
	_jam = 1.0


func _set_crack(value: float, animate: bool) -> void:
	if _crack_tween:
		_crack_tween.kill()
	if not animate:
		_crack = value
		queue_redraw()
		return
	_crack_tween = create_tween()
	_crack_tween.set_ignore_time_scale(true)
	_crack_tween.tween_method(func(v: float) -> void:
		_crack = v
		queue_redraw()
	, _crack, value, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func randomize_target(snap_pointer: bool = false) -> void:
	if flips_enabled and randf() < 0.35:
		direction = -direction
		EventBus.direction_flipped.emit(direction)
	elif not flips_enabled and direction < 0.0:
		direction = 1.0
	if snap_pointer:
		pointer_angle = -PI / 2.0
	# Target always spawns ahead of the pointer, at least one reaction time away.
	var min_lead: float = maxf(min_lead_deg, rpm * 360.0 * reaction_time)
	var lead: float = deg_to_rad(randf_range(min_lead, 330.0))
	target_angle = wrapf(pointer_angle + lead * direction, 0.0, TAU)
	_restore_door()
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
	_paint_shell()
	queue_redraw()


## Fills the door cache for the current stage without swapping the flying sprite.
func warm_shell() -> void:
	VaultArt.door_for(GameState.current_stage)


func _paint_shell() -> void:
	if _door_sprite == null:
		return
	_door_base_scale = Vector2.ONE * (radius / 105.0)
	_door_sprite.scale = _door_base_scale
	_door_sprite.texture = VaultArt.door_for(GameState.current_stage)
	_door_sprite.modulate = Color.WHITE


func _build_sprites() -> void:
	VaultArt.ensure()
	_door_sprite = Sprite2D.new()
	_door_sprite.name = "VaultDoor"
	_door_sprite.texture = VaultArt.door_for(GameState.current_stage)
	_door_sprite.z_index = -2
	# Texture dial radius is 105px. Scale it onto the gameplay ring.
	_door_base_scale = Vector2.ONE * (radius / 105.0)
	_door_sprite.scale = _door_base_scale
	add_child(_door_sprite)
	move_child(_door_sprite, 0)
	_hand_sprite = Sprite2D.new()
	_hand_sprite.name = "TapHand"
	_hand_sprite.texture = VaultArt.hand
	_hand_sprite.z_index = 6
	_hand_sprite.visible = false
	add_child(_hand_sprite)
	_refresh_count()


func _place_hand(show_hand: bool) -> void:
	if _hand_sprite == null:
		return
	_hand_sprite.visible = show_hand
	if not show_hand:
		return
	var dir := Vector2.from_angle(target_angle)
	var pulse: float = 0.85 + 0.15 * sin(_coach_pulse)
	# Finger presses into the gate so the first glance reads as a tap.
	_hand_sprite.position = dir * (radius + 118.0 - 16.0 * pulse)
	_hand_sprite.rotation = target_angle + PI * 0.5
	_hand_sprite.scale = Vector2.ONE * 0.72 * pulse
	_hand_sprite.modulate = Color(1.0, 0.96, 0.7, 1.0)


func _draw() -> void:
	var center := Vector2.ZERO
	if _door > 0.0:
		draw_circle(center, (radius - 20.0) * _door, Color(1.0, 0.78, 0.25, 0.2 + 0.55 * _door))
	_draw_crack_light()

	var near: float = float(windows.near)
	var red_band: float = near - float(windows.good)
	_draw_side_bands(near, near + red_band * outer_band_ratio, outer_band_color, 8.0)
	_draw_window_arc(near, danger.lerp(Color(0.25, 0.08, 0.1, 0.55), 0.4), 12.0)
	# The gate the pick has to hit.
	_draw_window_arc(float(windows.good), _gate, 20.0)
	_draw_window_arc(float(windows.perfect), Color(1.0, 0.84, 0.2, 0.95), 8.0)
	if _bezel_flash > 0.0:
		draw_arc(center, radius, 0.0, TAU, 64, Color(1, 1, 1, 0.35 * _bezel_flash), 6.0, true)
	if _theme_accent.a > 0.0:
		draw_arc(center, radius + 26.0, 0.0, TAU, 48, _theme_accent, 4.0 if _golden else 3.0, true)
	_draw_meter()


## Gold light leaking from the door seam. Reads as "almost open" without a number.
## The door is a 300px square texture scaled onto the ring, so its half-size follows the radius.
func _draw_crack_light() -> void:
	if _crack <= 0.0 or _door_sprite == null:
		return
	var half: float = 150.0 * _door_base_scale.x
	var glow := Color(1.0, 0.82, 0.3, 0.12 + 0.55 * _crack)
	var width: float = 2.0 + 12.0 * _crack
	var rect := Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0))
	draw_rect(rect, glow, false, width)
	# Soft halo outside the seam.
	var halo := Color(1.0, 0.82, 0.3, 0.05 + 0.2 * _crack)
	draw_rect(rect.grow(width * 1.5), halo, false, width * 2.0)


func _in_coach_window() -> bool:
	if _coach_done or GameState.current_stage != 1 or not spinning:
		return false
	# The opening seconds keep the hand on the gate even before the needle arrives.
	if _coach_age < 3.0:
		return true
	var err: float = absf(rad_to_deg(angle_difference(pointer_angle, target_angle)))
	return err <= maxf(float(windows.get("near", 22.0)), 42.0)


func _fly_door(_index: int, _payout: int) -> void:
	_door = 1.0
	_shatter_count()
	if _door_sprite == null:
		return
	if _door_tween:
		_door_tween.kill()
	_door_sprite.scale = _door_base_scale
	_door_sprite.modulate = Color.WHITE
	_door_tween = create_tween()
	_door_tween.set_ignore_time_scale(true)
	# Wait out the 100ms hitstop, then this shell rushes the camera and vanishes.
	_door_tween.tween_interval(0.1)
	_door_tween.tween_property(_door_sprite, "scale", _door_base_scale * 1.65, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_door_tween.parallel().tween_property(_door_sprite, "modulate:a", 0.0, 0.28)
	_door_tween.finished.connect(func() -> void:
		_paint_shell()
		_set_crack(0.0, false)
	, CONNECT_ONE_SHOT)


func _restore_door() -> void:
	if _door_tween:
		_door_tween.kill()
	_count_hold = false
	_count_fade = 1.0
	_paint_shell()
	_refresh_count()


func _refresh_count() -> void:
	if _count_hold:
		return
	_count_hits = GameState.hits_in_stage
	_count_need = maxi(GameState.hits_needed, 1)
	queue_redraw()


func _shatter_count() -> void:
	_count_hits = GameState.hits_in_stage
	_count_need = maxi(GameState.hits_needed, 1)
	_count_hold = true
	_count_fade = 1.0


func _draw_meter() -> void:
	if _count_hold and _count_fade <= 0.0:
		return
	var alpha := _count_fade if _count_hold else 1.0
	var ink := GameState.shell_color(GameState.current_stage).lerp(Color(0.96, 0.93, 0.86), 0.45)
	ink.a = alpha
	var swell := 1.0 + (1.0 - alpha) * 0.12 if _count_hold else 1.0
	var spin := (1.0 - alpha) * 0.35 if _count_hold else 0.0
	draw_set_transform(Vector2.ZERO, spin, Vector2(swell, swell))
	draw_circle(Vector2.ZERO, 46.0, Color(0.04, 0.045, 0.06, alpha))
	draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 48, Color(ink.r, ink.g, ink.b, alpha), 2.4, true)
	var need := maxi(_count_need, 1)
	for i in need:
		var ang := -PI * 0.5 + TAU * float(i) / float(need)
		var slot := Vector2.from_angle(ang) * 34.0
		draw_circle(slot, 2.6, Color(0.1, 0.1, 0.12, alpha))
		if i < _count_hits:
			draw_circle(slot, 1.8, ink)
	var label := "%d/%d" % [_count_hits, need]
	var digit_w := 9.0
	var digit_h := 14.0
	var advance := 11.0
	var width := float(label.length()) * advance
	var cursor := -width * 0.5
	var y := -digit_h * 0.5
	for ch in label:
		if ch == "/":
			draw_line(Vector2(cursor + 2.0, y + digit_h), Vector2(cursor + advance - 2.0, y), ink, 1.6, true)
		else:
			_draw_digit(Vector2(cursor, y), int(ch), digit_w, digit_h, ink)
		cursor += advance
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


const _DIGIT_MASKS: Array[int] = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F]


func _draw_digit(origin: Vector2, digit: int, width: float, height: float, color: Color) -> void:
	if digit < 0 or digit > 9:
		return
	var mask := _DIGIT_MASKS[digit]
	var mid := height * 0.5
	var t := 2.2
	if mask & 0x01:
		draw_line(origin + Vector2(t, 0.0), origin + Vector2(width - t, 0.0), color, t, true)
	if mask & 0x02:
		draw_line(origin + Vector2(width, t), origin + Vector2(width, mid - t), color, t, true)
	if mask & 0x04:
		draw_line(origin + Vector2(width, mid + t), origin + Vector2(width, height - t), color, t, true)
	if mask & 0x08:
		draw_line(origin + Vector2(t, height), origin + Vector2(width - t, height), color, t, true)
	if mask & 0x10:
		draw_line(origin + Vector2(0.0, mid + t), origin + Vector2(0.0, height - t), color, t, true)
	if mask & 0x20:
		draw_line(origin + Vector2(0.0, t), origin + Vector2(0.0, mid - t), color, t, true)
	if mask & 0x40:
		draw_line(origin + Vector2(t, mid), origin + Vector2(width - t, mid), color, t, true)


func _draw_window_arc(half_deg: float, color: Color, width: float) -> void:
	var half: float = deg_to_rad(half_deg)
	draw_arc(Vector2.ZERO, radius, target_angle - half, target_angle + half, 32, color, width, true)


func _draw_side_bands(inner_deg: float, outer_deg: float, color: Color, width: float) -> void:
	var inner: float = deg_to_rad(inner_deg)
	var outer: float = deg_to_rad(outer_deg)
	draw_arc(Vector2.ZERO, radius, target_angle + inner, target_angle + outer, 16, color, width, true)
	draw_arc(Vector2.ZERO, radius, target_angle - outer, target_angle - inner, 16, color, width, true)
