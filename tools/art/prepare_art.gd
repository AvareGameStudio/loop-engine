extends SceneTree
## Turns the Canva export (1080 px PNGs, see tools/art/README.md) into game-ready art.
##   CANVA_DIR=<dir> godot --headless --path . -s res://tools/art/prepare_art.gd   (pass 1: images)
##   godot --headless --path . --import                                             (Godot imports them)
##   STEP=theme godot --headless --path . -s res://tools/art/prepare_art.gd         (pass 2: UI theme)
## Re-run both passes whenever an export changes; the outputs are committed, the export is not.

const ART := "res://assets/art/"
const UI := "res://assets/ui/"
const LOOT_IDS: PackedStringArray = [
	"cash", "gold", "diamond", "painting", "trophy", "watch",
	"crown", "car", "yacht", "jet", "island", "moonrock",
]
const BACKGROUNDS: PackedStringArray = ["piggy", "office", "bank", "museum", "casino", "fort", "moon"]
## City strip: one building per vault type plus the moon vault at the end of the road.
const CITY: PackedStringArray = ["piggy", "office", "bank", "museum", "casino", "fort", "moon"]
## The flashlight lens on guard_alert sits at ~71% of the width; the painted beam is cut past it
## so Guard.gd can aim its own beam at the dial.
const ALERT_BEAM_CUT: float = 0.725
const LOOT_SIZE: int = 160


func _initialize() -> void:
	if OS.get_environment("STEP") == "theme":
		_build_theme()
	else:
		_prepare_images(OS.get_environment("CANVA_DIR"))
	quit()


func _prepare_images(src: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ART))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UI))
	_door(_load(src, "door"))
	var alert := _load(src, "guard_alert")
	_clear_right_of(alert, int(alert.get_width() * ALERT_BEAM_CUT))
	_save(_fit_height(_trim(alert), 360), ART + "guard_alert.png")
	_save(_fit_height(_trim(_load(src, "guard_sleep")), 280), ART + "guard_sleep.png")
	# Third pose: head up, flashlight raised toward the dial (pose 2-3).
	if FileAccess.file_exists(src.path_join("guard_aim.png")):
		_save(_fit_height(_trim(_load(src, "guard_aim")), 360), ART + "guard_aim.png")
	for kind: String in CITY:
		var city := src.path_join("city_%s.png" % kind)
		if FileAccess.file_exists(city):
			_save(_square(_trim(_load(src, "city_" + kind)), 128), ART + "city_%s.png" % kind)
	for extra: Array in [["cuffs", 240], ["tap_hand", 180], ["daily", 160]]:
		if FileAccess.file_exists(src.path_join(extra[0] + ".png")):
			_save(_square(_trim(_load(src, extra[0])), extra[1]), ART + extra[0] + ".png")
	_save(_fit_width(_trim(_load(src, "bag")), 360), ART + "bag.png")
	for id: String in LOOT_IDS:
		_save(_square(_trim(_load(src, "loot_" + id)), LOOT_SIZE), ART + "loot_%s.png" % id)
	for kind: String in BACKGROUNDS:
		var bg := _load(src, "bg_" + kind)
		bg.resize(720, 1280, Image.INTERPOLATE_LANCZOS)
		bg.convert(Image.FORMAT_RGB8)
		bg.save_jpg(ProjectSettings.globalize_path(ART + "bg_%s.jpg" % kind), 0.86)
	# 64 px tall: the nine-slice caps must fit inside a 48 px button.
	_save(_fit_height(_trim(_load(src, "btn_primary")), 64), UI + "btn_primary.png")
	_save(_fit_height(_trim(_load(src, "btn_secondary")), 64), UI + "btn_secondary.png")
	_save(_fit_width(_trim(_load(src, "panel")), 512), UI + "panel.png")
	var icon := _load(src, "app_icon")
	icon.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	_save(icon, "res://icon.png")
	print("prepared art from ", src)


