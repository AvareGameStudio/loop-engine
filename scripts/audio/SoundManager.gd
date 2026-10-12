extends Node
## Procedural one-shots, baked once into PCM. Pitch is `pitch_scale` so the
## cache stays a handful of durations at 440 Hz.
## Recorded CC0 samples in res://assets/sfx/ (Kenney) replace the key one-shots:
## pin click, door slam, loot landing, miss clunk, cuff click, glass snap. Each name
## has numbered variants (`door_1.ogg`, `door_2.ogg`) picked at random so repeats
## do not drill. A missing file falls back to the old tones.

const MIX_RATE: int = 22050
const VOICES: int = 8
const ATTACK: float = 0.005
const BASE_FREQ: float = 440.0
const PITCH_CAP: float = 1.8
const SFX_DIR := "res://assets/sfx/"
const SFX_NAMES: PackedStringArray = ["pin", "door", "loot", "miss", "cuff", "glass"]
const SFX_MAX_VARIANTS: int = 4
## Juice beats that a sample fully replaces.
const JUICE_SAMPLES: Dictionary[String, String] = {"hot_hands_out": "glass", "cuffed": "cuff"}

var _players: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _cache: Dictionary[int, AudioStreamWAV] = {}
var _samples: Dictionary[String, Array] = {}
var _drone: AudioStreamPlayer
## Each cleared ring lifts the lock pitch so the center feels closer.
var _phase_pitch: float = 1.0
## Hot Hands adds an octave-up layer to every landed hit.
var _hot: bool = false


func _ready() -> void:
	_load_samples()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	EventBus.tap_evaluated.connect(_on_tap)
	EventBus.jackpot.connect(_on_jackpot)
	EventBus.stage_cleared.connect(_on_stage_cleared)
	EventBus.run_started.connect(_on_run_started)
	EventBus.direction_flipped.connect(_on_flip)
	EventBus.countdown.connect(_on_countdown)
	EventBus.juice_hit.connect(_on_juice)
	EventBus.alarm_changed.connect(_on_alarm)
	EventBus.loot_unlocked.connect(func(_id: String) -> void: _play_fanfare())
	EventBus.approach_changed.connect(_on_approach)
	EventBus.gold_pin_armed.connect(_on_gold_armed)
	EventBus.hot_hands.connect(func(on: bool) -> void: _hot = on)
	_drone = AudioStreamPlayer.new()
	_drone.stream = _bake_loop(180.0, 0.25)
	_drone.volume_db = linear_to_db(0.07)
	add_child(_drone)


func _on_run_started() -> void:
	# Pitch climbs with the pins inside one vault, not across the whole career.
	_phase_pitch = 1.0
	_stop_drone()
	play_tone(392.0, 0.12, 0.2)


func _on_flip(_d: float) -> void:
	play_tone(220.0, 0.06, 0.22)
	play_tone(340.0, 0.05, 0.16)


func _on_gold_armed(armed: bool) -> void:
	if armed:
		play_tone(880.0, 0.08, 0.18)


func _on_approach(hot: bool, closeness: float) -> void:
	if _drone == null:
		return
	if not hot:
		_stop_drone()
		return
	_drone.pitch_scale = lerpf(0.8, 1.25, clampf(closeness, 0.0, 1.0))
	if not _drone.playing:
		_drone.play()


func _stop_drone() -> void:
	if _drone and _drone.playing:
		_drone.stop()


## Door "ka-chunk", then the cash-register "cha-ching" 200 ms later when the loot lands.
func _on_stage_cleared(_index: int, _payout: int) -> void:
	if play_sample("door", 0.8):
		# The bell tones stay: they are the "cha-ching" sparkle on top of the chips.
		play_tone(55.0, 0.32, 0.3)
		get_tree().create_timer(0.2, true, false, true).timeout.connect(func() -> void:
			play_sample("loot", 0.75)
			play_tone(1760.0, 0.06, 0.14)
			play_tone(2640.0, 0.12, 0.1)
		)
		return
	play_tone(55.0, 0.32, 0.46)
	play_tone(110.0, 0.2, 0.32)
	play_tone(380.0, 0.1, 0.24)
	get_tree().create_timer(0.2, true, false, true).timeout.connect(func() -> void:
		play_tone(1760.0, 0.06, 0.2)
		play_tone(2640.0, 0.12, 0.16)
		play_tone(1320.0, 0.18, 0.18)
	)


func _play_fanfare() -> void:
	for i in 4:
		var freq: float = [523.0, 659.0, 784.0, 1046.0][i]
		get_tree().create_timer(0.45 + 0.09 * float(i), true, false, true).timeout.connect(func() -> void:
			play_tone(freq, 0.16, 0.22)
		)


## Strikes: a low clunk per lamp, the full siren on the third.
func _on_alarm(level: int, max_level: int) -> void:
	if level <= 0:
		return
	if level >= max_level:
		play_siren()
		return
	play_tone(110.0, 0.14, 0.3)


