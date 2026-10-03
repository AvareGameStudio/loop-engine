class_name Juice
extends Node
## Hitstop, camera punch, particle bursts, pointer flash, jackpot glow, haptics.
## Time scale goes through the TimeScale autoload.

@export var camera: Camera2D
@export var burst: GPUParticles2D
@export var pointer: RingPointer
@export var glow: CanvasItem
@export var lock_pin: LockPin
@export var alarm: CanvasItem
@export var vignette: CanvasItem
## Particle buffer size; individual bursts scale down via amount_ratio.
@export var max_burst: int = 64
## Ring clear: hold this scale, then restore after RING_SLOWMO_SEC real seconds.
const RING_TIME_SCALE: float = 0.15
const RING_SLOWMO_SEC: float = 0.25
const HIT_ZOOM := Vector2(1.04, 1.04)

var _shake: float = 0.0
var _base_zoom: Vector2 = Vector2.ONE
var _zoom_tween: Tween
var _glow_tween: Tween
var _zone_tween: Tween
var _alarm_tween: Tween
var _vig_tween: Tween


func _ready() -> void:
	if camera:
		_base_zoom = camera.zoom
	if burst:
		burst.amount = max_burst
		burst.texture = _spark_texture()
	if alarm:
		alarm.modulate.a = 0.0
	EventBus.juice_hit.connect(_on_juice)
	EventBus.run_started.connect(_stop_alarm)
	EventBus.tap_evaluated.connect(_on_tap)
	EventBus.stage_cleared.connect(_on_ring_cleared)


func _process(delta: float) -> void:
	if camera == null:
		return
	var real_dt: float = delta / maxf(Engine.time_scale, 0.001)
	if _shake > 0.01:
		_shake *= exp(-10.0 * real_dt)
		camera.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	elif camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO


## Tap haptics come from TimingEngine's per-hit profile.
func _on_tap(result: Dictionary) -> void:
	Settings.vibrate(int(result.get("haptic_ms", 0)), float(result.get("haptic_amplitude", -1.0)))


func _on_juice(grade: String, intensity: float) -> void:
	# Perfect Power (intensity) scales the body-feel of a Perfect: bigger flash,
	# confetti, shake, glow. Buying the upgrade is felt on the next Perfect.
	var power: float = intensity if grade == "perfect" else 1.0
	match grade:
		"perfect":
			_add_shake(7.0 * power)
			_zoom_punch_success()
			_bounce_zone()
			spawn_hit_sparks(_contact_point())
			_burst(int(28.0 * power), Color(1.0, 0.84, 0.28).lerp(Color(1.0, 0.95, 0.55), clampf(power - 1.0, 0.0, 1.0)))
			_flash_pointer(0.16 + 0.08 * (power - 1.0), clampf(0.7 + 0.3 * power, 0.7, 1.0))
			_flash_pin(0.18, 1.0)
			_pulse_glow(1.4 * power)
			Settings.vibrate(16)
		"good":
			_add_shake(4.0 * intensity)
			_zoom_punch_success()
			_bounce_zone()
			spawn_hit_sparks(_contact_point())
			_burst(16, Color(1.0, 0.84, 0.28))
			_flash_pointer(0.1, 0.65)
			_flash_pin(0.12, 0.8)
			_pulse_glow(0.9)
			Settings.vibrate(12)
		"near_miss":
			TimeScale.hitstop(0.18)
			_add_shake(14.0)
			_punch(0.94)
			_burst(36, Color(1.0, 0.35, 0.55))
			_police_alarm()
		"miss":
			_add_shake(18.0)
			_punch(0.9)
			_burst(22, Color(0.7, 0.2, 0.3))
			_police_alarm()
			Settings.vibrate(28)
		"tension":
			_show_vignette()
			_add_shake(3.0)
		"jackpot":
			TimeScale.hitstop(0.1)
			_add_shake(12.0)
			_burst(48, Color(1.0, 0.84, 0.2))
			_pulse_glow(2.5)
			Settings.vibrate(30)
		"claim":
			# Idle Vault collect: gold explosion so the piggy emptying is a reward, not a number.
			_add_shake(10.0)
			_burst(48, Color(1.0, 0.84, 0.2))
			_pulse_glow(2.2)
			Settings.vibrate(25)
		"combo_break":
			_add_shake(6.0)
			_punch(0.97)
			Settings.vibrate(18)
		"empty_focus":
			_add_shake(3.0)
			Settings.vibrate(12)


