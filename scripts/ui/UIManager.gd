extends CanvasLayer
## HUD (door pips, alarm lamps, grade, loot bag) and the end-of-heist card, which
## holds the market / stash entry points. Fully signal-driven.
## HUD rule: three things on screen during play. Door pips, lamps, bag. No buttons, no labels.

const GRADE_COLORS: Dictionary[String, Color] = {
	"perfect": Color(1.0, 0.86, 0.3),
	"good": Color(0.45, 0.9, 1.0),
	"near_miss": Color(1.0, 0.35, 0.55),
	"miss": Color(0.8, 0.25, 0.3),
}
## Combo label shows from this streak up; below it the grade word is enough.
const COMBO_SHOW_FROM: int = 3

@onready var pips: DoorPips = $HUD/Pips
@onready var lamps: AlarmLamps = $HUD/Lamps
@onready var grade_label: Label = $HUD/Grade
@onready var combo_label: Label = $HUD/Combo
@onready var bag: LootBag = $HUD/Bag
@onready var card: Control = $Card
@onready var card_panel: Control = $Card/Panel
@onready var card_title: Label = $Card/Panel/Margin/VBox/Title
@onready var card_subtitle: Label = $Card/Panel/Margin/VBox/Subtitle
@onready var card_loot: Label = $Card/Panel/Margin/VBox/Loot
@onready var card_ring: QuestRing = $Card/Panel/Margin/VBox/Shelf/Ring
@onready var card_shelf_text: Label = $Card/Panel/Margin/VBox/Shelf/ShelfText
@onready var primary_btn: Button = $Card/Panel/Margin/VBox/Primary
@onready var x3_btn: Button = $Card/Panel/Margin/VBox/X3
@onready var card_market_btn: Button = $Card/Panel/Margin/VBox/Meta/Market
@onready var stash_btn: Button = $Card/Panel/Margin/VBox/Meta/Stash
@onready var settings_btn: Button = $SettingsButton
@onready var settings_popup: SettingsPopup = $SettingsPopup
@onready var market_popup: MarketPopup = $MarketPopup
@onready var claim_popup: ClaimPopup = $ClaimPopup
@onready var hideout_popup: HideoutPopup = $HideoutPopup
@onready var glove_btn: Button = $Card/Panel/Margin/VBox/Glove

var _grade_tween: Tween
var _combo_tween: Tween
var _loot_tween: Tween
var _x3_key: String = "CARD_X3"
var _run_end_reason: String = ""
var _run_end_stats: Dictionary = {}
var _loot_popped: String = ""


func _ready() -> void:
	card.visible = false
	grade_label.text = ""
	combo_label.visible = false
	primary_btn.pressed.connect(_primary)
	x3_btn.pressed.connect(_x3)
	glove_btn.pressed.connect(_glove_ad)
	card_market_btn.pressed.connect(market_popup.open)
	stash_btn.pressed.connect(_open_stash)
	card_shelf_text.gui_input.connect(_on_shelf_input)
	card_ring.gui_input.connect(_on_shelf_input)
	settings_btn.pressed.connect(settings_popup.open)
	$Card/Dim.gui_input.connect(_on_card_dim)
	EventBus.tap_evaluated.connect(_on_tap)
	EventBus.jackpot.connect(_on_jackpot)
	EventBus.cash_changed.connect(_on_cash)
	EventBus.stash_changed.connect(_on_stash)
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
	EventBus.stash_ready.connect(_on_stash_ready)
	EventBus.glove_granted.connect(_on_glove_granted)
	bag.set_cash(GameState.cash, true)
	_refresh_market()
	_refresh_session()
	_refresh_pips()
	_refresh_stash()
	lamps.set_level(GameState.session_alarm, GameState.ALARM_MAX)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()


func _refresh_texts() -> void:
	grade_label.text = ""
	_refresh_market()
	_refresh_session()
	_refresh_stash()
	if card.visible:
		_render_card()


func _refresh_session() -> void:
	combo_label.visible = false


## Run start and next door only. A crack moves current_stage on before the card,
## so refreshing on session_changed would wipe the gold pop of the last door.
## Doors already cracked this heist sit gold; a bust retries the current door.
func _refresh_pips() -> void:
	var stage: int = GameState.current_stage
	pips.set_state(GameState.door_in_heist(stage), GameState.DOORS_PER_HEIST, GameState.is_golden(stage))


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


