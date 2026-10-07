extends SceneTree

var failures := 0
var checks := 0
var audio: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _count_event(id: String) -> int:
	var count := 0
	for entry: Dictionary in audio.trace:
		if entry.event == id:
			count += 1
	return count

func _run() -> void:
	await process_frame
	audio = root.get_node("GameAudio")
	_check(audio.catalog.size() >= 50, "central catalog contains complete current event coverage")
	for bus_name: String in ["Music", "SFX", "UI", "Cards", "World", "Ambience", "MusicMix", "AmbienceMix", "Cinematic"]:
		_check(AudioServer.get_bus_index(bus_name) >= 0, "bus exists: " + bus_name)
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index("Cards")) == &"SFX", "card effects respect existing SFX slider")
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index("Cinematic")) == &"Music", "native movie respects Music slider")
	for id: String in audio.catalog:
		var spec: Dictionary = audio.catalog[id]
		for path: String in spec.files:
			_check(audio._stream(path, spec.loop) != null, "loadable " + id + ": " + path.get_file())
	audio.set_context(false, false, false, 0.2)
	_check(audio._layer_events.music == "music.day" and audio._layer_events.ambience == "ambience.day", "day soundscape selected")
	var count: int = audio.trace.size()
	audio.set_context(false, false, false, 0.2)
	_check(audio.trace.size() == count, "unchanged context does not restart loops")
	_check(audio.play_event("card.pick"), "card pickup accepted")
	_check(not audio.play_event("card.pick"), "cooldown prevents duplicate pickup in same frame")
	_check(not audio.play_event("missing.event"), "unknown event safely ignored")
	_check(not audio.play_event("music.day"), "one-shot API cannot accidentally create looping music voices")
	audio.set_context(false, true, false, 0.2)
	_check(not audio.play_event("card.drop"), "paused gameplay sound suppressed")
	_check(audio.play_event("ui.press"), "UI stays audible during pause")
	await create_timer(0.5).timeout
	_check(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("MusicMix")) < 0.5, "pause ducks music without modifying Music preference")
	audio.set_context(false, false, false, 0.9)
	_check(audio._layer_events.music == "music.night" and audio._layer_events.ambience == "ambience.night", "night crossfade selected")
	# Repeated and reversed transitions must remain bounded, without stale stop callbacks.
	for index in 12:
		audio.set_context(index % 2 == 0, false, false, float(index % 2))
		await process_frame
	audio.set_context(false, false, true, 0.2)
	_check(audio._layer_events.music == "", "unmapped pursuit/reading defaults to musical silence")
	audio.set_cinematic(true, true)
	_check(audio._layer_events.music == "" and audio._layer_events.ambience == "", "native movie owns soundtrack; game layers fade out")
	await create_timer(2.6).timeout
	var loop_count := 0
	for pair: Array in audio._layers.values():
		for player: AudioStreamPlayer in pair:
			if player.playing:
				loop_count += 1
	_check(loop_count == 0, "cinematic fade stops both outgoing layers")
	audio.set_cinematic(false)
	audio.set_context(false, false, false, 0.2)
	await create_timer(2.6).timeout
	loop_count = 0
	for pair: Array in audio._layers.values():
		for player: AudioStreamPlayer in pair:
			if player.playing:
				loop_count += 1
	_check(loop_count == 2, "exactly one music and one ambience voice survive rapid transitions")
	var button := Button.new()
	button.position = Vector2(40, 40)
	button.size = Vector2(180, 60)
	button.text = "Audio test"
	root.add_child(button)
	await process_frame
	audio._bind_control(button)
	var before := _count_event("ui.press")
	button.pressed.emit()
	_check(_count_event("ui.press") == before + 1, "binding is idempotent: one sound per button activation")
	var settings := GameSettings.new("res://work/audio-qa/settings.cfg")
	settings.apply_all()
	_check(settings.preview_volume("music_volume", 0.0), "music zero preview accepted")
	_check(is_zero_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Music"))), "music slider can fully mute BGM and film")
	_check(settings.preview_volume("sfx_volume", 0.0), "SFX zero preview accepted")
	_check(is_zero_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("SFX"))), "SFX slider can fully mute UI, card, world, ambience")
	settings.apply_all()
	var data: Dictionary = audio.debug_snapshot()
	_check(data.active_voices <= 24, "voice pool bounded")
	var report := {"checks": checks, "failures": failures, "audio": data}
	var file := FileAccess.open("res://work/audio-qa/service-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	audio.stop_all()
	button.queue_free()
	await create_timer(0.2).timeout
	print("AUDIO_SERVICE_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
