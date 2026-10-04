class_name VaultSprites
extends RefCounted
## Painted vault door, tumbler, tap hand, and gem textures.
## The door starts as solid rust and, across 200 rings, sheds it down to gem-set ore.

static var door: Texture2D
static var pin: Texture2D
static var hand: Texture2D
static var gold: Texture2D
static var gem: Texture2D
static var _door_stage: int = -1


static func ensure() -> void:
	if pin != null:
		return
	pin = ImageTexture.create_from_image(_pin())
	hand = ImageTexture.create_from_image(_hand())
	gold = ImageTexture.create_from_image(_bar())
	gem = ImageTexture.create_from_image(_gem())


## One painted door for the current ring. Stage 1 is solid rust; stage 200 is gem-set ore.
static func door_for(stage: int) -> Texture2D:
	ensure()
	var key := stage if stage < 10 else 1000 + (maxi(stage, 10) - 10) / 2
	if key == _door_stage and door != null:
		return door
	door = ImageTexture.create_from_image(_door(key))
	_door_stage = key
	return door


static func _door(stage: int = 1) -> Image:
	var size := 320
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(159.5, 159.5)
	var rust_cover := GameState.shell_rust(stage)
	var metal := GameState.shell_metal(stage)
	var rust_hi := Color(0.55, 0.28, 0.10, 1.0)
	var rust_lo := Color(0.28, 0.13, 0.06, 1.0)
	for y in size:
		for x in size:
			var local := Vector2(float(x), float(y)) - c
			if absf(local.x) > 150.0 or absf(local.y) > 150.0:
				continue
			var edge := maxf(absf(local.x), absf(local.y))
			var dist := local.length()
			var shade := 0.34
			if edge > 140.0:
				shade = 0.16
			elif edge > 132.0:
				shade = 0.72
			if dist < 124.0:
				shade = 0.26 + 0.14 * (1.0 - dist / 124.0)
			if dist > 108.0 and dist < 118.0:
				shade = 0.62
			if dist < 84.0 and dist > 74.0:
				shade = 0.58
			if dist < 58.0:
				shade = 0.045
			var grain := 0.9 + 0.1 * _unit(x, int(y / 3))
			var col := Color(metal.r * shade * grain, metal.g * shade * grain, metal.b * shade * grain, 1.0)
			if dist >= 58.0 and rust_cover > 0.0:
				var flake := _unit(int(x / 10), int(y / 10))
				if flake < rust_cover:
					var pit := _unit(x * 3 + 11, y * 5 + 7)
					var crust := rust_lo.lerp(rust_hi, pit)
					var thick := clampf((rust_cover - flake) / 0.22, 0.35, 1.0)
					col = col.lerp(crust, thick)
				elif flake - rust_cover < 0.045:
					col = col.lerp(metal.lightened(0.45), 0.65)
			img.set_pixel(x, y, col)
	var bolt_cap := metal.lerp(rust_hi, rust_cover)
	var bolt_sink := metal.darkened(0.55).lerp(rust_lo, rust_cover)
	for i in 8:
		var bolt := c + Vector2.from_angle(float(i) * TAU / 8.0 + 0.4) * 136.0
		_disc(img, bolt, 7.0, bolt_sink)
		_disc(img, bolt, 4.5, bolt_cap)
		if rust_cover < 0.85:
			_disc(img, bolt + Vector2(-1.2, -1.2), 1.4, metal.lightened(0.55))
	for i in 4:
		var spoke := float(i) * TAU / 4.0 + 0.4
		_line(img, c + Vector2.from_angle(spoke) * 60.0, c + Vector2.from_angle(spoke) * 74.0, 5.0, bolt_cap.darkened(0.15))
	# Empty glass. The live counter sits here; the hoard only appears when the ring breaks.
	_ring(img, c, 54.0, 2.6, metal.lerp(Color(0.78, 0.62, 0.24), 0.35).lerp(rust_hi, rust_cover))
	var tick := metal.lightened(0.35).lerp(rust_lo, rust_cover * 0.7)
	for deg in range(0, 360, 15):
		var ang := deg_to_rad(float(deg))
		var major := deg % 45 == 0
		_line(
			img,
			c + Vector2.from_angle(ang) * (92.0 if major else 98.0),
			c + Vector2.from_angle(ang) * 108.0,
			1.8 if major else 1.0,
			tick
		)
	var inlay := GameState.shell_inlay(stage)
	if inlay >= 1:
		_ring(img, c, 78.0, 2.2, metal.lightened(0.25))
	if inlay >= 2:
		_ring(img, c, 96.0, 3.0, metal.lerp(Color(0.95, 0.82, 0.35), 0.55))
	if inlay >= 3:
		_ring(img, c, 128.0, 2.4, metal.lightened(0.45))
	var stones := GameState.shell_gems(stage)
	for i in stones:
		var at := c + Vector2.from_angle(float(i) / float(stones) * TAU + 0.2) * 100.0
		_stone(img, at, 4.5 + float(i % 3), i % 4)
	return img