## Pitch comes from TimingEngine so the combo counter and the melody stay on one ladder.
func _on_tap(result: Dictionary) -> void:
	_stop_drone()
	var grade_name: String = String(result.get("grade_name", ""))
	match grade_name:
		"perfect", "good":
			var pitch: float = clampf(float(result.get("pitch", 1.0)) * _phase_pitch, 1.0, PITCH_CAP)
			var base_freq: float = 740.0 if grade_name == "perfect" else 520.0
			var volume: float = 0.26
			play_click()
			if grade_name == "perfect":
				var power: float = MetaUpgrade.perfect_power()
				volume = 0.32 * lerpf(1.0, 1.4, clampf((power - 1.0) / 1.5, 0.0, 1.0))
			play_tone(base_freq, 0.09, volume, pitch)
			if _hot:
				play_tone(base_freq * 2.0, 0.07, volume * 0.45, pitch)
		"near_miss":
			# Siren pitch sliding down: 1.0 → 0.7 across 400 ms.
			for i in 4:
				var pitch: float = lerpf(1.0, 0.7, float(i) / 3.0)
				get_tree().create_timer(0.1 * float(i), true, false, true).timeout.connect(func() -> void:
					play_tone(640.0, 0.12, 0.3, pitch)
				)
		"miss":
			if play_sample("miss", 0.7):
				return
			play_tone(140.0, 0.16, 0.3)
			play_tone(95.0, 0.2, 0.26)


func _on_jackpot(_mult: float, _label: String) -> void:
	# Door-bolt thunk instead of a shriek.
	play_tone(90.0, 0.22, 0.32)
	play_tone(180.0, 0.14, 0.28)


func _on_juice(grade: String, _intensity: float) -> void:
	if JUICE_SAMPLES.has(grade) and play_sample(JUICE_SAMPLES[grade], 0.85):
		return
	match grade:
		"hot_hands":
			# Fast rising arpeggio: the run just caught fire.
			for i in 5:
				var freq: float = [523.0, 659.0, 784.0, 1046.0, 1318.0][i]
				get_tree().create_timer(0.04 * float(i), true, false, true).timeout.connect(func() -> void:
					play_tone(freq, 0.09, 0.22)
				)
		"hot_hands_out":
			# Glass break: three bright, very short shards.
			play_tone(3100.0, 0.03, 0.18)
			play_tone(2350.0, 0.05, 0.16)
			play_tone(1780.0, 0.08, 0.14)
		"cuffed":
			# Ratchet then a hard metal click with a low thunk under it.
			play_tone(3900.0, 0.02, 0.22)
			play_tone(2600.0, 0.04, 0.3)
			play_tone(180.0, 0.1, 0.34)
		"combo_break":
			play_tone(196.0, 0.12, 0.26)
			play_tone(147.0, 0.16, 0.22)


func _on_countdown(step: int) -> void:
	if step > 0:
		play_tone(660.0, 0.06, 0.22)
	else:
		play_tone(990.0, 0.1, 0.28)


func play_click() -> void:
	# The tick climbs with the pins like the old tone did; the low thump stays as body.
	if play_sample("pin", 0.9, _phase_pitch):
		play_tone(78.0, 0.08, 0.3, _phase_pitch)
		return
	play_tone(78.0, 0.08, 0.38, _phase_pitch)
	play_tone(150.0, 0.06, 0.28, _phase_pitch)
	play_tone(1480.0, 0.035, 0.2, _phase_pitch)


func play_siren() -> void:
	play_tone(640.0, 0.32, 0.38)
	get_tree().create_timer(0.16, true, false, true).timeout.connect(func() -> void: play_tone(920.0, 0.32, 0.34))
	get_tree().create_timer(0.34, true, false, true).timeout.connect(func() -> void: play_tone(640.0, 0.28, 0.3))


## Plays a random variant of a recorded sample. False when none was loaded.
func play_sample(sample: String, volume: float = 0.8, pitch_scale: float = 1.0) -> bool:
	var variants: Array = _samples.get(sample, [])
	if variants.is_empty():
		return false
	var player: AudioStreamPlayer = _players[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	player.stream = variants[randi() % variants.size()]
	# ±4% random detune on top, so two identical hits never sound copy-pasted.
	player.pitch_scale = pitch_scale * randf_range(0.96, 1.04)
	player.volume_db = linear_to_db(volume)
	player.play()
	return true


func _load_samples() -> void:
	for sample: String in SFX_NAMES:
		var variants: Array = []
		for i in range(1, SFX_MAX_VARIANTS + 1):
			var path: String = "%s%s_%d.ogg" % [SFX_DIR, sample, i]
			if ResourceLoader.exists(path):
				variants.append(load(path))
		if not variants.is_empty():
			_samples[sample] = variants


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


func _bake_loop(freq: float, seconds: float) -> AudioStreamWAV:
	var wav := _bake(freq, seconds)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = int(seconds * MIX_RATE)
	return wav


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
