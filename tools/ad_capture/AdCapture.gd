extends Node
## Scripted ~30 s ad capture. Plays the real game with a director instead of a player,
## for Godot's Movie Maker:
##   godot --path . --write-movie ad.avi --fixed-fps 30 --resolution 720x1280 res://tools/ad_capture/AdCapture.tscn
## Never writes the player's save (GameState.no_save).
##
## Movie Maker records the window, which a laptop screen shrinks below 720x1280. With
## AD_FRAMES=<dir> set, the game renders in a 720x1280 SubViewport instead and every frame is
## saved there as a JPG (frame_00000.jpg...), plus start_frame.txt so the audio from the same
## Movie Maker run (`--write-movie <dir>/mm.png` writes mm.wav) can be lined up.
## tools/ad_capture/encode_mp4.swift then builds the H.264/AAC mp4 without ffmpeg.
##
## Always English (ad networks test in US/EN), with a tutorial finger pressing on each tap.
## AD_HOOK picks the opening; AD_SIZE=1080 renders 1080x1920 instead of 720x1280.
##   cuff (default): busted hook -> double-gate heist -> golden door -> loot card
##   nearmiss:       two hair-width misses, then a Perfect streak -> golden door -> loot card
##   golden:         golden door bursts first -> double-gate heist -> busted, end on the bribe

const FPS: int = 30
const SIZE := Vector2i(720, 1280)
const FINGER := preload("res://tools/ad_capture/TapFinger.gd")
## Where the fingertip rests (design coordinates): below the dial, right of the loot bag.
const FINGER_AT := Vector2(560, 940)
const MAIN := preload("res://scenes/Main.tscn")

var _main: Node
var _world: Node
var _arena: Node
var _ui: Node
var _popup: Node
## Seconds the director wants the tap off the gate centre: 0 = Perfect, + early, - late.
var _offset: float = 0.0
var _auto: bool = false
var _frames_dir: String = OS.get_environment("AD_FRAMES")
var _view: SubViewport
var _frame_index: int = 0
var _hook_kind: String = OS.get_environment("AD_HOOK") if OS.get_environment("AD_HOOK") != "" else "cuff"
var _finger: Node2D


func _ready() -> void:
	TranslationServer.set_locale("en")
	GameState.no_save = true
	GameState.auto_tap = false
	# Clean numbers on screen: the bag climbs from a small stake, no stash from a real save.
	GameState.cash = 120
	GameState.unclaimed_cash = 0
	_main = MAIN.instantiate()
	if _frames_dir.is_empty():
		add_child(_main)
	else:
		# Full-size render target, shown scaled in the window for a live preview.
		var box := SubViewportContainer.new()
		# No stretch: a stretching container would force the viewport down to the window size.
		box.stretch = false
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(box)
		_view = SubViewport.new()
		var out_size: Vector2i = Vector2i(1080, 1920) if OS.get_environment("AD_SIZE") == "1080" else SIZE
		_view.size = out_size
		# The game is laid out at 720x1280; a bigger target renders the same layout sharper.
		_view.size_2d_override = SIZE
		_view.size_2d_override_stretch = true
		_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		box.add_child(_view)
		_view.add_child(_main)
		_view.size = out_size
		DirAccess.make_dir_recursive_absolute(_frames_dir)
		var f := FileAccess.open(_frames_dir.path_join("start_frame.txt"), FileAccess.WRITE)
		f.store_string(str(Engine.get_frames_drawn()))
		f.close()
		RenderingServer.frame_post_draw.connect(_grab)
	var layer := CanvasLayer.new()
	layer.layer = 60
	_finger = FINGER.new()
	_finger.position = FINGER_AT
	layer.add_child(_finger)
	(_view if _view else self).add_child(layer)
	get_tree().current_scene = self
	_run.call_deferred()


func _grab() -> void:
	var img: Image = _view.get_texture().get_image()
	img.save_jpg(_frames_dir.path_join("frame_%05d.jpg" % _frame_index), 0.92)
	_frame_index += 1


