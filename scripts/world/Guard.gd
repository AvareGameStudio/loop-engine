class_name Guard
extends Node2D
## The threat is a person you read in one glance. A guard dozes at a desk in the
## bottom-left corner, and every strike wakes him one step further:
## 0 asleep (Zzz) · 1 head up, eyes open · 2 on his feet, flashlight sweeping the dial ·
## 3 stepped out from the desk, beam locked on the dial (Juice runs the strobe).
## Heist 1 never catches: on the third strike he looks up, then dozes off again.

const BEAM := Color(1.0, 0.92, 0.55, 0.14)
const BEAM_HARD := Color(1.0, 0.92, 0.55, 0.32)
const BODY := Color(0.03, 0.04, 0.08, 1.0)
const BACKLIGHT := Color(0.45, 0.58, 0.9, 0.07)
const DESK := Color(0.14, 0.11, 0.1, 1.0)
const DESK_EDGE := Color(0.24, 0.19, 0.16, 1.0)
const LAMP := Color(1.0, 0.78, 0.4, 1.0)
const BADGE := Color(0.95, 0.76, 0.3, 1.0)
const ALERT := Color(1.0, 0.86, 0.25, 1.0)
const SNORE := Color(0.75, 0.82, 1.0, 1.0)
const STEEL := Color(0.78, 0.8, 0.86, 1.0)
const STEEL_DARK := Color(0.32, 0.34, 0.4, 1.0)
## Bust timeline (real seconds): the arm reaches, then the cuff ring closes on the pick tip.
const REACH_SEC: float = 0.3
const CLOSE_SEC: float = 0.12
const CUFF_OPEN_R: float = 40.0
const CUFF_SHUT_R: float = 22.0
## Pick tip distance from the dial centre (RingPointer.length).
const PICK_TIP: float = 200.0

## Pose keyframes in world space (camera centre 360, 560; the loot bag owns x 220–500 below the dial).
## Origin is the guard's waist. Pose 0 slumps forward so the head rests on the desk.
const POSE_POS: Array[Vector2] = [Vector2(120, 1048), Vector2(120, 1040), Vector2(124, 1000), Vector2(150, 985)]
const POSE_ROT: PackedFloat32Array = [0.62, 0.0, 0.0, -0.05]
const POSE_SCALE: PackedFloat32Array = [0.86, 0.92, 1.0, 1.2]
const DESK_TOP := Rect2(24, 1000, 188, 14)
const DESK_FRONT := Rect2(34, 1014, 168, 64)
const SHOULDER := Vector2(22, -62)
const HEAD := Vector2(0, -92)
const HEAD_R: float = 20.0
const ARM_LEN: float = 40.0
## Heist 1, third strike: how long he stays up before dozing off again.
const DOZE_DELAY: float = 0.8

## Canva sprites (assets/art). Without them the silhouette below is drawn in code.
const SLEEP_ART := "res://assets/art/guard_sleep.png"
const ALERT_ART := "res://assets/art/guard_alert.png"
## Head up, flashlight raised at the dial: the pose for strikes 2-3.
const AIM_ART := "res://assets/art/guard_aim.png"
const AIM_LENS := Vector2(0.9, 0.2)
const AIM_HEAD := Vector2(0.38, 0.12)
var _aim_tex: Texture2D = load(AIM_ART) if ResourceLoader.exists(AIM_ART) else null
## Strike 1: awake at the desk, eyes up, flashlight still off (no painted beam to cut).
const WAKE_ART := "res://assets/art/guard_wake.png"
const WAKE_HEAD := Vector2(0.38, 0.2)
var _wake_tex: Texture2D = load(WAKE_ART) if ResourceLoader.exists(WAKE_ART) else null
## Feet (bottom-centre) in world space and sprite height per pose: asleep at the desk, then
## up and growing as he steps toward the dial. The loot bag owns x 220-500 below the dial.
const ART_FEET: Array[Vector2] = [Vector2(116, 1090), Vector2(108, 1090), Vector2(116, 1090), Vector2(124, 1090)]
const ART_HEIGHT: PackedFloat32Array = [170.0, 200.0, 228.0, 262.0]
## Points on the sprites as fractions of their size: flashlight lens, and heads (Zzz, "!").
const ALERT_LENS := Vector2(0.95, 0.44)
const ALERT_HEAD := Vector2(0.45, 0.14)
const SLEEP_HEAD := Vector2(0.62, 0.3)
var _sleep_tex: Texture2D = load(SLEEP_ART) if ResourceLoader.exists(SLEEP_ART) else null
var _alert_tex: Texture2D = load(ALERT_ART) if ResourceLoader.exists(ALERT_ART) else null

