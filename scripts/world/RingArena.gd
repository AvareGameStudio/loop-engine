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
@export var min_lead_deg: float = 120.0
@export var max_lead_deg: float = 270.0
## Seconds of pointer travel guaranteed between respawn and target.
@export var reaction_time: float = 0.35

@onready var pointer: RingPointer = $Pointer
@onready var pin: LockPin = $LockPin

var _door_sprite: Sprite2D
var _hand_sprite: Sprite2D
var _loot_sprite: Sprite2D
var _cuff: Sprite2D
var _cuff_tween: Tween
const CUFF_SCALE := Vector2(1.55, 1.55)

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

## Kept for callers; flips now happen only through `start_flip_telegraph`.
var flips_enabled: bool = false
## Next tumbler is a gold pin (variable-ratio drop).
var gold_pin: bool = false
var _telegraph: float = 0.0
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
## Active vault trick ("" / "slide" / "double" / "dark"). GameState.trick_for picks it.
var trick: String = ""
## Slide: the gate creeps against the pick at this many revolutions per second.
const SLIDE_RPS: float = 0.06
## Double: the chained second gate sits this far past the first.
const CHAIN_MIN_DEG: float = 110.0
const CHAIN_MAX_DEG: float = 170.0
var _has_next: bool = false
var _next_target: float = 0.0
## Dark: the gate is fully lit within DARK_FULL_DEG ahead of the pick and gone past DARK_EDGE_DEG.
const DARK_FULL_DEG: float = 60.0
const DARK_EDGE_DEG: float = 110.0
const DARK_DOOR := Color(0.42, 0.42, 0.5, 1.0)
## Hot Hands fire ring, 0..1. Orange so it never competes with the golden-heist dial.
const HOT := Color(1.0, 0.45, 0.1, 1.0)
const HOT_CORE := Color(1.0, 0.8, 0.35, 1.0)
var _hot: float = 0.0
var _hot_tween: Tween
var _hot_t: float = 0.0
## Miss ghost: where the gate was and how far the pick stopped from it, so a miss
## reads as "a hair late" instead of "unfair". Survives the respawn, then fades.
const GHOST_HOLD: float = 0.45
const GHOST_FADE: float = 0.35
var _ghost: float = 0.0
var _ghost_tween: Tween
var _ghost_target: float = 0.0
var _ghost_pointer: float = 0.0
var _ghost_good: float = 16.0


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
	EventBus.cosmetic_equipped.connect(func(id: String) -> void: _apply_skin(id, true))
	EventBus.juice_hit.connect(_on_cuff_juice)
	EventBus.hot_hands.connect(_on_hot_hands)
	_apply_skin(GameState.equipped_gloves, false)
	set_vault(GameState.current_stage)
	randomize_target(true)
	if pin:
		pin.place(target_angle)


func _process(delta: float) -> void:
	if spinning:
		# A hitch while the next door bakes must not skip the timing window.
		var step: float = minf(delta, 1.0 / 30.0)
		pointer_angle = wrapf(pointer_angle + direction * rpm * TAU * step, 0.0, TAU)
		if trick == "slide":
			target_angle = wrapf(target_angle + drift_rate() * step, 0.0, TAU)
	if trick == "dark":
		queue_redraw()
	if pin:
		# The tumbler would give the dark gate away, so it fades with it.
		pin.modulate.a = _visibility(target_angle)
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
	if _telegraph > 0.0:
		_telegraph = maxf(0.0, _telegraph - real_dt)
		queue_redraw()
	if _hot > 0.0:
		_hot_t += real_dt
		queue_redraw()
	if _bezel_flash > 0.0 or _door > 0.0 or _count_hold or coach_now != _coach_hot:
		_bezel_flash = maxf(0.0, _bezel_flash - real_dt * 4.0)
		_door = maxf(0.0, _door - real_dt * 0.7)
		_coach_hot = coach_now
		queue_redraw()


## Ignite in 0.3 s; going out is faster so the break reads as a snap.
func _on_hot_hands(on: bool) -> void:
	if _hot_tween:
		_hot_tween.kill()
	_hot_tween = create_tween()
	_hot_tween.set_ignore_time_scale(true)
	_hot_tween.tween_property(self, "_hot", 1.0 if on else 0.0, 0.3 if on else 0.12)
	_hot_tween.tween_callback(queue_redraw)


