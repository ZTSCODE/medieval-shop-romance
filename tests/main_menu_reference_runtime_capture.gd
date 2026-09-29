extends SceneTree

class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

var app: Node
var failures := 0
const OUTPUT := "res://outputs/main-menu-ui-20260929/"

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
	await create_timer(2.0).timeout
	var menu: MainMenu = app.main_menu
	_check("isolated main menu", app.qa_mode and app._at_main_menu)
	_check("original title", menu._title.get_theme_stylebox("normal").texture.atlas.resource_path.ends_with("forest_rebuild/menu-title-plaque.png"))
	var expected: Vector2 = menu.buttons["new"].size
	for id: String in ["continue", "new", "settings", "quit"]:
		var button: Button = menu.buttons[id]
		_check(id + " regular aligned bounds", button.visible and button.size.is_equal_approx(expected) and is_equal_approx(button.position.x, menu.buttons["new"].position.x))
	_check("hidden load preserved", not menu.buttons["load"].visible)
	await _shot("01-main-menu.png")
	if "--preview-hold" in OS.get_cmdline_user_args():
		print("Main menu preview ready")
		return
	menu.buttons["settings"].pressed.emit()
	await create_timer(0.3).timeout
	_check("settings opens", app.overlay.current_page == "settings")
	app.overlay._window.close_button.pressed.emit()
	await create_timer(0.3).timeout
	_check("settings closes", not app._menu_paused)
	menu.buttons["new"].pressed.emit()
	await create_timer(0.3).timeout
	_check("new journey opens naming", app.name_entry.visible)
	app.name_entry.canceled.emit()
	await create_timer(0.3).timeout
	_check("naming cancel returns", not app.name_entry.visible and app._at_main_menu)
	root.size = Vector2i(960, 640)
	await create_timer(0.5).timeout
	_check("small window fits", Rect2(Vector2.ZERO, menu._root.size).encloses(menu.panel.get_rect()))
	await _shot("02-main-menu-small.png")
	print("MAIN_MENU_REFERENCE_RUNTIME failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1

func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	_check("capture " + filename, root.get_texture().get_image().save_png(OUTPUT + filename) == OK)
