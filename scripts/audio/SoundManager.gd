extends Node
## Procedural one-shots, baked once into PCM so nothing is synthesized at hit time.

const MIX_RATE: int = 22050
const VOICES: int = 6
const ATTACK: float = 0.005

var _players: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _cache: Dictionary[Vector2i, AudioStreamWAV] = {}
const PITCH_STEP: float = 0.08
const PITCH_CAP: float = 1.8
## Consecutive successful hits. A miss or a new run resets the climb.
var hit_streak: int = 0


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	EventBus.tap_evaluated.connect(_on_tap)
	EventBus.jackpot.connect(func(_m: float, _l: String) -> void: play_tone(880.0, 0.22, 0.35))
	EventBus.near_miss.connect(func(_r: Dictionary) -> void: play_tone(140.0, 0.28, 0.4))
	EventBus.stage_cleared.connect(_on_stage_cleared)
	EventBus.run_started.connect(_on_run_started)
	EventBus.direction_flipped.connect(func(_d: float) -> void: play_tone(300.0, 0.05, 0.15))
	EventBus.countdown.connect(_on_countdown)


func _on_run_started() -> void:
	hit_streak = 0
	play_tone(392.0, 0.12, 0.2)


func _on_stage_cleared(_index: int, _payout: int) -> void:
	hit_streak = 0
	play_tone(523.25, 0.18, 0.3)


## Successful hits climb: pitch = clamp(1 + streak * 0.08, 1, 1.8). A miss breaks it.
func _on_tap(result: Dictionary) -> void:
	var grade_name: String = String(result.get("grade_name", ""))
	match grade_name:
		"perfect", "good":
			hit_streak += 1
			var base_pitch: float = 1.0
			var step: float = PITCH_STEP
			var max_pitch: float = PITCH_CAP
			var pitch: float = clampf(base_pitch + float(hit_streak) * step, base_pitch, max_pitch)
			var base_freq: float = 740.0 if grade_name == "perfect" else 520.0
			var volume: float = 0.26
			if grade_name == "perfect":
				var power: float = MetaUpgrade.perfect_power()
				volume = 0.32 * lerpf(1.0, 1.4, clampf((power - 1.0) / 1.5, 0.0, 1.0))
			play_tone(base_freq, 0.09, volume, pitch)
		"near_miss", "miss":
			hit_streak = 0
			if grade_name == "miss":
				play_tone(110.0, 0.2, 0.35)


func _on_countdown(step: int) -> void:
	if step > 0:
		play_tone(660.0, 0.06, 0.22)
	else:
		play_tone(990.0, 0.1, 0.28)


func play_tone(freq: float, seconds: float, volume: float = 0.3, pitch_scale: float = 1.0) -> void:
	var player: AudioStreamPlayer = _players[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	player.stream = _get_tone(freq, seconds)
	player.pitch_scale = pitch_scale
	player.volume_db = linear_to_db(volume)
	player.play()


func _get_tone(freq: float, seconds: float) -> AudioStreamWAV:
	var key := Vector2i(roundi(freq * 100.0), roundi(seconds * 1000.0))
	if not _cache.has(key):
		_cache[key] = _bake(freq, seconds)
	return _cache[key]


func _bake(freq: float, seconds: float) -> AudioStreamWAV:
	var frames: int = int(seconds * MIX_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t: float = float(i) / MIX_RATE
		# Short attack avoids the click a hard 0→1 onset produces.
		var env: float = minf(t / ATTACK, 1.0) * (1.0 - t / seconds)
		data.encode_s16(i * 2, int(sin(TAU * freq * t) * env * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
