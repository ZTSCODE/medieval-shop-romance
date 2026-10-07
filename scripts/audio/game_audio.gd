extends Node
## Single presentation-only entry point. Event data lives in audio_catalog.json.
## No gameplay RNG, model mutations, or save-format dependencies.
signal event_played(event_id: String, record: Dictionary)

const CATALOG_PATH := "res://assets/audio/audio_catalog.json"
const POOL_SIZE := 24
const TRACE_LIMIT := 256
var catalog: Dictionary = {}
var trace: Array[Dictionary] = []
var enabled := true
var world_suspended := true
var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _last_played: Dictionary = {}
var _sequence: Dictionary = {}
var _layers: Dictionary = {}
var _layer_events: Dictionary = {}
var _layer_tweens: Dictionary = {}
var _menu := true
var _paused := false
var _reading := false
var _night := false
var _cinematic := false
var _cinematic_native := false
var _duck := 1.0
var _initialized_context := false
var narrative: Node
var _narrative_active := false
var _narrative_environment := ""
var _narrative_music := ""
var _movement_event := ""
var _last_ui_action_frame := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if parsed is Dictionary:
		catalog = parsed.get("events", {})
	for index in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "AudioVoice%02d" % index
		add_child(player)
		_players.append(player)
	for layer: String in ["music", "ambience", "movement"]:
		var pair: Array[AudioStreamPlayer] = []
		for index in 2:
			var player := AudioStreamPlayer.new()
			player.name = layer.capitalize() + str(index)
			add_child(player)
			pair.append(player)
		_layers[layer] = pair
		_layer_events[layer] = ""
	narrative = preload("res://scripts/audio/narrative_audio_director.gd").new()
	narrative.name = "NarrativeDirector"
	add_child(narrative)
	get_tree().node_added.connect(_schedule_ui_binding)
	_bind_tree.call_deferred(get_tree().root)
	if "--audio-trace" in OS.get_cmdline_user_args():
		event_played.connect(func(_id: String, record: Dictionary): print("AUDIO_EVENT ", JSON.stringify(record)))

func _ensure_buses() -> void:
	# Keep parent buses to the right of their sends. Settings owns only their gain.
	var routes := {"Music": "Master", "SFX": "Master", "MusicMix": "Music", "Cinematic": "Music", "UI": "SFX", "Cards": "SFX", "World": "SFX", "Narrative": "SFX", "Ambience": "SFX", "AmbienceMix": "Ambience"}
	for bus_name: String in routes:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
		AudioServer.set_bus_send(AudioServer.get_bus_index(bus_name), routes[bus_name])
	# One gentle final safety limiter; source trims provide the actual balance.
	if AudioServer.get_bus_effect_count(0) == 0:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -0.6
		AudioServer.add_bus_effect(0, limiter)

func play_event(event_id: String, context: Dictionary = {}) -> bool:
	if not enabled or not catalog.has(event_id):
		return false
	var spec: Dictionary = catalog[event_id]
	if bool(spec.get("loop", false)):
		return false # Only set_context owns persistent layers.
	if world_suspended and String(spec.get("bus", "UI")) in ["Cards", "World"] and not context.get("allow_paused", false):
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(event_id, -100000)) < int(spec.get("cooldown_ms", 60)):
		return false
	var active := 0
	for candidate in _players:
		if candidate.playing and candidate.get_meta("event_id", "") == event_id:
			active += 1
	if active >= int(spec.get("max_voices", 3)):
		return false
	var files: Array = spec.get("files", [])
	if files.is_empty():
		return false
	var sequence := int(_sequence.get(event_id, 0))
	var file := String(files[sequence % files.size()])
	var stream := _stream(file, false)
	if stream == null:
		return false
	var player: AudioStreamPlayer
	for candidate in _players:
		if not candidate.playing:
			player = candidate
			break
	# Drop a low-priority new sound rather than cutting an audible existing sound.
	if player == null:
		return false
	_sequence[event_id] = sequence + 1
	_last_played[event_id] = now
	var category_bus := String(spec.get("bus", "SFX"))
	player.set_meta("category_bus", category_bus)
	player.bus = category_bus
	if category_bus == "Narrative":
		var voice_bus := "NarrativeVoice%02d" % _players.find(player)
		var index := AudioServer.get_bus_index(voice_bus)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, voice_bus)
			AudioServer.set_bus_send(index, "Narrative")
			AudioServer.add_bus_effect(index, AudioEffectPanner.new())
		var panner := AudioServer.get_bus_effect(index, 0) as AudioEffectPanner
		panner.pan = clampf(float(context.get("pan", spec.get("pan", 0.0))), -1.0, 1.0)
		player.bus = voice_bus
	player.stream_paused = false
	player.stream = stream
	player.volume_db = float(spec.get("gain_db", -12.0)) + clampf(float(context.get("gain_offset_db", 0.0)), -24.0, 6.0)
	var pitch_range: Array = spec.get("pitch", [1.0, 1.0])
	var pitch := lerpf(float(pitch_range[0]), float(pitch_range[1]), float((sequence * 3 + 2) % 7) / 6.0)
	player.pitch_scale = pitch
	player.set_meta("event_id", event_id)
	player.set_meta("sequence", sequence)
	player.play()
	if category_bus == "UI" and event_id != "ui.hover":
		_last_ui_action_frame = Engine.get_process_frames()
	_record(event_id, {"file": file, "bus": category_bus, "voice_bus": player.bus, "pan": context.get("pan", spec.get("pan", 0.0)), "gain_db": player.volume_db, "pitch": pitch, "sequence": sequence, "context": context})
	return true

