class_name Juice
extends Node
## Hitstop, camera punch, particle bursts, pointer flash, jackpot glow, haptics.
## Time scale goes through the TimeScale autoload.

@export var camera: Camera2D
@export var burst: GPUParticles2D
@export var pointer: RingPointer
@export var glow: CanvasItem
## Particle buffer size; individual bursts scale down via amount_ratio.
@export var max_burst: int = 64
## Ring clear: world drops to this scale, then returns before the next beat.
const RING_TIME_SCALE: float = 0.2
const RING_SLOWMO_SEC: float = 0.3

var _shake: float = 0.0
var _base_zoom: Vector2 = Vector2.ONE
var _zoom_tween: Tween
var _glow_tween: Tween
var _zone_tween: Tween
var _slowmo_token: int = 0
var _sparks: CPUParticles2D


func _ready() -> void:
	if camera:
		_base_zoom = camera.zoom
	if burst:
		burst.amount = max_burst
	_sparks = _make_sparks()
	EventBus.juice_hit.connect(_on_juice)
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
			_zoom_punch(1.06 + 0.02 * (power - 1.0))
			_bounce_zone()
			_emit_perfect_sparks()
			_burst(int(28.0 * power), Color(1.0, 0.84, 0.28).lerp(Color(1.0, 0.95, 0.55), clampf(power - 1.0, 0.0, 1.0)))
			_flash_pointer(0.16 + 0.08 * (power - 1.0), clampf(0.7 + 0.3 * power, 0.7, 1.0))
			_pulse_glow(1.4 * power)
		"good":
			_add_shake(4.0 * intensity)
			_zoom_punch(1.04)
			_bounce_zone()
			_burst(16, Color(0.45, 0.75, 1.0))
		"near_miss":
			TimeScale.hitstop(0.18)
			_add_shake(14.0)
			_punch(0.94)
			_burst(36, Color(1.0, 0.35, 0.55))
		"miss":
			_add_shake(18.0)
			_punch(0.9)
			_burst(22, Color(0.7, 0.2, 0.3))
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


func _add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## 0.08s camera punch. Real time, so a victory slow-mo doesn't stretch it.
func _zoom_punch(scale: float) -> void:
	_punch(scale)


## Full ring cleared: TimeScale 0.2 for 0.3s, then back to 1 before the next beat.
## Deferred because the tap handler restores slow-mo at the end of the same call.
func _on_ring_cleared(_index: int, _payout: int) -> void:
	_zoom_punch(1.08)
	_bounce_zone()
	_slowmo_token += 1
	_apply_ring_slowmo.call_deferred(_slowmo_token)


func _apply_ring_slowmo(token: int) -> void:
	if token != _slowmo_token:
		return
	TimeScale.set_time_scale(RING_TIME_SCALE)
	get_tree().create_timer(RING_SLOWMO_SEC, true, false, true).timeout.connect(func() -> void:
		if token != _slowmo_token:
			return
		TimeScale.set_time_scale(1.0)
	)


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
	_zone_tween.tween_property(zone, "scale", Vector2(1.045, 1.045), 0.04).set_trans(Tween.TRANS_QUAD)
	_zone_tween.tween_property(zone, "scale", Vector2.ONE, 0.04).set_trans(Tween.TRANS_BACK)


func _punch(scale: float) -> void:
	if camera == null:
		return
	if _zoom_tween:
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_ignore_time_scale(true)
	_zoom_tween.tween_property(camera, "zoom", _base_zoom * scale, 0.03).set_trans(Tween.TRANS_QUAD)
	_zoom_tween.tween_property(camera, "zoom", _base_zoom, 0.05).set_trans(Tween.TRANS_BACK)


func _make_sparks() -> CPUParticles2D:
	var sparks := CPUParticles2D.new()
	sparks.name = "PerfectSparks"
	sparks.one_shot = true
	sparks.emitting = false
	sparks.amount = 24
	sparks.lifetime = 0.4
	sparks.explosiveness = 0.95
	sparks.randomness = 0.4
	sparks.spread = 180.0
	sparks.gravity = Vector2(0, 280)
	sparks.initial_velocity_min = 90.0
	sparks.initial_velocity_max = 240.0
	sparks.scale_amount_min = 1.4
	sparks.scale_amount_max = 3.2
	sparks.color = Color(1.0, 0.84, 0.28, 1)
	sparks.texture = _spark_texture()
	sparks.z_index = 6
	var host: Node = pointer.get_parent() if pointer else self
	host.add_child(sparks)
	return sparks


func _spark_texture() -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(3.5, 3.5)
	for y in 8:
		for x in 8:
			if Vector2(x, y).distance_to(center) <= 3.2:
				img.set_pixel(x, y, Color(1, 0.9, 0.45, 1))
	return ImageTexture.create_from_image(img)


func _emit_perfect_sparks() -> void:
	if pointer == null or _sparks == null:
		return
	_sparks.global_position = pointer.to_global(Vector2(pointer.length, 0.0))
	_sparks.restart()


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
	_glow_tween.tween_property(mat, "shader_parameter/intensity", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

