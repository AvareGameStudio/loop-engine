extends CanvasLayer
## HUD, Zeigarnik quest rings, run-over sheet, and market entry points. Fully signal-driven.

const GRADE_COLORS: Dictionary[String, Color] = {
	"perfect": Color(1.0, 0.86, 0.3),
	"good": Color(0.45, 0.9, 1.0),
	"near_miss": Color(1.0, 0.35, 0.55),
	"miss": Color(0.8, 0.25, 0.3),
}

@onready var score_label: Label = $HUD/Top/Score
@onready var combo_label: Label = $HUD/Top/Combo
@onready var mult_label: Label = $HUD/Top/Mult
@onready var grade_label: Label = $HUD/Center/Grade
@onready var hint_label: Label = $HUD/Center/Hint
@onready var stage_bar: ProgressBar = $HUD/Bottom/StageBar
@onready var focus_bar: ProgressBar = $HUD/Bottom/FocusBar
@onready var energy_label: Label = $HUD/Bottom/Wallet/Energy
@onready var coins_label: Label = $HUD/Bottom/Wallet/Coins
@onready var passive_label: Label = $HUD/Bottom/Wallet/Passive
@onready var loops_box: HBoxContainer = $Meta/Loops
@onready var run_over: Control = $RunOver
@onready var run_over_title: Label = $RunOver/Panel/VBox/Title
@onready var run_over_body: Label = $RunOver/Panel/VBox/Body
@onready var retry_btn: Button = $RunOver/Panel/VBox/Retry
@onready var x3_btn: Button = $RunOver/Panel/VBox/X3
@onready var run_over_market_btn: Button = $RunOver/Panel/VBox/Market
@onready var market_btn: Button = $Meta/Actions/Market
@onready var shop_btn: Button = $Meta/Actions/Shop
@onready var settings_btn: Button = $SettingsButton
@onready var settings_popup: SettingsPopup = $SettingsPopup
@onready var market_popup: MarketPopup = $MarketPopup

var zeigarnik := ZeigarnikTracker.new()
## id -> {"ring": QuestRing, "title": Label, "subtitle": Label}
var _loop_rows: Dictionary[String, Dictionary] = {}
var _grade_tween: Tween
## Translation keys behind code-set texts, re-rendered on language change.
var _hint_key: String = "HINT_RUN"
var _hint_args: Array = []
var _x3_key: String = "RUN_CLAIM_X3"
var _run_end_reason: String = ""
var _run_end_stats: Dictionary = {}


func _ready() -> void:
	run_over.visible = false
	grade_label.text = ""
	retry_btn.pressed.connect(_retry)
	x3_btn.pressed.connect(_x3)
	market_btn.pressed.connect(market_popup.open)
	run_over_market_btn.pressed.connect(market_popup.open)
	shop_btn.pressed.connect(_toggle_auto_tap)
	settings_btn.pressed.connect(settings_popup.open)
	EventBus.tap_evaluated.connect(_on_tap)
	EventBus.jackpot.connect(_on_jackpot)
	EventBus.multiplier_changed.connect(_on_mult)
	EventBus.energy_changed.connect(_on_energy)
	EventBus.coins_changed.connect(_on_coins)
	EventBus.vault_changed.connect(_on_vault)
	EventBus.meta_upgraded.connect(func(_stat: String, _level: int) -> void: _refresh_market())
	EventBus.zeigarnik_updated.connect(_on_loops)
	EventBus.run_ended.connect(_on_run_end)
	EventBus.run_started.connect(_on_run_start)
	EventBus.stage_cleared.connect(_on_stage)
	EventBus.ad_finished.connect(_on_ad)
	EventBus.dda_changed.connect(_on_dda)
	EventBus.session_changed.connect(_refresh_session)
	EventBus.focus_changed.connect(_on_focus)
	EventBus.countdown.connect(_on_countdown)
	_refresh_currency()
	_refresh_market()
	_refresh_session()
	_refresh_shop()
	_render_hint()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()


func _refresh_texts() -> void:
	grade_label.text = ""
	_render_hint()
	_refresh_currency()
	_refresh_market()
	_refresh_shop()
	_on_loops(zeigarnik.loops())
	if run_over.visible:
		_render_run_over()


func _set_hint(key: String, args: Array = []) -> void:
	_hint_key = key
	_hint_args = args
	_render_hint()


func _render_hint() -> void:
	hint_label.text = tr(_hint_key) % _hint_args if not _hint_args.is_empty() else tr(_hint_key)


func _refresh_session() -> void:
	stage_bar.max_value = maxi(GameState.hits_needed, 1)
	stage_bar.value = GameState.hits_in_stage
	score_label.text = str(GameState.session_score)
	combo_label.text = "x%d" % GameState.session_combo


func _on_tap(result: Dictionary) -> void:
	var grade_name: String = String(result.grade_name)
	_show_grade(tr("GRADE_" + grade_name.to_upper()), GRADE_COLORS.get(grade_name, Color.WHITE))


