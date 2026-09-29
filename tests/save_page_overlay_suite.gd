extends SceneTree

class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

var failures := 0
var app: Node

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
	await create_timer(1.5).timeout
	app.main_menu.buttons["settings"].pressed.emit()
	app.overlay.open_page("saves")
	await create_timer(0.85).timeout
	var panel: SaveSlotsPanel = app.overlay.saves_panel
	_check("save page no outer title", not app.overlay._window.title_bar.visible)
	_check("save page fits", panel.size.y <= app.overlay.page_scroll.size.y + 1)
	_check("main menu saves read only", panel.read_only and not panel.slot_controls.slot_1.save_button.visible)
	await _shot("save-page-main-menu.png")
	_click(panel._back)
	app.overlay._settings_exit.pause()
	app.overlay._settings_exit.custom_step(0.08)
	_check("shade fades with paper", app.overlay.pause_root.visible and app.overlay.pause_root.modulate.a > 0 and app.overlay.pause_root.modulate.a < 1)
	app.overlay._settings_exit.play()
	await create_timer(0.2).timeout
	_check("back to menu", not app._menu_paused)
	app._commit_new_journey("SavePreview")
	await create_timer(1.5).timeout
	app.set_game_paused(true)
	app.overlay.open_page("saves")
	await create_timer(0.85).timeout
	_check("journey saving enabled", not panel.read_only and panel.slot_controls.slot_1.save_button.visible)
	await _shot("save-page-journey.png")
	app.overlay._open_confirmation("save", "slot_1")
	await create_timer(0.2).timeout
	_check("overwrite confirmation present", app.overlay.confirmation_dialog.visible)
	await _shot("save-page-confirmation.png")
	_click(app.overlay.confirmation_dialog.get_cancel_button())
	app.overlay._close_confirmation()
	_click(panel._back)
	await create_timer(0.3).timeout
	_check("Esc return", app.overlay.current_page == "main" and app._menu_paused)
	root.size = Vector2i(960, 640)
	app.overlay.open_page("saves")
	await create_timer(0.85).timeout
	_check("small page fits", panel.size.y <= app.overlay.page_scroll.size.y + 1)
	await _shot("save-page-small.png")
	print("SAVE_PAGE_OVERLAY failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/settings-book-20260929/" + filename)

func _click(control: Control) -> void:
	var at := control.get_global_transform_with_canvas() * (control.size * 0.5)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)

func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
