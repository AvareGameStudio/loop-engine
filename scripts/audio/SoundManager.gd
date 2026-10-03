extends Node
## Procedural one-shots, baked once into PCM. Pitch is `pitch_scale` so the
## cache stays a handful of durations at 440 Hz.

const MIX_RATE: int = 22050
const VOICES: int = 8
const ATTACK: float = 0.005
const BASE_FREQ: float = 440.0
const PITCH_STEP: float = 0.08
const PITCH_CAP: float = 1.8

var _players: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _cache: Dictionary[int, AudioStreamWAV] = {}
## Consecutive successful hits. A miss or a new run resets the climb.
var hit_streak: int = 0


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	EventBus.tap_evaluated.connect(_on_tap)
	EventBus.jackpot.connect(_on_jackpot)
	EventBus.near_miss.connect(func(_r: Dictionary) -> void: play_tone(140.0, 0.28, 0.4))
	EventBus.stage_cleared.connect(_on_stage_cleared)
	EventBus.run_started.connect(_on_run_started)
	EventBus.direction_flipped.connect(func(_d: float) -> void: play_tone(300.0, 0.05, 0.15))
	EventBus.countdown.connect(_on_countdown)
	EventBus.juice_hit.connect(_on_juice)


func _on_run_started() -> void:
	hit_streak = 0
	play_tone(392.0, 0.12, 0.2)


func _on_stage_cleared(_index: int, _payout: int) -> void:
	hit_streak = 0
	play_tone(55.0, 0.32, 0.46)
	play_tone(110.0, 0.2, 0.32)
	play_tone(380.0, 0.1, 0.24)


## Successful hits climb: pitch = clamp(1 + streak * 0.08, 1, 1.8). A miss breaks it.
func _on_tap(result: Dictionary) -> void:
	var grade_name: String = String(result.get("grade_name", ""))
	match grade_name:
		"perfect", "good":
			hit_streak += 1
			var pitch: float = clampf(1.0 + float(hit_streak) * PITCH_STEP, 1.0, PITCH_CAP)
			var base_freq: float = 740.0 if grade_name == "perfect" else 520.0
			var volume: float = 0.26
			play_click()
			if grade_name == "perfect":
				var power: float = MetaUpgrade.perfect_power()
				volume = 0.32 * lerpf(1.0, 1.4, clampf((power - 1.0) / 1.5, 0.0, 1.0))
			play_tone(base_freq, 0.09, volume, pitch)
		"near_miss", "miss":
			hit_streak = 0
			if grade_name == "miss":
				play_siren()
			else:
				play_tone(140.0, 0.16, 0.3)


func _on_jackpot(_mult: float, _label: String) -> void:
	# Door-bolt thunk instead of a shriek.
	play_tone(90.0, 0.22, 0.32)
	play_tone(180.0, 0.14, 0.28)


func _on_juice(grade: String, _intensity: float) -> void:
	match grade:
		"combo_break":
			play_tone(196.0, 0.12, 0.26)
			play_tone(147.0, 0.16, 0.22)
		"empty_focus":
			play_tone(90.0, 0.06, 0.2)


func _on_countdown(step: int) -> void:
	if step > 0:
		play_tone(660.0, 0.06, 0.22)
	else:
		play_tone(990.0, 0.1, 0.28)


func play_click() -> void:
	play_tone(78.0, 0.08, 0.38)
	play_tone(150.0, 0.06, 0.28)
	play_tone(1480.0, 0.035, 0.2)


func play_siren() -> void:
	play_tone(640.0, 0.32, 0.38)
	get_tree().create_timer(0.16, true, false, true).timeout.connect(func() -> void: play_tone(920.0, 0.32, 0.34))
	get_tree().create_timer(0.34, true, false, true).timeout.connect(func() -> void: play_tone(640.0, 0.28, 0.3))


func play_tone(freq: float, seconds: float, volume: float = 0.3, pitch_scale: float = 1.0) -> void:
	var player: AudioStreamPlayer = _players[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	player.stream = _get_tone(seconds)
	player.pitch_scale = (freq / BASE_FREQ) * pitch_scale
	player.volume_db = linear_to_db(volume)
	player.play()


func _get_tone(seconds: float) -> AudioStreamWAV:
	var key: int = roundi(seconds * 1000.0)
	if not _cache.has(key):
		_cache[key] = _bake(BASE_FREQ, seconds)
	return _cache[key]


func _bake(freq: float, seconds: float) -> AudioStreamWAV:
	var frames: int = int(seconds * MIX_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t: float = float(i) / MIX_RATE
		var env: float = minf(t / ATTACK, 1.0) * (1.0 - t / seconds)
		data.encode_s16(i * 2, int(sin(TAU * freq * t) * env * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
