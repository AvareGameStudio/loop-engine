class_name Juice
extends Node

const VaultArt := preload("res://scripts/vfx/VaultSprites.gd")
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
const RING_TIME_SCALE: float = 0.2
const RING_SLOWMO_SEC: float = 0.15
const LAST_PIN_FREEZE: float = 0.1
const HIT_ZOOM := Vector2(1.05, 1.05)

var _shake: float = 0.0
var _base_zoom: Vector2 = Vector2.ONE
var _zoom_tween: Tween
var _glow_tween: Tween
var _zone_tween: Tween
var _alarm_tween: Tween
var _vig_tween: Tween
var _cleared_stage: int = 1


func _ready() -> void:
	if camera:
		_base_zoom = camera.zoom
	if burst:
		burst.amount = max_burst
		burst.texture = _spark_texture()
		burst.position = Vector2.ZERO
		burst.visibility_rect = Rect2(-900, -1400, 1800, 2800)
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
			_burst(int(36.0 * power), Color(1.0, 0.86, 0.35).lerp(Color(1.0, 0.96, 0.7), clampf(power - 1.0, 0.0, 1.0)))
			_flash_pointer(0.16 + 0.08 * (power - 1.0), clampf(0.7 + 0.3 * power, 0.7, 1.0))
			_flash_pin(0.18, 1.0)
			_pulse_glow(1.4 * power)
			Settings.vibrate(40, 1.0)
		"good":
			_add_shake(4.0 * intensity)
			_zoom_punch_success()
			_bounce_zone()
			_burst(24, Color(0.95, 0.78, 0.32))
			_flash_pointer(0.1, 0.65)
			_flash_pin(0.12, 0.8)
			_pulse_glow(0.9)
			Settings.vibrate(26, 0.8)
		"near_miss":
			TimeScale.hitstop(0.18)
			_add_shake(14.0)
			_punch(0.94)
			_burst(12, Color(1.0, 0.35, 0.42))
			_police_alarm()
		"miss":
			_add_shake(18.0)
			_punch(0.9)
			_burst(8, Color(0.75, 0.22, 0.28))
			_police_alarm()
			Settings.vibrate(28)
		"tension":
			_show_vignette()
			_add_shake(3.0)
		"jackpot":
			TimeScale.hitstop(0.1)
			_add_shake(12.0)
			_burst(22, Color(1.0, 0.84, 0.35))
			_pulse_glow(2.5)
			Settings.vibrate(30)
		"claim":
			# Idle Vault collect: gold explosion so the piggy emptying is a reward, not a number.
			_add_shake(10.0)
			_burst(20, Color(1.0, 0.84, 0.35))
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