func _stream(path: String, looped: bool) -> AudioStream:
	var key := path + (":loop" if looped else ":once")
	if _streams.has(key):
		return _streams[key]
	if not ResourceLoader.exists(path):
		push_warning("Audio asset missing: " + path)
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		return null
	stream = stream.duplicate()
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = looped
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if looped else AudioStreamWAV.LOOP_DISABLED
		if looped:
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_streams[key] = stream
	return stream

func set_context(at_menu: bool, menu_paused: bool, reading: bool, day_progress: float = 0.0) -> void:
	var next_night := day_progress >= 0.72
	var changed := not _initialized_context or [_menu, _paused, _reading, _night] != [at_menu, menu_paused, reading, next_night]
	_menu = at_menu
	_paused = menu_paused
	_reading = reading
	_night = next_night
	world_suspended = _menu or _paused or _reading or _cinematic
	if changed:
		_initialized_context = true
		_refresh_layers()
		if world_suspended:
			for player in _players:
				if player.get_meta("category_bus", "") in ["Cards", "World"]:
					player.stop()

func set_cinematic(active: bool, native_audio: bool = false) -> void:
	if _cinematic == active and _cinematic_native == native_audio:
		return
	_cinematic = active
	_cinematic_native = native_audio
	world_suspended = _menu or _paused or _reading or _cinematic
	_refresh_layers()

func _refresh_layers() -> void:
	var music := "music.menu" if _menu else ("" if _reading else ("music.night" if _night else "music.day"))
	var ambience := "ambience.night" if _night or _menu else "ambience.day"
	if _reading:
		ambience = "ambience.snowline"
	if _narrative_active and not _menu:
		music = _narrative_music
		ambience = _narrative_environment
	if _cinematic:
		music = "" if _cinematic_native else "music.story"
		ambience = ""
	_crossfade("music", music, 1.8)
	_crossfade("ambience", ambience, 2.5)
	_crossfade("movement", "" if world_suspended else _movement_event, 0.25)

func _crossfade(layer: String, event_id: String, seconds: float) -> void:
	if _layer_events.get(layer, "") == event_id:
		return
	_layer_events[layer] = event_id
	if _layer_tweens.has(layer) and is_instance_valid(_layer_tweens[layer]):
		_layer_tweens[layer].kill()
	var pair: Array = _layers[layer]
	var incoming: AudioStreamPlayer = pair[0] if pair[0].volume_linear < pair[1].volume_linear else pair[1]
	# Prefer the already playing target during a rapidly reversed transition.
	for candidate: AudioStreamPlayer in pair:
		if candidate.playing and candidate.get_meta("event_id", "") == event_id:
			incoming = candidate
	var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_layer_tweens[layer] = tween
	for player: AudioStreamPlayer in pair:
		if player != incoming or event_id.is_empty():
			tween.tween_property(player, "volume_linear", 0.0, seconds)
			tween.tween_callback(player.stop).set_delay(seconds)
	if event_id.is_empty() or not catalog.has(event_id):
		return
	var spec: Dictionary = catalog[event_id]
	if incoming.get_meta("event_id", "") != event_id or not incoming.playing:
		incoming.stop()
		incoming.stream = _stream(String(spec.files[0]), true)
		incoming.bus = spec.bus
		incoming.volume_linear = 0.0
		incoming.set_meta("event_id", event_id)
		if incoming.stream != null:
			incoming.play()
			_record(event_id, {"file": spec.files[0], "layer": layer, "crossfade_seconds": seconds})
	tween.tween_property(incoming, "volume_linear", db_to_linear(float(spec.gain_db)), seconds)

func _process(delta: float) -> void:
	for player in _players:
		if player.get_meta("category_bus", "") == "Narrative":
			player.stream_paused = _paused or _menu or _cinematic
	var target := 0.38 if _paused else (0.70 if _reading else 1.0)
	_duck = move_toward(_duck, target, maxf(delta, 0.0) * 1.8)
	AudioServer.set_bus_volume_linear(AudioServer.get_bus_index("MusicMix"), _duck)
	AudioServer.set_bus_volume_linear(AudioServer.get_bus_index("AmbienceMix"), 0.42 if _paused else (0.65 if _reading and not _narrative_active else 1.0))

func _record(event_id: String, detail: Dictionary) -> void:
	var record := {"event": event_id, "time_ms": Time.get_ticks_msec()}
	record.merge(detail)
	trace.append(record)
	if trace.size() > TRACE_LIMIT:
		trace.pop_front()
	event_played.emit(event_id, record)

