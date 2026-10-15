extends CanvasLayer
## HUD (door pips, alarm lamps, grade, loot bag) and the end-of-heist card, which
## holds the market / hideout entry points. Fully signal-driven.
## HUD rule: three things on screen during play. Door pips, lamps, bag. No buttons, no labels.

const GRADE_COLORS: Dictionary[String, Color] = {
	"perfect": Color(1.0, 0.86, 0.3),
	"good": Color(0.45, 0.9, 1.0),
	"near_miss": Color(1.0, 0.35, 0.55),
	"miss": Color(0.8, 0.25, 0.3),
}
## Combo label shows from this streak up; below it the grade word is enough.
const COMBO_SHOW_FROM: int = 3
## The new hideout item pops onto the shelf once the card has landed.
const HIDEOUT_ICON := "res://assets/art/hideout_btn.png"
const SHELF_POP_DELAY: float = 0.45

@onready var pips: DoorPips = $HUD/Pips
@onready var lamps: AlarmLamps = $HUD/Lamps
@onready var grade_label: Label = $HUD/Grade
@onready var combo_label: Label = $HUD/Combo
@onready var bag: LootBag = $HUD/Bag
@onready var card: Control = $Card
@onready var card_panel: Control = $Card/Panel
@onready var card_title: Label = $Card/Panel/Margin/VBox/Title
@onready var card_loot: Label = $Card/Panel/Margin/VBox/Loot
@onready var card_ring: QuestRing = $Card/Panel/Margin/VBox/Shelf/Ring
@onready var primary_btn: Button = $Card/Panel/Margin/VBox/Primary
@onready var x3_btn: Button = $Card/Panel/Margin/VBox/X3
@onready var card_market_btn: Button = $Card/Panel/Margin/VBox/Meta/Market
@onready var hideout_btn: Button = $Card/Panel/Margin/VBox/Meta/Hideout
@onready var buy_btn: Button = $Card/Panel/Margin/VBox/Buy
@onready var card_meta: Control = $Card/Panel/Margin/VBox/Meta
@onready var card_city: CityStrip = $Card/Panel/Margin/VBox/City
@onready var daily_btn: Button = $Card/Panel/Margin/VBox/Daily
@onready var settings_btn: Button = $SettingsButton
@onready var settings_popup: SettingsPopup = $SettingsPopup
@onready var market_popup: MarketPopup = $MarketPopup
@onready var hideout_popup: HideoutPopup = $HideoutPopup
@onready var glove_btn: Button = $Card/Panel/Margin/VBox/Meta/Glove

var _grade_tween: Tween
var _combo_tween: Tween
var _loot_tween: Tween
var _x3_key: String = "CARD_X3"
var _run_end_reason: String = ""
var _run_end_stats: Dictionary = {}
var _loot_popped: String = ""
## Market button breathes while an upgrade is affordable.
var _market_pulse: Tween
var _bonus_label: Label
## "HEIST 15" under the door pips: play data said nobody knew which heist they were on.
var _heist_label: Label
## "Next city: Casino Vault · in 3 heists" under the card's city strip.
var _city_label: Label


