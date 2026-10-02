extends Node
## Procedural one-shots so the prototype ships without audio files.

var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	EventBus.tap_evaluated.connect(_on_tap)
	EventBus.jackpot.connect(func(_m: float, _l: String) -> void: play_tone(880.0, 0.22, 0.35))
	EventBus.near_miss.connect(func(_r: Dictionary) -> void: play_tone(140.0, 0.28, 0.4))
	EventBus.stage_cleared.connect(func(_i: int, _p: int) -> void: play_tone(523.25, 0.18, 0.3))
	EventBus.run_started.connect(func() -> void: play_tone(392.0, 0.12, 0.2))


func _on_tap(result: Dictionary) -> void:
	match String(result.get("grade_name", "")):
		"perfect":
			play_tone(740.0, 0.09, 0.32)
		"good":
			play_tone(520.0, 0.08, 0.26)
		"miss":
			play_tone(110.0, 0.2, 0.35)


func play_tone(freq: float, seconds: float, volume: float = 0.3) -> void:
	var player := _idle_player()
	if player == null:
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.15
	player.stream = gen
	player.volume_db = linear_to_db(volume)
	player.play()
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var frames := int(seconds * gen.mix_rate)
	for i in frames:
		var t := float(i) / gen.mix_rate
		var env := 1.0 - t / seconds
		var s := sin(TAU * freq * t) * env
		playback.push_frame(Vector2(s, s))


func _idle_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return _players[0]
