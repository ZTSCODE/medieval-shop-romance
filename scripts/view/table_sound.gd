class_name TableSound
extends Node

const SAMPLE_RATE := 22050
const PLAYER_COUNT := 4

var enabled: bool = true:
	set(value):
		enabled = value
		if not value:
			for player in _players:
				player.stop()

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _last_played: Dictionary = {}
var _cursor: int = 0
var _sequence: int = 0


func _ready() -> void:
	for index in range(PLAYER_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "CardCue%d" % (index + 1)
		player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		player.volume_db = -8.0
		add_child(player)
		_players.append(player)
	for kind in [&"grab", &"drop", &"stack", &"split", &"add"]:
		_streams[kind] = _make_cue(kind)


func play_cue(kind: StringName) -> void:
	if not enabled or _players.is_empty():
		return
	var cue := kind
	match cue:
		&"pick", &"pickup", &"lift", &"take":
			cue = &"grab"
		&"land", &"release":
			cue = &"drop"
		&"reset", &"clear", &"remove":
			cue = &"split"
	if not _streams.has(cue):
		cue = &"drop"
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(cue, -1000)) < 24:
		return
	_last_played[cue] = now
	var player := _players[_cursor]
	for candidate in _players:
		if not candidate.playing:
			player = candidate
			break
	_cursor = (_cursor + 1) % PLAYER_COUNT
	_sequence += 1
	player.stream = _streams[cue] as AudioStreamWAV
	player.pitch_scale = 1.0 + float((_sequence % 5) - 2) * 0.008
	player.play()


static func _make_cue(kind: StringName) -> AudioStreamWAV:
	var duration := 0.055
	var pitch := 190.0
	var tone_gain := 0.12
	var noise_gain := 0.023
	var release_rate := 76.0
	match kind:
		&"grab":
			duration = 0.032
			pitch = 670.0
			tone_gain = 0.034
			noise_gain = 0.067
			release_rate = 115.0
		&"stack":
			duration = 0.070
			pitch = 240.0
			tone_gain = 0.14
			noise_gain = 0.030
			release_rate = 67.0
		&"split":
			duration = 0.038
			pitch = 840.0
			tone_gain = 0.025
			noise_gain = 0.048
			release_rate = 100.0
		&"add":
			duration = 0.056
			pitch = 420.0
			tone_gain = 0.083
			noise_gain = 0.018
			release_rate = 85.0
	var random := RandomNumberGenerator.new()
	random.seed = hash(kind)
	var sample_count := int(ceil(duration * SAMPLE_RATE))
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	var previous_noise := 0.0
	for index in range(sample_count):
		var time := float(index) / SAMPLE_RATE
		var noise := random.randf_range(-1.0, 1.0)
		var paper_noise := noise - previous_noise * 0.7
		previous_noise = noise
		var envelope := (1.0 - exp(-time * 1700.0)) * exp(-time * release_rate)
		envelope *= 1.0 - smoothstep(duration * 0.78, duration, time)
		var phase := TAU * pitch * (time - time * time * 1.3)
		var sample := (sin(phase) * tone_gain + paper_noise * noise_gain) * envelope
		pcm.encode_s16(index * 2, clampi(int(round(sample * 32767.0)), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = pcm
	return stream
