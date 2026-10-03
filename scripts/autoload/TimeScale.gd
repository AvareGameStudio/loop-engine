extends Node
## Sole writer of Engine.time_scale. Hitstop always wins over hold slow-mo,
## so no system can cancel another system's freeze-frame.

const HITSTOP_SCALE: float = 0.08

var slowmo: float = 1.0
var _hitstop_left: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _hitstop_left <= 0.0:
		return
	# delta is scaled; hitstop durations are authored in real seconds.
	_hitstop_left -= delta / maxf(Engine.time_scale, 0.001)
	if _hitstop_left <= 0.0:
		_apply()


func hitstop(seconds: float) -> void:
	_hitstop_left = maxf(_hitstop_left, seconds)
	_apply()


func set_slowmo(scale: float) -> void:
	slowmo = clampf(scale, 0.05, 1.0)
	_apply()


## Public name for a timed victory freeze. Hitstop still wins over this value.
func set_time_scale(scale: float) -> void:
	set_slowmo(scale)


func reset() -> void:
	slowmo = 1.0
	_hitstop_left = 0.0
	_apply()


func _apply() -> void:
	Engine.time_scale = HITSTOP_SCALE if _hitstop_left > 0.0 else slowmo
