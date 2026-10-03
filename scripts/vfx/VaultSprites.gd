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
			if dist < 46.0:
				shade = 0.05
			img.set_pixel(x, y, Color(shade * grain, shade * grain * 1.01, shade * grain * 1.07, 1.0))
	for i in 8:
		var bolt := c + Vector2.from_angle(float(i) * TAU / 8.0 + 0.4) * 136.0
		_disc(img, bolt, 7.0, Color(0.16, 0.17, 0.19, 1.0))
		_disc(img, bolt, 4.5, Color(0.62, 0.64, 0.68, 1.0))
		_disc(img, bolt + Vector2(-1.2, -1.2), 1.4, Color(0.9, 0.91, 0.93, 1.0))
	for i in 4:
		var spoke := float(i) * TAU / 4.0 + 0.4
		_line(img, c + Vector2.from_angle(spoke) * 16.0, c + Vector2.from_angle(spoke) * 70.0, 5.0, Color(0.46, 0.48, 0.52, 1.0))
	_disc(img, c, 12.0, Color(0.55, 0.57, 0.6, 1.0))
	_disc(img, c, 4.0, Color(0.1, 0.1, 0.12, 1.0))
	for i in 3:
		_rect(img, Rect2(c.x - 16.0, c.y - 14.0 + float(i) * 8.0, 32.0, 5.0), Color(0.95, 0.72, 0.18, 1.0))
	_diamond(img, c + Vector2(-10, 16), 5.0, Color(0.78, 0.94, 1.0, 1.0))
	_diamond(img, c + Vector2(10, 16), 5.0, Color(0.92, 0.98, 1.0, 1.0))
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


static func _bar() -> Image:
	var img := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_rect(img, Rect2(0, 0, 16, 8), Color(0.7, 0.46, 0.08, 1.0))
	_rect(img, Rect2(1, 1, 14, 3), Color(1.0, 0.88, 0.4, 1.0))
	return img


static func _gem() -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_diamond(img, Vector2(8, 8), 7.0, Color(0.72, 0.94, 1.0, 1.0))
	_diamond(img, Vector2(8, 7), 3.0, Color(1, 1, 1, 0.95))
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


static func _diamond(img: Image, c: Vector2, extent: float, color: Color) -> void:
	var reach := int(ceil(extent)) + 1
	for y in range(int(c.y) - reach, int(c.y) + reach + 1):
		for x in range(int(c.x) - reach, int(c.x) + reach + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var local := Vector2(float(x), float(y)) - c
			if absf(local.x) + absf(local.y) <= extent:
				img.set_pixel(x, y, color)


static func _finger(img: Image, rect: Rect2, cap: float, color: Color) -> void:
	_rect(img, rect, color)
	var mid_x := rect.position.x + rect.size.x * 0.5
	_disc(img, Vector2(mid_x, rect.position.y), cap, color)
	_disc(img, Vector2(mid_x, rect.end.y), cap, color)