## Successful timing: zoom to 1.05, then ease back to 1.0 over 0.1s.
func _zoom_punch_success() -> void:
	if camera == null:
		return
	if _zoom_tween:
		_zoom_tween.kill()
	camera.zoom = HIT_ZOOM
	_zoom_tween = create_tween()
	_zoom_tween.set_ignore_time_scale(true)
	_zoom_tween.tween_property(camera, "zoom", Vector2.ONE, 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Last pin: freeze 100ms, then the door flies and the hoard spills.
## The freeze is hitstop, so the tap handler's slow-mo restore cannot cancel it.
func _on_ring_cleared(index: int, _payout: int) -> void:
	_cleared_stage = index
	TimeScale.hitstop(LAST_PIN_FREEZE)
	get_tree().create_timer(LAST_PIN_FREEZE, true, false, true).timeout.connect(_slam_vault)


func _slam_vault() -> void:
	_zoom_punch_success()
	bounce_node(_dial(), 1.28)
	_tint_glow(_shell_color(_cleared_stage + 1))
	_pulse_glow(3.0)
	spawn_vault_rain()
	_shed_rust(_cleared_stage)
	_shed_shell(_shell_color(_cleared_stage))
	Settings.vibrate(70, 1.0)
	TimeScale.pulse_slowmo(RING_TIME_SCALE, RING_SLOWMO_SEC)


func _shell_color(stage: int) -> Color:
	return GameState.shell_color(stage)


func _tint_glow(color: Color) -> void:
	if glow == null or not (glow.material is ShaderMaterial):
		return
	(glow.material as ShaderMaterial).set_shader_parameter("glow_color", color)


func _shed_rust(stage: int) -> void:
	var cover := GameState.shell_rust(stage)
	if cover <= 0.02:
		return
	var layer: Node = glow.get_parent() if glow else (get_tree().current_scene if get_tree() else self)
	var flakes := CPUParticles2D.new()
	flakes.name = "RustFall"
	flakes.one_shot = true
	flakes.amount = int(lerpf(28.0, 80.0, cover))
	flakes.lifetime = 1.15
	flakes.explosiveness = 0.92
	flakes.direction = Vector2(0, 1)
	flakes.spread = 70.0
	flakes.gravity = Vector2(0, 980)
	flakes.initial_velocity_min = 80.0
	flakes.initial_velocity_max = 280.0
	flakes.angular_velocity_min = -180.0
	flakes.angular_velocity_max = 180.0
	flakes.scale_amount_min = 1.6
	flakes.scale_amount_max = 3.4
	flakes.color = Color(0.62, 0.32, 0.12, 1.0)
	flakes.texture = _rust_texture()
	flakes.z_index = 12
	layer.add_child(flakes)
	flakes.position = _vault_origin()
	flakes.emitting = true
	get_tree().create_timer(flakes.lifetime + 0.1, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(flakes):
			flakes.queue_free()
	)


func _rust_texture() -> Texture2D:
	var img := Image.create(12, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 10:
		for x in 12:
			if _rust_on(x, y):
				var pit := 0.75 + 0.25 * float((x * 3 + y) % 4) / 3.0
				img.set_pixel(x, y, Color(0.55 * pit, 0.26 * pit, 0.08 * pit, 1.0))
	return ImageTexture.create_from_image(img)


func _rust_on(x: int, y: int) -> bool:
	return y > 1 and y < 9 and x > 0 and x < 11 and not (y < 3 and (x < 2 or x > 9))


func _shed_shell(color: Color) -> void:
	var layer: Node = glow.get_parent() if glow else (get_tree().current_scene if get_tree() else self)
	var chips := CPUParticles2D.new()
	chips.name = "ShellChips"
	chips.one_shot = true
	chips.amount = 36
	chips.lifetime = 0.7
	chips.explosiveness = 0.95
	chips.spread = 180.0
	chips.gravity = Vector2(0, 520)
	chips.initial_velocity_min = 180.0
	chips.initial_velocity_max = 520.0
	chips.scale_amount_min = 1.2
	chips.scale_amount_max = 2.4
	chips.color = color
	chips.texture = _spark_texture()
	chips.z_index = 11
	layer.add_child(chips)
	chips.position = _vault_origin()
	chips.emitting = true
	get_tree().create_timer(chips.lifetime + 0.1, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(chips):
			chips.queue_free()
	)


func _bounce_zone() -> void:
	bounce_node(_dial(), 1.08)


func bounce_node(node: Node2D, peak: float) -> void:
	if node == null:
		return
	if _zone_tween:
		_zone_tween.kill()
	node.scale = Vector2.ONE
	_zone_tween = create_tween()
	_zone_tween.set_ignore_time_scale(true)
	_zone_tween.tween_property(node, "scale", Vector2(peak, peak), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_zone_tween.tween_property(node, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _dial() -> Node2D:
	if pointer == null:
		return null
	return pointer.get_parent() as Node2D


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


## Gold bars and diamonds fill the phone when the door slams open.
func spawn_vault_rain() -> void:
	VaultArt.ensure()
	var layer: Node = glow.get_parent() if glow else (get_tree().current_scene if get_tree() else self)
	var origin := _vault_origin()
	_drop_rain(layer, "VaultRainGold", VaultArt.gold, Color(1.0, 0.86, 0.3, 1.0), 140, 0.0)
	_drop_rain(layer, "VaultRainGem", VaultArt.gem, Color(0.85, 0.95, 1.0, 1.0), 70, 0.05)
	_explode_hoard(layer, "VaultBurstGold", VaultArt.gold, Color(1.0, 0.84, 0.25, 1.0), origin, 90)
	_explode_hoard(layer, "VaultBurstGem", VaultArt.gem, Color(0.8, 0.95, 1.0, 1.0), origin, 40)


func _drop_rain(layer: Node, rain_name: String, texture: Texture2D, color: Color, count: int, delay: float) -> void:
	var rain := CPUParticles2D.new()
	rain.name = rain_name
	rain.one_shot = true
	rain.amount = count
	rain.lifetime = 1.8
	rain.explosiveness = 0.2
	rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain.emission_rect_extents = Vector2(400.0, 16.0)
	rain.direction = Vector2(0, 1)
	rain.spread = 24.0
	rain.gravity = Vector2(0, 1100)
	rain.initial_velocity_min = 60.0
	rain.initial_velocity_max = 260.0
	rain.scale_amount_min = 1.4
	rain.scale_amount_max = 2.8
	rain.color = color
	rain.texture = texture
	rain.z_index = 12
	layer.add_child(rain)
	rain.position = Vector2(360, -30)
	if delay <= 0.0:
		rain.emitting = true
	else:
		rain.emitting = false
		get_tree().create_timer(delay, true, false, true).timeout.connect(func() -> void:
			if is_instance_valid(rain):
				rain.emitting = true
		)
	get_tree().create_timer(rain.lifetime + delay + 0.1, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(rain):
			rain.queue_free()
	)


func _explode_hoard(layer: Node, burst_name: String, texture: Texture2D, color: Color, origin: Vector2, count: int) -> void:
	var spill := CPUParticles2D.new()
	spill.name = burst_name
	spill.one_shot = true
	spill.amount = count
	spill.lifetime = 1.15
	spill.explosiveness = 0.95
	spill.spread = 180.0
	spill.gravity = Vector2(0, 980)
	spill.initial_velocity_min = 320.0
	spill.initial_velocity_max = 880.0
	spill.scale_amount_min = 1.3
	spill.scale_amount_max = 2.6
	spill.color = color
	spill.texture = texture
	spill.z_index = 13
	layer.add_child(spill)
	spill.position = origin
	spill.emitting = true
	get_tree().create_timer(spill.lifetime + 0.1, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(spill):
			spill.queue_free()
	)


## Gold spray toward the HUD counter when the vault door opens.
func spawn_vault_coins(global_pos: Vector2) -> void:
	var coins := CPUParticles2D.new()
	coins.name = "VaultCoins"
	coins.one_shot = true
	coins.amount = 16
	coins.lifetime = 0.7
	coins.explosiveness = 0.8
	coins.direction = Vector2(0, -1)
	coins.spread = 24.0
	coins.gravity = Vector2(0, 420)
	coins.initial_velocity_min = 420.0
	coins.initial_velocity_max = 760.0
	coins.scale_amount_min = 0.55
	coins.scale_amount_max = 0.95
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


func _vault_origin() -> Vector2:
	# Arena origin is the hub. The needle only rotates around it.
	var arena := pointer.get_parent() as Node2D if pointer else null
	var world_pos := arena.global_position if arena else Vector2.ZERO
	if glow is CanvasItem and camera:
		var screen := camera.get_canvas_transform() * world_pos
		return (glow as CanvasItem).get_global_transform_with_canvas().affine_inverse() * screen
	return world_pos


func _spark_texture() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(7.5, 7.5)
	for y in 16:
		for x in 16:
			var d: float = Vector2(x, y).distance_to(center) / 7.5
			if d <= 1.0:
				var a: float = pow(1.0 - d, 2.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _burst(amount: int, color: Color) -> void:
	if burst == null:
		return
	# Changing `amount` reallocates the particle buffer; amount_ratio does not.
	burst.amount_ratio = clampf(float(amount) / float(max_burst), 0.0, 1.0)
	burst.modulate = color
	burst.scale = Vector2.ONE
	burst.position = Vector2.ZERO
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
	mat.set_shader_parameter("rect_size", glow.size)
	mat.set_shader_parameter("origin", _vault_origin())
	_glow_tween.tween_property(mat, "shader_parameter/intensity", peak, 0.08)
	_glow_tween.parallel().tween_property(mat, "shader_parameter/pulse", PI * 0.5, 0.08).from(0.0)
	_glow_tween.parallel().tween_property(mat, "shader_parameter/ripple", 1.15, 0.45).from(0.02)
	_glow_tween.tween_property(mat, "shader_parameter/intensity", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
