extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, result: bool) -> void:
	checks += 1
	if not result:
		failures += 1
	print(("PASS " if result else "FAIL ") + label)

func _wait() -> void:
	await create_timer(0.25, true).timeout

func _shot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work/menu-reference-20260922"))
	root.get_texture().get_image().save_png("res://work/menu-reference-20260922/" + filename)

func _run() -> void:
	root.size = Vector2i(1672, 941)
	TranslationServer.set_locale("zh_CN")
	var menu := MainMenu.new()
	root.add_child(menu)
	menu.set_continue_available(true)
	menu.set_active(true)
	await create_timer(0.45, true).timeout
	_check("default keyboard selection shows olive paper", menu.buttons["continue"]._selection > 0.99)
	_check("default keyboard selection shows red leaf", menu.buttons["continue"]._leaf.modulate.a > 0.99)
	await _shot("01-main-selected.png")
	menu.buttons["settings"].grab_focus()
	await _wait()
	_check("keyboard selection transfers paper and leaf", menu.buttons["settings"]._selection > 0.99 and menu.buttons["continue"]._selection < 0.01)
	menu.buttons["new"].mouse_entered.emit()
	await _wait()
	_check("pointer selection transfers focus", menu.buttons["new"].has_focus() and menu.buttons["new"]._selection > 0.99)
	menu.buttons["new"].mouse_exited.emit()
	await _wait()
	_check("mouse exit preserves keyboard focused selection", menu.buttons["new"]._selection > 0.99)
	menu.set_active(false)
	await create_timer(0.4, true).timeout
	var overlay := SessionOverlay.new()
	root.add_child(overlay)
	overlay.set_hud_visible(false)
	overlay.set_paused(true)
	await create_timer(0.45, true).timeout
	_check("pause resume defaults to olive selected paper", overlay.resume_button._selection > 0.99)
	_check("pause is fixed in place", not overlay._window.draggable)
	_check("pause has five actions", overlay._pause_entries.get_child_count() == 5)
	_check("pause stays centered", overlay._window.get_global_rect().get_center().distance_to(overlay._root.size * 0.5) < 2)
	await _shot("02-pause-selected.png")
	root.size = Vector2i(1280, 720)
	await _wait()
	_check("small viewport encloses pause", overlay._root.get_global_rect().encloses(overlay._window.get_global_rect()))
	_check("small viewport encloses last action", overlay._window.get_global_rect().encloses(overlay.quit_button.get_global_rect()))
	await _shot("03-pause-small.png")
	overlay.open_page("settings")
	await _wait()
	_check("settings workflow remains available", overlay.settings_panel.visible and overlay.back_button.visible)
	overlay.back()
	await _wait()
	_check("return restores selected resume", overlay.current_page == "main" and overlay.resume_button._selection > 0.99)
	print("Menu reference checks: %d, failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