## 0..3, tweened between alarm levels. Fractions blend the keyframes.
var _pose: float = 0.0
var _pose_tween: Tween
## 1 on a fresh strike, fades to 0: drives the "!" and the body punch.
var _alert: float = 0.0
var _alert_tween: Tween
var _level: int = 0
var _t: float = 0.0
## 0..1 arm reach, 0..1 cuff closed.
var _reach: float = 0.0
var _shut: float = 0.0
var _bust_tween: Tween


func _ready() -> void:
	z_index = 1
	# Overlays pause the tree; the beam keeps scanning behind the bribe popup.
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.alarm_changed.connect(_on_alarm)
	EventBus.run_started.connect(_on_run_started)
	EventBus.busted.connect(_on_busted)
	# A bribe lets go of the pick; a bust keeps it cuffed under the card.
	EventBus.revive_resolved.connect(func(success: bool) -> void:
		if success:
			_release()
	)
	queue_redraw()


func _process(delta: float) -> void:
	# Real seconds, so hitstop does not freeze the snore.
	_t += delta / maxf(Engine.time_scale, 0.001)
	queue_redraw()


func _on_run_started() -> void:
	_release()
	_level = 0
	if _pose_tween:
		_pose_tween.kill()
	_pose = 0.0
	_alert = 0.0


