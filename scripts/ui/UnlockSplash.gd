class_name UnlockSplash
extends CanvasLayer
## Full-screen "MARKET OPEN!" / "CREW UNLOCKED!" moment over the card that closes the unlock
## heist. Play data: the gold "NEW! Market" word on the card's meta row was too small to see,
## so the Market sat unopened. Sunburst + hero art pop + coin rain + one big gold button.
## Built in code; the card stays under it and one tap on the button opens the system.

signal accepted(kind: String)

const VaultArt := preload("res://scripts/vfx/VaultSprites.gd")
const GOLD := Color(1.0, 0.84, 0.3, 1.0)
const INK := Color(0.04, 0.03, 0.02, 1.0)
## Hero art per unlock. A missing file falls back to the fan of painted gloves / nothing.
const HERO_ART := {
	"market": "res://assets/art/market.png",
	"crew": "res://assets/art/crew.png",
	"daily": "res://assets/art/daily.png",
}
## Three gloves fanned behind the market hero: what the shop sells, no words needed.
const FAN_GLOVES: PackedStringArray = ["latex", "crimson", "ice"]

var _kind: String = ""
var _root: Control
var _rays: Control
var _hero: Control
var _title: Label
var _body: Label
var _go: Button
var _later: Button
var _confetti: CPUParticles2D
var _spin: Tween
var _breath: Tween


func _ready() -> void:
	layer = 28
	process_mode = Node.PROCESS_MODE_ALWAYS
	VaultArt.ensure()
	_build()
	_root.visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _root.visible:
		_refresh_texts()


func is_open() -> bool:
	return _root.visible


## `kind`: "market", "crew" or "daily".
func show_unlock(kind: String) -> void:
	_kind = kind
	_fill_hero()
	_refresh_texts()
	_root.visible = true
	_root.modulate.a = 0.0
	_title.scale = Vector2(0.2, 0.2)
	_hero.scale = Vector2.ZERO
	_go.scale = Vector2(0.6, 0.6)
	_go.modulate.a = 0.0
	_later.modulate.a = 0.0
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(_root, "modulate:a", 1.0, 0.16)
	# Hero slams in big and settles: 0 -> 1.25 -> 1.0.
	tw.tween_callback(func() -> void:
		_pivot_center(_hero)
		EventBus.juice_hit.emit("unlock", 1.0)
		_confetti.restart()
		_confetti.emitting = true
	)
	tw.tween_property(_hero, "scale", Vector2(1.25, 1.25), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_hero, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: _pivot_center(_title))
	tw.tween_property(_title, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _pivot_center(_go))
	tw.parallel().tween_property(_go, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(_go, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_later, "modulate:a", 0.6, 0.25).set_delay(0.3)
	tw.tween_callback(_breathe_go)
	_start_rays()


func _close() -> void:
	for tw: Tween in [_spin, _breath]:
		if tw:
			tw.kill()
	_spin = null
	_breath = null
	_go.scale = Vector2.ONE
	_root.visible = false


func _accept() -> void:
	_close()
	accepted.emit(_kind)


func _refresh_texts() -> void:
	var key: String = _kind.to_upper()
	_title.text = tr("UNLOCK_%s_TITLE" % key)
	_body.text = tr("UNLOCK_%s_BODY" % key)
	_go.text = tr("UNLOCK_%s_GO" % key)
	_later.text = tr("UNLOCK_LATER")


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.06, 0.93)
	_root.add_child(dim)

	_rays = Control.new()
	_rays.position = Vector2(360, 440)
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rays.draw.connect(_draw_rays)
	_root.add_child(_rays)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 40
	col.offset_right = -40
	col.offset_top = 150
	col.offset_bottom = -90
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", 18)
	_root.add_child(col)

	_title = _label(68, GOLD, 12)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)

	_hero = Control.new()
	_hero.custom_minimum_size = Vector2(0, 380)
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_hero)

	_body = _label(28, Color(1, 1, 1, 0.95), 8)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_body)

	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(gap)

	_go = Button.new()
	_go.theme_type_variation = &"PrimaryButton"
	_go.custom_minimum_size = Vector2(0, 104)
	_go.add_theme_font_size_override("font_size", 40)
	_go.pressed.connect(_accept)
	col.add_child(_go)

	_later = Button.new()
	_later.flat = true
	_later.custom_minimum_size = Vector2(0, 56)
	_later.add_theme_font_size_override("font_size", 22)
	_later.pressed.connect(_close)
	col.add_child(_later)

	_confetti = CPUParticles2D.new()
	_confetti.position = Vector2(360, -28)
	_confetti.z_index = 5
	_confetti.emitting = false
	_confetti.amount = 90
	_confetti.lifetime = 2.0
	_confetti.one_shot = true
	_confetti.explosiveness = 0.85
	_confetti.randomness = 0.45
	_confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_confetti.emission_rect_extents = Vector2(340, 40)
	_confetti.direction = Vector2(0, 1)
	_confetti.spread = 28.0
	_confetti.gravity = Vector2(0, 1100)
	_confetti.initial_velocity_min = 40.0
	_confetti.initial_velocity_max = 220.0
	_confetti.scale_amount_min = 0.8
	_confetti.scale_amount_max = 1.5
	_confetti.texture = VaultArt.gold
	_confetti.color = Color(1.0, 0.86, 0.28, 1.0)
	add_child(_confetti)