func _show_grade(text: String, color: Color) -> void:
	grade_label.text = text
	grade_label.modulate = color
	if _grade_tween:
		_grade_tween.kill()
	grade_label.scale = Vector2(1.25, 1.25)
	_grade_tween = create_tween()
	_grade_tween.set_ignore_time_scale(true)
	_grade_tween.tween_property(grade_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)


func _on_jackpot(mult: float, label: String) -> void:
	_show_grade("%s  x%.0f" % [tr(label), mult], Color(1.0, 0.84, 0.2))


func _on_countdown(step: int) -> void:
	if step > 0:
		_show_grade(str(step), Color.WHITE)
	else:
		_show_grade(tr("COUNTDOWN_GO"), GRADE_COLORS.good)


func _on_mult(value: float) -> void:
	mult_label.text = tr("HUD_PAYOUT") % value


func _on_focus(value: float) -> void:
	focus_bar.value = value


func _on_energy(amount: int, delta: int) -> void:
	energy_label.text = tr("HUD_ENERGY") % amount + ("  +%d" % delta if delta > 0 else "")
	_refresh_market()


func _on_coins(amount: int, _delta: int) -> void:
	coins_label.text = tr("HUD_COINS") % amount
	_refresh_market()


func _on_vault(_amount: int, _delta: int) -> void:
	_refresh_currency()
	_on_loops(zeigarnik.loops())


func _on_loops(loops: Array) -> void:
	var focus: String = ZeigarnikTracker.focus_id(loops)
	for loop: Dictionary in loops:
		var id: String = String(loop.id)
		if not _loop_rows.has(id):
			_loop_rows[id] = _make_loop_row(id)
		var row: Dictionary = _loop_rows[id]
		(row.ring as QuestRing).set_state(float(loop.progress), bool(loop.complete), id == focus)
		(row.title as Label).text = String(loop.title)
		(row.subtitle as Label).text = String(loop.subtitle)


func _make_loop_row(id: String) -> Dictionary:
	var column := VBoxContainer.new()
	column.name = id
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	var ring := QuestRing.new()
	ring.custom_minimum_size = Vector2(108, 108)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _make_caption(14, Color.WHITE)
	var subtitle := _make_caption(12, Color(0.7, 0.78, 0.9, 1))
	column.add_child(ring)
	column.add_child(title)
	column.add_child(subtitle)
	loops_box.add_child(column)
	return {"ring": ring, "title": title, "subtitle": subtitle}


func _make_caption(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _on_run_end(reason: String, stats: Dictionary) -> void:
	_run_end_reason = reason
	_run_end_stats = stats
	_x3_key = "RUN_BOOST_AUTO" if GameState.no_ads else "RUN_CLAIM_X3"
	x3_btn.disabled = GameState.no_ads
	run_over.visible = true
	_render_run_over()


func _render_run_over() -> void:
	run_over_title.text = tr("RUN_OVER_ALMOST" if _run_end_reason == "near_miss" else "RUN_OVER_BROKEN")
	run_over_body.text = "%s\n%s" % [
		tr("RUN_OVER_STATS") % [int(_run_end_stats.get("score", 0)), int(_run_end_stats.get("combo", 0))],
		tr("RUN_OVER_LOOPS") % zeigarnik.open_count(),
	]
	x3_btn.text = tr(_x3_key)


func _on_run_start() -> void:
	run_over.visible = false
	_set_hint("HINT_RUN")
	grade_label.text = ""
	focus_bar.value = 1.0


func _on_stage(index: int, _payout: int) -> void:
	_set_hint("HINT_RING_UNLOCKED", [index + 1])


func _on_dda(profile: Dictionary) -> void:
	_set_hint("HINT_FLOW", [float(profile.rpm)])


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
			_x3_key = "RUN_BOOST_CLAIMED"
			x3_btn.text = tr(_x3_key)
			x3_btn.disabled = true


## Market buttons advertise how many upgrades are affordable right now.
func _refresh_market() -> void:
	var affordable: int = MetaUpgrade.affordable_count()
	var text: String = tr("HUD_MARKET_COUNT") % affordable if affordable > 0 else tr("HUD_MARKET")
	market_btn.text = text
	run_over_market_btn.text = text
	passive_label.text = (
		tr("HUD_VAULT") % GameState.unclaimed_energy
		if GameState.unclaimed_energy > 0
		else tr("HUD_PULSE")
	)


func _refresh_currency() -> void:
	energy_label.text = tr("HUD_ENERGY") % GameState.energy
	coins_label.text = tr("HUD_COINS") % GameState.coins
	mult_label.text = tr("HUD_PAYOUT") % GameState.session_multiplier
	passive_label.text = (
		tr("HUD_VAULT") % GameState.unclaimed_energy
		if GameState.unclaimed_energy > 0
		else tr("HUD_PULSE")
	)


## Prototype-only: toggles the Auto-Tap entitlement so idle can be felt in-session.
func _toggle_auto_tap() -> void:
	GameState.auto_tap = not GameState.auto_tap
	GameState.save_game()
	_refresh_shop()


func _refresh_shop() -> void:
	shop_btn.text = tr("AUTO_TAP_ON" if GameState.auto_tap else "AUTO_TAP_OFF")
