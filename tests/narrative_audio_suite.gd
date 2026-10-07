extends SceneTree
var failures := 0
var checks := 0
var audio: Node
var flow: DialogueFlow
var overlay: DialogueOverlay

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _count(id: String) -> int:
	var count := 0
	for record: Dictionary in audio.trace:
		if record.event == id:
			count += 1
	return count

func _show(index: int, branch: String = "") -> void:
	flow.story_id = "story.messenger.edge"
	flow.active_npc_id = "npc.messenger"
	flow.line_index = index
	flow.branch_choice = branch
	flow.branch_index = 0
	flow.changed.emit()

func _run() -> void:
	await process_frame
	audio = root.get_node("GameAudio")
	TranslationServer.set_locale("zh_CN")
	_check(audio.narrative.entries.size() == 21, "only 21 latest exact prose and marker entries are active")
	for key: String in audio.narrative.entries:
		var spec: Dictionary = audio.narrative.entries[key]
		var parts := String(spec.marker).split(":")
		var definition := ContentCatalog.story_definition(parts[0])
		var line: Dictionary = definition.lines[int(parts[1])]
		if not parts[2].is_empty():
			for choice: Dictionary in line.get("choices", []):
				if choice.id == parts[2]:
					line = choice.lines[int(parts[3])]
		_check(line.text_key == key and tr(key) == spec.quotes.zh_CN, "latest content and locale validate " + key)
		for cue: Dictionary in spec.get("cues", []) + spec.get("stops", []):
			_check(tr(key).contains(String(cue.phrase)), "exact cue phrase exists " + key)
	audio.set_context(false, false, true, 0.0)
	flow = DialogueFlow.new()
	overlay = DialogueOverlay.new()
	root.add_child(overlay)
	overlay.configure(flow)
	_check(flow.start_solo("story.hero.thaw_edge"), "latest new solo scene starts without restoring old narrative")
	_check(audio.narrative.pending.is_empty(), "unmapped solo scene has no invented physical actions")
	flow.cancel()
	_check(flow.start_for_npc("npc.messenger"), "actual latest messenger flow starts")
	await create_timer(1.1).timeout
	_check(_count("narrative.dog_far") == 0, "rewritten first line never plays removed dog bark")
	_show(28)
	await create_timer(0.8).timeout
	_check(_count("narrative.dog_nearer") == 0, "rewritten late line never plays removed nearby dog bark")
	_show(6)
	var before := _count("dialogue.choice")
	overlay._choose("stone")
	_check(flow.branch_choice == "stone" and _count("dialogue.choice") == before + 1, "actual choice preserves latest branch and generic choice sound")
	await create_timer(0.6).timeout
	_check(_count("narrative.stone_pickup") == 0, "changed stone reply does not blindly use obsolete cue")
	_show(19)
	audio.set_context(false, true, true, 0.0)
	overlay.set_menu_paused(true)
	await create_timer(0.6).timeout
	_check(_count("narrative.flask_handover") == 0, "pause freezes phrase timing")
	audio.set_context(false, false, true, 0.0)
	overlay.set_menu_paused(false)
	await create_timer(1.2).timeout
	_check(_count("narrative.flask_handover") == 1, "unchanged latest flask phrase plays once after resume")
	for index in 8:
		overlay.sync()
		overlay._layout()
	await create_timer(0.3).timeout
	_check(_count("narrative.flask_handover") == 1, "UI reflow never replays narrative action")
	AudioEvents.set_restoring(true)
	_show(19)
	AudioEvents.set_restoring(false)
	await create_timer(1.0).timeout
	_check(_count("narrative.flask_handover") == 1 and audio.narrative.pending.is_empty(), "restoring actual line establishes bed without replay")
	audio.narrative.reset()
	var spec: Dictionary = audio.narrative.entries["DLG_MESSENGER_EDGE_19"]
	audio.narrative.enter_line("DLG_MESSENGER_EDGE_19", spec.marker, "changed text")
	_check(audio.narrative.pending.is_empty() and not audio.narrative.line_active, "future text edits reject obsolete cue at runtime")
	audio.narrative.enter_line("DLG_MESSENGER_EDGE_19", "wrong:marker", spec.quotes.zh_CN)
	_check(audio.narrative.pending.is_empty() and not audio.narrative.line_active, "wrong marker rejects cue even if quote matches")
	_check(audio.narrative._phrase_offset({"phrase": "absent", "position": 0.5}, "new line") == -1, "absent phrase has no position fallback")
	audio.narrative.restore_scene([], "complete")
	_check(audio._layer_events.ambience == "ambience.cold_wood" and audio._layer_events.music == "", "latest completed forest stage restores sheltered wood without obsolete rules story")
	audio.set_cinematic(true, true)
	_check(audio._layer_events.music == "" and audio._layer_events.ambience == "", "native film owns soundtrack")
	audio.set_cinematic(false)
	var report := FileAccess.open("res://work/audio-qa/narrative-report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "trace": audio.trace}, "\t"))
	report.close()
	overlay.queue_free()
	audio.stop_all()
	await create_timer(0.25).timeout
	print("NARRATIVE_AUDIO_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
