extends SceneTree
var failures := 0
var checks := 0
var app: Node
var audio: Node

func _initialize() -> void:
	_run.call_deferred()
func _check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func _count(id: String) -> int:
	var n := 0
	for entry: Dictionary in audio.trace:
		if entry.event == id: n += 1
	return n
func _run() -> void:
	app = load("res://scenes/table.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	audio = root.get_node("GameAudio")
	app.autosave_enabled = false
	_check(is_instance_valid(app.main_menu), "full game creates its main menu")
	_check(audio._layer_events.music == "music.menu", "game main menu selects menu music")
	_check(app._commit_new_journey("Audio QA"), "actual new journey saves latest opening in isolated QA profile")
	var film = app.opening_overlay._film
	_check(film.is_showing() and film._player.bus == "Cinematic" and film._player.stream != null, "actual opening film keeps native stream on Cinematic bus")
	_check(audio._cinematic and audio._cinematic_native and audio._layer_events.music == "" and audio._layer_events.ambience == "", "actual native film suppresses additional BGM and ambience")
	_check(app.save_game("slot_1", false).ok, "actual latest new-game snapshot saves")
	_check(app.load_game("slot_1").ok, "actual latest snapshot reloads")
	_check(not audio.narrative.restoring and audio.narrative.pending.is_empty(), "reload completes audio restore without queued narrative one-shots")
	app.opening_overlay.hide_all()
	app.dialogue_overlay.sync()
	# Use actual domain state and real gesture handlers, keeping all writes in test profile.
	app._at_main_menu = false
	app._menu_paused = false
	app.opening.stage = &"inactive"
	app.dialogue.cancel()
	app._has_session = true
	app._scene_view_initialized = true
	app.table_stage.set_menu_view(false, true)
	app._apply_pause_state()
	paused = false
	audio.set_context(false, false, false, 0.2)
	var state := TableState.new()
	state.seed()
	if state.cards.is_empty():
		state.create_typed(&"hero", Vector2(0, 0))
		state.create_typed(&"first_forest", Vector2(300, 0))
	app.shop.state = state
	app.board.replace_state(state)
	await process_frame
	var card: String = state.cards.keys()[0]
	var stack: String = state.stack_for(card)
	app.board.pressed_id = card
	app.board.selected_id = card
	app.board.press_at = app.board.camera.to_screen(state.card_position(card))
	app.board.pressed_snapshot = state.stacks[stack].duplicate(true)
	app.board._start_drag()
	_check(_count("card.pick") + _count("card.split") > 0, "real card drag emits pickup/split")
	app.board.cancel_gesture()
	_check(_count("card.cancel") > 0 and app.board.dragging_id.is_empty(), "cancel gesture restores stack and emits one return")
	var before := _count("card.cancel")
	app.board.cancel_gesture()
	_check(_count("card.cancel") == before, "idle cancel is silent")
	app.set_game_paused(true)
	_check(audio.world_suspended and _count("ui.pause") > 0, "actual pause opens UI sound and suspends world audio")
	app.overlay.open_page("settings")
	await process_frame
	app.overlay.settings_panel.select_category("audio")
	_check(is_instance_valid(app.overlay.settings_panel.volume_sliders.music_volume), "existing in-game audio sliders still present")
	app.set_game_paused(false)
	app.table_stage.set_menu_view(false, true)
	app._apply_pause_state()
	app.journal._root.show()
	app.journal.toggle("recipes")
	_check(_count("book.open") > 0, "actual journal reveal has book sound")
	app.journal.close()
	_check(_count("book.close") > 0, "actual journal close has book sound")
	app._has_session = false
	app.autosave_enabled = false
	var out := FileAccess.open("res://work/audio-qa/gameplay-report.json", FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks": checks, "failures": failures, "trace": audio.trace}, "\t"))
	out.close()
	app.queue_free()
	await process_frame
	await process_frame
	audio.stop_all()
	await create_timer(0.2).timeout
	print("AUDIO_GAMEPLAY_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
