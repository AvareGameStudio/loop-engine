extends CanvasLayer

const VaultArt := preload("res://scripts/vfx/VaultSprites.gd")
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
@onready var grade_label: Label = $HUD/Grade
@onready var hint_label: Label = $HUD/Center/Hint
@onready var tap_prompt: Label = $HUD/TapPrompt
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
@onready var claim_popup: ClaimPopup = $ClaimPopup

var zeigarnik := ZeigarnikTracker.new()
## id -> {"ring": QuestRing, "title": Label, "subtitle": Label}
var _loop_rows: Dictionary[String, Dictionary] = {}
var _grade_tween: Tween
var _x3_key: String = "RUN_CLAIM_X3"
var _run_end_reason: String = ""
var _run_end_stats: Dictionary = {}
var _show_tap: bool = false
var _tap_pulse: float = 0.0
var _tap_reward: CanvasLayer
var _tap_hand: TextureRect
var _shop_home: Node
var _shop_index: int = -1
var _shop_anchor: Rect2 = Rect2()
var _reward_pause: bool = false
var _hold_hint_seen: bool = false


func _ready() -> void:
	run_over.visible = false
	grade_label.text = ""
	hint_label.visible = false
	hint_label.text = ""
	tap_prompt.visible = false
	retry_btn.pressed.connect(_retry)
	x3_btn.pressed.connect(_x3)
	market_btn.pressed.connect(market_popup.open)
	run_over_market_btn.pressed.connect(market_popup.open)
	shop_btn.visible = false
	shop_btn.pressed.connect(_toggle_auto_tap)
	settings_btn.pressed.connect(settings_popup.open)
	passive_label.mouse_filter = Control.MOUSE_FILTER_STOP
	passive_label.gui_input.connect(_on_vault_chip)
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
	EventBus.vr_tension.connect(_on_tension)
	EventBus.juice_hit.connect(_on_juice)
	EventBus.hold_started.connect(_hide_hold_hint)
	EventBus.theme_unlocked.connect(_on_theme)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_currency()
	_refresh_market()
	_refresh_session()
	_refresh_shop()
	_render_hint()
	_build_tap_reward()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()


func _refresh_texts() -> void:
	grade_label.text = ""
	_render_hint()
	if tap_prompt.visible:
		tap_prompt.text = tr("COACH_TAP")
	_refresh_currency()
	_refresh_market()
	_refresh_shop()
	_on_loops(zeigarnik.loops())
	if run_over.visible:
		_render_run_over()


func _process(delta: float) -> void:
	if not _show_tap:
		return
	var real_dt: float = delta / maxf(Engine.time_scale, 0.001)
	_tap_pulse = wrapf(_tap_pulse + real_dt * 8.0, 0.0, TAU)
	tap_prompt.modulate.a = 1.0 if sin(_tap_pulse) > 0.0 else 0.25
	var pulse: float = 1.0 + 0.08 * maxf(sin(_tap_pulse), 0.0)
	tap_prompt.scale = Vector2(pulse, pulse)


func _set_hint(_key: String, _args: Array = []) -> void:
	pass


func _render_hint() -> void:
	if hint_label.visible:
		hint_label.text = tr("HINT_RUN")
		return
	hint_label.text = ""


func _show_hold_hint() -> void:
	_hold_hint_seen = true
	hint_label.visible = true
	hint_label.text = tr("HINT_RUN")
	get_tree().create_timer(3.5, true, false, true).timeout.connect(_hide_hold_hint)


func _hide_hold_hint() -> void:
	hint_label.visible = false
	hint_label.text = ""


func _on_theme(theme_id: String) -> void:
	var theme_name: String = tr("THEME_" + theme_id.to_upper())
	_show_grade(tr("THEME_UNLOCKED") % theme_name, Color(0.65, 0.9, 1.0))


func _refresh_session() -> void:
	stage_bar.max_value = maxi(GameState.hits_needed, 1)
	stage_bar.value = GameState.hits_in_stage
	score_label.text = str(GameState.session_score)
	combo_label.text = "x%d" % GameState.session_combo
	_refresh_shop()


