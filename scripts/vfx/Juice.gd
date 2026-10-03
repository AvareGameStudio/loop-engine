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
## Successful lock: world drops to this scale, then returns after UNLOCK_SLOWMO_SEC.
const UNLOCK_TIME_SCALE: float = 0.2
## Shorter than RESPAWN_DELAY so slow-mo ends before the next lock is armed.
const UNLOCK_SLOWMO_SEC: float = 0.16

var _shake: float = 0.0
var _base_zoom: Vector2 = Vector2.ONE
var _zoom_tween: Tween
var _glow_tween: Tween


func _ready() -> void:
	if camera:
		_base_zoom = camera.zoom
	if burst:
		burst.amount = max_burst
	EventBus.juice_hit.connect(_on_juice)
	EventBus.tap_evaluated.connect(_on_tap)


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
			_zoom_punch(1.16 + 0.04 * (power - 1.0))
			_trigger_unlock_slowmo()
			_burst(int(28.0 * power), Color(1.0, 0.84, 0.28).lerp(Color(1.0, 0.95, 0.55), clampf(power - 1.0, 0.0, 1.0)))
			_flash_pointer(0.16 + 0.08 * (power - 1.0), clampf(0.7 + 0.3 * power, 0.7, 1.0))
			_pulse_glow(1.4 * power)
		"good":
			_add_shake(4.0 * intensity)
			_zoom_punch(1.1)
			_trigger_unlock_slowmo()
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
		"combo_break":
			_add_shake(6.0)
			_punch(0.97)
			Settings.vibrate(18)
		"empty_focus":
			_add_shake(3.0)
			Settings.vibrate(12)


func _add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Camera punches in on a cracked lock, then eases back. Ignores time scale so the
## 0.2 slow-mo doesn't stretch the zoom.
func _zoom_punch(scale: float) -> void:
	_punch(scale)


## Deferred: InputProcessor._commit writes slowmo=1.0 at the end of this frame.
func _trigger_unlock_slowmo() -> void:
	TimeScale.pulse_slowmo.call_deferred(UNLOCK_TIME_SCALE, UNLOCK_SLOWMO_SEC)


func _punch(scale: float) -> void:
	if camera == null:
		return
	if _zoom_tween:
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_ignore_time_scale(true)
	_zoom_tween.tween_property(camera, "zoom", _base_zoom * scale, 0.05).set_trans(Tween.TRANS_QUAD)
	_zoom_tween.tween_property(camera, "zoom", _base_zoom, 0.12).set_trans(Tween.TRANS_BACK)


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

