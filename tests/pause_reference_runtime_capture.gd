extends SceneTree

class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

var app: Node
var failures := 0
const OUTPUT := "res://outputs/pause-ui-20260929/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--flow-qa" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(1672, 941)
	TranslationServer.set_locale("zh_CN")
	app = PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	app.board.sound.enabled = false
	await create_timer(0.7).timeout
	app._commit_new_journey("UI Preview")
	await create_timer(1.8).timeout
	app.set_game_paused(true)
	await create_timer(0.5).timeout
	var ui: SessionOverlay = app.overlay
	_check("isolated preview profile", app.qa_mode)
	_check("five functional actions", ui._pause_entries.get_child_count() == 5)
	_check("reference panel width", absf(ui._window.size.x - 460 * ui._pause_scale) < 4)
	_check("reference panel height", absf(ui._window.size.y - 646 * ui._pause_scale) < 4)
	_check("resume selected", ui.resume_button.has_focus())
	await _shot("01-pause-in-game.png")
	if "--preview-hold" in OS.get_cmdline_user_args():
		print("Pause preview ready")
		return
	var elapsed: float = app.day_cycle.elapsed
	await create_timer(0.2).timeout
	_check("pause freezes simulation", is_equal_approx(elapsed, app.day_cycle.elapsed))
	for page: String in ["settings", "saves"]:
		ui._menu_buttons[page].pressed.emit()
		await create_timer(0.2).timeout
		_check(page + " opens", ui.current_page == page)
		ui.back_button.pressed.emit()
		await process_frame
		_check(page + " returns", ui.current_page == "main")
	ui.new_journey_button.pressed.emit()
	await process_frame
	_check("new journey requires existing confirmation", ui.confirmation_dialog.visible)
	ui.confirmation_dialog.canceled.emit()
	ui.resume_button.pressed.emit()
	await process_frame
	_check("resume closes pause", not app._menu_paused)
	app.set_game_paused(true)
	ui._window.close_button.pressed.emit()
	await process_frame
	_check("close resumes game", not app._menu_paused)
	app.set_game_paused(true)
	root.size = Vector2i(960, 640)
	await create_timer(0.5).timeout
	_check("small window contains panel", Rect2(Vector2.ZERO, ui._root.size).encloses(ui._window.get_rect()))
	await _shot("02-pause-small.png")
	ui.quit_button.pressed.emit()
	await create_timer(1.8).timeout
	_check("return to main menu", app._at_main_menu)
	print("PAUSE_REFERENCE_RUNTIME failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1

func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	_check("capture " + filename, root.get_texture().get_image().save_png(OUTPUT + filename) == OK)