func _on_stash(_amount: int, _delta: int) -> void:
	_refresh_stash()


func _refresh_stash() -> void:
	var n: int = GameState.unclaimed_cash
	stash_btn.visible = n > 0
	if n > 0:
		stash_btn.text = tr("HUD_STASH") % n
		stash_btn.pivot_offset = stash_btn.size * 0.5


func _on_stash_ready(_amount: int) -> void:
	_refresh_stash()
	if not stash_btn.visible:
		return
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	stash_btn.scale = Vector2(1.12, 1.12)
	tw.tween_property(stash_btn, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK)


func _open_stash() -> void:
	if GameState.unclaimed_cash <= 0:
		return
	claim_popup.open(GameState.unclaimed_cash, true)


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
	glove_btn.visible = _run_end_reason == "cracked" and GameState.should_offer_glove()
	glove_btn.disabled = false
	if glove_btn.visible:
		var pool: PackedStringArray = GameState.unowned_gloves()
		if not pool.is_empty():
			glove_btn.icon = VaultSprites.cuff_for(pool[0])
			glove_btn.expand_icon = true
			glove_btn.add_theme_constant_override("icon_max_width", 40)
	card.visible = true
	_render_card()
	card_panel.scale = Vector2(0.86, 0.86)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(card_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_roll_loot(int(stats.get("cash", 0)))
	_refresh_stash()


func _render_card() -> void:
	var cracked: bool = _run_end_reason == "cracked"
	var stage: int = int(_run_end_stats.get("stage", GameState.current_stage))
	if cracked:
		card_title.text = tr("CARD_CRACKED") % stage
		var door: int = int(_run_end_stats.get("door", GameState.current_stage - 1))
		var kind_key: String = "VAULT_GOLDEN" if GameState.is_golden(door) else "VAULT_" + GameState.vault_type(door).to_upper()
		card_subtitle.text = tr(kind_key)
		primary_btn.text = tr("CARD_NEXT")
	else:
		card_title.text = tr("CARD_CAUGHT")
		card_subtitle.text = tr("CARD_RETRY_SUB") % stage
		primary_btn.text = tr("CARD_RETRY")
	card_loot.visible = int(_run_end_stats.get("cash", 0)) > 0
	x3_btn.text = tr(_x3_key)
	glove_btn.text = tr("CARD_GLOVE")
	_render_shelf(cracked)


## Hideout shelf: a new item when the vault just completed one, otherwise the unfinished ring.
func _render_shelf(cracked: bool) -> void:
	var next_id: String = GameState.next_loot_id()
	if cracked and _loot_popped != "":
		card_ring.set_state(1.0, true, false)
		card_shelf_text.text = tr("CARD_NEW_LOOT") % tr("LOOT_" + _loot_popped.to_upper())
		return
	if next_id == "":
		card_ring.set_state(1.0, true, false)
		card_shelf_text.text = tr("CARD_SHELF_FULL")
		return
	card_ring.set_state(ZeigarnikTracker.loot_tease(), false, true)
	var step: Vector2i = GameState.loot_step()
	card_shelf_text.text = tr("CARD_NEXT_LOOT") % [tr("LOOT_" + next_id.to_upper()), step.x, step.y]


func _roll_loot(target: int) -> void:
	if _loot_tween:
		_loot_tween.kill()
	card_loot.text = "+$0"
	if target <= 0:
		return
	_loot_tween = create_tween()
	_loot_tween.set_ignore_time_scale(true)
	_loot_tween.tween_method(func(v: float) -> void:
		card_loot.text = "+$%d" % int(round(v))
	, 0.0, float(target), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_run_start() -> void:
	card.visible = false
	grade_label.text = ""
	combo_label.visible = false
	glove_btn.visible = false
	_loot_popped = ""
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
	glove_btn.text = tr("CARD_GLOVE_GOT") % tr("GLOVE_" + id.to_upper())
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


## Market buttons advertise how many upgrades are affordable right now.
func _refresh_market() -> void:
	var affordable: int = MetaUpgrade.affordable_count()
	var text: String = tr("HUD_MARKET_COUNT") % affordable if affordable > 0 else tr("HUD_MARKET")
	card_market_btn.text = text
