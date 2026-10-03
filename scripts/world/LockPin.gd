class_name LockPin
extends Node2D

const VaultArt := preload("res://scripts/vfx/VaultSprites.gd")
## Tumbler sitting in the combination notch. A hit seats it; the flash shader
## is what the player reads as the pin catching.

@export var radius: float = 210.0

var locked: bool = false
var _flash_tween: Tween
var _eject_tween: Tween
var _bolt: Sprite2D


func _ready() -> void:
	VaultArt.ensure()
	_bolt = Sprite2D.new()
	_bolt.name = "Bolt"
	_bolt.texture = VaultArt.pin
	_bolt.scale = Vector2(0.72, 0.72)
	_bolt.use_parent_material = true
	add_child(_bolt)
	_layout()
	EventBus.stage_cleared.connect(_eject)


func place(angle: float) -> void:
	rotation = angle
	_layout()


func set_locked(is_locked: bool) -> void:
	locked = is_locked
	if _eject_tween:
		_eject_tween.kill()
	if _bolt:
		_bolt.modulate.a = 1.0
	_layout()


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


func _layout() -> void:
	if _bolt == null:
		return
	var sunk: float = 16.0 if locked else 0.0
	_bolt.position = Vector2(radius - 28.0 - sunk, 0.0)
	_bolt.modulate = Color(1.0, 0.86, 0.45, 1.0) if locked else Color.WHITE


func _eject(_index: int, _payout: int) -> void:
	if _bolt == null:
		return
	if _eject_tween:
		_eject_tween.kill()
	_eject_tween = create_tween()
	_eject_tween.set_ignore_time_scale(true)
	_eject_tween.tween_interval(0.1)
	_eject_tween.tween_property(_bolt, "position:x", radius + 90.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_eject_tween.parallel().tween_property(_bolt, "modulate:a", 0.0, 0.16)
