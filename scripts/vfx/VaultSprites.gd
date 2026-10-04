class_name VaultSprites
extends RefCounted
## Painted vault door, tumbler, tap hand, and gem textures.
## Built once at runtime so the dial reads as a steel door, not a flat circle.

static var door: Texture2D
static var pin: Texture2D
static var hand: Texture2D
static var gold: Texture2D
static var gem: Texture2D


static func ensure() -> void:
	if door != null:
		return
	door = ImageTexture.create_from_image(_door())
	pin = ImageTexture.create_from_image(_pin())
	hand = ImageTexture.create_from_image(_hand())
	gold = ImageTexture.create_from_image(_bar())
	gem = ImageTexture.create_from_image(_gem())


static func _door() -> Image:
	var size := 320
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(159.5, 159.5)
	for y in size:
		for x in size:
			var local := Vector2(float(x), float(y)) - c
			if absf(local.x) > 150.0 or absf(local.y) > 150.0:
				continue
			var edge := maxf(absf(local.x), absf(local.y))
			var dist := local.length()
			var ang := local.angle()
			var grain := 0.9 + 0.1 * sin(local.y * 1.1) * sin(local.x * 0.33)
			var shade := 0.3
			if edge > 140.0:
				shade = 0.14
			elif edge > 132.0:
				shade = 0.66
			if dist < 124.0:
				shade = 0.2 + 0.12 * (1.0 - dist / 124.0)
				grain = 0.86 + 0.14 * sin(ang * 64.0 + dist * 0.8)
			if dist > 108.0 and dist < 118.0:
				shade = 0.55
			if dist < 84.0 and dist > 74.0:
				shade = 0.6
			if dist < 58.0:
				shade = 0.045
			img.set_pixel(x, y, Color(shade * grain, shade * grain * 1.01, shade * grain * 1.07, 1.0))
	for i in 8:
		var bolt := c + Vector2.from_angle(float(i) * TAU / 8.0 + 0.4) * 136.0
		_disc(img, bolt, 7.0, Color(0.16, 0.17, 0.19, 1.0))
		_disc(img, bolt, 4.5, Color(0.62, 0.64, 0.68, 1.0))
		_disc(img, bolt + Vector2(-1.2, -1.2), 1.4, Color(0.9, 0.91, 0.93, 1.0))
	for i in 4:
		var spoke := float(i) * TAU / 4.0 + 0.4
		_line(img, c + Vector2.from_angle(spoke) * 60.0, c + Vector2.from_angle(spoke) * 74.0, 5.0, Color(0.46, 0.48, 0.52, 1.0))
	# Glass window: a beveled bullion stack and a faceted stone.
	_bullion(img, c + Vector2(-28.0, -26.0), 54.0, 13.0)
	_bullion(img, c + Vector2(-24.0, -8.0), 48.0, 13.0)
	_brilliant(img, c + Vector2(0.0, 24.0), 14.0)
	_ring(img, c, 54.0, 2.6, Color(0.78, 0.62, 0.24, 1.0))
	for deg in range(0, 360, 15):
		var tick := deg_to_rad(float(deg))
		var major := deg % 45 == 0
		_line(
			img,
			c + Vector2.from_angle(tick) * (92.0 if major else 98.0),
			c + Vector2.from_angle(tick) * 108.0,
			1.8 if major else 1.0,
			Color(0.86, 0.88, 0.9, 1.0)
		)
	return img


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