static func _unit(x: int, y: int) -> float:
	var n := (x * 374761393 + y * 668265263) & 2147483647
	n = (n ^ (n >> 13)) * 1274126177
	return float(n & 65535) / 65535.0


static func _stone(img: Image, at: Vector2, radius: float, kind: int) -> void:
	var body := Color(0.12, 0.62, 0.34, 1.0)
	match kind:
		1:
			body = Color(0.18, 0.38, 0.82, 1.0)
		2:
			body = Color(0.72, 0.10, 0.16, 1.0)
		3:
			body = Color(0.90, 0.94, 0.98, 1.0)
	_disc(img, at, radius + 1.2, body.darkened(0.45))
	_disc(img, at, radius, body)
	_disc(img, at + Vector2(-radius * 0.28, -radius * 0.32), radius * 0.28, Color(1, 1, 1, 1))


static func _pin() -> Image:
	var img := Image.create(160, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_rect(img, Rect2(4, 14, 52, 36), Color(0.42, 0.3, 0.08, 1.0))
	_rect(img, Rect2(8, 18, 44, 28), Color(0.82, 0.62, 0.2, 1.0))
	_rect(img, Rect2(36, 24, 86, 16), Color(0.62, 0.64, 0.68, 1.0))
	_rect(img, Rect2(36, 24, 86, 4), Color(0.9, 0.92, 0.94, 1.0))
	_disc(img, Vector2(132, 32), 18.0, Color(0.32, 0.34, 0.37, 1.0))
	_disc(img, Vector2(132, 32), 13.0, Color(0.74, 0.76, 0.8, 1.0))
	_line(img, Vector2(124, 26), Vector2(140, 38), 2.2, Color(0.12, 0.12, 0.13, 1.0))
	return img


static func _hand() -> Image:
	var img := Image.create(128, 168, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var skin := Color(1.0, 0.9, 0.62, 1.0)
	var ink := Color(0.1, 0.07, 0.02, 1.0)
	_finger(img, Rect2(18, 58, 16, 52), 8.0, ink)
	_finger(img, Rect2(36, 40, 18, 70), 9.0, ink)
	_finger(img, Rect2(56, 28, 18, 82), 9.0, ink)
	_finger(img, Rect2(76, 46, 16, 60), 8.0, ink)
	_disc(img, Vector2(58, 108), 36.0, ink)
	_disc(img, Vector2(96, 96), 16.0, ink)
	_finger(img, Rect2(22, 62, 12, 46), 6.0, skin)
	_finger(img, Rect2(40, 44, 14, 64), 7.0, skin)
	_finger(img, Rect2(60, 32, 14, 76), 7.0, skin)
	_finger(img, Rect2(80, 50, 12, 54), 6.0, skin)
	_disc(img, Vector2(58, 108), 32.0, skin)
	_disc(img, Vector2(94, 96), 13.0, skin)
	return img


## Top face, front face, and a short end so the bar reads as a bullion, not a stripe.
static func _bullion(img: Image, origin: Vector2, width: float, height: float) -> void:
	var top := 8.0
	var gold := Color(0.96, 0.72, 0.12, 1.0)
	var face := Color(1.0, 0.88, 0.34, 1.0)
	var shine := Color(1.0, 0.97, 0.72, 1.0)
	var edge := Color(0.55, 0.32, 0.05, 1.0)
	var back_l := origin + Vector2(8.0, 0.0)
	var back_r := origin + Vector2(width - 6.0, -2.0)
	var top_l := origin + Vector2(14.0, -top)
	var top_r := origin + Vector2(width - 12.0, -top - 2.0)
	var front_l := origin + Vector2(8.0, height)
	var front_r := origin + Vector2(width - 6.0, height - 2.0)
	var end_b := origin + Vector2(0.0, height + 3.0)
	var end_t := origin + Vector2(2.0, 4.0)
	_tri(img, back_l + Vector2(2, 3), front_r + Vector2(2, 3), end_b + Vector2(2, 3), edge)
	_tri(img, back_l, back_r, top_r, face)
	_tri(img, back_l, top_l, top_r, face)
	_tri(img, back_l + Vector2(10, -2), back_r + Vector2(-8, -1), top_r + Vector2(-6, 2), shine)
	_tri(img, back_l, back_r, front_r, gold)
	_tri(img, back_l, front_l, front_r, gold)
	_tri(img, back_l, end_t, end_b, edge)
	_tri(img, back_l, front_l, end_b, edge)
	_tri(img, front_l, front_r, front_r + Vector2(0, 3), Color(0.42, 0.24, 0.04, 1.0))


## Brilliant cut: table on top, crown, then a pointed pavilion.
static func _brilliant(img: Image, center: Vector2, half: float) -> void:
	var table := Color(0.96, 0.99, 1.0, 1.0)
	var crown := Color(0.7, 0.9, 1.0, 1.0)
	var crown_side := Color(0.42, 0.7, 0.95, 1.0)
	var pavilion := Color(0.28, 0.58, 0.88, 1.0)
	var pavilion_side := Color(0.16, 0.4, 0.7, 1.0)
	var girdle_l := center + Vector2(-half, 0.0)
	var girdle_r := center + Vector2(half, 0.0)
	var tip := center + Vector2(0.0, half * 1.25)
	var crown_tip := center + Vector2(0.0, -half * 1.15)
	_tri(img, girdle_l, girdle_r, tip, pavilion)
	_tri(img, girdle_l, center, tip, pavilion_side)
	_tri(img, girdle_l, crown_tip, center, crown)
	_tri(img, girdle_r, crown_tip, center, crown_side)
	_tri(img, center + Vector2(-half * 0.32, -half * 0.62), center + Vector2(half * 0.32, -half * 0.62), crown_tip, table)
	_tri(img, center + Vector2(-half * 0.32, -half * 0.62), center + Vector2(half * 0.32, -half * 0.62), center + Vector2(0.0, -half * 0.28), table)
	_disc(img, center + Vector2(-half * 0.08, -half * 0.78), 1.6, Color(1, 1, 1, 1))


static func _tri(img: Image, a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	var area := _edge(a, b, c)
	if absf(area) < 0.01:
		return
	var min_x := int(floor(minf(a.x, minf(b.x, c.x))))
	var max_x := int(ceil(maxf(a.x, maxf(b.x, c.x))))
	var min_y := int(floor(minf(a.y, minf(b.y, c.y))))
	var max_y := int(ceil(maxf(a.y, maxf(b.y, c.y))))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var w0 := _edge(b, c, p)
			var w1 := _edge(c, a, p)
			var w2 := _edge(a, b, p)
			if w0 * area >= 0.0 and w1 * area >= 0.0 and w2 * area >= 0.0:
				img.set_pixel(x, y, color)


static func _edge(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)


static func _ring(img: Image, c: Vector2, radius: float, width: float, color: Color) -> void:
	var reach := int(ceil(radius + width)) + 1
	var inner := radius - width
	for y in range(int(c.y) - reach, int(c.y) + reach + 1):
		for x in range(int(c.x) - reach, int(c.x) + reach + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var dist := Vector2(float(x), float(y)).distance_to(c)
			if dist <= radius and dist >= inner:
				img.set_pixel(x, y, color)


static func _bar() -> Image:
	var img := Image.create(32, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_bullion(img, Vector2(2, 8), 26.0, 8.0)
	return img


static func _gem() -> Image:
	var img := Image.create(28, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_brilliant(img, Vector2(14, 12), 10.0)
	return img


static func _disc(img: Image, c: Vector2, radius: float, color: Color) -> void:
	var reach := int(ceil(radius)) + 1
	for y in range(int(c.y) - reach, int(c.y) + reach + 1):
		for x in range(int(c.x) - reach, int(c.x) + reach + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if Vector2(float(x), float(y)).distance_to(c) <= radius:
				img.set_pixel(x, y, color)


static func _rect(img: Image, rect: Rect2, color: Color) -> void:
	for y in range(int(rect.position.y), int(rect.end.y)):
		for x in range(int(rect.position.x), int(rect.end.x)):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			img.set_pixel(x, y, color)


static func _line(img: Image, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var steps := int(a.distance_to(b)) + 1
	for i in steps + 1:
		_disc(img, a.lerp(b, float(i) / float(maxi(steps, 1))), width * 0.5, color)


static func _finger(img: Image, rect: Rect2, cap: float, color: Color) -> void:
	_rect(img, rect, color)
	var mid_x := rect.position.x + rect.size.x * 0.5
	_disc(img, Vector2(mid_x, rect.position.y), cap, color)
	_disc(img, Vector2(mid_x, rect.end.y), cap, color)