func _on_alarm(level: int, _max_level: int) -> void:
	var show: int = clampi(level, 0, 3)
	var rising: bool = show > 0 and show >= _level
	_level = show
	if rising:
		_ping_alert()
	if _pose_tween:
		_pose_tween.kill()
	_pose_tween = create_tween()
	_pose_tween.set_ignore_time_scale(true)
	if show <= 0:
		# Alarm cleared (bribe or new run): he settles back at the desk.
		_pose_tween.tween_method(_set_pose, _pose, 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		return
	if show >= 3 and GameState.is_first_heist(GameState.current_stage):
		# Heist 1 teaches the threat without the bust: up, look around, back to sleep.
		_pose_tween.tween_method(_set_pose, _pose, 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_pose_tween.tween_interval(DOZE_DELAY)
		_pose_tween.tween_method(_set_pose, 1.0, 0.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		return
	_pose_tween.tween_method(_set_pose, _pose, float(show), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_busted() -> void:
	if _bust_tween:
		_bust_tween.kill()
	_reach = 0.0
	_shut = 0.0
	_bust_tween = create_tween()
	_bust_tween.set_ignore_time_scale(true)
	_bust_tween.tween_property(self, "_reach", 1.0, REACH_SEC).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_bust_tween.tween_property(self, "_shut", 1.0, CLOSE_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_bust_tween.tween_callback(func() -> void: EventBus.juice_hit.emit("cuffed", 1.0))


func _release() -> void:
	if _bust_tween:
		_bust_tween.kill()
	_reach = 0.0
	_shut = 0.0


func _set_pose(value: float) -> void:
	_pose = clampf(value, 0.0, 3.0)


func _ping_alert() -> void:
	if _alert_tween:
		_alert_tween.kill()
	_alert = 1.0
	_alert_tween = create_tween()
	_alert_tween.set_ignore_time_scale(true)
	_alert_tween.tween_property(self, "_alert", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _draw() -> void:
	if _sleep_tex and _alert_tex:
		_draw_art()
		return
	var i: int = mini(floori(_pose), 2)
	var f: float = _pose - float(i)
	var pos: Vector2 = POSE_POS[i].lerp(POSE_POS[i + 1], f)
	var rot: float = lerpf(POSE_ROT[i], POSE_ROT[i + 1], f)
	# Strike punch: 1.18 → 1.0 as the alert fades.
	var s: float = lerpf(POSE_SCALE[i], POSE_SCALE[i + 1], f) * (1.0 + 0.18 * _alert * _alert)
	var awake: float = clampf(_pose * 2.0, 0.0, 1.0)
	var standing: float = clampf(_pose - 1.0, 0.0, 1.0)
	var out_front: bool = _pose >= 2.5

	_draw_backlight(pos, rot, s)
	if out_front:
		_draw_desk()
	_draw_body(pos, rot, s, awake, standing)
	if not out_front:
		_draw_desk()
	var head: Vector2 = pos + HEAD.rotated(rot) * s
	if standing > 0.0:
		_draw_flashlight(pos, rot, s, standing)
	_draw_snore(head, 1.0 - awake)
	_draw_alert(head, s)
	if _reach > 0.0:
		_draw_cuffs(pos, rot, s)


## Sprite version: the sleeping guard cross-fades into the alert one as he wakes, which
## then grows and steps toward the dial. Beam, Zzz, "!" and cuffs anchor to sprite points.
func _draw_art() -> void:
	var i: int = mini(floori(_pose), 2)
	var f: float = _pose - float(i)
	var feet: Vector2 = ART_FEET[i].lerp(ART_FEET[i + 1], f)
	var punch: float = 1.0 + 0.12 * _alert * _alert
	var height: float = lerpf(ART_HEIGHT[i], ART_HEIGHT[i + 1], f) * punch
	# Wake-up cross-fade sits between pose 0.3 and 0.7.
	var awake: float = clampf((_pose - 0.3) / 0.4, 0.0, 1.0)
	var standing: float = clampf(_pose - 1.0, 0.0, 1.0)
	# Strike 1 keeps him at the desk (awake, flashlight off); from pose 1.3 he is up and aiming.
	var aim: float = clampf((_pose - 1.3) / 0.4, 0.0, 1.0) if _aim_tex else 0.0
	var desk_feet: Vector2 = ART_FEET[0]
	var sleep_rect := _feet_rect(_sleep_tex, desk_feet, ART_HEIGHT[0] * punch)
	var mid_tex: Texture2D = _wake_tex if _wake_tex else _alert_tex
	var mid_rect := _feet_rect(mid_tex, desk_feet, ART_HEIGHT[0] * punch) if _wake_tex else _feet_rect(_alert_tex, feet, height)
	var aim_rect := _feet_rect(_aim_tex, feet, height) if _aim_tex else mid_rect
	if awake < 1.0:
		draw_texture_rect(_sleep_tex, sleep_rect, false, Color(1, 1, 1, 1.0 - awake))
	if awake > 0.0 and aim < 1.0:
		draw_texture_rect(mid_tex, mid_rect, false, Color(1, 1, 1, awake * (1.0 - aim)))
	if aim > 0.0:
		draw_texture_rect(_aim_tex, aim_rect, false, Color(1, 1, 1, awake * aim))
	var lens: Vector2 = aim_rect.position + aim_rect.size * AIM_LENS if _aim_tex else mid_rect.position + mid_rect.size * ALERT_LENS
	# The beam only exists once the flashlight is up: it fades in with the aiming pose.
	var beam: float = standing * (aim if _aim_tex else 1.0)
	if beam > 0.0:
		_draw_beam(lens, beam)
	var head: Vector2 = sleep_rect.position + sleep_rect.size * SLEEP_HEAD
	if awake > 0.5:
		head = mid_rect.position + mid_rect.size * (WAKE_HEAD if _wake_tex else ALERT_HEAD)
	if aim > 0.5:
		head = aim_rect.position + aim_rect.size * AIM_HEAD
	_draw_snore(head, 1.0 - awake)
	_draw_alert(head, height / 200.0)
	if _reach > 0.0:
		_draw_cuffs_from(lens, height / 200.0)


func _feet_rect(tex: Texture2D, feet: Vector2, height: float) -> Rect2:
	var width: float = height * float(tex.get_width()) / float(tex.get_height())
	return Rect2(feet - Vector2(width * 0.5, height), Vector2(width, height))


## Flashlight cone from `from` to the dial: sweeping on pose 2, locked on pose 3.
func _draw_beam(from: Vector2, amount: float) -> void:
	var arena := get_parent().get_node_or_null("Arena") as Node2D
	var centre: Vector2 = arena.position if arena else Vector2(360, 500)
	var lock: float = clampf(_pose - 2.0, 0.0, 1.0)
	var sweep := Vector2(sin(_t * 1.7) * 160.0, sin(_t * 1.1) * 70.0)
	var jitter := Vector2(sin(_t * 9.0) * 6.0, cos(_t * 7.0) * 4.0)
	var aim: Vector2 = centre + sweep.lerp(jitter, lock)
	var dir: Vector2 = (aim - from).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var half: float = lerpf(70.0, 95.0, lock)
	var beam: Color = BEAM.lerp(BEAM_HARD, lock)
	beam.a *= amount
	draw_colored_polygon(PackedVector2Array([
		from + perp * 6.0, aim + perp * half, aim - perp * half, from - perp * 6.0,
	]), beam)
	draw_circle(aim, half, Color(beam, beam.a * 0.8))


## Cold halo behind the silhouette so the dark body reads on every wall colour.
func _draw_backlight(pos: Vector2, rot: float, s: float) -> void:
	var chest: Vector2 = pos + Vector2(0, -60).rotated(rot) * s
	for k in 3:
		draw_circle(chest, (64.0 + 22.0 * k) * s, BACKLIGHT)


func _draw_desk() -> void:
	draw_rect(DESK_FRONT, DESK)
	draw_rect(DESK_TOP, DESK_EDGE)
	# Desk lamp: warm pool on the top, the only light while he sleeps.
	var base := Vector2(DESK_TOP.position.x + 22.0, DESK_TOP.position.y)
	draw_circle(base + Vector2(10, 4), 34.0, Color(LAMP, 0.06))
	draw_circle(base + Vector2(10, 4), 18.0, Color(LAMP, 0.1))
	draw_line(base, base + Vector2(0, -26), DESK_EDGE, 3.0, true)
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(-8, -24), base + Vector2(10, -32), base + Vector2(16, -20), base + Vector2(2, -16),
	]), DESK_EDGE)


func _draw_body(pos: Vector2, rot: float, s: float, awake: float, standing: float) -> void:
	draw_set_transform(pos, rot, Vector2(s, s))
	# Legs only show once he stands; behind the desk they are hidden anyway.
	if standing > 0.0:
		var leg_h: float = 62.0 * standing
		draw_rect(Rect2(-22, 0, 17, leg_h), BODY)
		draw_rect(Rect2(5, 0, 17, leg_h), BODY)
	# Torso: broad shoulders, narrow waist.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-36, -64), Vector2(-26, -72), Vector2(26, -72), Vector2(36, -64), Vector2(28, 2), Vector2(-28, 2),
	]), BODY)
	draw_circle(Vector2(-14, -48), 3.5, BADGE)
	# Head and police cap, visor facing the dial.
	draw_circle(HEAD, HEAD_R, BODY)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-21, -102), Vector2(19, -102), Vector2(25, -118), Vector2(-23, -116),
	]), BODY)
	draw_colored_polygon(PackedVector2Array([
		Vector2(4, -104), Vector2(32, -102), Vector2(30, -98), Vector2(4, -99),
	]), BODY)
	draw_circle(Vector2(1, -110), 3.0, BADGE)
	# Eyes: closed slits while asleep, white dots once awake, wider when he is on you.
	if awake < 0.5:
		draw_line(Vector2(3, -93), Vector2(9, -92), Color(1, 1, 1, 0.35), 1.6, true)
		draw_line(Vector2(12, -93), Vector2(18, -92), Color(1, 1, 1, 0.35), 1.6, true)
	else:
		var r: float = 2.4 + 1.0 * standing
		draw_circle(Vector2(6, -93), r, Color(1, 1, 1, awake))
		draw_circle(Vector2(15, -93), r, Color(1, 1, 1, awake))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Pose 2 sweeps the dial; pose 3 locks on it.