## The background remover left the porthole edge ragged. Recentre the square on the hole
## and punch a clean circle a few pixels wider, so the loot sprite behind it reads sharply.
func _door(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var c := Vector2(w, h) * 0.5
	var sum := Vector2.ZERO
	var count := 0
	var probe: int = int(w * 0.16)
	for y in range(int(c.y) - probe, int(c.y) + probe):
		for x in range(int(c.x) - probe, int(c.x) + probe):
			if img.get_pixel(x, y).a < 0.5:
				sum += Vector2(x, y)
				count += 1
	var hole_c: Vector2 = sum / maxf(count, 1)
	var hole_r: float = sqrt(float(count) / PI)
	# Largest square centred on the hole that stays inside the image.
	var half: int = int(minf(minf(hole_c.x, w - hole_c.x), minf(hole_c.y, h - hole_c.y)))
	var square := img.get_region(Rect2i(int(hole_c.x) - half, int(hole_c.y) - half, half * 2, half * 2))
	var size := square.get_width()
	var centre := Vector2(size, size) * 0.5
	var punch: float = hole_r + 16.0
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(centre)
			if d < punch:
				square.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d < punch + 2.0:
				var p := square.get_pixel(x, y)
				p.a *= (d - punch) / 2.0
				square.set_pixel(x, y, p)
	square.resize(640, 640, Image.INTERPOLATE_LANCZOS)
	_save(square, ART + "door.png")
	print("door: hole centre offset ", hole_c - c, " radius ", hole_r, " -> ", punch * 640.0 / size, " px of 640")


func _load(src: String, name: String) -> Image:
	var img := Image.load_from_file(src.path_join(name + ".png"))
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _trim(img: Image) -> Image:
	var used := img.get_used_rect()
	return img.get_region(used.grow(4).intersection(Rect2i(Vector2i.ZERO, img.get_size())))


func _clear_right_of(img: Image, x0: int) -> void:
	for y in img.get_height():
		for x in range(x0, img.get_width()):
			img.set_pixel(x, y, Color(0, 0, 0, 0))


func _fit_height(img: Image, h: int) -> Image:
	img.resize(maxi(1, int(img.get_width() * float(h) / img.get_height())), h, Image.INTERPOLATE_LANCZOS)
	return img


func _fit_width(img: Image, w: int) -> Image:
	img.resize(w, maxi(1, int(img.get_height() * float(w) / img.get_width())), Image.INTERPOLATE_LANCZOS)
	return img


## Fits inside a size x size transparent square, centred, so every loot icon has the same box.
func _square(img: Image, size: int) -> Image:
	var s: float = float(size) / maxf(img.get_width(), img.get_height())
	img.resize(maxi(1, int(img.get_width() * s)), maxi(1, int(img.get_height() * s)), Image.INTERPOLATE_LANCZOS)
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), (Vector2i(size, size) - img.get_size()) / 2)
	return out


func _save(img: Image, path: String) -> void:
	img.save_png(ProjectSettings.globalize_path(path))


# --- Pass 2: theme -----------------------------------------------------------

## Teal secondary buttons by default, gold "PrimaryButton" variation, gold-rimmed panels.
## Nine-slice margins keep the rounded caps and the chunky bottom edge at any width.
func _build_theme() -> void:
	var theme := Theme.new()
	var secondary: Texture2D = load(UI + "btn_secondary.png")
	var primary: Texture2D = load(UI + "btn_primary.png")
	var panel: Texture2D = load(UI + "panel.png")
	_button_styles(theme, "Button", secondary)
	theme.set_type_variation("PrimaryButton", "Button")
	_button_styles(theme, "PrimaryButton", primary)
	for type: String in ["Button", "PrimaryButton"]:
		theme.set_color("font_color", type, Color.WHITE)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, Color(0.92, 0.92, 0.92))
		theme.set_color("font_focus_color", type, Color.WHITE)
		theme.set_color("font_disabled_color", type, Color(1, 1, 1, 0.55))
		theme.set_color("font_outline_color", type, Color(0.05, 0.06, 0.12))
		theme.set_constant("outline_size", type, 8)
	var box := StyleBoxTexture.new()
	box.texture = panel
	var m: float = panel.get_width() * 0.14
	box.set_texture_margin_all(m)
	box.set_content_margin_all(m * 0.7)
	theme.set_stylebox("panel", "PanelContainer", box)
	theme.set_stylebox("panel", "Panel", box)
	var err := ResourceSaver.save(theme, UI + "game_theme.tres")
	print("theme saved: ", error_string(err))


func _button_styles(theme: Theme, type: String, tex: Texture2D) -> void:
	var h: float = tex.get_height()
	var states := {
		"normal": Color.WHITE,
		"hover": Color(1.08, 1.08, 1.08),
		"pressed": Color(0.82, 0.82, 0.82),
		"disabled": Color(0.55, 0.55, 0.6, 0.7),
	}
	for state: String in states:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.modulate_color = states[state]
		sb.texture_margin_left = h * 0.5
		sb.texture_margin_right = h * 0.5
		sb.texture_margin_top = h * 0.3
		sb.texture_margin_bottom = h * 0.36
		sb.content_margin_left = h * 0.45
		sb.content_margin_right = h * 0.45
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 10.0
		theme.set_stylebox(state, type, sb)
	theme.set_stylebox("focus", type, StyleBoxEmpty.new())