func _draw_hot_ring() -> void:
	var r: float = radius + 26.0
	var flicker: float = 0.8 + 0.2 * sin(_hot_t * 23.0) * sin(_hot_t * 7.0)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(HOT, 0.18 * _hot), 26.0, true)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(HOT, 0.85 * _hot * flicker), 8.0, true)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(HOT_CORE, 0.9 * _hot), 3.0, true)
	# Twelve tongues licking outward, each on its own beat.
	for i in 12:
		var a: float = TAU * float(i) / 12.0 + _hot_t * 0.6
		var lick: float = 10.0 + 14.0 * (0.5 + 0.5 * sin(_hot_t * 9.0 + float(i) * 1.7))
		var base := Vector2.from_angle(a)
		var side := Vector2(-base.y, base.x) * 6.0
		draw_colored_polygon(PackedVector2Array([
			base * (r + 2.0) + side, base * (r + 2.0 + lick * _hot), base * (r + 2.0) - side,
		]), Color(HOT, 0.75 * _hot))


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
		_show_ghost(result)


func _show_ghost(result: Dictionary) -> void:
	_ghost_target = float(result.get("target", target_angle))
	_ghost_pointer = float(result.get("pointer", pointer_angle))
	_ghost_good = float(windows.good)
	if _ghost_tween:
		_ghost_tween.kill()
	_ghost = 1.0
	_ghost_tween = create_tween()
	_ghost_tween.set_ignore_time_scale(true)
	_ghost_tween.tween_interval(GHOST_HOLD)
	_ghost_tween.tween_method(func(v: float) -> void:
		_ghost = v
		queue_redraw()
	, 1.0, 0.0, GHOST_FADE)
	queue_redraw()


## Ghost gate at the old target, plus a white gap from where the pick stopped to the
## nearest gate edge and a red tick at the stop. White so it never blends into the red near band.
func _draw_miss_ghost() -> void:
	var half: float = deg_to_rad(_ghost_good)
	draw_arc(Vector2.ZERO, radius, _ghost_target - half, _ghost_target + half, 32, Color(0.2, 0.95, 0.4, 0.4 * _ghost), 24.0, true)
	var rim := Color(0.55, 1.0, 0.65, 0.9 * _ghost)
	draw_arc(Vector2.ZERO, radius - 13.0, _ghost_target - half, _ghost_target + half, 32, rim, 3.0, true)
	draw_arc(Vector2.ZERO, radius + 13.0, _ghost_target - half, _ghost_target + half, 32, rim, 3.0, true)
	var delta: float = angle_difference(_ghost_target, _ghost_pointer)
	var edge: float = _ghost_target + signf(delta) * half
	var stop_at: float = _ghost_target + delta
	draw_arc(Vector2.ZERO, radius, minf(edge, stop_at), maxf(edge, stop_at), 16, Color(1, 1, 1, 0.95 * _ghost), 7.0, true)
	var stop := Vector2.from_angle(_ghost_pointer)
	draw_line(stop * (radius - 22.0), stop * (radius + 22.0), Color(1.0, 0.25, 0.3, _ghost), 6.0, true)


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
	if snap_pointer:
		pointer_angle = -PI / 2.0
	# Target always spawns ahead of the pointer, at least one reaction time away.
	# A sliding gate closes the gap faster, so it counts toward the reaction distance.
	var closing: float = rpm + (SLIDE_RPS if trick == "slide" else 0.0)
	var min_lead: float = maxf(min_lead_deg, closing * 360.0 * reaction_time)
	var max_lead: float = maxf(min_lead + 8.0, max_lead_deg)
	var lead: float = deg_to_rad(randf_range(min_lead, max_lead))
	target_angle = wrapf(pointer_angle + lead * direction, 0.0, TAU)
	# Double: chain a second gate further along when at least two pins are still needed.
	_has_next = trick == "double" and GameState.hits_needed - GameState.hits_in_stage >= 2
	if _has_next:
		_next_target = wrapf(target_angle + deg_to_rad(randf_range(CHAIN_MIN_DEG, CHAIN_MAX_DEG)) * direction, 0.0, TAU)
	_restore_door()
	if pin:
		pin.set_locked(false)
		pin.set_gold(gold_pin)


func set_trick(id: String, intro: bool) -> void:
	trick = id
	_has_next = false
	if intro:
		_bezel_flash = 1.0
	_paint_shell()
	queue_redraw()


## Signed gate drift in rad/s: against the pick, so the two close in on each other.
func drift_rate() -> float:
	return -direction * SLIDE_RPS * TAU if trick == "slide" else 0.0


## Double: move straight on to the chained gate. False when there is none.
func take_chained_target() -> bool:
	if not _has_next:
		return false
	_has_next = false
	target_angle = _next_target
	if pin:
		pin.set_locked(false)
		pin.set_gold(gold_pin)
	queue_redraw()
	return true


## Dark: 1 when the gate is within reach of the pick's light, 0 when it is still far ahead.
func _visibility(angle: float) -> float:
	if trick != "dark":
		return 1.0
	var ahead: float = rad_to_deg(wrapf((angle - pointer_angle) * direction, 0.0, TAU))
	return clampf((DARK_EDGE_DEG - ahead) / (DARK_EDGE_DEG - DARK_FULL_DEG), 0.0, 1.0)