func _draw_flashlight(pos: Vector2, rot: float, s: float, amount: float) -> void:
	var arena := get_parent().get_node_or_null("Arena") as Node2D
	var centre: Vector2 = arena.position if arena else Vector2(360, 500)
	var lock: float = clampf(_pose - 2.0, 0.0, 1.0)
	var sweep := Vector2(sin(_t * 1.7) * 160.0, sin(_t * 1.1) * 70.0)
	var jitter := Vector2(sin(_t * 9.0) * 6.0, cos(_t * 7.0) * 4.0)
	var aim: Vector2 = centre + sweep.lerp(jitter, lock)
	var shoulder: Vector2 = pos + SHOULDER.rotated(rot) * s
	var dir: Vector2 = (aim - shoulder).normalized()
	var hand: Vector2 = shoulder + dir * ARM_LEN * s
	var perp := Vector2(-dir.y, dir.x)
	var half: float = lerpf(70.0, 95.0, lock)
	var beam: Color = BEAM.lerp(BEAM_HARD, lock)
	beam.a *= amount
	draw_colored_polygon(PackedVector2Array([
		hand + perp * 5.0, aim + perp * half, aim - perp * half, hand - perp * 5.0,
	]), beam)
	draw_circle(aim, half, Color(beam, beam.a * 0.8))
	draw_line(shoulder, hand, Color(BODY, amount), 11.0 * s, true)
	draw_circle(hand, 7.0 * s, Color(LAMP, amount))