func _add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Successful timing: zoom to 1.04, then ease back to 1.0 over 0.1s.
func _zoom_punch_success() -> void:
	if camera == null:
		return
	if _zoom_tween:
		_zoom_tween.kill()
	camera.zoom = HIT_ZOOM
	_zoom_tween = create_tween()
	_zoom_tween.set_ignore_time_scale(true)
	_zoom_tween.tween_property(camera, "zoom", Vector2.ONE, 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Full ring cleared: 0.15 for 0.25 real seconds, then back to 1.0.
## Deferred because the tap handler restores slow-mo at the end of the same call.
func _on_ring_cleared(_index: int, _payout: int) -> void:
	_zoom_punch_success()
	_bounce_zone()
	_pulse_glow(2.2)
	spawn_vault_coins(_contact_point())
	TimeScale.pulse_slowmo.call_deferred(RING_TIME_SCALE, RING_SLOWMO_SEC)


func _bounce_zone() -> void:
	if pointer == null:
		return
	var zone := pointer.get_parent() as Node2D
	if zone == null:
		return
	if _zone_tween:
		_zone_tween.kill()
	zone.scale = Vector2.ONE
	_zone_tween = create_tween()
	_zone_tween.set_ignore_time_scale(true)
	_zone_tween.tween_property(zone, "scale", Vector2(1.18, 1.18), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_zone_tween.tween_property(zone, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _punch(scale: float) -> void:
	if camera == null:
		return
	if _zoom_tween:
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_ignore_time_scale(true)
	_zoom_tween.tween_property(camera, "zoom", _base_zoom * scale, 0.03).set_trans(Tween.TRANS_QUAD)
	_zoom_tween.tween_property(camera, "zoom", _base_zoom, 0.05).set_trans(Tween.TRANS_BACK)


## One-shot gold burst at the pick tip. The node frees itself when the burst ends.
func spawn_hit_sparks(global_pos: Vector2) -> void:
	var sparks := CPUParticles2D.new()
	sparks.name = "HitSparks"
	sparks.one_shot = true
	sparks.amount = 20
	sparks.lifetime = 0.35
	sparks.explosiveness = 1.0
	sparks.spread = 180.0
	sparks.initial_velocity_min = 150.0
	sparks.initial_velocity_max = 300.0
	sparks.gravity = Vector2(0, 420)
	sparks.scale_amount_min = 1.6
	sparks.scale_amount_max = 3.4
	sparks.color = Color(1.0, 0.85, 0.3, 1.0)
	sparks.texture = _spark_texture()
	sparks.z_index = 8
	var host: Node = get_tree().current_scene if get_tree() else self
	host.add_child(sparks)
	sparks.global_position = global_pos
	sparks.emitting = true
	get_tree().create_timer(sparks.lifetime + 0.05, true, false, true).timeout.connect(sparks.queue_free)


## Gold spray toward the HUD counter when the vault door opens.
func spawn_vault_coins(global_pos: Vector2) -> void:
	var coins := CPUParticles2D.new()
	coins.name = "VaultCoins"
	coins.one_shot = true
	coins.amount = 28
	coins.lifetime = 0.75
	coins.explosiveness = 0.92
	coins.direction = Vector2(0, -1)
	coins.spread = 36.0
	coins.gravity = Vector2(0, 260)
	coins.initial_velocity_min = 320.0
	coins.initial_velocity_max = 560.0
	coins.scale_amount_min = 1.8
	coins.scale_amount_max = 3.2
	coins.color = Color(1.0, 0.843, 0.0, 1.0)
	coins.texture = _spark_texture()
	coins.z_index = 9
	var host: Node = get_tree().current_scene if get_tree() else self
	host.add_child(coins)
	coins.global_position = global_pos
	coins.emitting = true
	get_tree().create_timer(coins.lifetime + 0.05, true, false, true).timeout.connect(coins.queue_free)


func _contact_point() -> Vector2:
	if pointer == null:
		return Vector2.ZERO
	return pointer.to_global(Vector2(pointer.length, 0.0))


func _spark_texture() -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(3.5, 3.5)
	for y in 8:
		for x in 8:
			if Vector2(x, y).distance_to(center) <= 3.2:
				img.set_pixel(x, y, Color(1, 0.9, 0.45, 1))
	return ImageTexture.create_from_image(img)


func _burst(amount: int, color: Color) -> void:
	if burst == null:
		return
	# Changing `amount` reallocates the particle buffer; amount_ratio does not.
	burst.amount_ratio = clampf(float(amount) / float(max_burst), 0.0, 1.0)
	burst.modulate = color
	# Perfect Power / Claim: grow the gold burst without reallocating the GPU buffer.
	var size_scale: float = clampf(float(amount) / 28.0, 0.7, 2.2)
	burst.scale = Vector2(size_scale, size_scale)
	burst.restart()


func _flash_pointer(seconds: float = 0.16, peak: float = 1.0) -> void:
	if pointer:
		pointer.flash(seconds, peak)


func _flash_pin(seconds: float = 0.16, peak: float = 1.0) -> void:
	if lock_pin:
		lock_pin.flash(seconds, peak)


func _police_alarm() -> void:
	if alarm == null:
		return
	if _alarm_tween:
		_alarm_tween.kill()
	alarm.visible = true
	_alarm_tween = create_tween()
	_alarm_tween.set_ignore_time_scale(true)
	_alarm_tween.tween_method(_set_alarm_phase, 0.0, 6.0, 1.15)


func _set_alarm_phase(t: float) -> void:
	if alarm == null:
		return
	var red: bool = int(t * 2.0) % 2 == 0
	alarm.modulate = Color(0.95, 0.08, 0.1, 0.48) if red else Color(0.1, 0.28, 0.95, 0.42)
	if t > 5.0:
		alarm.modulate.a = lerpf(0.42, 0.0, (t - 5.0) / 1.0)


func _stop_alarm() -> void:
	if _alarm_tween:
		_alarm_tween.kill()
	if alarm:
		alarm.modulate.a = 0.0


func _show_vignette() -> void:
	if vignette == null or not (vignette.material is ShaderMaterial):
		return
	var mat := vignette.material as ShaderMaterial
	if _vig_tween:
		_vig_tween.kill()
	_vig_tween = create_tween()
	_vig_tween.set_ignore_time_scale(true)
	_vig_tween.tween_property(mat, "shader_parameter/strength", 0.9, 0.06)
	_vig_tween.tween_property(mat, "shader_parameter/strength", 0.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _pulse_glow(peak: float = 2.5) -> void:
	if glow == null or not (glow.material is ShaderMaterial):
		return
	var mat := glow.material as ShaderMaterial
	if _glow_tween:
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.set_ignore_time_scale(true)
	_glow_tween.tween_property(mat, "shader_parameter/intensity", peak, 0.08)
	_glow_tween.parallel().tween_property(mat, "shader_parameter/pulse", PI * 0.5, 0.08).from(0.0)
	_glow_tween.parallel().tween_property(mat, "shader_parameter/ripple", 0.72, 0.32).from(0.18)
	_glow_tween.tween_property(mat, "shader_parameter/intensity", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
