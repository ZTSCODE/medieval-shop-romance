extends SceneTree

class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

var app: Node
var failures := 0
const OUTPUT := "res://outputs/settings-book-20260929/"

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
	await create_timer(0.4).timeout
	var panel: SettingsPanel = app.overlay.settings_panel
	_check("three categories", panel.category_pages.size() == 3)
	for id: String in ["display", "audio", "language"]:
		_click_control(panel.category_buttons[id])
		await create_timer(0.25).timeout
		_check(id + " selected", panel.current_category == id)
		_check(id + " no vertical overflow", panel.size.y <= app.overlay.page_scroll.size.y + 1)
		for control: Control in panel.category_pages[id].get_children():
			_check(id + " direct control visible", control.is_visible_in_tree())
		for other: String in panel.category_pages:
			_check(id + " visibility " + other, panel.category_pages[other].visible == (other == id))
		await _shot(id + ".png")
	panel.select_category("display")
	await process_frame
	_click_control(panel.window_option)
	await create_timer(0.2).timeout
	_check("window dropdown opens by pointer", panel.window_option.get_popup().visible)
	await _shot("display-options.png")
	panel.window_option.get_popup().hide()
	if "--preview-hold" in OS.get_cmdline_user_args():
		print("Settings book preview ready")
		return
	var isolated := GameSettings.new(OUTPUT + "test-settings.cfg")
	panel.configure(isolated)
	panel.select_category("audio")
	await process_frame
	panel.volume_sliders["master_volume"].value = 43
	_click_control(panel.mute_check._choices[0])
	_check("mute toggles by pointer", panel.mute_check.button_pressed)
	var config := ConfigFile.new()
	_check("saved settings file", config.load(OUTPUT + "test-settings.cfg") == OK)
	_check("volume persists", is_equal_approx(float(config.get_value("settings", "master_volume")), 0.43))
	_check("mute persists", config.get_value("settings", "muted") == true)
	TranslationServer.set_locale("en")
	await create_timer(0.2).timeout
	_check("icon categories have no tooltip", panel.category_buttons["display"].tooltip_text.is_empty())
	_check("icon only categories", panel.category_buttons["display"].text.is_empty())
	_check("HDR disabled on compatibility", panel.hdr_toggle.disabled and not panel.hdr_toggle.button_pressed)
	await _shot("audio-en.png")
	TranslationServer.set_locale("zh_CN")
	panel._return_button.pressed.emit()
	app.overlay._settings_exit.pause()
	app.overlay._settings_exit.custom_step(0.08)
	_check("shade and window fade as one root", app.overlay.pause_root.visible and app.overlay.pause_root.modulate.a > 0.0 and app.overlay.pause_root.modulate.a < 1.0 and is_equal_approx(panel.modulate.a, 1.0))
	app.overlay._settings_exit.play()
	await create_timer(0.25).timeout
	_check("main menu return", app._at_main_menu and not app._menu_paused)
	app._commit_new_journey("UiPreview")
	await create_timer(1.5).timeout
	app.set_game_paused(true)
	app.overlay.open_page("settings")
	await create_timer(0.3).timeout
	panel._return_button.pressed.emit()
	await create_timer(0.3).timeout
	_check("Esc return", app.overlay.current_page == "main" and app._menu_paused)
	app.overlay.open_page("settings")
	root.size = Vector2i(960, 640)
	panel.select_category("audio")
	await create_timer(0.5).timeout
	_check("small window contains book", Rect2(Vector2.ZERO, app.overlay._root.size).encloses(app.overlay._window.get_rect()))
	_check("no horizontal overflow", panel.size.x <= app.overlay.page_scroll.size.x + 1)
	_check("small window no vertical overflow", panel.size.y <= app.overlay.page_scroll.size.y + 1)
	await _shot("small-audio.png")
	print("SETTINGS_BOOK_RUNTIME failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func _click_control(control: Control) -> void:
	var at := control.get_global_transform_with_canvas() * (control.size * 0.5)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.pressed = pressed
		root.push_input(event, true)

func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	_check("capture " + filename, root.get_texture().get_image().save_png(OUTPUT + filename) == OK)