## Arm shoots from his shoulder to the pick tip; one cuff ring closes on the tip,
## the other stays on his wrist, chain between.
func _draw_cuffs(pos: Vector2, rot: float, s: float) -> void:
	_draw_cuffs_from(pos + SHOULDER.rotated(rot) * s, s)


func _draw_cuffs_from(shoulder: Vector2, s: float) -> void:
	var arena := get_parent().get_node_or_null("Arena") as RingArena
	if arena == null:
		return
	var tip: Vector2 = arena.position + Vector2.from_angle(arena.pointer_angle) * PICK_TIP
	var hand: Vector2 = shoulder.lerp(tip, 0.55 * _reach)
	var cuff_at: Vector2 = shoulder.lerp(tip, _reach)
	draw_line(shoulder, hand, BODY, 14.0 * s, true)
	draw_circle(hand, 9.0 * s, BODY)
	# Chain: alternating links from the wrist ring to the tip ring.
	var links: int = 7
	for i in links:
		var a: Vector2 = hand.lerp(cuff_at, float(i) / float(links))
		var b: Vector2 = hand.lerp(cuff_at, float(i + 1) / float(links))
		draw_line(a, b, STEEL_DARK if i % 2 == 0 else STEEL, 4.0, true)
	_draw_cuff_ring(hand, 12.0 * s, 1.0)
	var r: float = lerpf(CUFF_OPEN_R, CUFF_SHUT_R, _shut)
	# Open cuff is a C; it closes to a full ring as `_shut` reaches 1.
	_draw_cuff_ring(cuff_at, r, lerpf(0.7, 1.0, _shut))


func _draw_cuff_ring(at: Vector2, r: float, closed: float) -> void:
	var gap: float = (1.0 - closed) * TAU
	var start: float = -PI * 0.5 + gap * 0.5
	var end: float = start + TAU - gap
	draw_arc(at, r, start, end, 32, STEEL_DARK, 9.0, true)
	draw_arc(at, r, start, end, 32, STEEL, 4.0, true)
	draw_arc(at, r - 3.0, start, start + (end - start) * 0.35, 12, Color(1, 1, 1, 0.8), 1.6, true)


func _draw_snore(head: Vector2, amount: float) -> void:
	if amount <= 0.01:
		return
	var font: Font = ThemeDB.fallback_font
	for k in 3:
		var phase: float = fmod(_t * 0.6 + float(k) / 3.0, 1.0)
		var at: Vector2 = head + Vector2(20.0 + phase * 30.0, -18.0 - phase * 60.0)
		var size: int = int(18.0 + phase * 14.0)
		draw_string(font, at, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(SNORE, amount * (1.0 - phase)))


## "!" pops over the head on every strike.
func _draw_alert(head: Vector2, s: float) -> void:
	if _alert <= 0.01:
		return
	var font: Font = ThemeDB.fallback_font
	var size: int = int(56.0 * (0.8 + 0.4 * _alert))
	var at: Vector2 = head + Vector2(-10.0, -HEAD_R * s - 40.0 - 12.0 * (1.0 - _alert))
	draw_string(font, at, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(ALERT, minf(1.0, _alert * 2.0)))