func _on_tap(result: Dictionary) -> void:
	_hide_tap_prompt()
	var grade_name: String = String(result.grade_name)
	_show_grade(tr("GRADE_" + grade_name.to_upper()), GRADE_COLORS.get(grade_name, Color.WHITE))
	if not _hold_hint_seen and (grade_name == "good" or grade_name == "perfect"):
		_show_hold_hint()


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


func _on_tension(value: float) -> void:
	# Gold pulse when a VR drop is close, without revealing the interval.
	focus_bar.modulate = Color(1.0, 0.84, 0.3, 1) if value >= 0.7 else Color.WHITE


func _on_juice(grade: String, _intensity: float) -> void:
	if grade != "empty_focus":
		return
	focus_bar.modulate = Color(1.0, 0.3, 0.35, 1)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(focus_bar, "modulate", Color.WHITE, 0.28)


func _on_vault_chip(event: InputEvent) -> void:
	if GameState.unclaimed_energy <= 0:
		return
	if event is InputEventMouseButton and event.pressed:
		claim_popup.open(GameState.unclaimed_energy, true)
		get_viewport().set_input_as_handled()


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
	var live: Dictionary = {}
	for loop: Dictionary in loops:
		var id: String = String(loop.id)
		live[id] = true
		if not _loop_rows.has(id):
			_loop_rows[id] = _make_loop_row(id)
		var row: Dictionary = _loop_rows[id]
		(row.ring as QuestRing).set_state(float(loop.progress), bool(loop.complete), id == focus)
		(row.title as Label).text = String(loop.title)
		(row.subtitle as Label).text = String(loop.subtitle)
	for id: String in _loop_rows.keys():
		if live.has(id):
			continue
		var stale: Dictionary = _loop_rows[id]
		(stale.column as Node).queue_free()
		_loop_rows.erase(id)


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
	return {"ring": ring, "title": title, "subtitle": subtitle, "column": column}


func _make_caption(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _on_run_end(reason: String, stats: Dictionary) -> void:
	_hide_tap_prompt()
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
	_hide_hold_hint()
	grade_label.text = ""
	focus_bar.value = 1.0
	# The dial shows a TAP hand on the gate. A banner here covers the vault.
	_hide_tap_prompt()


func _show_tap_prompt() -> void:
	# Level 1 only. The first registered tap retires the prompt for the run.
	if GameState.current_stage != 1:
		_hide_tap_prompt()
		return
	_show_tap = true
	_tap_pulse = 0.0
	tap_prompt.text = tr("COACH_TAP")
	tap_prompt.visible = true
	tap_prompt.scale = Vector2.ONE
	tap_prompt.modulate.a = 1.0


func _hide_tap_prompt() -> void:
	_show_tap = false
	tap_prompt.visible = false


func _on_stage(index: int, _payout: int) -> void:
	_set_hint("HINT_RING_UNLOCKED", [index + 1])
	if index == 1 and GameState.has_auto_tap_announce():
		_open_tap_reward()


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
func _build_tap_reward() -> void:
	var layer := CanvasLayer.new()
	layer.name = "AutoTapReward"
	layer.layer = 30
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.visible = false
	add_child(layer)
	var root := Control.new()
	root.name = "Root"
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_right = 720
	root.offset_bottom = 1280
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_right = 720
	dim.offset_bottom = 1280
	# Escape hatch: this sheet pauses the tree, so it must never be the only way out.
	dim.gui_input.connect(_on_reward_dim)
	root.add_child(dim)
	var panel := Panel.new()
	panel.name = "Panel"
	panel.position = Vector2(70, 460)
	panel.size = Vector2(580, 320)
	root.add_child(panel)
	var title := Label.new()
	title.name = "Title"
	title.position = Vector2(28, 12)
	title.size = Vector2(524, 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.28))
	panel.add_child(title)
	var body := Label.new()
	body.name = "Body"
	body.position = Vector2(36, 78)
	body.size = Vector2(508, 72)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 20)
	panel.add_child(body)
	var button := Button.new()
	button.name = "Continue"
	button.position = Vector2(170, 164)
	button.size = Vector2(240, 52)
	button.pressed.connect(_close_tap_reward)
	panel.add_child(button)
	VaultArt.ensure()
	var hand := TextureRect.new()
	hand.name = "Hand"
	hand.texture = VaultArt.hand
	hand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand.size = Vector2(96, 126)
	hand.pivot_offset = Vector2(48, 14)
	hand.rotation = PI
	root.add_child(hand)
	_tap_hand = hand
	_tap_reward = layer