func _exit_tree() -> void:
	stop_all()

func stop_all() -> void:
	for tween: Tween in _layer_tweens.values():
		if is_instance_valid(tween):
			tween.kill()
	for player in _players:
		player.stop()
		player.stream = null
	for pair: Array in _layers.values():
		for player: AudioStreamPlayer in pair:
			player.stop()
			player.stream = null
	_streams.clear()
	_layer_tweens.clear()
	_layer_events = {"music": "", "ambience": "", "movement": ""}
	_initialized_context = false

func debug_snapshot() -> Dictionary:
	var active := 0
	for player in _players:
		if player.playing:
			active += 1
	return {"driver": AudioServer.get_driver_name(), "events": catalog.size(), "active_voices": active, "layers": _layer_events.duplicate(), "trace": trace.duplicate(true), "world_suspended": world_suspended}

func _schedule_ui_binding(node: Node) -> void:
	_bind_control_ref.call_deferred(weakref(node))

func _bind_control_ref(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node
	if is_instance_valid(node):
		_bind_control(node)

func _bind_tree(node: Node) -> void:
	_bind_control(node)
	for child in node.get_children():
		_bind_tree(child)

func _bind_control(node: Node) -> void:
	if not is_instance_valid(node) or node.has_meta("audio_bound"):
		return
	node.set_meta("audio_bound", true)
	if node is BaseButton:
		node.mouse_entered.connect(_ui_hover.bind(node))
		node.focus_entered.connect(_ui_focus.bind(node))
		node.pressed.connect(_ui_pressed.bind(node))
		if node is OptionButton:
			node.item_selected.connect(func(_index: int): play_event("ui.select"))
	elif node is Slider:
		node.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton or event is InputEventKey or event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				node.set_meta("audio_input_ms", Time.get_ticks_msec())
		)
		node.value_changed.connect(func(_value: float):
			if node.is_visible_in_tree() and Time.get_ticks_msec() - int(node.get_meta("audio_input_ms", -10000)) < 150:
				play_event("ui.slider")
		)

func _ui_hover(button: BaseButton) -> void:
	if is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled:
		play_event("ui.hover")

func _ui_focus(button: BaseButton) -> void:
	# Programmatic focus during panel opening stays quiet; keyboard navigation speaks.
	if Input.is_physical_key_pressed(KEY_TAB) or Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_DOWN):
		_ui_hover(button)

func _ui_pressed(button: BaseButton) -> void:
	if not is_instance_valid(button) or _last_ui_action_frame == Engine.get_process_frames():
		return
	var event_id := String(button.get_meta("audio_event", ""))
	if button.has_meta("audio_event") and event_id.is_empty():
		return
	if event_id.is_empty():
		event_id = "ui.popup_open" if button is OptionButton else ("ui.toggle" if button.toggle_mode else "ui.press")
	play_event(event_id)


func set_narrative_soundscape(environment: String, music: String = "") -> void:
	if environment == "inherit":
		environment = _narrative_environment
	if music == "inherit":
		music = _narrative_music
	if music == "silence":
		music = ""
	if _narrative_active and _narrative_environment == environment and _narrative_music == music:
		return
	_narrative_active = true
	_narrative_environment = environment
	_narrative_music = music
	_refresh_layers()

func clear_narrative_soundscape() -> void:
	_narrative_active = false
	_narrative_environment = ""
	_narrative_music = ""
	_refresh_layers()


func set_movement(event_id: String) -> void:
	if _movement_event == event_id:
		return
	_movement_event = event_id
	_crossfade("movement", "" if world_suspended else event_id, 0.25)


func stop_events(event_ids: Array, fade_seconds: float = 0.06) -> void:
	for player in _players:
		var event_id := String(player.get_meta("event_id", ""))
		if not player.playing or event_id not in event_ids:
			continue
		var sequence := int(player.get_meta("sequence", -1))
		var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_method(_fade_voice.bind(weakref(player), event_id, sequence), player.volume_linear, 0.0, fade_seconds)
		tween.tween_callback(_stop_voice.bind(weakref(player), event_id, sequence))
	_record("narrative.stop_motion", {"events": event_ids, "fade_seconds": fade_seconds})

func _fade_voice(value: float, reference: WeakRef, event_id: String, sequence: int) -> void:
	var player := reference.get_ref() as AudioStreamPlayer
	if player != null and player.get_meta("event_id", "") == event_id and int(player.get_meta("sequence", -2)) == sequence:
		player.volume_linear = value

func _stop_voice(reference: WeakRef, event_id: String, sequence: int) -> void:
	var player := reference.get_ref() as AudioStreamPlayer
	if player != null and player.get_meta("event_id", "") == event_id and int(player.get_meta("sequence", -2)) == sequence:
		player.stop()


func cancel_narrative_voices() -> void:
	for player in _players:
		if player.get_meta("category_bus", "") == "Narrative":
			player.stop()
			player.stream = null
			player.stream_paused = false
	set_movement("")