func _ready() -> void:
	card.visible = false
	grade_label.text = ""
	combo_label.visible = false
	primary_btn.pressed.connect(_primary)
	daily_btn.pressed.connect(_start_daily)
	if ResourceLoader.exists("res://assets/art/daily.png"):
		daily_btn.icon = load("res://assets/art/daily.png")
		daily_btn.add_theme_constant_override("icon_max_width", 48)
	x3_btn.pressed.connect(_x3)
	glove_btn.pressed.connect(_glove_ad)
	card_market_btn.pressed.connect(market_popup.open)
	hideout_btn.pressed.connect(hideout_popup.open)
	buy_btn.pressed.connect(_buy_loot)
	if ResourceLoader.exists(HIDEOUT_ICON):
		hideout_btn.icon = load(HIDEOUT_ICON)
		hideout_btn.add_theme_constant_override("icon_max_width", 34)
	buy_btn.add_theme_constant_override("icon_max_width", 40)
	EventBus.loot_unlocked.connect(func(_id: String) -> void:
		if card.visible:
			_render_buy())
	card_ring.gui_input.connect(_on_shelf_input)
	settings_btn.pressed.connect(settings_popup.open)
	# The theme's nine-slice margins squeezed the gear icon to a dot; the icon is the button.
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		settings_btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	$Card/Dim.gui_input.connect(_on_card_dim)
	EventBus.tap_evaluated.connect(_on_tap)
	EventBus.jackpot.connect(_on_jackpot)
	EventBus.cash_changed.connect(_on_cash)
	EventBus.alarm_changed.connect(_on_alarm)
	EventBus.meta_upgraded.connect(func(_stat: String, _level: int) -> void: _refresh_market())
	EventBus.run_ended.connect(_on_run_end)
	EventBus.run_started.connect(_on_run_start)
	EventBus.stage_cleared.connect(_on_stage)
	EventBus.door_advanced.connect(func(_stage: int) -> void: _refresh_pips())
	EventBus.loot_unlocked.connect(func(id: String) -> void: _loot_popped = id)
	EventBus.ad_finished.connect(_on_ad)
	EventBus.session_changed.connect(_refresh_session)
	EventBus.countdown.connect(_on_countdown)
	EventBus.glove_granted.connect(_on_glove_granted)
	bag.set_cash(GameState.cash, true)
	_refresh_market()
	_refresh_session()
	_refresh_pips()
	lamps.set_level(GameState.session_alarm, GameState.ALARM_MAX)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()


func _refresh_texts() -> void:
	grade_label.text = ""
	_refresh_market()
	_refresh_session()
	if card.visible:
		_render_card()


func _refresh_session() -> void:
	combo_label.visible = false


## Run start and next door only. A crack moves current_stage on before the card,
## so refreshing on session_changed would wipe the gold pop of the last door.
## Doors already cracked this heist sit gold; a bust retries the current door.
func _refresh_pips() -> void:
	_ensure_heist_label()
	if GameState.daily_active:
		pips.set_state(0, 1, true)
		_heist_label.text = tr("CARD_DAILY")
		_heist_label.add_theme_color_override("font_color", GRADE_COLORS.perfect)
		return
	var stage: int = GameState.current_stage
	pips.set_state(GameState.door_in_heist(stage), GameState.DOORS_PER_HEIST, GameState.is_golden(stage))
	_heist_label.text = tr("HUD_HEIST") % GameState.heist_for(stage)
	_heist_label.add_theme_color_override("font_color", GRADE_COLORS.perfect if GameState.is_golden(stage) else Color(1, 1, 1, 0.9))


func _ensure_heist_label() -> void:
	if _heist_label:
		return
	_heist_label = Label.new()
	_heist_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heist_label.add_theme_font_size_override("font_size", 22)
	_heist_label.add_theme_constant_override("outline_size", 8)
	_heist_label.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.1, 1))
	pips.get_parent().add_child(_heist_label)
	_heist_label.anchor_left = 0.5
	_heist_label.anchor_right = 0.5
	_heist_label.offset_left = -160.0
	_heist_label.offset_right = 160.0
	_heist_label.offset_top = pips.offset_bottom + 2.0
	_heist_label.offset_bottom = pips.offset_bottom + 34.0


## Cities change at fixed doors (VAULT_TYPE_BY_STAGE); say where and how far the next one is.
func _render_next_city() -> void:
	if _city_label == null:
		_city_label = Label.new()
		_city_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_city_label.add_theme_font_size_override("font_size", 16)
		_city_label.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0, 1.0))
		card_city.get_parent().add_child(_city_label)
		card_city.get_parent().move_child(_city_label, card_city.get_index() + 1)
	var next_door: int = GameState.current_stage
	var best: int = 0
	for key in GameState.VAULT_TYPE_BY_STAGE.keys():
		if int(key) > next_door and (best == 0 or int(key) < best):
			best = int(key)
	_city_label.visible = best > 0
	if best > 0:
		var heists: int = maxi(GameState.heist_for(best) - GameState.heist_for(next_door), 1)
		var city: String = tr("VAULT_" + String(GameState.VAULT_TYPE_BY_STAGE[best]).to_upper())
		_city_label.text = tr("CARD_NEXT_CITY") % [city, heists]


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