func _label(size: int, color: Color, outline: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	return l


## Market: three gloves fanned behind the shop art (or alone without it). Crew: the crew art.
func _fill_hero() -> void:
	for child in _hero.get_children():
		child.queue_free()
	var center := Vector2(320, 190)
	if _kind == "market":
		var angles: Array[float] = [-24.0, 0.0, 24.0]
		var offsets: Array[Vector2] = [Vector2(-150, 40), Vector2(0, -10), Vector2(150, 40)]
		for i in FAN_GLOVES.size():
			var g := _tex(VaultArt.glove_icon(FAN_GLOVES[i]), Vector2(190, 190))
			g.position = center + offsets[i] - g.size * 0.5
			g.pivot_offset = g.size * 0.5
			g.rotation_degrees = angles[i]
			_hero.add_child(g)
	var art: String = String(HERO_ART.get(_kind, ""))
	if art != "" and ResourceLoader.exists(art):
		var big := _kind != "market"
		var hero := _tex(load(art), Vector2(340, 340) if big else Vector2(250, 250))
		hero.position = center + (Vector2.ZERO if big else Vector2(0, 70)) - hero.size * 0.5
		_hero.add_child(hero)


func _tex(texture: Texture2D, box: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size = box
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## 14 soft gold rays behind the hero, turning one revolution every 14 s.
func _draw_rays() -> void:
	var n: int = 14
	var r: float = 900.0
	var half: float = PI / float(n) * 0.5
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var pts := PackedVector2Array([Vector2.ZERO, Vector2.from_angle(a - half) * r, Vector2.from_angle(a + half) * r])
		_rays.draw_colored_polygon(pts, Color(1.0, 0.8, 0.25, 0.13))
	_rays.draw_circle(Vector2.ZERO, 210.0, Color(1.0, 0.82, 0.3, 0.12))


func _start_rays() -> void:
	if _spin:
		_spin.kill()
	_rays.rotation = 0.0
	_rays.queue_redraw()
	_spin = create_tween().set_loops()
	_spin.set_ignore_time_scale(true)
	_spin.tween_property(_rays, "rotation", TAU, 14.0).from(0.0)


## The button breathes 1.0 -> 1.06 so the eye lands on it.
func _breathe_go() -> void:
	if not _root.visible:
		return
	_pivot_center(_go)
	_breath = create_tween().set_loops()
	_breath.set_ignore_time_scale(true)
	_breath.tween_property(_go, "scale", Vector2(1.06, 1.06), 0.45).set_trans(Tween.TRANS_SINE)
	_breath.tween_property(_go, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)


func _pivot_center(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
