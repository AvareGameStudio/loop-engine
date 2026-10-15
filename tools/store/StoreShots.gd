extends SceneTree
## Renders the five store screenshots as 1080x1920 PNGs (English, never touches the save):
##   OUT=<dir> godot --path . --fixed-fps 30 -s res://tools/store/StoreShots.gd --resolution 720x1280
## (--fixed-fps: at 1080 a frame can take longer than the pick's 1/30 s step cap and Auto-Crack stalls)
## 1 first door + tap finger · 2 guard aiming at the dial · 3 bust + bribe offer
## 4 golden vault cracking open · 5 hideout shop
## Captions are added in Canva (see tools/store/README.md).

const SIZE := Vector2i(1080, 1920)
const LAYOUT := Vector2i(720, 1280)

var _view: SubViewport
var _out: String = OS.get_environment("OUT")


func _initialize() -> void:
	root.get_node("GameState").no_save = true
	TranslationServer.set_locale("en")
	_view = SubViewport.new()
	_view.size = SIZE
	_view.size_2d_override = LAYOUT
	_view.size_2d_override_stretch = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	_view.add_child(main)
	# Juice parents sparks to current_scene.
	current_scene = main
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_view.get_texture().get_image().save_png(_out.path_join(name + ".png"))


func _run() -> void:
	var gs: Node = root.get_node("GameState")
	for i in 10:
		await process_frame
	# Settings applies the player's saved language on startup; store shots are English.
	TranslationServer.set_locale("en")
	var world: Node = get_first_node_in_group("game_world")
	var ui: Node = _view.get_node("Main").find_child("UIManager", true, false)
	gs.cash = 0
	gs.unclaimed_cash = 0
	gs.loot_bought = 0
	gs.daily_last_day = gs.today()
	gs.cosmetics = PackedStringArray(["leather", "gold"])
	gs.equip_glove("gold")
	# 1 first door, the coach finger on the gate.
	gs.stages_cleared = 0
	world.start_run()
	ui.bag.set_cash(0, true)
	await create_timer(1.0).timeout
	await _shot("01_tap")
	# 2 museum, two strikes: the guard looks up and aims at the dial.
	gs.stages_cleared = 15
	world.start_run()
	ui.bag.set_cash(860, true)
	await process_frame
	gs.raise_alarm()
	gs.raise_alarm()
	# Guard tweens run on real time, which --fixed-fps outpaces; give them room.
	await create_timer(3.0).timeout
	await _shot("02_guard")
	# 3 the third strike: cuffs on the pick, then the bribe offer.
	var arena: Node = world.arena
	arena.spinning = false
	arena.pointer_angle = arena.target_angle + deg_to_rad(60.0)
	world._on_commit("tap", 0.0)
	await create_timer(1.6).timeout
	await _shot("03_bribe")
	_view.get_node("Main").find_child("RevivePopup", true, false)._close()
	# 4 golden heist, last door: auto-crack until the door flies, shoot the hoard.
	ui.card.visible = false
	gs.stages_cleared = 14
	world.start_run()
	gs.auto_tap = true
	var cracked: Array[bool] = [false]
	root.get_node("EventBus").stage_cleared.connect(func(_s: int, _p: int) -> void: cracked[0] = true, CONNECT_ONE_SHOT)
	var frames: int = 0
	while not cracked[0] and frames < 60 * 30:
		await process_frame
		frames += 1
	if not cracked[0]:
		push_warning("StoreShots: golden door did not crack in 30 s")
	gs.auto_tap = false
	await create_timer(0.45).timeout
	await _shot("04_golden")
	await create_timer(1.5).timeout
	# 5 hideout shop with a few items and the next one for sale.
	ui.card.visible = false
	gs.stages_cleared = 30
	gs.loot_bought = 3
	gs.cash = 7200
	ui.bag.set_cash(7200, true)
	ui.get_node("HideoutPopup").open()
	await create_timer(0.6).timeout
	await _shot("05_hideout")
	quit()
