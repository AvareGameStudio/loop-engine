extends CanvasLayer
## HUD, Zeigarnik bars, run-over sheet, and meta upgrades.

@onready var score_label: Label = $HUD/Top/Score
@onready var combo_label: Label = $HUD/Top/Combo
@onready var mult_label: Label = $HUD/Top/Mult
@onready var grade_label: Label = $HUD/Center/Grade
@onready var hint_label: Label = $HUD/Center/Hint
@onready var stage_bar: ProgressBar = $HUD/Bottom/StageBar
@onready var energy_label: Label = $HUD/Bottom/Energy
@onready var loops_box: VBoxContainer = $Meta/Loops
@onready var run_over: Control = $RunOver
@onready var run_over_title: Label = $RunOver/Panel/VBox/Title
@onready var run_over_body: Label = $RunOver/Panel/VBox/Body
@onready var retry_btn: Button = $RunOver/Panel/VBox/Retry
@onready var x3_btn: Button = $RunOver/Panel/VBox/X3
@onready var gen_btn: Button = $Meta/Actions/Gen
@onready var glob_btn: Button = $Meta/Actions/Glob
@onready var shop_btn: Button = $Meta/Actions/Shop

var _loop_bars: Dictionary = {}
var _grade_tween: Tween


func _ready() -> void:
	run_over.visible = false
	grade_label.text = ""
	retry_btn.pressed.connect(_retry)
	x3_btn.pressed.connect(_x3)
	gen_btn.pressed.connect(func() -> void: _upgrade("generator"))
	glob_btn.pressed.connect(func() -> void: _upgrade("global_mult"))
	shop_btn.pressed.connect(_grant_debug_shop)
	EventBus.tap_evaluated.connect(_on_tap)
	EventBus.jackpot.connect(_on_jackpot)
	EventBus.multiplier_changed.connect(_on_mult)
	EventBus.energy_changed.connect(_on_energy)
	EventBus.zeigarnik_updated.connect(_on_loops)
	EventBus.run_ended.connect(_on_run_end)
	EventBus.run_started.connect(_on_run_start)
	EventBus.stage_cleared.connect(_on_stage)
	EventBus.ad_finished.connect(_on_ad)
	EventBus.dda_changed.connect(_on_dda)
	_refresh_currency()
	_refresh_upgrades()


func _process(_delta: float) -> void:
	if GameState.hits_needed <= 0:
		return
	stage_bar.max_value = GameState.hits_needed
	stage_bar.value = GameState.hits_in_stage
	score_label.text = str(GameState.session_score)
	combo_label.text = "x%d" % GameState.session_combo


func _on_tap(result: Dictionary) -> void:
	var name := String(result.grade_name).replace("_", " ").to_upper()
	grade_label.text = name
	grade_label.modulate = {
		"perfect": Color(1.0, 0.86, 0.3),
		"good": Color(0.45, 0.9, 1.0),
		"near_miss": Color(1.0, 0.35, 0.55),
		"miss": Color(0.8, 0.25, 0.3),
	}.get(String(result.grade_name), Color.WHITE)
	if _grade_tween:
		_grade_tween.kill()
	grade_label.scale = Vector2(1.25, 1.25)
	_grade_tween = create_tween()
	_grade_tween.tween_property(grade_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)


func _on_jackpot(mult: float, label: String) -> void:
	grade_label.text = "%s  x%.0f" % [label, mult]
	grade_label.modulate = Color(1.0, 0.84, 0.2)


func _on_mult(value: float) -> void:
	mult_label.text = "PAYOUT x%.1f" % value


func _on_energy(amount: int, delta: int) -> void:
	energy_label.text = "ENERGY  %d" % amount + ("  +%d" % delta if delta > 0 else "")
	_refresh_upgrades()


func _on_loops(loops: Array) -> void:
	for loop in loops:
		var id := String(loop.id)
		var row: Control = _loop_bars.get(id)
		if row == null:
			row = _make_loop_row(loop)
			loops_box.add_child(row)
			_loop_bars[id] = row
		var bar: ProgressBar = row.get_node("Bar")
		var caption: Label = row.get_node("Caption")
		bar.value = float(loop.progress)
		caption.text = "%s\n%s" % [loop.title, loop.subtitle]


func _make_loop_row(loop: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.name = String(loop.id)
	var caption := Label.new()
	caption.name = "Caption"
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 14)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	box.add_child(caption)
	box.add_child(bar)
	return box


func _on_run_end(reason: String, stats: Dictionary) -> void:
	run_over.visible = true
	run_over_title.text = "ALMOST" if reason == "near_miss" else "LOOP BROKEN"
	run_over_body.text = "Score %d   ·   Combo %d\n%d unfinished loops waiting." % [
		int(stats.get("score", 0)),
		int(stats.get("combo", 0)),
		ZeigarnikTracker.new().open_count(),
	]
	x3_btn.disabled = GameState.no_ads
	x3_btn.text = "Claim 3x Energy" if not GameState.no_ads else "3x already yours"


func _on_run_start() -> void:
	run_over.visible = false
	hint_label.text = "TAP THE RING"
	grade_label.text = ""


func _on_stage(index: int, _payout: int) -> void:
	hint_label.text = "RING %d UNLOCKED" % (index + 1)


func _on_dda(profile: Dictionary) -> void:
	hint_label.text = "FLOW  %.2f rps" % float(profile.rpm)


func _retry() -> void:
	run_over.visible = false
	var world := get_tree().get_first_node_in_group("game_world")
	if world and world.has_method("start_run"):
		world.start_run()


func _x3() -> void:
	x3_btn.disabled = true
	EventBus.ad_requested.emit("end_multiplier", {})


func _on_ad(placement: String, rewarded: bool) -> void:
	if placement == "end_multiplier":
		x3_btn.disabled = false
		if rewarded:
			x3_btn.text = "Boost claimed"
			x3_btn.disabled = true


func _upgrade(stat: String) -> void:
	if GameState.try_upgrade(stat):
		_refresh_upgrades()
		EventBus.zeigarnik_updated.emit(ZeigarnikTracker.new().loops())


func _refresh_upgrades() -> void:
	gen_btn.text = "Upgrade Generator  %d" % GameState.upgrade_cost("generator")
	glob_btn.text = "Upgrade Multiplier  %d" % GameState.upgrade_cost("global_mult")
	gen_btn.disabled = GameState.energy < GameState.upgrade_cost("generator")
	glob_btn.disabled = GameState.energy < GameState.upgrade_cost("global_mult")


func _refresh_currency() -> void:
	energy_label.text = "ENERGY  %d" % GameState.energy
	mult_label.text = "PAYOUT x%.1f" % GameState.session_multiplier


func _grant_debug_shop() -> void:
	## Prototype: long-press shop grants Auto-Tap so idle can be felt in-session.
	IAPCatalog.grant("auto_tap")
	shop_btn.text = "Auto-Tap ON"