func _on_jackpot(_mult: float, _label: String) -> void:
	pass


func _on_countdown(step: int) -> void:
	if step > 0:
		_show_grade(str(step), Color.WHITE)
	else:
		_show_grade(tr("COUNTDOWN_GO"), GRADE_COLORS.good)


func _on_alarm(level: int, max_level: int) -> void:
	lamps.set_level(level, max_level)


func _on_cash(amount: int, delta: int) -> void:
	bag.set_cash(amount)
	if delta > 0:
		bag.bounce(1.06)
	_refresh_market()


## The hideout's +2%-per-item is invisible unless the card says what it paid this heist.
func _render_bonus_line() -> void:
	if _bonus_label == null:
		_bonus_label = Label.new()
		_bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bonus_label.add_theme_font_size_override("font_size", 17)
		_bonus_label.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0, 1.0))
		card_loot.get_parent().add_child(_bonus_label)
		card_loot.get_parent().move_child(_bonus_label, card_loot.get_index() + 1)
	var run_cash: int = int(_run_end_stats.get("cash", 0))
	var bonus: float = GameState.loot_bonus()
	var extra: int = run_cash - int(round(float(run_cash) / bonus))
	_bonus_label.visible = extra > 0
	if extra > 0:
		_bonus_label.text = tr("CARD_LOOT_BONUS") % [extra, roundi((bonus - 1.0) * 100.0)]


## Play data: $144k banked, 3 of 12 shelf items bought. When the next item is affordable
## the card offers it in one tap, above the Next button.
func _render_buy() -> void:
	var id: String = GameState.next_loot_id()
	buy_btn.visible = GameState.can_buy_loot() and id != ""
	if not buy_btn.visible:
		return
	buy_btn.text = tr("CARD_BUY") % [tr("LOOT_" + id.to_upper()), GameState.next_loot_price(), roundi(GameState.LOOT_BONUS_STEP * 100.0)]
	buy_btn.icon = VaultSprites.loot_icon(id)


## One-tap buy from the card: the item pops into the shelf ring, the bag gives up the cash.
func _buy_loot() -> void:
	var id: String = GameState.buy_next_loot()
	if id == "":
		return
	EventBus.juice_hit.emit("claim", 1.0)
	card_ring.set_icon(VaultSprites.loot_icon(id))
	card_ring.set_state(1.0, true, false)
	card_ring.buyable = false
	card_ring.pop()
	_render_buy()
	# Next item is affordable too: keep the button, re-punch it.
	if buy_btn.visible:
		_punch(buy_btn)