func _process(_delta: float) -> void:
	if not _auto or _world == null or not GameState.run_active or not _arena.spinning or _world._busy:
		return
	var ahead: float = wrapf(angle_difference(_arena.pointer_angle, _arena.target_angle) * _arena.direction, -PI * 0.5, PI * 1.5)
	var speed: float = _arena.rpm * TAU + absf(_arena.drift_rate())
	if ahead / speed <= _offset:
		_finger.tap()
		_world._on_commit("tap", 0.0)


func _run() -> void:
	await _frames(3)
	_world = get_tree().get_first_node_in_group("game_world")
	_arena = _world.arena
	_ui = _main.find_child("UIManager", true, false)
	_popup = _main.find_child("RevivePopup", true, false)
	_ui.bag.set_cash(GameState.cash, true)
	GameState.daily_last_day = GameState.today()
	match _hook_kind:
		"nearmiss":
			await _hook_nearmiss()
			await _golden_heist()
			await _end_on_card()
		"golden":
			await _golden_heist()
			await _seconds(1.2)
			await _double_heist()
			await _hook(false)
			await _seconds(2.0)
		_:
			await _hook()
			await _double_heist()
			await _golden_heist()
			await _end_on_card()
	get_tree().quit()


## End frame: only the loot and NEXT HEIST, no meta row.
func _end_on_card() -> void:
	await _frames(2)
	_ui.card_meta.visible = false
	_ui.daily_btn.visible = false
	await _seconds(3.0)


## Heist 9: a hair late, a hair early (two lamps, the guard rising), then a clean Perfect run.
func _hook_nearmiss() -> void:
	_start_at(25)
	var good: float = deg_to_rad(float(_arena.windows.good) + 2.5)
	var speed: float = _arena.rpm * TAU
	_auto = true
	_offset = -good / speed
	await _wait_taps(1)
	_offset = good / speed
	await _wait_taps(1)
	_offset = 0.0
	await _wait_taps(4)
	_auto = false
	await _seconds(0.6)


## Two lamps lit, the guard up with his flashlight, then a late tap: near miss, third strike, cuffs.
func _hook(close_popup: bool = true) -> void:
	_start_at(16)
	GameState.raise_alarm()
	GameState.raise_alarm()
	_offset = 0.0
	_auto = true
	# One clean pin so the first second shows the verb, then the miss.
	await _wait_taps(1)
	_offset = -deg_to_rad(float(_arena.windows.good) + 3.0) / (_arena.rpm * TAU)
	await _wait_signal_or(EventBus.busted, 4.0)
	_auto = false
	await _seconds(1.3)
	if close_popup and _popup._open:
		_popup._close()


## Heist 7, door 2 onward: the chained second gate and four Perfects into Hot Hands.
func _double_heist() -> void:
	_start_at(20)
	_offset = 0.0
	_auto = true
	await _wait_signal_or(EventBus.run_ended, 14.0)
	_auto = false
	await _seconds(1.2)


## Golden heist, last door: gold door, fire ring, the hoard spilling, the card rolling the loot.
func _golden_heist() -> void:
	_ui.card.visible = false
	_start_at(15)
	_offset = 0.0
	_auto = true
	await _wait_signal_or(EventBus.run_ended, 14.0)
	_auto = false


## Starts a run on `stage` without touching the save.
func _start_at(stage: int) -> void:
	GameState.stages_cleared = stage - 1
	_ui.card.visible = false
	_world.start_run()


func _wait_taps(count: int) -> void:
	for i in count:
		await EventBus.tap_evaluated


func _wait_signal_or(sig: Signal, timeout: float) -> void:
	var done: Array[bool] = [false]
	var mark := func(_a = null, _b = null) -> void: done[0] = true
	sig.connect(mark, CONNECT_ONE_SHOT)
	var frames: int = int(timeout * FPS)
	while not done[0] and frames > 0:
		await get_tree().process_frame
		frames -= 1
	if sig.is_connected(mark):
		sig.disconnect(mark)


func _seconds(s: float) -> void:
	await _frames(int(s * FPS))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