## One flip at the start of a door. Holds the dial while chevrons sweep.
func start_flip_telegraph() -> void:
	direction = -direction
	_telegraph = 0.4
	_bezel_flash = 1.0
	EventBus.direction_flipped.emit(direction)
	queue_redraw()


func set_gold_pin(armed: bool) -> void:
	gold_pin = armed
	if pin:
		pin.set_gold(armed)


func _apply_skin(_id: String, flash: bool) -> void:
	_rim = Color(0.15, 0.17, 0.22, 1.0)
	_gate = Color(0.2, 0.95, 0.4, 0.85)
	_paint_cuff(flash)
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
	_door_sprite.modulate = DARK_DOOR if trick == "dark" else Color.WHITE
	_door_sprite.rotation = 0.0
	_door_sprite.position = Vector2.ZERO
	_show_loot()


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
	_loot_sprite = Sprite2D.new()
	_loot_sprite.name = "LootWindow"
	_loot_sprite.z_index = -1
	_loot_sprite.scale = Vector2(1.35, 1.35)
	add_child(_loot_sprite)
	_cuff = Sprite2D.new()
	_cuff.name = "Cuff"
	_cuff.z_index = 1
	_cuff.scale = CUFF_SCALE
	_cuff.texture = VaultArt.cuff_for(GameState.equipped_gloves)
	add_child(_cuff)
	_show_loot()
	_refresh_count()


func _paint_cuff(flash: bool) -> void:
	if _cuff == null:
		return
	_cuff.texture = VaultArt.cuff_for(GameState.equipped_gloves)
	_cuff.modulate = Color.WHITE
	_cuff.scale = CUFF_SCALE
	_cuff.rotation = 0.0
	if not flash:
		return
	if _cuff_tween:
		_cuff_tween.kill()
	_cuff.modulate = Color(4.0, 4.0, 4.0, 1.0)
	_cuff_tween = create_tween()
	_cuff_tween.set_ignore_time_scale(true)
	_cuff_tween.tween_property(_cuff, "modulate", Color.WHITE, 0.12)


func _on_cuff_juice(grade: String, _intensity: float) -> void:
	if _cuff == null:
		return
	if grade == "perfect":
		_bounce_cuff()
	elif grade == "miss" or grade == "near_miss":
		_shake_cuff()


