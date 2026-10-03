class_name RingPointer
extends Node2D
## Lockpick swept around the vault dial. The shaft is steel; the tip is a laser
## tooth bent along travel. RingArena drives `rotation`.
## Opening coach is a child Label (counter-rotated) so spinning costs no redraw.

const COACH_SECONDS: float = 3.0

@export var length: float = 200.0

var accent := Color(0.18, 0.9, 1.0, 1)
var danger := Color(1.0, 0.28, 0.52, 1)
var gold := Color(1.0, 0.84, 0.28, 1)

var direction: float = 1.0:
	set(value):
		if value != direction:
			_flip_flash = 1.0
		direction = value
		queue_redraw()
var grade: String = "":
	set(value):
		grade = value
		queue_redraw()

var _pulse: float = 0.0
var _flip_flash: float = 0.0
var _flash_tween: Tween
var _coach_left: float = 0.0
var _blink: float = 0.0
var _coach_anchor: Node2D
var _coach: Label


func _ready() -> void:
	_coach_anchor = Node2D.new()
	_coach_anchor.position = Vector2(length, 0.0)
	_coach = Label.new()
	_coach.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coach.add_theme_font_size_override("font_size", 32)
	_coach.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1))
	_coach.position = Vector2(-48.0, -56.0)
	_coach.custom_minimum_size = Vector2(96.0, 40.0)
	_coach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coach.visible = false
	_coach_anchor.add_child(_coach)
	add_child(_coach_anchor)
	EventBus.run_started.connect(_begin_coach)
	EventBus.run_ended.connect(_end_coach)
	EventBus.tap_evaluated.connect(func(_result: Dictionary) -> void: _end_coach())


func _begin_coach() -> void:
	_coach_left = COACH_SECONDS
	_blink = 0.0
	_coach.text = tr("COACH_TAP")
	_coach.visible = true


func _end_coach(_reason: String = "", _stats: Dictionary = {}) -> void:
	if _coach_left <= 0.0 and not _coach.visible:
		return
	_coach_left = 0.0
	_coach.visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _coach != null and _coach.visible:
		_coach.text = tr("COACH_TAP")


func _process(delta: float) -> void:
	var real_dt: float = delta / maxf(Engine.time_scale, 0.001)
	_pulse = wrapf(_pulse + real_dt * 2.4, 0.0, TAU)
	self_modulate.a = 0.88 + 0.12 * sin(_pulse)
	if _flip_flash > 0.0:
		_flip_flash = maxf(0.0, _flip_flash - real_dt * 2.5)
		queue_redraw()
	if _coach_left > 0.0:
		_coach_left = maxf(0.0, _coach_left - real_dt)
		_blink = wrapf(_blink + real_dt * 8.0, 0.0, TAU)
		_coach_anchor.rotation = -rotation
		_coach.modulate.a = 1.0 if sin(_blink) > 0.0 else 0.12
		if _coach_left <= 0.0:
			_coach.visible = false


## Drives hit_flash.gdshader; runs in real time so hitstop doesn't stretch it.
## `peak` is Perfect Power: a freshly bought upgrade flashes harder on the next Perfect.
func flash(seconds: float = 0.16, peak: float = 1.0) -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	if _flash_tween:
		_flash_tween.kill()
	mat.set_shader_parameter("amount", peak)
	_flash_tween = create_tween()
	_flash_tween.set_ignore_time_scale(true)
	_flash_tween.tween_property(mat, "shader_parameter/amount", 0.0, seconds)


func _draw() -> void:
	var col: Color = _grade_color()
	var tip := Vector2(length, 0.0)
	var laser: Color = col.lerp(Color.WHITE, 0.62)
	draw_line(Vector2(24.0, 1.6), Vector2(length - 34.0, 1.2), Color(0.16, 0.17, 0.19), 7.0, true)
	draw_line(Vector2(24.0, 0.0), Vector2(length - 34.0, 0.0), Color(0.72, 0.75, 0.78), 3.6, true)
	draw_line(Vector2(24.0, -1.4), Vector2(length - 34.0, -1.2), Color(0.92, 0.94, 0.96, 0.8), 1.3, true)
	draw_line(Vector2(length - 52.0, 0.0), tip + Vector2(8.0, 0.0), Color(col, 0.35), 11.0, true)
	draw_line(Vector2(length - 46.0, 0.0), tip + Vector2(7.0, 0.0), laser, 2.2, true)
	var tooth := tip + Vector2(-2.0, direction * (18.0 + 8.0 * _flip_flash))
	draw_line(tip + Vector2(-8.0, 0.0), tooth, Color(0.82, 0.84, 0.87), 3.4, true)
	draw_line(tip + Vector2(-6.0, direction), tooth, laser, 1.5, true)
	draw_circle(tip, 3.4, Color.WHITE)
	draw_circle(tip, 1.6, laser)
	draw_circle(Vector2.ZERO, 20.0, Color(0.1, 0.11, 0.12))
	draw_circle(Vector2.ZERO, 13.0, Color(0.34, 0.36, 0.39))
	draw_circle(Vector2.ZERO, 7.0, Color(0.72, 0.75, 0.78))
	draw_line(Vector2(-6.0, 0.0), Vector2(6.0, 0.0), Color(0.08, 0.08, 0.09), 2.0, true)


func _grade_color() -> Color:
	match grade:
		"perfect":
			return gold
		"near_miss", "miss":
			return danger
		_:
			return accent
