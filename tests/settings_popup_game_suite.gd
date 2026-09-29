extends SceneTree

class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--flow-qa" not in OS.get_cmdline_user_args():
		quit(2)
		return
	root.size = Vector2i(1672, 941)
	TranslationServer.set_locale("zh_CN")
	var app := PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	await create_timer(1.5).timeout
	app.main_menu.buttons["settings"].pressed.emit()
	await create_timer(0.9).timeout
	var option: OptionButton = app.overlay.settings_panel.resolution_option
	var popup := option.get_popup()
	var failures := 0
	for pixels: Vector2i in [Vector2i(3840, 2160), Vector2i(960, 640), Vector2i(1672, 941)]:
		root.size = pixels
		await create_timer(0.5).timeout
		option.show_popup()
		await create_timer(0.3).timeout
		popup.set_focused_item(1)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/settings-book-20260929/popup-game-%d.png" % pixels.x)
		var paper: Vector2 = popup.get_theme_stylebox("panel").popup_full_size
		var ok := paper.is_equal_approx(popup.get_visible_rect().size) and absf(paper.x - option.size.x) < 3
		print(("PASS " if ok else "FAIL ") + "game popup content and button bounds %d" % pixels.x)
		if not ok:
			failures += 1
		popup.hide()
		await create_timer(0.2).timeout
	print("POPUP_GAME_SUITE failures=%d" % failures)
	if "--preview-hold" in OS.get_cmdline_user_args():
		option.show_popup()
		return
	quit(0 if failures == 0 else 1)
