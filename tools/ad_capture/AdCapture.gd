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
## 0-4 s    hook: two strikes lit, guard on his feet, a late tap, the cuffs snap on the pick
## 4-15 s   heist 7 (double gate), doors 2-3: chained gates, Hot Hands ignites, door flies
## 15-27 s  golden heist, last door: fire ring, gold door, hoard rain, card with the loot roll
## 27-30 s  hold on the card (NEXT HEIST is the call to action)

const FPS: int = 30
const SIZE := Vector2i(720, 1280)
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


func _ready() -> void:
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
		box.stretch = true
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(box)
		_view = SubViewport.new()
		_view.size = SIZE
		_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		box.add_child(_view)
		_view.add_child(_main)
		_view.size = SIZE
		DirAccess.make_dir_recursive_absolute(_frames_dir)
		var f := FileAccess.open(_frames_dir.path_join("start_frame.txt"), FileAccess.WRITE)
		f.store_string(str(Engine.get_frames_drawn()))
		f.close()
		RenderingServer.frame_post_draw.connect(_grab)
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
		_world._on_commit("tap", 0.0)


func _run() -> void:
	await _frames(3)
	_world = get_tree().get_first_node_in_group("game_world")
	_arena = _world.arena
	_ui = _main.find_child("UIManager", true, false)
	_popup = _main.find_child("RevivePopup", true, false)
	_ui.bag.set_cash(GameState.cash, true)
	await _hook()
	await _double_heist()
	await _golden_heist()
	# End frame: only the loot and NEXT HEIST, no meta row.
	await _frames(2)
	_ui.card_meta.visible = false
	await _seconds(3.0)
	get_tree().quit()


## Two lamps lit, the guard up with his flashlight, then a late tap: near miss, third strike, cuffs.
func _hook() -> void:
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
	if _popup._open:
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
