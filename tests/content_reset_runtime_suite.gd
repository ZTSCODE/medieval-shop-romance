extends SceneTree

class ResetApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

var app: Node
var output_dir := "res://outputs/content-reset-20260924"
var results: Array[Dictionary] = []
var metrics: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if "--flow-qa" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("A rendered run with isolated --flow-qa is required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	app = ResetApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	app.board.sound.enabled = false
	root.size = Vector2i(1600, 900)
	await _wait(1.0)
	_check("isolated profile", app.qa_mode and app.save_store.directory.replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://work/").replace("\\", "/")))
	_check("empty content catalog", ContentCatalog.card_ids().is_empty() and ContentCatalog.recipe_ids().is_empty() and ContentCatalog.npc_ids().is_empty())
	_check("main menu boots without session", app._at_main_menu and app.main_menu.visible and not app._has_session)
	await _shot("01-main-menu.png")
	app.main_menu.buttons.new.pressed.emit()
	await _wait(0.1)
	_check("new journey asks for name", app.name_entry.visible)
	app.name_entry.name_input.text = "Reset Test"
	app.name_entry.name_input.text_changed.emit("Reset Test")
	app.name_entry.confirm_button.pressed.emit()
	await _wait(1.5)
	_check("new empty journey starts", app._has_session and not app._at_main_menu and not app._menu_paused)
	_check("content remains empty", app.board.state.card_count() == 0 and app.progress.discovered_recipes.is_empty() and app.progress.npcs.is_empty())
	_check("old opening and dialogue remain inactive", app.opening.stage == &"inactive" and not app.dialogue.is_active() and not app.opening_overlay.intro_visible)
	_check("name persists without a hero card", app.identity.name == "Reset Test")
	_check("empty table is structurally valid", app.board.state.validate().is_empty())
	var running_elapsed: float = app.day_cycle.elapsed
	await _wait(0.2)
	_check("empty world still advances its clock", app.day_cycle.elapsed > running_elapsed)
	app.set_time_paused(true)
	var stopped_elapsed: float = app.day_cycle.elapsed
	await _wait(0.2)
	_check("time control pauses empty world", app._time_paused and app.day_cycle.elapsed == stopped_elapsed)
	app.set_time_paused(false)
	app.set_game_speed(3.0)
	_check("empty world supports game speed", app._game_speed == 3.0)
	app.set_game_speed(1.0)
	await _shot("02-empty-table.png")
	for page: String in ["recipes", "npcs"]:
		app._toggle_journal(page)
		await _wait(0.3)
		var panel: JournalPanel = app.journal.recipes_panel if page == "recipes" else app.journal.npcs_panel
		_check(page + " empty page opens", app.journal.current_page == page and app.journal.panel.visible and panel.entry_controls.is_empty() and panel._details.get_node_or_null("JournalEmpty") != null)
		await _shot("03-empty-" + page + ".png")
		app.journal.close()
	app.set_game_paused(true)
	await _wait(0.2)
	var paused_elapsed: float = app.day_cycle.elapsed
	await _wait(0.2)
	_check("pause freezes time", paused and app.day_cycle.elapsed == paused_elapsed)
	app.overlay.open_page("settings")
	await _wait(0.3)
	_check("settings open while paused", app.overlay.current_page == "settings" and app._menu_paused)
	await _shot("04-paused-settings.png")
	app.overlay.back_button.pressed.emit()
	_check("settings return to pause menu", app.overlay.current_page == "main" and app._menu_paused)
	var saved: Dictionary = app.save_game("slot_1", false)
	_check("empty session saves", saved.get("ok", false))
	app.day_cycle.elapsed = 99.0
	var loaded: Dictionary = app.load_game("slot_1")
	_check("empty session reloads", loaded.get("ok", false) and app.board.state.card_count() == 0 and app.identity.name == "Reset Test" and is_equal_approx(app.day_cycle.elapsed, paused_elapsed))
	var async_save: Dictionary = app._begin_async_save("slot_2", false)
	_check("empty save uses a background thread", async_save.get("ok", false) and app._storage_thread != null)
	var storage_deadline := Time.get_ticks_msec() + 10000
	while app._storage_thread != null and Time.get_ticks_msec() < storage_deadline:
		await process_frame
	_check("background save completes", app._storage_thread == null)
	var async_record: Dictionary = app.save_store.read_save("slot_2")
	_check("background save preserves content generation", async_record.get("ok", false) and async_record.get("payload", {}).get("content_generation") == ContentCatalog.content_generation() and async_record.get("payload", {}).get("identity", {}).get("name") == "Reset Test")
	app._return_main_menu()
	await _wait(1.5)
	_check("return to main menu preserves session", app._at_main_menu and app.main_menu.visible and app._has_session)
	var menu_elapsed: float = app.day_cycle.elapsed
	await _wait(0.2)
	_check("main menu freezes time", app.day_cycle.elapsed == menu_elapsed)
	app._continue_journey()
	await _wait(1.5)
	_check("continue restores empty journey", not app._at_main_menu and not app._menu_paused and app.board.state.card_count() == 0 and app.identity.name == "Reset Test")
	await _measure_zoom()
	await _shot("05-zoom-final.png")
	app.set_game_speed(3.0)
	app.set_time_paused(true)
	_check("new journey reset starts from paused triple speed", app._time_paused and app._game_speed == 3.0 and app.board.simulation_paused)
	var restarted: bool = app._commit_new_journey("Reset Again")
	await _wait(0.3)
	_check("new journey resets simulation controls", restarted and not app._time_paused and not app._menu_paused and app._game_speed == 1.0 and not app.board.simulation_paused and app.board.simulation_speed == 1.0)
	_check("new journey keeps empty content", app.identity.name == "Reset Again" and app.board.state.card_count() == 0)
	await _shot("06-new-journey-reset.png")
	var failures := 0
	for result: Dictionary in results:
		if not result.ok:
			failures += 1
	var file := FileAccess.open(output_dir.path_join("runtime-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": results.size(), "failures": failures, "results": results, "zoom": metrics, "renderer": RenderingServer.get_current_rendering_method()}, "\t"))
	file.close()
	print("CONTENT_RESET_RUNTIME: %d checks, %d failures" % [results.size(), failures])
	quit(0 if failures == 0 else 1)


func _measure_zoom() -> void:
	var previous: Vector2i = app.table_stage.card_canvas.size
	var reallocations := 0
	var samples: Array[float] = []
	var last := Time.get_ticks_usec()
	for frame in 240:
		if frame % 8 == 0:
			app.board.camera.zoom_at(root.get_visible_rect().get_center(), 1.12 if frame < 120 else 1.0 / 1.12)
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - last) / 1000.0)
		last = now
		var current: Vector2i = app.table_stage.card_canvas.size
		if current != previous:
			reallocations += 1
		previous = current
	samples.sort()
	metrics = {"frames": samples.size(), "texture_reallocations": reallocations, "median_ms": samples[120], "p95_ms": samples[228], "max_ms": samples[-1]}
	_check("zoom preserves allocated card framebuffer", reallocations == 0)


func _check(label: String, ok: bool) -> void:
	results.append({"label": label, "ok": ok})
	print(("PASS " if ok else "FAIL ") + label)


func _wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout


func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check("capture " + filename, image != null and image.save_png(output_dir.path_join(filename)) == OK)