func _open_tap_reward() -> void:
	if _tap_reward == null or _tap_reward.visible:
		return
	var panel := _tap_reward.get_node("Root/Panel")
	panel.get_node("Title").text = tr("AUTO_TAP_UNLOCKED")
	panel.get_node("Body").text = tr("AUTO_TAP_BODY")
	panel.get_node("Continue").text = tr("AUTO_TAP_CONTINUE")
	shop_btn.visible = true
	_tap_reward.visible = true
	get_tree().process_frame.connect(_finish_tap_reward, CONNECT_ONE_SHOT)


func _finish_tap_reward() -> void:
	if _tap_reward == null or not _tap_reward.visible:
		return
	_lift_shop_button()
	_point_at_shop()
	if not _reward_pause:
		_reward_pause = true
		OverlayPause.push()


func _on_reward_dim(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_tap_reward()
		get_viewport().set_input_as_handled()


func _close_tap_reward() -> void:
	if _tap_reward == null or not _tap_reward.visible:
		return
	_tap_reward.visible = false
	_drop_shop_button()
	GameState.accept_auto_tap_reward()
	_refresh_shop()
	if _reward_pause:
		_reward_pause = false
		OverlayPause.pop()


## Moves the live Auto-Tap button onto the reward layer so the dim cannot grey it out.
func _lift_shop_button() -> void:
	if _shop_home != null:
		return
	shop_btn.visible = true
	shop_btn.text = tr("AUTO_TAP_ON")
	var host: Control = _tap_reward.get_node("Root")
	# The button was hidden, so its container may not have laid it out yet. An empty
	# rect would throw the hand and the sheet off screen, so fall back to the row.
	var rect: Rect2 = shop_btn.get_global_rect()
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		var row := shop_btn.get_parent() as Control
		var row_rect: Rect2 = row.get_global_rect() if row else Rect2(24, 1180, 220, 48)
		rect = Rect2(row_rect.position, Vector2(220.0, 48.0))
	_shop_home = shop_btn.get_parent()
	_shop_index = shop_btn.get_index()
	# reparent, not add_child: the button still has a parent, and a failed move used to
	# leave it in the HBox with the panel placed off screen, freezing the paused tree.
	shop_btn.reparent(host, false)
	shop_btn.layout_mode = 0
	shop_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	shop_btn.position = rect.position
	shop_btn.size = rect.size
	_shop_anchor = rect


func _drop_shop_button() -> void:
	if _shop_home == null:
		return
	shop_btn.reparent(_shop_home, false)
	_shop_home.move_child(shop_btn, mini(_shop_index, _shop_home.get_child_count() - 1))
	shop_btn.layout_mode = 2
	shop_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_shop_home = null


func _point_at_shop() -> void:
	var rect: Rect2 = _shop_anchor
	var tip := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y - 8.0)
	if _tap_hand:
		_tap_hand.position = tip - _tap_hand.pivot_offset
	var panel: Control = _tap_reward.get_node("Root/Panel")
	panel.size = Vector2(580, 250)
	# Sit above the button, but never off screen: this sheet is the only way to unpause.
	var top: float = clampf(tip.y - panel.size.y - 140.0, 24.0, 1280.0 - panel.size.y - 24.0)
	panel.position = Vector2(70, top)


func _toggle_auto_tap() -> void:
	if _tap_reward != null and _tap_reward.visible:
		_close_tap_reward()
		return
	if not GameState.auto_tap_unlocked:
		return
	GameState.auto_tap = not GameState.auto_tap
	GameState.save_game()
	_refresh_shop()


func _refresh_shop() -> void:
	shop_btn.visible = GameState.auto_tap_unlocked
	shop_btn.text = tr("AUTO_TAP_ON" if GameState.auto_tap else "AUTO_TAP_OFF")
