class_name InputProcessor
extends Node
## One-finger input: tap-to-lock, plus hold-and-release for a brief slow-mo assist.
## Emits a single "commit" per press so the timing engine never double-fires.

signal committed(mode: String, held_seconds: float)
signal hold_progress(t: float)

@export var hold_slowmo_after: float = 0.12
@export var max_hold: float = 0.85
@export var ignore_ui: bool = true

var _holding := false
var _hold_time := 0.0
var _armed := true
var _consumed_this_frame := false


func arm(enabled: bool = true) -> void:
	_armed = enabled
	if not enabled:
		_cancel_hold()


func _process(delta: float) -> void:
	_consumed_this_frame = false
	if not _holding:
		return
	_hold_time += delta
	hold_progress.emit(clampf(_hold_time / max_hold, 0.0, 1.0))
	if _hold_time >= hold_slowmo_after and Engine.time_scale > 0.55:
		Engine.time_scale = lerpf(Engine.time_scale, 0.55, 0.2)
	if _hold_time >= max_hold:
		_commit("hold_release")


func _unhandled_input(event: InputEvent) -> void:
	if not _armed:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_hold()
		else:
			_commit("tap" if _hold_time < hold_slowmo_after else "hold_release")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("tap"):
		_begin_hold()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("tap"):
		_commit("tap" if _hold_time < hold_slowmo_after else "hold_release")
		get_viewport().set_input_as_handled()


func _begin_hold() -> void:
	if _holding or _consumed_this_frame:
		return
	_holding = true
	_hold_time = 0.0
	EventBus.hold_started.emit()


func _commit(mode: String) -> void:
	if not _holding or _consumed_this_frame:
		return
	_consumed_this_frame = true
	var held := _hold_time
	_holding = false
	_hold_time = 0.0
	if Engine.time_scale < 0.99 and mode == "hold_release":
		pass
	else:
		Engine.time_scale = 1.0
	EventBus.hold_released.emit(held)
	committed.emit(mode, held)


func _cancel_hold() -> void:
	_holding = false
	_hold_time = 0.0
	if Engine.time_scale != 0.0:
		Engine.time_scale = 1.0
