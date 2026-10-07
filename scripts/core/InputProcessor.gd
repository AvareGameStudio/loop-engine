class_name InputProcessor
extends Node
## One-finger input: a press locks the pin. No hold, no slow-mo, no second verb.
## Only the "tap" action is read: on mobile, touch index 0 is emulated as a
## mouse click, so GUI buttons consume it first.

signal committed(mode: String, held_seconds: float)

var _armed: bool = false
var _tap_buffered: bool = false


func arm(enabled: bool = true) -> void:
	_armed = enabled


func peek_buffer() -> bool:
	return _tap_buffered


func take_buffer() -> bool:
	if not _tap_buffered:
		return false
	_tap_buffered = false
	return true


func clear_buffer() -> void:
	_tap_buffered = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("tap"):
		return
	if not _armed:
		# Early tap during respawn: GameWorld fires it at the Good gate.
		if GameState.run_active:
			_tap_buffered = true
			get_viewport().set_input_as_handled()
		return
	# Commit on press, not release: the lowest-latency read of the player's intent.
	committed.emit("tap", 0.0)
	get_viewport().set_input_as_handled()