func _punch(target: Control) -> void:
	target.pivot_offset = target.size * 0.5
	target.scale = Vector2(1.12, 1.12)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(target, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Door open: the loot is in the air; the bag catches it half a second later.
func _on_stage(index: int, _payout: int) -> void:
	pips.crack(GameState.door_in_heist(index))
	get_tree().create_timer(0.55, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(bag):
			bag.bounce(1.14)
	)


func _on_run_end(reason: String, stats: Dictionary) -> void:
	_run_end_reason = reason
	_run_end_stats = stats
	grade_label.text = ""
	combo_label.visible = false
	_x3_key = "CARD_X3_AUTO" if GameState.no_ads else "CARD_X3"
	x3_btn.disabled = GameState.no_ads or int(stats.get("cash", 0)) <= 0
	glove_btn.visible = _run_end_reason == "cracked" and GameState.should_offer_glove() and not bool(stats.get("daily", false))
	glove_btn.disabled = false
	if glove_btn.visible:
		var pool: PackedStringArray = GameState.unowned_gloves()
		if not pool.is_empty():
			glove_btn.icon = VaultSprites.cuff_for(pool[0])
			glove_btn.expand_icon = true
			glove_btn.add_theme_constant_override("icon_max_width", 34)
	# The daily Big Heist hands its glove over on the card.
	var daily_glove: String = String(stats.get("daily_glove", ""))
	if daily_glove != "":
		glove_btn.visible = true
		glove_btn.icon = VaultSprites.cuff_for(daily_glove)
		glove_btn.text = ""
		glove_btn.disabled = true
	_render_city(reason, stats)
	card.visible = true
	_render_card()
	_announce_unlock(reason, stats)
	card_panel.scale = Vector2(0.86, 0.86)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(card_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_roll_loot(int(stats.get("cash", 0)))


func _render_card() -> void:
	var cracked: bool = _run_end_reason == "cracked"
	var stage: int = int(_run_end_stats.get("stage", GameState.current_stage))
	if cracked and bool(_run_end_stats.get("daily", false)):
		card_title.text = tr("CARD_DAILY_DONE")
		primary_btn.text = tr("CARD_NEXT")
	elif cracked:
		card_title.text = tr("CARD_CRACKED") % stage
		primary_btn.text = tr("CARD_NEXT")
	else:
		card_title.text = tr("CARD_CAUGHT")
		primary_btn.text = tr("CARD_RETRY")
	card_loot.visible = int(_run_end_stats.get("cash", 0)) > 0
	_render_bonus_line()
	_render_next_city()
	x3_btn.text = tr(_x3_key)
	daily_btn.text = tr("CARD_DAILY")
	daily_btn.visible = GameState.daily_available()
	if not glove_btn.disabled:
		glove_btn.text = tr("CARD_GLOVE_SHORT")
	_render_shelf(cracked)
	_render_buy()


## City strip: the vault the next run plays in. Crossing into a new city pops its icon.
func _render_city(reason: String, stats: Dictionary) -> void:
	var door: int = int(stats.get("door", GameState.current_stage))
	var was: int = CityStrip.index_for(GameState.vault_type(door))
	var next: int = was
	if reason == "cracked" and not bool(stats.get("daily", false)):
		next = CityStrip.index_for(GameState.vault_type(door + 1))
	card_city.set_current(next, next != was)


func _start_daily() -> void:
	if not card.visible or not GameState.daily_available():
		return
	card.visible = false
	var world := get_tree().get_first_node_in_group("game_world")
	if world and world.has_method("start_run"):
		world.start_run(true)


## Hideout shelf, no text: a new item lands in colour with a pop; otherwise the next
## item waits as a dark silhouette inside the unfinished ring.
func _render_shelf(cracked: bool) -> void:
	var next_id: String = GameState.next_loot_id()
	card_ring.buyable = false
	if cracked and _loot_popped != "":
		card_ring.set_icon(VaultSprites.loot_icon(_loot_popped))
		card_ring.set_state(1.0, true, false)
		get_tree().create_timer(SHELF_POP_DELAY, true, false, true).timeout.connect(card_ring.pop)
		return
	if next_id == "":
		card_ring.set_icon(null)
		card_ring.set_state(1.0, true, false)
		return
	card_ring.set_icon(VaultSprites.loot_icon(next_id))
	card_ring.set_state(ZeigarnikTracker.loot_tease(), false, true)
	card_ring.buyable = GameState.can_buy_loot()


func _roll_loot(target: int) -> void:
	if _loot_tween:
		_loot_tween.kill()
	card_loot.text = "+$0"
	if target <= 0:
		return
	_loot_tween = create_tween()
	_loot_tween.set_ignore_time_scale(true)
	var beat: Array[int] = [0]
	_loot_tween.tween_method(func(v: float) -> void:
		card_loot.text = "+$%d" % int(round(v))
		# The bag under the card bumps 8% at every fifth of the roll.
		var fifth: int = int(v / float(target) * 5.0)
		if fifth > beat[0]:
			beat[0] = fifth
			bag.bounce(1.08)
	, 0.0, float(target), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_run_start() -> void:
	card.visible = false
	grade_label.text = ""
	combo_label.visible = false
	glove_btn.visible = false
	_loot_popped = ""
	card_market_btn.remove_theme_color_override("font_color")
	_refresh_session()
	_refresh_pips()


func _on_card_dim(event: InputEvent) -> void:
	# One tap anywhere continues. The card must never feel like a wall.
	if card.visible and event is InputEventMouseButton and event.pressed:
		_primary()
		get_viewport().set_input_as_handled()


func _primary() -> void:
	if not card.visible:
		return
	card.visible = false
	var world := get_tree().get_first_node_in_group("game_world")
	if world and world.has_method("start_run"):
		world.start_run()


func _on_shelf_input(event: InputEvent) -> void:
	if card.visible and event is InputEventMouseButton and event.pressed:
		hideout_popup.open()
		get_viewport().set_input_as_handled()


func _glove_ad() -> void:
	glove_btn.disabled = true
	EventBus.ad_requested.emit("glove_drop", {})


func _on_glove_granted(id: String) -> void:
	glove_btn.text = ""
	glove_btn.icon = VaultSprites.cuff_for(id)
	glove_btn.disabled = true


func _x3() -> void:
	x3_btn.disabled = true
	EventBus.ad_requested.emit("end_multiplier", {})


func _on_ad(placement: String, rewarded: bool) -> void:
	if placement == "end_multiplier":
		x3_btn.disabled = false
		if rewarded:
			_x3_key = "CARD_X3_CLAIMED"
			x3_btn.text = tr(_x3_key)
			x3_btn.disabled = true
			var tripled: int = int(_run_end_stats.get("cash", 0)) * 3
			_run_end_stats["cash"] = tripled
			_roll_loot(tripled)
	elif placement == "glove_drop":
		if rewarded:
			GameState.grant_random_glove()
		else:
			glove_btn.disabled = false


## The card that closes the unlock heist names the new system and bounces its button.
func _announce_unlock(reason: String, stats: Dictionary) -> void:
	if reason != "cracked":
		return
	var heist: int = int(stats.get("stage", 0))
	var target: Button = null
	if heist == GameState.MARKET_UNLOCK_AFTER:
		target = card_market_btn
		card_market_btn.text = tr("HUD_MARKET_NEW")
	elif heist == GameState.CREW_UNLOCK_AFTER:
		# The Crew is hired in the Market and steals from the next time the app closes.
		target = card_market_btn
		card_market_btn.text = tr("HUD_CREW_NEW")
	if target == null:
		return
	target.add_theme_color_override("font_color", GRADE_COLORS.perfect)
	_refresh_meta_row()
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	# Wait for the card pop and the first layout pass, so the pivot sits on the real size.
	tw.tween_interval(0.25)
	tw.tween_callback(func() -> void:
		target.pivot_offset = target.size * 0.5
		target.scale = Vector2(1.3, 1.3)
	)
	tw.tween_property(target, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Glove, Market and Hideout share one row on the card. The hideout is always there.
func _refresh_meta_row() -> void:
	card_market_btn.visible = GameState.market_unlocked()
	hideout_btn.text = tr("HUD_HIDEOUT")
	card_meta.visible = true


## Market buttons advertise how many upgrades are affordable right now.
func _refresh_market() -> void:
	var affordable: int = MetaUpgrade.affordable_count()
	var text: String = tr("HUD_MARKET_COUNT") % affordable if affordable > 0 else tr("HUD_MARKET")
	card_market_btn.text = text
	_refresh_meta_row()
	_pulse_market(affordable > 0 and card_market_btn.visible)


## 1.0 -> 1.06 breathing while an upgrade is affordable, so the card says "spend here".
func _pulse_market(on: bool) -> void:
	if on == (_market_pulse != null):
		return
	if _market_pulse:
		_market_pulse.kill()
		_market_pulse = null
		card_market_btn.scale = Vector2.ONE
		return
	card_market_btn.pivot_offset = card_market_btn.size * 0.5
	_market_pulse = create_tween().set_loops()
	_market_pulse.set_ignore_time_scale(true)
	_market_pulse.tween_callback(func() -> void: card_market_btn.pivot_offset = card_market_btn.size * 0.5)
	_market_pulse.tween_property(card_market_btn, "scale", Vector2(1.06, 1.06), 0.45).set_trans(Tween.TRANS_SINE)
	_market_pulse.tween_property(card_market_btn, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)
