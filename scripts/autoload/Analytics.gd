extends Node
## The events a publisher's CPI test reads, built from EventBus and named the way
## GameAnalytics expects (progression + design events). No SDK ships with the repo:
## - if a native `GameAnalytics` singleton is present (its Godot plugin, configured with
##   your game key in the export preset), every event is forwarded to it;
## - otherwise, with `debug_log` on (default in debug builds), events go to user://analytics.jsonl
##   so a test session can be checked by hand.
## Events: heist start/complete/fail (progression), busted, bribe offered/taken, daily heist,
## hideout purchase, glove equip, ad results, session start/end with length.

const LOG_PATH := "user://analytics.jsonl"

var debug_log: bool = OS.is_debug_build()
var _ga: Object = null
var _session_start: int = 0
var _heist_start: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.has_singleton("GameAnalytics"):
		_ga = Engine.get_singleton("GameAnalytics")
	_session_start = Time.get_ticks_msec()
	# Deferred: tools set GameState.no_save right after startup and must not log.
	design.call_deferred("session:start")
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.busted.connect(func() -> void: design("heist:busted", GameState.heist_for(GameState.current_stage)))
	EventBus.revive_offered.connect(func(_r: Dictionary) -> void: design("bribe:offered"))
	EventBus.revive_resolved.connect(func(ok: bool) -> void: design("bribe:taken" if ok else "bribe:declined"))
	EventBus.ad_finished.connect(func(placement: String, rewarded: bool) -> void:
		design("ad:%s:%s" % [placement, "rewarded" if rewarded else "failed"]))
	EventBus.loot_unlocked.connect(func(id: String) -> void:
		if GameState.last_buy_gold:
			design("hideout:gold:" + id, GameState.gold_bought)
		else:
			design("hideout:item:" + id, GameState.loot_unlocked_count()))
	EventBus.cosmetic_equipped.connect(func(id: String) -> void: design("glove:equip:" + id))
	EventBus.hot_hands.connect(func(on: bool) -> void:
		if on:
			design("hot_hands:lit"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		design("session:end", (Time.get_ticks_msec() - _session_start) / 1000.0)


func _on_run_started() -> void:
	_heist_start = Time.get_ticks_msec()
	var label: String = "daily" if GameState.daily_active else "heist_%03d" % GameState.heist_for(GameState.current_stage)
	progression("Start", label)


func _on_run_ended(reason: String, stats: Dictionary) -> void:
	var label: String = "daily" if bool(stats.get("daily", false)) else "heist_%03d" % int(stats.get("stage", 0))
	var secs: float = (Time.get_ticks_msec() - _heist_start) / 1000.0
	progression("Complete" if reason == "cracked" else "Fail", label, int(stats.get("cash", 0)))
	design("heist:seconds", secs)


## GameAnalytics progression event: status is Start / Complete / Fail.
func progression(status: String, label: String, score: int = -1) -> void:
	var data := {"type": "progression", "status": status, "p1": label}
	if score >= 0:
		data["score"] = score
	if _ga and _ga.has_method("add_progression_event"):
		_ga.call("add_progression_event", {"progressionStatus": status, "progression01": label, "score": maxi(score, 0)})
	_log(data)


## GameAnalytics design event, `id` is colon-separated (max 5 parts).
func design(id: String, value: float = 0.0) -> void:
	if _ga and _ga.has_method("add_design_event"):
		_ga.call("add_design_event", {"eventId": id, "value": value})
	_log({"type": "design", "id": id, "value": value})


func _log(data: Dictionary) -> void:
	if not debug_log or GameState.no_save or _is_tool_run():
		return
	data["t"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(data))
	f.close()


## Headless/editor tool scripts (`godot -s ...`) and imports are not play sessions.
func _is_tool_run() -> bool:
	var args := OS.get_cmdline_args()
	return args.has("-s") or args.has("--script") or args.has("--import") or DisplayServer.get_name() == "headless"