func _bounce_cuff() -> void:
	if _cuff_tween:
		_cuff_tween.kill()
	_cuff.scale = CUFF_SCALE
	_cuff_tween = create_tween()
	_cuff_tween.set_ignore_time_scale(true)
	_cuff_tween.tween_property(_cuff, "scale", CUFF_SCALE * 1.08, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_cuff_tween.tween_property(_cuff, "scale", CUFF_SCALE, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _shake_cuff() -> void:
	if _cuff_tween:
		_cuff_tween.kill()
	_cuff.rotation = 0.0
	_cuff_tween = create_tween()
	_cuff_tween.set_ignore_time_scale(true)
	_cuff_tween.tween_property(_cuff, "rotation", deg_to_rad(4.0), 0.04)
	_cuff_tween.tween_property(_cuff, "rotation", 0.0, 0.04)


func _show_loot() -> void:
	if _loot_sprite == null:
		return
	_loot_sprite.texture = VaultArt.loot_icon(GameState.window_loot_id())
	_loot_sprite.modulate = Color.WHITE
	_loot_sprite.visible = true
	_loot_sprite.scale = Vector2(1.35, 1.35)


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
	_hand_sprite.modulate = Color(0.55, 0.36, 0.22, 1.0)


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
	if _hot > 0.0:
		_draw_hot_ring()
	_draw_trick()
	if _ghost > 0.0:
		_draw_miss_ghost()
	if _telegraph > 0.0:
		_draw_flip_chevrons()
	_draw_window()
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
	_door_sprite.rotation = 0.0
	_door_sprite.position = Vector2.ZERO
	if _loot_sprite:
		_loot_sprite.visible = false
	_door_tween = create_tween()
	_door_tween.set_ignore_time_scale(true)
	# Wait out the 100ms hitstop, then the door swings on a hinge and vanishes.
	_door_tween.tween_interval(0.1)
	_door_tween.tween_property(_door_sprite, "rotation", -1.35, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_door_tween.parallel().tween_property(_door_sprite, "position:x", -36.0, 0.35)
	_door_tween.parallel().tween_property(_door_sprite, "modulate:a", 0.0, 0.32)
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
	var need := maxi(_count_need, 1)
	var seated := clampi(_count_hits, 0, need)
	for i in need:
		var ang := -PI * 0.5 + TAU * float(i) / float(need)
		var sunk: float = 16.0 if i < seated else 0.0
		var at := Vector2.from_angle(ang) * (radius - 6.0 - sunk)
		var r: float = 7.0
		draw_circle(at, r, Color(0.08, 0.08, 0.1, alpha))
		if i < seated:
			var cap := Color(1.0, 0.84, 0.28, alpha) if last_grade == "perfect" and i == seated - 1 else ink
			draw_circle(at, r * 0.62, cap)
			draw_circle(at + Vector2(-2.0, -2.0), 1.6, Color(1, 1, 1, 0.55 * alpha))
		else:
			draw_arc(at, r, 0.0, TAU, 16, Color(ink.r, ink.g, ink.b, 0.45 * alpha), 1.8, true)


## Prize sits in the door hole. Dark wash + gold bezel, bolts stay the counter.
func _draw_window() -> void:
	if _door_sprite == null:
		return
	var hole: float = 46.0 * _door_base_scale.x
	draw_circle(Vector2.ZERO, hole * 0.92, Color(0.08, 0.08, 0.1, 0.55))
	draw_arc(Vector2.ZERO, hole, 0.0, TAU, 64, Color(1.0, 0.84, 0.28, 0.95), 3.0, true)


func _draw_flip_chevrons() -> void:
	var a: float = clampf(_telegraph / 0.4, 0.0, 1.0)
	var col := Color(1.0, 0.95, 0.7, 0.25 + 0.55 * a)
	var step: float = direction * 0.22
	for i in 8:
		var ang: float = float(i) * TAU / 8.0 + (1.0 - a) * step * 6.0
		var outer := Vector2.from_angle(ang) * (radius + 18.0)
		var left := Vector2.from_angle(ang - 0.18) * (radius + 4.0)
		var right := Vector2.from_angle(ang + 0.18) * (radius + 4.0)
		if direction < 0.0:
			draw_colored_polygon(PackedVector2Array([outer, left, right]), col)
		else:
			draw_colored_polygon(PackedVector2Array([outer, right, left]), col)


## Per-trick cue, no text: drift arrows for slide, the chained gate for double,
## the pick's flashlight wedge for dark.
func _draw_trick() -> void:
	match trick:
		"slide":
			# Three chevrons trailing the gate in the direction it creeps.
			var drift_dir: float = -direction
			var good: float = deg_to_rad(float(windows.good))
			for i in 3:
				var a: float = target_angle + drift_dir * (good + deg_to_rad(6.0 + 7.0 * float(i)))
				var fwd := Vector2.from_angle(a + drift_dir * 0.05)
				var col := Color(0.55, 1.0, 0.65, (0.75 - 0.2 * float(i)) * _visibility(target_angle))
				draw_colored_polygon(PackedVector2Array([
					fwd * radius, Vector2.from_angle(a) * (radius - 9.0), Vector2.from_angle(a) * (radius + 9.0),
				]), col)
		"double":
			if _has_next:
				var half: float = deg_to_rad(float(windows.good))
				var col := Color(0.2, 0.95, 0.4, 0.75 * _visibility(_next_target))
				draw_arc(Vector2.ZERO, radius - 11.0, _next_target - half, _next_target + half, 24, col, 3.0, true)
				draw_arc(Vector2.ZERO, radius + 11.0, _next_target - half, _next_target + half, 24, col, 3.0, true)
				draw_arc(Vector2.ZERO, radius, _next_target - half * 0.3, _next_target + half * 0.3, 12, col, 6.0, true)
		"dark":
			# Warm light sweeping ahead of the pick, fading to nothing at the edge of sight.
			var steps: int = 8
			for i in steps:
				var t0: float = float(i) / float(steps)
				var t1: float = float(i + 1) / float(steps)
				var a0: float = pointer_angle + direction * deg_to_rad(DARK_EDGE_DEG * t0)
				var a1: float = pointer_angle + direction * deg_to_rad(DARK_EDGE_DEG * t1)
				draw_arc(Vector2.ZERO, radius, minf(a0, a1), maxf(a0, a1), 6, Color(1.0, 0.9, 0.6, 0.3 * (1.0 - t0)), 40.0, true)


func _draw_window_arc(half_deg: float, color: Color, width: float) -> void:
	var half: float = deg_to_rad(half_deg)
	color.a *= _visibility(target_angle)
	draw_arc(Vector2.ZERO, radius, target_angle - half, target_angle + half, 32, color, width, true)


func _draw_side_bands(inner_deg: float, outer_deg: float, color: Color, width: float) -> void:
	var inner: float = deg_to_rad(inner_deg)
	var outer: float = deg_to_rad(outer_deg)
	color.a *= _visibility(target_angle)
	draw_arc(Vector2.ZERO, radius, target_angle + inner, target_angle + outer, 16, color, width, true)
	draw_arc(Vector2.ZERO, radius, target_angle - outer, target_angle - inner, 16, color, width, true)
