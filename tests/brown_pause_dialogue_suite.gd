extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	root.size = Vector2i(1600, 900)
	var overlay := SessionOverlay.new()
	root.add_child(overlay)
	overlay.set_paused(true)
	await process_frame
	await process_frame
	_check("main pause uses tall panel", overlay._window.size.y >= 600)
	_check("five main actions remain", overlay._pause_center.get_child(0).get_child_count() == 5)
	_check("pause close sits at right", overlay._window.close_button.position.x > overlay._window.title_label.position.x)
	_check("title tab above panel", overlay._pause_tab.position.y < overlay._window.position.y)
	_check("full scene dim is 45 percent", is_equal_approx(overlay.pause_root.get_node("PauseSceneDim").color.a, 0.45))
	var dialogue := DialogueOverlay.new()
	root.add_child(dialogue)
	dialogue._presentation = 1
	dialogue._layout()
	_check("dialogue uses the wider bottom paper band", dialogue.text_panel.size.x >= 950 and dialogue.text_panel.position.y > 650)
	_check("speaker tab projects above paper", dialogue._speaker_tab.position.y < dialogue.text_panel.position.y)
	_check("portraits rest on the upper paper edge", dialogue._stage.position.y < dialogue.text_panel.position.y and dialogue._stage.get_rect().end.y < dialogue.text_panel.position.y + 20)
	dialogue._hero_speaking = true
	dialogue._layout()
	_check("hero speaker layered in front", dialogue.hero_portrait.z_index > dialogue.npc_portrait.z_index)
	dialogue._hero_speaking = false
	dialogue._layout()
	_check("NPC speaker layered in front", dialogue.npc_portrait.z_index > dialogue.hero_portrait.z_index)
	print("Brown UI checks: %d, failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
