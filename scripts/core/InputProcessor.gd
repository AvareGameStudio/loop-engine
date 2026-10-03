class_name InputProcessor
extends Node
## One-finger input: tap-to-lock, plus hold-and-release for a slow-mo assist
## that drains a Focus meter. Only the "tap" action is read: on mobile, touch
## index 0 is emulated as a mouse click, so GUI buttons consume it first.

signal committed(mode: String, held_seconds: float)
signal hold_progress(t: float)

@export var hold_slowmo_after: float = 0.12
@export var max_hold: float = 0.85
@export var slowmo_scale: float = 0.55
## time_scale units per real second.
@export var slowmo_ramp: float = 4.0
## Focus spent per real second of slow-mo; a full meter lasts ~0.9 s.
@export var focus_drain: float = 1.1
const FOCUS_EMIT_STEP: float = 0.04

var focus: float = 1.0
var _holding: bool = false
var _hold_time: float = 0.0
var _armed: bool = false
var _tap_buffered: bool = false
var _empty_signaled: bool = false


func arm(enabled: bool = true) -> void:
	_armed = enabled
	if not enabled:
		_cancel_hold()


func peek_buffer() -> bool:
	return _tap_buffered


func take_buffer() -> bool:
	if not _tap_buffered:
		return false
	_tap_buffered = false
	return true


func clear_buffer() -> void:
	_tap_buffered = false


func add_focus(amount: float) -> void:
	var previous: float = focus
	focus = clampf(focus + amount, 0.0, 1.0)
	if focus > 0.0:
		_empty_signaled = false
	var crossed_edge: bool = is_zero_approx(focus) or is_equal_approx(focus, 1.0)
	if crossed_edge or absf(focus - previous) >= FOCUS_EMIT_STEP:
		EventBus.focus_changed.emit(focus)
	if previous > 0.0 and focus <= 0.0 and not _empty_signaled:
		_empty_signaled = true
		EventBus.juice_hit.emit("empty_focus", 1.0)


func reset_focus() -> void:
	focus = 1.0
	_empty_signaled = false
	EventBus.focus_changed.emit(focus)


func _process(delta: float) -> void:
	if not _holding:
		return
	var real_dt: float = delta / maxf(Engine.time_scale, 0.001)
	_hold_time += real_dt
	hold_progress.emit(clampf(_hold_time / max_hold, 0.0, 1.0))
	if _hold_time >= hold_slowmo_after and focus > 0.0:
		add_focus(-focus_drain * real_dt)
		TimeScale.set_slowmo(move_toward(TimeScale.slowmo, slowmo_scale, slowmo_ramp * real_dt))
	elif TimeScale.slowmo < 1.0:
		TimeScale.set_slowmo(move_toward(TimeScale.slowmo, 1.0, slowmo_ramp * real_dt))
	if _hold_time >= max_hold:
		_commit()


func _unhandled_input(event: InputEvent) -> void:
	if not _armed:
		if event.is_action_pressed("tap") and GameState.run_active:
			_tap_buffered = true
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("tap"):
		_begin_hold()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("tap"):
		_commit()
		get_viewport().set_input_as_handled()


func _begin_hold() -> void:
	if _holding:
		return
	_holding = true
	_hold_time = 0.0
	EventBus.hold_started.emit()


func _commit() -> void:
	if not _holding:
		return
	var held: float = _hold_time
	var mode: String = "tap" if held < hold_slowmo_after else "hold_release"
	_holding = false
	_hold_time = 0.0
	EventBus.hold_released.emit(held)
	committed.emit(mode, held)
	TimeScale.set_slowmo(1.0)


func _cancel_hold() -> void:
	_holding = false
	_hold_time = 0.0
	TimeScale.set_slowmo(1.0)
